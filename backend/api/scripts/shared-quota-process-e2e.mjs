import assert from "node:assert/strict";
import {fork} from "node:child_process";
import {randomBytes} from "node:crypto";
import {performance} from "node:perf_hooks";
import {fileURLToPath} from "node:url";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
assert.ok(config.NODE_ENV!=="production"&&["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const ns="process_qa_"+randomBytes(6).toString("hex"),children=[];
async function start(){
 const child=fork(fileURLToPath(new URL("./shared-quota-process-worker.mjs",import.meta.url)),[],{execArgv:["--import","tsx"],env:{...process.env,REVERIE_QUOTA_QA_NAMESPACE:ns},stdio:["ignore","ignore","inherit","ipc"]});
 children.push(child);
 const port=await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error("worker startup timeout")),15000);child.once("message",m=>{clearTimeout(timer);resolve(m.port)});child.once("exit",code=>{clearTimeout(timer);reject(Error("worker exit "+code))});child.once("error",reject);});
 return {child,url:"http://127.0.0.1:"+port};
}
async function stop(child){if(child.exitCode!==null||child.signalCode!==null)return;await new Promise(resolve=>{const t=setTimeout(()=>child.kill(),3000);child.once("exit",()=>{clearTimeout(t);resolve()});if(child.connected)child.send("stop");else child.kill();});}
try{
 const [a,b]=await Promise.all([start(),start()]);
 const latencies=[],statuses=[];
 for(let wave=0;wave<20;wave++){
  await Promise.all(Array.from({length:30},async(_,i)=>{
   const worker=(wave+i)%2?a:b,t=performance.now();
   const r=await fetch(worker.url+"/probe/"+(wave*30+i));await r.arrayBuffer();latencies.push(performance.now()-t);statuses.push(r.status);
  }));
 }
 assert.equal(statuses.filter(s=>s===200).length,300);assert.equal(statuses.filter(s=>s===429).length,300);
 await stop(a.child);const c=await start();
 assert.equal((await fetch(c.url+"/probe/after-restart")).status,429);
 assert.equal((await fetch(c.url+"/independent")).status,200);
 const rows=(await pool.query("SELECT hits FROM api_rate_limit_buckets WHERE namespace=$1 ORDER BY hits DESC",[ns])).rows;
 assert.equal(rows[0].hits,601);assert.equal(rows[1].hits,1);
 latencies.sort((a,b)=>a-b);console.log("PASS separate process HTTP quota, exact 300 accepted/300 rejected, restart continuity and route isolation; p95="+latencies[Math.ceil(latencies.length*.95)-1].toFixed(1)+"ms");
}finally{
 await Promise.all(children.map(stop));await pool.query("DELETE FROM api_rate_limit_buckets WHERE namespace=$1",[ns]);await pool.end();console.log("PASS processes and quota fixtures cleaned");
}
