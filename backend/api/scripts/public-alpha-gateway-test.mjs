import assert from "node:assert/strict";
import {spawn} from "node:child_process";
import {once} from "node:events";
import net from "node:net";
const child=spawn(process.execPath,["scripts/public-alpha-gateway.mjs"],{env:{...process.env,REVERIE_ALPHA_GATEWAY_PORT:"0"},stdio:["ignore","pipe","inherit"]});
try{
 const ready=await Promise.race([once(child.stdout,"data"),new Promise((_,reject)=>setTimeout(()=>reject(Error("startup timeout")),5000))]);
 const port=Number(String(ready[0]).match(/port (\d+)/)[1]),base="http://127.0.0.1:"+port;
 const health=await fetch(base+"/health");assert.equal(health.status,200);assert.equal((await health.json()).gameplayOpen,false);
 for(const path of ["/developer","/v1/developer/activity","/v1/auth/login","/v1/shop/checkout","/v1/game-servers","/ready","/health?x=1","/%64eveloper","/v1/world/realtime"]){
  const r=await fetch(base+path);assert.equal(r.status,404,path);
 }
 assert.equal((await fetch(base+"/health?utm_source=chatgpt.com")).status,200);
 assert.equal((await fetch(base+"/developer?utm_source=chatgpt.com")).status,404);
 assert.equal((await fetch(base+"/health?utm_source=chatgpt.com&x=1")).status,404);
 assert.equal((await fetch(base+"/",{method:"POST",body:"{}"})).status,404);
 const raw=await new Promise((resolve,reject)=>{let data="";const s=net.connect(port,"127.0.0.1",()=>s.write("GET /v1/world/realtime HTTP/1.1\r\nHost: localhost\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n"));s.on("data",d=>data+=d);s.on("end",()=>resolve(data));s.on("error",reject);s.setTimeout(3000,()=>s.destroy(Error("timeout")))});
 assert.ok(raw.includes("404"));
 console.log("PASS health status, admin isolation, payment isolation, no internal directory, encoded path denial, WebSocket denial");
}finally{child.kill();await once(child,"exit").catch(()=>{})}