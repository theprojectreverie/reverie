import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {z} from "zod";
import {createHash} from "node:crypto";
import {pool} from "../db.js";
import {config} from "../config.js";
import {paymentReviewHtml} from "./payment-review-dashboard.js";
const uuid=z.string().uuid();
const filter=z.object({status:z.enum(["refund_review","refunded","credited","expired","pending"]).default("refund_review"),limit:z.coerce.number().int().min(1).max(100).default(25),before:z.string().datetime({offset:true}).optional(),beforeId:uuid.optional()}).strict().refine(v=>!!v.before===!!v.beforeId);
const decisionInput=z.object({orderId:uuid,requestId:uuid,evidenceKey:z.string().regex(/^[a-f0-9]{64}$/),action:z.enum(["reviewed_no_adjustment","escalate"]),note:z.string().trim().min(8).max(500)}).strict();
function evidence(row:any){return {status:row.status,amountCents:row.amount_cents,stones:row.stones,refundedCents:row.refunded_cents,disputeSeen:row.dispute_seen,reviewReason:row.review_reason,creditedAt:row.credited_at?new Date(row.credited_at).toISOString():null};}
function evidenceKey(row:any){return createHash("sha256").update(JSON.stringify(evidence(row))).digest("hex");}
export function makePaymentReviewRoutes(accountIds:string):FastifyPluginAsync{
 const allow=new Set(accountIds.split(",").map(s=>s.trim()).filter(s=>uuid.safeParse(s).success));
 async function authorize(req:FastifyRequest,reply:FastifyReply){
  try{await req.jwtVerify();}catch{reply.code(401).send({error:"authentication_required"});return false;}
  const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion)){reply.code(401).send({error:"authentication_required"});return false;}
  if(!allow.has(c.sub)){reply.code(403).send({error:"payment_review_admin_required"});return false;}
  const q=await pool.query("SELECT 1 FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=$1 AND p.id=$2 AND a.status='active' AND a.token_version=$3",[c.sub,c.playerId,c.tokenVersion]);
  if(!q.rowCount){reply.code(401).send({error:"authentication_required"});return false;}return c;
 }
 return async app=>{
  app.addHook("onSend",async(_req,reply,payload)=>{reply.header("Cache-Control","no-store");return payload;});
  app.get("/dashboard",async(_req,reply)=>reply.type("text/html; charset=utf-8").header("Content-Security-Policy","default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'").send(paymentReviewHtml));
  app.get("/reviews",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
   if(!await authorize(req,reply))return;
   const input=filter.safeParse(req.query);if(!input.success)return reply.code(400).send({error:"invalid_filter"});
   const {status,limit,before,beforeId}=input.data;
   const q=await pool.query(`SELECT o.id,o.player_id,o.package_id,o.stones,o.amount_cents,o.refunded_cents,o.dispute_seen,o.review_reason,o.status,o.created_at,o.credited_at,o.updated_at,to_char(o.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS cursor_time,COALESCE(c.balance,0)::text AS wallet_balance,(SELECT count(*)::int FROM currency_ledger l WHERE l.player_id=o.player_id AND l.ref_id=o.id::text AND l.reason='stripe_sandbox_purchase') AS purchase_entries,(SELECT count(*)::int FROM currency_ledger l WHERE l.player_id=o.player_id AND l.ref_id=o.id::text AND l.reason='stripe_sandbox_refund') AS reversal_entries FROM stripe_sandbox_orders o LEFT JOIN player_currencies c ON c.player_id=o.player_id AND c.currency_id='paid_moonstones' WHERE o.status=$1 AND ($2::timestamptz IS NULL OR (o.created_at,o.id)<($2::timestamptz,$3::uuid)) ORDER BY o.created_at DESC,o.id DESC LIMIT $4`,[status,before??null,beforeId??null,limit+1]);
   const rows=q.rows.slice(0,limit),last=rows.at(-1);
   const history=rows.length?(await pool.query("SELECT id,order_id,evidence_key,action,note,actor_account_id,created_at FROM stripe_sandbox_review_decisions WHERE order_id=ANY($1::uuid[]) ORDER BY created_at DESC,id DESC",[rows.map(r=>r.id)])).rows:[];
   const reviews=rows.map(r=>{const key=evidenceKey(r),decisions=history.filter(d=>d.order_id===r.id);return {...r,evidenceKey:key,currentDecision:decisions.find(d=>d.evidence_key===key)??null,decisions};});
   return {testMode:true,readOnly:true,decisionLogging:true,reviews,nextCursor:q.rows.length>limit&&last?{before:last.cursor_time,beforeId:last.id}:null};
  });
  app.post("/decisions",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(req,reply)=>{
   const c=await authorize(req,reply);if(!c)return;
   const parsed=decisionInput.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_decision"});
   const {orderId,requestId,evidenceKey:key,action,note}=parsed.data;const db=await pool.connect();
   try{await db.query("BEGIN");const fail=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error});};
    const admin=(await db.query("SELECT status,token_version FROM accounts WHERE id=$1 FOR UPDATE",[c.sub])).rows[0];if(admin?.status!=="active"||admin.token_version!==c.tokenVersion)return await fail(401,"authentication_required");
    const order=(await db.query("SELECT o.*,p.account_id FROM stripe_sandbox_orders o JOIN players p ON p.id=o.player_id WHERE o.id=$1 FOR UPDATE OF o",[orderId])).rows[0];if(!order)return await fail(404,"order_not_found");if(order.account_id===c.sub)return await fail(403,"self_review_forbidden");
    const prior=(await db.query("SELECT * FROM stripe_sandbox_review_decisions WHERE actor_account_id=$1 AND request_id=$2",[c.sub,requestId])).rows[0];
    if(prior){if(prior.order_id!==orderId||prior.evidence_key!==key||prior.action!==action||prior.note!==note)return await fail(409,"request_id_conflict");await db.query("COMMIT");return {testMode:true,decision:prior,replayed:true};}
    if(order.status!=="refund_review"||evidenceKey(order)!==key)return await fail(409,"review_evidence_changed_refresh");
    if((await db.query("SELECT 1 FROM stripe_sandbox_review_decisions WHERE order_id=$1 AND evidence_key=$2",[orderId,key])).rowCount)return await fail(409,"evidence_already_reviewed");
    const saved=(await db.query("INSERT INTO stripe_sandbox_review_decisions(order_id,actor_account_id,request_id,evidence_key,evidence,action,note) VALUES($1,$2,$3,$4,$5::jsonb,$6,$7) RETURNING *",[orderId,c.sub,requestId,key,JSON.stringify(evidence(order)),action,note])).rows[0];
    await db.query("COMMIT");return {testMode:true,decision:saved,replayed:false};
   }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
  });
 };
}
// Dedicated, fail-closed allowlist. No implicit grant from general developer access.
export const paymentReviewRoutes=makePaymentReviewRoutes(config.NODE_ENV==="development"&&config.HOST==="127.0.0.1"&&['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname)?process.env.PAYMENT_REVIEW_ADMIN_ACCOUNT_IDS??"":"");
