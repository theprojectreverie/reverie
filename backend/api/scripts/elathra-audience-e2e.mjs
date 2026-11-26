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
import {gardensStoryPilotRoutes} from "../src/routes/gardens-story-pilot.ts";
let server;
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.register(gardensStoryPilotRoutes,{prefix:"/v1/gardens-story"});await app.ready();
 const a=await create(0),b=await create(1);
 const credentials=async id=>{const row=(await pool.query("SELECT a.id,a.token_version FROM accounts a JOIN players p ON p.account_id=a.id WHERE p.id=$1",[id])).rows[0];return app.jwt.sign({sub:row.id,playerId:id,tokenVersion:row.token_version});};
 const ta=await credentials(a),tb=await credentials(b);
 const req=async(payload,token=ta)=>{const r=await app.inject({method:"POST",url:"/v1/gardens-story/",headers:{authorization:"Bearer "+token},payload});return {status:r.statusCode,body:r.json()};};
 const choice=async(choice,token=ta)=>(await req({operation:"audience",choice},token)).body;
 assert.equal((await choice("hear")).reason,"story_progression_required");
 assert.equal((await req({operation:"audience",choice:"hear",xp:99999})).status,400);
 for(const group of ["tutorial_fairy_spar","gerald_boss_encounter"])await pool.query("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,status,finished_at,settled_at,rewards,state) VALUES($1,$2,ARRAY['kael'],'victory',now(),CASE WHEN $2='tutorial_fairy_spar' THEN NULL ELSE now() END,CASE WHEN $2='tutorial_fairy_spar' THEN NULL ELSE '{}'::jsonb END,$3::jsonb)",[a,group,JSON.stringify({view:{status:"victory"},actions:[{kind:"skill"}]})]);
 assert.equal((await choice("accept")).reason,"audience_hear_first");
 assert.equal((await choice("hear")).reason,"audience_position_required");
 server=(await pool.query("INSERT INTO game_servers(server_key,display_name,region_id,status,heartbeat_at) VALUES($1,'Audience QA','story_royal_gardens','online',now()) RETURNING id",["audience-qa-"+suffix])).rows[0].id;
 await pool.query("INSERT INTO game_server_players(server_id,player_id) VALUES($1,$2)",[server,a]);await pool.query("INSERT INTO game_server_player_state(server_id,player_id,x,y) VALUES($1,$2,2179,1400)",[server,a]);
 assert.equal((await choice("hear")).reason,"audience_position_required");
 const lease=randomUUID();await pool.query("INSERT INTO game_server_player_connections(connection_id,server_id,player_id,lease_expires_at) VALUES($1,$2,$3,now()+interval '45 seconds')",[lease,server,a]);
 await pool.query("UPDATE game_server_player_state SET x=-1320,y=2325 WHERE server_id=$1",[server]);assert.equal((await choice("hear")).reason,"audience_position_required");
 await pool.query("UPDATE game_server_player_state SET x=2179,y=1400,updated_at=now() WHERE server_id=$1",[server]);
 const heard=await choice("hear");assert.equal(heard.audience.state,"active");assert.equal(heard.audience.royalGateUnlocked,false);assert.equal((await choice("hear")).replayed,true);
 await pool.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,'kael') ON CONFLICT DO NOTHING",[a]);
 const before=(await pool.query("SELECT xp::text,bond FROM owned_characters WHERE player_id=$1 AND char_id='kael'",[a])).rows[0];assert.ok(before);
 const complete=await choice("accept");assert.equal(complete.audience.state,"complete");assert.equal(complete.audience.royalGateUnlocked,true);assert.deepEqual(complete.rewards,{xp:25,bond:5});
 const after=(await pool.query("SELECT xp::text,bond FROM owned_characters WHERE player_id=$1 AND char_id='kael'",[a])).rows[0];assert.equal(Number(after.xp),Number(before.xp)+25);assert.equal(after.bond,before.bond+5);
 assert.equal((await choice("accept")).replayed,true);assert.deepEqual((await pool.query("SELECT xp::text,bond FROM owned_characters WHERE player_id=$1 AND char_id='kael'",[a])).rows[0],after);
 assert.equal((await req({operation:"status"})).body.audience.royalGateUnlocked,true);assert.equal((await choice("hear",tb)).reason,"story_progression_required");
 console.log("PASS Elathra: ordered dialogue, live position, no forged reward, durable unlock, exact-once XP and bond, account isolation");
}finally{await app.close();if(server)await pool.query("DELETE FROM game_servers WHERE id=$1",[server]);await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();}
