import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import type {PoolClient} from "pg";
import {z} from "zod";
import {pool} from "../db.js";
import {config} from "../config.js";
import {staffOwners} from "./staff.js";
import {currentSuspension,expireSuspension} from "../world/account-suspensions.js";
const uuid=z.string().uuid();
const legacy=new Set([config.DEVELOPER_ACCOUNT_IDS,config.COMPENSATION_ADMIN_ACCOUNT_IDS,process.env.PAYMENT_REVIEW_ADMIN_ACCOUNT_IDS??""].join(",").split(",").map(s=>s.trim()));
type Claims={sub:string;playerId:string;tokenVersion:number};
async function roleFor(c:Claims,db:PoolClient|typeof pool=pool){
 const r=await db.query("SELECT r.role FROM accounts a JOIN players p ON p.account_id=a.id LEFT JOIN reverie_staff_roles r ON r.account_id=a.id WHERE a.id=$1 AND p.id=$2 AND a.status='active' AND a.token_version=$3",[c.sub,c.playerId,c.tokenVersion]);
 if(!r.rowCount)return null;
 return staffOwners.has(c.sub)?"owner":r.rows[0].role??"player";
}
async function authorize(req:FastifyRequest,reply:FastifyReply){
 try{await req.jwtVerify();}catch{reply.code(401).send({error:"authentication_required"});return null;}
 const c=req.user as Claims;
 if(!uuid.safeParse(c.sub).success||!uuid.safeParse(c.playerId).success||!Number.isInteger(c.tokenVersion)){reply.code(401).send({error:"authentication_required"});return null;}
 const role=await roleFor(c);
 if(!role){reply.code(401).send({error:"session_revoked"});return null;}
 if(!["owner","admin","moderator"].includes(role)){reply.code(403).send({error:"moderation_access_required"});return null;}
 return c;
}
export async function suspensionAccess(id:string){
 return staffOwners.has(id)||!!(await pool.query("SELECT 1 FROM reverie_staff_roles WHERE account_id=$1 AND role='admin'",[id])).rowCount;
}
export async function moderationAccess(id:string){
 return staffOwners.has(id)||!!(await pool.query("SELECT 1 FROM reverie_staff_roles WHERE account_id=$1 AND role IN ('admin','moderator')",[id])).rowCount;
}
const common={playerName:z.string().trim().min(3).max(32),reason:z.string().trim().min(8).max(300)};
const action=z.discriminatedUnion("action",[
 z.object({...common,action:z.literal("warn")}).strict(),
 z.object({...common,action:z.literal("mute"),minutes:z.number().int().min(5).max(10080)}).strict(),
 z.object({...common,action:z.literal("unmute")}).strict()
]);
export const moderationRoutes:FastifyPluginAsync=async app=>{
 app.addHook("onSend",async(_req,reply,payload)=>{reply.header("Cache-Control","no-store");return payload});
 app.get("/",async(req,reply)=>{
  const c=await authorize(req,reply);if(!c)return;
  const messages=await pool.query("SELECT m.id,m.sender_name AS name,m.body AS text,m.created_at FROM recent_chat_messages m WHERE m.channel='world' AND m.created_at>=now()-interval '30 minutes' ORDER BY m.created_at DESC LIMIT 100");
  const mutes=await pool.query("SELECT p.name,m.muted_until FROM reverie_chat_mutes m JOIN players p ON p.id=m.player_id WHERE m.muted_until>now() ORDER BY m.muted_until LIMIT 100");
  const audit=await pool.query("SELECT COALESCE(p.name,'Former staff') AS actor,a.target_name AS target,a.action,a.reason,a.muted_until,a.created_at FROM reverie_moderation_audit a LEFT JOIN players p ON p.account_id=a.actor_account_id ORDER BY a.id DESC LIMIT 100");
  return {messages:messages.rows,mutes:mutes.rows,audit:audit.rows};
 });
 app.get("/players",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
  const c=await authorize(req,reply);if(!c)return;
  const f=z.object({q:z.string().trim().min(3).max(20).regex(/^[A-Za-z0-9_]+$/)}).strict().safeParse(req.query);
  if(!f.success)return reply.code(400).send({error:"invalid_player_search"});
  const prefix=f.data.q.toLowerCase();
  const rows=await pool.query("SELECT p.id,p.name,p.level,a.status FROM players p JOIN accounts a ON a.id=p.account_id WHERE starts_with(lower(p.name),$1) AND a.status<>'deleted' ORDER BY (lower(p.name)=$1) DESC,lower(p.name),p.id LIMIT 21",[prefix]);
  return {players:rows.rows.slice(0,20),more:rows.rows.length>20};
 });
 app.get("/players/:id",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
  const c=await authorize(req,reply);if(!c)return;
  const f=z.object({id:uuid}).strict().safeParse(req.params);
  if(!f.success)return reply.code(400).send({error:"invalid_player_id"});
  const role=await roleFor(c);
  if(!role||!["owner","admin","moderator"].includes(role))return reply.code(403).send({error:"moderation_access_required"});
  const t=(await pool.query("SELECT p.id,p.name,p.level,p.created_at,a.id AS account_id,a.status,r.role,m.muted_until FROM players p JOIN accounts a ON a.id=p.account_id LEFT JOIN reverie_staff_roles r ON r.account_id=a.id LEFT JOIN reverie_chat_mutes m ON m.player_id=p.id AND m.muted_until>clock_timestamp() WHERE p.id=$1 AND a.status<>'deleted'",[f.data.id])).rows[0];
  if(!t)return reply.code(404).send({error:"player_not_found"});
  const protectedAccount=staffOwners.has(t.account_id)||legacy.has(t.account_id)||Boolean(t.role)||t.account_id===c.sub;
  const admin=role==="owner"||role==="admin";
  const history=await pool.query("SELECT a.action,a.reason,a.muted_until,a.created_at,COALESCE(p.name,'Former staff') AS actor FROM reverie_moderation_audit a LEFT JOIN players p ON p.account_id=a.actor_account_id WHERE a.target_player_id=$1 ORDER BY a.id DESC LIMIT 50",[t.id]);
  const counts=await pool.query("SELECT status,count(*)::int AS total FROM reverie_chat_reports WHERE target_player_id=$1 GROUP BY status",[t.id]);
  const suspensions=admin?(await pool.query("SELECT s.reason,s.created_at,s.suspended_until,s.ended_at,s.end_reason,COALESCE(p.name,'Former staff') AS actor FROM reverie_account_suspensions s LEFT JOIN players p ON p.account_id=s.actor_account_id WHERE s.account_id=$1 ORDER BY s.created_at DESC,s.id LIMIT 50",[t.account_id])).rows:null;
  return {player:{id:t.id,name:t.name,level:t.level,status:t.status,createdAt:t.created_at,mutedUntil:t.muted_until,protectedAccount},canModerate:!protectedAccount,canSuspend:admin&&!protectedAccount,history:history.rows,reports:counts.rows,suspensions};
 });
 app.get("/suspensions",async(req,reply)=>{
  const c=await authorize(req,reply);if(!c)return;
  if(!["owner","admin"].includes(await roleFor(c)??""))return reply.code(403).send({error:"admin_required"});
  const q=await pool.query("SELECT s.id,s.target_name,s.reason,s.created_at,s.suspended_until,s.ended_at,s.end_reason,COALESCE(p.name,'Former staff') AS actor,CASE WHEN s.ended_at IS NOT NULL THEN 'ended' WHEN a.status<>'suspended' OR a.token_version<>s.suspension_version THEN 'superseded' WHEN s.suspended_until<=clock_timestamp() THEN 'expired' ELSE 'active' END AS status FROM reverie_account_suspensions s JOIN accounts a ON a.id=s.account_id LEFT JOIN players p ON p.account_id=s.actor_account_id ORDER BY s.created_at DESC LIMIT 100");
  return {suspensions:q.rows};
 });
 app.post("/suspensions",{config:{rateLimit:{max:8,timeWindow:"1 minute"}}},async(req,reply)=>{
  const c=await authorize(req,reply);if(!c)return;
  const parsed=z.discriminatedUnion("action",[
   z.object({...common,action:z.literal("suspend"),minutes:z.number().int().min(5).max(43200)}).strict(),
   z.object({...common,action:z.literal("lift")}).strict()
  ]).safeParse(req.body);
  if(!parsed.success)return reply.code(400).send({error:"invalid_suspension"});
  const a=parsed.data,db=await pool.connect();
  try{
   await db.query("BEGIN");await db.query("SELECT pg_advisory_xact_lock(568923411)");
   const role=await roleFor(c,db);
   const fail=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error})};
   if(!role)return await fail(401,"session_revoked");
   if(!["owner","admin"].includes(role))return await fail(403,"admin_required");
   if(a.action==="suspend"&&role==="admin"&&a.minutes>10080)return await fail(403,"admin_duration_limit");
   const q=await db.query("SELECT p.id,p.name,p.account_id,r.role,ac.status,ac.token_version FROM players p JOIN accounts ac ON ac.id=p.account_id LEFT JOIN reverie_staff_roles r ON r.account_id=p.account_id WHERE lower(p.name)=lower($1) LIMIT 2 FOR UPDATE OF ac",[a.playerName]);
   const t=q.rows[0];
   if(q.rows.length!==1||!t)return await fail(404,"player_not_found");
   if(staffOwners.has(t.account_id)||legacy.has(t.account_id)||t.role||t.account_id===c.sub)return await fail(403,"staff_target_protected");
   if(a.action==="lift"){
    const active=await currentSuspension(db,t.account_id,t.token_version);
    if(t.status!=="suspended"||!active)return await fail(409,"managed_suspension_required");
    await db.query("UPDATE accounts SET status='active',updated_at=now() WHERE id=$1",[t.account_id]);
    await db.query("UPDATE reverie_account_suspensions SET ended_at=now(),ended_by=$2,end_reason=$3 WHERE id=$1",[active.id,c.sub,a.reason]);
    await db.query("COMMIT");return {ok:true};
   }
   if(t.status==="suspended"){
    const previous=await currentSuspension(db,t.account_id,t.token_version);
    if(!previous?.expired||!await expireSuspension(db,t.account_id,t.token_version,previous.id))return await fail(409,"account_already_restricted");
   }else if(t.status!=="active")return await fail(409,"account_already_restricted");
   // Do not silently replace a suspension record if another administrator changed the account.
   if((await db.query("SELECT 1 FROM reverie_account_suspensions WHERE account_id=$1 AND ended_at IS NULL",[t.account_id])).rowCount)return await fail(409,"managed_suspension_conflict");
   const updated=await db.query("UPDATE accounts SET status='suspended',token_version=token_version+1,updated_at=now() WHERE id=$1 RETURNING token_version",[t.account_id]);
   await db.query("UPDATE account_sessions SET revoked_at=now() WHERE account_id=$1 AND revoked_at IS NULL",[t.account_id]);
   const saved=await db.query("INSERT INTO reverie_account_suspensions(account_id,actor_account_id,target_name,reason,suspension_version,suspended_until) VALUES($1,$2,$3,$4,$5,clock_timestamp()+$6::int*interval '1 minute') RETURNING suspended_until",[t.account_id,c.sub,t.name,a.reason,updated.rows[0].token_version,a.minutes]);
   await db.query("UPDATE player_presence SET state='offline' WHERE player_id=$1",[t.id]);
   await db.query("DELETE FROM game_server_player_connections WHERE player_id=$1",[t.id]);
   await db.query("COMMIT");return {ok:true,suspendedUntil:saved.rows[0].suspended_until};
  }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 });
 app.get("/appeals",async(req,reply)=>{
  const c=await authorize(req,reply);if(!c)return;
  if(!["owner","admin"].includes(await roleFor(c)??""))return reply.code(403).send({error:"admin_required"});
  const f=z.object({status:z.enum(["pending","approved","rejected","closed"]).default("pending")}).strict().safeParse(req.query);
  if(!f.success)return reply.code(400).send({error:"invalid_filter"});
  const q=await pool.query("SELECT v.id,v.statement,v.status,v.created_at,v.review_note,v.reviewed_at,s.target_name,s.reason,s.suspended_until,COALESCE(p.name,'Former staff') AS imposed_by,COALESCE(r.name,'Former staff') AS reviewer,(s.ended_at IS NULL AND a.status='suspended' AND a.token_version=s.suspension_version AND s.suspended_until>clock_timestamp()) AS actionable,(s.actor_account_id=$2) AS conflict FROM reverie_suspension_appeals v JOIN reverie_account_suspensions s ON s.id=v.suspension_id JOIN accounts a ON a.id=s.account_id LEFT JOIN players p ON p.account_id=s.actor_account_id LEFT JOIN players r ON r.account_id=v.reviewed_by WHERE v.status=$1 ORDER BY v.created_at DESC,v.id LIMIT 100",[f.data.status,c.sub]);
  return {appeals:q.rows};
 });
 app.post("/appeals",{config:{rateLimit:{max:8,timeWindow:"1 minute"}}},async(req,reply)=>{
  const c=await authorize(req,reply);if(!c)return;
  const parsed=z.object({id:uuid,decision:z.enum(["approve","reject","close"]),note:z.string().trim().min(8).max(300)}).strict().safeParse(req.body);
  if(!parsed.success)return reply.code(400).send({error:"invalid_appeal_review"});
  const d=parsed.data,db=await pool.connect();
  try{
   await db.query("BEGIN");await db.query("SELECT pg_advisory_xact_lock(568923411)");
   const role=await roleFor(c,db);
   const fail=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error})};
   if(!role)return await fail(401,"session_revoked");
   if(!["owner","admin"].includes(role))return await fail(403,"admin_required");
   const target=(await db.query("SELECT s.account_id FROM reverie_suspension_appeals v JOIN reverie_account_suspensions s ON s.id=v.suspension_id WHERE v.id=$1",[d.id])).rows[0];
   if(!target)return await fail(404,"appeal_not_found");
   const account=(await db.query("SELECT status,token_version FROM accounts WHERE id=$1 FOR UPDATE",[target.account_id])).rows[0];
   const row=(await db.query("SELECT v.status,s.id AS suspension_id,s.actor_account_id,s.suspension_version,s.ended_at,s.suspended_until<=clock_timestamp() AS expired FROM reverie_suspension_appeals v JOIN reverie_account_suspensions s ON s.id=v.suspension_id WHERE v.id=$1 FOR UPDATE OF v,s",[d.id])).rows[0];
   if(!row||!account)return await fail(404,"appeal_not_found");
   if(row.status!=="pending")return await fail(409,"appeal_already_reviewed");
   if(row.actor_account_id===c.sub||target.account_id===c.sub)return await fail(403,"conflict_of_interest");
   const live=!row.ended_at&&!row.expired&&account.status==="suspended"&&account.token_version===row.suspension_version;
   if(d.decision==="close"?live:!live)return await fail(409,live?"active_suspension_requires_decision":"suspension_no_longer_active");
   if(d.decision==="approve"){
    const updated=await db.query("UPDATE accounts SET status='active',updated_at=now() WHERE id=$1 AND status='suspended' AND token_version=$2 RETURNING id",[target.account_id,row.suspension_version]);
    if(!updated.rowCount)return await fail(409,"suspension_no_longer_active");
    await db.query("UPDATE reverie_account_suspensions SET ended_at=now(),ended_by=$2,end_reason=$3 WHERE id=$1 AND ended_at IS NULL",[row.suspension_id,c.sub,d.note]);
   }
   const status=d.decision==="approve"?"approved":d.decision==="reject"?"rejected":"closed";
   await db.query("UPDATE reverie_suspension_appeals SET status=$2,reviewed_by=$3,review_note=$4,reviewed_at=now() WHERE id=$1",[d.id,status,c.sub,d.note]);
   await db.query("COMMIT");return {ok:true,status};
  }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 });
 app.get("/reports",async(req,reply)=>{
  const c=await authorize(req,reply);if(!c)return;
  const filter=z.object({status:z.enum(["pending","resolved","dismissed"]).default("pending")}).strict().safeParse(req.query);
  if(!filter.success)return reply.code(400).send({error:"invalid_filter"});
  const q=await pool.query("SELECT r.id,r.target_name,r.message_text,r.message_at,r.created_at,r.status,r.review_note,r.reviewed_at,p.name AS reviewer FROM reverie_chat_reports r LEFT JOIN players p ON p.account_id=r.reviewed_by WHERE r.status=$1 ORDER BY r.created_at DESC,r.id LIMIT 100",[filter.data.status]);
  return {reports:q.rows};
 });
 app.post("/reports",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(req,reply)=>{
  const c=await authorize(req,reply);if(!c)return;
  const parsed=z.object({id:uuid,status:z.enum(["resolved","dismissed"]),note:z.string().trim().min(8).max(300)}).strict().safeParse(req.body);
  if(!parsed.success)return reply.code(400).send({error:"invalid_report_review"});
  const db=await pool.connect();
  try{
   await db.query("BEGIN");await db.query("SELECT pg_advisory_xact_lock(568923411)");
   const role=await roleFor(c,db);
   const fail=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error})};
   if(!role)return await fail(401,"session_revoked");
   if(!["owner","admin","moderator"].includes(role))return await fail(403,"moderation_access_required");
   const found=await db.query("SELECT p.account_id,r.reporter_id,r.target_player_id,r.status FROM reverie_chat_reports r LEFT JOIN players p ON p.id=r.target_player_id WHERE r.id=$1 FOR UPDATE OF r",[parsed.data.id]);
   const row=found.rows[0];
   if(!row)return await fail(404,"report_not_found");
   if(row.account_id===c.sub||row.reporter_id===c.playerId)return await fail(403,"conflict_of_interest");
   if(row.status!=="pending")return await fail(409,"report_already_reviewed");
   await db.query("UPDATE reverie_chat_reports SET status=$2,reviewed_by=$3,review_note=$4,reviewed_at=now() WHERE id=$1",[parsed.data.id,parsed.data.status,c.sub,parsed.data.note]);
   await db.query("COMMIT");return {ok:true};
  }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 });
 app.post("/",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(req,reply)=>{
  const c=await authorize(req,reply);if(!c)return;
  const parsed=action.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_moderation_action"});
  const a=parsed.data,db=await pool.connect();
  try{
   await db.query("BEGIN");
   // Serialize with staff role changes and revalidate current privilege.
   await db.query("SELECT pg_advisory_xact_lock(568923411)");
   const role=await roleFor(c,db);
   const fail=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error})};
   if(!role)return await fail(401,"session_revoked");
   if(!["owner","admin","moderator"].includes(role))return await fail(403,"moderation_access_required");
   if(a.action==="mute"&&role==="moderator"&&a.minutes>1440)return await fail(403,"moderator_duration_limit");
   const q=await db.query("SELECT p.id,p.name,p.account_id,r.role FROM players p LEFT JOIN reverie_staff_roles r ON r.account_id=p.account_id WHERE lower(p.name)=lower($1) LIMIT 2",[a.playerName]);
   const target=q.rows[0];
   if(q.rows.length!==1||!target)return await fail(404,"player_not_found");
   if(staffOwners.has(target.account_id)||legacy.has(target.account_id)||target.role||target.account_id===c.sub)return await fail(403,"staff_target_protected");
   await db.query("SELECT pg_advisory_xact_lock(hashtextextended('reverie-chat:'||$1::uuid::text,0))",[target.id]);
   let until=null;
   if(a.action==="mute"){
    const m=await db.query("INSERT INTO reverie_chat_mutes(player_id,muted_until) VALUES($1,clock_timestamp()+$2::int*interval '1 minute') ON CONFLICT(player_id) DO UPDATE SET muted_until=GREATEST(reverie_chat_mutes.muted_until,EXCLUDED.muted_until) RETURNING muted_until",[target.id,a.minutes]);until=m.rows[0].muted_until;
   }else if(a.action==="unmute"){
    if(role==="moderator")return await fail(403,"admin_required");
    const removed=await db.query("DELETE FROM reverie_chat_mutes WHERE player_id=$1 AND muted_until>clock_timestamp()",[target.id]);if(!removed.rowCount){await db.query("COMMIT");return {ok:true,changed:false};}
   }
   await db.query("INSERT INTO reverie_moderation_audit(actor_account_id,target_player_id,target_name,action,reason,muted_until) VALUES($1,$2,$3,$4,$5,$6)",[c.sub,target.id,target.name,a.action,a.reason,until]);
   await db.query("COMMIT");return {ok:true,changed:true,mutedUntil:until};
  }catch(e){await db.query("ROLLBACK");throw e}finally{db.release()}
 });
};