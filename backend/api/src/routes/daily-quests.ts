import {seasonChallenges} from "../world/season-challenges.js";
import {seasonalTitles,championTitle} from "../world/season-rewards.js";
import {collectionCharacterIds,ascendedBonds} from "../world/summon.js";
import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import type {PoolClient} from "pg";
import {z} from "zod";
import {pool} from "../db.js";
const tasks=[
 {id:"checkin",title:"Adventurer's Check-in",description:"Check in to your online account today.",target:1,gold:150,crystals:0},
 {id:"victories",title:"Expedition Duty",description:"Contribute to three rewarded online expedition victories.",target:3,gold:300,crystals:40},
 {id:"shared",title:"United Front",description:"Defeat an enemy with another contributing party member.",target:1,gold:250,crystals:25},
 {id:"bonus",title:"Daily Devotion",description:"Claim all three online daily quest rewards.",target:3,gold:500,crystals:75}
] as const;
type Progress={date:string;victories:number;shared_victories:number;claimed:string[];encounter_credits:string[]};
const daySql="(CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date";
const weekSql="date_trunc('week',CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date";
const weeklyTasks=[
 {id:"checkins",title:"Faithful Adventurer",description:"Claim online check-in on five different days this week.",target:5,gold:600,crystals:60},
 {id:"victories",title:"Expedition Veteran",description:"Earn twelve daily expedition victory credits (up to three per day).",target:12,gold:1000,crystals:100},
 {id:"shared",title:"Together We Stand",description:"Earn shared victory credit on three different days.",target:3,gold:800,crystals:80},
 {id:"bonus",title:"Weekly Devotion",description:"Claim all three weekly quest rewards.",target:3,gold:1500,crystals:150}
] as const;
type WeeklyProgress={date:string;checkins:number;victories:number;shared:number;claimed:string[]};
function weeklyRows(p:WeeklyProgress){
 return weeklyTasks.map(t=>{
 const progress=Math.min(t.target,t.id==="checkins"?p.checkins:t.id==="victories"?p.victories:t.id==="shared"?p.shared:weeklyTasks.slice(0,3).filter(x=>p.claimed.includes(x.id)).length);
 const claimed=p.claimed.includes(t.id);
 return {...t,progress,claimed,can_claim:!claimed&&progress>=t.target};
 });
}
function weeklyProgressSql(){return `SELECT to_char(${weekSql},'YYYY-MM-DD') AS date,(SELECT count(DISTINCT day)::int FROM (SELECT quest_day AS day FROM online_daily_quests WHERE player_id=$1 AND quest_day>=${weekSql} AND quest_day<=${daySql} AND 'checkin'=ANY(claimed) UNION SELECT d::date AS day FROM generate_series(${weekSql},${daySql},interval '1 day') d WHERE EXISTS (SELECT 1 FROM currency_ledger WHERE player_id=$1 AND reason='online_daily_quest' AND ref_id=to_char(d,'YYYY-MM-DD')||':checkin' AND delta>0)) checked_days) AS checkins,COALESCE((SELECT sum(victories)::int FROM online_daily_quests WHERE player_id=$1 AND quest_day>=${weekSql} AND quest_day<=${daySql}),0) AS victories,COALESCE((SELECT sum(shared_victories)::int FROM online_daily_quests WHERE player_id=$1 AND quest_day>=${weekSql} AND quest_day<=${daySql}),0) AS shared,ARRAY(SELECT DISTINCT unnest(COALESCE((SELECT claimed FROM online_weekly_quests WHERE player_id=$1 AND week_start=${weekSql}),'{}'::text[]) || ARRAY(SELECT split_part(ref_id,':',2) FROM currency_ledger WHERE player_id=$1 AND reason='online_weekly_quest' AND ref_id LIKE to_char(${weekSql},'YYYY-MM-DD')||':%' AND delta>0))) AS claimed`;}
async function weeklyProgress(db:PoolClient|typeof pool,id:string):Promise<WeeklyProgress>{
 const q=await db.query<WeeklyProgress>(weeklyProgressSql(),[id]);
 return q.rows[0]!;
}
function timing(date:string,days:number){
 return {serverTime:Date.now(),resetAt:Date.parse(date+"T00:00:00Z")+days*86400000};
}
export async function onlineWeeklyClaimable(id:string):Promise<number>{return weeklyRows(await weeklyProgress(pool,id)).filter(x=>x.can_claim).length;}

