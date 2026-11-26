import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {socialRoutes} from '../src/routes/social.ts';
import {chatRoutes} from '../src/routes/chat.ts';
import {coopRoutes} from '../src/routes/coop.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}), suffix=randomBytes(5).toString('hex'),names=['A','B'].map(n=>'Chat'+n+suffix), emails=names.map(n=>n.toLowerCase()+'@example.test'),passwords=names.map(()=>randomBytes(16).toString('hex'));
function worker(i){return new Promise((resolve,reject)=>{const root=fileURLToPath(new URL('../../../',import.meta.url));const p=spawn(process.env.QA_GODOT,['--headless','--path',root,'res://tools/qa_social_client.tscn'],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:'1',QA_API:'http://127.0.0.1:'+app.server.address().port,QA_NAME:names[i],QA_PASSWORD:passwords[i],QA_ROLE:i?'B':'A',QA_OTHER:names[1-i]}});let out='';p.stdout.on('data',d=>out+=d);p.stderr.on('data',d=>out+=d);const timer=setTimeout(()=>p.kill(),60000);p.on('error',reject);p.on('close',code=>{clearTimeout(timer);console.log('CLIENT',i,code,out);resolve(code)});});}
let ownsSeason=false;
try{await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(socialRoutes,{prefix:'/v1/social'});await app.register(chatRoutes,{prefix:'/v1/chat'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.listen({host:'127.0.0.1',port:0});for(let i=0;i<2;i++){const r=await app.inject({method:'POST',url:'/v1/auth/register',payload:{email:emails[i],playerName:names[i],password:passwords[i]}});assert.equal(r.statusCode,201);}if(process.env.QA_SEASON_FIXTURE==='1'){
 const result=await pool.query("INSERT INTO online_season_finalizations(season_start) VALUES('2002-01-01') ON CONFLICT DO NOTHING RETURNING season_start");
 assert.equal(result.rowCount,1,'QA season must not preexist');ownsSeason=true;
 const players=(await pool.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE a.email=ANY($1)",[emails])).rows;
 for(const player of players)await pool.query("INSERT INTO online_season_results(season_start,player_id,category,score,rank,gold) VALUES('2002-01-01',$1,'combat',2,1,1000)",[player.id]);
 for(const player of players)await pool.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) SELECT $1,'gold',15,15,'coop_monster_defeat','monster','qa','qa-season-challenge:'||n FROM generate_series(1,10) n",[player.id]);

 }
 assert.deepEqual(await Promise.all([worker(0),worker(1)]),[0,0]);if(ownsSeason){
 const paid=(await pool.query("SELECT count(*)::int count FROM online_season_results WHERE season_start='2002-01-01' AND claimed_at IS NOT NULL")).rows[0].count;
 assert.equal(paid,2);
 const challengePaid=(await pool.query("SELECT count(*)::int count FROM currency_ledger cl JOIN players p ON p.id=cl.player_id JOIN accounts a ON a.id=p.account_id WHERE a.email=ANY($1) AND cl.reason='online_season_challenge' AND cl.delta=150",[emails])).rows[0].count;
 assert.equal(challengePaid,2);

 console.log('PASS both UI claims persisted');
 }console.log('PASS both Godot social clients');}catch(e){console.error(e);process.exitCode=1;}finally{await app.close();await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);if(ownsSeason)await pool.query("DELETE FROM online_season_finalizations WHERE season_start='2002-01-01'");await pool.end();}
