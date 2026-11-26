import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
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
const donate=(app,i,guildId,amount,requestId=randomUUID())=>call(app,'POST','/treasury/donate',i,{guildId,amount,requestId});
try{
 for(const app of [a,b]){await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(guildRoutes,{prefix:'/v1/guilds'});await app.ready();}
 for(let i=0;i<3;i++){
  const name='GTreas'+i+suffix,email=name+'@example.test',password=randomBytes(16).toString('hex');emails.push(email);
  const r=await a.inject({method:'POST',url:'/v1/auth/register',payload:{email,playerName:name,password}});assert.equal(r.statusCode,201,r.body);
  const l=await a.inject({method:'POST',url:'/v1/auth/login',payload:{playerName:name,password}});assert.equal(l.statusCode,200,l.body);ids.push(l.json().player.id);tokens.push(l.json().accessToken);
  await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'gold',$2) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=EXCLUDED.balance",[ids[i],i===1?50:2000]);
 }
 for(const i of [0,2]){const r=await post(i,'/create',{name:'Treasury '+i+' '+suffix,description:'QA',emblem:'moon'});assert.equal(r.statusCode,201,r.body);guilds.push(r.json().guildId);}
 const [g,h]=guilds;
 assert.equal((await donate(a,1,g,100)).statusCode,403);
 assert.equal((await post(0,'/invite',{playerId:ids[1]})).statusCode,200);
 assert.equal((await post(1,'/invitation',{guildId:g,accept:true})).statusCode,200);
 assert.equal((await donate(a,1,g,100)).json().error,'insufficient_gold');
 assert.equal((await donate(a,0,h,100)).statusCode,403);
 assert.equal((await donate(a,0,g,-100)).statusCode,400);
 assert.equal((await donate(a,0,g,1.5)).statusCode,400);
 const requestId=randomUUID();
 const results=await Promise.all([donate(a,0,g,500,requestId),donate(b,0,g,500,requestId)]);
 assert.ok(results.every(r=>r.statusCode===200),results.map(r=>r.body).join(';'));
 assert.equal(results.filter(r=>r.json().replayed).length,1);
 assert.equal((await donate(a,0,g,100,requestId)).statusCode,409);
 let state=await me(0);assert.equal(state.treasury.gold,'500');assert.equal(state.treasury.wallet,'1500');assert.equal(state.treasury.donatedToday,500);
 const race=await Promise.all([donate(a,0,g,500),donate(b,0,g,500)]);
 assert.deepEqual(race.map(r=>r.statusCode).sort(),[200,409]);
 state=await me(0);assert.equal(state.treasury.gold,'1000');assert.equal(state.treasury.wallet,'1000');assert.equal(state.treasury.history.length,2);
 assert.equal((await me(1)).treasury.gold,'1000');assert.equal((await me(2)).treasury.gold,'0');
 const debit=await pool.query("SELECT count(*)::int AS n,sum(delta)::text AS delta FROM currency_ledger WHERE player_id=$1 AND reason='guild_donation'",[ids[0]]);
 assert.equal(debit.rows[0].n,2);assert.equal(debit.rows[0].delta,'-1000');
 assert.equal((await post(0,'/role',{playerId:ids[1],role:'leader'})).statusCode,200);
 assert.equal((await post(0,'/leave',{})).statusCode,200);
 assert.equal((await post(2,'/invite',{playerId:ids[0]})).statusCode,200);
 assert.equal((await post(0,'/invitation',{guildId:h,accept:true})).statusCode,200);
 assert.equal((await donate(b,0,h,100)).json().error,'guild_donation_daily_cap');
 assert.equal((await post(1,'/leave',{})).statusCode,200);
 assert.equal((await donate(b,0,h,100)).json().error,'guild_donation_daily_cap');
 assert.equal((await me(0)).treasury.gold,'0');
 console.log('PASS gold conservation, transaction history, insufficient funds, retry idempotency, concurrent cap, membership, guild switching and disband protection');
}catch(e){console.error(e);process.exitCode=1;}finally{await a.close();await b.close();for(const g of guilds)await pool.query('DELETE FROM guilds WHERE id=$1',[g]);await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}