import Fastify from "fastify";
import jwt from "@fastify/jwt";
import assert from "node:assert/strict";
import {randomBytes,randomUUID} from "node:crypto";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {createDeveloperRoutes} from "../src/routes/developer.ts";
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const suffix=randomBytes(5).toString("hex"),region="qa_health_"+suffix,keys=[],emails=[],app=Fastify({logger:false});
async function player(i){
 const email="health-"+suffix+"-"+i+"@example.test";emails.push(email);
 const a=(await pool.query("INSERT INTO accounts(email,password_hash,email_verified,status) VALUES($1,'disposable-test-no-login',true,'active') RETURNING id,token_version",[email])).rows[0];
 const p=(await pool.query("INSERT INTO players(account_id,name) VALUES($1,$2) RETURNING id",[a.id,"Health"+suffix+i])).rows[0];return {account:a.id,id:p.id,version:a.token_version};
}
async function server(label,status,seconds,capacity=10){
 const key="health-"+suffix+"-"+label;keys.push(key);
 return (await pool.query("INSERT INTO game_servers(server_key,display_name,region_id,status,endpoint_url,max_players,build_version,started_at,heartbeat_at,server_secret_hash) VALUES($1,$2,$3,$4,'ws://127.0.0.1:59999',$5,'qa-health',now()-interval '90 seconds',now()-($6::int*interval '1 second'),$7) RETURNING id",[key,"Health "+label,region,status,capacity,seconds,randomBytes(32).toString("hex")])).rows[0].id;
}
try{
 const [owner,staff,visitor]=await Promise.all([player(0),player(1),player(2)]);
 await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(createDeveloperRoutes({developerAccountIds:owner.account,staffAccess:async id=>id===staff.account,database:{query:(s,v)=>pool.query(s,v)}}));
 const token=p=>app.jwt.sign({sub:p.account,playerId:p.id,tokenVersion:p.version});
 const get=p=>app.inject({url:"/v1/developer/server-health",headers:p?{authorization:"Bearer "+token(p)}:{}});
 assert.equal((await get(null)).statusCode,401);
 assert.equal((await get(staff)).statusCode,403);
 assert.equal((await get(visitor)).statusCode,403);
 assert.equal((await get({...owner,version:owner.version+1})).statusCode,401);
 assert.equal((await get({...owner,id:visitor.id})).statusCode,401);
 const full=await server("full","online",2,1),stale=await server("stale","online",90),offline=await server("offline","offline",90),healthy=await server("healthy","online",1),draining=await server("draining","draining",1);
 await pool.query("INSERT INTO game_server_players(server_id,player_id) VALUES($1,$2)",[full,visitor.id]);
 // Two concurrent sockets must count as one connected player.
 for(let i=0;i<2;i++)await pool.query("INSERT INTO game_server_player_connections(connection_id,server_id,player_id,lease_expires_at) VALUES($1,$2,$3,now()+interval '45 seconds')",[randomUUID(),full,visitor.id]);
 const response=await get(owner);assert.equal(response.statusCode,200);assert.equal(response.headers["cache-control"],"no-store");
 const body=response.json(),rows=body.servers.filter(r=>r.region===region);
 assert.equal(rows.length,5);const by=Object.fromEntries(rows.map(r=>[r.name,r]));
 assert.equal(by["Health full"].state,"full");assert.equal(by["Health full"].reserved,1);assert.equal(by["Health full"].connected,1);
 assert.equal(by["Health stale"].state,"stale");assert.equal(by["Health offline"].state,"offline");assert.equal(by["Health healthy"].state,"online");assert.equal(by["Health draining"].state,"draining");
 assert.ok(body.unhealthy>=1&&body.pressured>=1&&body.online>=2);
 assert.ok(rows.every(r=>!Object.keys(r).some(k=>/secret|token|endpoint|playerId|server_key/i.test(k))));
 assert.ok(!JSON.stringify(body).includes("59999"));
 console.log("PASS health SQL, full/stale/offline/online/draining states, unique live players, permission boundaries, revoked sessions and secret exclusion");
}finally{
 await app.close();await pool.query("DELETE FROM game_servers WHERE server_key=ANY($1)",[keys]);await pool.query("DELETE FROM accounts WHERE email=ANY($1)",[emails]);await pool.end();console.log("PASS health fixtures cleaned up");
}
