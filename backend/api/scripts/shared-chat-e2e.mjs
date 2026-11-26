import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {chatRoutes} from '../src/routes/chat.ts';
import {coopRoutes} from '../src/routes/coop.ts';
assert.equal(config.NODE_ENV,'development');
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const a=Fastify(),b=Fastify(),suffix=randomBytes(5).toString('hex'),names=['A','B','C'].map(n=>'Share'+n+suffix),emails=names.map(n=>n+'@example.test'),ids=[],tokens=[];
let lobby='';
const call=(app,method,url,i,payload)=>app.inject({method,url,headers:i==null?{}:{authorization:'Bearer '+tokens[i]},...(payload?{payload}:{})});
const send=(app,i,text,channel='world',replyTo)=>call(app,'POST','/v1/chat/messages',i,{channel,text,...(replyTo?{replyTo}:{})});
const read=(app,i,channel='world')=>call(app,'GET','/v1/chat/messages?channel='+channel,i);
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
try{
 for(const app of [a,b]){await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(chatRoutes,{prefix:'/v1/chat'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.ready();}
 for(let i=0;i<3;i++){const password=randomBytes(16).toString('hex');assert.equal((await call(a,'POST','/v1/auth/register',null,{email:emails[i],playerName:names[i],password})).statusCode,201);const r=await call(a,'POST','/v1/auth/login',null,{playerName:names[i],password});assert.equal(r.statusCode,200);ids.push(r.json().player.id);tokens.push(r.json().accessToken);}
 const racing=await Promise.all([send(a,0,'Concurrent A'),send(b,0,'Concurrent B')]);assert.deepEqual(racing.map(r=>r.statusCode).sort(),[201,429]);
 const parent=racing.find(r=>r.statusCode===201).json().message;
 assert.ok((await read(b,1)).json().messages.some(m=>m.id===parent.id));
 const answer=await send(b,1,'Cross instance reply','world',parent.id);assert.equal(answer.statusCode,201,answer.body);
 assert.ok((await read(a,0)).json().messages.some(m=>m.replyTo===parent.id));
 const created=await call(a,'POST','/v1/co-op/lobbies',0,{regionId:'six_zone_willow_fields',maxMembers:4});assert.equal(created.statusCode,201);lobby=created.json().lobbyId;
 assert.ok((await call(b,'POST','/v1/co-op/lobbies/join',1,{inviteCode:created.json().inviteCode})).statusCode<300);
 await sleep(1100);
 const party=await send(a,0,'[sticker:gerald_chibi]','party');assert.equal(party.statusCode,201,party.body);
 assert.ok((await read(b,1,'party')).json().messages.some(m=>m.id===party.json().message.id));
 assert.equal((await read(b,2,'party')).statusCode,403);
 assert.equal((await send(b,2,'leak','world',party.json().message.id)).statusCode,400);
 assert.ok((await call(b,'POST','/v1/co-op/lobbies/'+lobby+'/leave',1,{})).statusCode<300);
 assert.equal((await read(a,1,'party')).statusCode,403);
 await pool.query("UPDATE recent_chat_messages SET created_at=now()-interval '31 minutes' WHERE id=$1",[parent.id]);
 assert.ok(!(await read(b,1)).json().messages.some(m=>m.id===parent.id));
 assert.equal((await send(b,2,'expired','world',parent.id)).statusCode,400);
 await call(a,'POST','/v1/chat/block',2,{playerId:ids[0]});
 assert.ok(!(await read(b,2)).json().messages.some(m=>m.playerId===ids[0]));
 console.log('PASS cross-instance world/party delivery, atomic concurrent throttle, shared reply references, isolation, expiry and blocking');
}catch(e){console.error(e);process.exitCode=1;}finally{await a.close();await b.close();if(lobby)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[lobby]);await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}