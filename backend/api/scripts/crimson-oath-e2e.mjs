import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {summonRoutes} from '../src/routes/summon.ts';
assert.equal(config.NODE_ENV,'development');assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}),name='OathQA'+randomBytes(4).toString('hex'),email=name.toLowerCase()+'@example.test',password=randomBytes(16).toString('hex');let token='',id='';
const call=(method,url,payload)=>app.inject({method,url,headers:token?{authorization:'Bearer '+token}:{},...(payload?{payload}:{})});
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(summonRoutes,{prefix:'/v1/summon'});await app.ready();
 assert.equal((await call('POST','/v1/auth/register',{playerName:name,email,password})).statusCode,201);
 const login=(await call('POST','/v1/auth/login',{playerName:name,password})).json();token=login.accessToken;id=login.player.id;
 await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'paid_moonstones',12000) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=EXCLUDED.balance",[id]);
 let last;
 for(let i=0;i<10;i++){const r=await call('POST','/v1/summon/pull',{bannerId:'crimson_oath',count:10,currency:'paid_moonstones',requestId:randomUUID()});assert.equal(r.statusCode,200,r.body);last=r.json();assert.equal(last.paidProgress,((i+1)*10)%100);}
 assert.equal(last.results[9].character_id,'cassien_mythic');assert.equal(last.results[9].paid_guaranteed,true);assert.equal(last.balance,'0');
 const state=(await call('GET','/v1/summon/state')).json();assert.ok(state.roster.some(r=>r.char_id==='cassien_mythic'));assert.equal(state.paidTotal,'100');
 const h=(await call('GET','/v1/summon/history')).json();assert.equal(h.entries[0].bannerId,'crimson_oath');assert.equal(h.entries[0].bannerName,'Crimson Oath');
 console.log('CRIMSON_OATH_E2E_PASS: 100 paid pulls on isolated account, guaranteed Mythic Cassien, persistent ownership, correct history and exact debit');
}finally{await app.close();await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end();}
