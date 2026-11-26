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
assert.ok(process.env.REVERIE_STORY_GODOT);
const a=Fastify(),b=Fastify(),suffix=randomBytes(4).toString('hex'),emails=[],ids=[],tokens=[],guilds=[];
const call=(app,method,path,i,payload)=>app.inject({method,url:'/v1/guilds'+path,headers:i==null?{}:{authorization:'Bearer '+tokens[i]},...(payload?{payload}:{})});
const post=(i,path,payload)=>call(a,'POST',path,i,payload);
const me=async i=>(await call(a,'GET','/me',i)).json();
const start=(app,i,guildId)=>call(app,'POST','/raid/start',i,{guildId});
const act=(app,i,guildId,attemptId,sequence,action)=>call(app,'POST','/raid/action',i,{guildId,attemptId,sequence,action});
const claim=(app,i,guildId,week)=>call(app,'POST','/raid/claim',i,{guildId,week});
try{
 for(const app of [a,b]){await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(guildRoutes,{prefix:'/v1/guilds'});await app.ready();}
 for(let i=0;i<3;i++){
  const name='GRaid'+i+suffix,email=name+'@example.test',password=randomBytes(16).toString('hex');emails.push(email);
  const r=await a.inject({method:'POST',url:'/v1/auth/register',payload:{email,playerName:name,password}});assert.equal(r.statusCode,201,r.body);
  const l=await a.inject({method:'POST',url:'/v1/auth/login',payload:{playerName:name,password}});assert.equal(l.statusCode,200,l.body);ids.push(l.json().player.id);tokens.push(l.json().accessToken);
  await pool.query("INSERT INTO owned_characters(player_id,char_id,level,ascension,awakening) SELECT $1,unnest($2::text[]),80,3,5 ON CONFLICT(player_id,char_id) DO UPDATE SET level=80,ascension=3,awakening=5",[ids[i],['kael','gerald','lilith']]);
 }
 const g0=await post(0,'/create',{name:'Raid '+suffix,description:'QA',emblem:'moon'});assert.equal(g0.statusCode,201,g0.body);const g=g0.json().guildId;guilds.push(g);
 assert.equal((await start(a,2,g)).statusCode,403);
 assert.equal((await post(0,'/invite',{playerId:ids[1]})).statusCode,200);
 assert.equal((await post(1,'/invitation',{guildId:g,accept:true})).statusCode,200);
 let overview=(await me(0)).raid;assert.equal(overview.hp,12000);assert.equal(overview.attemptsUsed,0);
 assert.equal((await claim(a,0,g,overview.week)).statusCode,409);
 let initial=await start(a,0,g);assert.equal(initial.statusCode,200,initial.body);let battle=initial.json();assert.equal(battle.view.status,'active');
 assert.equal((await start(b,0,g)).json().attemptId,battle.attemptId);
 const actor=battle.view.units.find(u=>u.uid===battle.view.actorUid),foe=battle.view.units.find(u=>u.team===1&&u.hp>0);
 const action={kind:'skill',actorUid:actor.uid,skillId:actor.skills[0],targetUids:[foe.uid]};
 assert.equal((await act(b,1,g,battle.attemptId,1,action)).statusCode,409);
 assert.equal((await act(a,0,g,battle.attemptId,1,{...action,damage:99999})).statusCode,409);
 assert.equal((await act(a,0,g,battle.attemptId,2,action)).statusCode,409);
 const before=await pool.query("SELECT coalesce(sum(balance),0)::text AS n FROM player_currencies WHERE player_id=$1",[ids[0]]);
 let lastAction;
 for(let n=1;n<=30&&battle.view.status==='active';n++){
  const u=battle.view.units.find(u=>u.uid===battle.view.actorUid),enemy=battle.view.units.find(u=>u.team===1&&u.hp>0);
  lastAction={kind:'skill',actorUid:u.uid,skillId:u.skills[0],targetUids:[enemy.uid]};
  let r=await act(a,0,g,battle.attemptId,n,lastAction);
  if(r.statusCode!==200){lastAction={kind:'end_turn',actorUid:u.uid};r=await act(a,0,g,battle.attemptId,n,lastAction);}
  assert.equal(r.statusCode,200,r.body);battle=r.json();
 }
 assert.equal(battle.view.status,'victory');assert.ok(battle.damage>=100);
 assert.equal((await me(1)).raid.hp,12000-battle.damage);
 assert.equal((await act(b,0,g,battle.attemptId,battle.view.sequence,lastAction)).json().replayed,true);
 assert.equal((await me(0)).raid.damage,battle.damage);
 assert.equal((await pool.query("SELECT coalesce(sum(balance),0)::text AS n FROM player_currencies WHERE player_id=$1",[ids[0]])).rows[0].n,before.rows[0].n);
 // The daily budget includes abandoned attempts and applies across API instances.
 for(let i=0;i<2;i++){
  const r=await start(i===0?a:b,0,g);assert.equal(r.statusCode,200,r.body);
  const id=r.json().attemptId;
  const abandon=await call(b,'POST','/raid/abandon',0,{guildId:g,attemptId:id});
  assert.equal(abandon.statusCode,200,abandon.body);
 }
 assert.equal((await start(b,0,g)).json().error,'raid_attempt_limit');
 assert.equal((await me(0)).raid.attemptsUsed,3);
 assert.equal((await me(0)).raid.damage,battle.damage);
 assert.equal((await me(1)).raid.hp,12000-battle.damage);
 console.log('PASS daily raid limit across API instances and no damage from retreats');
 // Set a low remaining shared HP for this disposable guild; final damage must be clamped.
 await pool.query("UPDATE guild_raids SET hp=100 WHERE guild_id=$1",[g]);
 let second=(await start(a,1,g)).json();assert.ok(second.ok,JSON.stringify(second));
 for(let n=1;n<=30&&second.view.status==='active';n++){
  const u=second.view.units.find(u=>u.uid===second.view.actorUid),enemy=second.view.units.find(u=>u.team===1&&u.hp>0);
  let r=await act(b,1,g,second.attemptId,n,{kind:'skill',actorUid:u.uid,skillId:u.skills[0],targetUids:[enemy.uid]});
  if(r.statusCode!==200)r=await act(b,1,g,second.attemptId,n,{kind:'end_turn',actorUid:u.uid});
  assert.equal(r.statusCode,200,r.body);second=r.json();
 }
 assert.equal(second.damage,100);overview=(await me(0)).raid;assert.equal(overview.hp,0);assert.ok(overview.canClaim);
 const claims=await Promise.all([claim(a,0,g,overview.week),claim(b,0,g,overview.week)]);
 assert.ok(claims.every(r=>r.statusCode===200),claims.map(r=>r.body).join(';'));assert.equal(claims.filter(r=>r.json().replayed).length,1);
 assert.equal((await pool.query("SELECT count(*)::int AS n FROM currency_ledger WHERE player_id=$1 AND reason='guild_raid_reward'",[ids[0]])).rows[0].n,2);
 assert.equal((await start(a,0,g)).json().error,'raid_defeated');
 assert.equal((await claim(a,2,g,overview.week)).statusCode,403);
 console.log('PASS real Godot combat, isolation, replay protection, shared HP, overkill clamp, no story payouts and exactly-once weekly rewards');
}catch(e){console.error(e);process.exitCode=1;}finally{await a.close();await b.close();for(const g of guilds)await pool.query('DELETE FROM guilds WHERE id=$1',[g]);await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}