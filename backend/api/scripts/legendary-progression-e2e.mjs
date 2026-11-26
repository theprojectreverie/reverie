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
const b=banners.crimson_oath, oldRates=b.rates,oldPool=b.pool.legendary;
const call=(method,url,payload)=>app.inject({method,url,headers:token?{authorization:'Bearer '+token}:{},...(payload?{payload}:{})});
const post=async(path,payload)=>{const r=await call('POST','/v1/summon/'+path,payload);assert.equal(r.statusCode,200,r.body);return r.json()};
const state=async()=>{const r=await call('GET','/v1/summon/state');assert.equal(r.statusCode,200,r.body);return r.json()};
try{await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(summonRoutes,{prefix:'/v1/summon'});await app.ready();assert.equal((await call('POST','/v1/auth/register',{playerName:name,email,password})).statusCode,201);const login=(await call('POST','/v1/auth/login',{playerName:name,password})).json();token=login.accessToken;id=login.player.id;
await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'gold',100000),($1,'crystals',5000) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=EXCLUDED.balance",[id]);await pool.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,'dew_of_awakening',10) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=EXCLUDED.quantity",[id]);
for(const [legend,mythic] of [['cassien_legendary','cassien_mythic'],['ravienna','ravienna_mythic']]){
 b.rates={common:0,rare:0,epic:0,legendary:1,mythic:0};b.pool.legendary=[legend];
 for(let i=0;i<7;i++){const r=await post('pull',{bannerId:'crimson_oath',count:1,currency:'crystals',requestId:randomUUID()});assert.equal(r.results[0].character_id,legend);}
 let s=await state();assert.ok(s.roster.some(r=>r.char_id===mythic));assert.ok(s.roster.some(r=>r.char_id===legend));assert.equal(String(s.inventory['legendary_progress_'+legend]??0),'0');
 const first=await post('train',{characterId:legend,expectedLevel:1,expectedXp:0});assert.equal(first.level,2);
 await pool.query('UPDATE owned_characters SET level=20,xp=0 WHERE player_id=$1 AND char_id=$2',[id,legend]);const up=await post('upgrade',{characterId:legend,action:'ascend',expectedTier:0});assert.equal(up.character.level,21);assert.equal(up.character.ascension,1);
 s=await state();const row=s.roster.find(r=>r.char_id===legend);assert.equal(row.level,21);assert.equal(row.ascension,1);assert.ok(s.roster.some(r=>r.char_id===mythic));console.log('PASS',legend,'seven copies fuse Mythic, Legendary retained, training and ascension persisted');
}
}finally{b.rates=oldRates;b.pool.legendary=oldPool;await app.close();await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end()}
