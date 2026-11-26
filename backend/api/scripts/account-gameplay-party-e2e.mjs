import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {chatRoutes} from '../src/routes/chat.ts';
import {summonRoutes} from '../src/routes/summon.ts';
import {banners} from '../src/world/summon.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:{level:'error'}}),suffix=randomBytes(4).toString('hex');
const names=['ChatPull'+suffix,'ChatWatch'+suffix],emails=names.map(n=>n.toLowerCase()+'@example.test'),password=randomBytes(16).toString('hex');
let ids=[],tokens=[];
const banner=banners.crimson_covenant,oldRates=banner.rates,oldPool=banner.pool.mythic;
try {
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(summonRoutes,{prefix:'/v1/summon'});await app.register(chatRoutes,{prefix:'/v1/chat'});
 await app.listen({host:'127.0.0.1',port:0});
 for(let i=0;i<2;i++){
  assert.equal((await app.inject({method:'POST',url:'/v1/auth/register',payload:{playerName:names[i],email:emails[i],password}})).statusCode,201);
  const login=(await app.inject({method:'POST',url:'/v1/auth/login',payload:{playerName:names[i],password}})).json();ids.push(login.player.id);tokens.push(login.accessToken);
 }
 await pool.query("UPDATE player_currencies SET balance=120 WHERE player_id=$1 AND currency_id='crystals'",[ids[0]]);
 await pool.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,'cassien_mythic') ON CONFLICT DO NOTHING",[ids[0]]);
 banner.rates={common:0,rare:0,epic:0,legendary:0,mythic:1};banner.pool.mythic=['ravienna_mythic'];
 const root=fileURLToPath(new URL('../../../',import.meta.url));
 const code=await new Promise((resolve,reject)=>{
  const p=spawn(process.env.QA_GODOT,['--headless','--path',root,'res://tools/qa_account_gameplay_party.tscn'],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:'1',QA_API:'http://127.0.0.1:'+app.server.address().port,QA_NAME:names[0],QA_PASSWORD:password}});
  p.stdout.on('data',d=>process.stdout.write(d));p.stderr.on('data',d=>process.stderr.write(d));
  const timer=setTimeout(()=>p.kill(),30000);p.on('error',reject);p.on('close',c=>{clearTimeout(timer);resolve(c)});
 });
 assert.equal(code,0);
 const history=(await app.inject({url:'/v1/chat/messages?channel=world',headers:{authorization:'Bearer '+tokens[1]}})).json();
 const notices=history.messages.filter(m=>m.kind==='mythic_summon'&&m.playerId===ids[0]);
 assert.equal(notices.length,1);assert.equal(notices[0].characterId,'ravienna_mythic');
 console.log('PASS real Godot default online Mythic summon visible to second authenticated player');
}finally{
 banner.rates=oldRates;banner.pool.mythic=oldPool;
 await app.close();await pool.query('DELETE FROM accounts WHERE email=ANY($1::text[])',[emails]);await pool.end();
}