const monthSql="date_trunc('month',CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date";
const monthlyTasks=[
 {id:"checkins",title:"Steadfast Adventurer",description:"Claim online check-in on 15 different days this month.",target:15,gold:2500,crystals:100},
 {id:"victories",title:"Expedition Champion",description:"Earn 30 daily expedition victory credits this month (up to three per day).",target:30,gold:3500,crystals:150},
 {id:"shared",title:"Bound by Courage",description:"Earn shared victory credit on 10 different days this month.",target:10,gold:3000,crystals:100},
 {id:"bonus",title:"Monthly Devotion",description:"Claim all three monthly quest rewards.",target:3,gold:5000,crystals:150}
] as const;
function monthlyRows(p:WeeklyProgress){
 return monthlyTasks.map(t=>{
 const progress=Math.min(t.target,t.id==="checkins"?p.checkins:t.id==="victories"?p.victories:t.id==="shared"?p.shared:monthlyTasks.slice(0,3).filter(x=>p.claimed.includes(x.id)).length);
 const claimed=p.claimed.includes(t.id);
 return {...t,progress,claimed,can_claim:!claimed&&progress>=t.target};
 });
}
function monthlyProgressSql(){return `SELECT to_char(${monthSql},'YYYY-MM-DD') AS date,(SELECT count(DISTINCT day)::int FROM (SELECT quest_day AS day FROM online_daily_quests WHERE player_id=$1 AND quest_day>=${monthSql} AND quest_day<=${daySql} AND 'checkin'=ANY(claimed) UNION SELECT d::date AS day FROM generate_series(${monthSql},${daySql},interval '1 day') d WHERE EXISTS (SELECT 1 FROM currency_ledger WHERE player_id=$1 AND reason='online_daily_quest' AND ref_id=to_char(d,'YYYY-MM-DD')||':checkin' AND delta>0)) checked_days) AS checkins,COALESCE((SELECT sum(victories)::int FROM online_daily_quests WHERE player_id=$1 AND quest_day>=${monthSql} AND quest_day<=${daySql}),0) AS victories,COALESCE((SELECT sum(shared_victories)::int FROM online_daily_quests WHERE player_id=$1 AND quest_day>=${monthSql} AND quest_day<=${daySql}),0) AS shared,ARRAY(SELECT DISTINCT unnest(COALESCE((SELECT claimed FROM online_monthly_quests WHERE player_id=$1 AND month_start=${monthSql}),'{}'::text[]) || ARRAY(SELECT split_part(ref_id,':',2) FROM currency_ledger WHERE player_id=$1 AND reason='online_monthly_quest' AND ref_id LIKE to_char(${monthSql},'YYYY-MM-DD')||':%' AND delta>0))) AS claimed`;}
async function monthlyProgress(db:PoolClient|typeof pool,id:string):Promise<WeeklyProgress>{
 const q=await db.query<WeeklyProgress>(monthlyProgressSql(),[id]);
 return q.rows[0]!;
}
export function monthlyTiming(date:string){
 const start=new Date(date+"T00:00:00Z");
 return {serverTime:Date.now(),resetAt:Date.UTC(start.getUTCFullYear(),start.getUTCMonth()+1,1)};
}
export async function onlineMonthlyClaimable(id:string):Promise<number>{return monthlyRows(await monthlyProgress(pool,id)).filter(x=>x.can_claim).length;}

// Every featured encounter is an alternative route to the existing shared quest.
 // The slot, claim key and payout stay stable; weekly shared credit still requires real co-op.
