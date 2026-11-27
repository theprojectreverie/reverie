import test from "node:test";
import assert from "node:assert/strict";
import {resolvePvpAction,type PvpState,type PvpSkill,type PvpUnit} from "../src/world/pvp.js";
const book:Record<string,PvpSkill>={mend:{id:"mend",kind:"heal",power:0,target:"self"},strike:{id:"strike",kind:"damage",power:1000,target:"single_enemy"}};
const unit=(id:string,team:1|2=1):PvpUnit=>({uid:id,ownerId:"p"+team,team,charId:id,ascension:3,element:"neutral",hp:1000,maxHp:1000,atk:100,defense:100,speed:10,critChance:0,energy:0,shield:0,skillIds:["mend","strike"],cooldowns:{},statuses:[]});
function state():PvpState{return {matchId:"bond",seed:42,sequence:0,turn:1,turnPlayerId:"p1",status:"active",units:[unit("gerald_mythic"),unit("lilith_mythic"),unit("cassien_mythic"),unit("ravienna_mythic"),{...unit("enemy",2),hp:10000,maxHp:10000}]};}
function play(s:PvpState,uid:string,id:string,targets:string[]=[]){return resolvePvpAction(s,{playerId:s.turnPlayerId,actorUid:uid,skillId:id,targetUids:targets,sequence:s.sequence+1},book);}
function success(s:PvpState,uid:string,id:string,targets:string[]=[]){const r=play(s,uid,id,targets);assert.ok(r.ok);return r.state;}
test("bond gauge charges only on partner actions; cap and target validation",()=>{
 let s=state();
 assert.deepEqual(play(s,"gerald_mythic","beyond_death"),{ok:false,reason:"bond_not_ready"});
 for(let i=0;i<4;i++){s=success(s,i%2?"lilith_mythic":"gerald_mythic","mend");s=success(s,"enemy","mend");}
 assert.equal(s.bonds?.["1:beyond_death"]?.gauge,100);
 assert.equal(s.bonds?.["1:eternal_eclipse"],undefined);
 assert.deepEqual(play(s,"gerald_mythic","beyond_death",["enemy"]),{ok:false,reason:"invalid_targets"});
 for(const u of s.units.filter(u=>u.team===1))u.hp=400;
 s=success(s,"gerald_mythic","beyond_death");
 for(const u of s.units.filter(u=>u.team===1)){assert.equal(u.hp,900);assert.equal(u.shield,300);}
 assert.equal(s.bonds?.["1:beyond_death"]?.uses,1);
 assert.equal(s.bonds?.["1:beyond_death"]?.gauge,0);
});
test("offensive bond hits all enemies, cleanses allies, heals and rejects exhausted or unascended pair",()=>{
 let s=state();s.bonds={"1:eternal_eclipse":{gauge:100,uses:0}};
 s.units.push({...unit("enemy2",2),hp:10000,maxHp:10000});
 s.units[0]!.statuses=[{id:"poison",turns:3,potency:.1},{id:"bond_guard",turns:2,potency:.35}];
 s.units[2]!.hp=400;s.units[3]!.hp=400;
 const r=play(s,"cassien_mythic","eternal_eclipse");assert.ok(r.ok);
 const n=r.state;
 assert.ok(n.units.filter(u=>u.team===2).every(u=>u.hp<10000&&u.statuses.some(x=>x.id==="eclipse_curse")));
 assert.ok(!n.units[0]!.statuses.some(x=>x.id==="poison"));
 assert.ok(n.units[0]!.statuses.some(x=>x.id==="bond_guard"));
 assert.ok(n.units[2]!.hp>400&&n.units[3]!.hp>400);
 s.units[3]!.ascension=2;assert.deepEqual(play(s,"cassien_mythic","eternal_eclipse"),{ok:false,reason:"bond_not_ready"});
 s.units[3]!.ascension=3;s.bonds["1:eternal_eclipse"]!.uses=2;assert.deepEqual(play(s,"cassien_mythic","eternal_eclipse"),{ok:false,reason:"bond_not_ready"});
});
test("redirection and lethal protection are consumed once",()=>{
 let s=state();s.bonds={"1:beyond_death":{gauge:100,uses:0}};s=success(s,"gerald_mythic","beyond_death");
 const g=s.units[0]!,l=s.units[1]!;g.hp=10;l.hp=10;g.shield=0;l.shield=0;
 s=success(s,"enemy","strike",[l.uid]);assert.equal(s.units[0]!.hp,1);assert.equal(s.units[1]!.hp,1);
 assert.ok(!s.units[0]!.statuses.some(x=>x.id==="bond_survive"));assert.ok(!s.units[1]!.statuses.some(x=>x.id==="bond_survive"));
 s=success(s,"cassien_mythic","mend");s=success(s,"enemy","strike",[l.uid]);assert.equal(s.units[1]!.hp,0);
});

