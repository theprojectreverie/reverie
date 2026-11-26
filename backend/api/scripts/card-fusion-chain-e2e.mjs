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
const app=Fastify({logger:false}),name='FusionQA'+randomBytes(4).toString('hex'),email=name.toLowerCase()+'@example.test',password=randomBytes(16).toString('hex');let token='',id='';
const b=banners.crimson_oath, oldRates=b.rates, oldEpic=b.pool.epic, oldRare=b.pool.rare;
const call=(method,url,payload)=>app.inject({method,url,headers:token?{authorization:'Bearer '+token}:{},...(payload?{payload}:{})});
const pull=async(requestId=randomUUID())=>{const r=await call('POST','/v1/summon/pull',{bannerId:'crimson_oath',count:1,currency:'crystals',requestId});assert.equal(r.statusCode,200,r.body);return r.json()};
const state=async()=>{const r=await call('GET','/v1/summon/state');assert.equal(r.statusCode,200,r.body);return r.json()};
try{await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(summonRoutes,{prefix:'/v1/summon'});await app.ready();assert.equal((await call('POST','/v1/auth/register',{playerName:name,email,password})).statusCode,201);const login=(await call('POST','/v1/auth/login',{playerName:name,password})).json();token=login.accessToken;id=login.player.id;
await pool.query("UPDATE player_currencies SET balance=10000 WHERE player_id=$1 AND currency_id='crystals'",[id]);
for(const [key,legend,mythic] of [['cassien','cassien_legendary','cassien_mythic'],['ravienna','ravienna','ravienna_mythic']]){
 const rare=`upgrade_${key}_rare_v1`,epic=`upgrade_${key}_epic_v1`,progress=`legendary_progress_${legend}`;
 for(const [card,r,quantity] of [[rare,'rare',19],[epic,'epic',9]]){await pool.query("INSERT INTO items(id,display_name,category,rarity) VALUES($1,$1,'material',$2) ON CONFLICT DO NOTHING",[card,r]);await pool.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=EXCLUDED.quantity",[id,card,quantity]);}
 b.rates={common:0,rare:1,epic:0,legendary:0,mythic:0};b.pool.rare=[rare];
 const first=await pull();assert.ok(first.results[0].fusions.some(f=>f.id===epic));assert.ok(first.results[0].fusions.some(f=>f.id===legend));let s=await state();assert.ok(s.roster.some(r=>r.char_id===legend));assert.equal(Number(s.inventory[progress]),1);assert.equal(Number(s.inventory[rare]??0),0);assert.equal(Number(s.inventory[epic]??0),0);
 b.rates={common:0,rare:0,epic:1,legendary:0,mythic:0};b.pool.epic=[epic];
 for(let i=2;i<=7;i++){await pool.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,9) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=9",[id,epic]);const req=randomUUID();const r=await pull(req);assert.ok(r.results[0].fusions.some(f=>f.id===legend));const replay=await pull(req);assert.deepEqual(replay.results,r.results);s=await state();assert.equal(Number(s.inventory[progress]??0),i%7);assert.equal(Number(s.inventory[epic]??0),0);if(i===7){assert.ok(r.results[0].fusions.some(f=>f.id===mythic));assert.ok(s.roster.some(r=>r.char_id===mythic));assert.ok(s.roster.some(r=>r.char_id===legend));}}
 console.log('FUSION_CHAIN_PASS',key,'20 Rare -> Epic -> Legendary -> Mythic, exact consumption and replay safety');
}
}finally{b.rates=oldRates;b.pool.epic=oldEpic;b.pool.rare=oldRare;await app.close();await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end()}
