import assert from "node:assert/strict";
import {randomBytes,randomUUID} from "node:crypto";
import {readFileSync} from "node:fs";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {settleStoryVictory,storyReward} from "../src/world/story-battle-rewards.ts";
import {gainCharacterXp} from "../src/world/character-xp.ts";
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname)&&config.NODE_ENV!=="production");
const app=Fastify({logger:false});
const emails=[],players=[];
const suffix=randomBytes(4).toString("hex");
const ids=["kael","gerald","lilith"];
async function fixture(i){
 const playerName="StoryQA"+suffix+i,email=playerName.toLowerCase()+"@example.test",password=randomBytes(16).toString("hex");
 emails.push(email);
 assert.equal((await app.inject({method:"POST",url:"/v1/auth/register",payload:{email,playerName,password}})).statusCode,201);
 const login=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName,password}})).json();
 const id=login.player.id;players.push(id);
 await pool.query("INSERT INTO owned_characters(player_id,char_id) SELECT $1,unnest($2::text[]) ON CONFLICT DO NOTHING",[id,ids]);
 return id;
}
async function makeBattle(id,group,status,party=["kael","lilith"]){
 const battle=randomUUID();
 // Internal fixture only: simulates a persisted server combat outcome, not a public API.
 await pool.query("INSERT INTO story_battle_sessions(id,player_id,group_id,party_ids,status,finished_at) VALUES($1,$2,$3,$4,$5,CASE WHEN $5='active' THEN NULL ELSE now() END)",[battle,id,group,party,status]);
 return battle;
}
async function settle(id,battle,rollback=false){
 const db=await pool.connect();
 try{await db.query("BEGIN");const result=await settleStoryVictory(db,id,battle);await db.query(rollback?"ROLLBACK":"COMMIT");return result;}
 catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
}
async function wallet(id){
 return Object.fromEntries((await pool.query("SELECT currency_id,balance::int AS balance FROM player_currencies WHERE player_id=$1 ORDER BY currency_id",[id])).rows.map(r=>[r.currency_id,r.balance]));
}
try{
 await pool.query(readFileSync("../migrations/034_story_battle_sessions.sql","utf8").replace(/^\uFEFF/,""));
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.ready();
 const a=await fixture(0),b=await fixture(1);
 const groupIds=Object.keys(JSON.parse(readFileSync("../../resources/data/enemy_groups.json","utf8")));
 for(const id of groupIds.filter(id=>id!=="tutorial_fairy_spar")){storyReward(id,()=>0);storyReward(id,()=>0.9999);}
 assert.deepEqual(storyReward("revienna_encounter"),{gold:4160,crystals:832,ancient_coins:5,xp:6240,items:{gothic_shard:4,royal_seal:1}});
 assert.deepEqual(storyReward("glade_mossling_pack",()=>0).items,{glade_sap:2});
 assert.deepEqual(storyReward("glade_mossling_pack",()=>0.9999).items,{glade_sap:1});
 const original=await wallet(a);
 for(const status of ["active","defeat","abandoned"]){
  const id=await makeBattle(a,"rose_slime_garden_1",status);
  assert.deepEqual(await settle(a,id),{ok:false,reason:"victory_not_verified"});
 }
 const foreign=await makeBattle(b,"rose_slime_garden_1","victory");
 assert.deepEqual(await settle(a,foreign),{ok:false,reason:"battle_not_found"});
 const unowned=await makeBattle(a,"rose_slime_garden_1","victory",["ravienna_mythic"]);
 assert.deepEqual(await settle(a,unowned),{ok:false,reason:"battle_party_not_owned"});
 const tutorial=await makeBattle(a,"tutorial_fairy_spar","victory");
 assert.deepEqual(await settle(a,tutorial),{ok:false,reason:"not_rewarded_story_encounter"});
 assert.deepEqual(await wallet(a),original);
 const battle=await makeBattle(a,"revienna_encounter","victory");
 const rolledBack=await settle(a,battle,true);assert.ok(rolledBack.ok);assert.deepEqual(await wallet(a),original);
 const pair=await Promise.all([settle(a,battle),settle(a,battle)]);
 assert.ok(pair.every(r=>r.ok));
 assert.deepEqual(pair.map(r=>r.replayed).sort(),[false,true]);
 assert.deepEqual(pair[0].rewards,pair[1].rewards);
 const after=await wallet(a),reward=pair[0].rewards;
 for(const c of ["gold","crystals","ancient_coins"])assert.equal(after[c],(original[c]??0)+reward[c]);
 const stock=(await pool.query("SELECT item_id,quantity::int AS n FROM inventory_items WHERE player_id=$1",[a])).rows;
 for(const [id,amount] of Object.entries(reward.items))assert.equal(stock.find(r=>r.item_id===id).n,amount);
 const expected=gainCharacterXp(1,0,0,reward.xp);
 const roster=(await pool.query("SELECT char_id,level,xp::int AS xp,bond FROM owned_characters WHERE player_id=$1 ORDER BY char_id",[a])).rows;
 assert.deepEqual(roster.find(r=>r.char_id==="gerald"),{char_id:"gerald",level:1,xp:0,bond:0});
 for(const id of ["kael","lilith"])assert.deepEqual(roster.find(r=>r.char_id===id),{char_id:id,level:expected.level,xp:expected.xp,bond:2});
 const second=await makeBattle(a,"revienna_encounter","victory");
 assert.deepEqual(await settle(a,second),{ok:false,reason:"already_claimed"});
 assert.deepEqual(await wallet(a),after);
 const ledger=await pool.query("SELECT count(*)::int AS n FROM currency_ledger WHERE player_id=$1 AND reason='story_battle_defeat'",[a]);assert.equal(ledger.rows[0].n,3);
 const daily=await pool.query("SELECT victories,shared_victories FROM online_daily_quests WHERE player_id=$1",[a]);assert.deepEqual(daily.rows,[{victories:1,shared_victories:0}]);
 const xp=await pool.query("SELECT xp::int AS n FROM players WHERE id=$1",[a]);assert.equal(xp.rows[0].n,3120);
 console.log("PASS all authored rewards, rollback, ownership, defeated-only settlement, concurrency, exact wallet and items, participating party XP, one-time Revienna payout, daily quest credit");
}finally{
 await app.close();
 await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);
 await pool.end();
}
