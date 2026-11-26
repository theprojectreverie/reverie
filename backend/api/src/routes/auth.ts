import type {FastifyPluginAsync} from "fastify";
import argon2 from "argon2";
import {createHash,randomBytes} from "node:crypto";
import {z} from "zod";
import {pool} from "../db.js";
import {ownedProfilePicture} from "./social.js";
import {config,localDevelopmentRegistration} from "../config.js";

const registerBody=z.object({email:z.string().trim().email().max(254),password:z.string().min(localDevelopmentRegistration ? 8 : 12).max(128),playerName:z.string().trim().min(3).max(20).regex(/^[A-Za-z0-9_]+$/)});
const loginBody=z.object({playerName:z.string().trim().min(3).max(20).regex(/^[A-Za-z0-9_]+$/).optional(),email:z.string().trim().email().max(254).optional(),password:z.string().min(1).max(128)}).refine(v=>Boolean(v.playerName || v.email));
const verifyBody=z.object({token:z.string().min(32).max(200)});
const refreshBody=z.object({refreshToken:z.string().min(32).max(200)});
type AccountRow={id:string;status:string;password_hash:string;player_id:string;player_name:string;avatar?:string;token_version:number};
const hashToken=(value:string)=>createHash("sha256").update(value).digest("hex");
const newToken=()=>randomBytes(48).toString("base64url");
const issueAccess=(app:any,row:AccountRow)=>app.jwt.sign({sub:row.id,playerId:row.player_id,playerName:row.player_name,tokenVersion:row.token_version});

