import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {createHash,randomBytes} from "node:crypto";
import {readFileSync} from "node:fs";
import {pool} from "../db.js";
import {z} from "zod";
import {expirePlayerMatches} from "../world/pvp-expiry.js";
import {guildPartyPower,guildPowerCompatible,GUILD_DUEL_REMATCH_MINUTES} from "../world/guild-duel-policy.js";
import {liveDefinitions} from "../world/live-character-packs.js";
import {retiredPlayableIds} from "../world/summon.js";
import {buildPvpRoster,createInitialPvpState,type OwnedPvpCharacter,type PvpRosterContent} from "../world/pvp-roster.js";

type Claims={playerId?:string;sub?:string;tokenVersion?:number};
type PartyRow=OwnedPvpCharacter & {slot:number};
const contentFile=(name:string)=>JSON.parse(readFileSync(new URL("../../../../resources/data/"+name+".json",import.meta.url),"utf8")) as Record<string,Record<string,unknown>>;
const rosterContent:PvpRosterContent={
 characters:contentFile("characters"),skills:contentFile("skills"),items:contentFile("items")
};
async function playerFromRequest(req:FastifyRequest,reply:FastifyReply):Promise<string|null>{
 try{await req.jwtVerify();const claims=req.user as Claims;if(claims.playerId&&claims.sub&&Number.isInteger(claims.tokenVersion)){const current=await pool.query<{token_version:number;status:string}>("SELECT a.token_version,a.status FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=$1 AND p.id=$2",[claims.sub,claims.playerId]);if(current.rows[0]?.status==="active"&&current.rows[0].token_version===claims.tokenVersion)return claims.playerId;}}
 catch{/* rejected below */}
 reply.code(401).send({error:"authentication_required"});return null;
}
async function loadPlayerRoster(client: import("pg").PoolClient,playerId:string,team:1|2){
 const party=await client.query<PartyRow>(
  "SELECT oc.id,oc.char_id,oc.level,oc.ascension,oc.awakening,oc.bond,oc.dupes,oc.skill_levels,pm.slot FROM party_members pm JOIN owned_characters oc ON oc.id=pm.character_id AND oc.player_id=pm.player_id WHERE pm.player_id=$1 AND NOT(oc.char_id=ANY($2::text[])) ORDER BY pm.slot FOR UPDATE OF pm,oc",
  [playerId,retiredPlayableIds]);
 if(party.rows.length<1||party.rows.length>4)return {ok:false as const,reason:"party_required"};
 const ids=party.rows.map(row=>row.id);
 const equipment=await client.query<{character_id:string;slot:string;item_id:string;enhancement_level:number;reroll_stat:string|null;reroll_value:string|null}>(
  "SELECT character_id,slot,item_id,enhancement_level,reroll_stat,reroll_value FROM character_equipment WHERE player_id=$1 AND character_id=ANY($2::uuid[]) ORDER BY character_id,slot FOR UPDATE",
  [playerId,ids]);
 const byCharacter=new Map<string,OwnedPvpCharacter["equipment"]>();
 for(const row of equipment.rows){
  const list=byCharacter.get(row.character_id)??[];
  list.push({slot:row.slot,item_id:row.item_id,enhancement_level:row.enhancement_level,reroll_stat:row.reroll_stat,reroll_value:row.reroll_value===null?undefined:Number(row.reroll_value)});
  byCharacter.set(row.character_id,list);
 }
 const owned:OwnedPvpCharacter[]=party.rows.map(row=>({...row,equipment:byCharacter.get(row.id)??[]}));
 const count=await client.query<{count:string}>("SELECT count(DISTINCT char_id)::text AS count FROM owned_characters WHERE player_id=$1 AND NOT(char_id=ANY($2::text[]))",[playerId,retiredPlayableIds]);
 const roster=buildPvpRoster(playerId,team,owned,{...rosterContent,characters:{...rosterContent.characters,...liveDefinitions()}},Number(count.rows[0]?.count??0));
 if(!roster.ok)return {ok:false as const,reason:roster.reason};
 return {ok:true as const,units:roster.units,skillbook:roster.skillbook};
}

