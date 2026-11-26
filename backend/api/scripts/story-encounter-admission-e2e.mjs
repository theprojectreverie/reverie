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
import {verifyStoryEncounter,startVerifiedStoryEncounter} from "../src/world/story-encounter-admission.ts";
import {gardensStoryPilotRoutes} from "../src/routes/gardens-story-pilot.ts";
const group="rose_slime_garden_1";let server;
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.register(gardensStoryPilotRoutes,{prefix:"/v1/gardens-story"});await app.ready();
 const a=await create(0),b=await create(1);const check=(id=a,g=group)=>transaction(db=>verifyStoryEncounter(db,id,g));
 assert.deepEqual(await check(),{ok:false,reason:"world_position_unverified"});
 server=(await pool.query("INSERT INTO game_servers(server_key,display_name,region_id,status,heartbeat_at) VALUES($1,'Story QA','story_royal_gardens','online',now()) RETURNING id",["story-qa-"+suffix])).rows[0].id;
 await pool.query("INSERT INTO game_server_players(server_id,player_id) VALUES($1,$2)",[server,a]);
 await pool.query("INSERT INTO game_server_player_state(server_id,player_id,x,y) VALUES($1,$2,-1100,2200)",[server,a]);
 assert.deepEqual(await check(),{ok:false,reason:"world_position_unverified"});
 const lease=randomUUID();await pool.query("INSERT INTO game_server_player_connections(connection_id,server_id,player_id,lease_expires_at) VALUES($1,$2,$3,now()+interval '45 seconds')",[lease,server,a]);
 assert.deepEqual(await check(),{ok:false,reason:"encounter_progression_required"});
 await pool.query("INSERT INTO story_milestone_reaches(player_id,milestone_id) VALUES($1,'village') ON CONFLICT DO NOTHING",[a]);
 assert.deepEqual(await check(),{ok:false,reason:"encounter_progression_required"});
 const fake=await pool.query("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,status,finished_at) VALUES($1,'gerald_boss_encounter',ARRAY['kael'],'victory',now()) RETURNING id",[a]);
 assert.deepEqual(await check(),{ok:false,reason:"encounter_progression_required"});
 // QA fixture only: represent a previously settled trusted victory.
 await pool.query("UPDATE story_battle_sessions SET rewards='{}'::jsonb,settled_at=now() WHERE id=$1",[fake.rows[0].id]);
 assert.deepEqual(await check(),{ok:false,reason:"encounter_progression_required"});
 await pool.query("UPDATE story_battle_sessions SET state=$2::jsonb WHERE id=$1",[fake.rows[0].id,JSON.stringify({view:{status:"victory"},actions:[{kind:"skill"}]})]);
 assert.deepEqual(await check(),{ok:false,reason:"encounter_progression_required"});
 await pool.query("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,status,finished_at,state) VALUES($1,'tutorial_fairy_spar',ARRAY['kael'],'victory',now(),$2::jsonb)",[a,JSON.stringify({view:{status:"victory"},actions:[{kind:"skill"}]})]);
 assert.deepEqual(await check(),{ok:true});assert.deepEqual(await check(b),{ok:false,reason:"world_position_unverified"});
 assert.deepEqual(await check(a,"revienna_encounter"),{ok:false,reason:"encounter_not_enabled"});
 await pool.query("UPDATE game_server_player_state SET x=-900 WHERE server_id=$1 AND player_id=$2",[server,a]);assert.deepEqual(await check(),{ok:false,reason:"encounter_out_of_range"});
 await pool.query("UPDATE game_server_player_state SET x=-1100,updated_at=now()-interval '20 seconds' WHERE server_id=$1 AND player_id=$2",[server,a]);assert.deepEqual(await check(),{ok:false,reason:"world_position_unverified"});
 await pool.query("UPDATE game_server_player_state SET updated_at=now() WHERE server_id=$1 AND player_id=$2",[server,a]);
 await pool.query("UPDATE game_server_player_connections SET lease_expires_at=now()-interval '1 second' WHERE connection_id=$1",[lease]);assert.deepEqual(await check(),{ok:false,reason:"world_position_unverified"});
 await pool.query("UPDATE game_server_player_connections SET lease_expires_at=now()+interval '45 seconds' WHERE connection_id=$1",[lease]);
 const previous=(await pool.query("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,status,rewards,finished_at,settled_at) VALUES($1,$2,ARRAY['kael'],'victory','{}'::jsonb,now(),now()) RETURNING id",[a,group])).rows[0].id;
 assert.deepEqual(await check(),{ok:false,reason:"encounter_respawning"});
 await pool.query("UPDATE story_battle_sessions SET settled_at=now()-interval '16 seconds' WHERE id=$1",[previous]);
 const valid=await startVerifiedStoryEncounter(a,group);assert.ok(valid.ok,JSON.stringify(valid));
 assert.ok((await transaction(db=>abandonStoryBattle(db,a,valid.battleId))).ok);
 console.log("PASS committed position, live lease, account ownership, verified progression, range, freshness, cooldown, denied bosses and internal verified start");
 const credentials=async id=>{const row=(await pool.query("SELECT a.id,a.token_version FROM accounts a JOIN players p ON p.account_id=a.id WHERE p.id=$1",[id])).rows[0];return app.jwt.sign({sub:row.id,playerId:id,tokenVersion:row.token_version});};
 const ta=await credentials(a),tb=await credentials(b);
 const req=async(payload,token=ta)=>{const r=await app.inject({method:"POST",url:"/v1/gardens-story/",headers:{authorization:"Bearer "+token},payload});return {status:r.statusCode,body:r.json()};};
 assert.equal((await req({operation:"status"},tb)).body.reason,"story_progression_required");
 assert.equal((await req({operation:"start",groupId:"revienna_encounter"})).status,400);
 const coords=[[-1100,2200],[-800,1850],[-1450,1500],[700,2250],[1200,1750],[950,1000],[-900,2100],[550,2100],[1100,1500]];
 const refresh=async(x,y)=>{await pool.query("UPDATE game_servers SET heartbeat_at=now() WHERE id=$1",[server]);await pool.query("UPDATE game_server_player_connections SET lease_expires_at=now()+interval '45 seconds' WHERE connection_id=$1",[lease]);await pool.query("UPDATE game_server_player_state SET x=$3,y=$4,updated_at=now() WHERE server_id=$1 AND player_id=$2",[server,a,x,y]);};
 for(let i=0;i<coords.length;i++){
  const groupId=i<6?"rose_slime_garden_"+(i+1):"crownling_garden_"+(i-5);await refresh(...coords[i]);
  const started=(await req({operation:"start",groupId})).body;assert.ok(started.ok,JSON.stringify(started));
  assert.equal((await req({operation:"start",groupId})).body.battleId,started.battleId);
  const status=(await req({operation:"status"})).body;assert.equal(status.encounters.length,9);assert.deepEqual(status.active,{battleId:started.battleId,groupId});
  assert.equal((await req({operation:"resume",groupId,battleId:started.battleId},tb)).status,404);
  assert.equal((await req({operation:"resume",groupId:"rose_slime_garden_"+(i===0?2:1),battleId:started.battleId})).status,404);
  assert.ok((await req({operation:"abandon",groupId,battleId:started.battleId})).body.ok);
 }
 console.log("PASS all nine authenticated garden starts, session recovery, group and account isolation, retreat");
 await pool.query("UPDATE owned_characters SET level=80,ascension=3,awakening=5 WHERE player_id=$1",[a]);
 await refresh(...coords[0]);const gold=await balance(a,"gold");let r=(await req({operation:"start",groupId:group})).body;assert.ok(r.ok,JSON.stringify(r));const bid=r.battleId;
 for(let n=1;n<=20&&r.view.status==="active";n++){
  const actor=r.view.units.find(u=>u.uid===r.view.actorUid),foe=r.view.units.find(u=>u.team===1&&u.hp>0);
  const payload={operation:"act",groupId:group,battleId:bid,sequence:n,action:{kind:"skill",actorUid:actor.uid,skillId:actor.skills[0],targetUids:[foe.uid]}};
  r=(await req(payload)).body;assert.ok(r.ok,JSON.stringify(r));assert.deepEqual((await req(payload)).body,{...r,replayed:true});
 }
 assert.equal(r.view.status,"victory");assert.equal(await balance(a,"gold"),gold+r.rewards.gold);
 assert.deepEqual((await req({operation:"resume",groupId:group,battleId:bid})).body,{...r,replayed:true});
 await refresh(...coords[0]);assert.equal((await req({operation:"start",groupId:group})).body.reason,"encounter_respawning");
 const state=(await req({operation:"status"})).body;assert.ok(state.encounters[0].remainingMs>0&&state.encounters[0].remainingMs<=15000);assert.ok(state.encounters.slice(1).every(e=>e.remainingMs===0));
 await pool.query("UPDATE story_battle_sessions SET settled_at=now()-interval '16 seconds' WHERE id=$1",[bid]);
 assert.equal((await req({operation:"status"})).body.encounters[0].remainingMs,0);
 const next=(await req({operation:"start",groupId:group})).body;assert.ok(next.ok);assert.notEqual(next.battleId,bid);assert.ok((await req({operation:"abandon",groupId:group,battleId:next.battleId})).body.ok);assert.equal(await balance(a,"gold"),gold+r.rewards.gold);
 console.log("PASS authoritative slime victory, exact-once reward, per-encounter cooldown and respawn");
}finally{
 await app.close();if(server)await pool.query("DELETE FROM game_servers WHERE id=$1",[server]);await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();
}
