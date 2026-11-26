import type {PoolClient} from "pg";
import {pool} from "../db.js";

// First prospective competition. November was informational, with no announced prizes.
export const FIRST_REWARD_SEASON="2026-12-01";
export const seasonalTitles=[
 {id:"season_combat_champion",name:"Arena Sovereign",category:"Seasonal",achievement:"First place in monthly combat"},
 {id:"season_exploration_champion",name:"Realm Pioneer",category:"Seasonal",achievement:"First place in monthly exploration"},
 {id:"season_achievement_champion",name:"Seasonal Paragon",category:"Seasonal",achievement:"First place in monthly achievements"}
] as const;
const categoryTitles={combat:seasonalTitles[0].id,exploration:seasonalTitles[1].id,achievements:seasonalTitles[2].id};
export function championTitle(category:string):string{return categoryTitles[category as keyof typeof categoryTitles]??"";}

// Caller must begin a transaction. The unique season row serializes finalizers.
// Rank on one canonical global population, never viewer-specific block filters.
export async function freezeSeason(db:PoolClient,season:string,achievementIds:string[],first=FIRST_REWARD_SEASON){
 if(!/^\d{4}-(0[1-9]|1[0-2])-01$/.test(season)||season<first)throw Error("invalid_reward_season");
 const inserted=await db.query("INSERT INTO online_season_finalizations(season_start) SELECT $1::date WHERE (($1::date+interval '1 month') AT TIME ZONE 'UTC')+interval '5 minutes'<=clock_timestamp() ON CONFLICT DO NOTHING RETURNING season_start",[season]);
 if(!inserted.rowCount)return false;
 // No zero-score placements. Equal scores share rank and reward.
 await db.query(`WITH enrolled AS (
 SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id
 WHERE a.status='active' AND COALESCE((SELECT e.enabled FROM online_ranking_visibility_events e WHERE e.player_id=p.id AND e.changed_at<(($1::date+interval '1 month') AT TIME ZONE 'UTC') ORDER BY e.changed_at DESC,e.id DESC LIMIT 1),false)
 ), scores AS (
 SELECT e.id,'combat'::text category,(SELECT count(*)::int FROM currency_ledger cl WHERE cl.player_id=e.id AND cl.reason='coop_monster_defeat' AND cl.currency_id='gold' AND cl.delta>0 AND cl.created_at>=($1::date::timestamp AT TIME ZONE 'UTC') AND cl.created_at<(($1::date+interval '1 month') AT TIME ZONE 'UTC')) score FROM enrolled e
 UNION ALL SELECT e.id,'exploration',(SELECT count(*)::int FROM online_season_exploration s WHERE s.player_id=e.id AND s.season_start=$1::date) FROM enrolled e
 UNION ALL SELECT e.id,'achievements',(SELECT count(DISTINCT cl.ref_id)::int FROM currency_ledger cl WHERE cl.player_id=e.id AND cl.reason='online_achievement' AND cl.currency_id='gold' AND cl.delta>0 AND cl.ref_id=ANY($2::text[]) AND cl.created_at>=($1::date::timestamp AT TIME ZONE 'UTC') AND cl.created_at<(($1::date+interval '1 month') AT TIME ZONE 'UTC')) FROM enrolled e
 ), ranked AS (SELECT *,rank() OVER(PARTITION BY category ORDER BY score DESC)::int AS rank FROM scores WHERE score>0)
 INSERT INTO online_season_results(season_start,player_id,category,score,rank,gold)
 SELECT $1::date,id,category,score,rank,CASE rank WHEN 1 THEN 1000 WHEN 2 THEN 600 WHEN 3 THEN 300 ELSE 0 END FROM ranked`,[season,achievementIds]);
 return true;
}