const featured=[
 null,
 {tag:"gardens",title:"Garden Sentinel",objective:"Defeat an enemy in Royal Gardens"},
 {tag:"gate",title:"Royal Watch",objective:"Defeat a Royal Gate patrol enemy"},
 {tag:"willow",title:"Willow Hunt",objective:"Defeat the Willow Slime"},
 {tag:"cassien",title:"Crimson Challenge",objective:"Defeat Cassien"},
 {tag:"revienna",title:"Eclipse Challenge",objective:"Defeat the Eclipse Sovereign"},
 {tag:"willow",title:"Willow Expedition",objective:"Defeat the Willow Slime"}
] as const;
export function featuredEncounter(date:string){
 return featured[new Date(date+"T00:00:00Z").getUTCDay()]??null;
}
export function encounterCredit(region:string,monsterId:string):string|null{
 if(region==="six_zone_royal_gardens"&&/^(rose_slime|crownling)_garden_[1-9]$/.test(monsterId))return "gardens";
 if(region==="six_zone_royal_gate"&&/^royal_gate_patrol_[12]$/.test(monsterId))return "gate";
 if(region==="six_zone_willow_fields"&&monsterId==="willow_slime_1")return "willow";
 if(region==="six_zone_forsaken_ruins"&&monsterId==="cassien_encounter")return "cassien";
 if(region==="six_zone_ruined_tower"&&monsterId==="revienna_encounter")return "revienna";
 return null;
}
export function rows(p:Progress){
 const rotation=featuredEncounter(p.date);
 return tasks.map(t=>{
  const progress=t.id==="checkin"?1:t.id==="victories"?p.victories:t.id==="shared"?Math.max(p.shared_victories,rotation&&p.encounter_credits.includes(rotation.tag)?1:0):tasks.slice(0,3).filter(x=>p.claimed.includes(x.id)).length;
  const claimed=p.claimed.includes(t.id);
  const display=t.id==="shared"&&rotation?{title:rotation.title,description:rotation.objective+" in an online expedition, or win with another contributing player."}:{};
  return {...t,...display,progress,claimed,can_claim:!claimed&&progress>=t.target};
 });
}
const activityTasks=[
 {id:"activity_1",title:"Daily Momentum",description:"Claim one of today's three main online quest rewards.",target:1,gold:100,crystals:0},
 {id:"activity_3",title:"Daily Dedication",description:"Claim all three main online quest rewards.",target:3,gold:200,crystals:0}
] as const;
export function activityRows(p:Progress){
 const progress=tasks.slice(0,3).filter(t=>p.claimed.includes(t.id)).length;
 return activityTasks.map(t=>({...t,progress:Math.min(t.target,progress),claimed:p.claimed.includes(t.id),can_claim:!p.claimed.includes(t.id)&&progress>=t.target}));
}
function dailyRows(p:Progress){return [...rows(p),...activityRows(p)];}
function progressSql(){return `SELECT to_char(${daySql},'YYYY-MM-DD') AS date,COALESCE(d.victories,0) AS victories,COALESCE(d.shared_victories,0) AS shared_victories,ARRAY(SELECT DISTINCT unnest(COALESCE(d.claimed,'{}'::text[]) || ARRAY(SELECT split_part(ref_id,':',2) FROM currency_ledger WHERE player_id=$1 AND reason IN ('online_daily_quest','online_activity_quest') AND ref_id LIKE to_char(${daySql},'YYYY-MM-DD')||':%' AND delta>0))) AS claimed,COALESCE(d.encounter_credits,'{}'::text[]) AS encounter_credits FROM (SELECT 1) x LEFT JOIN online_daily_quests d ON d.player_id=$1 AND d.quest_day=${daySql}`;}
async function progress(db:PoolClient|typeof pool,id:string):Promise<Progress>{
 const q=await db.query<Progress>(progressSql(),[id]);
 return q.rows[0]!;
}
export async function onlineDailyClaimable(id:string):Promise<number>{return dailyRows(await progress(pool,id)).filter(x=>x.can_claim).length;}
export async function onlineQuestSummary(id:string){
 const q=await pool.query<{daily:Progress;weekly:WeeklyProgress;monthly:WeeklyProgress}>(`SELECT (SELECT row_to_json(d) FROM (${progressSql()}) d) AS daily,(SELECT row_to_json(w) FROM (${weeklyProgressSql()}) w) AS weekly,(SELECT row_to_json(m) FROM (${monthlyProgressSql()}) m) AS monthly`,[id]);
 const p=q.rows[0]!;
 return {dailyClaimable:dailyRows(p.daily).filter(x=>x.can_claim).length,weeklyClaimable:weeklyRows(p.weekly).filter(x=>x.can_claim).length,monthlyClaimable:monthlyRows(p.monthly).filter(x=>x.can_claim).length};
}

