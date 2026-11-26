import type {PoolClient} from "pg";
import {pool} from "../db.js";
export const seasonChallenges=[
 {id:"combat_10",title:"Season Vanguard",description:"Earn 10 rewarded online expedition victories.",target:10,gold:150},
 {id:"combat_25",title:"Season Champion",description:"Earn 25 rewarded online expedition victories.",target:25,gold:300},
 {id:"explore_2",title:"Trail Seeker",description:"Complete 2 distinct online exploration objectives this month.",target:2,gold:150},
 {id:"explore_4",title:"Realm Surveyor",description:"Complete 4 distinct online exploration objectives this month.",target:4,gold:300},
 {id:"season_complete",title:"Season Mastery",description:"Claim all four personal seasonal challenges.",target:4,gold:400}
] as const;
export async function challengeState(db:PoolClient|typeof pool,id:string){
 const q=await db.query<{season:string;server_time:string;reset_at:string;combat:number;exploration:number;claimed:string[]}>(`WITH clock AS (
 SELECT date_trunc('month',server_time AT TIME ZONE 'UTC') AS start,server_time FROM (SELECT clock_timestamp() AS server_time) actual_clock
 ) SELECT to_char(start,'YYYY-MM-DD') AS season,extract(epoch FROM server_time)*1000 AS server_time,
 extract(epoch FROM ((start+interval '1 month') AT TIME ZONE 'UTC'))*1000 AS reset_at,
 (SELECT count(*)::int FROM currency_ledger WHERE player_id=$1 AND reason='coop_monster_defeat' AND currency_id='gold' AND delta>0 AND created_at>=(start AT TIME ZONE 'UTC') AND created_at<((start+interval '1 month') AT TIME ZONE 'UTC') AND created_at<=server_time) AS combat,
 (SELECT count(*)::int FROM online_season_exploration WHERE player_id=$1 AND season_start=start::date) AS exploration,
 ARRAY(SELECT DISTINCT split_part(ref_id,':',2) FROM currency_ledger WHERE player_id=$1 AND reason='online_season_challenge' AND currency_id='gold' AND delta>0 AND split_part(ref_id,':',1)=to_char(start,'YYYY-MM-DD')) AS claimed FROM clock`,[id]);
 const p=q.rows[0]!;
 const rows=seasonChallenges.map(task=>{
  const count=task.id==="season_complete"?seasonChallenges.slice(0,4).filter(t=>p.claimed.includes(t.id)).length:task.id.startsWith("combat")?p.combat:p.exploration;
  const claimed=p.claimed.includes(task.id);
  return {...task,progress:claimed?task.target:Math.min(task.target,count),claimed,canClaim:!claimed&&count>=task.target};
 });
 return {playerId:id,season:p.season,serverTime:Number(p.server_time),resetAt:Number(p.reset_at),rows};
}
// Caller owns transaction; one lock per player, claims use current database UTC month.
export async function claimSeasonChallenges(db:PoolClient,id:string,season:string,taskId:string|null){
 await db.query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))",["season_challenge:"+id]);
 let state=await challengeState(db,id);
 if(state.season!==season)return null;
 const awards:{id:string;gold:number}[]=[];
 for(const definition of seasonChallenges){
  if(taskId!==null&&definition.id!==taskId)continue;
  const task=state.rows.find(r=>r.id===definition.id&&r.canClaim);
  if(!task)continue;
  const q=await db.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'gold',$2) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[id,task.gold]);
  const ref=season+":"+task.id;
  await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',$2,$3,'online_season_challenge','season_challenge',$4,$5)",[id,task.gold,q.rows[0].balance,ref,"season_challenge:"+ref+":gold"]);
  awards.push({id:task.id,gold:task.gold});
  state=await challengeState(db,id);
  // Never claim from a different month in the same request.
  if(state.season!==season)break;
 }
 return awards.length?{gold:awards.reduce((total,a)=>total+a.gold,0),awards,state}:null;
}
export const claimSeasonChallenge=(db:PoolClient,id:string,season:string,taskId:string)=>claimSeasonChallenges(db,id,season,taskId);
