import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {summonRoutes} from '../src/routes/summon.ts';
import {banners} from '../src/world/summon.ts';
assert.equal(config.NODE_ENV,'development');
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}),name='CassienQA'+randomBytes(4).toString('hex'),email=name.toLowerCase()+'@example.test',password=randomBytes(16).toString('hex');
const banner=banners.crimson_covenant;const rates=banner.rates,legendary=banner.pool.legendary,mythic=banner.pool.mythic;
let token='',id='';
const call=(method,url,payload)=>app.inject({method,url,headers:token?{authorization:'Bearer '+token}:{},...(payload?{payload}:{})});
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(summonRoutes,{prefix:'/v1/summon'});await app.ready();
 assert.equal((await call('POST','/v1/auth/register',{playerName:name,email,password})).statusCode,201);
 const login=(await call('POST','/v1/auth/login',{playerName:name,password})).json();token=login.accessToken;id=login.player.id;assert.ok(id&&token);
 await pool.query("UPDATE player_currencies SET balance=240 WHERE player_id=$1 AND currency_id='crystals'",[id]);
 for(const rarity of ['legendary','mythic']){
  const target='cassien_'+rarity;banner.pool[rarity]=[target];banner.rates={common:0,rare:0,epic:0,legendary:0,mythic:0,[rarity]:1};
  const request={bannerId:'crimson_covenant',count:1,requestId:randomUUID()};const pull=await call('POST','/v1/summon/pull',request);assert.equal(pull.statusCode,200,pull.body);assert.equal(pull.json().results[0].character_id,target);
  const state=await call('GET','/v1/summon/state');assert.equal(state.statusCode,200);assert.ok(state.json().roster.some(r=>r.char_id===target));
  const history=await call('GET','/v1/summon/history');assert.equal(history.statusCode,200);assert.ok(history.body.includes(target));
  console.log('PASS awarded, persisted, returned in roster and history:',target);
 }
 const party=await call('POST','/v1/summon/party',{characterIds:['kael','cassien_legendary','cassien_mythic']});assert.equal(party.statusCode,200,party.body);const state=(await call('GET','/v1/summon/state')).json();assert.ok(state.party.includes('cassien_legendary')&&state.party.includes('cassien_mythic'));console.log('PASS both Cassien variants deployable; disposable account only');
}finally{banner.rates=rates;banner.pool.legendary=legendary;banner.pool.mythic=mythic;await app.close();await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end();}
