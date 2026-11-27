import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {summonRoutes} from '../src/routes/summon.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}),name='BannerQA'+randomBytes(4).toString('hex'),email=name.toLowerCase()+'@example.test',password=randomBytes(16).toString('hex');
let token='',id='';
const call=(method,url,payload)=>app.inject({method,url,headers:token?{authorization:'Bearer '+token}:{},...(payload?{payload}:{})});
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(summonRoutes,{prefix:'/v1/summon'});await app.ready();
 const reg=await call('POST','/v1/auth/register',{playerName:name,email,password});assert.equal(reg.statusCode,201);
 const login=(await call('POST','/v1/auth/login',{playerName:name,password})).json();token=login.accessToken;id=login.player.id;
 assert.ok(token&&id);
 const live=await fetch('http://127.0.0.1:8787/v1/summon/state',{headers:{authorization:'Bearer '+token}});
 const liveData=await live.json();console.log('RUNNING API CATALOG',live.status,Object.keys(liveData.bannerCatalog??{})); assert.equal(live.status,200); const expected={lily_of_shadows:"elathra_mythic",crimson_oath:"cassien_mythic",eclipse_sovereign:"ravienna_mythic",flamebound_guardian:"gerald_mythic",moonlit_requiem:"lilith_mythic"}; for(const [key,value] of Object.entries(expected))assert.deepEqual(liveData.bannerCatalog[key].featured,[value],key); console.log("RUNNING API ALL FIVE MYTHIC FEATURES PASS");
 const state=await call('GET','/v1/summon/state');assert.equal(state.statusCode,200);const cat=state.json().bannerCatalog;
 await pool.query("UPDATE player_currencies SET balance=600 WHERE player_id=$1 AND currency_id='crystals'",[id]);
 for(const bannerId of ['lily_of_shadows','crimson_oath','eclipse_sovereign','flamebound_guardian','moonlit_requiem']){
  assert.ok(cat[bannerId],bannerId);
  const req={bannerId,count:1,requestId:randomUUID(),catalogRevision:cat[bannerId].revision};
  const r=await call('POST','/v1/summon/pull',req);
  assert.equal(r.statusCode,200,bannerId+': '+r.body);assert.equal(r.json().results.length,1);
  const replay=await call('POST','/v1/summon/pull',req);assert.equal(replay.statusCode,200);assert.ok(replay.json().replayed);
  console.log('AUTHENTICATED ISOLATED PULL PASS',bannerId);
 }
 const ledger=await pool.query("SELECT count(*)::int AS n FROM currency_ledger WHERE player_id=$1 AND reason='gacha_pull'",[id]);assert.equal(ledger.rows[0].n,5);
 console.log('FIVE DEBITS ONLY; ALL RETRIES IDEMPOTENT');
}finally{await app.close();await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end();}
