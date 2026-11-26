import {monitorEventLoopDelay,performance} from "node:perf_hooks";
import type {Pool} from "pg";
import type {FastifyInstance} from "fastify";
const WINDOW=60000, BUCKET=1000, MAX_MS=60000;
// Fixed-size rolling histogram, independent of traffic volume and URL cardinality.
const bounds=[1,2,5,10,20,50,100,200,500,1000,2000,5000,10000,30000,60000];
type Bucket={second:number;count:number;errors:number;limited:number;hist:number[]};
export function createRequestMetrics(now=Date.now){
 const buckets:Bucket[]=Array.from({length:60},()=>({second:-1,count:0,errors:0,limited:0,hist:bounds.map(()=>0)}));
 function record(ms:number,status:number){
  if(!Number.isFinite(ms)||ms<0)return;
  const second=Math.floor(now()/BUCKET),index=((second%60)+60)%60,b=buckets[index]!;
  if(b.second!==second){b.second=second;b.count=0;b.errors=0;b.limited=0;b.hist.fill(0);}
  b.count++;if(status>=500)b.errors++;if(status===429)b.limited++;
  const bin=bounds.findIndex(x=>x>=ms);b.hist[bin<0?bounds.length-1:bin]!++;
 }
 function snapshot(){
  const second=Math.floor(now()/BUCKET),live=buckets.filter(b=>b.second<=second&&b.second>second-60);
  const count=live.reduce((s,b)=>s+b.count,0),hist=bounds.map((_,i)=>live.reduce((s,b)=>s+b.hist[i]!,0));
  function percentile(q:number){if(!count)return null;let n=0;for(let i=0;i<hist.length;i++){n+=hist[i]!;if(n>=Math.ceil(count*q))return bounds[i]!;}return MAX_MS;}
  return {windowSeconds:WINDOW/1000,requests:count,serverErrors:live.reduce((s,b)=>s+b.errors,0),rateLimited:live.reduce((s,b)=>s+b.limited,0),p50UpperMs:percentile(.5),p95UpperMs:percentile(.95)};
 }
 return {record,snapshot};
}
export const requestMetrics=createRequestMetrics();
export function attachOperationalMetrics(app:FastifyInstance){
 const starts=new WeakMap<object,number>();
 app.addHook("onRequest",async req=>{starts.set(req,performance.now());});
 app.addHook("onResponse",async(req,reply)=>{const started=starts.get(req);if(started!==undefined)requestMetrics.record(performance.now()-started,reply.statusCode);});
}
type DatabaseSample={status:"unknown"|"ok"|"unavailable";roundTripMs:number|null;sampledAt:string|null};
let databaseSample:DatabaseSample={status:"unknown",roundTripMs:null,sampledAt:null};
let loopP95Ms:number|null=null;
export function startOperationalSampling(pool:Pool,intervalMs=15000){
 const histogram=monitorEventLoopDelay({resolution:20});histogram.enable();
 let stopped=false,active:Promise<void>|undefined;
 const tick=()=>{
  if(stopped||active)return;
  if(histogram.count>0){loopP95Ms=Math.round(histogram.percentile(95)/1e6*10)/10;histogram.reset();}
  active=(async()=>{
   const start=performance.now();
   try{await pool.query(Object.assign({text:"SELECT 1"},{query_timeout:5000}));databaseSample={status:"ok",roundTripMs:Math.round((performance.now()-start)*10)/10,sampledAt:new Date().toISOString()};}
   catch{databaseSample={status:"unavailable",roundTripMs:null,sampledAt:new Date().toISOString()};}
  })().finally(()=>{active=undefined;});
 };
 const timer=setInterval(tick,intervalMs);timer.unref();tick();
 return async()=>{stopped=true;clearInterval(timer);histogram.disable();await active;};
}
export function operationalSnapshot(pool:Pool){
 return {scope:"single_api_process",http:requestMetrics.snapshot(),database:{...databaseSample,poolTotal:pool.totalCount,poolIdle:pool.idleCount,poolWaiting:pool.waitingCount},process:{uptimeSeconds:Math.floor(process.uptime()),residentMiB:Math.round(process.memoryUsage.rss()/1048576),eventLoopP95Ms:loopP95Ms}};
}
