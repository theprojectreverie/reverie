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
import {readVerifiedOpeningProgress,TUTORIAL_GROUP,VILLAGE_GROUP} from "../src/world/story-progression-proof.ts";
import {settleStoryVictory} from "../src/world/story-battle-rewards.ts";
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.ready();
 const a=await create(0),b=await create(1);
 const progress=id=>transaction(db=>readVerifiedOpeningProgress(db,id));
 const initial={tutorialComplete:false,geraldDefeated:false,next:TUTORIAL_GROUP};
 assert.deepEqual(await progress(a),initial);
 await pool.query("INSERT INTO story_milestone_reaches(player_id,milestone_id) VALUES($1,'village'),($1,'royal_gardens') ON CONFLICT DO NOTHING",[a]);
 assert.deepEqual(await progress(a),initial);
 const forged=await pool.query("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,status,finished_at) VALUES($1,$2,ARRAY['kael'],'victory',now()) RETURNING id",[a,TUTORIAL_GROUP]);
 assert.deepEqual(await progress(a),initial);
 await pool.query("DELETE FROM story_battle_sessions WHERE id=$1",[forged.rows[0].id]);
 // QA-only max-level fixture isolates security and reward checks from balancing.
 await pool.query("INSERT INTO owned_characters(player_id,char_id,level,ascension,awakening) VALUES($1,'kael',80,3,5) ON CONFLICT(player_id,char_id) DO UPDATE SET level=80,ascension=3,awakening=5",[a]);
 const retreat=await start(a,TUTORIAL_GROUP);assert.ok(retreat.ok);assert.ok((await transaction(db=>abandonStoryBattle(db,a,retreat.battleId))).ok);
 assert.deepEqual(await progress(a),initial);
 async function win(group){
  let r=await start(a,group);assert.ok(r.ok,JSON.stringify(r));const bid=r.battleId;
  assert.equal(r.view.units.filter(u=>u.team===0).length,1);
  for(let n=1;n<=20&&r.view.status==="active";n++){
   const actor=r.view.units.find(u=>u.uid===r.view.actorUid),foe=r.view.units.find(u=>u.team===1&&u.hp>0);
   const action={kind:"skill",actorUid:actor.uid,skillId:actor.skills[0],targetUids:[foe.uid]};
   const pair=await Promise.all([act(a,bid,n,action),act(a,bid,n,action)]);assert.ok(pair.every(v=>v.ok),JSON.stringify(pair));assert.deepEqual(pair.map(v=>v.replayed).sort(),[false,true]);r=pair[0];
  }
  assert.equal(r.view.status,"victory");return r;
 }
 const gold=await balance(a,"gold");
 const tutorial=await win(TUTORIAL_GROUP);assert.equal(tutorial.rewards,null);assert.equal(await balance(a,"gold"),gold);
 assert.deepEqual(await progress(a),{tutorialComplete:true,geraldDefeated:false,next:VILLAGE_GROUP});
 assert.deepEqual(await start(a,TUTORIAL_GROUP),{ok:false,reason:"already_claimed"});
 const gerald=await win(VILLAGE_GROUP);assert.ok(gerald.rewards.gold>0);assert.equal(await balance(a,"gold"),gold+gerald.rewards.gold);
 assert.deepEqual(await progress(a),{tutorialComplete:true,geraldDefeated:true,next:"royal_gardens"});assert.deepEqual(await progress(b),initial);
 assert.deepEqual(await start(a,VILLAGE_GROUP),{ok:false,reason:"already_claimed"});
 const duplicate=(await pool.query("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,status,finished_at) VALUES($1,$2,ARRAY['kael'],'victory',now()) RETURNING id",[a,VILLAGE_GROUP])).rows[0].id;
 assert.deepEqual(await transaction(db=>settleStoryVictory(db,a,duplicate)),{ok:false,reason:"already_claimed"});assert.equal(await balance(a,"gold"),gold+gerald.rewards.gold);
 console.log("PASS opening progression: telemetry and incomplete records denied; retreat does not unlock; tutorial victory unlocks Gerald; Gerald victory unlocks gardens; one-time rewards and account isolation");
}finally{
 await app.close();await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();
}
