import test from "node:test";
import assert from "node:assert/strict";
import {buildPvpRoster,createInitialPvpState,type PvpRosterContent,type OwnedPvpCharacter} from "../src/world/pvp-roster.js";

const contentData:PvpRosterContent={
 characters:{kael:{element:"fire",base:{hp:43,atk:14,def:7,spd:12,crit:0.09,crit_dmg:1.35},growth:{hp:3,atk:2,def:1,spd:1,crit:0.004,crit_dmg:0.008},skills:["ember_lance","rally_cry"],ultimate:"blazing_charge"}},
 skills:{
  ember_lance:{kind:"damage",power:96,target:"single_enemy",element:"fire",energy_gain:22,scaling_stat:"atk",statuses:[{id:"burn",chance:0.35,turns:2,potency:0.06}]},
  rally_cry:{kind:"buff",power:0,target:"all_allies",statuses:[{id:"atk_up",turns:3,potency:0.22}]},
  blazing_charge:{kind:"damage",power:210,target:"single_enemy",ultimate:true,element:"fire"}
 },
 items:{
  gladewood_bow:{category:"equipment",slot:"weapon",set_id:"greenward_wayfarer",element:"wind",stats:{atk:24,spd:4}},
  mossweave_vest:{category:"equipment",slot:"armor",set_id:"greenward_wayfarer",stats:{hp:120,def:16}},
  wayfarer_charm:{category:"equipment",slot:"accessory",set_id:"greenward_wayfarer",stats:{spd:9,crit:0.04}}
 }
};
const owned:OwnedPvpCharacter={id:"owned-1",char_id:"kael",level:1,ascension:0,awakening:0,bond:0};

test("builds server-owned unit stats and converts authored skill data",()=>{
 const result=buildPvpRoster("player-a",1,[owned],contentData);
 assert.equal(result.ok,true);
 if(!result.ok)return;
 const unit=result.units[0]!;
 assert.equal(unit.uid,"p_owned-1");
 assert.equal(unit.ownerId,"player-a");
 assert.equal(unit.team,1);
 assert.equal(unit.maxHp,43);
 assert.equal(unit.atk,14);
 assert.equal(unit.defense,7);
 assert.equal(unit.speed,12);
 assert.deepEqual(unit.skillIds,["ember_lance","rally_cry"]);
 assert.equal(unit.ultimateId,"blazing_charge");
 assert.equal(result.skillbook.ember_lance?.element,"fire");
 assert.equal(result.skillbook.ember_lance?.energyGain,22);
 assert.equal(result.skillbook.rally_cry?.target,"all_allies");
});

test("mirrors character level, ascension, awakening and bond progression formulas",()=>{
 const result=buildPvpRoster("player-a",1,[{...owned,level:2,ascension:1,awakening:2,bond:30}],contentData);
 assert.equal(result.ok,true);
 if(!result.ok)return;
 const unit=result.units[0]!;
 const power=1.085*1.1*1.08;
 assert.ok(Math.abs(unit.maxHp-(46*1.1*power))<1e-9);
 assert.ok(Math.abs(unit.atk-(16*1.1*power*1.06))<1e-9);
 assert.ok(Math.abs(unit.speed-(13*1.02*1.02))<1e-9);
});

test("applies authored equipment and greenward set bonuses",()=>{
 const result=buildPvpRoster("player-a",1,[{...owned,equipment:[
  {slot:"weapon",item_id:"gladewood_bow"},{slot:"armor",item_id:"mossweave_vest"},{slot:"accessory",item_id:"wayfarer_charm"}
 ]}],contentData);
 assert.equal(result.ok,true);
 if(!result.ok)return;
 const unit=result.units[0]!;
 assert.equal(unit.maxHp,43+120+40);
 assert.equal(unit.atk,14+24);
 assert.equal(unit.defense,7+16+4);
 assert.equal(unit.speed,12+4+9+5);
 assert.equal(unit.critChance,0.09+0.04+0.02);
 assert.equal(unit.element,"wind");
});

