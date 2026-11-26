import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {randomBytes,randomUUID} from 'node:crypto';
import {pool} from '../src/db.ts';
import {config} from '../src/config.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {makePaymentReviewRoutes} from '../src/routes/payment-review.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const auth=Fastify({logger:false}),app=Fastify({logger:false});const names=['QaPayAdmin','QaPayPlayer'].map(s=>s+randomBytes(4).toString('hex'));const emails=names.map(s=>s.toLowerCase()+'@example.test');const passwords=names.map(()=>randomBytes(16).toString('hex'));let tokens=[],ids=[],accounts=[];
try{
 await pool.query(readFileSync(new URL('../../migrations/048_payment_review_decisions.sql',import.meta.url),'utf8'));
 await auth.register(jwt,{secret:config.JWT_SECRET});await auth.register(authRoutes,{prefix:'/v1/auth'});
 for(let i=0;i<2;i++){const r=await auth.inject({method:'POST',url:'/v1/auth/register',payload:{playerName:names[i],email:emails[i],password:passwords[i]}});assert.equal(r.statusCode,201,r.body);const a=(await auth.inject({method:'POST',url:'/v1/auth/login',payload:{playerName:names[i],password:passwords[i]}})).json();tokens.push(a.accessToken);ids.push(a.player.id);accounts.push((await pool.query('SELECT account_id FROM players WHERE id=$1',[ids[i]])).rows[0].account_id);}
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(makePaymentReviewRoutes(accounts[0]),{prefix:'/review'});await app.register(makePaymentReviewRoutes(''),{prefix:'/closed'});
 const req=(url,token=tokens[0],method='GET')=>app.inject({method,url,headers:token?{authorization:'Bearer '+token}:{}});
 const own=[];for(let i=0;i<3;i++){const o=(await pool.query("INSERT INTO stripe_sandbox_orders(player_id,request_id,package_id,stones,amount_cents,currency,status,refunded_cents,dispute_seen,review_reason,created_at) VALUES($1,$2,'moon_120',120,120,'eur','refund_review',40,true,'payment_dispute','2099-01-01T00:00:00.123456Z') RETURNING id",[ids[1],randomUUID()])).rows[0];own.push(o.id);}
 const before=(await pool.query('SELECT id,status,refunded_cents FROM stripe_sandbox_orders WHERE player_id=$1 ORDER BY id',[ids[1]])).rows;
 assert.equal((await req('/review/reviews','')).statusCode,401);assert.equal((await req('/review/reviews',tokens[1])).statusCode,403);assert.equal((await req('/closed/reviews')).statusCode,403);assert.equal((await req('/review/reviews?limit=101')).statusCode,400);assert.equal((await req('/review/reviews?beforeId='+own[0])).statusCode,400);
 const page=await req('/review/reviews?limit=2');assert.equal(page.statusCode,200,page.body);assert.equal(page.headers['cache-control'],'no-store');const first=page.json();assert.equal(first.readOnly,true);assert.equal(first.testMode,true);assert.ok(first.nextCursor);assert.ok(first.reviews.every(r=>own.includes(r.id)&&r.refunded_cents===40&&r.dispute_seen&&r.purchase_entries===0&&r.reversal_entries===0&&!('session_id' in r)&&!('payment_intent_id' in r)));const next=await req('/review/reviews?limit=1&'+new URLSearchParams(first.nextCursor));assert.equal(next.statusCode,200,next.body);assert.ok(own.includes(next.json().reviews[0].id));assert.ok(!first.reviews.some(r=>r.id===next.json().reviews[0].id));
 const dash=await req('/review/dashboard','');assert.equal(dash.statusCode,200);assert.match(dash.headers['content-security-policy'],/frame-ancestors 'none'/);assert.ok(dash.body.includes('Decisions are audit notes only'));assert.ok(!dash.body.includes(own[0]));assert.equal((await req('/review/reviews',tokens[0],'POST')).statusCode,404);
 const target=first.reviews[0],body={orderId:target.id,requestId:randomUUID(),evidenceKey:target.evidenceKey,action:'escalate',note:'Investigate recorded dispute.'};
 const decide=(payload,token=tokens[0])=>app.inject({method:'POST',url:'/review/decisions',headers:token?{authorization:'Bearer '+token}:{},payload});
 assert.equal((await decide(body,'')).statusCode,401);assert.equal((await decide(body,tokens[1])).statusCode,403);assert.equal((await decide({...body,note:'short'})).statusCode,400);assert.equal((await decide({...body,evidenceKey:'0'.repeat(64)})).statusCode,409);
 const race=await Promise.all([decide(body),decide(body)]);assert.ok(race.every(r=>r.statusCode===200),race.map(r=>r.body).join(' '));assert.equal(race[0].json().decision.id,race[1].json().decision.id);assert.deepEqual(race.map(r=>r.json().replayed).sort(),[false,true]);assert.equal((await decide({...body,note:'Different note for same request.'})).statusCode,409);assert.equal((await decide({...body,requestId:randomUUID()})).statusCode,409);
 const self=(await pool.query("INSERT INTO stripe_sandbox_orders(player_id,request_id,package_id,stones,amount_cents,currency,status,refunded_cents,review_reason) VALUES($1,$2,'moon_120',120,120,'eur','refund_review',40,'partial_refund') RETURNING id",[ids[0],randomUUID()])).rows[0];assert.equal((await decide({...body,orderId:self.id,requestId:randomUUID()})).statusCode,403);
 const after=(await req('/review/reviews?limit=2')).json().reviews.find(r=>r.id===target.id);assert.equal(after.currentDecision.action,'escalate');assert.equal(after.decisions.length,1);
 await pool.query('UPDATE stripe_sandbox_orders SET refunded_cents=80 WHERE id=$1',[target.id]);const changed=(await req('/review/reviews?limit=2')).json().reviews.find(r=>r.id===target.id);assert.equal(changed.currentDecision,null);assert.equal(changed.decisions.length,1);assert.equal((await decide({...body,requestId:randomUUID()})).statusCode,409);assert.equal((await decide({...body,requestId:randomUUID(),evidenceKey:changed.evidenceKey,action:'reviewed_no_adjustment',note:'Reviewed updated refund amount.'})).statusCode,200);
 assert.equal((await pool.query('SELECT count(*)::int AS n FROM stripe_sandbox_review_decisions WHERE order_id=$1',[target.id])).rows[0].n,2);
 // Restore only the fixture provider evidence; no operator decision may touch the wallet or order.
 await pool.query('UPDATE stripe_sandbox_orders SET refunded_cents=40 WHERE id=$1',[target.id]);
 assert.equal((await pool.query("SELECT count(*)::int AS n FROM currency_ledger WHERE player_id=$1 AND currency_id='paid_moonstones'",[ids[1]])).rows[0].n,0);
 console.log('PASS decision authorization, self-review denial, idempotent concurrent retry, stale evidence, append-only audit and no wallet mutation');
 await pool.query('UPDATE accounts SET token_version=token_version+1 WHERE id=$1',[accounts[0]]);assert.equal((await req('/review/reviews')).statusCode,401);
 assert.deepEqual((await pool.query('SELECT id,status,refunded_cents FROM stripe_sandbox_orders WHERE player_id=$1 ORDER BY id',[ids[1]])).rows,before);
 console.log('PASS review admin authorization, fail-closed allowlist, expired token, cursor pagination at tied microsecond timestamp, no secrets, CSP, read-only data integrity');
}finally{await app.close();await auth.close();await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}
