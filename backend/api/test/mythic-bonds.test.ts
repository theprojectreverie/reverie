import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {buildPvpRoster} from "../src/world/pvp-roster.js";
const read=(name:string)=>JSON.parse(readFileSync("../../resources/data/"+name+".json","utf8"));
const content={characters:read("characters"),skills:read("skills"),items:read("items")};
const ids=["gerald_mythic","lilith_mythic","ravienna_mythic","cassien_mythic"];
const roster=ids.map(id=>({id,char_id:id,level:15,ascension:3,awakening:0,bond:0}));
test("both ascended pair bonuses are scoped to matching party members",()=>{
 const paired=buildPvpRoster("owner",1,roster,content,4);assert.ok(paired.ok);
 for(const entry of roster){
  const single=buildPvpRoster("owner",1,[entry],content,4);assert.ok(single.ok);
  const unit=paired.units.find(u=>u.charId===entry.char_id)!;
  const base=single.units[0]!;
  if(ids.indexOf(entry.char_id)<2){assert.equal(unit.defense,base.defense*1.1);assert.equal(unit.atk,base.atk);}
  else{assert.equal(unit.atk,base.atk*1.1);assert.equal(unit.defense,base.defense);}
 }
});
test("one unascended partner cannot activate the sibling bonus",()=>{
 const pair=[roster[0]!,{...roster[1]!,ascension:2}];
 const result=buildPvpRoster("owner",1,pair,content,4);const single=buildPvpRoster("owner",1,[pair[0]!],content,4);
 assert.ok(result.ok&&single.ok);assert.equal(result.units[0]!.defense,single.units[0]!.defense);
});
