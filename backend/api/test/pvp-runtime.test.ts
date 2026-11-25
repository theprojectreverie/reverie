import test from "node:test";
import assert from "node:assert/strict";
import {sequencePvpEvents,validatePersistedPvpState} from "../src/world/pvp-runtime.js";

const state={matchId:"m1",seed:1,sequence:4,turn:3,turnPlayerId:"p1",status:"active" as const,units:[
 {uid:"a",ownerId:"p1",team:1 as const,charId:"kael",element:"fire",maxHp:100,hp:100,atk:10,defense:5,speed:10,critChance:0,energy:0,shield:0,skillIds:["s"],cooldowns:{},statuses:[]},
 {uid:"b",ownerId:"p2",team:2 as const,charId:"gerald",element:"fire",maxHp:100,hp:100,atk:10,defense:5,speed:10,critChance:0,energy:0,shield:0,skillIds:["s"],cooldowns:{},statuses:[]}
]};
test("persisted active state must match its row id and committed sequence",()=>{
 assert.equal(validatePersistedPvpState(state,"m1",4),true);
 assert.equal(validatePersistedPvpState(state,"m2",4),false);
 assert.equal(validatePersistedPvpState(state,"m1",3),false);
 assert.equal(validatePersistedPvpState({...state,status:"completed"},"m1",4),false);
});
test("event batches receive contiguous monotonically increasing sequence numbers",()=>{
 const result=sequencePvpEvents(7,[{type:"damage"},{type:"turn"}]);
 assert.deepEqual(result,{events:[{sequence:7,event:{type:"damage"}},{sequence:8,event:{type:"turn"}}],nextSequence:9});
});
test("empty event batches do not consume sequence numbers",()=>{
 assert.deepEqual(sequencePvpEvents(12,[]),{events:[],nextSequence:12});
});
test("unsafe or malformed event batches are rejected",()=>{
 assert.equal(sequencePvpEvents(0,[{type:"x"}]),null);
 assert.equal(sequencePvpEvents(Number.MAX_SAFE_INTEGER,[{type:"x"},{type:"y"}]),null);
 assert.equal(sequencePvpEvents(1,[null as unknown as Record<string,unknown>]),null);
});
