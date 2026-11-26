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
type HistorySample={at:string;requests:number;p95UpperMs:number|null;serverErrors:number;rateLimited:number;databaseMs:number|null;databaseStatus:string;waiting:number;residentMiB:number};
export function createOperationalHistory(now=Date.now,maxSamples=240){
 const samples:HistorySample[]=[];
 return {
  record(value:Omit<HistorySample,"at">){
   const t=now();
   samples.push({...value,at:new Date(t).toISOString()});
   while(samples.length>maxSamples|| (samples.length>0&&Date.parse(samples[0]!.at)<t-3600000))samples.shift();
  },
  snapshot(){return samples.filter(s=>Date.parse(s.at)>=now()-3600000).map(s=>({...s}));}
 };
}
const history=createOperationalHistory();
export async function persistOperationalSample(pool:Pool,instanceId:string,sample:HistorySample){
 await pool.query("INSERT INTO api_operational_history(instance_id,sampled_at,sample) VALUES($1,$2,$3) ON CONFLICT DO NOTHING",[instanceId,sample.at,JSON.stringify(sample)]);
}
export async function readOperationalHistory(pool:Pool,instanceId:string){
 const result=await pool.query<{sample:HistorySample}>("SELECT sample FROM (SELECT sampled_at,sample FROM api_operational_history WHERE instance_id=$1 AND sampled_at>=now()-interval '1 hour' AND sampled_at<=now() ORDER BY sampled_at DESC LIMIT 240) recent ORDER BY sampled_at",[instanceId]);
 return result.rows.map(r=>r.sample);
}
export async function pruneOperationalHistory(pool:Pool,instanceId:string){
 return (await pool.query("DELETE FROM api_operational_history WHERE instance_id=$1 AND sampled_at IN (SELECT sampled_at FROM api_operational_history WHERE instance_id=$1 AND sampled_at<now()-interval '24 hours' ORDER BY sampled_at LIMIT 1000)",[instanceId])).rowCount??0;
}


export function startOperationalSampling(pool:Pool,intervalMs=15000,persistence?:{instanceId:string;onError:(e:unknown)=>void}){
 let nextPrune=0;
 const histogram=monitorEventLoopDelay({resolution:20});histogram.enable();
 let stopped=false,active:Promise<void>|undefined;
 const tick=()=>{
  if(stopped||active)return;
  if(histogram.count>0){loopP95Ms=Math.round(histogram.percentile(95)/1e6*10)/10;histogram.reset();}
  active=(async()=>{
   const start=performance.now();
   try{await pool.query(Object.assign({text:"SELECT 1"},{query_timeout:5000}));databaseSample={status:"ok",roundTripMs:Math.round((performance.now()-start)*10)/10,sampledAt:new Date().toISOString()};}
   catch{databaseSample={status:"unavailable",roundTripMs:null,sampledAt:new Date().toISOString()};}
   const http=requestMetrics.snapshot();
   history.record({requests:http.requests,p95UpperMs:http.p95UpperMs,serverErrors:http.serverErrors,rateLimited:http.rateLimited,databaseMs:databaseSample.roundTripMs,databaseStatus:databaseSample.status,waiting:pool.waitingCount,residentMiB:Math.round(process.memoryUsage.rss()/1048576)});
   if(persistence&&databaseSample.status==="ok"){
    try{
     const sample=history.snapshot().at(-1);
     if(sample)await persistOperationalSample(pool,persistence.instanceId,sample);
     if(Date.now()>=nextPrune){await pruneOperationalHistory(pool,persistence.instanceId);nextPrune=Date.now()+60000;}
    }catch(e){persistence.onError(e);}
   }


  })().finally(()=>{active=undefined;});
 };
 const timer=setInterval(tick,intervalMs);timer.unref();tick();
 return async()=>{stopped=true;clearInterval(timer);histogram.disable();await active;};
}
export function operationalSnapshot(pool:Pool){
 return {scope:"single_api_process",history:history.snapshot(),http:requestMetrics.snapshot(),database:{...databaseSample,poolTotal:pool.totalCount,poolIdle:pool.idleCount,poolWaiting:pool.waitingCount},process:{uptimeSeconds:Math.floor(process.uptime()),residentMiB:Math.round(process.memoryUsage.rss()/1048576),eventLoopP95Ms:loopP95Ms}};
}
