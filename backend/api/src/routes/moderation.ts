import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import type {PoolClient} from "pg";
import {z} from "zod";
import {pool} from "../db.js";
import {config} from "../config.js";
import {staffOwners} from "./staff.js";
const uuid=z.string().uuid();
const legacy=new Set(config.DEVELOPER_ACCOUNT_IDS.split(",").map(s=>s.trim()));
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