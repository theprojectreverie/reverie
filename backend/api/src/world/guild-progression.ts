import type {PoolClient,Pool} from "pg";
export const guildMissions=[
 {id:"checkin",title:"Guild allegiance",description:"Claim today's online check-in while in your guild.",target:1,xp:25},
 {id:"victories",title:"Guild vanguard",description:"Win three verified expeditions while in your guild.",target:3,xp:75},
 {id:"daily_duties",title:"Guild devotion",description:"Claim all three main daily quest rewards while in your guild.",target:3,xp:100}
] as const;
type Db=PoolClient|Pool;
export const GUILD_LEVEL_XP=1000;
export async function guildMissionState(db:Db,id:string,guildId:string){
 const r=await db.query<{day:string;checkin:number;victories:number;daily_duties:number;claimed:string[]}>(
  "WITH membership AS (SELECT joined_at FROM guild_members WHERE player_id=$1 AND guild_id=$2), today AS (SELECT (now() AT TIME ZONE 'UTC')::date AS d) SELECT to_char(today.d,'YYYY-MM-DD') AS day, count(DISTINCT l.ref_id) FILTER(WHERE l.reason='online_daily_quest' AND l.ref_id=to_char(today.d,'YYYY-MM-DD')||':checkin')::int AS checkin, count(*) FILTER(WHERE l.reason='coop_monster_defeat')::int AS victories, count(DISTINCT l.ref_id) FILTER(WHERE l.reason='online_daily_quest' AND l.ref_id IN (to_char(today.d,'YYYY-MM-DD')||':checkin',to_char(today.d,'YYYY-MM-DD')||':victories',to_char(today.d,'YYYY-MM-DD')||':shared'))::int AS daily_duties, ARRAY(SELECT mission_id FROM guild_mission_claims WHERE player_id=$1 AND mission_day=today.d) AS claimed FROM membership CROSS JOIN today LEFT JOIN currency_ledger l ON l.player_id=$1 AND l.currency_id='gold' AND l.delta>0 AND l.reason IN ('online_daily_quest','coop_monster_defeat') AND l.created_at>=membership.joined_at AND l.created_at>=today.d::timestamp AT TIME ZONE 'UTC' AND l.created_at<(today.d+1)::timestamp AT TIME ZONE 'UTC' GROUP BY today.d",[id,guildId]);
 const v=r.rows[0];if(!v)return null;
 return {day:v.day,rows:guildMissions.map(m=>{const claimed=v.claimed.includes(m.id);const progress=claimed?m.target:Math.min(m.target,v[m.id]);return {...m,tokens:m.xp/5,progress,claimed,canClaim:!claimed&&progress>=m.target};})};
}
export async function guildContributionRanking(db:Db,id:string,guildId:string){
 const r=await db.query("SELECT p.id,p.name,coalesce(sum(c.xp),0)::int AS xp FROM guild_members m JOIN players p ON p.id=m.player_id JOIN accounts a ON a.id=p.account_id LEFT JOIN guild_mission_claims c ON c.guild_id=m.guild_id AND c.player_id=m.player_id AND c.claimed_at>=m.joined_at AND c.mission_day>=date_trunc('week',now() AT TIME ZONE 'UTC')::date AND c.mission_day<=(now() AT TIME ZONE 'UTC')::date WHERE m.guild_id=$2 AND a.status='active' AND EXISTS(SELECT 1 FROM guild_members viewer WHERE viewer.player_id=$1 AND viewer.guild_id=m.guild_id) AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=p.id) OR (b.player_id=p.id AND b.blocked_id=$1)) GROUP BY p.id,p.name ORDER BY xp DESC,p.name,p.id",[id,guildId]);
 return r.rows;
}