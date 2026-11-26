import Fastify from "fastify";
import jwt from "@fastify/jwt";
import rateLimit from "@fastify/rate-limit";
import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {config} from "../src/config.ts";
import {pool} from "../src/db.ts";
import {gameServerRoutes} from "../src/routes/game-servers.ts";
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const suffix=randomBytes(6).toString("hex"),region="qa_region_"+suffix,app=Fastify({logger:false}),emails=[],keys=[];
async function player(i){
 const email="alloc-"+suffix+"-"+i+"@example.test";emails.push(email);
 const a=(await pool.query("INSERT INTO accounts(email,password_hash,email_verified,status) VALUES($1,'test-only-no-login',true,'active') RETURNING id,token_version",[email])).rows[0];
 const p=(await pool.query("INSERT INTO players(account_id,name) VALUES($1,$2) RETURNING id",[a.id,"Alloc"+suffix.slice(0,6)+i])).rows[0];
 return {id:p.id,token:app.jwt.sign({sub:a.id,playerId:p.id,tokenVersion:a.token_version})};
}
async function server(key,capacity,regionId=region,build="qa-build",status="online",stale=false){
 const k="alloc-"+suffix+"-"+key;keys.push(k);
 return (await pool.query("INSERT INTO game_servers(server_key,display_name,region_id,status,endpoint_url,max_players,build_version,heartbeat_at) VALUES($1,$2,$3,$4,'ws://127.0.0.1:59999',$5,$6,now()-($7::int*interval '1 second')) RETURNING id",[k,"Allocation "+key,regionId,status,capacity,build,stale?120:0])).rows[0].id;
}
const join=(id,p,options={})=>app.inject({method:"POST",url:"/v1/game-servers/"+id+"/join",headers:{authorization:"Bearer "+p.token},payload:options});
try{
 await app.register(rateLimit,{max:100,timeWindow:"1 minute"});
 await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(gameServerRoutes,{prefix:"/v1/game-servers"});await app.ready();
 const preferred=await server("preferred",1),a=await server("a",2),b=await server("b",2);
 const wrongRegion=await server("wrong-region",50,region+"_other");
 const wrongBuild=await server("wrong-build",50,region,"different-build");
 const stale=await server("stale",50,region,"qa-build","online",true);
 const draining=await server("draining",50,region,"qa-build","draining");
 const players=await Promise.all(Array.from({length:12},(_,i)=>player(i)));
 const first=await join(preferred,players[0],{allowRegionFallback:true});
 assert.equal(first.statusCode,200);assert.equal(first.json().serverId,preferred);assert.equal(first.json().redirected,false);
 const noOpt=await join(preferred,players[1]);assert.equal(noOpt.statusCode,409);assert.equal(noOpt.json().error,"server_full");
 const bad=await join(preferred,players[1],{allowRegionFallback:"true"});assert.equal(bad.statusCode,400);
 const duplicate=await join(preferred,players[0],{allowRegionFallback:true});assert.equal(duplicate.statusCode,409);assert.equal(duplicate.json().error,"already_on_server");
 const results=await Promise.all(players.slice(1,10).map(p=>join(preferred,p,{allowRegionFallback:true})));
 const winners=results.filter(r=>r.statusCode===200),losers=results.filter(r=>r.statusCode===409);
 assert.equal(winners.length,4);assert.equal(losers.length,5);assert.ok(losers.every(r=>r.json().error==="region_full"));
 assert.ok(winners.every(r=>{const x=r.json();return x.redirected&&x.requestedServerId===preferred&&[a,b].includes(x.serverId)&&x.regionId===region&&x.joinTicket&&x.displayName;}));
 const counts=(await pool.query("SELECT server_id,count(*)::int AS n FROM game_server_players WHERE server_id=ANY($1::uuid[]) GROUP BY server_id",[ [preferred,a,b,wrongRegion,wrongBuild,stale,draining] ])).rows;
 assert.equal(counts.length,3);assert.equal(counts.find(r=>r.server_id===preferred).n,1);assert.equal(counts.find(r=>r.server_id===a).n,2);assert.equal(counts.find(r=>r.server_id===b).n,2);
 const tickets=(await pool.query("SELECT count(*)::int AS n FROM game_server_join_tickets WHERE server_id=ANY($1::uuid[])",[[preferred,a,b,wrongRegion,wrongBuild,stale,draining]])).rows[0];assert.equal(tickets.n,5);
 const duplicateElsewhere=await join(b,players[0],{allowRegionFallback:true});assert.equal(duplicateElsewhere.statusCode,409);assert.equal(duplicateElsewhere.json().error,"leave_current_server_first");
 const unauthorized=await app.inject({method:"POST",url:"/v1/game-servers/"+preferred+"/join",payload:{allowRegionFallback:true}});assert.equal(unauthorized.statusCode,401);
 console.log("PASS preferred-first, opt-in, strict options, capacity races, same-region/build, stale/draining exclusion, no orphan tickets, existing assignments and auth");
 // Free one slot, race a single player against both the preferred and alternative route.
 const occupant=(await pool.query("SELECT player_id FROM game_server_players WHERE server_id=$1 LIMIT 1",[a])).rows[0].player_id;
 await pool.query("DELETE FROM game_server_join_tickets WHERE server_id=$1 AND player_id=$2",[a,occupant]);
 await pool.query("DELETE FROM game_server_players WHERE server_id=$1 AND player_id=$2",[a,occupant]);
 const race=await Promise.all([join(preferred,players[10],{allowRegionFallback:true}),join(a,players[10])]);
 assert.deepEqual(race.map(r=>r.statusCode).sort(),[200,409]);
 assert.equal((await pool.query("SELECT count(*)::int AS n FROM game_server_players WHERE player_id=$1",[players[10].id])).rows[0].n,1);
 console.log("PASS same-account concurrent requests reserve exactly one slot");
}finally{
 await app.close();await pool.query("DELETE FROM game_servers WHERE server_key=ANY($1)",[keys]);await pool.query("DELETE FROM accounts WHERE email=ANY($1)",[emails]);await pool.end();console.log("PASS allocation fixtures removed");
}
