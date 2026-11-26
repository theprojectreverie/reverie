import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {z} from "zod";
import {pool} from "../db.js";
import {config} from "../config.js";
const uuid=z.string().uuid();
export const staffOwners=new Set(config.STAFF_OWNER_ACCOUNT_IDS.split(",").map(v=>v.trim()).filter(v=>uuid.safeParse(v).success));
const legacy=new Set(config.DEVELOPER_ACCOUNT_IDS.split(",").map(v=>v.trim()).filter(v=>uuid.safeParse(v).success));
export async function staffActivityAccess(id:string):Promise<boolean>{
 return staffOwners.has(id)||!!(await pool.query("SELECT 1 FROM reverie_staff_roles WHERE account_id=$1",[id])).rowCount;
}
type Claims={sub:string;playerId:string;tokenVersion:number};
async function owner(req:FastifyRequest,reply:FastifyReply):Promise<Claims|null>{
 try{await req.jwtVerify();}catch{reply.code(401).send({error:"authentication_required"});return null;}
 const c=req.user as Claims;
 if(!uuid.safeParse(c.sub).success||!uuid.safeParse(c.playerId).success||!Number.isInteger(c.tokenVersion)){reply.code(401).send({error:"authentication_required"});return null;}
 if(!staffOwners.has(c.sub)){reply.code(403).send({error:"owner_required"});return null;}
 const q=await pool.query("SELECT 1 FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=$1 AND p.id=$2 AND a.status='active' AND a.token_version=$3",[c.sub,c.playerId,c.tokenVersion]);
 if(!q.rowCount){reply.code(401).send({error:"session_revoked"});return null;}
 return c;
}
const change=z.object({playerName:z.string().trim().min(3).max(32),role:z.enum(["admin","moderator","analyst","revoke"]),note:z.string().trim().min(8).max(300)}).strict();
export const staffRoutes:FastifyPluginAsync=async app=>{
 app.addHook("onSend",async(_req,reply,payload)=>{reply.header("Cache-Control","no-store");return payload;});
 app.get("/",async(req,reply)=>{
  const c=await owner(req,reply);if(!c)return;
  const roles=await pool.query("SELECT p.name AS name,r.role,r.assigned_at FROM reverie_staff_roles r JOIN players p ON p.account_id=r.account_id ORDER BY lower(p.name)");
  const audit=await pool.query("SELECT COALESCE(p.name,'Former owner') AS actor,a.target_name AS target,a.previous_role,a.new_role,a.note,a.created_at FROM reverie_staff_audit a LEFT JOIN players p ON p.account_id=a.actor_account_id ORDER BY a.id DESC LIMIT 100");
  return {roles:roles.rows,audit:audit.rows};
 });
 app.get("/statistics",{config:{rateLimit:{max:15,timeWindow:"1 minute"}}},async(req,reply)=>{
  const c=await owner(req,reply);if(!c)return;
  const f=z.object({days:z.enum(["7","30","90"]).default("30")}).strict().safeParse(req.query);
  if(!f.success)return reply.code(400).send({error:"invalid_statistics_period"});
  const days=Number(f.data.days);
  // Aggregate existing completed actions only. An appeal approval also
  // ends a suspension; count it as an appeal decision, not a second manual lift.
  const result=await pool.query(`
   WITH bounds AS (SELECT now()-$1::int*interval '1 day' AS since,now() AS until),
   events AS (
    SELECT actor_account_id AS actor,action AS kind,created_at AS at FROM reverie_moderation_audit
    UNION ALL SELECT actor_account_id,'suspension',created_at FROM reverie_account_suspensions
    UNION ALL SELECT s.ended_by,'manual_lift',s.ended_at FROM reverie_account_suspensions s
     WHERE s.ended_by IS NOT NULL AND NOT EXISTS(SELECT 1 FROM reverie_suspension_appeals v WHERE v.suspension_id=s.id AND v.status='approved')
    UNION ALL SELECT reviewed_by,'report_'||status,reviewed_at FROM reverie_chat_reports WHERE reviewed_by IS NOT NULL
    UNION ALL SELECT reviewed_by,'appeal_'||status,reviewed_at FROM reverie_suspension_appeals WHERE reviewed_by IS NOT NULL
    UNION ALL SELECT actor_account_id,'role_change',created_at FROM reverie_staff_audit
   ), counts AS (
    SELECT actor,count(*)::int AS total,max(at) AS last_action,
    count(*) FILTER(WHERE kind='warn')::int AS warnings,
    count(*) FILTER(WHERE kind='mute')::int AS mutes,
    count(*) FILTER(WHERE kind='unmute')::int AS unmutes,
    count(*) FILTER(WHERE kind='suspension')::int AS suspensions,
    count(*) FILTER(WHERE kind='manual_lift')::int AS manual_lifts,
    count(*) FILTER(WHERE kind='report_resolved')::int AS reports_resolved,
    count(*) FILTER(WHERE kind='report_dismissed')::int AS reports_dismissed,
    count(*) FILTER(WHERE kind='appeal_approved')::int AS appeals_approved,
    count(*) FILTER(WHERE kind='appeal_rejected')::int AS appeals_rejected,
    count(*) FILTER(WHERE kind='appeal_closed')::int AS appeals_closed,
    count(*) FILTER(WHERE kind='role_change')::int AS role_changes
    FROM events CROSS JOIN bounds WHERE at>=since AND at<=until AND actor IS NOT NULL GROUP BY actor
   ), roster AS (
    SELECT account_id AS id FROM reverie_staff_roles
    UNION SELECT unnest($2::uuid[])
    UNION SELECT actor FROM counts
   )
   SELECT COALESCE(p.name,'Former staff') AS name,
    CASE WHEN r.id=ANY($2::uuid[]) THEN 'owner' ELSE COALESCE(sr.role,'former_staff') END AS role,
    COALESCE(k.total,0) AS total,k.last_action,
    COALESCE(k.warnings,0) AS warnings,COALESCE(k.mutes,0) AS mutes,COALESCE(k.unmutes,0) AS unmutes,
    COALESCE(k.suspensions,0) AS suspensions,COALESCE(k.manual_lifts,0) AS manual_lifts,
    COALESCE(k.reports_resolved,0) AS reports_resolved,COALESCE(k.reports_dismissed,0) AS reports_dismissed,
    COALESCE(k.appeals_approved,0) AS appeals_approved,COALESCE(k.appeals_rejected,0) AS appeals_rejected,
    COALESCE(k.appeals_closed,0) AS appeals_closed,COALESCE(k.role_changes,0) AS role_changes,
    bounds.since,bounds.until
   FROM roster r CROSS JOIN bounds LEFT JOIN players p ON p.account_id=r.id
   LEFT JOIN reverie_staff_roles sr ON sr.account_id=r.id LEFT JOIN counts k ON k.actor=r.id
   ORDER BY lower(COALESCE(p.name,'Former staff')),r.id LIMIT 501
  `,[days,[...staffOwners]]);
  return {days,since:result.rows[0]?.since??null,until:result.rows[0]?.until??null,more:result.rows.length>500,staff:result.rows.slice(0,500).map(({since,until,...row})=>row)};
 });
 app.post("/",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(req,reply)=>{
  const c=await owner(req,reply);if(!c)return;
  const parsed=change.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_staff_change"});
  const {playerName,role,note}=parsed.data;
  const db=await pool.connect();
  try{
   await db.query("BEGIN");
   await db.query("SELECT pg_advisory_xact_lock(568923411)");
   const fresh=await db.query("SELECT 1 FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=$1 AND p.id=$2 AND a.status='active' AND a.token_version=$3 FOR UPDATE OF a",[c.sub,c.playerId,c.tokenVersion]);
   if(!fresh.rowCount){await db.query("ROLLBACK");return reply.code(401).send({error:"session_revoked"});}
   const q=await db.query<{id:string;name:string;status:string}>("SELECT a.id,p.name,a.status FROM players p JOIN accounts a ON a.id=p.account_id WHERE lower(p.name)=lower($1) LIMIT 2",[playerName]);
   const t=q.rows[0];
   if(q.rows.length!==1||!t){await db.query("ROLLBACK");return reply.code(404).send({error:"player_not_found"});}
   if(staffOwners.has(t.id)||legacy.has(t.id)){await db.query("ROLLBACK");return reply.code(409).send({error:"configured_account_protected"});}
   if(role!=="revoke"&&t.status!=="active"){await db.query("ROLLBACK");return reply.code(409).send({error:"account_inactive"});}
   const old=(await db.query<{role:string}>("SELECT role FROM reverie_staff_roles WHERE account_id=$1",[t.id])).rows[0]?.role??null;
   const next=role==="revoke"?null:role;
   if(old===next){await db.query("COMMIT");return {ok:true,changed:false};}
   if(next)await db.query("INSERT INTO reverie_staff_roles(account_id,role,assigned_by) VALUES($1,$2,$3) ON CONFLICT(account_id) DO UPDATE SET role=EXCLUDED.role,assigned_by=EXCLUDED.assigned_by,assigned_at=now()",[t.id,next,c.sub]);
   else await db.query("DELETE FROM reverie_staff_roles WHERE account_id=$1",[t.id]);
   await db.query("INSERT INTO reverie_staff_audit(actor_account_id,target_account_id,target_name,previous_role,new_role,note) VALUES($1,$2,$3,$4,$5,$6)",[c.sub,t.id,t.name,old,next,note]);
   await db.query("COMMIT");return {ok:true,changed:true};
  }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 });
};