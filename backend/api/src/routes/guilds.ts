import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import type {PoolClient} from "pg";
import {z} from "zod";
import {pool} from "../db.js";
import {profilePicture} from "./social.js";
import {guildMissionState,guildContributionRanking,GUILD_LEVEL_XP} from "../world/guild-progression.js";
import {guildTreasury,donatedToday,GUILD_DAILY_GOLD_CAP} from "../world/guild-treasury.js";
import {BASE_GUILD_CAPACITY,guildCapacity,guildPerks,perkState,purchasedPerks} from "../world/guild-perks.js";
import {raidOverview,startGuildRaid,actGuildRaid,abandonGuildRaid,claimGuildRaid} from "../world/guild-raids.js";
import {storyTransactionAdmission} from "../world/story-combat-service.js";
import {guildShop,grantGuildTokens,buyGuildOffer} from "../world/guild-shop.js";
import {guildCompetition} from "../world/guild-competition.js";
const CAP=BASE_GUILD_CAPACITY;
const clean=(min:number,max:number)=>z.string().trim().min(min).max(max).refine(s=>!/\p{Cc}|\p{Cf}/u.test(s));
const emblem=z.enum(["moon","star","shield","flame","rose","crown"]);
const guildFields=z.object({name:clean(3,24),description:clean(0,180),emblem}).strict();
const uuid=z.string().uuid();
type Result={status:number;data:Record<string,unknown>};
const error=(status:number,code:string):Result=>({status,data:{error:code}});
const ok=(data:Record<string,unknown>={}):Result=>({status:200,data});
async function identity(req:FastifyRequest,reply:FastifyReply):Promise<string|undefined>{
 try{
  await req.jwtVerify();const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(c.sub&&c.playerId&&Number.isInteger(c.tokenVersion)){
   const r=await pool.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3",[c.playerId,c.sub,c.tokenVersion]);
   if(r.rows[0])return r.rows[0].id;
  }
 }catch{}
 reply.code(401).send({error:"authentication_required"});
}
async function tx(fn:(db:PoolClient)=>Promise<Result>):Promise<Result>{
 const db=await pool.connect();
 try{
  await db.query("BEGIN");
  // Serialize low-frequency membership mutations globally, including cross-guild joins.
  await db.query("SELECT pg_advisory_xact_lock(741926041)");
  const r=await fn(db);
  await db.query(r.status<400?"COMMIT":"ROLLBACK");return r;
 }catch(e){
  await db.query("ROLLBACK");
  if((e as {code?:string}).code==="23505")return error(409,"guild_conflict");
  throw e;
 }finally{db.release();}
}
async function membership(db:PoolClient,id:string){return (await db.query("SELECT guild_id,guild_rank AS role FROM guild_members WHERE player_id=$1",[id])).rows[0];}
async function manager(db:PoolClient,id:string){const m=await membership(db,id);return m&&["leader","officer"].includes(m.role)?m:undefined;}
async function activePlayer(db:PoolClient,id:string){return !!(await db.query("SELECT 1 FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.status='active'",[id])).rowCount;}
async function blocked(db:PoolClient,a:string,b:string){return !!(await db.query("SELECT 1 FROM blocks WHERE (player_id=$1 AND blocked_id=$2) OR (player_id=$2 AND blocked_id=$1)",[a,b])).rowCount;}
async function join(db:PoolClient,guild:string,player:string):Promise<Result>{
 if(await membership(db,player))return error(409,"already_in_guild");
 const count=await db.query("SELECT count(*)::int AS n FROM guild_members WHERE guild_id=$1",[guild]);
 if(count.rows[0].n>=await guildCapacity(db,guild))return error(409,"guild_full");
 if(!await activePlayer(db,player))return error(404,"player_unavailable");
 await db.query("INSERT INTO guild_members(guild_id,player_id,guild_rank) VALUES($1,$2,'member')",[guild,player]);
 await db.query("DELETE FROM guild_requests WHERE player_id=$1",[player]);
 return ok({guildId:guild,joined:true});
}
export const guildRoutes:FastifyPluginAsync=async app=>{
 app.addHook("onSend",async(_req,reply,payload)=>{reply.header("Cache-Control","no-store");return payload;});
 const mutation=(schema:z.ZodType,fn:(db:PoolClient,id:string,data:any)=>Promise<Result>)=>async(req:FastifyRequest,reply:FastifyReply)=>{
  const id=await identity(req,reply);if(!id)return;
  const p=schema.safeParse(req.body);if(!p.success)return reply.code(400).send({error:"invalid_guild_request"});
  const r=await tx(db=>fn(db,id,p.data));return reply.code(r.status).send(r.data);
 };
 app.get("/me",async(req,reply)=>{
  const id=await identity(req,reply);if(!id)return;
  const mine=(await pool.query("SELECT g.id,g.name,g.description,g.emblem,g.level,g.xp::text,m.guild_rank AS role FROM guild_members m JOIN guilds g ON g.id=m.guild_id WHERE m.player_id=$1",[id])).rows[0];
  if(!mine){
   const requests=await pool.query("SELECT r.guild_id AS \"guildId\",g.name,g.emblem,r.kind,r.expires_at AS \"expiresAt\" FROM guild_requests r JOIN guilds g ON g.id=r.guild_id WHERE r.player_id=$1 AND r.expires_at>now() AND (r.kind='application' OR NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=r.sender_id) OR (b.player_id=r.sender_id AND b.blocked_id=$1))) ORDER BY r.created_at DESC LIMIT 50",[id]);
   return {playerId:id,guild:null,members:[],requests:requests.rows,capacity:CAP};
  }
  const members=await pool.query("SELECT p.id,p.name,p.settings->>'profile_picture' AS avatar,m.guild_rank AS role,p.level,EXISTS(SELECT 1 FROM player_presence pr WHERE pr.player_id=p.id AND pr.state<>'offline' AND pr.last_heartbeat_at>now()-interval '45 seconds') AS online FROM guild_members m JOIN players p ON p.id=m.player_id JOIN accounts a ON a.id=p.account_id WHERE m.guild_id=$2 AND a.status='active' AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=p.id) OR (b.player_id=p.id AND b.blocked_id=$1)) ORDER BY CASE m.guild_rank WHEN 'leader' THEN 0 WHEN 'officer' THEN 1 ELSE 2 END,p.name",[id,mine.id]);
  const requests=["leader","officer"].includes(mine.role)?(await pool.query("SELECT r.player_id AS \"playerId\",p.name,r.kind,r.expires_at AS \"expiresAt\" FROM guild_requests r JOIN players p ON p.id=r.player_id JOIN accounts a ON a.id=p.account_id WHERE r.guild_id=$1 AND r.kind='application' AND r.expires_at>now() AND a.status='active' AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$2 AND b.blocked_id=p.id) OR (b.player_id=p.id AND b.blocked_id=$2)) ORDER BY r.created_at LIMIT 50",[mine.id,id])).rows:[];
  const total=(await pool.query("SELECT count(*)::int AS n FROM guild_members WHERE guild_id=$1",[mine.id])).rows[0].n;
  const missions=await guildMissionState(pool,id,mine.id);
  const contributions=await guildContributionRanking(pool,id,mine.id);
  const treasury=await guildTreasury(pool,id,mine.id);
  if(!treasury)return reply.code(403).send({error:"guild_membership_required"});
  const capacity=await guildCapacity(pool,mine.id);
  const perks=await perkState(pool,mine.id,mine.level,mine.role,BigInt(treasury.gold));
  return {playerId:id,guild:{...mine,memberCount:total,xpPerLevel:GUILD_LEVEL_XP},members:members.rows.map(r=>({...r,avatar:profilePicture(r.avatar)})),requests,capacity,missions,contributions,treasury,perks,raid:await raidOverview(pool,id,mine.id),shop:await guildShop(pool,id,mine.id)};
 });
 app.get("/competition",async(req,reply)=>{
  const id=await identity(req,reply);if(!id)return;
  return guildCompetition(pool,id);
 });
 app.get("/search",async(req,reply)=>{
  const id=await identity(req,reply);if(!id)return;
  const p=z.object({q:clean(0,24).default(""),page:z.coerce.number().int().min(0).max(1000).default(0)}).strict().safeParse(req.query);
  if(!p.success)return reply.code(400).send({error:"invalid_search"});
  const r=await pool.query("SELECT g.id,g.name,g.description,g.emblem,g.level,count(m.player_id)::int AS \"memberCount\",CASE WHEN EXISTS(SELECT 1 FROM guild_perks gp WHERE gp.guild_id=g.id AND gp.perk_id='hall_3') THEN 45 WHEN EXISTS(SELECT 1 FROM guild_perks gp WHERE gp.guild_id=g.id AND gp.perk_id='hall_2') THEN 40 WHEN EXISTS(SELECT 1 FROM guild_perks gp WHERE gp.guild_id=g.id AND gp.perk_id='hall_1') THEN 35 ELSE 30 END AS capacity FROM guilds g JOIN guild_members m ON m.guild_id=g.id WHERE strpos(lower(g.name),lower($1))>0 OR $1='' GROUP BY g.id ORDER BY count(m.player_id) DESC,g.name,g.id LIMIT 21 OFFSET $2",[p.data.q,p.data.page*20]);
  return {guilds:r.rows.slice(0,20),hasMore:r.rows.length>20,capacity:CAP};
 });
 const raidMutation=(schema:z.ZodType,fn:(db:PoolClient,id:string,data:any)=>Promise<{ok:boolean;reason?:string}>)=>async(req:FastifyRequest,reply:FastifyReply)=>{
  const id=await identity(req,reply);if(!id)return;
  const p=schema.safeParse(req.body);if(!p.success)return reply.code(400).send({error:"invalid_raid_request"});
  const r=await storyTransactionAdmission.run(id,db=>fn(db,id,p.data));
  if(!r.ok)return reply.code(r.reason==="guild_membership_required"?403:r.reason?.includes("busy")?429:409).send({error:r.reason});
  return r;
 };
 app.post("/raid/start",raidMutation(z.object({guildId:uuid}).strict(),(db,id,d)=>startGuildRaid(db,id,d.guildId)));
 app.post("/raid/action",raidMutation(z.object({guildId:uuid,attemptId:uuid,sequence:z.number().int().min(1).max(256),action:z.unknown()}).strict(),(db,id,d)=>actGuildRaid(db,id,d.guildId,d.attemptId,d.sequence,d.action)));
 app.post("/raid/abandon",raidMutation(z.object({guildId:uuid,attemptId:uuid}).strict(),(db,id,d)=>abandonGuildRaid(db,id,d.guildId,d.attemptId)));
 app.post("/raid/claim",raidMutation(z.object({guildId:uuid,week:z.string().regex(/^\d{4}-\d{2}-\d{2}$/)}).strict(),(db,id,d)=>claimGuildRaid(db,id,d.guildId,d.week)));
 app.post("/shop/buy",mutation(z.object({guildId:uuid,requestId:uuid,week:z.string().regex(/^\d{4}-\d{2}-\d{2}$/),offerId:z.enum(["moonpetal","gothic_shard","dew","royal_seal","hollow_heart"])}).strict(),async(db,id,d)=>{
  const r=await buyGuildOffer(db,id,d.guildId,d.requestId,d.week,d.offerId);
  if(!r.ok)return error(r.reason==="guild_membership_required"?403:409,r.reason);
  return ok(r);
 }));
 app.post("/perks/purchase",mutation(z.object({guildId:uuid,perkId:z.enum(["hall_1","hall_2","hall_3"])}).strict(),async(db,id,d)=>{
  const m=await membership(db,id);
  if(!m||m.guild_id!==d.guildId||m.role!=="leader")return error(403,"guild_permission_required");
  const perk=guildPerks.find(p=>p.id===d.perkId)!;
  const owned=await purchasedPerks(db,m.guild_id);
  if(owned.has(perk.id))return ok({purchased:perk.id,replayed:true});
  const guild=(await db.query("SELECT level FROM guilds WHERE id=$1 FOR UPDATE",[m.guild_id])).rows[0];
  if(!guild||guild.level<perk.level)return error(409,"guild_level_required");
  if(perk.requires&&!owned.has(perk.requires))return error(409,"guild_prerequisite_required");
  const treasury=await guildTreasury(db,id,m.guild_id);
  if(!treasury||BigInt(treasury.gold)<BigInt(perk.cost))return error(409,"insufficient_treasury_gold");
  await db.query("INSERT INTO guild_perks(guild_id,perk_id,gold_cost) VALUES($1,$2,$3)",[m.guild_id,perk.id,perk.cost]);
  await db.query("INSERT INTO guild_bank_ledger(guild_id,player_id,currency_id,delta,reason) VALUES($1,$2,'gold',-$3::bigint,$4)",[m.guild_id,id,perk.cost,"guild_perk:"+perk.id]);
  return ok({purchased:perk.id,replayed:false,capacity:perk.capacity});
 }));
 app.post("/treasury/donate",mutation(z.object({guildId:uuid,requestId:uuid,amount:z.number().int().min(1).max(GUILD_DAILY_GOLD_CAP)}).strict(),async(db,id,d)=>{
  const m=await membership(db,id);if(!m||m.guild_id!==d.guildId)return error(403,"guild_membership_required");
  const key="guild-donation:"+d.requestId;
  const prior=(await db.query("SELECT delta::text,ref_id FROM currency_ledger WHERE player_id=$1 AND idempotency_key=$2",[id,key])).rows[0];
  if(prior){
   if(prior.ref_id!==m.guild_id||Number(prior.delta)!==-d.amount)return error(409,"donation_request_conflict");
   return ok({donated:d.amount,replayed:true,treasury:await guildTreasury(db,id,m.guild_id)});
  }
  if(await donatedToday(db,id)+d.amount>GUILD_DAILY_GOLD_CAP)return error(409,"guild_donation_daily_cap");
  const wallet=await db.query("UPDATE player_currencies SET balance=balance-$2 WHERE player_id=$1 AND currency_id='gold' AND balance>=$2 RETURNING balance::text",[id,d.amount]);
  if(!wallet.rowCount)return error(409,"insufficient_gold");
  await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',-$2::bigint,$3,'guild_donation','guild',$4,$5)",[id,d.amount,wallet.rows[0].balance,m.guild_id,key]);
  await db.query("INSERT INTO guild_bank_ledger(guild_id,player_id,currency_id,delta,reason,request_id) VALUES($1,$2,'gold',$3,'guild_donation',$4)",[m.guild_id,id,d.amount,d.requestId]);
  return ok({donated:d.amount,replayed:false,treasury:await guildTreasury(db,id,m.guild_id)});
 }));
 app.post("/missions/claim",mutation(z.object({guildId:uuid,day:z.string().regex(/^\d{4}-\d{2}-\d{2}$/),missionId:z.enum(["checkin","victories","daily_duties"])}).strict(),async(db,id,d)=>{
  const m=await membership(db,id);if(!m||m.guild_id!==d.guildId)return error(403,"guild_membership_required");
  const state=await guildMissionState(db,id,m.guild_id);
  const task=state?.rows.find(row=>row.id===d.missionId);
  if(!state||state.day!==d.day||!task?.canClaim)return error(409,"guild_mission_not_claimable");
  const inserted=await db.query("INSERT INTO guild_mission_claims(player_id,guild_id,mission_day,mission_id,xp) VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING RETURNING xp",[id,m.guild_id,state.day,task.id,task.xp]);
  if(!inserted.rowCount)return error(409,"guild_mission_not_claimable");
  const updated=await db.query("UPDATE guilds SET xp=xp+$2,level=GREATEST(level,1+((xp+$2)/$3)::int) WHERE id=$1 RETURNING level,xp::text",[m.guild_id,task.xp,GUILD_LEVEL_XP]);
  const awardedTokens=task.xp/5;
  await grantGuildTokens(db,id,awardedTokens,state.day+":"+task.id);
  return ok({awardedXp:task.xp,awardedTokens,...updated.rows[0]});
 }));
 app.post("/create",mutation(guildFields,async(db,id,d)=>{
  if(await membership(db,id))return error(409,"already_in_guild");
  const g=(await db.query("INSERT INTO guilds(name,description,emblem,leader_id,tag) VALUES($1,$2,$3,$4,gen_random_uuid()::text) ON CONFLICT DO NOTHING RETURNING id",[d.name,d.description,d.emblem,id])).rows[0];
  if(!g)return error(409,"guild_name_taken");
  await db.query("INSERT INTO guild_members(guild_id,player_id,guild_rank) VALUES($1,$2,'leader')",[g.id,id]);
  await db.query("DELETE FROM guild_requests WHERE player_id=$1",[id]);
  return {status:201,data:{guildId:g.id}};
 }));
 app.post("/apply",mutation(z.object({guildId:uuid}).strict(),async(db,id,d)=>{
  if(await membership(db,id))return error(409,"already_in_guild");
  const g=(await db.query("SELECT id FROM guilds WHERE id=$1",[d.guildId])).rows[0];if(!g)return error(404,"guild_unavailable");
  const n=(await db.query("SELECT count(*)::int AS n FROM guild_members WHERE guild_id=$1",[g.id])).rows[0].n;
  if(n>=await guildCapacity(db,g.id))return error(409,"guild_full");
  const pending=(await db.query("SELECT count(*)::int AS n FROM guild_requests WHERE player_id=$1 AND expires_at>now()",[id])).rows[0].n;
  if(pending>=10)return error(409,"too_many_requests");
  await db.query("INSERT INTO guild_requests(guild_id,player_id,kind) VALUES($1,$2,'application') ON CONFLICT(guild_id,player_id,kind) DO UPDATE SET expires_at=now()+interval '7 days'",[g.id,id]);return ok({applied:true});
 }));
 app.post("/invite",mutation(z.object({playerId:uuid}).strict(),async(db,id,d)=>{
  const m=await manager(db,id);if(!m)return error(403,"guild_permission_required");
  if(d.playerId===id||!await activePlayer(db,d.playerId)||await blocked(db,id,d.playerId))return error(404,"player_unavailable");
  if(await membership(db,d.playerId))return error(409,"already_in_guild");
  const n=(await db.query("SELECT count(*)::int AS n FROM guild_members WHERE guild_id=$1",[m.guild_id])).rows[0].n;if(n>=await guildCapacity(db,m.guild_id))return error(409,"guild_full");
  const pending=(await db.query("SELECT count(*)::int AS n FROM guild_requests WHERE guild_id=$1 AND kind='invitation' AND expires_at>now()",[m.guild_id])).rows[0].n;if(pending>=30)return error(409,"too_many_requests");
  await db.query("INSERT INTO guild_requests(guild_id,player_id,kind,sender_id) VALUES($1,$2,'invitation',$3) ON CONFLICT(guild_id,player_id,kind) DO UPDATE SET sender_id=EXCLUDED.sender_id,expires_at=now()+interval '7 days'",[m.guild_id,d.playerId,id]);return ok({invited:true});
 }));
 app.post("/application",mutation(z.object({playerId:uuid,accept:z.boolean()}).strict(),async(db,id,d)=>{
  const m=await manager(db,id);if(!m)return error(403,"guild_permission_required");
  const r=await db.query("SELECT 1 FROM guild_requests WHERE guild_id=$1 AND player_id=$2 AND kind='application' AND expires_at>now()",[m.guild_id,d.playerId]);
  if(!r.rowCount||await blocked(db,id,d.playerId))return error(404,"request_unavailable");
  if(d.accept)return join(db,m.guild_id,d.playerId);
  await db.query("DELETE FROM guild_requests WHERE guild_id=$1 AND player_id=$2 AND kind='application'",[m.guild_id,d.playerId]);return ok({declined:true});
 }));
 app.post("/invitation",mutation(z.object({guildId:uuid,accept:z.boolean()}).strict(),async(db,id,d)=>{
  const r=(await db.query("SELECT sender_id FROM guild_requests WHERE guild_id=$1 AND player_id=$2 AND kind='invitation' AND expires_at>now()",[d.guildId,id])).rows[0];
  if(!r||await blocked(db,id,r.sender_id))return error(404,"request_unavailable");
  if(d.accept){const inviter=await manager(db,r.sender_id);if(!inviter||inviter.guild_id!==d.guildId)return error(404,"request_unavailable");return join(db,d.guildId,id);}
  await db.query("DELETE FROM guild_requests WHERE guild_id=$1 AND player_id=$2 AND kind='invitation'",[d.guildId,id]);return ok({declined:true});
 }));
 app.post("/cancel",mutation(z.object({guildId:uuid}).strict(),async(db,id,d)=>{
  await db.query("DELETE FROM guild_requests WHERE guild_id=$1 AND player_id=$2 AND kind='application'",[d.guildId,id]);return ok({cancelled:true});
 }));
 app.post("/role",mutation(z.object({playerId:uuid,role:z.enum(["officer","member","leader"])}).strict(),async(db,id,d)=>{
  const m=await membership(db,id);if(m?.role!=="leader")return error(403,"guild_permission_required");
  const target=await membership(db,d.playerId);
  if(d.playerId===id||target?.guild_id!==m.guild_id)return error(404,"member_unavailable");
  if(d.role==="leader")await db.query("UPDATE guild_members SET guild_rank='member' WHERE player_id=$1",[id]);
  await db.query("UPDATE guild_members SET guild_rank=$2 WHERE player_id=$1",[d.playerId,d.role]);if(d.role==="leader")await db.query("UPDATE guilds SET leader_id=$2 WHERE id=$1",[m.guild_id,d.playerId]);return ok({updated:true});
 }));
 app.post("/kick",mutation(z.object({playerId:uuid}).strict(),async(db,id,d)=>{
  const m=await manager(db,id);if(!m)return error(403,"guild_permission_required");
  const t=await membership(db,d.playerId);
  if(!t||t.guild_id!==m.guild_id||d.playerId===id||t.role==="leader"||(m.role==="officer"&&t.role!=="member"))return error(403,"guild_permission_required");
  await db.query("DELETE FROM guild_members WHERE player_id=$1",[d.playerId]);return ok({removed:true});
 }));
 app.post("/leave",mutation(z.object({}).strict(),async(db,id)=>{
  const m=await membership(db,id);if(!m)return error(404,"not_in_guild");
  if(m.role==="leader"){
   const n=(await db.query("SELECT count(*)::int AS n FROM guild_members WHERE guild_id=$1",[m.guild_id])).rows[0].n;
   if(n>1)return error(409,"transfer_leadership_first");
   await db.query("DELETE FROM guilds WHERE id=$1",[m.guild_id]);return ok({disbanded:true});
  }
  await db.query("DELETE FROM guild_members WHERE player_id=$1",[id]);return ok({left:true});
 }));
 app.post("/settings",mutation(guildFields,async(db,id,d)=>{
  const m=await membership(db,id);if(m?.role!=="leader")return error(403,"guild_permission_required");
  await db.query("UPDATE guilds SET name=$2,description=$3,emblem=$4 WHERE id=$1",[m.guild_id,d.name,d.description,d.emblem]);return ok({updated:true});
 }));
};