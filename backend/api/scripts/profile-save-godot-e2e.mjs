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
function worker(i){return new Promise((resolve,reject)=>{const root=fileURLToPath(new URL('../../../',import.meta.url));const p=spawn(process.env.QA_GODOT,['--headless','--path',root,'res://tools/qa_profile_save_regression.tscn'],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:'1',QA_API:'http://127.0.0.1:'+app.server.address().port,QA_NAME:names[i],QA_PASSWORD:passwords[i],QA_ROLE:i?'B':'A',QA_OTHER:names[1-i]}});let out='';p.stdout.on('data',d=>out+=d);p.stderr.on('data',d=>out+=d);const timer=setTimeout(()=>p.kill(),60000);p.on('error',reject);p.on('close',code=>{clearTimeout(timer);console.log('CLIENT',i,code,out);resolve(code)});});}
try{await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(socialRoutes,{prefix:'/v1/social'});await app.register(chatRoutes,{prefix:'/v1/chat'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.listen({host:'127.0.0.1',port:0});for(let i=0;i<2;i++){const r=await app.inject({method:'POST',url:'/v1/auth/register',payload:{email:emails[i],playerName:names[i],password:passwords[i]}});assert.equal(r.statusCode,201);const owner=await pool.query("SELECT id FROM players WHERE name=$1",[names[i]]);await pool.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,$2)",[owner.rows[0].id,i?'ravienna_mythic':'ravienna']);}assert.deepEqual(await Promise.all([worker(0),worker(1)]),[0,0]);console.log('PASS both Godot social clients');}catch(e){console.error(e);process.exitCode=1;}finally{await app.close();await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}
