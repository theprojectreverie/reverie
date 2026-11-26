import Fastify from "fastify";
import jwt from "@fastify/jwt";
import assert from "node:assert/strict";
import {randomBytes,randomUUID} from "node:crypto";
import {spawn} from "node:child_process";
import {fileURLToPath} from "node:url";
import {config} from "../src/config.ts";
import {pool} from "../src/db.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {summonRoutes} from "../src/routes/summon.ts";
import {socialRoutes} from "../src/routes/social.ts";
import {banners} from "../src/world/summon.ts";
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}), name="PaidUI"+randomBytes(4).toString("hex"),email=name.toLowerCase()+"@example.test",password=randomBytes(16).toString("hex");
try{
 await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(authRoutes,{prefix:"/v1/auth"});
 await app.register(summonRoutes,{prefix:"/v1/summon"});
 await app.register(socialRoutes,{prefix:"/v1/social"});
 await app.listen({host:"127.0.0.1",port:0});
 assert.equal((await app.inject({method:"POST",url:"/v1/auth/register",payload:{playerName:name,email,password}})).statusCode,201);
 const login=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName:name,password}})).json();
 const id=login.player.id;
 await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'paid_moonstones',12000),($1,'crystals',1200) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=EXCLUDED.balance",[id]);
 const bannerId=Object.keys(banners)[0];
 for(let i=0;i<7;i++){
  const r=await app.inject({method:"POST",url:"/v1/summon/pull",headers:{authorization:"Bearer "+login.accessToken},payload:{bannerId,count:10,currency:"paid_moonstones",requestId:randomUUID()}});
  assert.equal(r.statusCode,200,r.body);
 }
 const root=fileURLToPath(new URL("../../../",import.meta.url));
 const launch=async(stage)=>new Promise((resolve,reject)=>{
  const p=spawn(process.env.QA_GODOT,["--headless","--path",root,"res://tools/qa_paid_repeat.tscn"],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:"1",QA_API:"http://127.0.0.1:"+app.server.address().port,QA_NAME:name,QA_PASSWORD:password,QA_PAID_STAGE:stage}});
  p.stdout.on("data",d=>process.stdout.write(d));p.stderr.on("data",d=>process.stderr.write(d));
  const timer=setTimeout(()=>p.kill(),45000);p.on("error",reject);p.on("close",c=>{clearTimeout(timer);resolve(c)});
 });
 assert.equal(await launch("first"),0);
 assert.equal(await launch("second"),0);
 const r=await pool.query("SELECT r.character_id,r.featured FROM gacha_pull_results r JOIN gacha_pulls p ON p.id=r.pull_id WHERE p.player_id=$1 AND r.reward_items @> $2::jsonb",[id,JSON.stringify({paid_guaranteed:true})]);
 assert.deepEqual(r.rows,[{character_id:banners[bannerId].featured[0],featured:true}]);
 console.log("PASS database confirms exact featured reward after real client repeat");
}finally{await app.close();await pool.query("DELETE FROM accounts WHERE email=$1",[email]);await pool.end();}
