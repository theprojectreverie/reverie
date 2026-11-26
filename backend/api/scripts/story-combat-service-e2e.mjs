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
 assert.deepEqual(await start(a,"invented_group"),{ok:false,reason:"unknown_encounter"});
 const oldGold=await balance(a,"gold");
 const initial=await start(a,"rose_slime_garden_1");assert.ok(initial.ok,JSON.stringify(initial));assert.equal(initial.view.status,"active");
 assert.equal(initial.view.sequence,0);assert.equal(initial.rewards,null);assert.equal(await balance(a,"gold"),oldGold);
 assert.ok(!("seed" in initial.view)&&!("party" in initial.view));
 assert.deepEqual(await start(a,"rose_slime_garden_1"),{...initial,replayed:true});
 assert.deepEqual(await start(a,"revienna_encounter"),{ok:false,reason:"battle_in_progress"});
 const bid=initial.battleId,actor=initial.view.units.find(u=>u.uid===initial.view.actorUid);
 const target=initial.view.units.find(u=>u.team===1&&u.hp>0);
 const attack={kind:"skill",actorUid:actor.uid,skillId:actor.skills[0],targetUids:[target.uid]};
 assert.deepEqual(await act(b,bid,1,attack),{ok:false,reason:"battle_not_found"});
 assert.deepEqual(await act(a,bid,2,attack),{ok:false,reason:"invalid_sequence"});
 assert.deepEqual(await act(a,bid,1,{...attack,damage:999999}),{ok:false,reason:"invalid_action"});
 assert.deepEqual(await act(a,bid,1,{...attack,actorUid:target.uid}),{ok:false,reason:"wrong_actor"});
 assert.equal((await act(a,bid,1,{...attack,skillId:"ravienna_eclipse"})).reason,"skill_not_equipped");
 assert.equal((await act(a,bid,1,{...attack,targetUids:[actor.uid]})).reason,"invalid_target");
 assert.equal(await balance(a,"gold"),oldGold);
 let current=initial;
 let lastAction;
 for(let n=1;n<=30&&current.view.status==="active";n++){
  const u=current.view.units.find(u=>u.uid===current.view.actorUid);
  const foe=current.view.units.find(u=>u.team===1&&u.hp>0);
  const action={kind:"skill",actorUid:u.uid,skillId:u.skills[0],targetUids:[foe.uid]};
  const next=await act(a,bid,n,action);
  if(!next.ok){
   // A support skill's target rule can differ; safely end turn instead.
   lastAction={kind:"end_turn",actorUid:u.uid};
   current=await act(a,bid,n,lastAction);
  }else{current=next;lastAction=action;}
  assert.ok(current.ok,JSON.stringify(current));
  if(current.view.status==="active")assert.equal(await balance(a,"gold"),oldGold);
 }
 assert.equal(current.view.status,"victory");
 assert.deepEqual(current.rewards,{gold:15,crystals:0,ancient_coins:0,xp:10,items:{glade_sap:1}});
 assert.equal(await balance(a,"gold"),oldGold+15);
 const replay=await act(a,bid,current.view.sequence,lastAction);
 assert.deepEqual(replay,{...current,replayed:true});
 assert.equal(await balance(a,"gold"),oldGold+15);
 const row=(await pool.query("SELECT state FROM story_battle_sessions WHERE id=$1",[bid])).rows[0].state;
 const recheck=await replayStoryCombat("rose_slime_garden_1",{seed:row.seed,party:row.party,collectionCount:row.collectionCount,actions:row.actions});
 assert.deepEqual(recheck,current.view);
 const stock=await pool.query("SELECT quantity::int AS n FROM inventory_items WHERE player_id=$1 AND item_id='glade_sap'",[a]);
 assert.equal(stock.rows[0].n,1);
 const xp=await pool.query("SELECT char_id,xp::int AS xp,bond FROM owned_characters WHERE player_id=$1 ORDER BY char_id",[a]);assert.equal(xp.rows.length,3);assert.ok(xp.rows.every(r=>r.xp===10&&r.bond===2));
 const retreat=await start(a,"rose_slime_garden_2");assert.ok(retreat.ok);
 const guard={kind:"defend",actorUid:retreat.view.actorUid};
 const guarded=await act(a,retreat.battleId,1,guard);
 assert.ok(guarded.ok);assert.ok(guarded.view.events.some(e=>e.type==="defend"));
 const resumed=await transaction(db=>resumeStoryBattle(db,a,retreat.battleId));
 assert.deepEqual(resumed,{...guarded,replayed:true});
 assert.deepEqual(await transaction(db=>abandonStoryBattle(db,b,retreat.battleId)),{ok:false,reason:"battle_not_found"});
 assert.deepEqual(await transaction(db=>abandonStoryBattle(db,a,retreat.battleId)),{ok:true,status:"abandoned",replayed:false});
 assert.deepEqual(await transaction(db=>abandonStoryBattle(db,a,retreat.battleId)),{ok:true,status:"abandoned",replayed:true});
 assert.deepEqual(await act(a,retreat.battleId,1,guard),{ok:false,reason:"battle_finished"});
 assert.equal(await balance(a,"gold"),oldGold+15);
 const fresh=await start(a,"rose_slime_garden_2");assert.ok(fresh.ok&&fresh.battleId!==retreat.battleId);
 assert.deepEqual(await transaction(db=>abandonStoryBattle(db,a,bid)),{ok:false,reason:"battle_finished"});
 console.log("PASS guard, resume persisted state, account isolation, retreat, no abandoned payout, fresh encounter");
 console.log("PASS persisted server-driven combat, strict action ownership/target/sequence checks, exact reward, duplicate replay, deterministic Godot simulation");
}finally{
 await app.close();await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();
}
