import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {chatRoutes} from '../src/routes/chat.ts';
import {summonRoutes} from '../src/routes/summon.ts';
import {banners} from '../src/world/summon.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:{level:'error'}});
const suffix=randomBytes(4).toString('hex');
const names=['MythicA'+suffix,'MythicB'+suffix],emails=names.map(n=>n.toLowerCase()+'@example.test'),tokens=[],ids=[];
const call=(method,url,token,payload)=>app.inject({method,url,headers:token?{authorization:'Bearer '+token}:{},...(payload?{payload}:{})});
const banner=banners.crimson_covenant,oldRates=banner.rates,oldMythic=banner.pool.mythic;
try {
 await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(authRoutes,{prefix:'/v1/auth'});
 await app.register(chatRoutes,{prefix:'/v1/chat'});
 await app.register(summonRoutes,{prefix:'/v1/summon'});
 await app.ready();
 for(let i=0;i<2;i++){
  const password=randomBytes(16).toString('hex');
  assert.equal((await call('POST','/v1/auth/register',null,{email:emails[i],playerName:names[i],password})).statusCode,201);
  const login=(await call('POST','/v1/auth/login',null,{playerName:names[i],password})).json();
  tokens.push(login.accessToken);ids.push(login.player.id);
 }
 const notices=async server=>{
  const result=await server.inject({method:'GET',url:'/v1/chat/messages?channel=world',headers:{authorization:'Bearer '+tokens[1]}});
  assert.equal(result.statusCode,200);
  return result.json().messages.filter(m=>m.kind==='mythic_summon'&&m.playerId===ids[0]);
 };
 assert.equal((await notices(app)).length,0);
 assert.equal((await call('POST','/v1/chat/messages',tokens[0],{channel:'world',text:'fake',kind:'mythic_summon'})).statusCode,400);
 assert.equal((await call('POST','/v1/chat/messages',tokens[0],{channel:'world',text:'[MYTHIC SUMMON] fake'})).statusCode,201);
 assert.equal((await notices(app)).length,0);
 banner.rates={common:0,rare:0,epic:0,legendary:0,mythic:1};banner.pool.mythic=['ravienna_mythic'];
 const pull={bannerId:'crimson_covenant',count:1,requestId:randomUUID()};
 assert.equal((await call('POST','/v1/summon/pull',tokens[0],pull)).statusCode,409);
 assert.equal((await notices(app)).length,0);
 await pool.query("UPDATE player_currencies SET balance=120 WHERE player_id=$1 AND currency_id='crystals'",[ids[0]]);
 const both=await Promise.all([call('POST','/v1/summon/pull',tokens[0],pull),call('POST','/v1/summon/pull',tokens[0],pull)]);
 assert.deepEqual(both.map(r=>r.statusCode),[200,200]);
 const actual=await notices(app);
 assert.equal(actual.length,1);assert.equal(actual[0].characterId,'ravienna_mythic');assert.equal(actual[0].name,names[0]);assert.match(actual[0].text,/summoned Mythic/);
 const second=Fastify({logger:false});
 try{
  await second.register(jwt,{secret:config.JWT_SECRET});await second.register(chatRoutes,{prefix:'/v1/chat'});await second.ready();
  assert.deepEqual(await notices(second),actual);
 }finally{await second.close();}
 assert.equal((await call('POST','/v1/chat/block',tokens[1],{playerId:ids[0]})).statusCode,200);
 assert.equal((await notices(app)).length,0);
 console.log('PASS Mythic notice, failed purchase exclusion, concurrent retry, cross-process visibility, spoof rejection, and blocking');
}finally{
 banner.rates=oldRates;banner.pool.mythic=oldMythic;
 await app.close();await pool.query('DELETE FROM accounts WHERE email=ANY($1::text[])',[emails]);await pool.end();
}
