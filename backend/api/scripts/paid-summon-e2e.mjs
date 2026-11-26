import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {summonRoutes} from '../src/routes/summon.ts';
import {banners,emptyPity,rollBanner} from '../src/world/summon.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
for(const banner of Object.values(banners)){
 const forced=rollBanner(banner,emptyPity(),10,()=>0,90);assert.equal(forced.results.length,10);assert.equal(forced.results[9].rarity,'legendary');assert.equal(forced.results[9].paid_guaranteed,true);assert.ok(banner.featured.includes(forced.results[9].character_id));assert.equal(forced.results[9].featured,true);assert.ok(!forced.results[9].kind);assert.equal(forced.results.filter(x=>x.paid_guaranteed).length,1);
 const crossing=rollBanner(banner,emptyPity(),10,()=>0,97);assert.equal(crossing.results[2].paid_guaranteed,true);assert.ok(banner.featured.includes(crossing.results[2].character_id));
 assert.ok(!rollBanner(banner,emptyPity(),10,()=>0).results.some(x=>x.paid_guaranteed));
 assert.ok(!rollBanner(banner,emptyPity(),10,()=>0,89).results.some(x=>x.paid_guaranteed));
 const naturallyMythic=rollBanner(banner,emptyPity(),1,()=>0.999,99);assert.ok(banner.featured.includes(naturallyMythic.results[0].character_id));assert.equal(naturallyMythic.results[0].featured,true);assert.equal(naturallyMythic.results[0].paid_guaranteed,true);
}
console.log('PASS all banner milestones, crossing batches, free exclusion and exact featured character even on natural Mythic rolls');
const app=Fastify({logger:false}),name='QaPaid'+randomBytes(5).toString('hex'),email=name.toLowerCase()+'@example.test',password=randomBytes(16).toString('hex');let token='',id='';
const call=(method,url,payload)=>app.inject({method,url,headers:token?{authorization:'Bearer '+token}:{},...(payload?{payload}:{})});
async function state(){const r=await call('GET','/v1/summon/state');assert.equal(r.statusCode,200,r.body);return r.json();}
const ids=Object.keys(banners);const make=(bannerId,count,currency)=>({bannerId,count,currency,requestId:randomUUID()});
async function pull(p){const r=await call('POST','/v1/summon/pull',p);assert.equal(r.statusCode,200,r.body);return r.json();}
try{
 // Idempotent, additive schema migration; does not grant existing accounts any currency.
 await pool.query(readFileSync(new URL('../../migrations/030_paid_moonstone_summon.sql',import.meta.url),'utf8'));
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(summonRoutes,{prefix:'/v1/summon'});
 assert.equal((await call('POST','/v1/auth/register',{playerName:name,email,password})).statusCode,201);
 const login=(await call('POST','/v1/auth/login',{playerName:name,password})).json();token=login.accessToken;id=login.player.id;
 assert.equal((await state()).paidProgress,0);assert.equal((await call('POST','/v1/summon/pull',make(ids[0],10,'paid_moonstones'))).statusCode,409);
 await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'paid_moonstones',24000),($1,'crystals',2400) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=EXCLUDED.balance",[id]);
 for(let i=0;i<9;i++){const r=await pull(make(ids[i%ids.length],10,'paid_moonstones'));assert.equal(r.paidProgress,(i+1)*10);assert.ok(!r.results.some(x=>x.paid_guaranteed));}
 const ordinary=await pull(make(ids[0],10,'crystals'));assert.equal(ordinary.paidProgress,90);assert.ok(!ordinary.results.some(x=>x.paid_guaranteed));
 const p=make(ids[1],10,'paid_moonstones');const pair=await Promise.all([pull(p),pull(p)]);assert.deepEqual(pair[0].results,pair[1].results);assert.equal(pair.filter(x=>x.replayed).length,1);
 const final=pair.find(x=>!x.replayed);assert.equal(final.paidProgress,0);const guaranteed=final.results[9];assert.ok(guaranteed.paid_guaranteed);assert.ok(['legendary','mythic'].includes(guaranteed.rarity)&&!guaranteed.kind);assert.ok(banners[ids[1]].featured.includes(guaranteed.character_id));assert.equal(guaranteed.featured,true);assert.equal(pair[0].paidProgress,0);assert.equal(pair[1].paidProgress,0);
 const saved=await state();assert.equal(saved.paidProgress,0);assert.equal(saved.currencies.paid_moonstones,'12000');assert.equal(saved.currencies.crystals,'1200');assert.ok(saved.roster.some(x=>x.char_id===guaranteed.character_id));
 assert.equal((await call('POST','/v1/summon/pull',{...p,currency:'crystals'})).statusCode,409);
 for(let i=0;i<10;i++){
  const r=await pull(make(ids[2],10,'paid_moonstones'));
  assert.equal(r.paidProgress,((i+1)*10)%100);
  const guaranteed=r.results.filter(x=>x.paid_guaranteed);
  assert.equal(guaranteed.length,i===9?1:0);
  if(i===9){assert.equal(guaranteed[0].character_id,banners[ids[2]].featured[0]);assert.equal(guaranteed[0].featured,true);}
 }
 const finalState=await state();
 assert.equal(finalState.paidProgress,0);assert.equal(finalState.currencies.paid_moonstones,'0');
 assert.ok(finalState.roster.some(x=>x.char_id===banners[ids[2]].featured[0]));
 const history=async(path="/v1/summon/history")=>{const r=await call("GET",path);assert.equal(r.statusCode,200,r.body);return r.json();};
 const page=await history("/v1/summon/history?limit=10&currency=paid_moonstones");
 assert.equal(page.entries.length,10);assert.equal(page.paidProgress,0);assert.ok(page.nextCursor);
 assert.equal(page.entries[0].results.length,10);assert.ok(page.entries[0].results.some(r=>r.paid_guaranteed&&r.featured));
 assert.ok(page.entries.every(r=>r.currency==="paid_moonstones"&&r.spent==="1200"));
 const page2=await history("/v1/summon/history?limit=10&currency=paid_moonstones&before="+page.nextCursor);
 assert.equal(page2.entries.length,10);assert.equal(page2.nextCursor,null);
 assert.equal(new Set([...page.entries,...page2.entries].map(r=>r.id)).size,20);
 const free=await history("/v1/summon/history?currency=crystals");assert.equal(free.entries.length,1);
 assert.equal((await call("GET","/v1/summon/history?limit=100")).statusCode,400);
 assert.equal((await call("GET","/v1/summon/history?playerId="+id)).statusCode,400);
 assert.equal((await app.inject({url:"/v1/summon/history"})).statusCode,401);
 const otherName="QaOther"+randomBytes(4).toString("hex"),otherEmail=otherName.toLowerCase()+"@example.test";
 try{
  assert.equal((await app.inject({method:"POST",url:"/v1/auth/register",payload:{playerName:otherName,email:otherEmail,password}})).statusCode,201);
  const other=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName:otherName,password}})).json();
  const headers={authorization:"Bearer "+other.accessToken};
  const h=await app.inject({url:"/v1/summon/history",headers});assert.equal(h.statusCode,200,h.body);assert.deepEqual(h.json().entries,[]);
  assert.equal((await app.inject({url:"/v1/summon/history?before="+page.nextCursor,headers})).statusCode,400);
 }finally{await pool.query("DELETE FROM accounts WHERE email=$1",[otherEmail]);}
 console.log("PASS history pagination, filters, exact spend, featured markers, authentication and cross-account isolation");
 const auditPath="/v1/summon/guarantee-audit",reviewPath="/v1/summon/guarantee-review";
 const audit=async()=>{const r=await call("GET",auditPath);assert.equal(r.statusCode,200,r.body);return r.json();};
 const clean=await audit();assert.equal(clean.totalPaidPulls,200);assert.equal(clean.historyComplete,true);assert.equal(clean.expectedMilestones,2);assert.deepEqual(clean.cases.map(c=>[c.milestone,c.status]),[[100,"fulfilled"],[200,"fulfilled"]]);
 const first=clean.cases[0],second=clean.cases[1];
 assert.equal((await call("POST",reviewPath,{pullId:first.pullId,rollIndex:first.rollIndex})).statusCode,404);
 // Change only disposable fixture history to reproduce the legacy bug.
 await pool.query("UPDATE gacha_pull_results SET featured=false WHERE pull_id=$1 AND roll_index=$2",[first.pullId,first.rollIndex]);
 await pool.query("UPDATE gacha_pull_results SET featured=false,reward_items=reward_items-'paid_guaranteed' WHERE pull_id=$1 AND roll_index=$2",[second.pullId,second.rollIndex]);
 const report=await audit();assert.deepEqual(report.cases.map(c=>c.status),["missed_featured","needs_review"]);
 const req={pullId:first.pullId,rollIndex:first.rollIndex};
 const reviews=await Promise.all([call("POST",reviewPath,req),call("POST",reviewPath,req)]);
 assert.ok(reviews.every(r=>r.statusCode===200));assert.deepEqual(reviews[0].json(),reviews[1].json());
 assert.equal((await audit()).cases[0].reviewStatus,"pending_review");
 assert.equal((await call("POST",reviewPath,{...req,rollIndex:0})).statusCode,404);
 assert.equal((await app.inject({url:auditPath})).statusCode,401);
 const otherName2="QaAudit"+randomBytes(4).toString("hex"),otherEmail2=otherName2.toLowerCase()+"@example.test";
 try{
  assert.equal((await app.inject({method:"POST",url:"/v1/auth/register",payload:{playerName:otherName2,email:otherEmail2,password}})).statusCode,201);
  const other=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName:otherName2,password}})).json();
  const headers={authorization:"Bearer "+other.accessToken};
  const foreign=await app.inject({url:auditPath,headers});assert.equal(foreign.statusCode,200);assert.deepEqual(foreign.json().cases,[]);
  assert.equal((await app.inject({method:"POST",url:reviewPath,headers,payload:req})).statusCode,404);
 }finally{await pool.query("DELETE FROM accounts WHERE email=$1",[otherEmail2]);}
 const reviewsDb=await pool.query("SELECT count(*)::int AS n FROM paid_guarantee_reviews WHERE pull_id=$1",[first.pullId]);assert.equal(reviewsDb.rows[0].n,1);
 const after=await state();assert.deepEqual(after,finalState);
 console.log("PASS paid guarantee audit, legacy missed featured, missing marker review, duplicate review protection, account isolation and no balance or roster mutation");
 const debits=await pool.query("SELECT count(*)::int AS n,COALESCE(sum(delta),0)::int AS amount FROM currency_ledger WHERE player_id=$1 AND currency_id='paid_moonstones' AND reason='gacha_pull'",[id]);assert.deepEqual(debits.rows[0],{n:20,amount:-24000});
 console.log('PASS 200 paid pulls and two exact featured guarantees, cross-banner counter, ordinary-pull exclusion, owned character, exact debit, concurrent idempotency, replay marker and currency mismatch rejection');
}finally{await app.close();await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end();console.log('Isolated fixture removed; no real account balances changed');}
