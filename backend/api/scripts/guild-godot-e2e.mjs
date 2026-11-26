import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {pool} from '../src/db.ts';
import {config} from '../src/config.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {guildRoutes} from '../src/routes/guilds.ts';
import {chatRoutes} from '../src/routes/chat.ts';
import {socialRoutes} from '../src/routes/social.ts';
assert.equal(config.NODE_ENV,'development');
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify(),suffix=randomBytes(4).toString('hex'),names=['A','B'].map(n=>'Guild'+n+suffix),emails=names.map(n=>n+'@example.test'),passwords=names.map(()=>randomBytes(16).toString('hex')),guildName='Moon '+suffix;
function worker(i){return new Promise((resolve,reject)=>{
 const root=fileURLToPath(new URL('../../../',import.meta.url));
 const p=spawn(process.env.QA_GODOT,['--headless','--path',root,'res://tools/qa_guild_client.tscn'],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:'1',QA_API:'http://127.0.0.1:'+app.server.address().port,QA_NAME:names[i],QA_PASSWORD:passwords[i],QA_ROLE:i?'B':'A',QA_GUILD:guildName}});
 let out='';p.stdout.on('data',d=>out+=d);p.stderr.on('data',d=>out+=d);const timer=setTimeout(()=>p.kill(),60000);
 p.on('error',reject);p.on('close',code=>{clearTimeout(timer);console.log('CLIENT',i,code,out);resolve(code===0&&!/SCRIPT ERROR:|^ERROR:/m.test(out)?0:1)});
});}
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(socialRoutes,{prefix:'/v1/social'});await app.register(guildRoutes,{prefix:'/v1/guilds'});await app.register(chatRoutes,{prefix:'/v1/chat'});await app.listen({host:'127.0.0.1',port:0});
 for(let i=0;i<2;i++){const r=await app.inject({method:'POST',url:'/v1/auth/register',payload:{email:emails[i],playerName:names[i],password:passwords[i]}});assert.equal(r.statusCode,201,r.body);}
 await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) SELECT id,'gold',500 FROM players WHERE name=$1 ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=500",[names[0]]);
 assert.deepEqual(await Promise.all([worker(0),worker(1)]),[0,0]);
 const r=await pool.query("SELECT count(*)::int AS n FROM guild_members m JOIN guilds g ON g.id=m.guild_id WHERE g.name=$1",[guildName]);assert.equal(r.rows[0].n,2);console.log('PASS both Godot guild clients and persistent membership');
}catch(e){console.error(e);process.exitCode=1;}finally{await app.close();await pool.query("DELETE FROM guilds WHERE name=$1",[guildName]);await pool.query("DELETE FROM accounts WHERE email=ANY($1)",[emails]);await pool.end();}