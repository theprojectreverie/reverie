import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {spawn} from "node:child_process";
import {fileURLToPath} from "node:url";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {socialRoutes} from "../src/routes/social.ts";
import {tutorialSparRoutes} from "../src/routes/tutorial-spar.ts";
import {summonRoutes} from "../src/routes/summon.ts";
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname)&&config.NODE_ENV!=="production");
const app=Fastify({logger:false}),suffix=randomBytes(4).toString("hex"),emails=[];
async function create(i){
 const playerName="SparQA"+suffix+i,email=playerName.toLowerCase()+"@example.test",password=randomBytes(16).toString("hex");emails.push(email);
 assert.equal((await app.inject({method:"POST",url:"/v1/auth/register",payload:{email,playerName,password}})).statusCode,201);
 const login=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName,password}})).json();
 return {id:login.player.id,token:login.accessToken,playerName,password};
}
const call=(a,url,payload)=>app.inject({method:payload?"POST":"GET",url,headers:a?{authorization:"Bearer "+a.token}:{},...(payload?{payload}:{})});
const spar=(a,p)=>call(a,"/v1/tutorial-spar/",p);
let dropped=false;
app.addHook("onSend",async(req,reply,payload)=>{
 if(!dropped&&req.url==="/v1/tutorial-spar/"&&req.body?.operation==="act"&&req.body?.action?.kind==="defend"&&reply.statusCode===200){
  dropped=true;reply.code(503);return JSON.stringify({ok:false,reason:"qa_lost_response"});
 }
 return payload;
});
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.register(socialRoutes,{prefix:"/v1/social"});await app.register(tutorialSparRoutes,{prefix:"/v1/tutorial-spar"});await app.register(summonRoutes,{prefix:"/v1/summon"});await app.listen({host:"127.0.0.1",port:0});
 const a=await create(0),b=await create(1);
 assert.equal((await spar(null,{operation:"start"})).statusCode,401);
 assert.equal((await spar(a,{operation:"start"})).statusCode,409);
 assert.equal((await spar(a,{operation:"start",groupId:"revienna_encounter"})).statusCode,400);
 assert.equal((await call(a,"/v1/social/companion-name",{name:"Astra"})).statusCode,200);
 const start=(await spar(a,{operation:"start"})).json();assert.ok(start.ok,JSON.stringify(start));
 assert.equal((await spar(b,{operation:"abandon",battleId:start.battleId})).statusCode,404);
 assert.equal((await spar(a,{operation:"act",battleId:start.battleId,sequence:1,action:{kind:"defend",actorUid:"fake"}})).statusCode,409);
 const starter=await pool.query("SELECT level,ascension,awakening FROM owned_characters WHERE player_id=$1 AND char_id='kael'",[a.id]);
 assert.equal(starter.rows[0].level,1);assert.equal(starter.rows[0].ascension,0);assert.equal(starter.rows[0].awakening,0);
 assert.equal((await spar(a,{operation:"ack_unlock",battleId:start.battleId})).statusCode,409);
 assert.equal((await spar(a,{operation:"abandon",battleId:start.battleId})).statusCode,200);
 assert.equal((await spar(a,{operation:"resume",battleId:start.battleId})).statusCode,409);
 const beforeWallet=(await call(a,"/v1/auth/wallet")).json().currencies;
 const beforePity=(await call(a,"/v1/summon/state")).json().pity;
 assert.equal((await call(b,"/v1/summon/tutorial-claim",{})).statusCode,409);
 const root=fileURLToPath(new URL("../../../",import.meta.url));
 const exit=await new Promise((resolve,reject)=>{const p=spawn(process.env.REVERIE_STORY_GODOT,["--headless","--path",root,"res://tools/qa_live_spar.tscn"],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:"1",QA_API:"http://127.0.0.1:"+app.server.address().port,QA_NAME:a.playerName,QA_PASSWORD:a.password}});p.stdout.on("data",d=>process.stdout.write(d));p.stderr.on("data",d=>process.stderr.write(d));const t=setTimeout(()=>p.kill(),150000);p.on("error",reject);p.on("close",c=>{clearTimeout(t);resolve(c);});});
 assert.equal(exit,0);
 assert.ok(dropped,"test must lose a committed defend response");
 const afterWallet=(await call(a,"/v1/auth/wallet")).json().currencies;
 assert.deepEqual(afterWallet,beforeWallet);
 const afterState=(await call(a,"/v1/summon/state")).json();
 assert.deepEqual(afterState.pity,beforePity);
 const receipt=(await call(a,"/v1/summon/tutorial-claim",{})).json();
 assert.equal(receipt.replayed,true);assert.equal(receipt.results[0].character_id,"kael_legendary");
 const owned=(await pool.query("SELECT dupes,awakening FROM owned_characters WHERE player_id=$1 AND char_id='kael_legendary'",[a.id])).rows;
 assert.equal(owned.length,1);assert.equal(owned[0].dupes,0);assert.equal(owned[0].awakening,0);
 console.log("PASS one real tutorial summon, replay receipt, unchanged wallet and pity");
 const view=(await spar(a,{operation:"start"})).json();assert.equal(view.view.status,"victory");assert.equal(view.unlockNoticePending,false);
 assert.equal((await spar(b,{operation:"ack_unlock",battleId:view.battleId})).statusCode,404);
 assert.equal((await spar(a,{operation:"ack_unlock",battleId:view.battleId})).statusCode,200);
 const resumed=(await spar(a,{operation:"resume",battleId:view.battleId})).json();assert.equal(resumed.unlockNoticePending,false);
 console.log("PASS unboosted level-one Kael, lost action response recovery, persistent one-time notice");
 assert.equal((await call(a,"/v1/social/menu-character",{character:"elathra"})).statusCode,200);
 assert.equal((await call(b,"/v1/social/menu-character",{character:"elathra"})).statusCode,403);
 console.log("PASS scoped live spar route, auth, invalid action, abandon, reconnect victory, account-bound Companion unlock");
}finally{await app.close();await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();}