import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {socialRoutes} from '../src/routes/social.ts';
import {summonRoutes} from '../src/routes/summon.ts';
import {banners,emptyPity,rollBanner} from '../src/world/summon.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
for(const banner of Object.values(banners)){
 const floor=rollBanner(banner,emptyPity(),10,()=>0);
 assert.equal(floor.results.length,10);assert.equal(floor.results[9].rarity,'epic');assert.ok(floor.results.slice(0,9).every(r=>r.kind==='mob_reward'&&r.items));
 assert.equal(rollBanner(banner,{legendary:banner.hard_pity-1,featured:banner.featured_pity-1,epic_streak:0},1,()=>0).results[0].rarity,'legendary');
 for(const r of [0.1,0.6,0.85,0.98,0.999])rollBanner(banner,emptyPity(),1,()=>r);
}
const app=Fastify({logger:false}),name='SummonQA'+randomBytes(4).toString('hex'),email=name.toLowerCase()+'@example.test',password=randomBytes(16).toString('hex');
let token='',id='';
const call=(method,url,payload)=>app.inject({method,url,headers:token?{authorization:'Bearer '+token}:{},...(payload?{payload}:{})});
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(socialRoutes,{prefix:'/v1/social'});await app.register(summonRoutes,{prefix:'/v1/summon'});
 await app.ready();
 const pull={bannerId:'crimson_covenant',count:10,requestId:randomUUID()};
 assert.equal((await call('POST','/v1/summon/pull',pull)).statusCode,401);
 assert.equal((await call('POST','/v1/auth/register',{playerName:name,email,password})).statusCode,201);
 const login=(await call('POST','/v1/auth/login',{playerName:name,password})).json();token=login.accessToken;id=login.player.id;
 assert.equal((await call('POST','/v1/summon/pull',pull)).statusCode,409);
 await pool.query("UPDATE player_currencies SET balance=1200 WHERE player_id=$1 AND currency_id='crystals'",[id]);
 // Fixture-only deterministic common rate; the ten-pull floor still applies.
 const banner=banners.crimson_covenant;
 const savedRates=banner.rates;
 banner.rates={common:1,rare:0,epic:0,legendary:0,mythic:0};
 const both=await Promise.all([call('POST','/v1/summon/pull',pull),call('POST','/v1/summon/pull',pull)]);
 assert.deepEqual(both.map(r=>r.statusCode),[200,200]);
 banner.rates=savedRates;
 const a=both[0].json(),b=both[1].json();assert.equal(a.results.length,10);assert.deepEqual(a.results,b.results);assert.notEqual(a.replayed,b.replayed);assert.equal(a.balance,'0');
 assert.equal((await call('POST','/v1/summon/pull',{...pull,count:1})).statusCode,409);
 const ledger=await pool.query("SELECT count(*)::int AS n FROM currency_ledger WHERE player_id=$1 AND reason='gacha_pull'",[id]);assert.equal(ledger.rows[0].n,1);
 const profile=(await call('GET','/v1/social/profile')).json();
 for(const roll of a.results){if(roll.kind==='mob_reward'){assert.ok(!profile.unlocked.includes(roll.character_id));continue;}const portrait=roll.character_id==='kael'?'kael_avatar':roll.character_id;assert.ok(profile.unlocked.includes(portrait),portrait);}
 assert.equal((await call('POST','/v1/summon/pull',{...pull,requestId:randomUUID(),character_id:'ravienna_mythic'})).statusCode,400);
 const mobs=a.results.filter(r=>r.kind==='mob_reward');assert.equal(mobs.length,9);
 const expected={};for(const roll of mobs)for(const [item,n] of Object.entries(roll.items))expected[item]=(expected[item]??0)+n;
 const stock=await pool.query("SELECT item_id,quantity::int AS quantity FROM inventory_items WHERE player_id=$1",[id]);
 assert.deepEqual(Object.fromEntries(stock.rows.map(r=>[r.item_id,r.quantity])),expected);
 const materials=await pool.query("SELECT count(*)::int AS n FROM item_ledger WHERE player_id=$1 AND reason='gacha_mob_reward'",[id]);assert.equal(materials.rows[0].n,9);
 const state=(await call('GET','/v1/summon/state')).json();
 assert.ok(state.roster.every(r=>!r.char_id.startsWith('mob_')&&!r.char_id.endsWith('_common')));
 console.log('PASS nine non-playable mob rewards, one epic, exact inventory and idempotent material grants',expected);
 console.log('PASS server summon, pity, rates, single debit, concurrent retry, account ownership, portrait unlock');
}finally{await app.close();await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end();}
