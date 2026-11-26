import assert from "node:assert/strict";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import websocket from "@fastify/websocket";
import {randomBytes,createHash} from "node:crypto";
import {once} from "node:events";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {chatRoutes} from "../src/routes/chat.ts";
import {coopRoutes} from "../src/routes/coop.ts";
import {realtimeRoutes} from "../src/routes/realtime.ts";
import {createGateway} from "./alpha-gameplay-gateway.mjs";
import {installAlphaAccess,alphaRateKey} from "../src/world/alpha-access.ts";
import WebSocket from "ws";
assert.ok(config.NODE_ENV==="development"&&["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}),emails=[],hashes=[],peers=[];let gateway,lobby="";
const hash=s=>createHash("sha256").update(s).digest("hex");
try{
 await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(websocket);
 installAlphaAccess(app);
 await app.register(authRoutes,{prefix:"/v1/auth"});
 await app.register(chatRoutes,{prefix:"/v1/chat"});
 await app.register(coopRoutes,{prefix:"/v1/co-op"});
 await app.register(realtimeRoutes,{prefix:"/v1"});
 await app.listen({host:"127.0.0.1",port:0});
 gateway=createGateway({upstreamPort:app.server.address().port});gateway.listen(0,"127.0.0.1");await once(gateway,"listening");
 const base="http://127.0.0.1:"+gateway.address().port;
 const req=(path,payload,token)=>fetch(base+path,{method:payload===undefined?"GET":"POST",headers:{...(payload===undefined?{}:{"content-type":"application/json"}),...(token?{authorization:"Bearer "+token}:{})},...(payload===undefined?{}:{body:JSON.stringify(payload)})});
 for(const path of ["/developer","/v1/developer/activity","/v1/shop/catalog","/v1/game-servers","/ready","/v1/summon/guarantee-audit"])assert.equal((await req(path)).status,404,path);
 assert.equal((await req("/v1/shop/checkout",{})).status,404);
 assert.equal((await req("/v1/summon/pull",{currency:"paid_moonstones"})).status,403);
 assert.equal((await req("/v1/auth/register",{})).status,403);
 const privateName="PrivateQA"+randomBytes(4).toString("hex"),privateEmail=privateName+"@example.test",privatePassword=randomBytes(16).toString("hex");emails.push(privateEmail);
 const privateReg=await app.inject({method:"POST",url:"/v1/auth/register",payload:{playerName:privateName,email:privateEmail,password:privatePassword}});
 assert.equal(privateReg.statusCode,201);
 const privateLogin=await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName:privateName,password:privatePassword}});
 assert.equal(privateLogin.statusCode,200);
 assert.equal((await req("/v1/auth/login",{playerName:privateName,password:privatePassword})).status,401);
 assert.equal((await req("/v1/auth/refresh",{refreshToken:privateLogin.json().refreshToken})).status,401);
 assert.equal((await req("/v1/auth/wallet",undefined,privateLogin.json().accessToken)).status,403);
 assert.equal(alphaRateKey(app,{headers:{"x-reverie-alpha":"1",authorization:"Bearer "+privateLogin.json().accessToken},ip:"127.0.0.1"}).startsWith("alpha-account:"),true);
 assert.equal(alphaRateKey(app,{headers:{"x-reverie-alpha":"1",authorization:"Bearer invalid"},ip:"127.0.0.1"}),"alpha-anonymous");
 const players=[];
 const sharedEmail="sharedqa"+randomBytes(6).toString("hex")+"@example.test";
 for(let i=0;i<2;i++){
  const name="AlphaQA"+randomBytes(4).toString("hex"),email=sharedEmail,password=randomBytes(4).toString("hex"),code=randomBytes(32).toString("base64url");
  emails.push(email);hashes.push(hash(code));
  await pool.query("INSERT INTO reverie_alpha_invites(token_hash,expires_at) VALUES($1,now()+interval '1 hour')",[hash(code)]);
  const data={playerName:name,email,password,inviteCode:code};
  assert.equal((await req("/v1/auth/register",{...data,inviteCode:randomBytes(32).toString("base64url")})).status,403);
  const register=await req("/v1/auth/register",data);assert.equal(register.status,201,await register.text());
  assert.equal((await req("/v1/auth/register",data)).status,403);
  const login=await req("/v1/auth/login",{playerName:name,password});assert.equal(login.status,200);players.push(await login.json());
 }
 const [a,b]=players;assert.notEqual(a.player.id,b.player.id);
 const refreshed=await req("/v1/auth/refresh",{refreshToken:a.refreshToken});assert.equal(refreshed.status,200);Object.assign(a,await refreshed.json());
 assert.equal((await req("/v1/auth/wallet")).status,401);
 assert.equal((await req("/v1/auth/wallet",undefined,a.accessToken)).status,200);
 const chat=await req("/v1/chat/messages",{channel:"world",text:"Alpha gateway QA"},a.accessToken);assert.equal(chat.status,201,await chat.text());
 assert.ok((await (await req("/v1/chat/messages?channel=world",undefined,b.accessToken)).json()).messages.some(m=>m.playerId===a.player.id));
 const created=await req("/v1/co-op/lobbies",{regionId:"six_zone_willow_fields",maxMembers:4},a.accessToken);assert.equal(created.status,201);const room=await created.json();lobby=room.lobbyId;
 assert.ok((await req("/v1/co-op/lobbies/join",{inviteCode:room.inviteCode},b.accessToken)).status<300);
 for(const player of players){
  const ws=new WebSocket(base.replace("http:","ws:")+"/v1/realtime?lobbyId="+lobby,{headers:{Authorization:"Bearer "+player.accessToken},handshakeTimeout:5000});
  peers.push(ws);await once(ws,"open");
 }
 assert.equal(peers.filter(p=>p.readyState===WebSocket.OPEN).length,2);
 console.log("PASS same-email accounts and 8-character passwords, single-use invites, unauthorized rejection, protected routes, payment isolation, two-player chat and co-op WebSocket handshake");
}finally{
 for(const p of peers)p.terminate();
 if(gateway)await new Promise(r=>gateway.close(r));
 await app.close();
 if(lobby)await pool.query("DELETE FROM co_op_lobbies WHERE id=$1",[lobby]);
 await pool.query("DELETE FROM reverie_alpha_invites WHERE token_hash=ANY($1::text[])",[hashes]);
 await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();
}