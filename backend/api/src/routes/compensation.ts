import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {z} from "zod";
import {pool} from "../db.js";
import {config} from "../config.js";
import {compensationDashboardHtml} from "./compensation-dashboard.js";
import {auditPaidGuarantees} from "../world/paid-guarantee-audit.js";
import {banners,contentId,contentHash} from "../world/summon.js";
import {grantPaidCompensation} from "../world/paid-compensation-grant.js";

const uuid=z.string().uuid();
type Claims={sub?:string;playerId?:string;tokenVersion?:number};
const decision=z.object({pullId:uuid,rollIndex:z.number().int().min(0).max(9),action:z.enum(["approve","reject"]),note:z.string().trim().min(8).max(500)}).strict();
function targetFor(row:any):string|null{
 // Do not guess old banner contents. A matching immutable hash is required.
 if(row.content_version_id!==contentId||row.manifest_hash!==contentHash)return null;
 const banner=banners[row.banner_id];if(!banner||banner.featured.length!==1)return null;
 const id=banner.featured[0]!;
 if(!banner.pool.legendary.includes(id)&&!banner.pool.mythic.includes(id))return null;
 return id;
}
export function makeCompensationRoutes(accountIds:string):FastifyPluginAsync{
 const allowed=new Set(accountIds.split(",").map(v=>v.trim()).filter(v=>uuid.safeParse(v).success));
 async function authorize(req:FastifyRequest,reply:FastifyReply){
  try{await req.jwtVerify();}catch{reply.code(401).send({error:"authentication_required"});return null;}
  const c=req.user as Claims;
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion)){reply.code(401).send({error:"authentication_required"});return null;}
  if(!allowed.has(c.sub)){reply.code(403).send({error:"compensation_admin_required"});return null;}
  const q=await pool.query("SELECT 1 FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=$1 AND p.id=$2 AND a.status='active' AND a.token_version=$3",[c.sub,c.playerId,c.tokenVersion]);
  if(!q.rowCount){reply.code(401).send({error:"authentication_required"});return null;}return c;
 }
 return async app=>{
  app.addHook("onSend",async(_req,reply,payload)=>{reply.header("Cache-Control","no-store");return payload;});
  app.get("/dashboard",async(_req,reply)=>reply.type("text/html; charset=utf-8").header("Content-Security-Policy","default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'").send(compensationDashboardHtml));
  app.get("/reviews",{config:{rateLimit:{max:20,timeWindow:"1 minute"}}},async(req,reply)=>{
   const c=await authorize(req,reply);if(!c)return;
   const filters=z.object({status:z.enum(["pending_review","resolved","rejected"]).default("pending_review")}).strict().safeParse(req.query);
   if(!filters.success)return reply.code(400).send({error:"invalid_filter"});
   const q=await pool.query(`SELECT v.*,p.player_id,p.banner_id,p.content_version_id,cv.manifest_hash,r.character_id AS recorded_character,r.featured AS recorded_featured FROM paid_guarantee_reviews v JOIN gacha_pulls p ON p.id=v.pull_id JOIN content_versions cv ON cv.id=p.content_version_id JOIN gacha_pull_results r ON r.pull_id=v.pull_id AND r.roll_index=v.roll_index WHERE v.status=$1 ORDER BY v.requested_at,v.pull_id,v.roll_index LIMIT 100`,[filters.data.status]);
   return {reviews:q.rows.map(row=>({...row,suggestedCharacter:targetFor(row)}))};
  });
  app.post("/decide",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(req,reply)=>{
   const c=await authorize(req,reply);if(!c)return;
   const body=decision.safeParse(req.body);if(!body.success)return reply.code(400).send({error:"invalid_decision"});
   const {pullId,rollIndex,action,note}=body.data;const db=await pool.connect();
   try{
    await db.query("BEGIN");
    const fail=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error});};
    const found=(await db.query("SELECT p.player_id,pl.account_id FROM gacha_pulls p JOIN players pl ON pl.id=p.player_id WHERE p.id=$1 AND p.currency_id='paid_moonstones'",[pullId])).rows[0];
    if(!found)return await fail(404,"review_not_found");
    if(found.account_id===c.sub)return await fail(403,"self_approval_forbidden");
    // Match summon lock order: accounts, then player, then review.
    const locks=await db.query("SELECT id,status,token_version FROM accounts WHERE id=ANY($1::uuid[]) ORDER BY id FOR UPDATE",[[c.sub,found.account_id]]);
    const admin=locks.rows.find(r=>r.id===c.sub),recipient=locks.rows.find(r=>r.id===found.account_id);
    if(admin?.status!=="active"||admin.token_version!==c.tokenVersion)return await fail(401,"authentication_required");
    if(recipient?.status!=="active")return await fail(409,"recipient_unavailable");
    if(!(await db.query("SELECT 1 FROM players WHERE id=$1 AND account_id=$2 FOR UPDATE",[found.player_id,found.account_id])).rowCount)return await fail(404,"review_not_found");
    const row=(await db.query(`SELECT v.*,p.banner_id,p.content_version_id,cv.manifest_hash,r.character_id AS recorded_character,r.reward_kind FROM paid_guarantee_reviews v JOIN gacha_pulls p ON p.id=v.pull_id JOIN content_versions cv ON cv.id=p.content_version_id JOIN gacha_pull_results r ON r.pull_id=v.pull_id AND r.roll_index=v.roll_index WHERE v.pull_id=$1 AND v.roll_index=$2 FOR UPDATE OF v`,[pullId,rollIndex])).rows[0];
    if(!row)return await fail(404,"review_not_found");
    const expectedStatus=action==="approve"?"resolved":"rejected";
    if(row.status!=="pending_review"){
     if(row.status!==expectedStatus)return await fail(409,"review_already_decided");
     await db.query("COMMIT");return {status:row.status,grantedCharacter:row.granted_character_id,details:row.grant_details,replayed:true};
    }
    let character:string|null=null,details:unknown=null;
    if(action==="approve"){
     const report=await auditPaidGuarantees(db,found.player_id);
     const issue=report.cases.find(r=>r.pullId===pullId&&r.rollIndex===rollIndex);
     if(!report.historyComplete||!issue||issue.status!=="missed_featured"||issue.milestone===null)return await fail(409,"insufficient_verified_evidence");
     character=targetFor(row);
     if(!character)return await fail(409,"historical_banner_not_verified");
     if(row.recorded_character===character&&row.reward_kind==="character")return await fail(409,"featured_character_already_recorded");
     details=await grantPaidCompensation(db,found.player_id,character,pullId+":"+rollIndex);
    }
    const saved=(await db.query("UPDATE paid_guarantee_reviews SET status=$3,decided_at=now(),decided_by=$4,decision_note=$5,granted_character_id=$6,grant_details=$7::jsonb WHERE pull_id=$1 AND roll_index=$2 RETURNING status,granted_character_id,grant_details",[pullId,rollIndex,expectedStatus,c.sub,note,character,JSON.stringify(details)])).rows[0];
    await db.query("COMMIT");return {status:saved.status,grantedCharacter:saved.granted_character_id,details:saved.grant_details,replayed:false};
   }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
  });
 };
}
export const compensationRoutes=makeCompensationRoutes(config.COMPENSATION_ADMIN_ACCOUNT_IDS);