test("rejects unknown characters, missing skills and invalid equipment",()=>{
 assert.deepEqual(buildPvpRoster("p",1,[{...owned,char_id:"missing"}],contentData),{ok:false,reason:"character_content_missing"});
 assert.deepEqual(buildPvpRoster("p",1,[owned],{...contentData,skills:{}}),{ok:false,reason:"skill_content_missing"});
 assert.deepEqual(buildPvpRoster("p",1,[{...owned,equipment:[{slot:"weapon",item_id:"missing"}]}],contentData),{ok:false,reason:"equipment_content_invalid"});
});

test("enforces party bounds and unique owned instance IDs",()=>{
 assert.deepEqual(buildPvpRoster("p",1,[],contentData),{ok:false,reason:"party_size_invalid"});
 assert.deepEqual(buildPvpRoster("p",1,[owned,owned],contentData),{ok:false,reason:"owned_character_invalid"});
});

test("chooses the first turn by fastest unit with team-one tie break",()=>{
 const a=buildPvpRoster("p1",1,[owned],contentData);
 const b=buildPvpRoster("p2",2,[{...owned,id:"owned-2"}],contentData);
 assert.equal(a.ok,true);assert.equal(b.ok,true);
 if(!a.ok||!b.ok)return;
 const state=createInitialPvpState("match-1",42,{playerId:"p1",team:1,units:a.units},{playerId:"p2",team:2,units:b.units});
 assert.equal(state?.turnPlayerId,"p1");
 assert.equal(state?.sequence,0);
 assert.equal(createInitialPvpState("match-1",42,{playerId:"p1",team:1,units:a.units},{playerId:"p1",team:2,units:b.units}),null);
});
test("rejects malformed progression values and duplicate character entries",()=>{
 assert.deepEqual(buildPvpRoster("p",1,[{...owned,level:Number.NaN}],contentData),{ok:false,reason:"owned_character_invalid"});
 assert.deepEqual(buildPvpRoster("p",1,[owned,{...owned,id:"owned-2"}],contentData),{ok:false,reason:"owned_character_invalid"});
});
test("rejects duplicate equipment slots rather than silently choosing one item",()=>{
 assert.deepEqual(buildPvpRoster("p",1,[{...owned,equipment:[{slot:"weapon",item_id:"gladewood_bow"},{slot:"weapon",item_id:"gladewood_bow"}]}],contentData),{ok:false,reason:"equipment_content_invalid"});
});
test("rejects malformed authored status effects instead of silently dropping them",()=>{
 const bad={...contentData,skills:{...contentData.skills,ember_lance:{...contentData.skills.ember_lance,statuses:[null]}}};
 assert.deepEqual(buildPvpRoster("p",1,[owned],bad),{ok:false,reason:"skill_content_invalid"});
});

test("uses the account-wide unique collection count rather than party size",()=>{
 const result=buildPvpRoster("player-a",1,[owned],contentData,9);
 assert.equal(result.ok,true);
 if(!result.ok)return;
 assert.equal(result.units[0]!.maxHp,43*1.03);
 assert.deepEqual(buildPvpRoster("p",1,[owned],contentData,0),{ok:false,reason:"owned_character_count_invalid"});
 assert.deepEqual(buildPvpRoster("p",1,[owned],contentData,0.5),{ok:false,reason:"owned_character_count_invalid"});
});
test("applies persisted equipment enhancement levels and reroll stat bonuses",()=>{
 const result=buildPvpRoster("player-a",1,[{...owned,equipment:[
  {slot:"weapon",item_id:"gladewood_bow",enhancement_level:2,reroll_stat:"atk",reroll_value:2.4}
 ]}],contentData);
 assert.equal(result.ok,true);
 if(!result.ok)return;
 assert.equal(result.units[0]!.atk,14+24*1.16+2.4);
 assert.equal(result.units[0]!.speed,12+4*1.16);
});
test("rejects invalid persisted enhancement and reroll values",()=>{
 assert.deepEqual(buildPvpRoster("p",1,[{...owned,equipment:[{slot:"weapon",item_id:"gladewood_bow",enhancement_level:7}]}],contentData),{ok:false,reason:"equipment_content_invalid"});
 assert.deepEqual(buildPvpRoster("p",1,[{...owned,equipment:[{slot:"weapon",item_id:"gladewood_bow",reroll_stat:"gold",reroll_value:1}]}],contentData),{ok:false,reason:"equipment_content_invalid"});
});
test("Whisperstep applies its team speed aura when selecting the opening player",()=>{const whisperContent={...contentData,characters:{...contentData.characters,kael:{...contentData.characters.kael,passive:{id:"whisperstep"}},other:{...contentData.characters.kael,base:{...contentData.characters.kael!.base,spd:12.5},passive:undefined}}};const a=buildPvpRoster("p1",1,[owned],whisperContent);const b=buildPvpRoster("p2",2,[{...owned,id:"owned-2",char_id:"other"}],whisperContent);assert.equal(a.ok,true);assert.equal(b.ok,true);if(!a.ok||!b.ok)return;const state=createInitialPvpState("match-whisper",7,{playerId:"p1",team:1,units:a.units},{playerId:"p2",team:2,units:b.units});assert.equal(state?.turnPlayerId,"p1");});

