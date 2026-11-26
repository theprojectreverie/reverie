import test from "node:test";
import assert from "node:assert/strict";
import type {Pool,PoolClient} from "pg";
import {StoryTransactionAdmission} from "../src/world/story-transaction-admission.js";
function mock(){
 const calls:string[]=[];
 const database={connect:async()=>{calls.push("connect");return {query:async(sql:string)=>{calls.push(sql);},release:()=>{calls.push("release");}} as unknown as PoolClient;}} as Pick<Pool,"connect">;
 return {database,calls};
}
test("admission rejects duplicate and overflow requests before checking out a connection",async()=>{
 const {database,calls}=mock();const gate=new StoryTransactionAdmission(database,2);
 let finish!:()=>void;const barrier=new Promise<void>(resolve=>{finish=resolve;});
 const operation=async()=>{await barrier;return {ok:true as const};};
 const a=gate.run("a",operation),b=gate.run("b",operation);
 assert.deepEqual(await gate.run("a",operation),{ok:false,reason:"story_player_busy"});
 assert.deepEqual(await gate.run("c",operation),{ok:false,reason:"story_request_busy"});
 assert.equal(calls.filter(x=>x==="connect").length,2);
 finish();await Promise.all([a,b]);assert.deepEqual(await gate.run("c",operation),{ok:true});
 assert.equal(calls.filter(x=>x==="release").length,3);
});
test("rejection rolls back and releases admission; successful retry commits",async()=>{
 const {database,calls}=mock();const gate=new StoryTransactionAdmission(database,1);
 assert.deepEqual(await gate.run("a",async()=>({ok:false,reason:"invalid_action"})),{ok:false,reason:"invalid_action"});
 assert.deepEqual(calls,["connect","BEGIN","ROLLBACK","release"]);
 assert.deepEqual(await gate.run("a",async()=>({ok:true})),{ok:true});assert.deepEqual(calls.slice(4),["connect","BEGIN","COMMIT","release"]);
});
test("operation failure rolls back and connection failure does not leak admission",async()=>{
 const {database,calls}=mock();const gate=new StoryTransactionAdmission(database,1);
 await assert.rejects(gate.run("a",async()=>{throw new Error("failure");}),/failure/);
 assert.deepEqual(calls,["connect","BEGIN","ROLLBACK","release"]);
 let attempts=0;const flaky={connect:async()=>{if(++attempts===1)throw new Error("connect failure");return database.connect();}} as Pick<Pool,"connect">;
 const retry=new StoryTransactionAdmission(flaky,1);
 await assert.rejects(retry.run("a",async()=>({ok:true})),/connect failure/);
 assert.deepEqual(await retry.run("a",async()=>({ok:true})),{ok:true});
});
