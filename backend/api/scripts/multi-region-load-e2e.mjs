import Fastify from "fastify";
import jwt from "@fastify/jwt";
import websocket from "@fastify/websocket";
import rateLimit from "@fastify/rate-limit";
import WebSocket from "ws";
import assert from "node:assert/strict";
import {randomBytes,randomUUID} from "node:crypto";
import {spawn} from "node:child_process";
import {createServer,createConnection} from "node:net";
import {fileURLToPath} from "node:url";
import {config} from "../src/config.ts";
import {pool} from "../src/db.ts";
import {gameServerRoutes} from "../src/routes/game-servers.ts";
import {persistentWorldRealtimeRoutes} from "../src/routes/persistent-world-realtime.ts";
import {runMovementLoadProbe} from "./movement-load-probe.mjs";
const N=Number(process.env.REVERIE_E2E_REGION_PLAYERS??32);
assert.ok(Number.isInteger(N)&&N>=2&&N<=50);
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
assert.ok(config.GAME_SERVER_BOOTSTRAP_SECRET);
const suffix=randomBytes(6).toString("hex"),app=Fastify({logger:false}),emails=[],sockets=new Set();
const regions=["castle_royal_gardens","six_zone_willow_fields"].map((region,i)=>({region,key:"multi-region-"+suffix+"-"+i,players:[],clients:[],id:null,child:null,token:null,output:""}));
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const root=fileURLToPath(new URL("../../../",import.meta.url));
const bin=process.env.REVERIE_GODOT_BIN;
assert.ok(bin,"REVERIE_GODOT_BIN required");
const wait=async(fn,label,timeout=20000)=>{const end=Date.now()+timeout;while(Date.now()<end){const v=await fn();if(v)return v;await sleep(100);}throw Error(label);};
const auth=token=>({"content-type":"application/json",authorization:"Bearer "+token});
let base;
const call=async(path,token,body)=>{const response=await fetch(base+"/v1/game-servers"+path,{headers:auth(token),method:body===undefined?"GET":"POST",...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(15000)});return {status:response.status,body:await response.json()};};
const allocatePort=async()=>{const s=createServer();await new Promise((r,j)=>s.once("error",j).listen(0,"127.0.0.1",r));const p=s.address().port;await new Promise(r=>s.close(r));return p;};
async function start(r){
 r.port??=await allocatePort();r.endpoint="ws://127.0.0.1:"+r.port;
 r.child=spawn(bin,["--headless","--path",root,"res://scenes/online/dedicated_world_server.tscn"],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:"1",REVERIE_API_BASE_URL:base,REVERIE_SERVER_BOOTSTRAP_SECRET:config.GAME_SERVER_BOOTSTRAP_SECRET,REVERIE_SERVER_KEY:r.key,REVERIE_SERVER_NAME:"Multi region "+suffix+" "+r.region,REVERIE_SERVER_REGION:r.region,REVERIE_SERVER_HOST:"127.0.0.1",REVERIE_SERVER_PORT:String(r.port),REVERIE_SERVER_MAX_PLAYERS:String(N),REVERIE_SERVER_ENDPOINT:r.endpoint,REVERIE_SERVER_EVENT_BATCH_SIZE:"100",REVERIE_SERVER_INTEREST_RADIUS:"0"},stdio:["ignore","pipe","pipe"]});
 r.child.stdout.on("data",b=>r.output=(r.output+b).slice(-6000));r.child.stderr.on("data",b=>r.output=(r.output+b).slice(-6000));
 const row=await wait(async()=>{if(r.child.exitCode!==null)throw Error(r.output);return (await pool.query("SELECT id FROM game_servers WHERE server_key=$1 AND status='online' AND endpoint_url=$2",[r.key,r.endpoint])).rows[0];},"server registration "+r.region);
 if(r.id)assert.equal(row.id,r.id);r.id=row.id;
}
async function stop(r){
 if(r.child&&r.child.exitCode===null)r.child.kill("SIGKILL");
 if(r.port)await wait(async()=>!(await new Promise(resolve=>{const socket=createConnection({host:"127.0.0.1",port:r.port});socket.once("connect",()=>{socket.destroy();resolve(true);});socket.once("error",()=>resolve(false));socket.setTimeout(250,()=>{socket.destroy();resolve(false);});})),"listener stop");
 r.child=null;
}
async function connect(r,p,ticket){
 const socket=new WebSocket(r.endpoint);sockets.add(socket);socket.once("close",()=>sockets.delete(socket));
 const result=await new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>reject(Error("admission timeout "+r.region)),12000);
  socket.on("error",e=>{clearTimeout(timeout);reject(e);});
  socket.on("message",raw=>{const m=JSON.parse(String(raw));if(m.type==="ticket_required"){assert.equal(m.serverId,r.id);socket.send(JSON.stringify({type:"join_ticket",ticket,lastEventSequence:0}));}else if(m.type==="world_joined"||m.type==="error"||m.type==="rejected"){clearTimeout(timeout);resolve(m);}});
 });
 return {socket,admission:result};
}
async function admit(r,action){
 const tickets=await Promise.all(r.players.map(p=>call("/"+r.id+"/"+action,p.token,{})));
 assert.ok(tickets.every(x=>x.status===200&&x.body.joinTicket));
 r.clients=[];
 for(let i=0;i<N;i+=8){
  const wave=await Promise.all(r.players.slice(i,i+8).map((p,j)=>connect(r,p,tickets[i+j].body.joinTicket)));
  r.clients.push(...wave);
 }
 const own=new Set(r.players.map(p=>p.id));
 assert.ok(r.clients.every((c,i)=>c.admission.type==="world_joined"&&c.admission.playerId===r.players[i].id&&c.admission.members.every(m=>own.has(m.playerId))));
 const snapshot=r.clients.reduce((a,b)=>a.admission.members.length>b.admission.members.length?a:b).admission.members;
 assert.equal(snapshot.length,N);
 return snapshot;
}
const positions=async r=>new Map((await pool.query("SELECT player_id,x,y FROM game_server_player_state WHERE server_id=$1",[r.id])).rows.map(x=>[x.player_id,[Number(x.x),Number(x.y)]]));
const leases=async(r,n)=>wait(async()=>Number((await pool.query("SELECT count(*) FROM game_server_player_connections WHERE server_id=$1 AND lease_expires_at>now()",[r.id])).rows[0].count)===n,"lease count "+r.region);
let crossMessages=0;
function observe(r){
 const allowed=new Set(r.players.map(p=>p.id));
 for(const c of r.clients)c.socket.on("message",raw=>{const m=JSON.parse(String(raw));if(m.playerId&&!allowed.has(m.playerId))crossMessages++;for(const member of m.members??[])if(!allowed.has(member.playerId))crossMessages++;});
}
try{
 await app.register(rateLimit,{max:100,timeWindow:"1 minute"}); await app.register(jwt,{secret:config.JWT_SECRET});await app.register(websocket);
 // Capture credentials only inside this isolated test app, never log or persist them.
 app.addHook("onSend",async(req,reply,payload)=>{if(req.url.endsWith("/register")&&reply.statusCode===201){const r=regions.find(r=>r.key===req.body.serverKey);if(r)r.token=JSON.parse(String(payload)).serverToken;}return payload;});
 await app.register(gameServerRoutes,{prefix:"/v1/game-servers"});await app.register(persistentWorldRealtimeRoutes,{prefix:"/v1"});
 base=await app.listen({host:"127.0.0.1",port:0});
 for(const r of regions)for(let i=0;i<N;i++){
  const email=r.key+"-"+i+"@example.test";emails.push(email);
  const a=(await pool.query("INSERT INTO accounts(email,password_hash,email_verified,status) VALUES($1,'disposable-test-no-login',true,'active') RETURNING id,token_version",[email])).rows[0];
  const p=(await pool.query("INSERT INTO players(account_id,name) VALUES($1,$2) RETURNING id",[a.id,"Multi"+suffix.slice(0,6)+regions.indexOf(r)+i])).rows[0];
  r.players.push({...p,token:app.jwt.sign({sub:a.id,playerId:p.id,tokenVersion:a.token_version})});
 }
 await Promise.all(regions.map(start));assert.notEqual(regions[0].id,regions[1].id);
 const [a,b]=regions;
 const directory=await call("/",a.players[0].token);assert.equal(directory.status,200);
 assert.ok(regions.every(r=>directory.body.servers.some(s=>s.id===r.id&&s.region_id===r.region)));
 await Promise.all(regions.map(r=>admit(r,"join")));await Promise.all(regions.map(r=>leases(r,N)));
 regions.forEach(observe);
 assert.equal((await call("/"+b.id+"/join",a.players[0].token,{})).status,409);
 assert.equal((await call("/"+b.id+"/reconnect",a.players[0].token,{})).status,404);
 assert.equal((await call("/"+b.id+"/events",a.token)).status,403);
 assert.equal((await call("/"+b.id+"/world-state",a.token)).status,403);
 const invalid=await call("/"+a.id+"/events/batch",a.token,{events:[{eventId:randomUUID(),type:"position",playerId:b.players[0].id,payload:{x:20,y:30}}]});
 assert.ok(invalid.status>=400&&invalid.status<500,"foreign player event rejected");
 console.log("PASS two live regions, directory, exclusive assignment and cross-server access rejection");
 // A legitimate extra account cannot reserve a slot in either full region.
 const overflowEmail="multi-overflow-"+suffix+"@example.test";emails.push(overflowEmail);
 const extraAccount=(await pool.query("INSERT INTO accounts(email,password_hash,email_verified,status) VALUES($1,'disposable-test-no-login',true,'active') RETURNING id,token_version",[overflowEmail])).rows[0];
 const extraPlayer=(await pool.query("INSERT INTO players(account_id,name) VALUES($1,$2) RETURNING id",[extraAccount.id,"Overflow"+suffix.slice(0,8)])).rows[0];
 const extraToken=app.jwt.sign({sub:extraAccount.id,playerId:extraPlayer.id,tokenVersion:extraAccount.token_version});
 for(const r of regions){
  const full=await call("/"+r.id+"/join",extraToken,{});
  assert.equal(full.status,409);assert.equal(full.body.error,"server_full");
 }
 assert.equal((await pool.query("SELECT count(*)::int AS n FROM game_server_players WHERE player_id=$1",[extraPlayer.id])).rows[0].n,0);
 assert.equal((await pool.query("SELECT count(*)::int AS n FROM game_server_join_tickets WHERE player_id=$1",[extraPlayer.id])).rows[0].n,0);
 for(let i=0;i<8;i++)assert.equal((await call("/"+a.id+"/join",extraToken,{})).status,409);
 assert.equal((await call("/"+a.id+"/join",extraToken,{})).status,429);
 const independent=await call("/"+a.id+"/join",b.players[0].token,{});
 assert.equal(independent.status,409);assert.equal(independent.body.error,"leave_current_server_first");
 console.log("PASS full-capacity rejection, no orphan reservations and per-account limits");

 await sleep(150);
 await Promise.all(regions.map(r=>runMovementLoadProbe({clients:r.clients,playerRows:r.players,rounds:15,pool,serverId:r.id})));
 assert.equal(crossMessages,0);
 const before=await positions(a);assert.equal(before.size,N);
 const oldToken=a.token;
 a.clients.forEach(c=>c.socket.terminate());await leases(a,0);
 await pool.query("UPDATE game_servers SET status='offline',heartbeat_at=NULL,stopped_at=now() WHERE id=$1",[a.id]);
 // The other region keeps serving movement throughout the restart.
 const ongoing=runMovementLoadProbe({clients:b.clients,playerRows:b.players,rounds:30,pool,serverId:b.id});
 ongoing.catch(()=>{}); // Await below; prevent premature unhandled rejection from bypassing cleanup.
 await stop(a);await start(a);
 assert.notEqual(a.token,oldToken);
 assert.equal((await call("/"+a.id+"/world-state",oldToken)).status,401);
 const restored=await admit(a,"reconnect");
 assert.ok(restored.every(m=>JSON.stringify([Number(m.x),Number(m.y)])===JSON.stringify(before.get(m.playerId))));
 await leases(a,N);observe(a);
 await ongoing;await leases(b,N);
 for(let i=0;i<29;i++){
  const invalid=await call("/"+a.id+"/world-state",randomBytes(48).toString("base64url"));
  assert.equal(invalid.status,401);
 }
 assert.equal((await call("/"+a.id+"/world-state",randomBytes(48).toString("base64url"))).status,429);
 assert.equal((await call("/"+a.id+"/world-state",a.token)).status,200);
 console.log("PASS invalid credential IP quota and valid server quota isolation");
 assert.equal(crossMessages,0);
 for(const r of regions){
  const ids=new Set(r.players.map(p=>p.id));
  assert.ok((await positions(r)).size===N&&[...(await positions(r)).keys()].every(id=>ids.has(id)));
  const events=(await pool.query("SELECT DISTINCT player_id FROM game_server_world_events WHERE server_id=$1 AND player_id IS NOT NULL",[r.id])).rows;
  assert.ok(events.length===N&&events.every(e=>ids.has(e.player_id)));
 }
 console.log("PASS restart one region while the other continues moving, exact coordinates, rotated credentials, event isolation and leases");
 console.log("MULTI_REGION_PASS "+JSON.stringify({regions:2,playersPerRegion:N,totalPlayers:N*2,crossMessages}));
}finally{
 for(const socket of sockets)socket.terminate();
 await Promise.allSettled(regions.map(stop));
 await app.close();
 await pool.query("DELETE FROM game_servers WHERE server_key=ANY($1)",[regions.map(r=>r.key)]);
 await pool.query("DELETE FROM accounts WHERE email=ANY($1)",[emails]);
 const residue=(await pool.query("SELECT (SELECT count(*)::int FROM game_servers WHERE server_key=ANY($1)) AS servers,(SELECT count(*)::int FROM accounts WHERE email=ANY($2)) AS accounts",[regions.map(r=>r.key),emails])).rows[0];
 assert.deepEqual(residue,{servers:0,accounts:0});
 await pool.end();console.log("PASS disposable multi-region fixtures cleaned up");
}