export async function seasonalResults(playerId:string){
 const q=await pool.query("WITH recent AS (SELECT *,row_number() OVER(ORDER BY season_start DESC,category) AS n FROM online_season_results WHERE player_id=$1) SELECT season_start::text AS season,category,score,rank,gold,claimed_at IS NOT NULL AS claimed FROM recent WHERE n<=36 OR (gold>0 AND claimed_at IS NULL) ORDER BY season_start DESC,category",[playerId]);
 return q.rows.map(r=>({...r,canClaim:r.gold>0&&!r.claimed,title:r.rank===1?seasonalTitles.find(t=>t.id===championTitle(r.category))?.name??"":""}));
}

export async function claimSeasonReward(db:PoolClient,playerId:string,season:string,category:string){
 const q=await db.query("SELECT gold,rank,claimed_at FROM online_season_results WHERE player_id=$1 AND season_start=$2::date AND category=$3 FOR UPDATE",[playerId,season,category]);
 const reward=q.rows[0];
 if(!reward||reward.claimed_at||reward.gold<=0)return null;
 const wallet=await db.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'gold',$2) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[playerId,reward.gold]);
 const ref=season+":"+category;
 await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',$2,$3,'online_season_reward','season_reward',$4,$5)",[playerId,reward.gold,wallet.rows[0].balance,ref,"season:"+ref+":gold"]);
 await db.query("UPDATE online_season_results SET claimed_at=now() WHERE player_id=$1 AND season_start=$2::date AND category=$3",[playerId,season,category]);
 return {gold:reward.gold,title:reward.rank===1?championTitle(category):""};
}

// Database clock governs eligibility. Catch up missed seasons, oldest first,
// with a bounded batch and transaction-level serialization across API replicas.
export async function finalizeDueSeasons(achievementIds:string[],limit=12){
 const due=await pool.query<{season:string}>("SELECT to_char(m,'YYYY-MM-DD') AS season FROM generate_series($1::date::timestamp,date_trunc('month',clock_timestamp() AT TIME ZONE 'UTC'),interval '1 month') m WHERE ((m+interval '1 month') AT TIME ZONE 'UTC') + interval '5 minutes' <= clock_timestamp() AND NOT EXISTS(SELECT 1 FROM online_season_finalizations f WHERE f.season_start=m::date) ORDER BY m LIMIT $2",[FIRST_REWARD_SEASON,Math.max(1,Math.min(12,limit))]);
 const completed:string[]=[];
 for(const {season} of due.rows){
  const db=await pool.connect();
  try{await db.query("BEGIN");const frozen=await freezeSeason(db,season,achievementIds);await db.query("COMMIT");if(frozen)completed.push(season);}
  catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 }
 return completed;
}

export function startSeasonFinalizer(run:()=>Promise<string[]>,onCompleted:(seasons:string[])=>void,onError:(error:unknown)=>void,intervalMs=60000){
 let stopped=false;
 let active:Promise<void>|null=null;
 const tick=()=>{
  if(stopped||active)return;
  active=Promise.resolve().then(run).then(seasons=>{if(seasons.length)onCompleted(seasons);}).catch(onError).finally(()=>{active=null;});
 };
 const timer=setInterval(tick,intervalMs);
 timer.unref();
 tick();
 return async()=>{stopped=true;clearInterval(timer);await active;};
}

export async function seasonRewardReady(playerId:string){
 const q=await pool.query("SELECT season_start::text AS season,category FROM online_season_results WHERE player_id=$1 AND gold>0 AND claimed_at IS NULL ORDER BY season_start,category",[playerId]);
 return q.rows.map(r=>({id:r.season+":"+r.category,season:r.season,category:r.category}));
}

export async function championshipHistory(playerId:string){
 const q=await pool.query("SELECT season_start::text AS season,category,score FROM online_season_results WHERE player_id=$1 AND rank=1 ORDER BY season_start DESC,category",[playerId]);
 return q.rows.map(r=>({...r,title:seasonalTitles.find(t=>t.id===championTitle(r.category))?.name??""}));
}
