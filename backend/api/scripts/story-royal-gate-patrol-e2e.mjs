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
import {royalGateStoryPilotRoutes} from "../src/routes/royal-gate-story-pilot.ts";
import {storyReward} from "../src/world/story-battle-rewards.ts";
let server;
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.register(royalGateStoryPilotRoutes,{prefix:"/v1/royal-gate-story"});await app.ready();
 const a=await create(0),b=await create(1);
 const credentials=async id=>{const row=(await pool.query("SELECT a.id,a.token_version FROM accounts a JOIN players p ON p.account_id=a.id WHERE p.id=$1",[id])).rows[0];return app.jwt.sign({sub:row.id,playerId:id,tokenVersion:row.token_version});};
 const ta=await credentials(a),tb=await credentials(b);
 const req=async(payload,token=ta)=>{const r=await app.inject({method:"POST",url:"/v1/royal-gate-story/",headers:{authorization:"Bearer "+token},payload});return {status:r.statusCode,body:r.json()};};
 const g1="royal_gate_patrol_1",g2="royal_gate_patrol_2";
 assert.equal((await req({operation:"status"})).body.reason,"story_progression_required");assert.equal((await req({operation:"start",groupId:"crownling_garden_1"})).status,400);
 for(const group of ["tutorial_fairy_spar","gerald_boss_encounter"])await pool.query("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,status,finished_at,settled_at,rewards,state) VALUES($1,$2,ARRAY['kael'],'victory',now(),CASE WHEN $2='tutorial_fairy_spar' THEN NULL ELSE now() END,CASE WHEN $2='tutorial_fairy_spar' THEN NULL ELSE '{}'::jsonb END,$3::jsonb)",[a,group,JSON.stringify({view:{status:"victory"},actions:[{kind:"skill"}]})]);
 server=(await pool.query("INSERT INTO game_servers(server_key,display_name,region_id,status,heartbeat_at) VALUES($1,'Gate QA','story_royal_gate','online',now()) RETURNING id",["gate-patrol-qa-"+suffix])).rows[0].id;
 await pool.query("INSERT INTO game_server_players(server_id,player_id) VALUES($1,$2)",[server,a]);await pool.query("INSERT INTO game_server_player_state(server_id,player_id,x,y) VALUES($1,$2,-65,1200)",[server,a]);
 const lease=randomUUID();await pool.query("INSERT INTO game_server_player_connections(connection_id,server_id,player_id,lease_expires_at) VALUES($1,$2,$3,now()+interval '45 seconds')",[lease,server,a]);
 assert.equal((await req({operation:"start",groupId:g1})).body.reason,"encounter_progression_required");await pool.query("INSERT INTO story_elathra_audience(player_id,completed_at) VALUES($1,now())",[a]);assert.equal((await req({operation:"start",groupId:g2})).body.reason,"encounter_out_of_range");
 await pool.query("INSERT INTO owned_characters(player_id,char_id,level,ascension,awakening) SELECT $1,unnest(ARRAY['kael','gerald','lilith']),80,3,5 ON CONFLICT DO NOTHING",[a]);
 const gold=await balance(a,"gold"),crystals=await balance(a,"crystals");const qty=async()=>Number((await pool.query("SELECT quantity FROM inventory_items WHERE player_id=$1 AND item_id='royal_seal'",[a])).rows[0]?.quantity??0);const seal=await qty();let total=0;
 for(const [groupId,x,y,expected] of [[g1,-65,1200,1],[g1,-65,1200,1],[g2,75,1840,2]]){
  await pool.query("UPDATE game_servers SET heartbeat_at=now() WHERE id=$1",[server]);await pool.query("UPDATE game_server_player_connections SET lease_expires_at=now()+interval '45 seconds' WHERE connection_id=$1",[lease]);await pool.query("UPDATE game_server_player_state SET x=$3,y=$4,updated_at=now() WHERE server_id=$1 AND player_id=$2",[server,a,x,y]);
  let r=(await req({operation:"start",groupId})).body;assert.ok(r.ok,JSON.stringify(r));const battleId=r.battleId;assert.equal((await req({operation:"resume",groupId,battleId},tb)).status,404);
  for(let sequence=1;sequence<=20&&r.view.status==="active";sequence++){
   const actor=r.view.units.find(u=>u.uid===r.view.actorUid),foe=r.view.units.find(u=>u.team===1&&u.hp>0);const payload={operation:"act",groupId,battleId,sequence,action:{kind:"skill",actorUid:actor.uid,skillId:actor.skills[0],targetUids:[foe.uid]}};
   r=(await req(payload)).body;assert.ok(r.ok,JSON.stringify(r));assert.deepEqual((await req(payload)).body,{...r,replayed:true});
  }
  assert.equal(r.view.status,"victory");assert.equal(r.patrol.progress,expected);assert.equal(r.patrol.willowFieldsUnlocked,expected===2);total+=storyReward(groupId).gold;
  assert.equal(await balance(a,"gold"),gold+total+(expected===2?100:0));assert.equal(await balance(a,"crystals"),crystals+(expected===2?10:0));assert.equal(await qty(),seal+(expected===2?1:0));
  await pool.query("UPDATE story_battle_sessions SET settled_at=now()-interval '16 seconds' WHERE id=$1",[battleId]);console.log("PASS "+groupId+" progress "+expected+"/2");
 }
 const status=(await req({operation:"status"})).body;assert.equal(status.patrol.state,"complete");assert.deepEqual(status.patrol.rewards,{gold:100,crystals:10,xp:60,items:{royal_seal:1}});assert.equal((await req({operation:"status"},tb)).status,409);assert.equal(Number((await pool.query("SELECT count(*) FROM currency_ledger WHERE player_id=$1 AND reason='story_quest_complete'",[a])).rows[0].count),2);
 console.log("PASS distinct Crownlings, duplicate reward prevention, durable Willow Fields proof");
}finally{await app.close();if(server)await pool.query("DELETE FROM game_servers WHERE id=$1",[server]);await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();}
