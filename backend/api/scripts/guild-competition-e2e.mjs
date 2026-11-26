import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {pool} from '../src/db.ts';
import {config} from '../src/config.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {guildRoutes} from '../src/routes/guilds.ts';
assert.equal(config.NODE_ENV,'development');
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify(),suffix=randomBytes(4).toString('hex'),emails=[],ids=[],tokens=[],guilds=[];
const call=(method,path,i,payload)=>app.inject({method,url:'/v1/guilds'+path,headers:i==null?{}:{authorization:'Bearer '+tokens[i]},...(payload?{payload}:{})});
const board=async i=>{const r=await call('GET','/competition',i);assert.equal(r.statusCode,200,r.body);return r.json();};
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(guildRoutes,{prefix:'/v1/guilds'});await app.ready();
 for(let i=0;i<3;i++){
  const name='GLeague'+i+suffix,email=name+'@example.test',password=randomBytes(16).toString('hex');emails.push(email);
  const r=await app.inject({method:'POST',url:'/v1/auth/register',payload:{email,playerName:name,password}});assert.equal(r.statusCode,201,r.body);
  const l=await app.inject({method:'POST',url:'/v1/auth/login',payload:{playerName:name,password}});assert.equal(l.statusCode,200,l.body);ids.push(l.json().player.id);tokens.push(l.json().accessToken);
 }
 assert.equal((await call('GET','/competition',null)).statusCode,401);
 for(const i of [0,1]){const r=await call('POST','/create',i,{name:'League '+i+' '+suffix,description:'QA',emblem:'moon'});assert.equal(r.statusCode,201,r.body);guilds.push(r.json().guildId);}
 const [g,h]=guilds;
 assert.equal((await board(0)).own.rank,null);
 const season=await board(0);
 assert.equal((new Date(season.end)-new Date(season.start))/86400000,28);
 assert.equal(season.memberLimit,30);
 const day=(await pool.query("SELECT to_char((now() AT TIME ZONE 'UTC')::date,'YYYY-MM-DD') AS day")).rows[0].day;
 await pool.query("INSERT INTO guild_mission_claims(player_id,guild_id,mission_day,mission_id,xp) VALUES($1,$2,$3,'checkin',25),($4,$5,$3,'checkin',25)",[ids[0],g,day,ids[1],h]);
 await pool.query("INSERT INTO guild_mission_claims(player_id,guild_id,mission_day,mission_id,xp) VALUES($1,$2,$3::date-1,'checkin',25)",[ids[0],g,season.start]);
 const join=(await pool.query("SELECT joined_at::text AS joined FROM guild_members WHERE player_id=$1",[ids[0]])).rows[0].joined;
 await pool.query("INSERT INTO guild_raid_attempts(guild_id,player_id,week_start,attempt_day,joined_at,state,status,damage) VALUES($1,$2,date_trunc('week',now() AT TIME ZONE 'UTC')::date,$3,$4,'{}','victory',1000)",[g,ids[0],day,join]);
 const result=await board(0);
 assert.equal(result.own.points,'125');assert.equal(result.own.contributors,1);
 const peer=await board(1);assert.equal(peer.own.points,'25');assert.ok(result.own.rank<peer.own.rank);
 assert.equal((await board(2)).own,null);
 const leaders=result.leaders.filter(x=>[g,h].includes(x.guildId));assert.ok(leaders.some(x=>x.guildId===g&&x.raidDamage==='1000'&&x.missionPoints==='25'));
 // A former member's points stay with the guild that earned them.
 assert.equal((await call('POST','/invite',0,{playerId:ids[2]})).statusCode,200);
 assert.equal((await call('POST','/invitation',2,{guildId:g,accept:true})).statusCode,200);
 await pool.query("INSERT INTO guild_mission_claims(player_id,guild_id,mission_day,mission_id,xp) VALUES($1,$2,$3,'checkin',25)",[ids[2],g,day]);
 assert.equal((await call('POST','/leave',2,{})).statusCode,200);
 assert.equal((await call('POST','/invite',1,{playerId:ids[2]})).statusCode,200);
 assert.equal((await call('POST','/invitation',2,{guildId:h,accept:true})).statusCode,200);
 assert.equal((await board(0)).own.points,'150');assert.equal((await board(2)).own.points,'25');
 console.log('PASS seasonal dates, mission/raid score, historical exclusion, account authentication, ranking and cross-guild attribution');
}catch(e){console.error(e);process.exitCode=1;}finally{await app.close();for(const g of guilds)await pool.query('DELETE FROM guilds WHERE id=$1',[g]);await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}