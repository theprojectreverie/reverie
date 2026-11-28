import type {FastifyInstance,FastifyRequest} from "fastify";
import {pool} from "../db.js";
import {config} from "../config.js";
import {z} from "zod";
const claims=z.object({sub:z.string().uuid(),playerId:z.string().uuid(),tokenVersion:z.number().int().nonnegative()});
const publicAuth=new Set(["POST /v1/auth/register","POST /v1/auth/login","POST /v1/auth/refresh","POST /v1/auth/logout","POST /v1/auth/suspension-appeal"]);
export function alphaRateKey(app:FastifyInstance,req:FastifyRequest):string{
 if(req.headers["x-reverie-alpha"]!=="1")return req.ip;
 try{
  const raw=req.headers.authorization;
  if(raw?.startsWith("Bearer ")){
   const c=claims.safeParse(app.jwt.verify(raw.slice(7)));
   if(c.success)return "alpha-account:"+c.data.sub;
  }
 }catch{}
 return "alpha-anonymous";
}
/** The login hook runs after body parsing. Keep the per-identity limit while
 * the public gateway separately bounds aggregate traffic. Never trust a
 * caller-supplied forwarded IP or use passwords as quota keys. */
export function alphaLoginRateKey(app:FastifyInstance,req:FastifyRequest):string{
 if(req.headers["x-reverie-alpha"]!=="1")return req.ip;
 const b=z.object({playerName:z.string().trim().min(3).max(20).regex(/^[A-Za-z0-9_]+$/).optional(),email:z.string().trim().email().max(254).optional()}).safeParse(req.body);
 if(b.success){
  if(b.data.playerName)return "alpha-login:name:"+b.data.playerName.toLowerCase();
  if(b.data.email)return "alpha-login:email:"+b.data.email.toLowerCase();
 }
 return alphaRateKey(app,req);
}
export function installAlphaAccess(app:FastifyInstance){
 app.addHook("onRequest",async(req,reply)=>{
  if(req.headers["x-reverie-alpha"]!=="1"||publicAuth.has(req.method+" "+req.url.split("?")[0]))return;
  let c;
  try{await req.jwtVerify();c=claims.safeParse(req.user)}catch{return reply.code(401).send({error:"authentication_required"})}
  if(!c.success)return reply.code(401).send({error:"authentication_required"});
  const q=await pool.query("SELECT 1 FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=$1 AND p.id=$2 AND a.status='active' AND a.token_version=$3 AND ($4::boolean OR EXISTS(SELECT 1 FROM reverie_alpha_invites i WHERE i.used_by=a.id AND i.used_at IS NOT NULL))",[c.data.sub,c.data.playerId,c.data.tokenVersion,config.REVERIE_ALPHA_REGISTRATION_MODE==="open"]);
  if(!q.rowCount)return reply.code(403).send({error:"alpha_access_required"});
 });
}