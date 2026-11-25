import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

const characters=JSON.parse(readFileSync(resolve(process.cwd(),"../../resources/data/characters.json"),"utf8")) as Record<string,{skills?:unknown[];ultimate?:unknown}>;
const skills=JSON.parse(readFileSync(resolve(process.cwd(),"../../resources/data/skills.json"),"utf8")) as Record<string,{ultimate?:boolean;kind?:string;target?:string;cleanse?:boolean}>;

test("every authored character has a valid and correctly flagged ultimate slot",()=>{
 for(const [characterId,character] of Object.entries(characters)){
  if(!Array.isArray(character.skills)||typeof character.ultimate!=="string")continue;
  assert.ok(skills[character.ultimate],characterId+" references missing ultimate");
  assert.equal(skills[character.ultimate]!.ultimate,true,characterId+" ultimate is not flagged ultimate");
  assert.ok(!character.skills.includes(character.ultimate),characterId+" equips its ultimate as a normal skill");
  for(const skillId of character.skills){
   assert.equal(typeof skillId,"string",characterId+" has a non-string skill ID");
   assert.ok(skills[skillId as string],characterId+" references missing skill "+String(skillId));
   assert.notEqual(skills[skillId as string]!.ultimate,true,characterId+" equips an ultimate in a normal slot");
  }
 }
});

test("authored cleanse skills are support skills with ally targets",()=>{
 const cleanse=Object.entries(skills).filter(([,skill])=>skill.cleanse===true);
 assert.ok(cleanse.length>0,"expected authored cleanse skills");
 for(const [id,skill] of cleanse){
  assert.equal(skill.kind,"heal",id+" cleanse must be a heal");
  assert.ok(skill.target==="single_ally"||skill.target==="all_allies",id+" cleanse must target allies");
 }
});