export const authRoutes:FastifyPluginAsync=async app=>{
 app.addHook("onSend",async(req,reply,payload)=>{
  reply.header("Cache-Control","no-store, max-age=0");
  reply.header("Pragma","no-cache");
  return payload;
 });
 app.get("/wallet",async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
  const claims=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!claims.sub||!claims.playerId||!Number.isInteger(claims.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const q=await pool.query(`SELECT p.id,p.xp::text,COALESCE((SELECT balance FROM player_currencies WHERE player_id=p.id AND currency_id='gold'),0)::text AS gold,
   COALESCE((SELECT jsonb_object_agg(item_id,quantity::text) FROM inventory_items WHERE player_id=p.id AND quantity>0),'{}'::jsonb) AS items,
   COALESCE((SELECT jsonb_object_agg(currency_id,balance::text) FROM player_currencies WHERE player_id=p.id),'{}'::jsonb) AS currencies
   FROM players p JOIN accounts a ON a.id=p.account_id WHERE a.id=$1 AND p.id=$2 AND a.status='active' AND a.token_version=$3`,[claims.sub,claims.playerId,claims.tokenVersion]);
  if(!q.rows[0])return reply.code(401).send({error:"session_revoked"});
  return {playerId:q.rows[0].id,gold:q.rows[0].gold,xp:q.rows[0].xp,currencies:q.rows[0].currencies,items:q.rows[0].items};
 });
 app.post("/register",{config:{rateLimit:{max:5,timeWindow:"1 hour"}}},async(req,reply)=>{
  const parsed=registerBody.safeParse(req.body);
  if(!parsed.success)return reply.code(400).send({error:"invalid_registration",details:parsed.error.issues.map(i=>({field:i.path.join("."),message:i.message}))});
  const email=parsed.data.email.toLowerCase();
  const passwordHash=await argon2.hash(parsed.data.password,{type:argon2.argon2id,memoryCost:19456,timeCost:2,parallelism:1});
  const verifyToken=newToken();const client=await pool.connect();
  try{
   await client.query("BEGIN");
   const a=await client.query<{id:string}>("INSERT INTO accounts(email,password_hash,email_verified) VALUES($1,$2,false) RETURNING id",[email,passwordHash]);
   const p=await client.query<{id:string}>("INSERT INTO players(account_id,name) VALUES($1,$2) RETURNING id",[a.rows[0]!.id,parsed.data.playerName]);
   await client.query("INSERT INTO player_currencies(player_id,currency_id,balance) SELECT $1,id,0 FROM currencies ON CONFLICT DO NOTHING",[p.rows[0]!.id]);
   if(!localDevelopmentRegistration) await client.query("INSERT INTO email_verification_tokens(account_id,token_hash,expires_at) VALUES($1,$2,now()+interval '24 hours')",[a.rows[0]!.id,hashToken(verifyToken)]);
   await client.query("COMMIT");
   if(localDevelopmentRegistration)return reply.code(201).send({status:"account_created",message:"Account created. You can now sign in."});
   const response:Record<string,unknown>={status:"verification_required",message:"Account created. Verify the email address to activate login."};
   if(config.NODE_ENV==="development")response.developmentVerificationToken=verifyToken;
   return reply.code(201).send(response);
  }catch(e){
   await client.query("ROLLBACK");const pe=e as {code?:string;constraint?:string};
   if(pe.code==="23505")return reply.code(409).send({error:pe.constraint?.includes("email")?"email_unavailable":"player_name_unavailable"});
   req.log.error(e);return reply.code(500).send({error:"registration_failed"});
  }finally{client.release();}
 });

 app.post("/verify-email",{config:{rateLimit:{max:10,timeWindow:"15 minutes"}}},async(req,reply)=>{
  const parsed=verifyBody.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_verification_token"});
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   const q=await client.query<{id:string;account_id:string}>("SELECT id,account_id FROM email_verification_tokens WHERE token_hash=$1 AND consumed_at IS NULL AND expires_at>now() FOR UPDATE",[hashToken(parsed.data.token)]);
   const row=q.rows[0];if(!row){await client.query("ROLLBACK");return reply.code(400).send({error:"invalid_or_expired_token"});}
   await client.query("UPDATE accounts SET email_verified=true WHERE id=$1",[row.account_id]);
   await client.query("UPDATE email_verification_tokens SET consumed_at=now() WHERE account_id=$1 AND consumed_at IS NULL",[row.account_id]);
   await client.query("COMMIT");return{status:"verified"};
  }catch(e){await client.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"verification_failed"});}
  finally{client.release();}
 });

 app.post("/login",{config:{rateLimit:{max:8,timeWindow:"15 minutes"}}},async(req,reply)=>{
  const parsed=loginBody.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_credentials"});
  const q=await pool.query<AccountRow>("SELECT a.id,a.status,a.password_hash,a.token_version,p.id AS player_id,p.name AS player_name,p.settings->>'profile_picture' AS avatar FROM accounts a JOIN players p ON p.account_id=a.id WHERE (CASE WHEN $2::boolean THEN lower(p.name)=lower($1) ELSE lower(a.email)=lower($1) END) LIMIT 2",[parsed.data.playerName ?? parsed.data.email,Boolean(parsed.data.playerName)]);
  const row=q.rows.length===1?q.rows[0]:undefined;const valid=row?await argon2.verify(row.password_hash,parsed.data.password).catch(()=>false):false;
  if(!row||!valid||row.status!=="active")return reply.code(401).send({error:"invalid_credentials"});
  const verified=await pool.query<{email_verified:boolean}>("SELECT email_verified FROM accounts WHERE id=$1",[row.id]);
  if(!localDevelopmentRegistration && !verified.rows[0]?.email_verified)return reply.code(403).send({error:"email_verification_required"});
  const refreshToken=newToken();
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   const locked=await client.query<{status:string;token_version:number}>("SELECT status,token_version FROM accounts WHERE id=$1 FOR UPDATE",[row.id]);
   if(locked.rows[0]?.status!=="active"){
    await client.query("ROLLBACK");
    return reply.code(401).send({error:"invalid_credentials"});
   }
   await client.query(
    "UPDATE account_sessions SET revoked_at=now() WHERE id IN (SELECT id FROM account_sessions WHERE account_id=$1 AND revoked_at IS NULL AND expires_at>now() ORDER BY created_at DESC,id DESC OFFSET 4)",
    [row.id]);
   await client.query("INSERT INTO account_sessions(account_id,refresh_token_hash,expires_at) VALUES($1,$2,now()+interval '30 days')",[row.id,hashToken(refreshToken)]);
   row.token_version=locked.rows[0]!.token_version;
   await client.query("UPDATE accounts SET last_login_at=now() WHERE id=$1",[row.id]);
   await client.query("COMMIT");
  }catch(e){await client.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"login_failed"});}
  finally{client.release();}
  return{accessToken:issueAccess(app,row),refreshToken,tokenType:"Bearer",expiresIn:config.ACCESS_TOKEN_TTL_SECONDS,player:{id:row.player_id,name:row.player_name,avatar:await ownedProfilePicture(row.player_id,row.avatar)}};
 });

 app.post("/refresh",{config:{rateLimit:{max:20,timeWindow:"15 minutes"}}},async(req,reply)=>{
  const parsed=refreshBody.safeParse(req.body);if(!parsed.success)return reply.code(401).send({error:"invalid_session"});
  const client=await pool.connect();const nextToken=newToken();
  try{
   await client.query("BEGIN");
   // Lock in the same order as logout-all (account, then session) to avoid
   // refresh/sign-out deadlocks and prevent a refresh from escaping sign-out.
   const tokenHash=hashToken(parsed.data.refreshToken);
   const owner=await client.query<{account_id:string}>(
    "SELECT account_id FROM account_sessions WHERE refresh_token_hash=$1 AND revoked_at IS NULL AND expires_at>now()",
    [tokenHash]);
   const accountId=owner.rows[0]?.account_id;
   if(!accountId){await client.query("ROLLBACK");return reply.code(401).send({error:"invalid_session"});}
   const account=await client.query<{status:string;token_version:number}>(
    "SELECT status,token_version FROM accounts WHERE id=$1 FOR UPDATE",[accountId]);
   const q=await client.query<AccountRow & {session_id:string}>(
    "SELECT s.id AS session_id,a.id,a.status,a.password_hash,a.token_version,p.id AS player_id,p.name AS player_name,p.settings->>'profile_picture' AS avatar FROM account_sessions s JOIN accounts a ON a.id=s.account_id JOIN players p ON p.account_id=a.id WHERE s.refresh_token_hash=$1 AND s.account_id=$2 AND s.revoked_at IS NULL AND s.expires_at>now() FOR UPDATE OF s",
    [tokenHash,accountId]);
   const row=q.rows[0];
   if(!row||account.rows[0]?.status!=="active"||row.status!=="active"){
    await client.query("ROLLBACK");return reply.code(401).send({error:"invalid_session"});
   }
   row.token_version=account.rows[0]!.token_version;
   await client.query("UPDATE account_sessions SET revoked_at=now(),last_used_at=now() WHERE id=$1",[row.session_id]);
   await client.query("INSERT INTO account_sessions(account_id,refresh_token_hash,expires_at) VALUES($1,$2,now()+interval '30 days')",[row.id,hashToken(nextToken)]);
   await client.query("COMMIT");
   return{accessToken:issueAccess(app,row),refreshToken:nextToken,tokenType:"Bearer",expiresIn:config.ACCESS_TOKEN_TTL_SECONDS,player:{id:row.player_id,name:row.player_name,avatar:await ownedProfilePicture(row.player_id,row.avatar)}};
  }catch(e){await client.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"session_refresh_failed"});}
  finally{client.release();}
 });

 app.post("/logout",{config:{rateLimit:{max:20,timeWindow:"15 minutes"}}},async(req,reply)=>{
  const parsed=refreshBody.safeParse(req.body);if(!parsed.success)return reply.code(204).send();
  await pool.query("UPDATE account_sessions SET revoked_at=now() WHERE refresh_token_hash=$1 AND revoked_at IS NULL",[hashToken(parsed.data.refreshToken)]);
  return reply.code(204).send();
 });

 // Revoke every refresh session after an authenticated account-wide sign-out.
 app.post("/logout-all",{config:{rateLimit:{max:5,timeWindow:"15 minutes"}}},async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
  const claims=req.user as {sub?:string;tokenVersion?:number};
  const accountId=claims.sub;
  if(!accountId||!Number.isInteger(claims.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   // Only a token from the current account version may revoke other sessions.
   const bumped=await client.query("UPDATE accounts SET token_version=token_version+1 WHERE id=$1 AND status='active' AND token_version=$2 RETURNING id",[accountId,claims.tokenVersion]);
   if(!bumped.rowCount){await client.query("ROLLBACK");return reply.code(401).send({error:"authentication_required"});}
   await client.query("UPDATE account_sessions SET revoked_at=now() WHERE account_id=$1 AND revoked_at IS NULL",[accountId]);
   await client.query("COMMIT");
  }catch(e){await client.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"logout_all_failed"});}
  finally{client.release();}
  return reply.code(204).send();
 });
};
