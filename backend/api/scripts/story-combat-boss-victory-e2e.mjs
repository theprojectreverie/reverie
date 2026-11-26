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
const groups=["tutorial_fairy_spar","elder_hollow","fallen_matron_encounter","baltoria_encounter","gerald_boss_encounter","cassien_encounter","revienna_encounter"];
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.ready();
 const id=await create(0);
 // QA-only max-level fixture; authored enemies, actions and rewards remain unchanged.
 await pool.query("INSERT INTO owned_characters(player_id,char_id,level,ascension,awakening) SELECT $1,unnest($2::text[]),80,3,5 ON CONFLICT(player_id,char_id) DO UPDATE SET level=80,ascension=3,awakening=5",[id,["kael","gerald","lilith"]]);
 for(const group of groups){
  const before=await balance(id,"gold");
  let r=await start(id,group);assert.ok(r.ok,`${group} start: ${JSON.stringify(r)}`);
  const bid=r.battleId;
  for(let n=1;n<=30&&r.view.status==="active";n++){
   const actor=r.view.units.find(u=>u.uid===r.view.actorUid);
   const foe=r.view.units.find(u=>u.team===1&&u.hp>0);
   const action={kind:"skill",actorUid:actor.uid,skillId:actor.skills[0],targetUids:[foe.uid]};
   const pair=await Promise.all([act(id,bid,n,action),act(id,bid,n,action)]);
   assert.ok(pair.every(x=>x.ok),`${group} action ${n}: ${JSON.stringify(pair)}`);
   assert.deepEqual(pair.map(x=>x.replayed).sort(),[false,true]);
   assert.deepEqual(pair[0].view,pair[1].view);assert.deepEqual(pair[0].rewards,pair[1].rewards);
   r=pair[0];
   if(r.view.status==="active")assert.equal(await balance(id,"gold"),before);
  }
  assert.equal(r.view.status,"victory",group);
  const stored=await transaction(db=>resumeStoryBattle(db,id,bid));assert.deepEqual(stored,{...r,replayed:true});
  const ledger=(await pool.query("SELECT count(*)::int AS n FROM currency_ledger WHERE player_id=$1 AND ref_id=$2 AND currency_id='gold'",[id,bid])).rows[0].n;
  if(group==="tutorial_fairy_spar"){assert.equal(r.rewards,null);assert.equal(await balance(id,"gold"),before);assert.equal(ledger,0);}
  else{assert.ok(r.rewards.gold>0);assert.equal(await balance(id,"gold"),before+r.rewards.gold);assert.equal(ledger,1);}
  if(group==="revienna_encounter")assert.deepEqual(await start(id,group),{ok:false,reason:"already_claimed"});
  console.log(`PASS ${group}: complete victory, ${r.view.sequence} actions, concurrent final retry, persisted rewards exactly once`);
 }
}finally{
 await app.close();await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();
}
