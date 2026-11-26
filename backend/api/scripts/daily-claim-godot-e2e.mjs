import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import {randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {dailyQuestRoutes} from '../src/routes/daily-quests.ts';
import {socialRoutes} from '../src/routes/social.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false});const name='QaDailyUi'+randomBytes(5).toString('hex'),email=name.toLowerCase()+'@example.test',password=randomBytes(16).toString('hex');
try{
 await app.register(jwt,{secret:config.JWT_SECRET,sign:{expiresIn:config.ACCESS_TOKEN_TTL_SECONDS}});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(dailyQuestRoutes,{prefix:'/v1/daily-quests'});await app.register(socialRoutes,{prefix:'/v1/social'});await app.listen({host:'127.0.0.1',port:0});
 const reg=await app.inject({method:'POST',url:'/v1/auth/register',payload:{email,playerName:name,password}});assert.equal(reg.statusCode,201,reg.body);
 const cwd=fileURLToPath(new URL('../../../',import.meta.url));
 const code=await new Promise((resolve,reject)=>{const child=spawn(process.env.QA_GODOT,['--headless','--path',cwd,'--script','res://tools/qa_daily_claim_client.gd'],{cwd,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:'1',QA_API:'http://127.0.0.1:'+app.server.address().port,QA_NAME:name,QA_PASSWORD:password}});let output='';child.stdout.on('data',d=>output+=d);child.stderr.on('data',d=>output+=d);const timer=setTimeout(()=>child.kill(),60000);child.on('error',e=>{clearTimeout(timer);reject(e)});child.on('close',code=>{clearTimeout(timer);console.log(output);resolve(code)});});assert.equal(code,0);
 const q=await pool.query("SELECT count(*)::int AS n,sum(l.delta)::int AS gold FROM currency_ledger l JOIN players p ON p.id=l.player_id JOIN accounts a ON a.id=p.account_id WHERE a.email=$1 AND l.reason='online_daily_quest' AND l.ref_id LIKE '%:checkin'",[email]);assert.deepEqual(q.rows[0],{n:1,gold:150});console.log('PASS actual Godot client and database ledger agree');
}finally{await app.close();await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end();console.log('Isolated test account cleaned');}
