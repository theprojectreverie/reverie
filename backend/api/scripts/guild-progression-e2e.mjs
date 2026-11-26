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
const a=Fastify(),b=Fastify(),suffix=randomBytes(4).toString('hex'),emails=[],ids=[],tokens=[],guilds=[];
const call=(app,method,path,i,payload)=>app.inject({method,url:'/v1/guilds'+path,headers:i==null?{}:{authorization:'Bearer '+tokens[i]},...(payload?{payload}:{})});
const post=(i,path,payload)=>call(a,'POST',path,i,payload);
const me=async i=>(await call(a,'GET','/me',i)).json();
const claim=(app,i,guildId,day,missionId)=>call(app,'POST','/missions/claim',i,{guildId,day,missionId});
async function ledger(i,reason,ref,key){
 await pool.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',1,1,$2,'qa',$3,$4)",[ids[i],reason,ref,'guild-qa:'+key]);
}
try{
 for(const app of [a,b]){await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(guildRoutes,{prefix:'/v1/guilds'});await app.ready();}
 for(let i=0;i<3;i++){
  const name='GXP'+i+suffix,email=name+'@example.test',password=randomBytes(16).toString('hex');emails.push(email);
  const r=await a.inject({method:'POST',url:'/v1/auth/register',payload:{email,playerName:name,password}});assert.equal(r.statusCode,201,r.body);
  const l=await a.inject({method:'POST',url:'/v1/auth/login',payload:{playerName:name,password}});assert.equal(l.statusCode,200,l.body);ids.push(l.json().player.id);tokens.push(l.json().accessToken);
 }
 const day=(await pool.query("SELECT to_char((now() AT TIME ZONE 'UTC')::date,'YYYY-MM-DD') AS day")).rows[0].day;
 await ledger(1,'online_daily_quest',day+':checkin','prejoin');
 for(const i of [0,2]){
  const r=await post(i,'/create',{name:'Guild XP '+i+' '+suffix,description:'QA',emblem:'moon'});assert.equal(r.statusCode,201,r.body);guilds.push(r.json().guildId);
 }
 const [g,h]=guilds;
 assert.equal((await claim(a,1,g,day,'checkin')).statusCode,403);
 assert.equal((await post(0,'/invite',{playerId:ids[1]})).statusCode,200);
 assert.equal((await post(1,'/invitation',{guildId:g,accept:true})).statusCode,200);
 assert.equal((await me(1)).missions.rows.find(r=>r.id==='checkin').progress,0);
 assert.equal((await claim(a,1,g,day,'checkin')).statusCode,409);
 assert.equal((await claim(a,0,g,day,'victories')).statusCode,409);
 await ledger(0,'online_daily_quest',day+':checkin','checkin');
 await ledger(0,'online_daily_quest',day+':victories','victorytask');
 await ledger(0,'online_daily_quest',day+':shared','sharedtask');
 for(let i=0;i<3;i++)await ledger(0,'coop_monster_defeat','qa-victory-'+i,'win'+i);
 assert.equal((await claim(a,0,g,'2000-01-01','checkin')).statusCode,409);
 assert.equal((await call(a,'POST','/missions/claim',0,{guildId:g,day,missionId:'checkin',xp:999999})).statusCode,400);
 await pool.query("UPDATE guilds SET xp=900 WHERE id=$1",[g]);
 const race=await Promise.all([claim(a,0,g,day,'checkin'),claim(b,0,g,day,'checkin')]);
 assert.deepEqual(race.map(r=>r.statusCode).sort(),[200,409]);
 assert.equal((await claim(a,0,g,day,'victories')).statusCode,200);
 assert.equal((await claim(b,0,g,day,'daily_duties')).statusCode,200);
 const state=await me(0);
 assert.equal(state.guild.xp,'1100');assert.equal(state.guild.level,2);
 assert.ok(state.missions.rows.every(r=>r.claimed&&!r.canClaim));
 assert.equal(state.contributions[0].id,ids[0]);assert.equal(state.contributions[0].xp,200);
 assert.equal(state.contributions[1].xp,0);
 assert.equal((await post(0,'/role',{playerId:ids[1],role:'leader'})).statusCode,200);
 assert.equal((await post(0,'/leave',{})).statusCode,200);
 assert.equal((await post(2,'/invite',{playerId:ids[0]})).statusCode,200);
 assert.equal((await post(0,'/invitation',{guildId:h,accept:true})).statusCode,200);
 assert.equal((await claim(a,0,g,day,'checkin')).statusCode,403);
 assert.equal((await claim(a,0,h,day,'checkin')).statusCode,409);
 assert.equal((await me(0)).guild.xp,'0');
 assert.equal((await post(1,'/leave',{})).statusCode,200);
 assert.equal((await pool.query("SELECT count(*)::int AS n FROM guild_mission_claims WHERE player_id=$1 AND guild_id IS NULL",[ids[0]])).rows[0].n,3);
 assert.equal((await claim(b,0,h,day,'daily_duties')).statusCode,409);
 console.log('PASS verified activity, prejoin isolation, forged claim rejection, concurrent claim idempotency, XP, level-up, rankings, guild switching and disband protection');
}catch(e){console.error(e);process.exitCode=1;}finally{await a.close();await b.close();for(const g of guilds)await pool.query('DELETE FROM guilds WHERE id=$1',[g]);await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}