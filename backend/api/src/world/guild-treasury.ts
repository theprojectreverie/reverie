import type {Pool,PoolClient} from "pg";
export const GUILD_DAILY_GOLD_CAP=1000;
type Db=Pool|PoolClient;
export async function donatedToday(db:Db,id:string){
 const r=await db.query("SELECT COALESCE(-sum(delta),0)::int AS total FROM currency_ledger WHERE player_id=$1 AND currency_id='gold' AND reason='guild_donation' AND delta<0 AND created_at>=date_trunc('day',now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AND created_at<(date_trunc('day',now() AT TIME ZONE 'UTC')+interval '1 day') AT TIME ZONE 'UTC'",[id]);
 return Number(r.rows[0].total);
}
export async function guildTreasury(db:Db,id:string,guildId:string){
 const q=await db.query("SELECT COALESCE((SELECT sum(delta) FROM guild_bank_ledger WHERE guild_id=$2 AND currency_id='gold'),0)::text AS gold,COALESCE((SELECT balance FROM player_currencies WHERE player_id=$1 AND currency_id='gold'),0)::text AS wallet WHERE EXISTS(SELECT 1 FROM guild_members WHERE guild_id=$2 AND player_id=$1)",[id,guildId]);
 if(!q.rows[0])return null;
 const history=await db.query("SELECT l.id::text,l.delta::text AS amount,l.reason,l.created_at AS \"createdAt\",CASE WHEN gm.player_id IS NOT NULL AND a.status='active' AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=l.player_id) OR (b.player_id=l.player_id AND b.blocked_id=$1)) THEN p.name ELSE 'Guild contributor' END AS name FROM guild_bank_ledger l LEFT JOIN guild_members gm ON gm.player_id=l.player_id AND gm.guild_id=l.guild_id LEFT JOIN players p ON p.id=l.player_id LEFT JOIN accounts a ON a.id=p.account_id WHERE l.guild_id=$2 AND l.currency_id='gold' AND (l.reason='guild_donation' OR l.reason LIKE 'guild_perk:%') AND EXISTS(SELECT 1 FROM guild_members WHERE guild_id=$2 AND player_id=$1) ORDER BY l.created_at DESC,l.id DESC LIMIT 20",[id,guildId]);
 return {...q.rows[0],dailyCap:GUILD_DAILY_GOLD_CAP,donatedToday:await donatedToday(db,id),history:history.rows};
}