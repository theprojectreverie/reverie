import type {FastifyPluginAsync,FastifyReply,FastifyRequest} from "fastify";
import {z} from "zod";
import {pool} from "../db.js";

type Claims={sub?:string;playerId?:string;tokenVersion?:number};
type Queryable={query:(sql:string,values?:unknown[])=>Promise<{rows:Array<Record<string,unknown>>}>};
type RouteOptions={database:Queryable};
const bodySchema=z.object({milestoneId:z.enum(["village","royal_gardens","royal_gate","willow_fields","elderwood_grove","forsaken_ruins","ruined_tower","chapter_complete"])}).strict();

export function createStoryProgressionRoutes({database}:RouteOptions):FastifyPluginAsync{
 return async app=>{
  app.addHook("onSend",async(_request,reply,payload)=>{reply.header("Cache-Control","no-store");return payload;});
  app.post("/milestones",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(request:FastifyRequest,reply:FastifyReply)=>{
   let claims:Claims;
   try{await request.jwtVerify();claims=request.user as Claims;}catch{return reply.code(401).send({error:"authentication_required"});}
   if(!claims.sub||!claims.playerId||!Number.isInteger(claims.tokenVersion))return reply.code(401).send({error:"authentication_required"});
   const parsed=bodySchema.safeParse(request.body);
   if(!parsed.success)return reply.code(400).send({error:"invalid_milestone"});
   const result=await database.query(
    `WITH current_player AS MATERIALIZED (
      SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id
      WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3
     ), inserted AS (
      INSERT INTO story_milestone_reaches(player_id,milestone_id)
      SELECT id,$4 FROM current_player
      ON CONFLICT(player_id,milestone_id) DO NOTHING
      RETURNING milestone_id
     )
     SELECT EXISTS(SELECT 1 FROM current_player) AS authorized,
       EXISTS(SELECT 1 FROM inserted) AS recorded`,
    [claims.playerId,claims.sub,claims.tokenVersion,parsed.data.milestoneId]);
   const row=result.rows[0];
   if(row?.authorized!==true)return reply.code(401).send({error:"session_revoked"});
   return reply.code(200).send({milestoneId:parsed.data.milestoneId,recorded:row.recorded===true});
  });
 };
}

export const storyProgressionRoutes=createStoryProgressionRoutes({database:{query:(sql,values)=>pool.query(sql,values)}});