test("Small Miracles grants one team-wide battle-start bonus even with multiple holders",()=>{const a=buildPvpRoster("p1",1,[owned,{...owned,id:"owned-a2",char_id:"other"}],{...contentData,characters:{...contentData.characters,other:{...contentData.characters.kael,passive:{id:"small_miracles"}}}});const b=buildPvpRoster("p2",2,[{...owned,id:"owned-b"}],contentData);assert.equal(a.ok,true);assert.equal(b.ok,true);if(!a.ok||!b.ok)return;a.units[0]!.passiveId="small_miracles";const state=createInitialPvpState("match-small-miracles",9,{playerId:"p1",team:1,units:a.units},{playerId:"p2",team:2,units:b.units});assert.ok(state);assert.deepEqual(state!.units.map(u=>u.energy),[10,10,0]);});

test("optional authored growth mirrors Godot zero-growth defaults",()=>{
 const {growth,...definition}=contentData.characters.kael!;
 const character={...owned,level:2};
 const omitted=buildPvpRoster("p",1,[character],{...contentData,characters:{kael:definition}});
 const empty=buildPvpRoster("p",1,[character],{...contentData,characters:{kael:{...definition,growth:{}}}});
 assert.ok(omitted.ok);
 assert.deepEqual(omitted,empty);
 assert.deepEqual(buildPvpRoster("p",1,[character],{...contentData,characters:{kael:{...definition,growth:[]}}}),{ok:false,reason:"character_content_missing"});
});


test("Mythic copies increase combat stats immediately and preserve legacy copy counts",()=>{
 const c={...contentData,characters:{...contentData.characters,ravienna_mythic:{...contentData.characters.kael,rarity:"mythic"}}};
 for(let copies=1;copies<=7;copies++){
  const result=buildPvpRoster("p",1,[{...owned,char_id:"ravienna_mythic",awakening:Math.floor((copies-1)/2),dupes:(copies-1)%2}],c);
  assert.ok(result.ok);
  if(result.ok)assert.ok(Math.abs(result.units[0]!.maxHp-43*(1+.04*(copies-1)))<1e-9);
 }
});

test("Mythic combat HP ATK and DEF gain four percent per copy, capped at seven stars",()=>{
 const mythic={...contentData,characters:{kael:{...contentData.characters.kael!,rarity:"mythic"}}};
 for(let n=1;n<=10;n++){
  const result=buildPvpRoster("p",1,[{...owned,awakening:Math.min(5,Math.floor((n-1)/2)),dupes:(n-1)%2}],mythic);
  assert.ok(result.ok);
  const unit=result.units[0]!,mult=1+Math.min(6,n-1)*0.04;
  assert.ok(Math.abs(unit.maxHp-43*mult)<1e-9);
  assert.ok(Math.abs(unit.atk-14*mult)<1e-9);
  assert.ok(Math.abs(unit.defense-7*mult)<1e-9);
 }
});
