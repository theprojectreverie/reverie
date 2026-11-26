import type {PoolClient,Pool} from "pg";
import {pool} from "../db.js";
import {FIRST_GUILD_REWARD_SEASON,settlementRankingSql} from "./guild-competition.js";
type Db=Pool|PoolClient;
const prizes={1:300,2:200,3:100} as const;
export async function freezeGuildSeason(db:PoolClient,season:string,first=FIRST_GUILD_REWARD_SEASON){
 // Internal only; no client can choose the settlement clock or create results.
 if(!/^\d{4}-\d{2}-\d{2}$/.test(season)||season<first)throw Error("invalid_guild_season");
 const inserted=await db.query("INSERT INTO guild_league_finalizations(season_start) SELECT $1::date WHERE mod($1::date-DATE '2026-11-23',28)=0 AND (($1::date+28)::timestamp AT TIME ZONE 'UTC')+interval '5 minutes'<=clock_timestamp() ON CONFLICT DO NOTHING RETURNING season_start",[season]);
 if(!inserted.rowCount)return false;
 await db.query(settlementRankingSql+" INSERT INTO guild_league_results(season_start,guild_id,guild_name,emblem,points,rank,contributors) SELECT $1::date,id,name,emblem,points,place,contributors FROM ranked",[season]);
 // One award per player per season, even if they contributed to several winners.
 await db.query(settlementRankingSql+" , eligible AS (SELECT n.player_id,n.guild_id,n.points,r.place,row_number() OVER(PARTITION BY n.player_id ORDER BY r.place,n.points DESC,n.guild_id) AS preference FROM numbered n JOIN ranked r ON r.id=n.guild_id WHERE n.slot<=30 AND n.points>=200 AND r.place<=3) INSERT INTO guild_league_rewards(season_start,player_id,guild_id,rank,tokens,points) SELECT $1::date,player_id,guild_id,place,CASE place WHEN 1 THEN 300 WHEN 2 THEN 200 ELSE 100 END,points FROM eligible WHERE preference=1",[season]);
 return true;
}
export async function finalizeDueGuildSeasons(){
 const due=await pool.query<{season:string}>("SELECT to_char(d,'YYYY-MM-DD') AS season FROM generate_series($1::date::timestamp,(clock_timestamp() AT TIME ZONE 'UTC')::date::timestamp,interval '28 days') d WHERE ((d+interval '28 days') AT TIME ZONE 'UTC')+interval '5 minutes'<=clock_timestamp() AND NOT EXISTS(SELECT 1 FROM guild_league_finalizations f WHERE f.season_start=d::date) ORDER BY d LIMIT 12",[FIRST_GUILD_REWARD_SEASON]);
 const completed:string[]=[];
 for(const {season} of due.rows){
  const db=await pool.connect();
  try{
   await db.query("BEGIN ISOLATION LEVEL REPEATABLE READ");
   const frozen=await freezeGuildSeason(db,season);
   await db.query("COMMIT");if(frozen)completed.push(season);
  }catch(e){await db.query("ROLLBACK");if((e as {code?:string}).code!=="40001")throw e;}
  finally{db.release();}
 }
 return completed;
}
export async function guildLeagueHistory(db:Db,id:string){
 const latest=await db.query("SELECT to_char(season_start,'YYYY-MM-DD') AS season FROM guild_league_finalizations ORDER BY season_start DESC LIMIT 12");
 const top=await db.query("SELECT to_char(season_start,'YYYY-MM-DD') AS season,guild_id AS \"guildId\",guild_name AS name,rank,points::text,contributors FROM guild_league_results WHERE rank<=3 AND season_start IN (SELECT season_start FROM guild_league_finalizations ORDER BY season_start DESC LIMIT 12) ORDER BY season_start DESC,rank,guild_name,guild_id");
 const personal=await db.query("SELECT to_char(r.season_start,'YYYY-MM-DD') AS season,g.guild_name AS name,r.rank,r.tokens,r.points::text,r.claimed_at IS NOT NULL AS claimed FROM guild_league_rewards r JOIN guild_league_results g USING(season_start,guild_id) WHERE r.player_id=$1 ORDER BY r.season_start DESC",[id]);
 const titles=await db.query("SELECT to_char(r.season_start,'YYYY-MM-DD') AS season,r.guild_name AS name FROM guild_league_results r JOIN guild_members m ON m.guild_id=r.guild_id WHERE m.player_id=$1 AND r.rank=1 ORDER BY r.season_start DESC LIMIT 12",[id]);
 return {firstRewardSeason:FIRST_GUILD_REWARD_SEASON,seasons:latest.rows,champions:top.rows,rewards:personal.rows,titles:titles.rows.map(r=>({...r,title:"Guild League Champion"}))};
}
export async function claimGuildLeagueReward(db:PoolClient,id:string,season:string){
 const r=(await db.query("SELECT tokens,rank,claimed_at FROM guild_league_rewards WHERE player_id=$1 AND season_start=$2::date FOR UPDATE",[id,season])).rows[0];
 if(!r)return null;
 if(r.claimed_at)return {tokens:r.tokens,rank:r.rank,replayed:true};
 const w=(await db.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'guild_tokens',$2) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[id,r.tokens])).rows[0];
 await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'guild_tokens',$2,$3,'guild_league_reward','guild_league',$4,$5)",[id,r.tokens,w.balance,season,"guild-league:"+season]);
 await db.query("UPDATE guild_league_rewards SET claimed_at=now() WHERE player_id=$1 AND season_start=$2::date",[id,season]);
 return {tokens:r.tokens,rank:r.rank,replayed:false};
}