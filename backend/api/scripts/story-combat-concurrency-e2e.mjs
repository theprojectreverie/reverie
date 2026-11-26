import assert from "node:assert/strict";
import {randomBytes,randomUUID} from "node:crypto";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {startStoryBattle,actStoryBattle,replayStoryCombat,resumeStoryBattle,abandonStoryBattle} from "../src/world/story-combat-service.ts";
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
const start=(id,group)=>transaction(db=>startStoryBattle(db,id,group));
const act=(id,battle,n,action,rollback=false)=>transaction(db=>actStoryBattle(db,id,battle,n,action),rollback);
const balance=async(id,currency)=>Number((await pool.query("SELECT balance FROM player_currencies WHERE player_id=$1 AND currency_id=$2",[id,currency])).rows[0]?.balance??0);
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.ready();
 const a=await create(0),b=await create(1);
 const oldGold=await balance(a,"gold");
 const starts=await Promise.all([start(a,"rose_slime_garden_1"),start(a,"rose_slime_garden_1")]);
 assert.ok(starts.every(r=>r.ok),JSON.stringify(starts));
 assert.equal(starts[0].battleId,starts[1].battleId);
 assert.deepEqual(starts.map(r=>r.replayed).sort(),[false,true]);
 assert.equal((await pool.query("SELECT count(*)::int AS n FROM story_battle_sessions WHERE player_id=$1 AND status='active'",[a])).rows[0].n,1);
 console.log("PASS concurrent starts create exactly one active battle");
 const initial=starts[0],bid=initial.battleId,guard={kind:"defend",actorUid:initial.view.actorUid};
 const results=await Promise.all([act(a,bid,1,guard),act(a,bid,1,guard)]);
 assert.ok(results.every(r=>r.ok),JSON.stringify(results));
 assert.deepEqual(results.map(r=>r.replayed).sort(),[false,true]);
 assert.deepEqual(results[0].view,results[1].view);
 assert.equal(results[0].view.sequence,1);
 assert.deepEqual(await act(a,bid,1,{kind:"end_turn",actorUid:guard.actorUid}),{ok:false,reason:"invalid_sequence"});
 assert.equal(await balance(a,"gold"),oldGold);
 console.log("PASS simultaneous duplicate action is executed once; conflicting replay is rejected");
 const abandon=await Promise.all([transaction(db=>abandonStoryBattle(db,a,bid)),transaction(db=>abandonStoryBattle(db,a,bid))]);
 assert.ok(abandon.every(r=>r.ok&&r.status==="abandoned"));
 assert.deepEqual(abandon.map(r=>r.replayed).sort(),[false,true]);
 assert.equal(await balance(a,"gold"),oldGold);
 console.log("PASS concurrent retreat is idempotent and never pays rewards");
 for(const group of ["tutorial_fairy_spar","fallen_matron_encounter","elder_hollow","baltoria_encounter","gerald_boss_encounter","cassien_encounter","revienna_encounter"]){
  const r=await start(b,group);assert.ok(r.ok,`${group}: ${JSON.stringify(r)}`);
  assert.equal(r.view.status,"active");assert.ok(r.view.units.some(u=>u.team===1&&u.hp>0));
  assert.ok(r.view.units.some(u=>u.team===0&&u.hp>0));
  if(["tutorial_fairy_spar","gerald_boss_encounter"].includes(group))assert.deepEqual(r.view.units.filter(u=>u.team===0).map(u=>u.charId),["kael"]);
  assert.ok((await transaction(db=>abandonStoryBattle(db,b,r.battleId))).ok);
  console.log(`PASS authoritative encounter initialization: ${group}`);
 }
}finally{
 await app.close();await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();
}
