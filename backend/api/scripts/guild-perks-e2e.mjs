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
const buy=(app,i,guildId,perkId)=>call(app,'POST','/perks/purchase',i,{guildId,perkId});
try{
 for(const app of [a,b]){await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(guildRoutes,{prefix:'/v1/guilds'});await app.ready();}
 for(let i=0;i<36;i++){
  const name='GPerk'+i+suffix,email=name+'@example.test',password=randomBytes(16).toString('hex');emails.push(email);
  const r=await a.inject({method:'POST',url:'/v1/auth/register',payload:{email,playerName:name,password}});assert.equal(r.statusCode,201,r.body);
  const l=await a.inject({method:'POST',url:'/v1/auth/login',payload:{playerName:name,password}});assert.equal(l.statusCode,200,l.body);ids.push(l.json().player.id);tokens.push(l.json().accessToken);
 }
 const r=await post(0,'/create',{name:'Perks '+suffix,description:'QA',emblem:'moon'});assert.equal(r.statusCode,201,r.body);const g=r.json().guildId;guilds.push(g);
 assert.equal((await me(0)).capacity,30);
 assert.equal((await buy(a,0,g,'hall_1')).json().error,'guild_level_required');
 await pool.query("UPDATE guilds SET level=10,xp=9000 WHERE id=$1",[g]);
 assert.equal((await buy(a,0,g,'hall_2')).json().error,'guild_prerequisite_required');
 assert.equal((await buy(a,0,g,'hall_1')).json().error,'insufficient_treasury_gold');
 await pool.query("INSERT INTO guild_bank_ledger(guild_id,player_id,currency_id,delta,reason) VALUES($1,$2,'gold',42000,'qa_seed')",[g,ids[0]]);
 for(let i=1;i<30;i++)await pool.query("INSERT INTO guild_members(guild_id,player_id,guild_rank) VALUES($1,$2,'member')",[g,ids[i]]);
 assert.equal((await post(30,'/apply',{guildId:g})).json().error,'guild_full');
 assert.equal((await buy(a,1,g,'hall_1')).statusCode,403);
 assert.equal((await buy(a,30,g,'hall_1')).statusCode,403);
 const race=await Promise.all([buy(a,0,g,'hall_1'),buy(b,0,g,'hall_1')]);assert.ok(race.every(r=>r.statusCode===200),race.map(r=>r.body).join(';'));assert.equal(race.filter(r=>r.json().replayed).length,1);
 let state=await me(0);assert.equal(state.capacity,35);assert.equal(state.treasury.gold,'37000');assert.equal(state.perks[0].owned,true);
 const search=(await call(a,'GET','/search?q='+suffix,30)).json();assert.equal(search.guilds[0].capacity,35);
 for(let i=30;i<35;i++){assert.equal((await post(i,'/apply',{guildId:g})).statusCode,200);assert.equal((await post(0,'/application',{playerId:ids[i],accept:true})).statusCode,200);}
 assert.equal((await me(0)).guild.memberCount,35);
 assert.equal((await post(35,'/apply',{guildId:g})).json().error,'guild_full');
 assert.equal((await buy(a,0,g,'hall_2')).statusCode,200);
 assert.equal((await buy(b,0,g,'hall_3')).statusCode,200);
 state=await me(0);assert.equal(state.capacity,45);assert.equal(state.treasury.gold,'0');assert.ok(state.perks.every(p=>p.owned));
 assert.equal(state.treasury.history.filter(t=>t.reason.startsWith('guild_perk:')).length,3);
 assert.equal((await post(35,'/apply',{guildId:g})).statusCode,200);
 assert.equal((await post(0,'/application',{playerId:ids[35],accept:true})).statusCode,200);
 assert.equal((await me(35)).capacity,45);
 assert.equal((await buy(a,0,g,'hall_3')).json().replayed,true);
 assert.equal((await me(0)).treasury.gold,'0');
 console.log('PASS level, prerequisites, funds, permissions, exactly-once concurrent purchases, real expanded membership, search, history, and all three tiers');
}catch(e){console.error(e);process.exitCode=1;}finally{await a.close();await b.close();for(const g of guilds)await pool.query('DELETE FROM guilds WHERE id=$1',[g]);await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}