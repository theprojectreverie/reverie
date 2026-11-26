import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {socialRoutes} from '../src/routes/social.ts';
import {summonRoutes} from '../src/routes/summon.ts';
import {dailyQuestRoutes} from '../src/routes/daily-quests.ts';
import {banners,emptyPity,rollBanner} from '../src/world/summon.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
for(const banner of Object.values(banners)){
 const floor=rollBanner(banner,emptyPity(),10,()=>0);
 assert.equal(floor.results.length,10);assert.equal(floor.results[9].rarity,'epic');assert.ok(floor.results.slice(0,9).every(r=>r.kind==='mob_reward'&&r.items));
 assert.equal(rollBanner(banner,{legendary:banner.hard_pity-1,featured:banner.featured_pity-1,epic_streak:0},1,()=>0).results[0].rarity,'legendary');
 for(const r of [0.1,0.6,0.85,0.98,0.999])rollBanner(banner,emptyPity(),1,()=>r);
}
const app=Fastify({logger:{level:"error"}}),name='SummonQA'+randomBytes(4).toString('hex'),email=name.toLowerCase()+'@example.test',password=randomBytes(16).toString('hex');
let token='',id='';
const call=(method,url,payload)=>app.inject({method,url,headers:token?{authorization:'Bearer '+token}:{},...(payload?{payload}:{})});
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(socialRoutes,{prefix:'/v1/social'});await app.register(summonRoutes,{prefix:'/v1/summon'});await app.register(dailyQuestRoutes,{prefix:'/v1/daily-quests'});
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
 for(const roll of a.results){if(roll.kind==='mob_reward'||roll.kind==='upgrade_card'){assert.ok(!profile.unlocked.includes(roll.character_id));continue;}const portrait=roll.character_id==='kael'?'kael_avatar':roll.character_id;assert.ok(profile.unlocked.includes(portrait),portrait);}
 assert.equal((await call('POST','/v1/summon/pull',{...pull,requestId:randomUUID(),character_id:'ravienna_mythic'})).statusCode,400);
 const mobs=a.results.filter(r=>r.kind==='mob_reward');assert.equal(mobs.length,9);
 const expected={};for(const roll of mobs)for(const [item,n] of Object.entries(roll.items))expected[item]=(expected[item]??0)+n;
 const stock=await pool.query("SELECT item_id,quantity::int AS quantity FROM inventory_items WHERE player_id=$1",[id]);
 for(const [item,n] of Object.entries(expected))assert.equal(stock.rows.find(r=>r.item_id===item).quantity,n);
 assert.equal(a.results[9].kind,'upgrade_card');
 const materials=await pool.query("SELECT count(*)::int AS n FROM item_ledger WHERE player_id=$1 AND reason='gacha_mob_reward'",[id]);assert.equal(materials.rows[0].n,9);
 const state=(await call('GET','/v1/summon/state')).json();
 assert.ok(state.roster.every(r=>!r.char_id.startsWith('mob_')&&!r.char_id.endsWith('_common')));
 console.log('PASS nine non-playable mob rewards, one epic, exact inventory and idempotent material grants',expected);
 // Force only the chosen epic card in this isolated fixture.
 const cardId='upgrade_kael_epic_v1';
 const oldPool=banner.pool.epic;const oldRates=banner.rates;
 banner.pool.epic=[cardId];banner.rates={common:0,rare:0,epic:1,legendary:0,mythic:0};
 await pool.query("INSERT INTO items(id,display_name,category,rarity) VALUES($1,'Kael Epic Card','material','epic') ON CONFLICT DO NOTHING",[cardId]);
 await pool.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,9) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=9",[id,cardId]);
 await pool.query("UPDATE player_currencies SET balance=120 WHERE player_id=$1 AND currency_id='crystals'",[id]);
 const fusionPull={bannerId:'crimson_covenant',count:1,requestId:randomUUID()};
 const pair=await Promise.all([call('POST','/v1/summon/pull',fusionPull),call('POST','/v1/summon/pull',fusionPull)]);
 banner.pool.epic=oldPool;banner.rates=oldRates;
 assert.deepEqual(pair.map(r=>r.statusCode),[200,200]);
 const first=pair[0].json(),second=pair[1].json();
 assert.deepEqual(first.results,second.results);
 assert.equal(first.results[0].kind,'upgrade_card');
 assert.equal(first.results[0].card_count,0);
 assert.equal(first.results[0].fusions[0].id,'kael_legendary');
 const owned=await pool.query("SELECT dupes FROM owned_characters WHERE player_id=$1 AND char_id='kael_legendary'",[id]);
 assert.equal(owned.rowCount,1);assert.equal(owned.rows[0].dupes,0);
 const finalStock=await pool.query("SELECT quantity::int AS n FROM inventory_items WHERE player_id=$1 AND item_id=$2",[id,cardId]);assert.equal(finalStock.rows[0].n,0);
 console.log('PASS 10 epic cards yield one Legendary Kael; simultaneous retry does not duplicate fusion');
 const progress='legendary_progress_kael_legendary';
 assert.equal(Number((await pool.query("SELECT quantity FROM inventory_items WHERE player_id=$1 AND item_id=$2",[id,progress])).rows[0].quantity),1);
 const originalLegendary=banner.pool.legendary,originalRare=banner.pool.rare,originalRates=banner.rates;
 banner.pool.rare=['upgrade_kael_rare_v1'];banner.rates={common:0,rare:1,epic:0,legendary:0,mythic:0};
 await pool.query("INSERT INTO items(id,display_name,category,rarity) VALUES('upgrade_kael_rare_v1','Kael Rare Card','material','rare') ON CONFLICT DO NOTHING");
 await pool.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,'upgrade_kael_rare_v1',18) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=18",[id]);
 await pool.query("UPDATE player_currencies SET balance=1000 WHERE player_id=$1 AND currency_id='crystals'",[id]);
 const take=()=>call('POST','/v1/summon/pull',{bannerId:'crimson_covenant',count:1,requestId:randomUUID()});
 let next=await take();assert.equal(next.statusCode,200);assert.equal(next.json().results[0].card_count,19);assert.deepEqual(next.json().results[0].fusions,[]);
 next=await take();assert.equal(next.statusCode,200);assert.equal(next.json().results[0].card_count,0);assert.equal(next.json().results[0].fusions[0].id,'upgrade_kael_epic_v1');
 banner.pool.legendary=['kael_legendary'];banner.rates={common:0,rare:0,epic:0,legendary:1,mythic:0};
 for(let i=2;i<=6;i++){next=await take();assert.equal(next.statusCode,200);assert.equal(next.json().results[0].mythic_count,i);assert.deepEqual(next.json().results[0].fusions,[]);}
 const finalRequest={bannerId:'crimson_covenant',count:1,requestId:randomUUID()};
 await pool.query("UPDATE player_currencies SET balance=120 WHERE player_id=$1 AND currency_id='crystals'",[id]);
 const finalPair=await Promise.all([call('POST','/v1/summon/pull',finalRequest),call('POST','/v1/summon/pull',finalRequest)]);
 assert.deepEqual(finalPair.map(r=>r.statusCode),[200,200]);assert.deepEqual(finalPair[0].json().results,finalPair[1].json().results);
 assert.equal(finalPair[0].json().results[0].mythic_count,0);assert.equal(finalPair[0].json().results[0].fusions[0].id,'kael_mythic');
 const versions=await pool.query("SELECT char_id,dupes FROM owned_characters WHERE player_id=$1 AND char_id IN ('kael_legendary','kael_mythic') ORDER BY char_id",[id]);
 assert.equal(versions.rows.length,2);assert.equal(versions.rows[1].dupes,0);
 banner.pool.legendary=originalLegendary;banner.pool.rare=originalRare;banner.rates=originalRates;
 console.log('PASS 19/20 Rare threshold, 6/7 Legendary threshold, both versions retained, Mythic replay protection');
 const achievements=async()=> (await call('GET','/v1/daily-quests/achievements')).json().rows;
 const getAchievement=async key=>(await achievements()).find(x=>x.id===key);
 assert.equal((await getAchievement('mythic_ascended')).can_claim,false);
 const mythicProgress='mythic_ascension_kael_mythic';
 assert.equal(Number((await pool.query("SELECT quantity FROM inventory_items WHERE player_id=$1 AND item_id=$2",[id,mythicProgress])).rows[0].quantity),1);
 await pool.query("UPDATE owned_characters SET level=15 WHERE player_id=$1 AND char_id='kael_mythic'",[id]);
 const savedMythic=banner.pool.mythic,savedMythicRates=banner.rates;
 banner.pool.mythic=['kael_mythic'];banner.rates={common:0,rare:0,epic:0,legendary:0,mythic:1};
 await pool.query("UPDATE player_currencies SET balance=720 WHERE player_id=$1 AND currency_id='crystals'",[id]);
 for(let i=2;i<=6;i++){
  next=await take();assert.equal(next.statusCode,200);assert.equal(next.json().results[0].ascended_count,i);
  assert.equal((await pool.query("SELECT ascension FROM owned_characters WHERE player_id=$1 AND char_id='kael_mythic'",[id])).rows[0].ascension,0);
 }
 const ascensionRequest={bannerId:'crimson_covenant',count:1,requestId:randomUUID()};
 const ascensionPair=await Promise.all([call('POST','/v1/summon/pull',ascensionRequest),call('POST','/v1/summon/pull',ascensionRequest)]);
 assert.deepEqual(ascensionPair.map(r=>r.statusCode),[200,200]);assert.deepEqual(ascensionPair[0].json().results,ascensionPair[1].json().results);
 assert.equal(ascensionPair[0].json().results[0].ascended_count,7);assert.equal(ascensionPair[0].json().results[0].fusions[0].fully_ascended,true);
 const max=await pool.query("SELECT ascension,level FROM owned_characters WHERE player_id=$1 AND char_id='kael_mythic'",[id]);assert.deepEqual(max.rows,[{ascension:3,level:15}]);
 banner.pool.mythic=savedMythic;banner.rates=savedMythicRates;
 console.log('PASS seven Mythic acquisitions, full ascension, level preserved and concurrent retry');
 assert.equal((await getAchievement('first_ascension')).can_claim,true);
 assert.equal((await getAchievement('mythic_ascended')).can_claim,true);
 assert.equal((await getAchievement('ascended_collection')).progress,1);
 assert.equal((await getAchievement('siblings_ascended')).progress,0);
 assert.equal((await call('POST','/v1/daily-quests/achievements/claim',{id:'siblings_ascended'})).statusCode,409);
 // Controlled QA roster fixtures cover mixed tiers, wrong variants and both exact bonds.
 await pool.query("INSERT INTO owned_characters(player_id,char_id,ascension) VALUES($1,'gerald_legendary',3),($1,'lilith_mythic',2),($1,'gerald_mythic',3),($1,'ravienna_mythic',3),($1,'cassien_mythic',2) ON CONFLICT(player_id,char_id) DO UPDATE SET ascension=EXCLUDED.ascension",[id]);
 assert.equal((await getAchievement('siblings_ascended')).progress,1);
 assert.equal((await getAchievement('eclipse_ascended')).progress,1);
 assert.equal((await getAchievement('ascended_collection')).can_claim,true);
 await pool.query("UPDATE owned_characters SET ascension=3 WHERE player_id=$1 AND char_id IN ('lilith_mythic','cassien_mythic')",[id]);
 assert.equal((await getAchievement('siblings_ascended')).can_claim,true);
 assert.equal((await getAchievement('eclipse_ascended')).can_claim,true);
 const summaryBefore=(await call('GET','/v1/social/summary')).json();
 assert.equal(summaryBefore.achievementReady.length,summaryBefore.achievementClaimable);
 assert.ok(['first_ascension','mythic_ascended','ascended_collection','siblings_ascended','eclipse_ascended'].every(key=>summaryBefore.achievementReady.some(x=>x.id===key)));
 const before=(await call('GET','/v1/auth/wallet')).json();
 const targetIds=['first_ascension','mythic_ascended','ascended_collection','siblings_ascended','eclipse_ascended'];
 // Individual claims for the new tasks, race each request.
 for(const key of targetIds){
  const results=await Promise.all([call('POST','/v1/daily-quests/achievements/claim',{id:key}),call('POST','/v1/daily-quests/achievements/claim',{id:key})]);
  assert.deepEqual(results.map(x=>x.statusCode).sort(),[200,409]);
  assert.equal((await getAchievement(key)).claimed,true);
 }
 const after=(await call('GET','/v1/auth/wallet')).json();
 assert.equal(Number(after.gold)-Number(before.gold),9000);
 assert.equal(Number(after.currencies.crystals)-Number(before.currencies.crystals),550);
 const summaryAfter=(await call('GET','/v1/social/summary')).json();
 assert.ok(targetIds.every(key=>!summaryAfter.achievementReady.some(x=>x.id===key)));
 const achievementProfile=(await call('GET','/v1/social/profile')).json();
 assert.equal(achievementProfile.titles.length,15);
 assert.ok(targetIds.every(key=>achievementProfile.titles.find(t=>t.id===key)?.unlocked));
 assert.equal((await call('POST','/v1/social/title',{titleId:'siblings_ascended'})).json().title,'Unbroken Bond');
 const pins=['siblings_ascended','eclipse_ascended','mythic_ascended'];
 assert.equal((await call('POST','/v1/social/showcase',{pins:[...pins,'first_ascension']})).statusCode,400);
 assert.equal((await call('POST','/v1/social/showcase',{pins:['siblings_ascended','siblings_ascended']})).statusCode,400);
 assert.equal((await call('POST','/v1/social/showcase',{pins:['cassien']})).statusCode,403);
 assert.equal((await call('POST','/v1/social/showcase',{pins:['unknown']})).statusCode,403);
 assert.equal((await call('POST','/v1/social/showcase',{pins})).statusCode,200);
 assert.deepEqual((await call('GET','/v1/social/profile')).json().pins,pins);
 assert.equal((await call('POST','/v1/social/showcase',{pins:[]})).statusCode,200);
 assert.deepEqual((await call('GET','/v1/social/profile')).json().pins,[]);
 console.log('PASS badge pin limit, duplicate and locked rejection, saved order and unpin');

 console.log('PASS actual seven-acquisition achievement credit, exact ascension tiers, both bonds, five one-time rewards and titles');



 console.log('PASS server summon, pity, rates, single debit, concurrent retry, account ownership, portrait unlock');
}finally{await app.close();await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end();}