// Called only inside the same transaction as the authoritative defeat payout.
export async function recordOnlineDailyVictory(db:PoolClient,id:string,shared:boolean,region="",monsterId=""){
 const tag=encounterCredit(region,monsterId);
 await db.query(`INSERT INTO online_daily_quests(player_id,quest_day,victories,shared_victories,encounter_credits) VALUES($1,${daySql},1,$2,$3::text[]) ON CONFLICT(player_id,quest_day) DO UPDATE SET victories=LEAST(3,online_daily_quests.victories+1),shared_victories=GREATEST(online_daily_quests.shared_victories,EXCLUDED.shared_victories),encounter_credits=ARRAY(SELECT DISTINCT unnest(online_daily_quests.encounter_credits||EXCLUDED.encounter_credits))`,[id,shared?1:0,tag?[tag]:[]]);
}
async function identity(req:FastifyRequest,reply:FastifyReply):Promise<string|null>{
 try{await req.jwtVerify();const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
 if(c.sub&&c.playerId&&Number.isInteger(c.tokenVersion)){
 const q=await pool.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3",[c.playerId,c.sub,c.tokenVersion]);if(q.rows[0])return q.rows[0].id;
 }}catch{}
 reply.code(401).send({error:"authentication_required"});return null;
}
const achievementTasks=[
 {id:"first_duty",title:"First Steps",description:"Claim your first online daily quest reward.",target:1,gold:200,crystals:20},
 {id:"ten_victories",title:"Proven Warrior",description:"Contribute to ten rewarded online expedition victories.",target:10,gold:1000,crystals:100},
 {id:"seven_days",title:"Unwavering Resolve",description:"Claim Daily Devotion on seven different days.",target:7,gold:1500,crystals:150},
 {id:"cassien",title:"Crimson Conqueror",description:"Contribute to a victory over Cassien.",target:1,gold:1000,crystals:100},
 {id:"revienna",title:"Eclipse Conqueror",description:"Contribute to a victory over the Eclipse Sovereign.",target:1,gold:1500,crystals:150},
 {id:"month_complete",title:"A Legend in Reverie",description:"Claim your first Monthly Devotion reward.",target:1,gold:2000,crystals:200},
 {id:"landmark_discoverer",title:"Hidden Paths",description:"Personally complete two distinct online exploration objectives.",target:2,gold:500,crystals:25},
 {id:"regional_explorer",title:"Beyond the Horizon",description:"Personally complete exploration objectives in two different online regions.",target:2,gold:800,crystals:50},
 {id:"legendary_collection",title:"Legendary Assembly",description:"Own three distinct legendary playable characters in your online roster.",target:3,gold:800,crystals:50},
 {id:"mythic_collection",title:"Mythic Awakening",description:"Own a mythic playable character in your online roster.",target:1,gold:1200,crystals:75},
 {id:"first_ascension",title:"Beyond the Limit",description:"Own a playable character at ascension tier one or higher.",target:1,gold:500,crystals:25},
 {id:"mythic_ascended",title:"Mythic Transcendence",description:"Own one fully ascended mythic character (tier three).",target:1,gold:1500,crystals:100},
 {id:"ascended_collection",title:"Ascended Vanguard",description:"Own three distinct fully ascended mythic characters.",target:3,gold:2000,crystals:125},
 {id:"siblings_ascended",title:"Unbroken Sibling Bond",description:"Own fully ascended Mythic Gerald and Mythic Lilith.",target:2,gold:2500,crystals:150},
 {id:"eclipse_ascended",title:"Eclipse Vow",description:"Own fully ascended Mythic Ravienna and Mythic Cassien.",target:2,gold:2500,crystals:150}
] as const;
// Titles are cosmetic and unlocked only by a successfully claimed achievement.
export const playerTitles=[
 {id:"first_duty",name:"Dawn Wanderer",category:"Adventure",achievement:"First Steps"},
 {id:"ten_victories",name:"Proven Warrior",category:"Combat",achievement:"Proven Warrior"},
 {id:"seven_days",name:"Unwavering",category:"Devotion",achievement:"Unwavering Resolve"},
 {id:"cassien",name:"Crimson Conqueror",category:"Bosses",achievement:"Crimson Conqueror"},
 {id:"revienna",name:"Eclipse Conqueror",category:"Bosses",achievement:"Eclipse Conqueror"},
 {id:"month_complete",name:"Legend of Reverie",category:"Devotion",achievement:"A Legend in Reverie"},
 {id:"landmark_discoverer",name:"Pathfinder",category:"Exploration",achievement:"Hidden Paths"},
 {id:"regional_explorer",name:"Horizon Walker",category:"Exploration",achievement:"Beyond the Horizon"},
 {id:"legendary_collection",name:"Legend Keeper",category:"Collection",achievement:"Legendary Assembly"},
 {id:"mythic_collection",name:"Mythic Collector",category:"Collection",achievement:"Mythic Awakening"},
 {id:"first_ascension",name:"Limit Breaker",category:"Ascension",achievement:"Beyond the Limit"},
 {id:"mythic_ascended",name:"Transcendent",category:"Ascension",achievement:"Mythic Transcendence"},
 {id:"ascended_collection",name:"Ascended Vanguard",category:"Ascension",achievement:"Ascended Vanguard"},
 {id:"siblings_ascended",name:"Unbroken Bond",category:"Bonds",achievement:"Unbroken Sibling Bond"},
 {id:"eclipse_ascended",name:"Eclipsebound",category:"Bonds",achievement:"Eclipse Vow"}
] as const;
// Reusable projection for player alias p. Only ledger-proven titles are public.
export const verifiedTitleSql="CASE WHEN EXISTS(SELECT 1 FROM currency_ledger cl WHERE cl.player_id=p.id AND cl.reason='online_achievement' AND cl.currency_id='gold' AND cl.delta>0 AND cl.ref_id=p.settings->>'profile_title') OR EXISTS(SELECT 1 FROM online_season_results sr WHERE sr.player_id=p.id AND sr.rank=1 AND sr.claimed_at IS NOT NULL AND ('season_'||CASE sr.category WHEN 'achievements' THEN 'achievement' ELSE sr.category END||'_champion')=p.settings->>'profile_title') THEN p.settings->>'profile_title' ELSE '' END";
export function titleName(value:unknown):string{return [...playerTitles,...seasonalTitles].find(t=>t.id===value)?.name??"";}
export async function profileTitles(id:string){
 const q=await pool.query<{equipped:string;unlocked:string[];pins:unknown}>("SELECT COALESCE(p.settings->>'profile_title','') AS equipped,p.settings->'achievement_pins' AS pins,ARRAY(SELECT DISTINCT ref_id FROM currency_ledger WHERE player_id=p.id AND reason='online_achievement' AND currency_id='gold' AND delta>0) AS unlocked FROM players p WHERE p.id=$1",[id]);
 const row=q.rows[0];
 const titles=playerTitles.map(t=>({...t,unlocked:row?.unlocked.includes(t.id)??false}));
 const winners=await pool.query<{category:string}>("SELECT DISTINCT category FROM online_season_results WHERE player_id=$1 AND rank=1 AND claimed_at IS NOT NULL",[id]);
 const seasonTitles=seasonalTitles.filter(t=>winners.rows.some(r=>championTitle(r.category)===t.id)).map(t=>({...t,unlocked:true}));
 const equipped=[...titles,...seasonTitles].some(t=>t.id===row?.equipped&&t.unlocked)?row!.equipped:"";
 const pins=Array.isArray(row?.pins)?[...new Set(row.pins.filter((id):id is string=>typeof id==="string"&&titles.some(t=>t.id===id&&t.unlocked)))].slice(0,3):[];
 return {equippedTitle:equipped,title:titleName(equipped),titles,seasonTitles,pins,achievementCount:titles.filter(t=>t.unlocked).length};
}
async function achievementRows(db:PoolClient|typeof pool,id:string){
 const q=await db.query<{first_duty:number;ten_victories:number;seven_days:number;cassien:number;revienna:number;month_complete:number;landmark_discoverer:number;regional_explorer:number;legendary_collection:number;mythic_collection:number;first_ascension:number;mythic_ascended:number;ascended_collection:number;siblings_ascended:number;eclipse_ascended:number;claimed:string[]}>("SELECT (count(*) FILTER(WHERE reason='online_daily_quest' AND currency_id='gold'))::int AS first_duty,(count(*) FILTER(WHERE reason='coop_monster_defeat' AND currency_id='gold'))::int AS ten_victories,(count(*) FILTER(WHERE reason='online_daily_quest' AND currency_id='gold' AND split_part(ref_id,':',2)='bonus'))::int AS seven_days,(count(*) FILTER(WHERE reason='coop_monster_defeat' AND currency_id='gold' AND idempotency_key LIKE '%:cassien_encounter'))::int AS cassien,(count(*) FILTER(WHERE reason='coop_monster_defeat' AND currency_id='gold' AND idempotency_key LIKE '%:revienna_encounter'))::int AS revienna,(count(*) FILTER(WHERE reason='online_monthly_quest' AND currency_id='gold' AND split_part(ref_id,':',2)='bonus'))::int AS month_complete,(SELECT count(*)::int FROM online_achievement_exploration WHERE player_id=$1) AS landmark_discoverer,(SELECT count(DISTINCT region_id)::int FROM online_achievement_exploration WHERE player_id=$1) AS regional_explorer,(SELECT count(DISTINCT char_id)::int FROM owned_characters WHERE player_id=$1 AND char_id=ANY($2::text[])) AS legendary_collection,(SELECT count(DISTINCT char_id)::int FROM owned_characters WHERE player_id=$1 AND char_id=ANY($3::text[])) AS mythic_collection,(SELECT count(*)::int FROM owned_characters WHERE player_id=$1 AND ascension>=1 AND char_id=ANY($4::text[])) AS first_ascension,(SELECT count(*)::int FROM owned_characters WHERE player_id=$1 AND ascension>=3 AND char_id=ANY($3::text[])) AS mythic_ascended,(SELECT count(*)::int FROM owned_characters WHERE player_id=$1 AND ascension>=3 AND char_id=ANY($3::text[])) AS ascended_collection,(SELECT count(*)::int FROM owned_characters WHERE player_id=$1 AND ascension>=3 AND char_id=ANY($5::text[])) AS siblings_ascended,(SELECT count(*)::int FROM owned_characters WHERE player_id=$1 AND ascension>=3 AND char_id=ANY($6::text[])) AS eclipse_ascended,COALESCE(array_agg(ref_id) FILTER(WHERE reason='online_achievement' AND currency_id='gold'),'{}'::text[]) AS claimed FROM currency_ledger WHERE player_id=$1 AND delta>0 AND reason IN ('online_daily_quest','coop_monster_defeat','online_monthly_quest','online_achievement')",[id,collectionCharacterIds("legendary"),collectionCharacterIds("mythic"),[...collectionCharacterIds("legendary"),...collectionCharacterIds("mythic"),"kael","gerald","lilith"],ascendedBonds.find(b=>b.id==="siblings_guard")?.members??[],ascendedBonds.find(b=>b.id==="eclipse_vow")?.members??[]]);
 const p=q.rows[0]!;
 return achievementTasks.map(t=>({...t,category:playerTitles.find(x=>x.id===t.id)?.category??"Adventure",unlockTitle:titleName(t.id),progress:p.claimed.includes(t.id)?t.target:Math.min(t.target,p[t.id]),claimed:p.claimed.includes(t.id),can_claim:!p.claimed.includes(t.id)&&p[t.id]>=t.target}));
}
export async function onlineAchievementReady(id:string){return (await achievementRows(pool,id)).filter(x=>x.can_claim).map(({id,title})=>({id,title}));}
export async function onlineAchievementClaimable(id:string):Promise<number>{return (await onlineAchievementReady(id)).length;}

