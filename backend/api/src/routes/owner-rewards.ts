import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {z} from "zod";
import {pool} from "../db.js";
import {staffOwners} from "./staff.js";
const uuid=z.string().uuid();
const claims=z.object({sub:uuid,playerId:uuid,tokenVersion:z.number().int().nonnegative()});
const grant=z.object({requestId:uuid,targetId:uuid,currency:z.enum(["gems","crystals","paid_moonstones","gold"]),amount:z.number().int().min(1).max(1000000),note:z.string().trim().min(8).max(300)}).strict();
export function ownerRewardRoutes(owners=staffOwners):FastifyPluginAsync{
 async function authorize(req:FastifyRequest,reply:FastifyReply){
  try{await req.jwtVerify()}catch{reply.code(401).send({error:"authentication_required"});return null}
  const c=claims.safeParse(req.user);
  if(!c.success){reply.code(401).send({error:"authentication_required"});return null}
  if(!owners.has(c.data.sub)){reply.code(403).send({error:"owner_required"});return null}
  const q=await pool.query("SELECT 1 FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=$1 AND p.id=$2 AND a.status='active' AND a.token_version=$3",[c.data.sub,c.data.playerId,c.data.tokenVersion]);
  if(!q.rowCount){reply.code(401).send({error:"session_revoked"});return null}
  return c.data;
 }
 return async app=>{
  app.addHook("onSend",async(_req,reply,payload)=>{reply.header("Cache-Control","no-store");return payload});
  app.get("/players",{config:{rateLimit:{max:20,timeWindow:"1 minute"}}},async(req,reply)=>{
   if(!await authorize(req,reply))return;
   const q=z.object({q:z.string().trim().min(3).max(32)}).strict().safeParse(req.query);
   if(!q.success)return reply.code(400).send({error:"invalid_search"});
   const rows=await pool.query(`SELECT p.id,p.name,a.status,COALESCE((SELECT jsonb_object_agg(currency_id,balance::text) FROM player_currencies WHERE player_id=p.id AND currency_id IN ('gold','gems','crystals','paid_moonstones')),'{}'::jsonb) AS balances FROM players p JOIN accounts a ON a.id=p.account_id WHERE left(lower(p.name),length($1))=lower($1) ORDER BY (lower(p.name)=lower($1)) DESC,lower(p.name),p.id LIMIT 21`,[q.data.q]);
   return {players:rows.rows.slice(0,20),more:rows.rows.length>20};
  });
  app.get("/history",{config:{rateLimit:{max:20,timeWindow:"1 minute"}}},async(req,reply)=>{
   if(!await authorize(req,reply))return;
   const q=z.object({before:uuid.optional()}).strict().safeParse(req.query);
   if(!q.success)return reply.code(400).send({error:"invalid_cursor"});
   const rows=await pool.query(`SELECT request_id,actor_name,target_name,currency_id,amount::text,balance_after::text,note,created_at FROM reverie_currency_grants WHERE ($1::uuid IS NULL OR (created_at,request_id)<(SELECT created_at,request_id FROM reverie_currency_grants WHERE request_id=$1)) ORDER BY created_at DESC,request_id DESC LIMIT 51`,[q.data.before??null]);
   return {grants:rows.rows.slice(0,50),next:rows.rows.length>50?rows.rows[49]!.request_id:null};
  });
  app.post("/grant",{config:{rateLimit:{max:6,timeWindow:"1 minute"}}},async(req,reply)=>{
   const c=await authorize(req,reply);if(!c)return;
   const parsed=grant.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_grant"});
   const g=parsed.data,db=await pool.connect();
   try{
    await db.query("BEGIN");
    const fail=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error})};
    // Serialize all owner grants, including retries with a different recipient.
    await db.query("SELECT pg_advisory_xact_lock(568923413)");
    const target=(await db.query("SELECT p.account_id,p.name FROM players p WHERE p.id=$1",[g.targetId])).rows[0];
    if(!target)return await fail(404,"player_not_found");
    const locks=await db.query("SELECT id,status,token_version FROM accounts WHERE id=ANY($1::uuid[]) ORDER BY id FOR UPDATE",[[c.sub,target.account_id]]);
    const actor=locks.rows.find(r=>r.id===c.sub),recipient=locks.rows.find(r=>r.id===target.account_id);
    if(actor?.status!=="active"||actor.token_version!==c.tokenVersion)return await fail(401,"session_revoked");
    const existing=(await db.query("SELECT * FROM reverie_currency_grants WHERE request_id=$1",[g.requestId])).rows[0];
    if(existing){
     if(existing.actor_account_id!==c.sub||existing.target_player_id!==g.targetId||existing.currency_id!==g.currency||Number(existing.amount)!==g.amount||existing.note!==g.note)return await fail(409,"grant_request_conflict");
     await db.query("COMMIT");return {requestId:g.requestId,target:existing.target_name,currency:g.currency,amount:g.amount,balanceAfter:existing.balance_after,replayed:true};
    }
    if(recipient?.status!=="active")return await fail(409,"recipient_unavailable");
    const players=await db.query("SELECT id,name,account_id FROM players WHERE id=ANY($1::uuid[]) ORDER BY id FOR UPDATE",[[c.playerId,g.targetId]]);
    const current=players.rows.find(r=>r.id===g.targetId),admin=players.rows.find(r=>r.id===c.playerId);
    if(!current||current.account_id!==target.account_id||!admin||admin.account_id!==c.sub)return await fail(409,"player_changed");
    const balance=(await db.query("UPDATE player_currencies SET balance=balance+$3::bigint,updated_at=now() WHERE player_id=$1 AND currency_id=$2 AND balance<=9007199254740991-$3::bigint RETURNING balance::text",[g.targetId,g.currency,g.amount])).rows[0];
    if(!balance)return await fail(409,"wallet_unavailable_or_limit");
    await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'owner_admin_grant','owner_grant',$5,$6)",[g.targetId,g.currency,g.amount,balance.balance,g.requestId,"owner-grant:"+g.requestId]);
    await db.query("INSERT INTO reverie_currency_grants(request_id,actor_account_id,actor_name,target_player_id,target_name,currency_id,amount,balance_after,note) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)",[g.requestId,c.sub,admin.name,g.targetId,current.name,g.currency,g.amount,balance.balance,g.note]);
    await db.query("COMMIT");return {requestId:g.requestId,target:current.name,currency:g.currency,amount:g.amount,balanceAfter:balance.balance,replayed:false};
   }catch(e){await db.query("ROLLBACK");throw e}finally{db.release()}
  });
 }
}