import assert from "node:assert/strict";
import {randomUUID,randomBytes} from "node:crypto";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {pool} from "../dist/db.js";
import {config} from "../dist/config.js";
import {ownerRewardRoutes} from "../dist/routes/owner-rewards.js";
assert.ok(config.NODE_ENV==="development"&&["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify(),ids=[],emails=[],requests=[];
try{
 const users=[];
 for(let i=0;i<2;i++){
  const name="GrantQA"+randomBytes(4).toString("hex"),email=name.toLowerCase()+"@example.test",password=randomBytes(18).toString("hex");
  emails.push(email);
  const r=await fetch("http://127.0.0.1:8787/v1/auth/register",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({playerName:name,email,password})});
  assert.equal(r.status,201);
  const row=(await pool.query("SELECT a.id,p.id AS player,a.token_version FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.email=$1",[email])).rows[0];
  assert.ok(row);ids.push(row.id);users.push({...row,name});
 }
 await app.register(jwt,{secret:"disposable-owner-grants-test-secret-12345"});
 await app.register(ownerRewardRoutes(new Set([users[0].id])),{prefix:"/rewards"});
 const token=(u,version=u.token_version)=>app.jwt.sign({sub:u.id,playerId:u.player,tokenVersion:version});
 const call=(u,path,body,version)=>app.inject({url:"/rewards/"+path,method:body?"POST":"GET",headers:{authorization:"Bearer "+token(u,version)},...(body?{payload:body}:{})});
 assert.equal((await app.inject({url:"/rewards/history"})).statusCode,401);
 assert.equal((await call(users[1],"history")).statusCode,403);
 assert.equal((await call(users[0],"history",undefined,users[0].token_version+1)).statusCode,401);
 assert.equal((await call(users[0],"players?q="+users[1].name)).json().players[0].id,users[1].player);
 for(const currency of ["gems","crystals","paid_moonstones","gold"]){
  const target=currency==="gems"?users[0]:users[1];
  const before=BigInt((await pool.query("SELECT balance FROM player_currencies WHERE player_id=$1 AND currency_id=$2",[target.player,currency])).rows[0].balance);
  const grant={requestId:randomUUID(),targetId:target.player,currency,amount:123,note:"Disposable owner reward QA"};requests.push(grant.requestId);
  assert.equal((await call(users[1],"grant",grant)).statusCode,403);
  assert.equal((await call(users[0],"grant",{...grant,amount:-1})).statusCode,400);
  const results=await Promise.all([call(users[0],"grant",grant),call(users[0],"grant",grant)]);
  for(const r of results)assert.equal(r.statusCode,200,r.body);
  assert.equal(results.filter(r=>r.json().replayed).length,1);
  assert.equal((await call(users[0],"grant",{...grant,amount:124})).statusCode,409);
  const after=BigInt((await pool.query("SELECT balance FROM player_currencies WHERE player_id=$1 AND currency_id=$2",[target.player,currency])).rows[0].balance);
  assert.equal(after,before+123n);
  const ledger=(await pool.query("SELECT reason,delta FROM currency_ledger WHERE player_id=$1 AND idempotency_key=$2",[target.player,"owner-grant:"+grant.requestId])).rows;
  assert.equal(ledger.length,1);assert.equal(ledger[0].reason,"owner_admin_grant");assert.equal(ledger[0].delta,"123");
 }
 const history=(await call(users[0],"history")).json().grants;assert.ok(requests.every(id=>history.some(r=>r.request_id===id)));
 console.log("PASS self-grant, other-player grants, four currencies, owner-only permission, revoked session, concurrent retries, ledger and grant history");
}finally{await app.close();await pool.query("DELETE FROM reverie_currency_grants WHERE request_id=ANY($1::uuid[])",[requests]);await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end()}