import test from "node:test";
import assert from "node:assert/strict";
import type {PoolClient} from "pg";
import {claimTutorialSummon,TUTORIAL_SUMMON_CHARACTER} from "../src/world/tutorial-summon.js";
import {collectionCharacterIds} from "../src/world/summon.js";

function fixture(won:boolean,owned=false){
 let receipt:unknown=null, grants=0;
 const queries:string[]=[];
 const db={query:async(sql:string,params:unknown[])=>{
  queries.push(sql);
  if(sql.startsWith("SELECT settings"))return {rowCount:1,rows:[{receipt}]};
  if(sql.includes("FROM story_battle_sessions"))return {rows:won?[{group_id:"tutorial_fairy_spar"}]:[]};
  if(sql.startsWith("INSERT INTO owned_characters")){
   assert.equal(params[1],TUTORIAL_SUMMON_CHARACTER);
   if(owned)return {rowCount:0,rows:[]};
   owned=true;grants++;return {rowCount:1,rows:[{id:"test"}]};
  }
  if(sql.startsWith("UPDATE players")){receipt=JSON.parse(String(params[1]));return {rowCount:1};}
  throw Error("Unexpected SQL: "+sql);
 }} as unknown as PoolClient;
 return {db,queries,grants:()=>grants};
}
test("verified spar required; no reward before victory",async()=>{
 const f=fixture(false);
 assert.deepEqual(await claimTutorialSummon(f.db,"test"),{ok:false,reason:"tutorial_victory_required"});
 assert.equal(f.grants(),0);
});
test("starter reveal grants exactly once, retry returns receipt, no banner or wallet writes",async()=>{
 assert.ok(collectionCharacterIds("legendary").includes(TUTORIAL_SUMMON_CHARACTER));
 const f=fixture(true);
 const first=await claimTutorialSummon(f.db,"test"),second=await claimTutorialSummon(f.db,"test");
 assert.ok(first.ok&&second.ok);
 assert.deepEqual(first.results,second.results);
 assert.equal(first.replayed,false);assert.equal(second.replayed,true);
 assert.equal(f.grants(),1);
 assert.ok(f.queries.every(q=>!/currency|pity|gacha_pulls/i.test(q)));
});
test("already owned character does not generate a duplicate or awakening",async()=>{
 const f=fixture(true,true);
 const r=await claimTutorialSummon(f.db,"test");
 assert.ok(r.ok);
 assert.equal(r.results[0].is_new,false);
 assert.equal(f.grants(),0);
});