export const pvpQueueRoutes:FastifyPluginAsync=async app=>{
 app.post("/queue/join",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const request=z.object({mode:z.enum(["friendly_duel","guild_duel"]).default("friendly_duel")}).strict().safeParse(req.body??{});
  if(!request.success)return reply.code(400).send({error:"invalid_pvp_queue"});
  const mode=request.data.mode;
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   await client.query("SELECT pg_advisory_xact_lock(hashtext('reverie:pvp:friendly-queue'))");
   await expirePlayerMatches(client,playerId);
   await client.query("UPDATE pvp_queue_tickets SET status='expired' WHERE status='waiting' AND expires_at<=now()");
   // Use the existing queue lock for both modes and the guild membership lock
   // before reading membership. A player can never have two waiting queues.
   await client.query("SELECT pg_advisory_xact_lock(741926041)");
   await client.query("UPDATE pvp_queue_tickets q SET status='cancelled' WHERE q.status='waiting' AND q.mode='guild_duel' AND NOT EXISTS(SELECT 1 FROM guild_members gm WHERE gm.player_id=q.player_id AND gm.guild_id=q.guild_id AND gm.joined_at=q.guild_joined_at)");
   const membership=mode==="guild_duel"?(await client.query("SELECT guild_id,joined_at::text AS joined FROM guild_members WHERE player_id=$1",[playerId])).rows[0]:null;
   const guild=membership?.guild_id??null;
   if(mode==="guild_duel"&&!guild){await client.query("COMMIT");return reply.code(403).send({error:"guild_membership_required"});}
   const existing=await client.query<{id:string;status:string;match_id:string|null;expires_at:Date;mode:string}>(
    "SELECT id,status,match_id,expires_at,mode FROM pvp_queue_tickets WHERE player_id=$1 AND status IN('waiting','matched') ORDER BY created_at DESC LIMIT 1 FOR UPDATE",[playerId]);
   if(existing.rows[0]){
    const ticket=existing.rows[0];
    const matchState=ticket.match_id?await client.query<{status:string}>("SELECT status FROM pvp_matches WHERE id=$1",[ticket.match_id]):null;
    const terminal=matchState?.rows[0]?.status;
    if(ticket.status==="waiting"||terminal==="active"||terminal==="queued"){
     await client.query("COMMIT");
     return {mode:ticket.mode,status:ticket.status,queueTicketId:ticket.id,matchId:ticket.match_id,expiresAt:ticket.expires_at,combatReady:terminal==="active"};
    }
    const terminalTicketStatus=terminal==="completed"?"completed":"expired";
    await client.query("UPDATE pvp_queue_tickets SET status=$2 WHERE id=$1",[ticket.id,terminalTicketStatus]);
   }
   const active=await client.query(
    "SELECT 1 FROM pvp_match_players mp JOIN pvp_matches m ON m.id=mp.match_id WHERE mp.player_id=$1 AND m.status IN('queued','active') LIMIT 1",[playerId]);
   if(active.rowCount){await client.query("ROLLBACK");return reply.code(409).send({error:"player_already_in_match"});}
   const first=await loadPlayerRoster(client,playerId,1);
   if(!first.ok){await client.query("ROLLBACK");return reply.code(409).send({error:"pvp_party_invalid",reason:first.reason});}
   const power=mode==="guild_duel"?guildPartyPower(first.units):null;
   const ticket=await client.query<{id:string;expires_at:Date}>(
    "INSERT INTO pvp_queue_tickets(player_id,mode,guild_id,guild_joined_at,party_power) VALUES($1,$2,$3,$4,$5) RETURNING id,expires_at",[playerId,mode,guild,membership?.joined??null,power]);
   const candidates=await client.query<{id:string;player_id:string;guild_id:string|null;wait_seconds:number}>(
    "SELECT q.id,q.player_id,q.guild_id,extract(epoch FROM now()-q.created_at)::int AS wait_seconds FROM pvp_queue_tickets q JOIN players p ON p.id=q.player_id JOIN accounts a ON a.id=p.account_id AND a.status='active' WHERE q.status='waiting' AND q.player_id<>$1 AND q.expires_at>now() AND q.mode=$2 AND ($2='friendly_duel' OR (q.guild_id<>$3::uuid AND EXISTS(SELECT 1 FROM guild_members gm WHERE gm.player_id=q.player_id AND gm.guild_id=q.guild_id AND gm.joined_at=q.guild_joined_at) AND NOT EXISTS(SELECT 1 FROM pvp_match_players a1 JOIN pvp_match_players a2 ON a2.match_id=a1.match_id JOIN pvp_matches recent ON recent.id=a1.match_id WHERE a1.player_id=$1 AND a2.player_id=q.player_id AND recent.mode='guild_duel' AND recent.started_at>now()-make_interval(mins=>$4)))) AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=q.player_id) OR (b.player_id=q.player_id AND b.blocked_id=$1)) AND NOT EXISTS(SELECT 1 FROM pvp_match_players mp JOIN pvp_matches m ON m.id=mp.match_id WHERE mp.player_id=q.player_id AND m.status IN('queued','active')) ORDER BY q.created_at,q.id LIMIT 32 FOR UPDATE OF q SKIP LOCKED",[playerId,mode,guild,GUILD_DUEL_REMATCH_MINUTES]);
   let opponent:typeof candidates.rows[number]|undefined;
   let second:Awaited<ReturnType<typeof loadPlayerRoster>>|undefined;
   for(const candidate of candidates.rows){
    const roster=await loadPlayerRoster(client,candidate.player_id,2);
    if(!roster.ok){
     // Invalid saved parties cannot clog a queue indefinitely.
     await client.query("UPDATE pvp_queue_tickets SET status='cancelled' WHERE id=$1",[candidate.id]);continue;
    }
    if(mode==="guild_duel"&&!guildPowerCompatible(power!,guildPartyPower(roster.units),candidate.wait_seconds))continue;
    opponent=candidate;second=roster;break;
   }
   if(!opponent||!second?.ok){
    await client.query("COMMIT");
    return reply.code(202).send({mode,status:"waiting",queueTicketId:ticket.rows[0]!.id,expiresAt:ticket.rows[0]!.expires_at,combatReady:false});
   }
   const opponentId=opponent.player_id;
   const seed=randomBytes(32);
   const seedHash=createHash("sha256").update(seed).digest("hex");
   const match=await client.query<{id:string}>(
    "INSERT INTO pvp_matches(mode,status,server_seed_hash,server_seed) VALUES($3,'queued',$1,$2) RETURNING id",[seedHash,seed,mode]);
   const matchId=match.rows[0]!.id;
   const stateSeed=seed.readUInt32BE(0);
   const state=createInitialPvpState(matchId,stateSeed,
    {playerId,team:1,units:first.units},{playerId:opponentId,team:2,units:second.units});
   if(!state){await client.query("ROLLBACK");return reply.code(409).send({error:"pvp_roster_invalid"});}
   const skillbook={...first.skillbook,...second.skillbook};
   await client.query("INSERT INTO pvp_match_players(match_id,player_id,team,guild_id) VALUES($1,$2,1,$4),($1,$3,2,$5)",[matchId,playerId,opponentId,guild,opponent.guild_id]);
   await client.query("INSERT INTO pvp_events(match_id,sequence,actor_player_id,event) VALUES($1,1,NULL,$2::jsonb)",
    [matchId,JSON.stringify({type:"match_started",turn:state.turn,turnPlayerId:state.turnPlayerId,units:state.units.map(unit=>({uid:unit.uid,ownerId:unit.ownerId,team:unit.team,charId:unit.charId}))})]);
   await client.query("UPDATE pvp_matches SET status='active',state=$2::jsonb,state_sequence=0,next_event_sequence=2,turn_player_id=$3,started_at=now(),expires_at=now()+interval '15 minutes' WHERE id=$1",
    [matchId,JSON.stringify({...state,skillbook}),state.turnPlayerId]);
   await client.query("UPDATE pvp_queue_tickets SET status='matched',match_id=$1,matched_at=now() WHERE id IN($2,$3)",
    [matchId,ticket.rows[0]!.id,opponent.id]);
   await client.query("COMMIT");
   return reply.code(202).send({mode,status:"matched",queueTicketId:ticket.rows[0]!.id,matchId,serverSeedHash:seedHash,combatReady:true,turnPlayerId:state.turnPlayerId});
  }catch(e){await client.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"pvp_queue_join_failed"});}
  finally{client.release();}
 });
 app.post("/queue/leave",{config:{rateLimit:{max:20,timeWindow:"1 minute"}}},async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   await client.query("SELECT pg_advisory_xact_lock(hashtext('reverie:pvp:friendly-queue'))");
   const result=await client.query<{id:string}>("UPDATE pvp_queue_tickets SET status='cancelled' WHERE player_id=$1 AND status='waiting' RETURNING id",[playerId]);
   await client.query("COMMIT");
   return {status:result.rowCount?"cancelled":"not_waiting"};
  }catch(e){await client.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"pvp_queue_leave_failed"});}
  finally{client.release();}
 });
 app.get("/queue/status",async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   await expirePlayerMatches(client,playerId);
   await client.query("UPDATE pvp_queue_tickets SET status='expired' WHERE player_id=$1 AND status='waiting' AND expires_at<=now()",[playerId]);
   await client.query("UPDATE pvp_queue_tickets q SET status='cancelled' WHERE q.player_id=$1 AND q.status='waiting' AND q.mode='guild_duel' AND NOT EXISTS(SELECT 1 FROM guild_members gm WHERE gm.player_id=q.player_id AND gm.guild_id=q.guild_id AND gm.joined_at=q.guild_joined_at)",[playerId]);
   await client.query(
    "UPDATE pvp_queue_tickets q SET status=CASE WHEN m.status='completed' THEN 'completed' ELSE 'expired' END FROM pvp_matches m WHERE q.match_id=m.id AND q.player_id=$1 AND q.status='matched' AND m.status IN('completed','expired','cancelled')",[playerId]);
   const result=await client.query<{status:string;match_id:string|null;expires_at:Date;match_status:string|null;mode:string}>(
    "SELECT q.status,q.match_id,q.expires_at,q.mode,m.status AS match_status FROM pvp_queue_tickets q LEFT JOIN pvp_matches m ON m.id=q.match_id WHERE q.player_id=$1 AND q.status IN('waiting','matched') ORDER BY q.created_at DESC LIMIT 1",[playerId]);
   await client.query("COMMIT");
   const row=result.rows[0];
   return {mode:row?.mode??null,status:row?.status??"not_queued",matchId:row?.match_id??null,expiresAt:row?.expires_at??null,combatReady:row?.match_status==="active"};
  }catch(error){await client.query("ROLLBACK");req.log.error(error);return reply.code(500).send({error:"pvp_queue_status_failed"});}
  finally{client.release();}
 });
};
