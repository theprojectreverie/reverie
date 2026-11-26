import assert from 'node:assert/strict';
import {randomBytes,createHash} from 'node:crypto';
import {once} from 'node:events';
import {pool} from '../dist/db.js';
import {config} from '../dist/config.js';
import WebSocket from 'ws';
import Fastify from 'fastify';
import jwt from '@fastify/jwt';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const base='https://reverie.tailad29fa.ts.net:8443',emails=[],hashes=[],peers=[];let lobby='';
const req=(path,payload,token)=>fetch(base+path,{method:payload===undefined?'GET':'POST',headers:{...(payload===undefined?{}:{'content-type':'application/json'}),...(token?{authorization:'Bearer '+token}:{})},...(payload===undefined?{}:{body:JSON.stringify(payload)}),signal:AbortSignal.timeout(20000)});
try{
 assert.equal((await (await req('/health')).json()).gameplayOpen,true);
 for(const p of ['/developer','/v1/developer/activity','/v1/shop/catalog','/ready','/v1/game-servers'])assert.equal((await req(p)).status,404,p);
 const players=[];
 for(let i=0;i<2;i++){
  const playerName='TunnelQA'+randomBytes(4).toString('hex'),email=playerName+'@example.test',password=randomBytes(16).toString('hex'),inviteCode=randomBytes(32).toString('base64url');
  const hash=createHash('sha256').update(inviteCode).digest('hex');emails.push(email);hashes.push(hash);
  await pool.query("INSERT INTO reverie_alpha_invites(token_hash,expires_at) VALUES($1,now()+interval '15 minutes')",[hash]);
  const registration=await req('/v1/auth/register',{playerName,email,password,inviteCode});assert.equal(registration.status,201,'registration '+registration.status);
  const login=await req('/v1/auth/login',{playerName,password});assert.equal(login.status,200,'login '+login.status);players.push(await login.json());
 }
 const [a,b]=players;
 assert.equal((await req('/v1/auth/wallet',undefined,a.accessToken)).status,200);
 const chat=await req('/v1/chat/messages',{channel:'world',text:'Temporary alpha tunnel QA'},a.accessToken);assert.equal(chat.status,201);
 const messages=await req('/v1/chat/messages?channel=world',undefined,b.accessToken);assert.equal(messages.status,200);assert.ok((await messages.json()).messages.some(m=>m.playerId===a.player.id));
 const create=await req('/v1/co-op/lobbies',{regionId:'six_zone_willow_fields',maxMembers:4},a.accessToken);assert.equal(create.status,201);const room=await create.json();lobby=room.lobbyId;
 assert.ok((await req('/v1/co-op/lobbies/join',{inviteCode:room.inviteCode},b.accessToken)).status<300);
 for(const p of players){const ws=new WebSocket(base.replace('https:','wss:')+'/v1/realtime?lobbyId='+lobby,{headers:{Authorization:'Bearer '+p.accessToken},handshakeTimeout:10000});peers.push(ws);await once(ws,'open')}
 assert.equal(peers.filter(w=>w.readyState===WebSocket.OPEN).length,2);
 if(config.PUBLIC_ALPHA_MONITOR_ENABLED==="1"){
  // Local operator-only check; no credentials or player identifiers are logged.
  const ids=[...config.DEVELOPER_ACCOUNT_IDS.split(','),...config.STAFF_OWNER_ACCOUNT_IDS.split(',')].map(x=>x.trim()).filter(x=>/^[0-9a-f-]{36}$/i.test(x));
  const owner=(await pool.query("SELECT a.id,p.id AS player,a.token_version FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=ANY($1::uuid[]) AND a.status='active' LIMIT 1",[ids])).rows[0];
  assert.ok(owner,'configured active developer account required');
  const signer=Fastify();
  try{
   await signer.register(jwt,{secret:config.JWT_SECRET});
   const token=signer.jwt.sign({sub:owner.id,playerId:owner.player,tokenVersion:owner.token_version},{expiresIn:60});
   const r=await fetch('http://127.0.0.1:8787/v1/developer/server-health',{headers:{authorization:'Bearer '+token},signal:AbortSignal.timeout(10000)});
   assert.equal(r.status,200);const a=(await r.json()).alpha;
   assert.equal(a.network.public.state,'open');
   assert.ok(a.realtime.connections>=2);assert.ok(a.realtime.players>=2);assert.ok(a.realtime.lobbies>=1);
   console.log('PASS dashboard counts actual live public co-op sockets and distinct players');
  }finally{await signer.close()}
 }
 console.log('PASS live HTTPS registration, login, wallet, world chat, two authenticated WSS connections, admin/payment isolation');
}finally{for(const ws of peers)ws.terminate();if(lobby)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[lobby]);await pool.query('DELETE FROM reverie_alpha_invites WHERE token_hash=ANY($1::text[])',[hashes]);await pool.query('DELETE FROM accounts WHERE email=ANY($1::text[])',[emails]);await pool.end()}
