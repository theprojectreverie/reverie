import assert from "node:assert/strict";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {randomBytes} from "node:crypto";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {staffRoutes,staffOwners} from "../src/routes/staff.ts";
import {developerRoutes} from "../src/routes/developer.ts";
import {authRoutes} from "../src/routes/auth.ts";
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname)&&config.NODE_ENV!=="production");
const app=Fastify(),emails=[],ids=[],suffix=randomBytes(4).toString("hex");
try{
 await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(authRoutes,{prefix:"/v1/auth"});await app.register(staffRoutes,{prefix:"/v1/developer/staff"});await app.register(developerRoutes);
 await app.ready();
 assert.equal(staffOwners.size,1);
 const owner=(await pool.query("SELECT a.id,a.token_version,p.id AS player_id,p.name FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=$1 AND a.status='active'",[[...staffOwners][0]])).rows[0];
 assert.ok(owner);
 const ownerToken=app.jwt.sign({sub:owner.id,playerId:owner.player_id,tokenVersion:owner.token_version});
 async function create(n){
  const name="StaffQA"+suffix+n,email=name.toLowerCase()+"@example.test",password=randomBytes(16).toString("hex");emails.push(email);
  assert.equal((await app.inject({method:"POST",url:"/v1/auth/register",payload:{email,playerName:name,password}})).statusCode,201);
  const login=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName:name,password}})).json();
  const id=(await pool.query("SELECT id FROM accounts WHERE email=$1",[email])).rows[0].id;ids.push(id);
  return {name,token:login.accessToken,id};
 }
 const a=await create(1),b=await create(2);
 const request=(token,url,payload)=>app.inject({method:payload?"POST":"GET",url,headers:token?{authorization:"Bearer "+token}:{},...(payload?{payload}:{})});
 const staff=(token,payload)=>request(token,"/v1/developer/staff/",payload);
 const activity=token=>request(token,"/v1/developer/activity");
 const change=(name,role)=>({playerName:name,role,note:"Automated permission QA"});
 assert.equal((await staff(null)).statusCode,401);
 assert.equal((await staff(a.token)).statusCode,403);
 assert.equal((await activity(a.token)).statusCode,403);
 assert.equal((await staff(ownerToken,change(owner.name,"revoke"))).statusCode,409);
 assert.equal((await staff(ownerToken,change(a.name,"analyst"))).statusCode,200);
 const allowed=await activity(a.token);assert.equal(allowed.statusCode,200);assert.equal(allowed.json().staffManagement,false);
 assert.equal((await staff(a.token,change(b.name,"admin"))).statusCode,403);
 assert.equal((await staff(ownerToken,change(a.name,"admin"))).statusCode,200);
 assert.equal((await staff(a.token)).statusCode,403);
 assert.equal((await staff(ownerToken,change(a.name,"admin"))).json().changed,false);
 assert.equal((await staff(ownerToken,change(a.name,"revoke"))).statusCode,200);
 assert.equal((await activity(a.token)).statusCode,403);
 const auditResponse=await staff(ownerToken);assert.equal(auditResponse.statusCode,200,auditResponse.body);const audit=auditResponse.json().audit.filter(x=>x.target===a.name);
 assert.equal(audit.length,3);
 assert.deepEqual(audit.map(x=>[x.previous_role,x.new_role]),[["admin",null],["analyst","admin"],[null,"analyst"]]);
 assert.equal((await activity(ownerToken)).json().staffManagement,true);
 console.log("PASS owner protected, role grant, update, duplicate prevention, no privilege escalation, immediate revocation, durable audit");
}finally{await app.close();await pool.query("DELETE FROM reverie_staff_audit WHERE target_account_id=ANY($1::uuid[])",[ids]);await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end()}