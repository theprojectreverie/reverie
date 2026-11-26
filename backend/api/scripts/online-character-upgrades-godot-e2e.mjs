import Fastify from "fastify";
import jwt from "@fastify/jwt";
import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {spawn} from "node:child_process";
import {fileURLToPath} from "node:url";
import {config} from "../src/config.ts";
import {pool} from "../src/db.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {summonRoutes} from "../src/routes/summon.ts";
assert.ok(config.NODE_ENV==="development"&&["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify(),name="UpgradeUI"+randomBytes(4).toString("hex"),email=name.toLowerCase()+"@example.test",password=randomBytes(16).toString("hex");
try{
 await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(authRoutes,{prefix:"/v1/auth"});
 await app.register(summonRoutes,{prefix:"/v1/summon"});
 await app.listen({host:"127.0.0.1",port:0});
 assert.equal((await app.inject({method:"POST",url:"/v1/auth/register",payload:{playerName:name,email,password}})).statusCode,201);
 const login=(await app.inject({method:"POST",url:"/v1/auth/login",payload:{playerName:name,password}})).json(),id=login.player.id;
 await pool.query("INSERT INTO owned_characters(player_id,char_id,level,dupes) VALUES($1,'kael',20,2) ON CONFLICT(player_id,char_id) DO UPDATE SET level=20,dupes=2",[id]);
 await pool.query("UPDATE player_currencies SET balance=2000 WHERE player_id=$1 AND currency_id='gold'",[id]);
 await pool.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,'dew_of_awakening',1),($1,'moonpetal',2) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=excluded.quantity",[id]);
 const root=fileURLToPath(new URL("../../../",import.meta.url));
 const code=await new Promise((resolve,reject)=>{
 const p=spawn(process.env.QA_GODOT,["--headless","--path",root,"res://tools/qa_online_character_upgrades.tscn"],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:"1",QA_API:"http://127.0.0.1:"+app.server.address().port,QA_NAME:name,QA_PASSWORD:password}});
 const timer=setTimeout(()=>p.kill(),50000);p.stdout.on("data",d=>process.stdout.write(d));p.stderr.on("data",d=>process.stderr.write(d));p.on("error",reject);p.on("close",c=>{clearTimeout(timer);resolve(c)});
 });assert.equal(code,0);
 const trained=(await pool.query("SELECT level,xp::text FROM owned_characters WHERE player_id=$1 AND char_id='gerald'",[id])).rows[0];
 assert.equal(trained.level,2);assert.equal(trained.xp,"0");
 const retry=await app.inject({method:"POST",url:"/v1/summon/train",headers:{authorization:"Bearer "+login.accessToken},payload:{characterId:"gerald",expectedLevel:1,expectedXp:0}});
 assert.equal(retry.statusCode,409);
 const training=(await pool.query("SELECT delta::int FROM currency_ledger WHERE player_id=$1 AND reason='character_training'",[id])).rows;
 assert.deepEqual(training,[{delta:-100}]);
 const row=(await pool.query("SELECT level,ascension,awakening,dupes,skill_levels FROM owned_characters WHERE player_id=$1 AND char_id='kael'",[id])).rows[0];
 assert.equal(row.level,21);assert.equal(row.ascension,1);assert.equal(row.awakening,1);assert.equal(row.dupes,0);assert.equal(row.skill_levels.ember_lance,2);
 const ledger=(await pool.query("SELECT reason,delta::int FROM currency_ledger WHERE player_id=$1 AND reason IN ('character_ascension','skill_upgrade') ORDER BY reason",[id])).rows;
 assert.deepEqual(ledger,[{reason:"character_ascension",delta:-800},{reason:"skill_upgrade",delta:-100}]);
 console.log("PASS persisted server progression and exact ledger deductions");
}finally{await app.close();await pool.query("DELETE FROM accounts WHERE email=$1",[email]);await pool.end()}