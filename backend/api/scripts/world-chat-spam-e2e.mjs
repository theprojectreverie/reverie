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
 const base='Recruiting adventurers for the Royal Gate';
 const variants=[base,base.toUpperCase(),'Recruiting   adventurers for the Royal Gate'];
 for(let i=0;i<3;i++){
  const r=await send(i%2?a:b,0,variants[i]);assert.equal(r.statusCode,201,r.body);await sleep(1100);
 }
 const duplicate=await send(a,0,base);
 assert.equal(duplicate.statusCode,429,duplicate.body);assert.equal(duplicate.json().error,'chat_duplicate_spam');
 await assert.rejects(pool.query("INSERT INTO recent_chat_messages(id,sender_id,channel,sender_name,avatar,title,body) VALUES(gen_random_uuid(),$1,'world',$2,'','',$3)",[ids[0],names[0],base]),/chat_duplicate_spam/);
 assert.equal((await send(b,1,base)).statusCode,201);
 await sleep(1100);
 const distinct=await send(b,0,'A different legitimate chat message');assert.equal(distinct.statusCode,201,distinct.body);
 assert.equal((await read(a,2)).json().messages.filter(m=>m.playerId===ids[0]).length,4);
 // Age only disposable fixture messages and reset only disposable budgets.
 await pool.query("UPDATE recent_chat_messages SET created_at=now()-interval '61 seconds' WHERE sender_id=$1",[ids[0]]);
 await pool.query("DELETE FROM chat_send_limits WHERE player_id=$1",[ids[0]]);
 assert.equal((await send(a,0,base)).statusCode,201);
 await pool.query("DELETE FROM chat_send_limits WHERE player_id=$1",[ids[0]]);
 for(let i=0;i<4;i++){assert.equal((await send(i%2?a:b,0,'Hi')).statusCode,201);await sleep(1100);}
 await pool.query("DELETE FROM chat_send_limits WHERE player_id=$1",[ids[0]]);
 for(let i=0;i<4;i++){assert.equal((await send(i%2?a:b,0,'[sticker:gerald_chibi]')).statusCode,201);await sleep(1100);}
 const created=await call(a,'POST','/v1/co-op/lobbies',0,{regionId:'six_zone_willow_fields',maxMembers:4});assert.equal(created.statusCode,201);lobby=created.json().lobbyId;
 await pool.query("DELETE FROM chat_send_limits WHERE player_id=$1",[ids[0]]);
 for(let i=0;i<4;i++){assert.equal((await send(i%2?a:b,0,base,'party')).statusCode,201);await sleep(1100);}
 console.log('PASS duplicate blocking across API instances, normalization, database guard, sender isolation, window expiry, distinct messages, short reactions, stickers, party privacy');
}catch(e){console.error(e);process.exitCode=1;}finally{await a.close();await b.close();if(lobby)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[lobby]);await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}