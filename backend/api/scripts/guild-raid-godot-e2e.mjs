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
assert.equal(config.NODE_ENV,'development');
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
assert.ok(process.env.QA_GODOT&&process.env.REVERIE_STORY_GODOT);
const app=Fastify(),suffix=randomBytes(4).toString('hex'),names=['A','B'].map(n=>'RaidUI'+n+suffix),emails=names.map(n=>n+'@example.test'),passwords=names.map(()=>randomBytes(16).toString('hex')),ids=[],tokens=[];
let guild='';
const req=(method,path,i,payload)=>app.inject({method,url:'/v1/guilds'+path,headers:{authorization:'Bearer '+tokens[i]},...(payload?{payload}:{})});
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(guildRoutes,{prefix:'/v1/guilds'});await app.listen({host:'127.0.0.1',port:0});
 for(let i=0;i<2;i++){
  const r=await app.inject({method:'POST',url:'/v1/auth/register',payload:{email:emails[i],playerName:names[i],password:passwords[i]}});assert.equal(r.statusCode,201,r.body);
  const l=await app.inject({method:'POST',url:'/v1/auth/login',payload:{playerName:names[i],password:passwords[i]}});assert.equal(l.statusCode,200,l.body);ids.push(l.json().player.id);tokens.push(l.json().accessToken);
 }
 const g=await req('POST','/create',0,{name:'RaidUI '+suffix,description:'QA',emblem:'moon'});assert.equal(g.statusCode,201,g.body);guild=g.json().guildId;
 assert.equal((await req('POST','/invite',0,{playerId:ids[1]})).statusCode,200);
 assert.equal((await req('POST','/invitation',1,{guildId:guild,accept:true})).statusCode,200);
 // Test-only fixture: one strong party and the last 100 HP of the shared raid.
 await pool.query("INSERT INTO owned_characters(player_id,char_id,level,ascension,awakening) SELECT $1,unnest($2::text[]),80,3,5 ON CONFLICT(player_id,char_id) DO UPDATE SET level=80,ascension=3,awakening=5",[ids[0],['kael','gerald','lilith']]);
 await pool.query("INSERT INTO guild_raids(guild_id,week_start,hp) VALUES($1,date_trunc('week',now() AT TIME ZONE 'UTC')::date,100)",[guild]);
 const root=fileURLToPath(new URL('../../../',import.meta.url));
 const exit=await new Promise((resolve,reject)=>{
  const p=spawn(process.env.QA_GODOT,['--headless','--path',root,'res://tools/qa_guild_raid_client.tscn'],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:'1',QA_API:'http://127.0.0.1:'+app.server.address().port,QA_NAME:names[0],QA_PASSWORD:passwords[0]}});
  let out='';p.stdout.on('data',d=>out+=d);p.stderr.on('data',d=>out+=d);
  const timer=setTimeout(()=>p.kill(),120000);
  p.on('error',reject);p.on('close',code=>{clearTimeout(timer);console.log(out);resolve(code===0&&out.includes('GUILD_RAID_CLIENT_PASS')&&!/SCRIPT ERROR:|^ERROR:/m.test(out)?0:1);});
 });
 assert.equal(exit,0);
 const peer=(await req('GET','/me',1)).json().raid;
 assert.equal(peer.hp,0);assert.equal(peer.damage,0);assert.equal(peer.canClaim,false);assert.equal(peer.ranking[0].damage,100);
 const attempts=await pool.query("SELECT count(*)::int AS n,sum(damage)::int AS damage FROM guild_raid_attempts WHERE player_id=$1",[ids[0]]);
 assert.deepEqual(attempts.rows[0],{n:1,damage:100});
 const ledger=await pool.query("SELECT currency_id,delta::int FROM currency_ledger WHERE player_id=$1 AND reason='guild_raid_reward' ORDER BY currency_id",[ids[0]]);
 assert.deepEqual(ledger.rows,[{currency_id:'crystals',delta:50},{currency_id:'gold',delta:500}]);
 console.log('PASS real Godot raid panel, persistent resume, reward ledger and peer-visible ranking');
}catch(e){console.error(e);process.exitCode=1;}finally{await app.close();if(guild)await pool.query('DELETE FROM guilds WHERE id=$1',[guild]);await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();}