// Local-only, bounded scale-up pilot. Never invoked by the public API.
import {spawn} from "node:child_process";
import {createServer,createConnection} from "node:net";
import {randomBytes} from "node:crypto";
import {existsSync} from "node:fs";
import {fileURLToPath} from "node:url";
const pause=ms=>new Promise(r=>setTimeout(r,ms));
export function planScale(rows,{regions,build,capacity,maxPerRegion,maxTotal,threshold=0.8,managedPrefix,pending=[]}){
 if(!Number.isInteger(capacity)||capacity<1||capacity>100||!Number.isInteger(maxPerRegion)||maxPerRegion<1||maxPerRegion>4||!Number.isInteger(maxTotal)||maxTotal<1||maxTotal>4||threshold<0.5||threshold>0.95)throw Error("Invalid scaling bounds");
 // Count even stale/offline managed registrations against the cap: a controller
 // restart cannot silently create unlimited processes. Operators retire records.
 const managed=rows.filter(r=>r.server_key.startsWith(managedPrefix));
 const outstanding=pending.filter(p=>!managed.some(r=>r.server_key===p.key));
 if(managed.length+outstanding.length>=maxTotal)return null;
 for(const region of regions){
  if(managed.filter(r=>r.region_id===region).length+outstanding.filter(p=>p.region===region).length>=maxPerRegion)continue;
  if(outstanding.some(p=>p.region===region)||managed.some(r=>r.region_id===region&&r.status==="starting"))continue;
  const online=rows.filter(r=>r.region_id===region&&r.build_version===build&&r.status==="online"&&r.fresh&&r.endpoint_url);
  if(!online.length)continue; // no bootstrap of an unapproved or unavailable region
  const slots=online.reduce((n,r)=>n+Number(r.max_players),0);
  const occupied=online.reduce((n,r)=>n+Number(r.current_players),0);
  if(occupied/slots>=threshold)return {region,capacity,occupied,slots};
 }
 return null;
}
export const readCapacity=async db=>(await db.query(`SELECT s.server_key,s.region_id,s.status,s.build_version,s.endpoint_url,s.max_players,
 COALESCE(s.heartbeat_at>now()-interval '60 seconds',false) AS fresh,count(p.player_id)::int AS current_players
 FROM game_servers s LEFT JOIN game_server_players p ON p.server_id=s.id GROUP BY s.id`)).rows;
