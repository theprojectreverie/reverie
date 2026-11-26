import Fastify from "fastify";
import jwt from "@fastify/jwt";
import rateLimit from "@fastify/rate-limit";
import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import WebSocket from "ws";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {gameServerRoutes} from "../src/routes/game-servers.ts";
import {createLocalScaler,planScale,readCapacity} from "./regional-scale-controller.mjs";
assert.ok(config.NODE_ENV!=="production"&&["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const suffix=randomBytes(5).toString("hex"),region="qa_scale_"+suffix,prefix="scale-"+suffix+"-",preferredKey="scale-fixture-"+suffix,emails=[],sockets=[];
const policy={regions:[region],build:"0.1.0-dev",capacity:4,maxPerRegion:1,maxTotal:1,managedPrefix:prefix,threshold:0.8};
const row={server_key:preferredKey,region_id:region,build_version:policy.build,status:"online",fresh:true,endpoint_url:"ws://127.0.0.1:59999",max_players:10,current_players:8};
assert.equal(planScale([{...row,current_players:7}],policy),null);
assert.equal(planScale([{...row,fresh:false}],policy),null);
assert.equal(planScale([row],policy).region,region);
assert.equal(planScale([row,{...row,server_key:prefix+"old",status:"offline"}],policy),null);
assert.equal(planScale([row],{...policy,pending:[{key:prefix+"pending",region}]}),null);
assert.equal(planScale([row,{...row,server_key:"spare",max_players:10,current_players:0}],policy),null);
console.log("PASS scaling threshold, spare capacity, stale region, pending and historical cap");
const app=Fastify({logger:false});let scaler;
const db=await pool.connect();
const wait=async(fn,label)=>{for(let i=0;i<120;i++){const r=await fn();if(r)return r;await new Promise(r=>setTimeout(r,250));}throw Error(label);};
const token=async i=>{
 const email="scale-qa-"+suffix+"-"+i+"@example.test";emails.push(email);
 const a=(await pool.query("INSERT INTO accounts(email,password_hash,email_verified,status) VALUES($1,'disposable-test-no-login',true,'active') RETURNING id,token_version",[email])).rows[0];
 const p=(await pool.query("INSERT INTO players(account_id,name) VALUES($1,$2) RETURNING id",[a.id,"Scale"+suffix+i])).rows[0];
 return {id:p.id,token:app.jwt.sign({sub:a.id,playerId:p.id,tokenVersion:a.token_version})};
};
try{
 const lock=(await db.query("SELECT pg_try_advisory_lock(hashtextextended($1,0)) AS locked",["reverie:local-scaler"])).rows[0];
 assert.ok(lock.locked);
 const contender=(await pool.query("SELECT pg_try_advisory_lock(hashtextextended($1,0)) AS locked",["reverie:local-scaler"])).rows[0];
 assert.equal(contender.locked,false);
 await app.register(rateLimit,{max:100,timeWindow:"1 minute"});await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(gameServerRoutes,{prefix:"/v1/game-servers"});
 const api=await app.listen({host:"127.0.0.1",port:0});
 const preferred=(await pool.query("INSERT INTO game_servers(server_key,display_name,region_id,status,endpoint_url,max_players,build_version,heartbeat_at) VALUES($1,'QA full preferred',$2,'online','ws://127.0.0.1:59999',1,$3,now()) RETURNING id",[preferredKey,region,policy.build])).rows[0].id;
 const owner=await token(0),overflow=await token(1),reserved=await token(2);
 const join=(p,allow)=>app.inject({method:"POST",url:"/v1/game-servers/"+preferred+"/join",headers:{authorization:"Bearer "+p.token},payload:{allowRegionFallback:allow}});
 assert.equal((await join(owner,false)).statusCode,200);
 const options={db,api,bootstrap:config.GAME_SERVER_BOOTSTRAP_SECRET,bin:process.env.REVERIE_GODOT_BIN,policy};
 const dry=createLocalScaler(options);assert.equal((await dry.tick()).status,"dry-run");assert.equal(dry.children.size,0);
 assert.equal((await join(overflow,true)).json().error,"region_full");
 let clock=Date.now();
 scaler=createLocalScaler({...options,execute:true,now:()=>clock,cooldownMs:180000});
 const concurrent=await Promise.all([scaler.tick(),scaler.tick()]);assert.deepEqual(concurrent.map(x=>x.status).sort(),["busy","launched"]);
 const launched=concurrent.find(x=>x.status==="launched");
 const online=await wait(async()=>(await pool.query("SELECT id,region_id,build_version,endpoint_url,max_players FROM game_servers WHERE server_key=$1 AND status='online'",[launched.key])).rows[0],"overflow process did not register");
 assert.equal(online.region_id,region);assert.equal(online.build_version,policy.build);assert.equal(online.max_players,4);
 assert.equal((await scaler.tick()).status,"idle");assert.equal(scaler.children.size,1);
 const result=await join(overflow,true);assert.equal(result.statusCode,200);const assigned=result.json();assert.equal(assigned.serverId,online.id);assert.ok(assigned.redirected);
 const socket=new WebSocket(assigned.endpointUrl);sockets.push(socket);
 const admission=await new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(Error("join timeout")),10000);
  socket.on("error",e=>{clearTimeout(timer);reject(e)});
  socket.on("message",raw=>{const m=JSON.parse(String(raw));if(m.type==="ticket_required")socket.send(JSON.stringify({type:"join_ticket",ticket:assigned.joinTicket,lastEventSequence:0}));else if(m.type==="world_joined"||m.type==="rejected"){clearTimeout(timer);resolve(m)}});
 });
 assert.equal(admission.type,"world_joined");assert.equal(admission.playerId,overflow.id);
 assert.equal((await pool.query("SELECT count(*)::int AS n FROM game_server_player_connections WHERE server_id=$1 AND player_id=$2",[online.id,overflow.id])).rows[0].n,1);
 assert.equal((await pool.query("SELECT server_id FROM game_server_players WHERE player_id=$1",[owner.id])).rows[0].server_id,preferred);
 console.log("PASS dry-run, singleton lock, one actual Godot overflow launch, automatic fallback, live websocket ticket, original assignment preserved");
 const record=scaler.children.get(launched.key);
 const initial=admission.members.find(m=>m.playerId===overflow.id);
 const target={x:Number(initial.x)+3,y:Number(initial.y)+3};
 await new Promise(r=>setTimeout(r,150));
 socket.send(JSON.stringify({type:"position",...target}));
 await wait(async()=>{const p=(await pool.query("SELECT x,y FROM game_server_player_state WHERE server_id=$1 AND player_id=$2",[online.id,overflow.id])).rows[0];return p&&Number(p.x)===target.x&&Number(p.y)===target.y;},"position did not persist");
 // Advance the policy clock without changing database timestamps. An active
 // reservation protects the server even after the idle threshold.
 clock+=700000;
 assert.equal((await scaler.tick()).status,"idle");
 assert.equal(record.child.exitCode,null);
 // Mark the heartbeat stale to exercise warning-only handling for a live process.
 await pool.query("UPDATE game_servers SET heartbeat_at=now()-interval '61 seconds' WHERE id=$1",[online.id]);
 assert.equal((await scaler.tick()).status,"unhealthy");
 assert.equal(record.child.exitCode,null);
 await pool.query("UPDATE game_servers SET heartbeat_at=now() WHERE id=$1",[online.id]);

 // Crash the owned process, not a production or unrelated process.
 const exited=new Promise(resolve=>record.child.once("exit",resolve));record.child.kill("SIGKILL");await exited;
 assert.equal((await scaler.tick()).status,"crashed");
 const offline=(await pool.query("SELECT status,server_secret_hash FROM game_servers WHERE id=$1",[online.id])).rows[0];
 assert.equal(offline.status,"offline");assert.equal(offline.server_secret_hash,null);
 assert.equal((await pool.query("SELECT server_id FROM game_server_players WHERE player_id=$1",[overflow.id])).rows[0].server_id,online.id);
 assert.equal((await scaler.tick()).status,"recovery_cooldown");
 clock+=180001;
 const recovered=await scaler.tick();assert.equal(recovered.status,"restarted");assert.equal(recovered.key,launched.key);assert.equal(recovered.port,launched.port);
 await wait(async()=>Boolean((await pool.query("SELECT 1 FROM game_servers WHERE id=$1 AND status='online' AND server_secret_hash IS NOT NULL",[online.id])).rowCount),"recovery did not register");
 const ticket=await app.inject({method:"POST",url:"/v1/game-servers/"+online.id+"/reconnect",headers:{authorization:"Bearer "+overflow.token},payload:{}});
 assert.equal(ticket.statusCode,200);
 const reconnected=new WebSocket(ticket.json().endpointUrl);sockets.push(reconnected);
 const restored=await new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(Error("reconnect timeout")),10000);
  reconnected.on("error",e=>{clearTimeout(timer);reject(e)});
  reconnected.on("message",raw=>{const m=JSON.parse(String(raw));if(m.type==="ticket_required")reconnected.send(JSON.stringify({type:"join_ticket",ticket:ticket.json().joinTicket,lastEventSequence:0}));else if(m.type==="world_joined"||m.type==="rejected"){clearTimeout(timer);resolve(m)}});
 });
 assert.equal(restored.type,"world_joined");
 const position=restored.members.find(m=>m.playerId===overflow.id);
 assert.equal(Number(position.x),target.x);assert.equal(Number(position.y),target.y);
 console.log("PASS crash fencing, cooldown, same identity recovery, reconnect exact durable coordinates");
 const leave=p=>app.inject({method:"POST",url:"/v1/game-servers/"+p.server+"/leave",headers:{authorization:"Bearer "+p.token},payload:{}});
 reconnected.terminate();
 await wait(async()=>!(await pool.query("SELECT 1 FROM game_server_player_connections WHERE server_id=$1 AND lease_expires_at>now()",[online.id])).rowCount,"lease release");
 assert.equal((await leave({...overflow,server:online.id})).statusCode,200);
 assert.equal((await leave({...owner,server:preferred})).statusCode,200);
 const reservation=await app.inject({method:"POST",url:"/v1/game-servers/"+online.id+"/join",headers:{authorization:"Bearer "+reserved.token},payload:{}});
 assert.equal(reservation.statusCode,200);
 clock+=700000;
 assert.equal((await scaler.tick()).status,"idle");
 assert.equal(scaler.children.get(launched.key).child.exitCode,null);
 assert.equal((await leave({...reserved,server:online.id})).statusCode,200);
 console.log("PASS stale heartbeat reports unhealthy without killing live engine; unredeemed reservation protects idle server");

 // The primary is available, so the empty overflow is safe to retire.
 await pool.query("UPDATE game_servers SET heartbeat_at=now() WHERE id=$1",[preferred]);
 assert.equal((await scaler.tick()).status,"idle");
 clock+=600001;
 const retired=await scaler.tick();assert.equal(retired.status,"retired");
 assert.equal((await pool.query("SELECT status FROM game_servers WHERE id=$1",[online.id])).rows[0].status,"offline");
 assert.equal(scaler.children.get(launched.key).retired,true);
 console.log("PASS occupied server protected, empty overflow safely retired, registry preserved");

}finally{
 for(const socket of sockets)socket.terminate();
 try{await scaler?.stopTestChildren();}finally{
 await app.close();
 await pool.query("DELETE FROM game_servers WHERE server_key=$1 OR left(server_key,length($2))=$2",[preferredKey,prefix]);
 await pool.query("DELETE FROM accounts WHERE email=ANY($1)",[emails]);
 assert.equal((await pool.query("SELECT count(*)::int AS n FROM game_servers WHERE server_key=$1 OR left(server_key,length($2))=$2",[preferredKey,prefix])).rows[0].n,0);
 await db.query("SELECT pg_advisory_unlock(hashtextextended($1,0))",["reverie:local-scaler"]);db.release();await pool.end();
 console.log("PASS owned test processes and fixtures cleaned up");
 }
}
