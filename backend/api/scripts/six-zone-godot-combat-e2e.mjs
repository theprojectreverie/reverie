import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import websocket from '@fastify/websocket';
import {randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {coopRoutes} from '../src/routes/coop.ts';
import {realtimeRoutes} from '../src/routes/realtime.ts';
import assert from 'node:assert/strict';
const region=process.argv[2] ?? "six_zone_royal_gardens";
const app=Fastify({logger:false}), suffix=randomBytes(5).toString('hex'), names=[`QaA${suffix}`,`QaB${suffix}`], emails=names.map(n=>`${n.toLowerCase()}@example.test`), passwords=names.map(()=>randomBytes(16).toString('hex')), tokens=[];let lobby='';
async function call(path,body,token){const r=await app.inject({method:'POST',url:path,payload:body,headers:token?{authorization:`Bearer ${token}`}:{}});assert.ok(r.statusCode<300,`${path}: ${r.statusCode} ${r.json().error??''}`);return r.json();}
function worker(i,port){return new Promise((resolve,reject)=>{const root=fileURLToPath(new URL('../../../',import.meta.url));const child=spawn(process.env.QA_GODOT,['--headless','--path',root,'res://tools/qa_coop_combat.tscn'],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:'1',QA_API:`http://127.0.0.1:${port}`,QA_WS:`ws://127.0.0.1:${port}/v1/realtime`,QA_NAME:names[i],QA_PASSWORD:passwords[i],QA_LOBBY:lobby,QA_REGION:region,QA_ROLE:i===0?'A':'B'}});let output='';child.stdout.on('data',d=>output+=d);child.stderr.on('data',d=>output+=d);const timer=setTimeout(()=>child.kill(),30000);child.on('error',e=>{clearTimeout(timer);reject(e)});child.on('close',code=>{clearTimeout(timer);console.log(`CLIENT ${i+1} EXIT ${code}\n${output}`);resolve(code);});});}
try {await app.register(jwt,{secret:config.JWT_SECRET});await app.register(websocket);await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.register(realtimeRoutes,{prefix:'/v1'});await app.listen({host:'127.0.0.1',port:0});for(let i=0;i<2;i++){await call('/v1/auth/register',{email:emails[i],playerName:names[i],password:passwords[i]});tokens.push((await call('/v1/auth/login',{playerName:names[i],password:passwords[i]})).accessToken);}const created=await call('/v1/co-op/lobbies',{regionId:region,maxMembers:4},tokens[0]);lobby=created.lobbyId;await call('/v1/co-op/lobbies/join',{inviteCode:created.inviteCode},tokens[1]);const codes=await Promise.all([worker(0,app.server.address().port),worker(1,app.server.address().port)]);assert.deepEqual(codes,[0,0]);console.log('PASS both actual Godot clients');}catch(e){console.error('FAIL',e.message);process.exitCode=1;}finally{if(lobby){for(const t of tokens.slice().reverse()){try{await call(`/v1/co-op/lobbies/${lobby}/leave`,{},t);}catch{}}}await app.close();if(lobby)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[lobby]);await pool.query('DELETE FROM accounts WHERE email = ANY($1)',[emails]);await pool.end();console.log('Test fixtures cleaned');}