const localHost=h=>["localhost","127.0.0.1","[::1]"].includes(h);
export function createLocalScaler({db,api,bootstrap,bin,policy,execute=false,cooldownMs=180000,now=Date.now}){
 if(!localHost(new URL(api).hostname)||!api.startsWith("http://")||!bootstrap||bootstrap.length<32)throw Error("Local API and bootstrap required");
 if(!/^scale-[a-z0-9-]{3,30}-$/.test(policy.managedPrefix))throw Error("Invalid managed prefix");
 if(execute&&(!bin||!existsSync(bin)||/console\.exe$/i.test(bin)))throw Error("Direct Godot engine executable required (not console launcher)");
 if(!policy.regions.length||policy.regions.some(r=>!/^[a-z0-9_]{2,48}$/.test(r)))throw Error("Invalid region allowlist");
 const children=new Map(),launchTimes=[];
 let busy=false,lastLaunch=-Infinity;
 const root=fileURLToPath(new URL("../../../",import.meta.url));
 const launch=async(plan,t,previous)=>{
   let port=previous?.port;
   if(!port){
   const listener=createServer();
   await new Promise((r,j)=>listener.once("error",j).listen(0,"127.0.0.1",r));
   port=listener.address().port;
   await new Promise(r=>listener.close(r));
   }
   const key=previous?.key??policy.managedPrefix+randomBytes(5).toString("hex");
   const env={...process.env};
   for(const k of Object.keys(env))if(/SECRET|TOKEN|PASSWORD|DATABASE_URL|STRIPE|^REVERIE_SERVER_|^REVERIE_API_BASE_URL/i.test(k))delete env[k];
   Object.assign(env,{REVERIE_E2E_DISABLE_LOCAL_SAVE:"1",REVERIE_API_BASE_URL:api,REVERIE_SERVER_BOOTSTRAP_SECRET:bootstrap,REVERIE_SERVER_KEY:key,REVERIE_SERVER_NAME:"Regional overflow "+key.slice(-10),REVERIE_SERVER_REGION:plan.region,REVERIE_SERVER_HOST:"127.0.0.1",REVERIE_SERVER_PORT:String(port),REVERIE_SERVER_MAX_PLAYERS:String(plan.capacity),REVERIE_SERVER_ENDPOINT:"ws://127.0.0.1:"+port,REVERIE_SERVER_EVENT_BATCH_SIZE:"100"});
   lastLaunch=t;launchTimes.push(t);
   const child=spawn(bin,["--headless","--path",root,"res://scenes/online/dedicated_world_server.tscn"],{cwd:root,env,stdio:["ignore","pipe","pipe"]});
   const record={key,region:plan.region,port,child,output:"",launchedAt:t,restarts:(previous?.restarts??-1)+1,emptySince:null,retired:false,failed:false};
   children.set(key,record);
   child.on("error",e=>{record.output=String(e);record.failed=true;});
   child.stdout.on("data",b=>record.output=(record.output+b).slice(-4000));
   child.stderr.on("data",b=>record.output=(record.output+b).slice(-4000));
   // Retain failed launch records until operator review; no automatic crash loop.
   return {status:previous?"restarted":"launched",key,port,plan};
 };
 const exited=r=>r.failed||r.child.exitCode!==null||r.child.signalCode!==null;
 const stopOwned=async r=>{
  if(!exited(r)){
   const stopped=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error("Managed engine did not exit")),10000);r.child.once("exit",()=>{clearTimeout(timer);resolve()});});
   r.child.kill("SIGKILL");await stopped;
  }
 };
 // Serialize with join/consume/reconnect using the same server row lock.
 // Retire only a genuinely empty server. Keep registry and durable state.
 const fence=async(r,emptyOnly)=>{
  await db.query("BEGIN");
  try{
   const row=(await db.query("SELECT id,status FROM game_servers WHERE server_key=$1 FOR UPDATE",[r.key])).rows[0];
   if(!row){await db.query("ROLLBACK");return !emptyOnly;}
   if(emptyOnly){
    const occupancy=(await db.query(`SELECT
      EXISTS(SELECT 1 FROM game_server_players WHERE server_id=$1)
      OR EXISTS(SELECT 1 FROM game_server_player_connections WHERE server_id=$1 AND lease_expires_at>now())
      OR EXISTS(SELECT 1 FROM game_server_join_tickets WHERE server_id=$1 AND consumed_at IS NULL AND expires_at>now()) AS occupied`,[row.id])).rows[0];
    if(occupancy.occupied){await db.query("ROLLBACK");return false;}
   }
   await db.query("UPDATE game_servers SET status='offline',heartbeat_at=NULL,stopped_at=now(),server_secret_hash=NULL WHERE id=$1",[row.id]);
   await db.query("DELETE FROM game_server_player_connections WHERE server_id=$1",[row.id]);
   await db.query("COMMIT");return true;
  }catch(e){await db.query("ROLLBACK");throw e;}
 };
 const supervise=async(rows,t)=>{
  for(const r of children.values()){
   if(r.retired)continue;
   const row=rows.find(x=>x.server_key===r.key);
   if(exited(r)){
    if(!r.fenced){await fence(r,false);r.fenced=true;r.failedAt=t;return {status:"crashed",key:r.key};}
    if(r.restarts>=2)return {status:"recovery_exhausted",key:r.key};
    if(t-r.failedAt<cooldownMs||t-lastLaunch<cooldownMs||launchTimes.filter(x=>t-x<900000).length>=4)return {status:"recovery_cooldown",key:r.key};
    return launch({region:r.region,capacity:r.capacity??policy.capacity},t,r);
   }
   // Never kill an unresponsive live process on heartbeat alone.
   if(!row||!row.fresh||row.status!=="online"){
    r.emptySince=null;
    if(t-r.launchedAt>60000)return {status:"unhealthy",key:r.key};
    continue;
   }
   if(Number(row.current_players)>0){r.emptySince=null;continue;}
   r.emptySince??=t;
   if(t-r.emptySince<(policy.idleMs??600000))continue;
   // Leave an existing compatible healthy server in this region.
   if(!rows.some(x=>x.server_key!==r.key&&x.region_id===r.region&&x.build_version===policy.build&&x.status==="online"&&x.fresh&&Number(x.current_players)<Number(x.max_players)))continue;
   if(!await fence(r,true)){r.emptySince=null;continue;}
   await stopOwned(r);r.retired=true;
   return {status:"retired",key:r.key};
  }
  return null;
 };
 const tick=async()=>{
  if(busy)return {status:"busy"};
  busy=true;
  try{
   const rows=await readCapacity(db);
   if(execute){const action=await supervise(rows,now());if(action)return action;}
   const pending=[...children.values()].map(c=>({key:c.key,region:c.region}));
   const plan=planScale(rows,{...policy,pending});
   if(!plan)return {status:"idle"};
   if(!execute)return {status:"dry-run",plan};
   const t=now();
   if(t-lastLaunch<cooldownMs||launchTimes.filter(x=>t-x<900000).length>=4)return {status:"cooldown",plan};
   // Session advisory lock is held by the operator runner, so one controller
   // owns the namespace. The spawn limit also counts failed launch attempts.
   return await launch(plan,t);

  }finally{busy=false;}
 };
 // Test-only cleanup: only the children launched by this instance, never unrelated processes.
 const stopTestChildren=async()=>{
  for(const r of children.values()){
   if(r.child.exitCode===null)r.child.kill("SIGKILL");
   for(let i=0;i<80;i++){
    const live=await new Promise(resolve=>{const s=createConnection({host:"127.0.0.1",port:r.port});s.once("connect",()=>{s.destroy();resolve(true)});s.once("error",()=>resolve(false));s.setTimeout(200,()=>{s.destroy();resolve(false)});});
    if(!live)break;
    if(i===79)throw Error("Managed test listener did not stop");
    await pause(100);
   }
  }
 };
 return {tick,children,stopTestChildren};
}
