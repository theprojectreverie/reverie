import type {Pool,PoolClient} from "pg";
import {randomInt} from "node:crypto";
import {actionSchema,fingerprint,replayStoryCombat} from "./story-combat-service.js";
import {STARTER_PARTY} from "./character-xp.js";
import {retiredPlayableIds} from "./summon.js";
const GROUP="cassien_encounter";
const MAX_HP=12000, DAILY_ATTEMPTS=3, MIN_DAMAGE=100;
const rewards={gold:500,crystals:50};
type Db=Pool|PoolClient;
type Replay=Parameters<typeof replayStoryCombat>[1];
type View=Extract<Awaited<ReturnType<typeof replayStoryCombat>>,{ok:true}>;
type State=Replay&{version:string;view:View};
type Attempt={id:string;guild_id:string|null;week:string;joined:string;status:string;damage:number;state:State};
const reject=(reason:string)=>({ok:false as const,reason});
const result=(a:Attempt,replayed:boolean)=>({ok:true as const,attemptId:a.id,view:a.state.view,status:a.status,damage:a.damage,replayed});
const weekSql="date_trunc('week',now() AT TIME ZONE 'UTC')::date";
const daySql="(now() AT TIME ZONE 'UTC')::date";
async function period(db:Db){return (await db.query("SELECT to_char("+weekSql+",'YYYY-MM-DD') AS week,to_char("+daySql+",'YYYY-MM-DD') AS day")).rows[0] as {week:string;day:string};}
async function membership(db:Db,id:string,lock=false){
 return (await db.query<{guild_id:string;joined:string}>("SELECT guild_id,joined_at::text AS joined FROM guild_members WHERE player_id=$1"+(lock?" FOR SHARE":""),[id])).rows[0];
}
async function playerLock(db:PoolClient,id:string){return !!(await db.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.status='active' FOR UPDATE OF p",[id])).rowCount;}
const fields="id,guild_id,to_char(week_start,'YYYY-MM-DD') AS week,joined_at::text AS joined,status,damage,state";
async function attemptsToday(db:Db,id:string,day:string){return (await db.query("SELECT count(*)::int AS n FROM guild_raid_attempts WHERE player_id=$1 AND attempt_day=$2",[id,day])).rows[0].n as number;}
async function ownDamage(db:Db,id:string,guild:string,week:string,joined:string){return (await db.query("SELECT coalesce(sum(damage),0)::int AS n FROM guild_raid_attempts WHERE player_id=$1 AND guild_id=$2 AND week_start=$3 AND joined_at=$4",[id,guild,week,joined])).rows[0].n as number;}
async function claimed(db:Db,id:string,week:string){return !!(await db.query("SELECT 1 FROM guild_raid_claims WHERE player_id=$1 AND week_start=$2",[id,week])).rowCount;}
export async function raidOverview(db:Db,id:string,guildId:string){
 const m=await membership(db,id);if(!m||m.guild_id!==guildId)return null;
 const {week,day}=await period(db);
 const r=(await db.query("SELECT hp FROM guild_raids WHERE guild_id=$1 AND week_start=$2",[guildId,week])).rows[0];
 const damage=await ownDamage(db,id,guildId,week,m.joined),used=await attemptsToday(db,id,day),already=await claimed(db,id,week);
 const active=(await db.query("SELECT id FROM guild_raid_attempts WHERE player_id=$1 AND guild_id=$2 AND week_start=$3 AND joined_at=$4 AND status='active'",[id,guildId,week,m.joined])).rows[0];
  const hp=r?.hp??MAX_HP;
 const ranking=await db.query("SELECT p.name,sum(t.damage)::int AS damage FROM guild_raid_attempts t JOIN guild_members gm ON gm.player_id=t.player_id AND gm.guild_id=t.guild_id AND gm.joined_at=t.joined_at JOIN players p ON p.id=t.player_id JOIN accounts a ON a.id=p.account_id WHERE t.guild_id=$2 AND t.week_start=$3 AND t.damage>0 AND a.status='active' AND EXISTS(SELECT 1 FROM guild_members v WHERE v.player_id=$1 AND v.guild_id=t.guild_id) AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=p.id) OR (b.player_id=p.id AND b.blocked_id=$1)) GROUP BY p.id,p.name ORDER BY damage DESC,p.name,p.id LIMIT 45",[id,guildId,week]);
 return {name:"Crimson Echo",week,day,hp,maxHp:MAX_HP,attemptsUsed:used,attemptsPerDay:DAILY_ATTEMPTS,damage,minDamage:MIN_DAMAGE,rewards,ranking:ranking.rows,claimed:already,canClaim:hp===0&&damage>=MIN_DAMAGE&&!already,activeAttemptId:hp>0?active?.id??null:null};
}
export async function startGuildRaid(db:PoolClient,id:string,guildId:string){
 if(!await playerLock(db,id))return reject("player_unavailable");
 const m=await membership(db,id,true);if(!m||m.guild_id!==guildId)return reject("guild_membership_required");
 const {week,day}=await period(db);
 const active=(await db.query<Attempt>("SELECT "+fields+" FROM guild_raid_attempts WHERE player_id=$1 AND status='active' FOR UPDATE",[id])).rows[0];
 const raid=(await db.query("SELECT hp FROM guild_raids WHERE guild_id=$1 AND week_start=$2",[guildId,week])).rows[0];
 if(raid?.hp===0)return reject("raid_defeated");
 if(active&&active.guild_id===guildId&&active.week===week&&active.joined===m.joined)return result(active,true);
 if(active)await db.query("UPDATE guild_raid_attempts SET status='abandoned' WHERE id=$1",[active.id]);
 if(await attemptsToday(db,id,day)>=DAILY_ATTEMPTS)return reject("raid_attempt_limit");
 const roster=(await db.query("SELECT char_id,level,xp::text,ascension,awakening,bond,dupes,skill_levels FROM owned_characters WHERE player_id=$1 AND NOT(char_id=ANY($2::text[])) ORDER BY char_id FOR UPDATE",[id,retiredPlayableIds])).rows;
 const selected=(await db.query("SELECT oc.char_id FROM party_members pm JOIN owned_characters oc ON oc.id=pm.character_id AND oc.player_id=pm.player_id WHERE pm.player_id=$1 AND NOT(oc.char_id=ANY($2::text[])) ORDER BY pm.slot",[id,retiredPlayableIds])).rows.map(r=>r.char_id);
 const ids=selected.length?selected:STARTER_PARTY.filter(c=>roster.some(r=>r.char_id===c));
 const gear=(await db.query("SELECT oc.char_id,e.slot,e.item_id,e.enhancement_level,e.reroll_stat,e.reroll_value FROM character_equipment e JOIN owned_characters oc ON oc.id=e.character_id AND oc.player_id=e.player_id WHERE e.player_id=$1",[id])).rows;
 const party=ids.map(c=>{const row=roster.find(r=>r.char_id===c);return row?{...row,equipment:gear.filter(e=>e.char_id===c)}:null;});
 if(party.length<1||party.length>4||party.some(r=>!r))return reject("invalid_party");
 const input:Replay={seed:randomInt(1,2147483647),party:party as Replay["party"],collectionCount:roster.length,actions:[]};
 const version=fingerprint(),view=await replayStoryCombat(GROUP,input);
 if(!view.ok)return view;
 if(view.status!=="active"||version!==fingerprint())return reject("raid_content_changed");
 const state:State={...input,version,view};
 const row=(await db.query<Attempt>("INSERT INTO guild_raid_attempts(guild_id,player_id,week_start,attempt_day,joined_at,state) VALUES($1,$2,$3,$4,$5,$6) RETURNING "+fields,[guildId,id,week,day,m.joined,JSON.stringify(state)])).rows[0]!;
 return result(row,false);
}
export async function actGuildRaid(db:PoolClient,id:string,guildId:string,attemptId:string,sequence:number,raw:unknown){
 const action=actionSchema.safeParse(raw);
 if(!action.success||!Number.isInteger(sequence)||sequence<1||sequence>256)return reject("invalid_action");
 if(!await playerLock(db,id))return reject("player_unavailable");
 const m=await membership(db,id,true);if(!m||m.guild_id!==guildId)return reject("guild_membership_required");
 const {week}=await period(db);
 const a=(await db.query<Attempt>("SELECT "+fields+" FROM guild_raid_attempts WHERE id=$1 AND player_id=$2 AND guild_id=$3 AND week_start=$4 AND joined_at=$5 FOR UPDATE",[attemptId,id,guildId,week,m.joined])).rows[0];
 if(!a)return reject("raid_attempt_unavailable");
 const state=a.state;
 if(a.status!=="abandoned"&&sequence===state.actions.length&&JSON.stringify(actionSchema.parse(state.actions[sequence-1]))===JSON.stringify(action.data))return result(a,true);
 if(a.status!=="active")return reject("raid_attempt_finished");
 if(sequence!==state.actions.length+1||state.view.actorUid!==action.data.actorUid)return reject("invalid_sequence_or_actor");
 if(state.version!==fingerprint())return reject("raid_content_changed");
 const prior=(await db.query("SELECT hp FROM guild_raids WHERE guild_id=$1 AND week_start=$2",[guildId,week])).rows[0];
 if(prior?.hp===0)return reject("raid_defeated");
 const next={...state,actions:[...state.actions,action.data]};
 const view=await replayStoryCombat(GROUP,next);
 if(!view.ok)return view;
 if(state.version!==fingerprint())return reject("raid_content_changed");
 next.view=view;
 const status=view.status==="active"&&sequence===256?"defeat":view.status;
 let damage=0;
 if(status!=="active"){
  // Only the trusted final combat snapshot contributes. Healing restores local HP;
  // overkill and concurrent completions cannot overdraw the shared health pool.
  const enemy=view.units.find(u=>typeof u==="object"&&u!==null&&(u as {team?:number}).team===1) as {hp:number;maxHp:number}|undefined;
  if(!enemy||!Number.isFinite(enemy.hp)||!Number.isFinite(enemy.maxHp)||enemy.maxHp<=0)return reject("raid_invalid_snapshot");
  const requested=Math.max(0,Math.min(MAX_HP,Math.floor(enemy.maxHp-Math.max(0,enemy.hp))));
  await db.query("INSERT INTO guild_raids(guild_id,week_start,hp) VALUES($1,$2,$3) ON CONFLICT DO NOTHING",[guildId,week,MAX_HP]);
  const row=(await db.query("SELECT hp FROM guild_raids WHERE guild_id=$1 AND week_start=$2 FOR UPDATE",[guildId,week])).rows[0];
  damage=Math.min(requested,row.hp);
  if(damage)await db.query("UPDATE guild_raids SET hp=hp-$3,defeated_at=CASE WHEN hp=$3 THEN now() ELSE defeated_at END WHERE guild_id=$1 AND week_start=$2",[guildId,week,damage]);
 }
 await db.query("UPDATE guild_raid_attempts SET state=$2,status=$3,damage=$4 WHERE id=$1",[a.id,JSON.stringify(next),status,damage]);
 a.state=next;a.status=status;a.damage=damage;
 return result(a,false);
}
export async function abandonGuildRaid(db:PoolClient,id:string,guildId:string,attemptId:string){
 if(!await playerLock(db,id))return reject("player_unavailable");
 const m=await membership(db,id,true);if(!m||m.guild_id!==guildId)return reject("guild_membership_required");
 const r=await db.query("UPDATE guild_raid_attempts SET status='abandoned' WHERE id=$1 AND player_id=$2 AND guild_id=$3 AND joined_at=$4 AND status='active'",[attemptId,id,guildId,m.joined]);
 return r.rowCount?{ok:true as const}:reject("raid_attempt_unavailable");
}
export async function claimGuildRaid(db:PoolClient,id:string,guildId:string,expectedWeek:string){
 if(!await playerLock(db,id))return reject("player_unavailable");
 const m=await membership(db,id,true);if(!m||m.guild_id!==guildId)return reject("guild_membership_required");
 const overview=await raidOverview(db,id,guildId);
 if(!overview||overview.week!==expectedWeek)return reject("raid_week_changed");
 if(overview.claimed)return {ok:true as const,replayed:true,rewards};
 if(!overview.canClaim)return reject("raid_reward_unavailable");
 const inserted=await db.query("INSERT INTO guild_raid_claims(player_id,week_start,guild_id) VALUES($1,$2,$3) ON CONFLICT DO NOTHING RETURNING player_id",[id,expectedWeek,guildId]);
 if(!inserted.rowCount)return reject("raid_reward_unavailable");
 for(const [currency,amount] of Object.entries(rewards)){
  const wallet=(await db.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,$2,$3) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[id,currency,amount])).rows[0];
  await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'guild_raid_reward','guild_raid',$5,$6)",[id,currency,amount,wallet.balance,expectedWeek,"guild-raid:"+expectedWeek+":"+currency]);
 }
 return {ok:true as const,replayed:false,rewards};
}