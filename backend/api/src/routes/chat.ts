import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {z} from "zod";
import {randomUUID} from "node:crypto";
import {pool} from "../db.js";
import {createChatRetention,RECENT_CHAT_CLEANUP_SQL} from "../world/chat-retention.js";
import type {PoolClient} from "pg";
import {profilePicture} from "./social.js";
import {summonDisplayName} from "../world/summon.js";
import {titleName,verifiedTitleSql} from "./daily-quests.js";

type Identity={id:string;name:string;avatar:string;title_id:string};
type Message={id:string;channel:"world"|"party"|"private"|"guild";playerId:string;name:string;avatar:string;title:string;text:string;at:number;partyId:string|null;recipientId:string|null;kind?:"mythic_summon";characterId?:string;replyTo?:string|null};
const channel=z.enum(["world","party","private","guild"]);
const query=z.object({channel:channel.default("world"),recipientId:z.string().uuid().optional()}).refine(v=>(v.channel==="private")===Boolean(v.recipientId));
const body=z.object({channel,recipientId:z.string().uuid().optional(),replyTo:z.string().uuid().optional(),guildId:z.string().uuid().optional(),text:z.string().trim().min(1).max(200).refine(s=>!/\p{Cc}|\p{Cf}/u.test(s),"Invalid characters")}).strict().refine(v=>(v.channel==="private")===Boolean(v.recipientId)&&(v.channel==="guild")===Boolean(v.guildId));
const blockBody=z.object({playerId:z.string().uuid()}).strict();
const CHARACTER_STICKERS=["kael_mythic","lilith_mythic","gerald_mythic","ravienna_mythic","cassien_mythic","nyx_mythic","crimson_witch_mythic","mirene_mythic","caelith_mythic"] as const;
function characterSticker(text:string):string|undefined {
 const match=/^\[sticker:([a-z_]+)\]$/.exec(text);
 return match&&CHARACTER_STICKERS.some(id=>id===match[1])?match[1]:undefined;
}
async function unlockedStickers(playerId:string):Promise<string[]> {
 const owned=await pool.query<{char_id:string}>("SELECT char_id FROM owned_characters WHERE player_id=$1 AND char_id=ANY($2::text[])",[playerId,CHARACTER_STICKERS]);
 return CHARACTER_STICKERS.filter(id=>owned.rows.some(row=>row.char_id===id));
}
async function identity(req:FastifyRequest,reply:FastifyReply):Promise<Identity|null>{
 try {
  await req.jwtVerify();
  const claims=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(claims.sub&&claims.playerId&&Number.isInteger(claims.tokenVersion)){
   const q=await pool.query<Identity>("SELECT p.id,p.name,p.settings->>'profile_picture' AS avatar,"+verifiedTitleSql+" AS title_id FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3",[claims.playerId,claims.sub,claims.tokenVersion]);
   if(q.rows[0])return q.rows[0];
  }
 }catch{/* fail closed */}
 reply.code(401).send({error:"authentication_required"});return null;
}
async function partyFor(id:string){
 const r=await pool.query<{lobby_id:string;joined_at:Date}>("SELECT m.lobby_id,m.joined_at FROM co_op_lobby_members m JOIN co_op_lobbies l ON l.id=m.lobby_id WHERE m.player_id=$1 AND l.status IN ('open','in_world')",[id]);
 return r.rows[0];
}
async function guildFor(id:string){
 return (await pool.query<{guild_id:string;joined_at:string}>("SELECT guild_id,joined_at::text AS joined_at FROM guild_members WHERE player_id=$1",[id])).rows[0];
}
async function friendshipSince(id:string,other:string,db:PoolClient|typeof pool=pool){
 if(id===other)return undefined;
 const r=await db.query<{updated_at:Date}>("SELECT f.updated_at FROM friendships f JOIN players p ON p.id=$2 JOIN accounts a ON a.id=p.account_id WHERE ((f.player_id=$1 AND f.friend_id=$2) OR (f.player_id=$2 AND f.friend_id=$1)) AND f.status='accepted' AND a.status='active' AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=$2) OR (b.player_id=$2 AND b.blocked_id=$1))",[id,other]);
 return r.rows[0]?.updated_at;
}
async function withFriendship<T>(id:string,other:string,work:(db:PoolClient)=>Promise<T>):Promise<T|undefined>{
 if(id===other)return undefined;
 const db=await pool.connect();
 try{
  await db.query("BEGIN");
  await db.query("SELECT id FROM players WHERE id=ANY($1::uuid[]) ORDER BY id FOR UPDATE",[[id,other]]);
  if(!await friendshipSince(id,other,db)){await db.query("ROLLBACK");return undefined;}
  const result=await work(db);
  await db.query("COMMIT");return result;
 }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
}
export const chatRoutes:FastifyPluginAsync=async app=>{
 app.setErrorHandler((error,req,reply)=>{
  const e=error as {code?:string;message?:string};
  if(e.code==="P0001"&&e.message==="chat_muted")return reply.code(403).send({error:"chat_muted"});
  throw error;
 });
 app.post("/reports",{config:{rateLimit:{max:12,timeWindow:"1 minute"}}},async(req,reply)=>{
  reply.header("Cache-Control","no-store");
  const me=await identity(req,reply);if(!me)return;
  const parsed=z.object({messageId:z.string().uuid()}).strict().safeParse(req.body);
  if(!parsed.success)return reply.code(400).send({error:"invalid_report"});
  const db=await pool.connect();
  try{
   await db.query("BEGIN");
   await db.query("SELECT pg_advisory_xact_lock(hashtextextended('reverie-report:'||$1::uuid::text,0))",[me.id]);
   const existing=await db.query("SELECT id FROM reverie_chat_reports WHERE reporter_id=$1 AND message_id=$2",[me.id,parsed.data.messageId]);
   if(existing.rowCount){await db.query("COMMIT");return {ok:true,duplicate:true};}
   const count=await db.query("SELECT count(*)::int AS n FROM reverie_chat_reports WHERE reporter_id=$1 AND created_at>now()-interval '24 hours'",[me.id]);
   if(count.rows[0].n>=10){await db.query("ROLLBACK");return reply.code(429).send({error:"report_limit"});}
   const q=await db.query("INSERT INTO reverie_chat_reports(reporter_id,message_id,target_player_id,target_name,message_text,message_at) SELECT $1,m.id,m.sender_id,m.sender_name,m.body,m.created_at FROM recent_chat_messages m JOIN players p ON p.id=m.sender_id JOIN accounts a ON a.id=p.account_id WHERE m.id=$2 AND m.channel='world' AND m.sender_id<>$1 AND m.created_at>=now()-interval '30 minutes' AND a.status='active' AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=m.sender_id) OR (b.player_id=m.sender_id AND b.blocked_id=$1)) RETURNING id",[me.id,parsed.data.messageId]);
   if(!q.rowCount){await db.query("ROLLBACK");return reply.code(404).send({error:"report_message_unavailable"});}
   await db.query("COMMIT");return reply.code(201).send({ok:true,duplicate:false});
  }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 });
 app.get("/moderation-status",async(req,reply)=>{
  reply.header("Cache-Control","no-store");
  const me=await identity(req,reply);if(!me)return;
  const m=await pool.query("SELECT muted_until FROM reverie_chat_mutes WHERE player_id=$1 AND muted_until>clock_timestamp()",[me.id]);
  const notices=await pool.query("SELECT a.id::text AS id,a.action,a.reason,a.muted_until,a.created_at,(n.notice_id IS NOT NULL) AS acknowledged FROM reverie_moderation_audit a LEFT JOIN reverie_notice_acknowledgements n ON n.notice_id=a.id AND n.player_id=$1 WHERE a.target_player_id=$1 ORDER BY (n.notice_id IS NOT NULL),a.id DESC LIMIT 30",[me.id]);
  const unread=await pool.query("SELECT count(*)::int AS n FROM reverie_moderation_audit a WHERE a.target_player_id=$1 AND NOT EXISTS(SELECT 1 FROM reverie_notice_acknowledgements n WHERE n.notice_id=a.id AND n.player_id=$1)",[me.id]);
  const mutedUntil=m.rows[0]?.muted_until??null;
  return {playerId:me.id,mutedUntil,remainingSeconds:mutedUntil?Math.max(0,Math.ceil((new Date(mutedUntil).getTime()-Date.now())/1000)):0,unread:unread.rows[0].n,notices:notices.rows};
 });
 app.post("/moderation-ack",{config:{rateLimit:{max:12,timeWindow:"1 minute"}}},async(req,reply)=>{
  reply.header("Cache-Control","no-store");
  const me=await identity(req,reply);if(!me)return;
  const parsed=z.object({ids:z.array(z.string().regex(/^[1-9][0-9]{0,17}$/)).min(1).max(30)}).strict().safeParse(req.body);
  if(!parsed.success)return reply.code(400).send({error:"invalid_notice_ack"});
  const ids=[...new Set(parsed.data.ids)];
  const db=await pool.connect();
  try{
   await db.query("BEGIN");
   const allowed=await db.query("SELECT id FROM reverie_moderation_audit WHERE target_player_id=$1 AND id=ANY($2::bigint[])",[me.id,ids]);
   if(allowed.rowCount!==ids.length){await db.query("ROLLBACK");return reply.code(404).send({error:"notice_not_found"});}
   await db.query("INSERT INTO reverie_notice_acknowledgements(notice_id,player_id) SELECT id,$1 FROM reverie_moderation_audit WHERE target_player_id=$1 AND id=ANY($2::bigint[]) ON CONFLICT DO NOTHING",[me.id,ids]);
   await db.query("COMMIT");return {ok:true,playerId:me.id};
  }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 });
 app.get("/stickers",async(req,reply)=>{
  reply.header("Cache-Control","no-store");
  const me=await identity(req,reply);if(!me)return;
  return {playerId:me.id,unlocked:await unlockedStickers(me.id)};
 });
 app.get("/contacts",async(req,reply)=>{
  reply.header("Cache-Control","no-store");
  const me=await identity(req,reply);if(!me)return;
  const q=await pool.query("SELECT p.id,p.name,p.settings->>'profile_picture' AS avatar,"+verifiedTitleSql+" AS title_id,EXISTS(SELECT 1 FROM player_presence pr WHERE pr.player_id=p.id AND pr.state<>'offline' AND pr.last_heartbeat_at>now()-interval '45 seconds') AS online,(SELECT count(*)::int FROM private_chat_messages m WHERE m.sender_id=p.id AND m.recipient_id=$1 AND m.read_at IS NULL) AS unread,latest.body AS preview,latest.sender_id AS preview_sender,extract(epoch FROM latest.created_at)*1000 AS preview_at FROM friendships f JOIN players p ON p.id=CASE WHEN f.player_id=$1 THEN f.friend_id ELSE f.player_id END JOIN accounts a ON a.id=p.account_id LEFT JOIN LATERAL (SELECT body,sender_id,created_at,id FROM ((SELECT body,sender_id,created_at,id FROM private_chat_messages WHERE sender_id=p.id AND recipient_id=$1 ORDER BY created_at DESC,id DESC LIMIT 1) UNION ALL (SELECT body,sender_id,created_at,id FROM private_chat_messages WHERE sender_id=$1 AND recipient_id=p.id ORDER BY created_at DESC,id DESC LIMIT 1)) recent ORDER BY created_at DESC,id DESC LIMIT 1) latest ON true WHERE (f.player_id=$1 OR f.friend_id=$1) AND f.status='accepted' AND a.status='active' AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=p.id) OR (b.blocked_id=$1 AND b.player_id=p.id)) ORDER BY unread DESC,latest.created_at DESC NULLS LAST,p.name LIMIT 200",[me.id]);
  return {players:q.rows.map(r=>({...r,avatar:profilePicture(r.avatar),title:titleName(r.title_id),preview:typeof r.preview==="string"?Array.from(r.preview).slice(0,64).join(""):null,preview_at:r.preview_at===null?null:Number(r.preview_at)}))};
 });
 // Expired messages are never readable; bounded, non-overlapping physical cleanup.
 const retention=createChatRetention(async()=>(await pool.query(RECENT_CHAT_CLEANUP_SQL)).rowCount??0,e=>app.log.warn({err:e},"chat retention cleanup failed"));
 const cleanup=setInterval(()=>{void retention.tick();},30000);
 cleanup.unref();
 app.addHook("onClose",async()=>{clearInterval(cleanup);await retention.close();});
 app.get("/messages",async(req,reply)=>{
  reply.header("Cache-Control","no-store");
  const me=await identity(req,reply);if(!me)return;
  const parsed=query.safeParse(req.query);if(!parsed.success)return reply.code(400).send({error:"invalid_channel"});
  const c=parsed.data.channel,party=c==="party"?await partyFor(me.id):undefined;
  if(c==="party"&&!party)return reply.code(403).send({error:"party_membership_required"});
  const guild=c==="guild"?await guildFor(me.id):undefined;
  if(c==="guild"&&!guild)return reply.code(403).send({error:"guild_membership_required"});
  const recipient=parsed.data.recipientId;
  const since=c==="private"?await friendshipSince(me.id,recipient!):undefined;
  if(c==="private"&&!since)return reply.code(403).send({error:"friendship_required"});
  if(c==="private"){
   const messages=await withFriendship(me.id,recipient!,async db=>{
    const result=await db.query("SELECT m.id,m.sender_id AS \"playerId\",m.recipient_id AS \"recipientId\",p.name,p.settings->>'profile_picture' AS avatar,"+verifiedTitleSql+" AS title_id,m.body AS text,m.reply_to AS \"replyTo\",extract(epoch FROM m.created_at)*1000 AS at FROM private_chat_messages m JOIN players p ON p.id=m.sender_id WHERE (m.sender_id=$1 AND m.recipient_id=$2) OR (m.sender_id=$2 AND m.recipient_id=$1) ORDER BY m.created_at DESC,m.id DESC LIMIT 100",[me.id,recipient]);
    await db.query("UPDATE private_chat_messages SET read_at=now() WHERE recipient_id=$1 AND sender_id=$2 AND read_at IS NULL",[me.id,recipient]);
    return result.rows.reverse().map(r=>({...r,channel:"private",avatar:profilePicture(r.avatar),title:titleName(r.title_id),at:Number(r.at)}));
   });
   if(!messages)return reply.code(403).send({error:"friendship_required"});
   return {channel:c,partyId:null,recipientId:recipient,messages};
  }
  if(c==="guild"){
   const rows=await pool.query("SELECT m.id,m.channel,m.sender_id AS \"playerId\",m.sender_name AS name,m.avatar,m.title,m.body AS text,m.reply_to AS \"replyTo\",extract(epoch FROM m.created_at)*1000 AS at FROM recent_chat_messages m JOIN players p ON p.id=m.sender_id JOIN accounts a ON a.id=p.account_id WHERE m.channel='guild' AND m.guild_id=$2 AND m.created_at>=now()-interval '30 minutes' AND a.status='active' AND EXISTS(SELECT 1 FROM guild_members gm WHERE gm.player_id=$1 AND gm.guild_id=m.guild_id AND gm.joined_at<=m.created_at) AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=m.sender_id) OR (b.player_id=m.sender_id AND b.blocked_id=$1)) ORDER BY m.created_at DESC,m.id DESC LIMIT 100",[me.id,guild!.guild_id]);
   return {channel:c,guildId:guild!.guild_id,partyId:null,recipientId:null,messages:rows.rows.reverse().map(r=>({...r,at:Number(r.at),recipientId:null}))};
  }
  const recentMessages=await pool.query("SELECT m.id,m.channel,m.sender_id AS \"playerId\",m.sender_name AS name,m.avatar,m.title,m.body AS text,m.reply_to AS \"replyTo\",m.party_id AS \"partyId\",extract(epoch FROM m.created_at)*1000 AS at FROM recent_chat_messages m JOIN players p ON p.id=m.sender_id JOIN accounts a ON a.id=p.account_id WHERE m.channel=$2 AND m.created_at>=now()-interval '30 minutes' AND a.status='active' AND ($2='world' OR (m.party_id=$3 AND m.created_at>=$4 AND EXISTS(SELECT 1 FROM co_op_lobby_members cm JOIN co_op_lobbies l ON l.id=cm.lobby_id WHERE cm.player_id=$1 AND cm.lobby_id=m.party_id AND cm.joined_at<=(m.created_at) AND l.status IN ('open','in_world')))) AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=m.sender_id) OR (b.player_id=m.sender_id AND b.blocked_id=$1)) ORDER BY m.created_at DESC,m.id DESC LIMIT 100",[me.id,c,party?.lobby_id??null,party?.joined_at??null]);
  const messages:Message[]=recentMessages.rows.reverse().map(r=>({...r,at:Number(r.at),recipientId:null}));
  if(c==="world"){
   // Derive notices from committed summon results. No client-controlled text,
   // extra grant, process-local event bus or replay-generated duplicate.
   const recent=await pool.query<{id:string;player_id:string;name:string;avatar:string;character_id:string;at:string}>(
    "SELECT r.id::text,g.player_id,p.name,p.settings->>'profile_picture' AS avatar,r.character_id,extract(epoch FROM g.created_at)*1000 AS at FROM gacha_pulls g JOIN gacha_pull_results r ON r.pull_id=g.id JOIN players p ON p.id=g.player_id JOIN accounts a ON a.id=p.account_id WHERE g.created_at>=now()-interval '30 minutes' AND r.rarity='mythic' AND r.reward_kind='character' AND a.status='active' AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=g.player_id) OR (b.player_id=g.player_id AND b.blocked_id=$1)) ORDER BY g.created_at DESC,r.id DESC LIMIT 100",[me.id]);
   for(const row of recent.rows){
    messages.push({id:"mythic-summon:"+row.id,channel:"world",kind:"mythic_summon",playerId:row.player_id,name:row.name,avatar:profilePicture(row.avatar),title:"",characterId:row.character_id,text:row.name+" summoned Mythic "+summonDisplayName(row.character_id)+"!",at:Number(row.at),partyId:null,recipientId:null});
   }
   messages.sort((a,b)=>a.at-b.at||a.id.localeCompare(b.id));
  }
  return {channel:c,partyId:party?.lobby_id??null,recipientId:recipient??null,messages:messages.slice(-100).map(({partyId,...m})=>m)};
 });
 app.post("/messages",async(req,reply)=>{
  reply.header("Cache-Control","no-store");
  const me=await identity(req,reply);if(!me)return;
  const parsed=body.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_message"});
  const c=parsed.data.channel,party=c==="party"?await partyFor(me.id):undefined;
  if(c==="party"&&!party)return reply.code(403).send({error:"party_membership_required"});
  const guild=c==="guild"?await guildFor(me.id):undefined;
  if(c==="guild"&&!guild)return reply.code(403).send({error:"guild_membership_required"});
  const recipient=parsed.data.recipientId;
  const since=c==="private"?await friendshipSince(me.id,recipient!):undefined;
  if(c==="private"&&!since)return reply.code(403).send({error:"friendship_required"});
  if(c==="guild"&&parsed.data.guildId!==guild?.guild_id)return reply.code(403).send({error:"guild_membership_required"});
  const sticker=characterSticker(parsed.data.text);
  if(sticker&&!(await unlockedStickers(me.id)).includes(sticker))return reply.code(403).send({error:"sticker_locked"});
  const replyTo=parsed.data.replyTo;
  if(replyTo&&c==="guild"){
   const target=await pool.query("SELECT m.id FROM recent_chat_messages m JOIN players p ON p.id=m.sender_id JOIN accounts a ON a.id=p.account_id WHERE m.id=$1 AND m.channel='guild' AND m.guild_id=$2 AND m.created_at>=now()-interval '30 minutes' AND a.status='active' AND EXISTS(SELECT 1 FROM guild_members gm WHERE gm.player_id=$3 AND gm.guild_id=m.guild_id AND gm.joined_at<=m.created_at) AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$3 AND b.blocked_id=m.sender_id) OR (b.player_id=m.sender_id AND b.blocked_id=$3))",[replyTo,guild!.guild_id,me.id]);
   if(!target.rowCount)return reply.code(400).send({error:"reply_unavailable"});
  }
  if(replyTo&&c!=="private"&&c!=="guild"){
   const target=await pool.query("SELECT m.id FROM recent_chat_messages m JOIN players p ON p.id=m.sender_id JOIN accounts a ON a.id=p.account_id WHERE a.status='active' AND m.id=$1 AND m.channel=$2 AND m.created_at>=now()-interval '30 minutes' AND ($2='world' OR (m.party_id=$3 AND m.created_at>=$4)) AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$5 AND b.blocked_id=m.sender_id) OR (b.player_id=m.sender_id AND b.blocked_id=$5))",[replyTo,c,party?.lobby_id??null,party?.joined_at??null,me.id]);
   if(!target.rowCount)return reply.code(400).send({error:"reply_unavailable"});
  }
  if((await pool.query("SELECT 1 FROM reverie_chat_mutes WHERE player_id=$1 AND muted_until>clock_timestamp()",[me.id])).rowCount)return reply.code(403).send({error:"chat_muted"});
  // An atomic upsert serializes competing requests for this account across API instances.
  const budget=await pool.query("INSERT INTO chat_send_limits(player_id,sent_at_ms) VALUES($1,ARRAY[(extract(epoch FROM clock_timestamp())*1000)::bigint]) ON CONFLICT(player_id) DO UPDATE SET sent_at_ms=ARRAY(SELECT t FROM unnest(chat_send_limits.sent_at_ms) AS t WHERE t>EXCLUDED.sent_at_ms[1]-10000 ORDER BY t)||EXCLUDED.sent_at_ms WHERE cardinality(ARRAY(SELECT t FROM unnest(chat_send_limits.sent_at_ms) AS t WHERE t>EXCLUDED.sent_at_ms[1]-10000))<5 AND coalesce(chat_send_limits.sent_at_ms[cardinality(chat_send_limits.sent_at_ms)],0)<=EXCLUDED.sent_at_ms[1]-1000 RETURNING player_id",[me.id]);
  if(!budget.rowCount)return reply.code(429).send({error:"chat_rate_limited"});
  const m:Message={id:randomUUID(),channel:c,playerId:me.id,name:me.name,avatar:profilePicture(me.avatar),title:titleName(me.title_id),text:parsed.data.text,replyTo:replyTo??null,at:Date.now(),partyId:party?.lobby_id??null,recipientId:recipient??null};
  if(c==="private"){
   const at=await withFriendship(me.id,recipient!,async db=>{
    if(replyTo){
     const target=await db.query("SELECT id FROM private_chat_messages WHERE id=$3 AND ((sender_id=$1 AND recipient_id=$2) OR (sender_id=$2 AND recipient_id=$1))",[me.id,recipient,replyTo]);
     if(!target.rowCount)return null;
    }
    const inserted=await db.query("INSERT INTO private_chat_messages(id,sender_id,recipient_id,body,reply_to) VALUES($1,$2,$3,$4,$5) RETURNING extract(epoch FROM created_at)*1000 AS at",[m.id,me.id,recipient,m.text,replyTo??null]);
    return Number(inserted.rows[0].at);
   });
   if(at===undefined)return reply.code(403).send({error:"friendship_required"});
   if(at===null)return reply.code(400).send({error:"reply_unavailable"});
   m.at=at;
  }else if(c==="guild"){
   const inserted=await pool.query("INSERT INTO recent_chat_messages(id,sender_id,channel,guild_id,sender_name,avatar,title,body,reply_to) SELECT $1,$2,'guild',$3,$4,$5,$6,$7,$8 WHERE EXISTS(SELECT 1 FROM guild_members gm WHERE gm.player_id=$2 AND gm.guild_id=$3 AND gm.joined_at=$9 FOR SHARE) RETURNING extract(epoch FROM created_at)*1000 AS at",[m.id,me.id,guild!.guild_id,m.name,m.avatar,m.title,m.text,m.replyTo,guild!.joined_at]);
   if(!inserted.rowCount)return reply.code(403).send({error:"guild_membership_required"});
   m.at=Number(inserted.rows[0].at);
  }else{
   const inserted=await pool.query("INSERT INTO recent_chat_messages(id,sender_id,channel,party_id,sender_name,avatar,title,body,reply_to) SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9 WHERE $3='world' OR EXISTS(SELECT 1 FROM co_op_lobby_members cm JOIN co_op_lobbies l ON l.id=cm.lobby_id WHERE cm.player_id=$2 AND cm.lobby_id=$4 AND l.status IN ('open','in_world')) RETURNING extract(epoch FROM created_at)*1000 AS at",[m.id,me.id,c,m.partyId,m.name,m.avatar,m.title,m.text,m.replyTo]);
   if(!inserted.rowCount)return reply.code(403).send({error:"party_membership_required"});
   m.at=Number(inserted.rows[0].at);
  }
  const {partyId,...message}=m;
  return reply.code(201).send({message,partyId,guildId:guild?.guild_id??null});
 });
 app.post("/block",async(req,reply)=>{
  const me=await identity(req,reply);if(!me)return;
  const parsed=blockBody.safeParse(req.body);if(!parsed.success||parsed.data.playerId===me.id)return reply.code(400).send({error:"invalid_player"});
  const target=parsed.data.playerId;
  const found=await pool.query("SELECT id FROM players WHERE id=$1",[target]);
  if(!found.rowCount)return reply.code(404).send({error:"player_not_found"});
  const client=await pool.connect();try{await client.query("BEGIN");await client.query("SELECT id FROM players WHERE id=ANY($1::uuid[]) ORDER BY id FOR UPDATE",[[me.id,target]]);await client.query("INSERT INTO blocks(player_id,blocked_id) VALUES($1,$2) ON CONFLICT DO NOTHING",[me.id,target]);await client.query("DELETE FROM friendships WHERE (player_id=$1 AND friend_id=$2) OR (player_id=$2 AND friend_id=$1)",[me.id,target]);await client.query("DELETE FROM private_chat_messages WHERE (sender_id=$1 AND recipient_id=$2) OR (sender_id=$2 AND recipient_id=$1)",[me.id,target]);await client.query("COMMIT");}catch(e){await client.query("ROLLBACK");throw e;}finally{client.release();}
  return {blocked:true};
 });
 app.get("/blocks",async(req,reply)=>{
  reply.header("Cache-Control","no-store");
  const me=await identity(req,reply);if(!me)return;
  const r=await pool.query("SELECT p.id,p.name FROM blocks b JOIN players p ON p.id=b.blocked_id WHERE b.player_id=$1 ORDER BY p.name LIMIT 500",[me.id]);
  return {players:r.rows};
 });
 app.post("/unblock",async(req,reply)=>{
  const me=await identity(req,reply);if(!me)return;
  const parsed=blockBody.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_player"});
  await pool.query("DELETE FROM blocks WHERE player_id=$1 AND blocked_id=$2",[me.id,parsed.data.playerId]);return {blocked:false};
 });
};
