import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {coopRoutes} from '../src/routes/coop.ts';
assert.equal(config.NODE_ENV,'development');
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const count=16, suffix=randomBytes(4).toString('hex'), names=Array.from({length:count},(_,i)=>'Load'+i+suffix),emails=names.map(n=>n+'@example.test'),ids=[],tokens=[],lobbies=[],workers=[],latencies=[];
const app=Fastify({logger:false});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const call=(method,url,i,payload)=>app.inject({method,url,headers:i==null?{}:{authorization:'Bearer '+tokens[i]},...(payload?{payload}:{})});
async function startWorker(){
 const child=spawn(process.execPath,['--env-file=.env','--import','tsx',fileURLToPath(new URL('./shared-chat-worker.mjs',import.meta.url))],{stdio:['pipe','pipe','pipe']});
 const w={child,port:0,pid:0};workers.push(w);
 child.stderr.on('data',d=>process.stderr.write(d));
 return await new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(new Error('worker startup timeout')),15000);
  child.once('error',e=>{clearTimeout(timer);reject(e);});
  child.once('exit',code=>{clearTimeout(timer);if(!w.port)reject(new Error('worker exited '+code));});
  const lines=createInterface({input:child.stdout});
  lines.on('line',line=>{try{const info=JSON.parse(line);if(info.ready){w.port=info.port;w.pid=info.pid;clearTimeout(timer);resolve(w);}}catch{console.log(line);}});
 });
}
async function stopWorker(w){
 if(w.child.exitCode!==null)return;
 await new Promise(resolve=>{const timer=setTimeout(()=>w.child.kill(),5000);w.child.once('exit',()=>{clearTimeout(timer);resolve();});w.child.stdin.end();});
}
async function request(w,i,method,path,payload){
 const start=performance.now();
 const r=await fetch('http://127.0.0.1:'+w.port+'/v1/chat'+path,{method,headers:{authorization:'Bearer '+tokens[i],'content-type':'application/json'},...(payload?{body:JSON.stringify(payload)}:{}),signal:AbortSignal.timeout(10000)});
 const body=await r.json();latencies.push(performance.now()-start);
 return {status:r.status,body};
}
const send=(w,i,text,channel='party',replyTo)=>request(w,i,'POST','/messages',{channel,text,...(replyTo?{replyTo}:{})});
const read=(w,i,channel='party')=>request(w,i,'GET','/messages?channel='+channel);
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.ready();
 for(let i=0;i<count;i++){
  const password=randomBytes(16).toString('hex');const registration=await call('POST','/v1/auth/register',null,{email:emails[i],playerName:names[i],password});assert.equal(registration.statusCode,201,registration.body);
  const login=await call('POST','/v1/auth/login',null,{playerName:names[i],password});assert.equal(login.statusCode,200,login.body);ids.push(login.json().player.id);tokens.push(login.json().accessToken);
 }
 for(let i=0;i<count;i+=4){
  const c=await call('POST','/v1/co-op/lobbies',i,{regionId:'six_zone_willow_fields',maxMembers:4});assert.equal(c.statusCode,201,c.body);lobbies.push(c.json().lobbyId);
  for(let j=1;j<4;j++){const r=await call('POST','/v1/co-op/lobbies/join',i+j,{inviteCode:c.json().inviteCode});assert.ok(r.statusCode<300,r.body);}
 }
 let [a,b]=await Promise.all([startWorker(),startWorker()]);
 assert.notEqual(a.pid,b.pid);console.log('Two independent API processes ready; 16 disposable players in four private parties');
 const idsByParty=Array.from({length:count/4},()=>new Set());
 for(let round=0;round<5;round++){
  const replies=await Promise.all(ids.map((_,i)=>send(i%2?a:b,i,'Load '+round+' '+i)));
  replies.forEach((r,i)=>{assert.equal(r.status,201,JSON.stringify(r.body));idsByParty[Math.floor(i/4)].add(r.body.message.id);});
  const reads=await Promise.all(ids.map((_,i)=>read(i%2?b:a,i)));
  reads.forEach((r,i)=>{assert.equal(r.status,200,JSON.stringify(r.body));const expected=idsByParty[Math.floor(i/4)];assert.equal(r.body.messages.length,expected.size);assert.ok(r.body.messages.every(m=>expected.has(m.id)));});
  if(round<4)await sleep(1100);
 }
 const bursts=await Promise.all(ids.flatMap((_,i)=>[send(a,i,'Spam A'),send(b,i,'Spam B')]));
 assert.ok(bursts.every(r=>r.status===429),'burst limit bypass');
 const before=await read(a,0);assert.equal(before.body.messages.length,20);
 await stopWorker(a);a=await startWorker();
 const restored=await read(a,0);assert.deepEqual(restored.body.messages.map(m=>m.id),before.body.messages.map(m=>m.id));
 const stillLimited=await send(a,0,'Restart bypass');assert.equal(stillLimited.status,429);
 const parent=before.body.messages[0];
 await sleep(10500);
 const reply=await send(b,1,'Restart reply','party',parent.id);assert.equal(reply.status,201,JSON.stringify(reply.body));assert.ok((await read(a,0)).body.messages.some(m=>m.replyTo===parent.id));
 const expired=before.body.messages[1];
 await pool.query("UPDATE recent_chat_messages SET created_at=now()-interval '31 minutes' WHERE id=$1",[expired.id]);
 assert.ok(!(await read(b,0)).body.messages.some(m=>m.id===expired.id));
 // Remove only the deliberately expired fixture, not existing players' records.
 const removed=await pool.query("DELETE FROM recent_chat_messages WHERE id=$1 AND created_at<now()-interval '30 minutes' RETURNING id",[expired.id]);assert.equal(removed.rowCount,1);
 const sorted=latencies.slice().sort((x,y)=>x-y);
 console.log(JSON.stringify({players:count,parties:4,requests:sorted.length,acceptedPartyMessages:81,p50Ms:Math.round(sorted[Math.floor(sorted.length*.5)]),p95Ms:Math.round(sorted[Math.floor(sorted.length*.95)]),maxMs:Math.round(sorted.at(-1)),pass:true}));
 console.log('PASS independent processes, concurrent party isolation, distributed burst limits, restart recovery and expiry');
}catch(e){console.error(e);process.exitCode=1;}finally{
 await Promise.all(workers.map(stopWorker));await app.close();
 for(const id of lobbies)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[id]);
 await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);await pool.end();
}