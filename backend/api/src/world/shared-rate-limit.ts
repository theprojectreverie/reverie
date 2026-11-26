import {createHmac} from "node:crypto";
import type {Pool} from "pg";
import type {FastifyRateLimitStore,FastifyRateLimitOptions} from "@fastify/rate-limit";
type Options=FastifyRateLimitOptions&{continueExceeding?:boolean;exponentialBackoff?:boolean;routeInfo?:{method?:string|string[];url?:string}};
type Callback=Parameters<FastifyRateLimitStore["incr"]>[1];
export const RATE_LIMIT_SQL=`INSERT INTO api_rate_limit_buckets(namespace,bucket_hash,hits,expires_at)
 VALUES($1,$2,1,clock_timestamp()+$3::double precision*interval '1 millisecond')
 ON CONFLICT(namespace,bucket_hash) DO UPDATE SET
 hits=CASE WHEN api_rate_limit_buckets.expires_at<=clock_timestamp() THEN 1
  ELSE LEAST(api_rate_limit_buckets.hits::bigint+1,2147483647)::int END,
 expires_at=CASE WHEN api_rate_limit_buckets.expires_at<=clock_timestamp()
  THEN clock_timestamp()+$3::double precision*interval '1 millisecond' ELSE api_rate_limit_buckets.expires_at END
 RETURNING hits AS current,GREATEST(1,ceil(extract(epoch FROM (expires_at-clock_timestamp()))*1000))::int AS ttl`;
export function createSharedRateLimitStore(pool:Pool,namespace:string,secret:string){
 if(!/^[a-zA-Z0-9_-]{1,48}$/.test(namespace)||secret.length<32)throw Error("Invalid shared quota configuration");
 return class SharedStore implements FastifyRateLimitStore{
  private scope:string;
  constructor(options:Options,scope="global"){
   if(options.continueExceeding||options.exponentialBackoff)throw Error("Shared quota supports fixed windows only");
   this.scope=scope;
  }
  incr(key:string,cb:Callback,timeWindow?:number,_max?:number){
   if(!Number.isSafeInteger(timeWindow)||timeWindow!<1||timeWindow!>86400000){cb(Error("Invalid shared quota window"));return;}
   const hash=createHmac("sha256",secret).update(JSON.stringify([this.scope,key])).digest("hex");
   pool.query<{current:number;ttl:number}>({text:RATE_LIMIT_SQL,values:[namespace,hash,timeWindow],...{query_timeout:5000}})
    .then(r=>{const result=r.rows[0];if(!result)cb(Error("Shared quota result missing"));else cb(null,result);},()=>{
     // Never fail open or expose PostgreSQL error details to clients.
     cb(Object.assign(Error("Rate limiting temporarily unavailable"),{statusCode:503,code:"RATE_LIMIT_UNAVAILABLE"}));
    });
  }
  child(options:Parameters<FastifyRateLimitStore["child"]>[0]){
   const o=options as unknown as Options,route=o.routeInfo;
   if(!route?.method||!route.url)throw Error("Shared quota requires a stable route identity");
   return new SharedStore(o,JSON.stringify([route.method,route.url]));
  }
 };
}
export async function pruneSharedRateLimits(pool:Pool,namespace:string){
 const r=await pool.query(`DELETE FROM api_rate_limit_buckets b USING (
 SELECT bucket_hash FROM api_rate_limit_buckets WHERE namespace=$1 AND expires_at<now()-interval '1 minute'
 ORDER BY expires_at LIMIT 1000 FOR UPDATE SKIP LOCKED) old WHERE b.namespace=$1 AND b.bucket_hash=old.bucket_hash`,[namespace]);
 return r.rowCount??0;
}
export function startSharedRateLimitCleanup(pool:Pool,namespace:string,onError:(e:unknown)=>void,intervalMs=60000){
 let active:Promise<void>|undefined,stopped=false;
 const tick=()=>{
  if(stopped||active)return;
  active=Promise.resolve().then(async()=>{for(let i=0;i<5&&!stopped;i++)if(await pruneSharedRateLimits(pool,namespace)<1000)break;}).catch(onError).finally(()=>{active=undefined;});
 };
 const timer=setInterval(tick,intervalMs);timer.unref();tick();
 return async()=>{stopped=true;clearInterval(timer);await active;};
}