export const dailyQuestRoutes:FastifyPluginAsync=async app=>{
 app.addHook("onSend",async(_req,reply,payload)=>{reply.header("Cache-Control","no-store");return payload;});
 app.get("/",async(req,reply)=>{const id=await identity(req,reply);if(!id)return;const p=await progress(pool,id);return {playerId:id,date:p.date,enabled:true,rows:dailyRows(p),...timing(p.date,1)};});
 app.get("/weekly",async(req,reply)=>{const id=await identity(req,reply);if(!id)return;const p=await weeklyProgress(pool,id);return {playerId:id,date:p.date,enabled:true,rows:weeklyRows(p),...timing(p.date,7)};});
 app.get("/monthly",async(req,reply)=>{const id=await identity(req,reply);if(!id)return;const p=await monthlyProgress(pool,id);return {playerId:id,date:p.date,enabled:true,rows:monthlyRows(p),...monthlyTiming(p.date)};});
 app.get("/achievements",async(req,reply)=>{const id=await identity(req,reply);if(!id)return;return {playerId:id,rows:await achievementRows(pool,id)};});
 async function claimAchievement(req:FastifyRequest,reply:FastifyReply,all:boolean){
 const id=await identity(req,reply);if(!id)return;
 const parsed=(all?z.object({}).strict():z.object({id:z.string().refine(id=>achievementTasks.some(t=>t.id===id))}).strict()).safeParse(req.body);
 if(!parsed.success)return reply.code(400).send({error:"invalid_claim"});
 const requested="id" in parsed.data?parsed.data.id:null;
 const db=await pool.connect();
 try{
 await db.query("BEGIN");
 // Separate per-player claim lock; avoid locking the player row before combat's wallet updates.
 await db.query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))",["achievement:"+id]);
 const eligible=(await achievementRows(db,id)).filter(t=>t.can_claim&&(all||t.id===requested));
 if(!eligible.length){const current=await achievementRows(db,id);await db.query("ROLLBACK");return reply.code(409).send({error:"achievement_not_claimable",playerId:id,rows:current});}
 for(const currency of ["gold","crystals"] as const){
 for(const task of eligible){
 const amount=task[currency];
 const q=await db.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,$2,$3) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[id,currency,amount]);
 await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'online_achievement','achievement',$5,$6)",[id,currency,amount,q.rows[0].balance,task.id,"achievement:"+task.id+":"+currency]);
 }}
 const updated=await achievementRows(db,id);
 await db.query("COMMIT");
 return {playerId:id,rows:updated,awards:eligible.map(({id,gold,crystals})=>({id,gold,crystals}))};
 }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 }
 app.post("/achievements/claim",(req,reply)=>claimAchievement(req,reply,false));
 app.post("/achievements/claim-all",(req,reply)=>claimAchievement(req,reply,true));
 app.get("/history",async(req,reply)=>{
 const id=await identity(req,reply);if(!id)return;
 const q=await pool.query<{reason:string;ref_id:string;gold:number;crystals:number;claimedAt:string}>("SELECT reason,ref_id,COALESCE(sum(delta) FILTER(WHERE currency_id='gold'),0)::int AS gold,COALESCE(sum(delta) FILTER(WHERE currency_id='crystals'),0)::int AS crystals,max(created_at) AS \"claimedAt\" FROM currency_ledger WHERE player_id=$1 AND reason IN ('online_daily_quest','online_weekly_quest','online_activity_quest','online_monthly_quest','online_achievement','online_season_reward','online_season_challenge') AND ref_id IS NOT NULL GROUP BY reason,ref_id ORDER BY max(created_at) DESC,ref_id DESC LIMIT 50",[id]);
 return {playerId:id,entries:q.rows.map(r=>{
 const [date="",key=""]=r.ref_id.split(":");
 const weekly=r.reason==="online_weekly_quest";
 const activity=r.reason==="online_activity_quest";
 const monthly=r.reason==="online_monthly_quest";
 const achievement=r.reason==="online_achievement";
 const seasonalReward=r.reason==="online_season_reward";
 const seasonalChallenge=r.reason==="online_season_challenge";
 const title=seasonalReward?"Season ranking: "+key:seasonalChallenge?seasonChallenges.find(t=>t.id===key)?.title:achievement?achievementTasks.find(t=>t.id===r.ref_id)?.title:monthly?monthlyTasks.find(t=>t.id===key)?.title:activity?activityTasks.find(t=>t.id===key)?.title:weekly?weeklyTasks.find(t=>t.id===key)?.title:key==="shared"?(featuredEncounter(date ?? "")?.title??"United Front"):tasks.find(t=>t.id===key)?.title;
 return {date:achievement?new Date(r.claimedAt).toISOString().slice(0,10):date,title:title??key,period:seasonalReward?"Season ranking":seasonalChallenge?"Season challenge":achievement?"Achievement":monthly?"Monthly":activity?"Activity":weekly?"Weekly":"Daily",gold:r.gold,crystals:r.crystals,claimedAt:r.claimedAt};
 })};
 });
 async function claim(req:FastifyRequest,reply:FastifyReply,weekly:boolean,all:boolean,monthly=false){
 const id=await identity(req,reply);if(!id)return;
 const dateSchema=z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
 const body=(all?z.object({date:dateSchema}).strict():z.object({date:dateSchema,id:z.enum(weekly||monthly?["checkins","victories","shared","bonus"]:["checkin","victories","shared","bonus","activity_1","activity_3"])}).strict()).safeParse(req.body);
 if(!body.success)return reply.code(400).send({error:"invalid_claim"});
 const requested="id" in body.data?body.data.id:null;
 const table=monthly?"online_monthly_quests":weekly?"online_weekly_quests":"online_daily_quests",column=monthly?"month_start":weekly?"week_start":"quest_day",period=monthly?monthSql:weekly?weekSql:daySql;
 const db=await pool.connect();
 try{
 await db.query("BEGIN");
 await db.query(`INSERT INTO ${table}(player_id,${column}) VALUES($1,${period}) ON CONFLICT DO NOTHING`,[id]);
 await db.query(`SELECT 1 FROM ${table} WHERE player_id=$1 AND ${column}=${period} FOR UPDATE`,[id]);
 const p=monthly?await monthlyProgress(db,id):weekly?await weeklyProgress(db,id):await progress(db,id);
 const currentRows=()=>monthly?monthlyRows(p as WeeklyProgress):weekly?weeklyRows(p as WeeklyProgress):dailyRows(p as Progress);
 if(p.date!==body.data.date){await db.query("ROLLBACK");return reply.code(409).send({error:"quest_not_claimable",playerId:id,date:p.date,enabled:true,rows:currentRows(),...(monthly?monthlyTiming(p.date):timing(p.date,weekly?7:1))});}
 const awards:{id:string;gold:number;crystals:number}[]=[];
 // Recompute eligibility after each claim so a newly unlocked bonus is included.
 for(const candidate of currentRows()){
 const task=currentRows().find(t=>t.id===candidate.id)!;
 if(!task.can_claim||(!all&&task.id!==requested))continue;
 p.claimed.push(task.id);awards.push({id:task.id,gold:task.gold,crystals:task.crystals});
 }
 if(!awards.length){await db.query(`UPDATE ${table} SET claimed=$2 WHERE player_id=$1 AND ${column}=${period}`,[id,p.claimed]);await db.query("COMMIT");return reply.code(409).send({error:"quest_not_claimable",playerId:id,date:p.date,enabled:true,rows:currentRows(),...(monthly?monthlyTiming(p.date):timing(p.date,weekly?7:1))});}
 await db.query(`UPDATE ${table} SET claimed=$2 WHERE player_id=$1 AND ${column}=${period}`,[id,p.claimed]);
 // Acquire wallet locks in the same order as the existing combat payouts.
 for(const currency of ["gold","crystals"] as const){
 for(const task of awards){
 const amount=task[currency];if(!amount)continue;
 const q=await db.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,$2,$3) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[id,currency,amount]);
 const scope=monthly?"monthly":weekly?"weekly":task.id.startsWith("activity_")?"activity":"daily";
 await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,$5,$6,$7,$8)",[id,currency,amount,q.rows[0].balance,"online_"+scope+"_quest",scope+"_quest",p.date+":"+task.id,scope+":"+p.date+":"+task.id+":"+currency]);
 }}
 await db.query("COMMIT");
 return {playerId:id,date:p.date,enabled:true,rows:currentRows(),...(monthly?monthlyTiming(p.date):timing(p.date,weekly?7:1)),awards};
 }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 }
 app.post("/claim",(req,reply)=>claim(req,reply,false,false));
 app.post("/claim-all",(req,reply)=>claim(req,reply,false,true));
 app.post("/weekly/claim",(req,reply)=>claim(req,reply,true,false));
 app.post("/weekly/claim-all",(req,reply)=>claim(req,reply,true,true));
 app.post("/monthly/claim",(req,reply)=>claim(req,reply,false,false,true));
 app.post("/monthly/claim-all",(req,reply)=>claim(req,reply,false,true,true));
};
