// Local API-only checkpoint regression. No real accounts or characters.
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import rateLimit from "@fastify/rate-limit";
import {randomBytes,randomUUID} from "node:crypto";
import assert from "node:assert/strict";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {gameServerRoutes} from "../src/routes/game-servers.ts";
if(!["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname))throw Error("local database required");
assert(config.GAME_SERVER_BOOTSTRAP_SECRET);
const app=Fastify({logger:false,bodyLimit:16384});
const serverKey="checkpoint-e2e-"+randomBytes(8).toString("hex");
let serverId="";
try{
 await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(rateLimit,{max:100,timeWindow:"1 minute"});
 await app.register(gameServerRoutes,{prefix:"/v1/game-servers"});
 const registration=await app.inject({method:"POST",url:"/v1/game-servers/register",headers:{"x-server-bootstrap-secret":config.GAME_SERVER_BOOTSTRAP_SECRET},payload:{serverKey,displayName:"Checkpoint QA",regionId:"castle_royal_gardens",maxPlayers:1000}});
 assert.equal(registration.statusCode,201);
 const registered=registration.json();serverId=registered.serverId;
 const headers={authorization:"Bearer "+registered.serverToken};
 const url="/v1/game-servers/"+serverId+"/world-state";
 const ids=Array.from({length:1000},()=>randomUUID());
 const state=count=>({schemaVersion:1,regionId:"castle_royal_gardens",entities:[],worldFlags:{},eventSequence:count,playerPositions:Object.fromEntries(ids.slice(0,count).map((id,i)=>[id,{x:12345.125+i,y:-12345.125}])),playerProfiles:Object.fromEntries(ids.slice(0,count).map(id=>[id,{name:"LongPlayerName123456",level:100,title:"Champion of the Eclipse"}]))});
 const first=state(100),second=state(1000);
 const save=(revision,state,auth=headers)=>app.inject({method:"PUT",url,headers:auth,payload:{revision,state}});
 assert(Buffer.byteLength(JSON.stringify(first))>12000);
 assert.equal((await save(0,first,{})).statusCode,401);
 const a=await save(0,first);assert.equal(a.statusCode,200);assert.equal(a.json().revision,1);
 const b=await save(1,second);assert.equal(b.statusCode,200);assert.equal(b.json().revision,2);
 assert.equal((await save(1,first)).statusCode,409);
 assert.equal((await save(0,first)).statusCode,409);
 const tooLarge=await save(2,{extra:"x".repeat(256*1024)});
 assert.equal(tooLarge.statusCode,413);
 const c=await app.inject({method:"GET",url,headers});assert.equal(c.statusCode,200);assert.equal(c.json().revision,2);assert.deepEqual(c.json().state,second);
 const candidateA={...second,eventSequence:1001},candidateB={...second,eventSequence:1002};
 const competing=await Promise.all([save(2,candidateA),save(2,candidateB)]);
 assert.deepEqual(competing.map(r=>r.statusCode).sort(),[200,409]);
 const winner=competing[0].statusCode===200?candidateA:candidateB;
 const d=await app.inject({method:"GET",url,headers});
 assert.equal(d.json().revision,3);assert.deepEqual(d.json().state,winner);

 console.log("WORLD_CHECKPOINT_CAPACITY_PASS "+JSON.stringify({players100Bytes:Buffer.byteLength(JSON.stringify(first)),players1000Bytes:Buffer.byteLength(JSON.stringify(second)),revision:3,concurrentWriterRejected:true,unauthenticatedRejected:true,staleRevisionRejected:true,oversizeRejected:true}));
}finally{
 if(serverId)await pool.query("delete from game_servers where id=$1 and server_key=$2",[serverId,serverKey]);
 const remaining=await pool.query("select count(*)::int as n from game_servers where server_key=$1",[serverKey]);assert.equal(remaining.rows[0].n,0);
 await app.close();await pool.end();
 console.log("CHECKPOINT_FIXTURE_CLEANUP_PASS");
}
