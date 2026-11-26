import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {coopRoutes} from '../src/routes/coop.ts';
import {socialRoutes} from '../src/routes/social.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}),suffix=randomBytes(5).toString('hex'),names=['A','B','C'].map(x=>'Invite'+x+suffix),emails=names.map(x=>x+'@example.test'),tokens=[],ids=[],lobbies=[];
const call=(method,url,i,payload)=>app.inject({method,url,headers:i==null?{}:{authorization:'Bearer '+tokens[i]},...(payload?{payload}:{})});
const send=(i,j)=>call('POST','/v1/co-op/friend-invites',i,{playerId:ids[j]});
const respond=(i,inviteId,action)=>call('POST','/v1/co-op/friend-invites/respond',i,{inviteId,action});
const friends=i=>call('GET','/v1/social/friends',i);
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.register(socialRoutes,{prefix:'/v1/social'});await app.ready();
 for(let i=0;i<3;i++){
 const password=randomBytes(16).toString('hex');
 assert.equal((await call('POST','/v1/auth/register',null,{email:emails[i],playerName:names[i],password})).statusCode,201);
 const r=await call('POST','/v1/auth/login',null,{playerName:names[i],password});assert.equal(r.statusCode,200);tokens.push(r.json().accessToken);ids.push(r.json().player.id);
 }
 await pool.query("INSERT INTO friendships(player_id,friend_id,status) VALUES($1,$2,'accepted'),($1,$3,'accepted')",[...ids]);
 assert.equal((await send(0,1)).statusCode,409);
 const party=await call('POST','/v1/co-op/lobbies',0,{regionId:'six_zone_willow_fields',maxMembers:2});assert.equal(party.statusCode,201);lobbies.push(party.json().lobbyId);
 let invite=await send(0,1);assert.equal(invite.statusCode,201);let id=invite.json().inviteId;
 assert.equal((await friends(1)).json().invites[0].id,id);assert.equal((await friends(2)).json().invites.length,0);
 assert.equal((await respond(2,id,'accept')).statusCode,404);
 assert.equal((await respond(1,id,'decline')).statusCode,200);assert.equal((await friends(1)).json().invites.length,0);
 id=(await send(0,1)).json().inviteId;await pool.query("UPDATE co_op_friend_invites SET expires_at=now()-interval '1 second' WHERE id=$1",[id]);assert.equal((await respond(1,id,'accept')).statusCode,404);
 id=(await send(0,1)).json().inviteId;const id2=(await send(0,2)).json().inviteId;
 const result=await respond(1,id,'accept');assert.equal(result.statusCode,200);assert.equal(result.json().lobbyId,lobbies[0]);
 assert.equal((await respond(2,id2,'accept')).statusCode,409);assert.equal((await respond(1,id,'accept')).statusCode,404);
 assert.equal((await send(1,2)).statusCode,409);
 assert.equal((await call('GET','/v1/co-op/lobbies/current',1)).json().lobby.members.length,2);
 console.log('PASS party invite consent, recipient isolation, decline, expiry, acceptance, replay, capacity and leadership');
}catch(e){console.error(e);process.exitCode=1;}finally{await app.close();for(const id of lobbies)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[id]);await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}