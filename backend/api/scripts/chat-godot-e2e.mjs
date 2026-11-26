import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {chatRoutes} from '../src/routes/chat.ts';
import {coopRoutes} from '../src/routes/coop.ts';
import {socialRoutes} from '../src/routes/social.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}), suffix=randomBytes(5).toString('hex'),names=['A','B'].map(n=>'Chat'+n+suffix), emails=names.map(n=>n.toLowerCase()+'@example.test'),passwords=names.map(()=>randomBytes(16).toString('hex'));
function worker(i){return new Promise((resolve,reject)=>{const root=fileURLToPath(new URL('../../../',import.meta.url));const p=spawn(process.env.QA_GODOT,['--headless','--path',root,'res://tools/qa_chat_client.tscn'],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:'1',QA_API:'http://127.0.0.1:'+app.server.address().port,QA_NAME:names[i],QA_PEER_NAME:names[1-i],QA_PASSWORD:passwords[i],QA_ROLE:i?'B':'A'}});let out='';p.stdout.on('data',d=>out+=d);p.stderr.on('data',d=>out+=d);const timer=setTimeout(()=>p.kill(),90000);p.on('error',reject);p.on('close',code=>{clearTimeout(timer);console.log('CLIENT',i,code,out);resolve(code)});});}
try{await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(chatRoutes,{prefix:'/v1/chat'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.register(socialRoutes,{prefix:'/v1/social'});await app.listen({host:'127.0.0.1',port:0});for(let i=0;i<2;i++){const r=await app.inject({method:'POST',url:'/v1/auth/register',payload:{email:emails[i],playerName:names[i],password:passwords[i]}});assert.equal(r.statusCode,201);}const players=(await pool.query('SELECT id FROM players WHERE name=ANY($1) ORDER BY name',[names])).rows;
await pool.query("INSERT INTO friendships(player_id,friend_id,status) VALUES($1,$2,'accepted')",[players[0].id,players[1].id]);
await pool.query("INSERT INTO private_chat_messages(id,sender_id,recipient_id,body) VALUES($1,$2,$3,$4)",[randomUUID(),players[0].id,players[1].id,'Offline delivery QA']);
assert.deepEqual(await Promise.all([worker(0),worker(1)]),[0,0]);const invites=await pool.query('SELECT id FROM co_op_friend_invites WHERE sender_id=$1 AND recipient_id=$2',[players[0].id,players[1].id]);assert.equal(invites.rowCount,1);console.log('PASS both Godot chat clients and persisted party invitation');}catch(e){console.error(e);process.exitCode=1;}finally{await app.close();await pool.query('DELETE FROM co_op_lobbies WHERE leader_player_id IN (SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE a.email=ANY($1))',[emails]);await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}
