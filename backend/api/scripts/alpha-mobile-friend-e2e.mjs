import assert from 'node:assert/strict';
import {randomBytes,createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {pool} from '../dist/db.js';
import {config} from '../dist/config.js';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const base='https://reverie.tailad29fa.ts.net:8443',emails=[],hashes=[],players=[];
const req=(path,body,token)=>fetch(base+path,{method:body?'POST':'GET',headers:{...(body?{'content-type':'application/json'}:{}),...(token?{authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(15000)});
try{
 for(let i=0;i<2;i++){
  const playerName='FriendQA'+randomBytes(4).toString('hex'),email=playerName+'@example.test',password=randomBytes(16).toString('hex'),inviteCode=randomBytes(32).toString('base64url'),hash=createHash('sha256').update(inviteCode).digest('hex');
  emails.push(email);hashes.push(hash);
  await pool.query("INSERT INTO reverie_alpha_invites(token_hash,expires_at) VALUES($1,now()+interval '15 minutes')",[hash]);
  assert.equal((await req('/v1/auth/register',{playerName,email,password,inviteCode})).status,201);
  const login=await req('/v1/auth/login',{playerName,password});assert.equal(login.status,200);
  players.push({...await login.json(),playerName,password});
 }
 const [a,b]=players;
 assert.equal((await req('/v1/social/friends',{playerId:b.player.id,action:'request'},a.accessToken)).status,200);
 const root=fileURLToPath(new URL('../../../',import.meta.url));
 const code=await new Promise((resolve,reject)=>{
 const p=spawn(process.env.QA_GODOT,['--headless','--path',root,'--resolution','1280x720','res://tools/qa_mobile_friend_accept.tscn'],{cwd:root,env:{...process.env,QA_API:base,QA_NAME:b.playerName,QA_PASSWORD:b.password,REVERIE_E2E_DISABLE_LOCAL_SAVE:'1'}});
 const timer=setTimeout(()=>p.kill(),45000);p.stdout.on('data',d=>process.stdout.write(d));p.stderr.on('data',d=>process.stderr.write(d));p.on('error',reject);p.on('close',c=>{clearTimeout(timer);resolve(c)});
 });
 assert.equal(code,0);
 for(const p of players){const r=await req('/v1/social/friends',undefined,p.accessToken);assert.equal(r.status,200);assert.equal((await r.json()).friends[0].status,'accepted')}
 console.log('PASS accepted relationship visible to both remote accounts');
}finally{await pool.query('DELETE FROM reverie_alpha_invites WHERE token_hash=ANY($1::text[])',[hashes]);await pool.query('DELETE FROM accounts WHERE email=ANY($1::text[])',[emails]);await pool.end()}