import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {summonRoutes} from '../src/routes/summon.ts';
import {banners} from '../src/world/summon.ts';
assert.equal(config.NODE_ENV,'development');assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}),name='LegendQA'+randomBytes(4).toString('hex'),email=name.toLowerCase()+'@example.test',password=randomBytes(16).toString('hex');let token='',id='';
const b=banners.eclipse_sovereign, oldRates=b.rates,oldPool=b.pool.legendary;
const call=(method,url,payload)=>app.inject({method,url,headers:token?{authorization:'Bearer '+token}:{},...(payload?{payload}:{})});
const post=async(path,payload)=>{const r=await call('POST','/v1/summon/'+path,payload);assert.equal(r.statusCode,200,r.body);return r.json()};
const state=async()=>{const r=await call('GET','/v1/summon/state');assert.equal(r.statusCode,200,r.body);return r.json()};
try{await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(summonRoutes,{prefix:'/v1/summon'});await app.ready();assert.equal((await call('POST','/v1/auth/register',{playerName:name,email,password})).statusCode,201);const login=(await call('POST','/v1/auth/login',{playerName:name,password})).json();token=login.accessToken;id=login.player.id;
await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'gold',100000),($1,'crystals',5000) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=EXCLUDED.balance",[id]);await pool.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,'dew_of_awakening',10) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=EXCLUDED.quantity",[id]);
b.rates={common:0,rare:0,epic:0,legendary:0,mythic:1};
for(let i=1;i<=7;i++){
 const requestId=randomUUID(), body={bannerId:'eclipse_sovereign',count:1,currency:'crystals',requestId};
 const result=await post('pull',body);assert.equal(result.results[0].character_id,'ravienna_mythic');assert.equal(result.results[0].ascended_count,i);
 const replay=await post('pull',body);assert.equal(replay.results[0].ascended_count,i);assert.equal(replay.replayed,true);
 const s=await state();const row=s.roster.find(r=>r.char_id==='ravienna_mythic');assert.equal(1+row.dupes+2*row.awakening,i);
 assert.equal(row.ascension,i===7?3:0);
}
console.log('PASS seven Mythic acquisitions, conserved duplicate counts, idempotent retries, full ascension');
}finally{b.rates=oldRates;b.pool.legendary=oldPool;await app.close();await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end()}
