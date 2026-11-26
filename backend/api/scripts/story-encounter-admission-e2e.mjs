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
const group="rose_slime_garden_1";let server;
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.ready();
 const a=await create(0),b=await create(1);const check=(id=a,g=group)=>transaction(db=>verifyStoryEncounter(db,id,g));
 assert.deepEqual(await check(),{ok:false,reason:"world_position_unverified"});
 server=(await pool.query("INSERT INTO game_servers(server_key,display_name,region_id,status,heartbeat_at) VALUES($1,'Story QA','six_zone_royal_gardens','online',now()) RETURNING id",["story-qa-"+suffix])).rows[0].id;
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
}finally{
 await app.close();if(server)await pool.query("DELETE FROM game_servers WHERE id=$1",[server]);await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();
}
