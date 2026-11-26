import Fastify from "fastify";
import jwt from "@fastify/jwt";
import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {guildRoutes} from "../src/routes/guilds.ts";
import {pvpQueueRoutes} from "../src/routes/pvp-queue.ts";
import {pvpMatchRoutes} from "../src/routes/pvp-match.ts";
assert.equal(config.NODE_ENV,"development");assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify(),suffix=randomBytes(4).toString("hex"),emails=[],ids=[],tokens=[],guilds=[],matches=[];
const req=(i,method,url,payload)=>app.inject({method,url,headers:{authorization:"Bearer "+tokens[i]},...(payload?{payload}:{})});
const join=(i,mode)=>req(i,"POST","/v1/pvp/queue/join",{mode});
try{
 assert.equal((await pool.query("SELECT count(*)::int AS n FROM pvp_queue_tickets WHERE status='waiting' AND expires_at>now()")).rows[0].n,0,"Non-test queue is in use; skip.");
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.register(guildRoutes,{prefix:"/v1/guilds"});await app.register(pvpQueueRoutes,{prefix:"/v1/pvp"});await app.register(pvpMatchRoutes,{prefix:"/v1/pvp/matches"});await app.ready();
 for(let i=0;i<4;i++){
  const name="GDuel"+i+suffix,email=name+"@example.test",password=randomBytes(16).toString("hex");emails.push(email);
  assert.equal((await app.inject({method:"POST",url:"/v1/auth/register",payload:{email,playerName:name,password}})).statusCode,201);
  const l=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName:name,password}})).json();ids.push(l.player.id);tokens.push(l.accessToken);
  await pool.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,'kael') ON CONFLICT DO NOTHING",[ids[i]]);
  await pool.query("INSERT INTO party_members(player_id,slot,character_id) SELECT player_id,1,id FROM owned_characters WHERE player_id=$1 AND char_id='kael' ON CONFLICT DO NOTHING",[ids[i]]);
 }
 for(const i of [0,2]){
  const r=await req(i,"POST","/v1/guilds/create",{name:"Duel "+i+" "+suffix,description:"QA",emblem:"moon"});assert.equal(r.statusCode,201,r.body);guilds.push(r.json().guildId);
 }
 const [g,h]=guilds;
 assert.equal((await req(0,"POST","/v1/guilds/invite",{playerId:ids[1]})).statusCode,200);
 assert.equal((await req(1,"POST","/v1/guilds/invitation",{guildId:g,accept:true})).statusCode,200);
 assert.equal((await join(3,"guild_duel")).statusCode,403);
 assert.equal((await join(0,"guild_duel")).json().status,"waiting");
 assert.equal((await join(1,"guild_duel")).json().status,"waiting");
 assert.equal((await join(3,"friendly_duel")).json().status,"waiting");
 const match=await join(2,"guild_duel");assert.equal(match.statusCode,202,match.body);const result=match.json();assert.equal(result.status,"matched");matches.push(result.matchId);
 const players=(await pool.query("SELECT player_id,guild_id FROM pvp_match_players WHERE match_id=$1",[result.matchId])).rows;
 assert.equal(players.length,2);assert.ok(players.some(p=>p.player_id===ids[0]&&p.guild_id===g));assert.ok(players.some(p=>p.player_id===ids[2]&&p.guild_id===h));
 assert.equal((await req(3,"GET","/v1/pvp/queue/status")).json().status,"waiting");
 const surrender=await req(0,"POST","/v1/pvp/matches/"+result.matchId+"/surrender",{});assert.equal(surrender.statusCode,200,surrender.body);assert.equal(surrender.json().winnerId,ids[2]);
 console.log("PASS same-guild exclusion, friendly queue isolation, membership validation, cross-guild match, authoritative surrender");
}catch(e){console.error(e);process.exitCode=1;}finally{await app.close();for(const m of matches)await pool.query("DELETE FROM pvp_matches WHERE id=$1",[m]);for(const g of guilds)await pool.query("DELETE FROM guilds WHERE id=$1",[g]);await pool.query("DELETE FROM accounts WHERE email=ANY($1)",[emails]);await pool.end();}