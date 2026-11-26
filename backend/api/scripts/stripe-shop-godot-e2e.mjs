import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import {randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {summonRoutes} from '../src/routes/summon.ts';
import {socialRoutes} from '../src/routes/social.ts';
import {makeShopRoutes,SANDBOX_PRICES,TEST_PACKAGES} from '../src/routes/shop.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}),name='QaShopUI'+randomBytes(4).toString('hex'),email=name.toLowerCase()+'@example.test',password=randomBytes(16).toString('hex');
const manual=process.env.QA_STRIPE_MANUAL==='1';
let fixtureSession=null;let sequence=0;
const provider={checkout:{sessions:{async create(params){const pack=TEST_PACKAGES.find(p=>SANDBOX_PRICES[p.id]===params.line_items[0].price);assert.ok(pack);fixtureSession={id:'cs_test_ui_manual_'+(++sequence),mode:'payment',livemode:false,status:'open',payment_status:'unpaid',currency:'eur',amount_total:pack.amountCents,metadata:params.metadata,client_reference_id:params.client_reference_id,payment_intent:'pi_ui_manual_'+sequence,url:null};return structuredClone(fixtureSession);},async retrieve(id){assert.equal(id,fixtureSession.id);if(!(process.env.QA_STRIPE_CANCEL==='1'&&sequence===1)&&fixtureSession.status!=='expired'){fixtureSession.status='complete';fixtureSession.payment_status='paid';}return structuredClone(fixtureSession);},async expire(id){assert.equal(id,fixtureSession.id);assert.equal(fixtureSession.status,'open');fixtureSession.status='expired';return structuredClone(fixtureSession);}}}};
try{
 await app.register(jwt,{secret:config.JWT_SECRET,sign:{expiresIn:config.ACCESS_TOKEN_TTL_SECONDS}});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(summonRoutes,{prefix:'/v1/summon'});await app.register(socialRoutes,{prefix:'/v1/social'});await app.register(makeShopRoutes(manual?provider:null,''),{prefix:'/v1/shop'});await app.listen({host:'127.0.0.1',port:0});
 const r=await app.inject({method:'POST',url:'/v1/auth/register',payload:{playerName:name,email,password}});assert.equal(r.statusCode,201,r.body);
 const cwd=fileURLToPath(new URL('../../../',import.meta.url));
 const code=await new Promise((resolve,reject)=>{const child=spawn(process.env.QA_GODOT,['--path',cwd,'--script','res://tools/qa_stripe_shop_client.gd','--resolution','1280x720','--rendering-method','gl_compatibility'],{cwd,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:'1',QA_API:'http://127.0.0.1:'+app.server.address().port,QA_NAME:name,QA_PASSWORD:password}});let out='';child.stdout.on('data',d=>out+=d);child.stderr.on('data',d=>out+=d);const timer=setTimeout(()=>child.kill(),45000);child.on('error',reject);child.on('close',code=>{clearTimeout(timer);console.log(out);resolve(code)});});assert.equal(code,0);if(manual){const q=await pool.query("SELECT count(*)::int AS n,sum(l.delta)::int AS amount FROM currency_ledger l JOIN players p ON p.id=l.player_id JOIN accounts a ON a.id=p.account_id WHERE a.email=$1 AND l.reason='stripe_sandbox_purchase'",[email]);assert.deepEqual(q.rows[0],{n:1,amount:600});console.log('PASS Godot manual verification and database agree: one 600-Moonstone credit');}
}finally{await app.close();await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end();}
