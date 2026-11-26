import Fastify from "fastify";
import jwt from "@fastify/jwt";
import assert from "node:assert/strict";
import {randomBytes,randomUUID} from "node:crypto";
import {spawn} from "node:child_process";
import {createServer} from "node:http";
import {fileURLToPath} from "node:url";
import {config} from "../src/config.ts";
import {pool} from "../src/db.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {summonRoutes} from "../src/routes/summon.ts";
import {socialRoutes} from "../src/routes/social.ts";
import {banners} from "../src/world/summon.ts";
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}),name="QaDrop"+randomBytes(4).toString("hex"),email=name.toLowerCase()+"@example.test",password=randomBytes(16).toString("hex");
let proxy, dropped=null;
try{
 await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(authRoutes,{prefix:"/v1/auth"});
 await app.register(summonRoutes,{prefix:"/v1/summon"});
 await app.register(socialRoutes,{prefix:"/v1/social"});
 await app.listen({host:"127.0.0.1",port:0});
 const base="http://127.0.0.1:"+app.server.address().port;
 assert.equal((await app.inject({method:"POST",url:"/v1/auth/register",payload:{playerName:name,email,password}})).statusCode,201);
 const login=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName:name,password}})).json(),id=login.player.id;
 const headers={authorization:"Bearer "+login.accessToken};
 await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'paid_moonstones',12000),($1,'crystals',1200) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=EXCLUDED.balance",[id]);
 const bannerId=Object.keys(banners)[0];
 for(let i=0;i<9;i++)assert.equal((await app.inject({method:"POST",url:"/v1/summon/pull",headers,payload:{bannerId,count:10,currency:"paid_moonstones",requestId:randomUUID()}})).statusCode,200);
 // Test-only proxy forwards the actual request, waits for the committed result,
 // then closes the client connection without sending a response.
 proxy=createServer(async(req,res)=>{
  try{
   const chunks=[];for await(const chunk of req)chunks.push(chunk);
   const body=Buffer.concat(chunks);
   const upstream=await fetch(base+req.url,{method:req.method,headers:{...(req.headers.authorization?{authorization:req.headers.authorization}:{}),...(req.headers["content-type"]?{"content-type":req.headers["content-type"]}:{})},...(body.length?{body}:{})});
   const result=await upstream.text();
   if(req.method==="POST"&&req.url==="/v1/summon/pull"&&!dropped){
    assert.equal(upstream.status,200,result);dropped={payload:JSON.parse(body.toString()),result:JSON.parse(result)};res.destroy();return;
   }
   res.writeHead(upstream.status,{"content-type":"application/json"});res.end(result);
  }catch(e){res.destroy();console.error("Fixture proxy error",e.message);}
 });
 await new Promise(resolve=>proxy.listen(0,"127.0.0.1",resolve));
 const root=fileURLToPath(new URL("../../../",import.meta.url));
 const launch=(stage,url)=>new Promise((resolve,reject)=>{
  const p=spawn(process.env.QA_GODOT,["--headless","--path",root,"res://tools/qa_paid_interrupted.tscn"],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:"1",QA_API:url,QA_NAME:name,QA_PASSWORD:password,QA_INTERRUPTED_STAGE:stage}});
  p.stdout.on("data",d=>process.stdout.write(d));p.stderr.on("data",d=>process.stderr.write(d));
  const timer=setTimeout(()=>p.kill(),45000);p.on("error",reject);p.on("close",code=>{clearTimeout(timer);resolve(code)});
 });
 assert.equal(await launch("drop","http://127.0.0.1:"+proxy.address().port),0);
 assert.ok(dropped);assert.equal(dropped.result.results[9].character_id,banners[bannerId].featured[0]);assert.equal(dropped.result.results[9].paid_guaranteed,true);
 const before=(await app.inject({url:"/v1/summon/state",headers})).json();assert.equal(before.paidTotal,"100");assert.equal(before.currencies.paid_moonstones,"0");
 assert.equal(await launch("recover",base),0);
 const after=(await app.inject({url:"/v1/summon/state",headers})).json();assert.deepEqual(after,before);
 const ledger=await pool.query("SELECT count(*)::int n,sum(delta)::int amount FROM currency_ledger WHERE player_id=$1 AND currency_id='paid_moonstones' AND reason='gacha_pull'",[id]);assert.deepEqual(ledger.rows[0],{n:10,amount:-12000});
 const stored=await pool.query("SELECT count(*)::int n FROM gacha_pulls WHERE player_id=$1 AND idempotency_key=$2",[id,dropped.payload.requestId]);assert.equal(stored.rows[0].n,1);
 console.log("PASS actual dropped response after commit, restart, original request replay, exact debit and unchanged roster/inventory");
}finally{if(proxy){proxy.closeAllConnections();await new Promise(resolve=>proxy.close(resolve));}await app.close();await pool.query("DELETE FROM accounts WHERE email=$1",[email]);await pool.end();}
