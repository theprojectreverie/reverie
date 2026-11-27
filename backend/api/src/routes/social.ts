import {challengeState,claimSeasonChallenges,seasonChallenges} from "../world/season-challenges.js";
import {FIRST_REWARD_SEASON,seasonalResults,claimSeasonReward,seasonalTitles,seasonRewardReady,championshipHistory} from "../world/season-rewards.js";
import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {z} from "zod";
import {pool} from "../db.js";
import {retiredPlayableIds} from "../world/summon.js";
import {readFile} from "node:fs/promises";
import {join} from "node:path";
import {localDevelopmentRegistration} from "../config.js";
import {onlineQuestSummary,onlineAchievementReady,profileTitles,titleName,playerTitles,verifiedTitleSql} from "./daily-quests.js";
export const PROFILE_PICTURES=["kael_avatar","ravienna_legendary","ravienna_mythic","ravienna_ascended","ravienna_human","gerald_legendary","gerald_mythic","gerald_ascended","gerald_human","lilith_legendary","lilith_mythic","lilith_ascended","lilith_human","cassien_legendary","cassien_mythic","cassien_ascended","cassien_human"] as const;
export function profilePicture(value:unknown):string{return PROFILE_PICTURES.includes(value as any)?String(value):"kael_avatar";}

const STARTER_PORTRAITS = ["kael_avatar","gerald","lilith"] as const;
function portraitForCharacter(id:string):string { return id==="kael"?"kael_avatar":id; }
// The current offline/dev build saves each authenticated account locally.
// Never trust a roster submitted by an HTTP client. This fallback is not enabled in production.
async function localDevelopmentCharacters(playerId:string):Promise<string[]> {
 if(!localDevelopmentRegistration || process.platform!=="win32" || !process.env.APPDATA || !/^[0-9a-f-]{36}$/i.test(playerId))return [];
 const path=join(process.env.APPDATA,"Project Fantasy","project_fantasy_save_"+playerId.toLowerCase()+".json");
 for(const candidate of [path,path+".previous.tmp"]){
  try{
   const save=JSON.parse(await readFile(candidate,"utf8"));
   if(!Array.isArray(save.roster))return [];
   return save.roster.flatMap((entry:unknown)=>entry && typeof entry==="object" && "char_id" in entry && typeof entry.char_id==="string"?[entry.char_id]:[]);
  }catch{}
 }
 return [];
}
export type PortraitOwnership={char_id:string;ascension:number};
export function profilePortraitUnlocks(owned:PortraitOwnership[],local:string[]=[]):string[] {
 const ids=new Set<string>([...STARTER_PORTRAITS,...owned.map(r=>portraitForCharacter(r.char_id)),...local.map(portraitForCharacter)]);
 for(const name of ["ravienna","gerald","lilith","cassien"]){
  const legendary=name==="ravienna"?name:name+"_legendary";
  const mythic=name+"_mythic";
  if(ids.has(legendary))ids.add(name+"_legendary");
  if(ids.has(legendary)||ids.has(mythic)||owned.some(r=>r.char_id===name))ids.add(name+"_human");
  if(owned.some(r=>r.char_id===mythic&&r.ascension===3))ids.add(name+"_ascended");
 }
 return PROFILE_PICTURES.filter(id=>ids.has(id)&&!retiredPlayableIds.includes(id));
}
export async function unlockedProfilePictures(playerId:string):Promise<string[]> {
 const owned=await pool.query<PortraitOwnership>("SELECT char_id,ascension FROM owned_characters WHERE player_id=$1",[playerId]);
 return profilePortraitUnlocks(owned.rows,await localDevelopmentCharacters(playerId));
}
export async function ownedProfilePicture(playerId:string,value:unknown):Promise<string> {
 const unlocked=await unlockedProfilePictures(playerId);
 const avatar=profilePicture(value);
 return unlocked.includes(avatar)?avatar:"kael_avatar";
}
type Identity={id:string;name:string;avatar:string};
async function identity(req:FastifyRequest,reply:FastifyReply):Promise<Identity|null>{
 try{await req.jwtVerify();const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
 if(c.sub&&c.playerId&&Number.isInteger(c.tokenVersion)){
 const q=await pool.query<Identity>("SELECT p.id,p.name,p.settings->>'profile_picture' AS avatar FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3",[c.playerId,c.sub,c.tokenVersion]);if(q.rows[0])return q.rows[0];}
 }catch{}
 reply.code(401).send({error:"authentication_required"});return null;
}
const target=z.object({playerId:z.string().uuid()}).strict();
const change=z.object({playerId:z.string().uuid(),action:z.enum(["request","accept","decline","remove","cancel"])}).strict();
export const socialRoutes:FastifyPluginAsync=async app=>{
 app.addHook("onSend",async(_req,reply,payload)=>{reply.header("Cache-Control","no-store");return payload;});
 async function profileStats(id:string){
 const q=await pool.query("SELECT p.level,p.xp::text,(SELECT count(*)::int FROM currency_ledger WHERE player_id=p.id AND reason='coop_monster_defeat' AND currency_id='gold' AND delta>0) AS victories,(SELECT count(*)::int FROM online_achievement_exploration WHERE player_id=p.id) AS landmarks FROM players p WHERE p.id=$1",[id]);
 return q.rows[0]??{};
 }
 app.post("/showcase",async(req,reply)=>{
 const me=await identity(req,reply);if(!me)return;
 const parsed=z.object({pins:z.array(z.string().max(64)).max(3).refine(a=>new Set(a).size===a.length)}).strict().safeParse(req.body);
 if(!parsed.success)return reply.code(400).send({error:"invalid_showcase"});
 const profile=await profileTitles(me.id);
 if(!parsed.data.pins.every(id=>profile.titles.some(t=>t.id===id&&t.unlocked)))return reply.code(403).send({error:"badge_locked"});
 await pool.query("UPDATE players SET settings=jsonb_set(COALESCE(settings,'{}'::jsonb),'{achievement_pins}',$2::jsonb,true),updated_at=now() WHERE id=$1",[me.id,JSON.stringify(parsed.data.pins)]);
 return {id:me.id,...await profileTitles(me.id)};
 });
 // Read-only friend inspection. Never expose private wallet, email, roster or settings.
 // Friends-only rankings: stable ties, canonical server scores, no wallet or roster data.
 app.post("/leaderboard/visibility",async(req,reply)=>{
 const me=await identity(req,reply);if(!me)return;
 const parsed=z.object({enabled:z.boolean()}).strict().safeParse(req.body);
 if(!parsed.success)return reply.code(400).send({error:"invalid_visibility"});
 const db=await pool.connect();
 try{await db.query("BEGIN");
 await db.query("UPDATE players SET settings=jsonb_set(COALESCE(settings,'{}'::jsonb),'{global_rankings}',to_jsonb($2::boolean),true),updated_at=now() WHERE id=$1",[me.id,parsed.data.enabled]);
 await db.query("INSERT INTO online_ranking_visibility_events(player_id,enabled) VALUES($1,$2)",[me.id,parsed.data.enabled]);
 await db.query("COMMIT");}catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}

 return {playerId:me.id,enabled:parsed.data.enabled};
 });
 // Hall of Fame: frozen winners, but current consent and current block rules.
 app.get("/championship-hall",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
 const me=await identity(req,reply);if(!me)return;
 const parsed=z.object({season:z.string().regex(/^\d{4}-(0[1-9]|1[0-2])-01$/).optional(),category:z.enum(["combat","exploration","achievements"]).default("combat"),page:z.coerce.number().int().min(0).max(10000).default(0)}).strict().safeParse(req.query);
 if(!parsed.success)return reply.code(400).send({error:"invalid_hall_filter"});
 const {category,page}=parsed.data;
 const seasons=(await pool.query<{season:string}>("SELECT season_start::text AS season FROM online_season_finalizations ORDER BY season_start DESC LIMIT 36")).rows.map(r=>r.season);
 const season=parsed.data.season??seasons[0]??null;
 if(season&&!seasons.includes(season))return reply.code(404).send({error:"season_unavailable"});
 if(!season)return {playerId:me.id,seasons,season,category,page,hasMore:false,rows:[]};
 const q=await pool.query("SELECT p.id,p.name,p.settings->>'profile_picture' AS avatar,s.score FROM online_season_results s JOIN players p ON p.id=s.player_id JOIN accounts a ON a.id=p.account_id WHERE s.season_start=$2::date AND s.category=$3 AND s.rank=1 AND a.status='active' AND p.settings->'global_rankings'='true'::jsonb AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=p.id) OR (b.blocked_id=$1 AND b.player_id=p.id)) ORDER BY p.id LIMIT 26 OFFSET $4",[me.id,season,category,page*25]);
 const title=seasonalTitles.find(t=>t.id==="season_"+(category==="achievements"?"achievement":category)+"_champion")?.name??"";
 return {playerId:me.id,seasons,season,category,page,hasMore:q.rows.length>25,rows:q.rows.slice(0,25).map(r=>({id:r.id,name:r.name,avatar:profilePicture(r.avatar),score:r.score,rank:1,title,self:r.id===me.id}))};
 });
 app.get("/season-challenges",async(req,reply)=>{
 const me=await identity(req,reply);if(!me)return;
 return challengeState(pool,me.id);
 });
 async function claimChallenge(req:FastifyRequest,reply:FastifyReply,all:boolean){
 const me=await identity(req,reply);if(!me)return;
 const season=z.string().regex(/^\d{4}-(0[1-9]|1[0-2])-01$/);
 const parsed=(all?z.object({season}).strict():z.object({season,id:z.string().refine(id=>seasonChallenges.some(t=>t.id===id))}).strict()).safeParse(req.body);
 if(!parsed.success)return reply.code(400).send({error:"invalid_challenge_claim"});
 const taskId="id" in parsed.data?String(parsed.data.id):null;
 const db=await pool.connect();
 try{await db.query("BEGIN");const reward=await claimSeasonChallenges(db,me.id,parsed.data.season,taskId);
 if(!reward){await db.query("ROLLBACK");return reply.code(409).send({error:"challenge_not_claimable",...await challengeState(db,me.id)});}
 await db.query("COMMIT");return {...reward.state,goldAwarded:reward.gold,awards:reward.awards};
 }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 }
 app.post("/season-challenges/claim",(req,reply)=>claimChallenge(req,reply,false));
 app.post("/season-challenges/claim-all",(req,reply)=>claimChallenge(req,reply,true));
 app.get("/season-results",async(req,reply)=>{
 const me=await identity(req,reply);if(!me)return;
 return {playerId:me.id,firstRewardSeason:FIRST_REWARD_SEASON,results:await seasonalResults(me.id),championships:await championshipHistory(me.id)};
 });
 app.post("/season-results/claim",async(req,reply)=>{
 const me=await identity(req,reply);if(!me)return;
 const parsed=z.object({season:z.string().regex(/^\d{4}-(0[1-9]|1[0-2])-01$/),category:z.enum(["combat","exploration","achievements"])}).strict().safeParse(req.body);
 if(!parsed.success)return reply.code(400).send({error:"invalid_season_claim"});
 const db=await pool.connect();
 try{await db.query("BEGIN");const reward=await claimSeasonReward(db,me.id,parsed.data.season,parsed.data.category);
 if(!reward){await db.query("ROLLBACK");return reply.code(409).send({error:"season_reward_unavailable"});}
 await db.query("COMMIT");return {playerId:me.id,reward,firstRewardSeason:FIRST_REWARD_SEASON,results:await seasonalResults(me.id),championships:await championshipHistory(me.id)};
 }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 });
 app.get("/leaderboard",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
 const me=await identity(req,reply);if(!me)return;
 const parsed=z.object({category:z.enum(["achievements","exploration","combat"]),scope:z.enum(["friends","global"]).default("friends"),period:z.enum(["lifetime","monthly"]).default("lifetime")}).strict().safeParse(req.query);
 if(!parsed.success)return reply.code(400).send({error:"invalid_category"});
 const {category,scope,period}=parsed.data;
 const now=new Date();
 const start=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth(),1));
 const end=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth()+1,1));
 const params:unknown[]=category==="achievements"?[me.id,playerTitles.map(t=>t.id)]:[me.id];
 let seasonFilter="";
 let seasonStart="";
 if(period==="monthly"){
  params.push(start.toISOString());seasonStart="$"+params.length;
  if(category!=="exploration"){params.push(end.toISOString());seasonFilter=" AND cl.created_at>="+seasonStart+"::timestamptz AND cl.created_at<$"+params.length+"::timestamptz";}
 }
 const visibility=await pool.query("SELECT settings->'global_rankings'='true'::jsonb AS enabled FROM players WHERE id=$1",[me.id]);
 const enabled=visibility.rows[0]?.enabled===true;
 const score=category==="exploration"?(period==="monthly"?"(SELECT count(*)::int FROM online_season_exploration e WHERE e.player_id=p.id AND e.season_start=("+seasonStart+"::timestamptz AT TIME ZONE 'UTC')::date)":"(SELECT count(*)::int FROM online_achievement_exploration e WHERE e.player_id=p.id)"):category==="combat"?"(SELECT count(*)::int FROM currency_ledger cl WHERE cl.player_id=p.id AND cl.reason='coop_monster_defeat' AND cl.currency_id='gold' AND cl.delta>0"+seasonFilter+")":"(SELECT count(DISTINCT cl.ref_id)::int FROM currency_ledger cl WHERE cl.player_id=p.id AND cl.reason='online_achievement' AND cl.currency_id='gold' AND cl.delta>0 AND cl.ref_id=ANY($2::text[])"+seasonFilter+")";
 const audience=scope==="global"?"p.settings->'global_rankings'='true'::jsonb":"(p.id=$1 OR EXISTS(SELECT 1 FROM friendships f WHERE f.status='accepted' AND ((f.player_id=$1 AND f.friend_id=p.id) OR (f.friend_id=$1 AND f.player_id=p.id))))";
 const canonical=scope==="global"&&period==="monthly";
 const unblocked="NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=p.id) OR (b.blocked_id=$1 AND b.player_id=p.id))";
 const q=await pool.query("WITH scored AS (SELECT p.id,p.name,p.settings->>'profile_picture' AS avatar,"+score+" AS score FROM players p JOIN accounts a ON a.id=p.account_id WHERE a.status='active' AND "+audience+(canonical?"":" AND "+unblocked)+"), ranked AS (SELECT id,name,avatar,score,rank() OVER(ORDER BY score DESC)::int AS rank,count(*) OVER()::int AS total FROM scored), visible AS (SELECT p.*,row_number() OVER(ORDER BY score DESC,lower(name),id) AS row_number FROM ranked p"+(canonical?" WHERE "+unblocked:"")+") SELECT * FROM visible WHERE "+(scope==="global"?"row_number<=50 OR id=$1":"true")+" ORDER BY row_number",params);
 reply.header("Cache-Control","no-store");
 return {playerId:me.id,category,scope,period,enabled,serverTime:now.getTime(),season:period==="monthly"?start.toISOString().slice(0,7):null,resetAt:period==="monthly"?end.getTime():null,total:q.rows[0]?.total??0,rows:q.rows.map(r=>({id:r.id,name:r.name,avatar:profilePicture(r.avatar),score:r.score,rank:r.rank,self:r.id===me.id}))};
 });
 app.get("/friend-profile",{config:{rateLimit:{max:40,timeWindow:"1 minute"}}},async(req,reply)=>{
 const me=await identity(req,reply);if(!me)return;
 const parsed=target.safeParse(req.query);
 if(!parsed.success)return reply.code(400).send({error:"invalid_player"});
 const id=parsed.data.playerId;
 const allowed=async()=>pool.query<{id:string;name:string;avatar:string;online:boolean}>("SELECT p.id,p.name,p.settings->>'profile_picture' AS avatar,EXISTS(SELECT 1 FROM player_presence pr WHERE pr.player_id=p.id AND pr.state<>'offline' AND pr.last_heartbeat_at>now()-interval '45 seconds') AS online FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$2 AND p.id<>$1 AND a.status='active' AND EXISTS(SELECT 1 FROM friendships f WHERE f.status='accepted' AND ((f.player_id=$1 AND f.friend_id=p.id) OR (f.player_id=p.id AND f.friend_id=$1))) AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=p.id) OR (b.player_id=p.id AND b.blocked_id=$1))",[me.id,id]);
 if(!(await allowed()).rowCount)return reply.code(404).send({error:"friend_profile_unavailable"});
 const [profile,stats]=await Promise.all([profileTitles(id),profileStats(id)]);
 const player=(await allowed()).rows[0];
 if(!player)return reply.code(404).send({error:"friend_profile_unavailable"});
 const badges=profile.pins.map(pin=>profile.titles.find(t=>t.id===pin&&t.unlocked)).filter(Boolean).map(t=>({name:t!.name,category:t!.category,achievement:t!.achievement}));
 reply.header("Cache-Control","no-store");
 return {id:player.id,name:player.name,avatar:profilePicture(player.avatar),online:player.online,title:profile.title,badges,achievementCount:profile.achievementCount,achievementTotal:profile.titles.length,stats};
 });
 app.get("/profile",async(req,reply)=>{const me=await identity(req,reply);if(!me)return;const unlocked=await unlockedProfilePictures(me.id);const avatar=unlocked.includes(profilePicture(me.avatar))?profilePicture(me.avatar):"kael_avatar";return {id:me.id,name:me.name,avatar,choices:PROFILE_PICTURES,unlocked,stats:await profileStats(me.id),...await profileTitles(me.id)};});
 app.post("/profile",async(req,reply)=>{const me=await identity(req,reply);if(!me)return;const p=z.object({avatar:z.enum(PROFILE_PICTURES)}).strict().safeParse(req.body);if(!p.success)return reply.code(400).send({error:"invalid_portrait"});const unlocked=await unlockedProfilePictures(me.id);if(!unlocked.includes(p.data.avatar))return reply.code(403).send({error:"portrait_locked"});await pool.query("UPDATE players SET settings=jsonb_set(COALESCE(settings,'{}'::jsonb),'{profile_picture}',to_jsonb($2::text),true),updated_at=now() WHERE id=$1",[me.id,p.data.avatar]);return {id:me.id,name:me.name,avatar:p.data.avatar,choices:PROFILE_PICTURES,unlocked,stats:await profileStats(me.id),...await profileTitles(me.id)};});
 // Menu artwork is separate from the social portrait and saved per account.
 const menuCharacters=["default","ravienna","kael_crouching","kael_seated","kael_standing","mirene","crimson_witch","elathra"] as const;
 const menuOwner:Record<string,string>={kael_crouching:"kael",kael_seated:"kael",kael_standing:"kael",ravienna:"ravienna",mirene:"mirene",crimson_witch:"elathra",elathra:"tutorial_companion"};
 async function menuChoices(id:string){
  const unlocked=await unlockedProfilePictures(id);
  // Legacy appearance keys are stable: crimson_witch is Elathra; elathra is Companion.
  // Only an authoritative completed spar qualifies; local flags and client claims never do.
  const spar=await pool.query<{won:boolean}>(
    "SELECT EXISTS(SELECT 1 FROM story_battle_sessions WHERE player_id=$1 AND group_id='tutorial_fairy_spar' AND status='victory' AND finished_at IS NOT NULL AND state->'view'->>'status'='victory') AS won",[id]);
  return menuCharacters.filter(key=>key==="default"||(key==="elathra"?spar.rows[0]?.won===true:unlocked.some(owned=>owned===menuOwner[key]||owned.startsWith(menuOwner[key]+"_"))));
 }
 // A personal story name, not a collectible unlock or public profile change.
 const companionNameSchema=z.object({name:z.string().trim().min(1).max(24).regex(/^[\p{L}\p{M}\p{N}][\p{L}\p{M}\p{N} '\-’]*$/u)}).strict();
 async function companionName(id:string):Promise<string>{
  const q=await pool.query<{name:string}>("SELECT settings->>'tutorial_companion_name' AS name FROM players WHERE id=$1",[id]);
  return q.rows[0]?.name??"";
 }
 app.get("/companion-name",async(req,reply)=>{
  const me=await identity(req,reply);if(!me)return;
  return {playerId:me.id,name:await companionName(me.id)};
 });
 app.post("/companion-name",async(req,reply)=>{
  const me=await identity(req,reply);if(!me)return;
  const parsed=companionNameSchema.safeParse(req.body);
  if(!parsed.success)return reply.code(400).send({error:"invalid_companion_name"});
  // First naming wins across devices, including simultaneous submissions.
  const q=await pool.query<{name:string}>("UPDATE players SET settings=jsonb_set(COALESCE(settings,'{}'::jsonb),'{tutorial_companion_name}',to_jsonb(COALESCE(NULLIF(settings->>'tutorial_companion_name',''),$2::text)),true) WHERE id=$1 RETURNING settings->>'tutorial_companion_name' AS name",[me.id,parsed.data.name]);
  return {playerId:me.id,name:q.rows[0]?.name??""};
 });
 app.get("/menu-character",async(req,reply)=>{
  const me=await identity(req,reply);if(!me)return;
  const choices=await menuChoices(me.id);
  const q=await pool.query<{character:string}>("SELECT settings->>'menu_character' AS character FROM players WHERE id=$1",[me.id]);
  const prior=q.rows[0]?.character;const stored=prior==="kael_avatar"?"kael_standing":prior;
  return {playerId:me.id,character:choices.includes(stored as typeof menuCharacters[number])?stored:"default",choices,companionName:await companionName(me.id)};
 });
 app.post("/menu-character",async(req,reply)=>{
  const me=await identity(req,reply);if(!me)return;
  const parsed=z.object({character:z.enum(menuCharacters)}).strict().safeParse(req.body);
  if(!parsed.success)return reply.code(400).send({error:"invalid_menu_character"});
  const choices=await menuChoices(me.id);
  if(!choices.includes(parsed.data.character))return reply.code(403).send({error:"character_locked"});
  await pool.query("UPDATE players SET settings=jsonb_set(COALESCE(settings,'{}'::jsonb),'{menu_character}',to_jsonb($2::text),true),updated_at=now() WHERE id=$1",[me.id,parsed.data.character]);
  return {playerId:me.id,character:parsed.data.character,choices,companionName:await companionName(me.id)};
 });
 app.post("/title",async(req,reply)=>{
 const me=await identity(req,reply);if(!me)return;
 const parsed=z.object({titleId:z.string().max(64)}).strict().safeParse(req.body);
 if(!parsed.success)return reply.code(400).send({error:"invalid_title"});
 const id=parsed.data.titleId;
 if(id&&![...playerTitles,...seasonalTitles].some(t=>t.id===id))return reply.code(400).send({error:"invalid_title"});
 const profile=await profileTitles(me.id);
 if(id&&![...profile.titles,...profile.seasonTitles].some(t=>t.id===id&&t.unlocked))return reply.code(403).send({error:"title_locked"});
 await pool.query("UPDATE players SET settings=jsonb_set(COALESCE(settings,'{}'::jsonb),'{profile_title}',to_jsonb($2::text),true),updated_at=now() WHERE id=$1",[me.id,id]);
 return {id:me.id,...await profileTitles(me.id)};
 });
 app.get("/search",{config:{rateLimit:{max:25,timeWindow:"1 minute"}}},async(req,reply)=>{
 const me=await identity(req,reply);if(!me)return;const p=z.object({name:z.string().trim().min(3).max(20).regex(/^[A-Za-z0-9_]+$/)}).safeParse(req.query);if(!p.success)return reply.code(400).send({error:"invalid_name"});
 const q=await pool.query("SELECT p.id,p.name,p.settings->>'profile_picture' AS avatar,"+verifiedTitleSql+" AS \"titleId\" FROM players p JOIN accounts a ON a.id=p.account_id WHERE lower(p.name)=lower($2) AND p.id<>$1 AND a.status='active' AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=p.id) OR (b.blocked_id=$1 AND b.player_id=p.id)) LIMIT 1",[me.id,p.data.name]);return {players:q.rows.map(r=>({...r,avatar:profilePicture(r.avatar),title:titleName(r.titleId)}))};});
 app.get("/summary",async(req,reply)=>{const me=await identity(req,reply);if(!me)return;
 const counts=await pool.query<{incoming:number;unread:number}>("SELECT (SELECT count(*)::int FROM friendships f JOIN players p ON p.id=f.player_id JOIN accounts a ON a.id=p.account_id WHERE f.friend_id=$1 AND f.status='pending' AND a.status='active' AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=p.id) OR (b.blocked_id=$1 AND b.player_id=p.id))) AS incoming,(SELECT count(*)::int FROM private_chat_messages m JOIN players p ON p.id=m.sender_id JOIN accounts a ON a.id=p.account_id WHERE m.recipient_id=$1 AND m.read_at IS NULL AND a.status='active' AND EXISTS(SELECT 1 FROM friendships f WHERE f.status='accepted' AND ((f.player_id=$1 AND f.friend_id=m.sender_id) OR (f.friend_id=$1 AND f.player_id=m.sender_id))) AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=m.sender_id) OR (b.blocked_id=$1 AND b.player_id=m.sender_id))) AS unread",[me.id]);
 await pool.query("INSERT INTO player_presence(player_id,state,last_heartbeat_at) VALUES($1,'online',now()) ON CONFLICT(player_id) DO UPDATE SET state=CASE WHEN player_presence.state='offline' THEN 'online' ELSE player_presence.state END,last_heartbeat_at=now(),updated_at=now() WHERE player_presence.state='offline' OR player_presence.last_heartbeat_at<now()-interval '20 seconds'",[me.id]);
 const achievementReady=await onlineAchievementReady(me.id);
 const seasonReady=await seasonRewardReady(me.id);
 const challenge=await challengeState(pool,me.id);
 return {playerId:me.id,avatar:await ownedProfilePicture(me.id,me.avatar),incoming:counts.rows[0]?.incoming??0,unread:counts.rows[0]?.unread??0,...await onlineQuestSummary(me.id),achievementClaimable:achievementReady.length,achievementReady,seasonClaimable:seasonReady.length,seasonReady,seasonChallengeClaimable:challenge.rows.filter(r=>r.canClaim).length};
 });
 app.get("/friends",async(req,reply)=>{const me=await identity(req,reply);if(!me)return;
 const q=await pool.query("SELECT p.id,p.name,p.settings->>'profile_picture' AS avatar,"+verifiedTitleSql+" AS \"titleId\",f.status,CASE WHEN f.status='accepted' THEN ARRAY(SELECT pin FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p.settings->'achievement_pins')='array' THEN p.settings->'achievement_pins' ELSE '[]'::jsonb END) WITH ORDINALITY AS item(pin,ord) WHERE EXISTS(SELECT 1 FROM currency_ledger cl WHERE cl.player_id=p.id AND cl.reason='online_achievement' AND cl.currency_id='gold' AND cl.delta>0 AND cl.ref_id=pin) ORDER BY ord LIMIT 3) ELSE ARRAY[]::text[] END AS pins,CASE WHEN f.status='accepted' THEN EXISTS(SELECT 1 FROM player_presence pr WHERE pr.player_id=p.id AND pr.state<>'offline' AND pr.last_heartbeat_at>now()-interval '45 seconds') ELSE NULL END AS online,CASE WHEN f.player_id=$1 THEN 'outgoing' ELSE 'incoming' END AS direction FROM friendships f JOIN players p ON p.id=CASE WHEN f.player_id=$1 THEN f.friend_id ELSE f.player_id END JOIN accounts a ON a.id=p.account_id WHERE (f.player_id=$1 OR f.friend_id=$1) AND f.status IN ('pending','accepted') AND a.status='active' AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=p.id) OR (b.blocked_id=$1 AND b.player_id=p.id)) ORDER BY f.status,p.name LIMIT 200",[me.id]);const invites=await pool.query("SELECT i.id,p.name,l.region_id AS \"regionId\" FROM co_op_friend_invites i JOIN co_op_lobbies l ON l.id=i.lobby_id JOIN players p ON p.id=i.sender_id JOIN accounts a ON a.id=p.account_id WHERE i.recipient_id=$1 AND i.expires_at>now() AND l.status IN ('open','in_world') AND l.leader_player_id=i.sender_id AND a.status='active' AND EXISTS(SELECT 1 FROM friendships f WHERE f.status='accepted' AND ((f.player_id=$1 AND f.friend_id=p.id) OR (f.friend_id=$1 AND f.player_id=p.id))) AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=p.id) OR (b.blocked_id=$1 AND b.player_id=p.id)) ORDER BY i.expires_at LIMIT 20",[me.id]);return {friends:q.rows.map(r=>({...r,avatar:profilePicture(r.avatar),title:titleName(r.titleId),badges:[...new Set<string>(r.pins)].map(titleName).filter(Boolean)})),invites:invites.rows};});
 app.post("/friends",{config:{rateLimit:{max:20,timeWindow:"1 minute"}}},async(req,reply)=>{
 const me=await identity(req,reply);if(!me)return;const p=change.safeParse(req.body);if(!p.success||p.data.playerId===me.id)return reply.code(400).send({error:"invalid_friend_action"});const other=p.data.playerId,action=p.data.action;
 const client=await pool.connect();try{await client.query("BEGIN");
 // Canonical lock order serializes reciprocal requests.
 const locked=await client.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=ANY($1::uuid[]) AND a.status='active' ORDER BY p.id FOR UPDATE OF p",[[me.id,other]]);
 const blocked=await client.query("SELECT 1 FROM blocks WHERE (player_id=$1 AND blocked_id=$2) OR (player_id=$2 AND blocked_id=$1)",[me.id,other]);
 if(locked.rowCount!==2||blocked.rowCount){await client.query("ROLLBACK");return reply.code(404).send({error:"player_unavailable"});}
 const existing=(await client.query("SELECT player_id,friend_id,status FROM friendships WHERE (player_id=$1 AND friend_id=$2) OR (player_id=$2 AND friend_id=$1) FOR UPDATE",[me.id,other])).rows[0];
 if(action==="request"){
 if(existing&&["pending","accepted","blocked"].includes(existing.status)){await client.query("ROLLBACK");return reply.code(409).send({error:"friendship_exists"});}
 const count=await client.query("SELECT count(*)::int AS count FROM friendships WHERE (player_id=$1 OR friend_id=$1 OR player_id=$2 OR friend_id=$2) AND status IN ('accepted','pending') GROUP BY CASE WHEN player_id=$1 OR friend_id=$1 THEN $1 ELSE $2 END",[me.id,other]);
 if(count.rows.some(r=>r.count>=200)){await client.query("ROLLBACK");return reply.code(409).send({error:"friend_limit"});}
 if(existing)await client.query("DELETE FROM friendships WHERE player_id=$1 AND friend_id=$2",[existing.player_id,existing.friend_id]);
 await client.query("INSERT INTO friendships(player_id,friend_id,status) VALUES($1,$2,'pending')",[me.id,other]);
 }else{
 const incoming=existing?.friend_id===me.id;
 const allowed=existing&&((action==="accept"||action==="decline")&&existing.status==="pending"&&incoming||action==="cancel"&&existing.status==="pending"&&!incoming||action==="remove"&&existing.status==="accepted");
 if(!allowed){await client.query("ROLLBACK");return reply.code(409).send({error:"invalid_friend_state"});}
 if(action==="accept")await client.query("UPDATE friendships SET status='accepted',updated_at=now() WHERE player_id=$1 AND friend_id=$2",[existing.player_id,existing.friend_id]);
 else {
  await client.query("DELETE FROM friendships WHERE player_id=$1 AND friend_id=$2",[existing.player_id,existing.friend_id]);
  if(action==="remove")await client.query("DELETE FROM private_chat_messages WHERE (sender_id=$1 AND recipient_id=$2) OR (sender_id=$2 AND recipient_id=$1)",[me.id,other]);
 }
 }
 await client.query("COMMIT");return {ok:true,action};
 }catch(e){await client.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"social_unavailable"});}finally{client.release();}
 });
};
