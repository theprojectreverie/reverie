import assert from "node:assert/strict";
import {randomBytes,randomUUID} from "node:crypto";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {startStoryBattle,actStoryBattle,replayStoryCombat,resumeStoryBattle,abandonStoryBattle,storyTransactionAdmission} from "../src/world/story-combat-service.ts";
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname)&&config.NODE_ENV!=="production");
assert.ok(process.env.REVERIE_STORY_GODOT);
const app=Fastify({logger:false}),emails=[];
const suffix=randomBytes(4).toString("hex");
async function create(i){
 const playerName="CombatQA"+suffix+i,email=playerName.toLowerCase()+"@example.test",password=randomBytes(16).toString("hex");
 emails.push(email);
 assert.equal((await app.inject({method:"POST",url:"/v1/auth/register",payload:{email,playerName,password}})).statusCode,201);
 const login=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName,password}})).json();
 return login.player.id;
}
async function transaction(fn,rollback=false){
 const db=await pool.connect();
 try{await db.query("BEGIN");const result=await fn(db);await db.query(rollback?"ROLLBACK":"COMMIT");return result;}
 catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
}
const start=(id,group)=>storyTransactionAdmission.run(id,db=>startStoryBattle(db,id,group));
const act=(id,battle,n,action)=>storyTransactionAdmission.run(id,db=>actStoryBattle(db,id,battle,n,action));
const balance=async(id,currency)=>Number((await pool.query("SELECT balance FROM player_currencies WHERE player_id=$1 AND currency_id=$2",[id,currency])).rows[0]?.balance??0);
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.ready();
 const ids=[];for(let i=0;i<8;i++)ids.push(await create(i));
 const extra=await create(8);
 const group="rose_slime_garden_1";
 const gold=await Promise.all(ids.map(id=>balance(id,"gold")));
 const started=Date.now();
 const pending=ids.map(id=>start(id,group));
 assert.deepEqual(await start(ids[0],group),{ok:false,reason:"story_player_busy"});
 assert.deepEqual(await start(extra,group),{ok:false,reason:"story_request_busy"});
 const probes=await Promise.all(Array.from({length:4},()=>pool.query("SELECT 1 AS available")));
 assert.ok(probes.every(r=>r.rows[0].available===1));
 console.log("PASS ninth request and duplicate player are rejected before pool checkout; four noncombat queries complete");
 const batch=await Promise.all(pending);
 const accepted=batch.filter(r=>r.ok),busy=batch.filter(r=>!r.ok);
 assert.ok(accepted.length>=1&&accepted.length<=8,JSON.stringify(batch));
 assert.ok(busy.every(r=>r.reason==="story_worker_busy"),JSON.stringify(busy));
 assert.equal(accepted.length,8,"all eight requests should fit the bounded queue");
 const active=(await pool.query("SELECT player_id,id FROM story_battle_sessions WHERE player_id=ANY($1::uuid[]) AND status='active'",[ids])).rows;
 assert.equal(active.length,accepted.length);
 for(let i=0;i<ids.length;i++){
  assert.equal(active.some(r=>r.player_id===ids[i]),batch[i].ok);
  assert.equal(await balance(ids[i],"gold"),gold[i]);
 }
 console.log(`PASS eight simultaneous story starts: ${accepted.length} accepted, ${busy.length} safely rejected as busy, ${Date.now()-started}ms`);
 const battles=[];
 for(let i=0;i<ids.length;i++){
  const result=batch[i].ok?batch[i]:await start(ids[i],group);
  assert.ok(result.ok,JSON.stringify(result));battles.push(result);
 }
 assert.equal(new Set(battles.map(r=>r.battleId)).size,8);
 const retryCount=(await pool.query("SELECT count(*)::int AS n FROM story_battle_sessions WHERE player_id=ANY($1::uuid[]) AND status='active'",[ids])).rows[0].n;
 assert.equal(retryCount,8);
 console.log("PASS eight independent battles persisted without client retries");
 const actions=battles.map(r=>({kind:"defend",actorUid:r.view.actorUid}));
 const acted=await Promise.all(ids.map((id,i)=>act(id,battles[i].battleId,1,actions[i])));
 assert.ok(acted.every(r=>r.ok),JSON.stringify(acted));
 for(let i=0;i<ids.length;i++){
  const saved=await storyTransactionAdmission.run(ids[i],db=>resumeStoryBattle(db,ids[i],battles[i].battleId));assert.ok(saved.ok);
  assert.equal(saved.view.sequence,acted[i].ok?1:0);
  if(!acted[i].ok){const r=await act(ids[i],battles[i].battleId,1,actions[i]);assert.ok(r.ok,JSON.stringify(r));assert.equal(r.view.sequence,1);}
  assert.ok((await storyTransactionAdmission.run(ids[i],db=>abandonStoryBattle(db,ids[i],battles[i].battleId))).ok);
  assert.equal(await balance(ids[i],"gold"),gold[i]);
 }
 console.log("PASS all eight queued actions advance exactly once; all eight retreats are reward-free");
}finally{
 await app.close();await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();
}
