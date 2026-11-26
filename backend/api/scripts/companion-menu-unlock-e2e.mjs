import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {socialRoutes} from "../src/routes/social.ts";
import {startStoryBattle,actStoryBattle,abandonStoryBattle} from "../src/world/story-combat-service.ts";
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname)&&config.NODE_ENV!=="production");
assert.ok(process.env.REVERIE_STORY_GODOT);
const app=Fastify({logger:false}),emails=[],suffix=randomBytes(5).toString("hex");
async function create(i){
 const playerName="CompQA"+suffix+i,email=playerName.toLowerCase()+"@example.test",password=randomBytes(16).toString("hex");
 emails.push(email);
 assert.equal((await app.inject({method:"POST",url:"/v1/auth/register",payload:{email,playerName,password}})).statusCode,201);
 const login=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName,password}})).json();
 return {id:login.player.id,token:login.accessToken,playerName,password};
}
async function tx(fn){
 const db=await pool.connect();
 try{await db.query("BEGIN");const result=await fn(db);await db.query("COMMIT");return result;}
 catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
}
const call=(account,method="GET",payload)=>app.inject({method,url:"/v1/social/menu-character",headers:{authorization:"Bearer "+account.token},...(payload?{payload}:{})});
async function locked(account){
 const result=await call(account);assert.equal(result.statusCode,200);assert.ok(!result.json().choices.includes("elathra"));
 assert.equal((await call(account,"POST",{character:"elathra"})).statusCode,403);
}
try{
 await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(authRoutes,{prefix:"/v1/auth"});
 await app.register(socialRoutes,{prefix:"/v1/social"});
 await app.ready();
 const a=await create(0),b=await create(1);
 await locked(a);await locked(b);
 await pool.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,'elathra')",[b.id]);
 await locked(b);
 // QA-only max-level starter. Production progression and enemy content are unchanged.
 await pool.query("INSERT INTO owned_characters(player_id,char_id,level,ascension,awakening) VALUES($1,'kael',80,3,5) ON CONFLICT(player_id,char_id) DO UPDATE SET level=80,ascension=3,awakening=5",[a.id]);
 const retreat=await tx(db=>startStoryBattle(db,a.id,"tutorial_fairy_spar"));assert.ok(retreat.ok,JSON.stringify(retreat));
 await locked(a);
 assert.ok((await tx(db=>abandonStoryBattle(db,a.id,retreat.battleId))).ok);
 await locked(a);
 let r=await tx(db=>startStoryBattle(db,a.id,"tutorial_fairy_spar"));assert.ok(r.ok,JSON.stringify(r));
 await locked(a);
 const battle=r.battleId;
 for(let n=1;n<=30&&r.view.status==="active";n++){
  const actor=r.view.units.find(u=>u.uid===r.view.actorUid),foe=r.view.units.find(u=>u.team===1&&u.hp>0);
  const action={kind:"skill",actorUid:actor.uid,skillId:actor.skills[0],targetUids:[foe.uid]};
  r=await tx(db=>actStoryBattle(db,a.id,battle,n,action));assert.ok(r.ok,JSON.stringify(r));
 }
 assert.equal(r.view.status,"victory");assert.equal(r.rewards,null);
 const choices=(await call(a)).json().choices;assert.ok(choices.includes("elathra"));
 assert.equal((await call(a,"POST",{character:"elathra"})).statusCode,200);
 const login=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName:a.playerName,password:a.password}})).json();
 a.token=login.accessToken;
 assert.equal((await call(a)).json().character,"elathra");await locked(b);
 console.log("PASS Companion locked before spar, after abandon, during active battle, and for other accounts including Elathra owner; actual server victory unlocks and saves across login");
}finally{await app.close();await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();}