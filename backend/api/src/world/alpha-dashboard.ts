import type {Pool} from "pg";
import {alphaRealtimeSnapshot} from "../routes/realtime.js";

const PUBLIC_HEALTH="https://reverie.tailad29fa.ts.net:8443/health";
const LOCAL_HEALTH="http://127.0.0.1:8791/health";
type Probe={state:"open"|"closed"|"unavailable"|"unknown";httpStatus:number|null;durationMs:number;checkedAt:string};
export async function probeAlphaHealth(url:string,fetcher:typeof fetch=fetch):Promise<Probe>{
 const start=performance.now();
 const result=(state:Probe["state"],httpStatus:number|null):Probe=>({state,httpStatus,durationMs:Math.round(performance.now()-start),checkedAt:new Date().toISOString()});
 try{
  const res=await fetcher(url,{redirect:"error",signal:AbortSignal.timeout(3500),headers:{accept:"application/json"}});
  if(!res.ok){await res.body?.cancel();return result("unavailable",res.status);}
  const data=await res.json();
  if(data?.service!=="Reverie"||data?.status!=="ok"||typeof data?.gameplayOpen!=="boolean")return result("unknown",res.status);
  return result(data.gameplayOpen?"open":"closed",res.status);
 }catch{return result("unavailable",null);}
}
export function createAlphaDashboard(pool:Pool){
 let cached:{local:Probe;public:Probe}|undefined,expires=0,pending:Promise<{local:Probe;public:Probe}>|undefined;
 async function probes(){
  if(cached&&Date.now()<expires)return cached;
  if(!pending)pending=Promise.all([probeAlphaHealth(LOCAL_HEALTH),probeAlphaHealth(PUBLIC_HEALTH)]).then(([local,external])=>{
   cached={local,public:external};expires=Date.now()+15000;return cached;
  }).finally(()=>{pending=undefined;});
  return pending;
 }
 return async()=>{
  const [network,q]=await Promise.all([probes(),pool.query(`
    WITH enrolled AS (
     SELECT DISTINCT a.id,a.status FROM reverie_alpha_invites i JOIN accounts a ON a.id=i.used_by WHERE i.used_at IS NOT NULL
    ), recent AS (
     SELECT p.id FROM enrolled e JOIN players p ON p.account_id=e.id JOIN player_presence pr ON pr.player_id=p.id
     WHERE e.status='active' AND pr.state<>'offline' AND pr.last_heartbeat_at>now()-interval '45 seconds'
    )
    SELECT
     (SELECT count(*)::int FROM enrolled) AS enrolled,
     (SELECT count(*)::int FROM enrolled WHERE status='active') AS active,
     (SELECT count(*)::int FROM reverie_alpha_invites WHERE used_at IS NULL AND expires_at>now()) AS unused,
     (SELECT count(*)::int FROM reverie_alpha_invites WHERE used_at IS NOT NULL) AS consumed,
     (SELECT count(*)::int FROM recent) AS recent_presence,
     (SELECT count(DISTINCT m.lobby_id)::int FROM co_op_lobby_members m JOIN recent r ON r.id=m.player_id JOIN co_op_lobbies l ON l.id=m.lobby_id WHERE l.status IN ('open','in_world')) AS recent_lobbies
   `)]);
  const row=q.rows[0]??{};
  return {network,enrollment:{enrolled:Number(row.enrolled??0),active:Number(row.active??0),unused:Number(row.unused??0),consumed:Number(row.consumed??0),issuanceLimit:20,remaining:Math.max(0,20-Number(row.consumed??0)-Number(row.unused??0))},recentPresence:Number(row.recent_presence??0),recentLobbies:Number(row.recent_lobbies??0),realtime:alphaRealtimeSnapshot(),scope:"host_probe_and_single_api_process",restrictions:{inviteOnly:true,paidPurchases:false,paidSummons:false,persistentRegionalWorld:false},asOf:new Date().toISOString()};
 };
}