import assert from "node:assert/strict";
import {randomBytes,randomUUID} from "node:crypto";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {villageStoryPilotRoutes} from "../src/routes/village-story-pilot.ts";
import {villageStages,villageParty} from "../src/world/village-progression.ts";
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname)&&config.NODE_ENV!=="production");
const solo=process.argv.includes("--public-solo");
assert.equal(solo?process.env.REVERIE_PUBLIC_VILLAGE:process.env.REVERIE_VILLAGE_PROGRESSION_PILOT,"1");
assert.ok(process.env.REVERIE_STORY_GODOT);
const app=Fastify({logger:false}),emails=[];
const suffix=randomBytes(4).toString("hex");let server;
async function create(n){
 const playerName="VillageQA"+suffix+n,email=playerName.toLowerCase()+"@example.test",password=randomBytes(16).toString("hex");emails.push(email);
 assert.equal((await app.inject({method:"POST",url:"/v1/auth/register",payload:{email,playerName,password}})).statusCode,201);
 const login=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName,password}})).json();
 const id=login.player.id;
 const row=(await pool.query("SELECT a.id,a.token_version FROM accounts a JOIN players p ON p.account_id=a.id WHERE p.id=$1",[id])).rows[0];
 return {id,token:app.jwt.sign({sub:row.id,playerId:id,tokenVersion:row.token_version})};
}
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.register(villageStoryPilotRoutes,{prefix:"/v1/village-story"});await app.ready();
 const a=await create(0),b=await create(1);
 const req=async(payload,token=a.token)=>(await app.inject({method:"POST",url:"/v1/village-story/",headers:{authorization:"Bearer "+token,...(solo?{"x-reverie-alpha":"1"}:{})},payload})).json();
 const start=groupId=>req({operation:"start",groupId});
 assert.equal((await start("village_slime_1")).reason,"story_progression_required");
 await pool.query("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,status,finished_at,state) VALUES($1,'tutorial_fairy_spar',ARRAY['kael'],'victory',now(),$2::jsonb)",[a.id,JSON.stringify({view:{status:"victory"},actions:[{kind:"skill"}]})]);
 assert.equal((await start("gerald_boss_encounter")).reason,"story_progression_required");
 if(!solo)assert.equal((await start("village_slime_1")).reason,"encounter_position_required");
 if(!solo){server=(await pool.query("INSERT INTO game_servers(server_key,display_name,region_id,status,heartbeat_at) VALUES($1,'Village QA','story_village','online',now()) RETURNING id",["village-qa-"+suffix])).rows[0].id;
 await pool.query("INSERT INTO game_server_players(server_id,player_id) VALUES($1,$2)",[server,a.id]);
 await pool.query("INSERT INTO game_server_player_state(server_id,player_id,x,y) VALUES($1,$2,-2090,112)",[server,a.id]);
 const lease=randomUUID();await pool.query("INSERT INTO game_server_player_connections(connection_id,server_id,player_id,lease_expires_at) VALUES($1,$2,$3,now()+interval '10 minutes')",[lease,server,a.id]);
 }
 const pos=async(x,y)=>{
  if(solo)return;
  await pool.query("UPDATE game_servers SET heartbeat_at=now() WHERE id=$1",[server]);
  await pool.query("UPDATE game_server_player_state SET x=$2,y=$3,updated_at=now() WHERE server_id=$1 AND player_id=$4",[server,x,y,a.id]);
 };
 await pos(-500,1500);assert.equal((await start("village_nyx_encounter")).reason,"story_progression_required");
 let battleCount=0;
 for(const stage of villageStages){
  const before=await req({operation:"status"});assert.equal(before.quests.find(q=>q.quest===stage.quest).state,"active");
  for(let i=0;i<stage.groups.length;i++){
   const groupId=stage.groups[i];await pos(...stage.positions[i]);
   let r=await start(groupId);assert.ok(r.ok,JSON.stringify(r));assert.deepEqual(r.view.units.filter(u=>u.team===0).map(u=>u.charId),villageParty(groupId));
   const bid=r.battleId;
   assert.equal((await req({operation:"resume",groupId,battleId:bid},b.token)).reason,"story_progression_required");
   let last;
   for(let n=1;n<=50&&r.view.status==="active";n++){
    const actor=r.view.units.find(u=>u.uid===r.view.actorUid),foe=r.view.units.find(u=>u.team===1&&u.hp>0);
    const skill=actor.energy>=100&&actor.ultimate?actor.ultimate:actor.skills[0];
    const all=["lunar_wisp","blazing_charge","hollow_moon_eclipse"].includes(skill);
    last={operation:"act",groupId,battleId:bid,sequence:n,action:{kind:"skill",actorUid:actor.uid,skillId:skill,targetUids:all?[]:[foe.uid]}};
    let result=await req(last);
    if(!result.ok&&result.reason==="invalid_target"){last.action.targetUids=[];result=await req(last);}
    assert.ok(result.ok,JSON.stringify(result));r=result;
   }
   assert.equal(r.view.status,"victory",JSON.stringify(r.view));
   const payout=await pool.query("SELECT count(*)::int AS n FROM currency_ledger WHERE player_id=$1 AND ref_id=$2",[a.id,bid]);
   assert.deepEqual(await req(last),{...r,replayed:true});
   assert.equal((await pool.query("SELECT count(*)::int AS n FROM currency_ledger WHERE player_id=$1 AND ref_id=$2",[a.id,bid])).rows[0].n,payout.rows[0].n);
   if(groupId!=="gerald_boss_encounter")assert.equal((await start(groupId)).reason,"already_claimed");
   console.log("PASS verified victory",groupId,"party",villageParty(groupId),"actions",r.view.sequence);
   battleCount++;
  }
  assert.equal((await req({operation:"status"})).quests.find(q=>q.quest===stage.quest).state,"complete");
  if(stage.recruit){
   const owned=(await pool.query("SELECT char_id,dupes FROM owned_characters WHERE player_id=$1 AND char_id=$2",[a.id,stage.recruit])).rows;
   assert.equal(owned.length,1);assert.equal(owned[0].dupes,0);
   const party=(await pool.query("SELECT oc.char_id FROM party_members pm JOIN owned_characters oc ON oc.id=pm.character_id WHERE pm.player_id=$1 ORDER BY pm.slot",[a.id])).rows.map(x=>x.char_id);
   assert.ok(party.includes(stage.recruit));console.log("PASS transactional recruit",stage.recruit,party);
  }
 }
 assert.equal(battleCount,8);
 console.log(solo?"PUBLIC SOLO VILLAGE SERVER E2E COMPLETE":"VILLAGE SERVER E2E COMPLETE");
}finally{await app.close();if(server)await pool.query("DELETE FROM game_servers WHERE id=$1",[server]);await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();}
