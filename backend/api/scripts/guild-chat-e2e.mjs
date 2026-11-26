import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {pool} from '../src/db.ts';
import {config} from '../src/config.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {guildRoutes} from '../src/routes/guilds.ts';
import {chatRoutes} from '../src/routes/chat.ts';
assert.equal(config.NODE_ENV,'development');
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const a=Fastify(),b=Fastify(),suffix=randomBytes(4).toString('hex'),emails=[],ids=[],tokens=[],guilds=[];
const call=(app,method,url,i,payload)=>app.inject({method,url,headers:i==null?{}:{authorization:'Bearer '+tokens[i]},...(payload?{payload}:{})});
const guild=(i,path,payload)=>call(a,'POST','/v1/guilds'+path,i,payload);
const send=(app,i,guildId,text,replyTo)=>call(app,'POST','/v1/chat/messages',i,{channel:'guild',guildId,text,...(replyTo?{replyTo}:{})});
const read=(app,i)=>call(app,'GET','/v1/chat/messages?channel=guild',i);
try{
 for(const app of [a,b]){await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(guildRoutes,{prefix:'/v1/guilds'});await app.register(chatRoutes,{prefix:'/v1/chat'});await app.ready();}
 for(let i=0;i<4;i++){const name='GChat'+i+suffix,email=name+'@example.test',password=randomBytes(16).toString('hex');emails.push(email);const r=await call(a,'POST','/v1/auth/register',null,{email,playerName:name,password});assert.equal(r.statusCode,201,r.body);const l=await call(a,'POST','/v1/auth/login',null,{playerName:name,password});assert.equal(l.statusCode,200,l.body);ids.push(l.json().player.id);tokens.push(l.json().accessToken);}
 for(const i of [0,2]){const r=await guild(i,'/create',{name:'GChat '+i+' '+suffix,description:'QA',emblem:'moon'});assert.equal(r.statusCode,201,r.body);guilds.push(r.json().guildId);}
 const [g,h]=guilds;
 assert.equal((await read(a,3)).statusCode,403);
 assert.equal((await send(b,3,g,'intruder')).statusCode,403);
 assert.equal((await send(b,2,g,'wrong guild')).statusCode,403);
 const old=await send(a,0,g,'Before joining');assert.equal(old.statusCode,201,old.body);
 assert.equal((await guild(0,'/invite',{playerId:ids[1]})).statusCode,200);
 assert.equal((await guild(1,'/invitation',{guildId:g,accept:true})).statusCode,200);
 assert.equal((await read(b,1)).json().messages.length,0);
 assert.equal((await send(b,1,g,'reply to old',old.json().message.id)).statusCode,400);
 const sticker=await send(b,1,g,'[sticker:gerald_chibi]');assert.equal(sticker.statusCode,201,sticker.body);
 assert.ok((await read(a,0)).json().messages.some(m=>m.id===sticker.json().message.id));
 assert.equal((await read(a,2)).json().messages.length,0);
 assert.equal((await send(a,2,h,'Cross guild reply',sticker.json().message.id)).statusCode,400);
 const world=await call(b,'GET','/v1/chat/messages?channel=world',2);assert.ok(!world.json().messages.some(m=>m.id===sticker.json().message.id));
 await new Promise(r=>setTimeout(r,1100));
 const reply=await send(a,0,g,'Guild reply',sticker.json().message.id);assert.equal(reply.statusCode,201,reply.body);
 assert.ok((await read(b,1)).json().messages.some(m=>m.replyTo===sticker.json().message.id));
 assert.equal((await call(b,'POST','/v1/chat/block',1,{playerId:ids[0]})).statusCode,200);
 assert.ok(!(await read(b,1)).json().messages.some(m=>m.playerId===ids[0]));
 assert.equal((await guild(0,'/kick',{playerId:ids[1]})).statusCode,200);
 assert.equal((await read(b,1)).statusCode,403);assert.equal((await send(b,1,g,'after kick')).statusCode,403);
 assert.equal((await guild(2,'/invite',{playerId:ids[1]})).statusCode,200);
 assert.equal((await guild(1,'/invitation',{guildId:h,accept:true})).statusCode,200);
 assert.equal((await send(b,1,g,'stale guild')).statusCode,403);
 assert.equal((await read(b,1)).json().messages.length,0);
 console.log('PASS guild chat cross-instance delivery, membership history, replies, stickers, block filtering, kick revocation and stale-guild protection');
}catch(e){console.error(e);process.exitCode=1;}finally{await a.close();await b.close();for(const g of guilds)await pool.query('DELETE FROM guilds WHERE id=$1',[g]);await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}