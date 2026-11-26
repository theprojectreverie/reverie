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
import {geraldStoryPilotRoutes} from "../src/routes/gerald-story-pilot.ts";
const group="gerald_boss_encounter";let server;
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.register(geraldStoryPilotRoutes,{prefix:"/v1/gerald-story"});await app.ready();
 const a=await create(0),b=await create(1);
 const credentials=async id=>{const row=(await pool.query("SELECT a.id,a.token_version FROM accounts a JOIN players p ON p.account_id=a.id WHERE p.id=$1",[id])).rows[0];return app.jwt.sign({sub:row.id,playerId:id,tokenVersion:row.token_version});};
 const ta=await credentials(a),tb=await credentials(b);
 const req=async(payload,token=ta)=>{const r=await app.inject({method:"POST",url:"/v1/gerald-story/",headers:{authorization:"Bearer "+token},payload});return {status:r.statusCode,body:r.json()};};
 const check=async(payload,reason,token=ta)=>{const r=await req(payload,token);assert.equal(r.body.reason,reason,JSON.stringify(r));};
 await check({operation:"start"},"story_progression_required");await check({operation:"start",groupId:"revienna_encounter"},"invalid_action");
 await pool.query("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,status,finished_at,state) VALUES($1,'tutorial_fairy_spar',ARRAY['kael'],'victory',now(),$2::jsonb)",[a,JSON.stringify({view:{status:"victory"},actions:[{kind:"skill"}]})]);
 await check({operation:"start"},"encounter_position_required");
 server=(await pool.query("INSERT INTO game_servers(server_key,display_name,region_id,status,heartbeat_at) VALUES($1,'Gerald QA','story_village','online',now()) RETURNING id",["gerald-qa-"+suffix])).rows[0].id;
 await pool.query("INSERT INTO game_server_players(server_id,player_id) VALUES($1,$2)",[server,a]);
 await pool.query("INSERT INTO game_server_player_state(server_id,player_id,x,y) VALUES($1,$2,-2090,112)",[server,a]);
 const lease=randomUUID();await pool.query("INSERT INTO game_server_player_connections(connection_id,server_id,player_id,lease_expires_at) VALUES($1,$2,$3,now()+interval '45 seconds')",[lease,server,a]);
 await check({operation:"start"},"encounter_position_required");
 await pool.query("UPDATE game_server_player_state SET x=13,y=2865,updated_at=now()-interval '20 seconds' WHERE server_id=$1",[server]);await check({operation:"start"},"encounter_position_required");
 await pool.query("UPDATE game_server_player_state SET updated_at=now() WHERE server_id=$1",[server]);
 await pool.query("INSERT INTO owned_characters(player_id,char_id,level,ascension,awakening) VALUES($1,'kael',80,3,5) ON CONFLICT(player_id,char_id) DO UPDATE SET level=80,ascension=3,awakening=5",[a]);
 const gold=await balance(a,"gold");let r=(await req({operation:"start"})).body;assert.ok(r.ok,JSON.stringify(r));const bid=r.battleId;
 assert.equal(r.view.units.filter(u=>u.team===0).length,1);
 await check({operation:"resume",battleId:bid},"battle_not_found",tb);
 assert.equal((await req({operation:"start"})).body.battleId,bid);
 for(let n=1;n<=20&&r.view.status==="active";n++){
  const actor=r.view.units.find(u=>u.uid===r.view.actorUid),foe=r.view.units.find(u=>u.team===1&&u.hp>0);
  const payload={operation:"act",battleId:bid,sequence:n,action:{kind:"skill",actorUid:actor.uid,skillId:actor.skills[0],targetUids:[foe.uid]}};
  r=(await req(payload)).body;assert.ok(r.ok,JSON.stringify(r));const duplicate=(await req(payload)).body;assert.deepEqual(duplicate,{...r,replayed:true});
 }
 assert.equal(r.view.status,"victory");assert.ok(r.rewards.gold>0);assert.equal(await balance(a,"gold"),gold+r.rewards.gold);
 assert.deepEqual((await req({operation:"start"})).body,{...r,replayed:true});assert.equal(await balance(a,"gold"),gold+r.rewards.gold);
 console.log("PASS Gerald pilot HTTP: progression, position, ownership, Kael-only combat, duplicate action and victory recovery, exact once payout");
}finally{await app.close();if(server)await pool.query("DELETE FROM game_servers WHERE id=$1",[server]);await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();}
