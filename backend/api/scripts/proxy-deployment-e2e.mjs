// Loopback-only reference routing harness, not a production proxy.
import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {fork} from "node:child_process";
import {createServer,request} from "node:http";
import {fileURLToPath} from "node:url";
import WebSocket from "ws";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {config} from "../src/config.ts";
import {pool} from "../src/db.ts";
import {trustLocalProxy} from "../src/world/proxy-trust.ts";
assert.ok(config.NODE_ENV!=="production"&&["127.0.0.1","localhost","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const ns="proxy_qa_"+randomBytes(6).toString("hex"),workers=[],connections=new Set();
const signer=Fastify();await signer.register(jwt,{secret:config.JWT_SECRET});await signer.ready();
let proxy,cursor=0;
async function start(){
 const child=fork(fileURLToPath(new URL("./proxy-deployment-worker.mjs",import.meta.url)),[],{execArgv:["--import","tsx"],env:{...process.env,REVERIE_QA_PROXY_NAMESPACE:ns},stdio:["ignore","ignore","inherit","ipc"]});
 const record={child,live:true};workers.push(record);
 child.once("exit",()=>record.live=false);
 return new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(Error("Worker startup timeout")),15000);
  child.once("message",m=>{clearTimeout(timer);Object.assign(record,m);resolve(record);});
  child.once("error",e=>{clearTimeout(timer);reject(e);});
 });
}
async function stop(w){
 if(!w.live)return;
 const done=new Promise(resolve=>w.child.once("exit",resolve));w.child.send("stop");await done;
}
const headers=req=>{
 const h={...req.headers};
 for(const k of Object.keys(h))if(k==="forwarded"||k.startsWith("x-forwarded-"))delete h[k];
 h["x-forwarded-for"]=req.socket.remoteAddress;
 h["x-forwarded-proto"]="http";
 h["x-forwarded-host"]=req.headers.host;
 return h;
};
try{
 const [a,b]=await Promise.all([start(),start()]);assert.notEqual(a.pid,b.pid);
 proxy=createServer((req,res)=>{
  if(req.url==="/ready"){res.writeHead(404).end();return;}
  const live=[a,b].filter(w=>w.live);
  if(!live.length){res.writeHead(503).end();return;}
  const target=live[cursor++%live.length];
  const upstream=request({host:"127.0.0.1",port:target.port,path:req.url,method:req.method,headers:headers(req)},r=>{res.writeHead(r.statusCode,r.headers);r.pipe(res);});
  upstream.on("error",()=>{if(!res.headersSent)res.writeHead(502);res.end();});
  req.pipe(upstream);
 });
 proxy.on("connection",s=>{connections.add(s);s.once("close",()=>connections.delete(s));});
 proxy.on("upgrade",(req,socket,head)=>{
  if(!a.live||new URL(req.url,"http://localhost").pathname!=="/v1/realtime"){socket.end("HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n");return;}
  const upstream=request({host:"127.0.0.1",port:a.port,path:req.url,method:req.method,headers:headers(req)});
  upstream.on("upgrade",(response,peer,upstreamHead)=>{
   socket.write("HTTP/1.1 101 Switching Protocols\r\n"+response.rawHeaders.reduce((str,v,i)=>str+(i%2?v+"\r\n":v+": "),"")+"\r\n");
   if(head.length)peer.write(head);if(upstreamHead.length)socket.write(upstreamHead);
   peer.pipe(socket);socket.pipe(peer);socket.on("close",()=>peer.destroy());peer.on("close",()=>socket.destroy());
  });
  upstream.on("response",r=>{socket.end("HTTP/1.1 "+r.statusCode+" Rejected\r\nConnection: close\r\n\r\n");r.resume();});
  upstream.on("error",()=>socket.destroy());upstream.end();
 });
 await new Promise((r,j)=>proxy.once("error",j).listen(0,"127.0.0.1",r));
 const base="http://127.0.0.1:"+proxy.address().port;
 const call=(path,opts)=>fetch(base+path,opts);
 const probes=await Promise.all(Array.from({length:6},()=>call("/probe",{headers:{"x-forwarded-for":"198.51.100.99","x-forwarded-proto":"https","forwarded":"for=198.51.100.99"}}).then(r=>r.json())));
 assert.deepEqual(new Set(probes.map(p=>p.pid)),new Set([a.pid,b.pid]));
 assert.ok(probes.every(p=>p.ip==="127.0.0.1"&&p.protocol==="http"));
 assert.equal(trustLocalProxy("198.51.100.99",0),false);assert.equal(trustLocalProxy("127.0.0.1",1),false);
 assert.equal((await call("/ready")).status,404);
 const quota=await Promise.all(Array.from({length:12},(_,i)=>call("/quota",{headers:{"x-forwarded-for":"198.51.100."+i}})));
 assert.equal(quota.filter(r=>r.status===200).length,5);assert.equal(quota.filter(r=>r.status===429).length,7);
 const token=signer.jwt.sign({sub:"11111111-1111-4111-8111-111111111111",playerId:"22222222-2222-4222-8222-222222222222",tokenVersion:1});
 const socketProbe=()=>new Promise((resolve,reject)=>{
  const s=new WebSocket(base.replace("http","ws")+"/v1/realtime",{headers:{authorization:"Bearer "+token}});
  const timer=setTimeout(()=>{s.terminate();reject(Error("WS timeout"));},5000);
  s.once("message",m=>{clearTimeout(timer);resolve(JSON.parse(String(m)));s.terminate();});
  s.once("error",e=>{clearTimeout(timer);reject(e);});
 });
 assert.equal((await socketProbe()).pid,a.pid);assert.equal((await socketProbe()).sub,"11111111-1111-4111-8111-111111111111");
 await stop(a);
 assert.equal((await call("/probe").then(r=>r.json())).pid,b.pid);
 assert.equal((await call("/quota")).status,429);
 await assert.rejects(socketProbe());
 console.log("PASS two independent worker processes, proxy balancing, spoofed forwarding rejection, shared quota, authenticated pinned socket, surviving HTTP worker and pinned socket fail-closed");
}finally{
 for(const s of connections)s.destroy();
 if(proxy)await new Promise(r=>proxy.close(r));
 for(const w of workers)await stop(w);
 await signer.close();await pool.query("DELETE FROM api_rate_limit_buckets WHERE namespace=$1",[ns]);await pool.end();
 console.log("PASS proxy test workers and quota fixtures removed");
}
