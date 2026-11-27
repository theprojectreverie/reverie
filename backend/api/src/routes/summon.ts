import type {FastifyPluginAsync} from "fastify";
import {z} from "zod";
import {createHash,randomInt} from "node:crypto";
import {readFileSync} from "node:fs";
const loadProgression=(name:string)=>JSON.parse(readFileSync(new URL("../../../../resources/data/"+name+".json",import.meta.url),"utf8"));
const progressionCharacters={...loadProgression("main_characters"),...loadProgression("characters")} as Record<string,{skills?:string[];ultimate?:string}>;
const progressionItems=loadProgression("items") as Record<string,{category:string;slot?:string;rarity?:string;stats?:Record<string,number>}>;
const progressionSkills=loadProgression("skills") as Record<string,{kind:string;ultimate?:boolean}>;

import {pool} from "../db.js";
import {summonAdmission} from "../world/summon-admission.js";
import {auditPaidGuarantees} from "../world/paid-guarantee-audit.js";
import {STARTER_PARTY,xpToNext} from "../world/character-xp.js";
import {banners,contentHash,contentId,emptyPity,rollBanner,describeRoll,retiredPlayableIds,upgradeCard,mythicRecipe,ascensionRecipe,type Pity,type Roll,PAID_MILESTONE,PAID_CURRENCY,PAID_GUARANTEE_POLICY} from "../world/summon.js";
import {publishedCharacterPacks,publishedCharacterArtwork,liveDefinition} from "../world/live-character-packs.js";
import {activeEvents,eventProgress} from "../world/live-events.js";
import {readArtwork} from "../world/live-content-store.js";
import {currentBannerCatalog,historicalBannerName} from "../world/live-banners.js";
const input=z.object({catalogRevision:z.string().regex(/^[a-f0-9]{64}$/).optional(),bannerId:z.string().min(1).max(80),count:z.union([z.literal(1),z.literal(10)]),requestId:z.string().uuid(),currency:z.enum(["crystals","paid_moonstones"]).optional(),expectedPaidTotal:z.string().regex(/^(0|[1-9][0-9]{0,18})$/).optional()}).strict();
async function paidTotal(db: Pick<typeof pool,"query">,id:string):Promise<string>{
 const q=await db.query("SELECT COALESCE(sum(pull_count),0)::text AS total FROM gacha_pulls WHERE player_id=$1 AND currency_id=$2",[id,PAID_CURRENCY]);
 return q.rows[0].total;
}
async function paidProgress(db: Pick<typeof pool,"query">,id:string):Promise<number>{
 return Number(BigInt(await paidTotal(db,id))%BigInt(PAID_MILESTONE));
}
export const summonRoutes:FastifyPluginAsync=async app=>{
 app.addHook("onSend",async(_req,reply,payload)=>{reply.header("Cache-Control","no-store");return payload;});
 app.get("/state",{config:{rateLimit:{max:120,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
  const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  // All fields are read from one PostgreSQL statement snapshot. No fan-out across pool connections.
  const snapshot=await pool.query(`SELECT p.id,
   COALESCE((SELECT jsonb_object_agg(currency_id,balance::text) FROM player_currencies WHERE player_id=p.id),'{}'::jsonb) AS currencies,
   COALESCE((SELECT jsonb_object_agg(banner_id,jsonb_build_object('legendary',legendary,'featured',featured,'epic_streak',epic_streak)) FROM banner_pity WHERE player_id=p.id),'{}'::jsonb) AS pity,
   COALESCE((SELECT jsonb_agg(jsonb_build_object('char_id',oc.char_id,'level',oc.level,'xp',oc.xp::text,'dupes',oc.dupes,'awakening',oc.awakening,'ascension',oc.ascension,'bond',oc.bond,'skill_levels',oc.skill_levels) ORDER BY oc.char_id) FROM owned_characters oc WHERE oc.player_id=p.id AND NOT(oc.char_id=ANY($4::text[]))),'[]'::jsonb) AS roster,
   COALESCE((SELECT jsonb_object_agg(item_id,quantity::text) FROM inventory_items WHERE player_id=p.id AND quantity>0),'{}'::jsonb) AS inventory,
   COALESCE((SELECT jsonb_agg(jsonb_build_object('char_id',oc.char_id,'slot',e.slot,'item_id',e.item_id,'enhancement_level',e.enhancement_level,'reroll_stat',e.reroll_stat,'reroll_value',e.reroll_value::text) ORDER BY oc.char_id,e.slot) FROM character_equipment e JOIN owned_characters oc ON oc.id=e.character_id AND oc.player_id=e.player_id WHERE e.player_id=p.id),'[]'::jsonb) AS equipment,
   COALESCE((SELECT jsonb_agg(oc.char_id ORDER BY pm.slot) FROM party_members pm JOIN owned_characters oc ON oc.id=pm.character_id AND oc.player_id=pm.player_id WHERE pm.player_id=p.id AND NOT(oc.char_id=ANY($4::text[]))),'[]'::jsonb) AS party,
   EXISTS(SELECT 1 FROM co_op_lobby_members m JOIN co_op_lobbies l ON l.id=m.lobby_id WHERE m.player_id=p.id AND l.status IN ('open','in_world')) AS "partyLocked",
   (SELECT COALESCE(sum(pull_count),0)::text FROM gacha_pulls WHERE player_id=p.id AND currency_id=$5) AS paid_total
   FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3`,[c.playerId,c.sub,c.tokenVersion,retiredPlayableIds,PAID_CURRENCY]);
  const row=snapshot.rows[0];
  if(!row)return reply.code(401).send({error:"authentication_required"});
  const characters=new Map<string,Record<string,unknown>>(row.roster.map((r:Record<string,unknown>)=>[String(r.char_id),r]));
  for(const id of STARTER_PARTY)if(!characters.has(id))characters.set(id,{char_id:id,level:1,xp:"0",dupes:0,awakening:0,ascension:0,bond:0,skill_levels:{}});
  let catalog;try{catalog=currentBannerCatalog();if(req.headers["x-reverie-character-content"]!=="1")catalog=Object.fromEntries(Object.entries(catalog).filter(([,b])=>!b.featured.some(id=>id.startsWith("livechar_"))));}catch(e){req.log.error(e);return reply.code(503).send({error:"summon_catalog_unavailable"});}
  let events;try{events=activeEvents();}catch(e){req.log.error(e);return reply.code(503).send({error:"event_catalog_unavailable"});}
  const receipts=events.length?(await pool.query("SELECT ref_id,reason FROM currency_ledger WHERE player_id=$1 AND reason IN ('live_event_reward','live_event_shop') AND ref_type='live_event' AND ref_id=ANY($2::text[])",[c.playerId,events.map(e=>e.id)])).rows:[];
  const claimed=receipts.filter(r=>r.reason==='live_event_reward').map(r=>r.ref_id),purchased=receipts.filter(r=>r.reason==='live_event_shop').map(r=>r.ref_id);
  const eventViews=await Promise.all(events.map(async e=>({...e,...await eventProgress(pool,c.playerId!,e),claimed:claimed.includes(e.id),purchased:purchased.includes(e.id)})));
  return {liveEvents:eventViews,bannerCatalog:catalog,playerId:c.playerId,paidTotal:row.paid_total,paidProgress:Number(BigInt(row.paid_total)%BigInt(PAID_MILESTONE)),paidMilestone:PAID_MILESTONE,paidGuaranteePolicy:PAID_GUARANTEE_POLICY,currencies:row.currencies,pity:row.pity,partyLocked:row.partyLocked,party:row.party.length?row.party:STARTER_PARTY,roster:[...characters.values()].map(character=>({...character,equipment:row.equipment.filter((e:{char_id:string})=>e.char_id===character.char_id)})),cards:Object.fromEntries(Object.entries(row.inventory).filter(([id])=>id.startsWith("upgrade_")).map(([id,quantity])=>[id,Number(quantity)])),inventory:row.inventory};
 });

 app.get("/character-content",async(req,reply)=>{try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion)||!(await pool.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3",[c.playerId,c.sub,c.tokenVersion])).rowCount)return reply.code(401).send({error:"authentication_required"});return {schema:1,playerId:c.playerId,packs:publishedCharacterPacks()};});
 app.get("/artwork/:hash",{config:{rateLimit:{max:80,timeWindow:"1 minute"}}},async(req,reply)=>{
  const params=z.object({hash:z.string().regex(/^[a-f0-9]{64}$/)}).safeParse(req.params);if(!params.success)return reply.code(404).send({error:"artwork_not_found"});
  try{if(!Object.values(currentBannerCatalog()).some(b=>b.artwork===params.data.hash)&&!publishedCharacterArtwork(params.data.hash))return reply.code(404).send({error:"artwork_not_found"});return reply.type("image/png").header("X-Content-Type-Options","nosniff").send(readArtwork(params.data.hash));}catch{return reply.code(404).send({error:"artwork_not_found"});}
 });
 app.post("/event-claim",{config:{rateLimit:{max:12,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const body=z.object({eventId:z.string().regex(/^event_[a-z0-9_]{1,60}$/)}).strict().safeParse(req.body);if(!body.success)return reply.code(400).send({error:"invalid_event_claim"});const id=body.data.eventId,db=await pool.connect();
  try{await db.query("BEGIN");const fail=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error});};
   const account=await db.query("SELECT id FROM accounts WHERE id=$1 AND status='active' AND token_version=$2 FOR UPDATE",[c.sub,c.tokenVersion]);const player=await db.query("SELECT id FROM players WHERE id=$1 AND account_id=$2 FOR UPDATE",[c.playerId,c.sub]);if(!account.rowCount||!player.rowCount)return await fail(401,"authentication_required");
   const prior=(await db.query("SELECT currency_id,delta::text,balance_after::text FROM currency_ledger WHERE player_id=$1 AND reason='live_event_reward' AND ref_type='live_event' AND ref_id=$2",[c.playerId,id])).rows[0];if(prior){await db.query("COMMIT");return {ok:true,eventId:id,currency:prior.currency_id,amount:Number(prior.delta),balance:prior.balance_after,replayed:true};}
   const event=activeEvents().find(e=>e.id===id);if(!event)return await fail(409,"event_not_active");if(!(await eventProgress(db,c.playerId,event)).eligible)return await fail(409,"event_objective_incomplete");const {currency,amount}=event.reward;
   const wallet=(await db.query("UPDATE player_currencies SET balance=balance+$3::bigint,updated_at=now() WHERE player_id=$1 AND currency_id=$2 AND balance<=9007199254740991-$3::bigint RETURNING balance::text",[c.playerId,currency,amount])).rows[0];if(!wallet)return await fail(409,"wallet_unavailable_or_limit");
   await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'live_event_reward','live_event',$5,$6)",[c.playerId,currency,amount,wallet.balance,id,"live-event:"+id]);await db.query("COMMIT");return {ok:true,eventId:id,currency,amount,balance:wallet.balance,replayed:false};
  }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 });

 app.post("/event-shop-buy",{config:{rateLimit:{max:12,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const body=z.object({eventId:z.string().regex(/^event_[a-z0-9_]{1,60}$/)}).strict().safeParse(req.body);if(!body.success)return reply.code(400).send({error:"invalid_event_shop_request"});const id=body.data.eventId,db=await pool.connect();
  try{await db.query("BEGIN");const fail=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error});};
   const account=await db.query("SELECT id FROM accounts WHERE id=$1 AND status='active' AND token_version=$2 FOR UPDATE",[c.sub,c.tokenVersion]);const player=await db.query("SELECT id FROM players WHERE id=$1 AND account_id=$2 FOR UPDATE",[c.playerId,c.sub]);if(!account.rowCount||!player.rowCount)return await fail(401,"authentication_required");
   const prior=(await db.query("SELECT currency_id,delta::text,balance_after::text FROM currency_ledger WHERE player_id=$1 AND reason='live_event_shop' AND ref_type='live_event' AND ref_id=$2",[c.playerId,id])).rows[0];if(prior){await db.query("COMMIT");return {ok:true,eventId:id,currency:prior.currency_id,spent:-Number(prior.delta),replayed:true};}
   const event=activeEvents().find(e=>e.id===id);if(!event?.shop)return await fail(409,"event_shop_not_active");if(!(await eventProgress(db,c.playerId,event)).eligible)return await fail(409,"event_objective_incomplete");const {item,quantity,currency,price}=event.shop;
   if(!(await db.query("SELECT 1 FROM items WHERE id=$1 AND category='material'",[item])).rowCount)return await fail(409,"event_item_unavailable");
   const wallet=(await db.query("UPDATE player_currencies SET balance=balance-$3::bigint,updated_at=now() WHERE player_id=$1 AND currency_id=$2 AND balance >= $3::bigint RETURNING balance::text",[c.playerId,currency,price])).rows[0];if(!wallet)return await fail(409,"insufficient_currency");
   const grant=await db.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=inventory_items.quantity+EXCLUDED.quantity WHERE inventory_items.quantity<=9007199254740991-EXCLUDED.quantity RETURNING quantity::text",[c.playerId,item,quantity]);if(!grant.rowCount)return await fail(409,"inventory_limit");
   await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'live_event_shop','live_event',$5,$6)",[c.playerId,currency,-price,wallet.balance,id,"live-event-shop:"+id]);await db.query("COMMIT");return {ok:true,eventId:id,item,quantity,currency,spent:price,balance:wallet.balance,replayed:false};
  }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 });

 // Read-only, account-scoped history. Keyset cursor keeps older pages stable as new pulls arrive.
 const historyInput=z.object({limit:z.coerce.number().int().min(1).max(30).default(10),before:z.string().uuid().optional(),currency:z.enum(["crystals","paid_moonstones"]).optional()}).strict();
 app.get("/history",{config:{rateLimit:{max:60,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
  const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const owner=await pool.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3",[c.playerId,c.sub,c.tokenVersion]);
  if(!owner.rowCount)return reply.code(401).send({error:"authentication_required"});
  const parsed=historyInput.safeParse(req.query);if(!parsed.success)return reply.code(400).send({error:"invalid_history_query"});
  const {limit,before,currency}=parsed.data;
  if(before){
   const cursor=await pool.query("SELECT 1 FROM gacha_pulls WHERE player_id=$1 AND id=$2 AND ($3::text IS NULL OR currency_id=$3)",[c.playerId,before,currency??null]);
   if(!cursor.rowCount)return reply.code(400).send({error:"invalid_history_cursor"});
  }
  const page=await pool.query(`WITH selected AS (
   SELECT p.id,p.banner_id,p.pull_count,p.currency_id,p.cost::text,p.created_at,(SELECT manifest->'banner'->>'name' FROM content_versions WHERE id=p.content_version_id) AS recorded_banner_name
   FROM gacha_pulls p WHERE p.player_id=$1 AND ($2::text IS NULL OR p.currency_id=$2)
   AND ($3::uuid IS NULL OR (p.created_at,p.id)<(SELECT created_at,id FROM gacha_pulls WHERE player_id=$1 AND id=$3))
   ORDER BY p.created_at DESC,p.id DESC LIMIT $4
  ) SELECT s.*,COALESCE((SELECT jsonb_agg(jsonb_build_object('character_id',r.character_id,'rarity',r.rarity,'featured',r.featured,'is_new',r.is_new,'index',r.roll_index,'kind',r.reward_kind,'reward_items',r.reward_items,'paid_guaranteed',COALESCE(r.reward_items->'paid_guaranteed','false'::jsonb)) ORDER BY r.roll_index) FROM gacha_pull_results r WHERE r.pull_id=s.id),'[]'::jsonb) AS results FROM selected s ORDER BY s.created_at DESC,s.id DESC`,[c.playerId,currency??null,before??null,limit+1]);
  const more=page.rows.length>limit;
  const entries=page.rows.slice(0,limit).map(r=>({id:r.id,bannerId:r.banner_id,bannerName:r.recorded_banner_name??historicalBannerName(r.banner_id)??r.banner_id,count:r.pull_count,currency:r.currency_id,spent:r.cost,createdAt:r.created_at,results:r.results}));
  return {playerId:c.playerId,paidProgress:await paidProgress(pool,c.playerId),paidMilestone:PAID_MILESTONE,paidGuaranteePolicy:PAID_GUARANTEE_POLICY,entries,nextCursor:more?entries.at(-1)?.id??null:null};
 });

 // Historical audit never grants currency or characters. A review request is a
 // durable, idempotent support record, not an automatic compensation claim.
 app.get("/guarantee-audit",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
  const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const owner=await pool.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3",[c.playerId,c.sub,c.tokenVersion]);
  if(!owner.rowCount)return reply.code(401).send({error:"authentication_required"});
  return {playerId:c.playerId,...await auditPaidGuarantees(pool,c.playerId)};
 });
 app.post("/guarantee-review",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
  const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const body=z.object({pullId:z.string().uuid(),rollIndex:z.number().int().min(0).max(9)}).strict().safeParse(req.body);
  if(!body.success)return reply.code(400).send({error:"invalid_review_request"});
  const db=await pool.connect();
  try{
   await db.query("BEGIN");
   const account=await db.query("SELECT id FROM accounts WHERE id=$1 AND status='active' AND token_version=$2 FOR UPDATE",[c.sub,c.tokenVersion]);
   const owner=await db.query("SELECT id FROM players WHERE id=$1 AND account_id=$2 FOR UPDATE",[c.playerId,c.sub]);
   if(!account.rowCount||!owner.rowCount){await db.query("ROLLBACK");return reply.code(401).send({error:"authentication_required"});}
   const report=await auditPaidGuarantees(db,c.playerId);
   const entry=report.cases.find(r=>r.pullId===body.data.pullId&&r.rollIndex===body.data.rollIndex&&r.status!=="fulfilled");
   if(!entry){await db.query("ROLLBACK");return reply.code(404).send({error:"review_not_eligible"});}
   await db.query("INSERT INTO paid_guarantee_reviews(pull_id,roll_index) VALUES($1,$2) ON CONFLICT DO NOTHING",[entry.pullId,entry.rollIndex]);
   const saved=await db.query("SELECT status,requested_at FROM paid_guarantee_reviews WHERE pull_id=$1 AND roll_index=$2",[entry.pullId,entry.rollIndex]);
   await db.query("COMMIT");return {playerId:c.playerId,pullId:entry.pullId,rollIndex:entry.rollIndex,status:saved.rows[0].status,requestedAt:saved.rows[0].requested_at};
  }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 });

 const trainingInput=z.object({characterId:z.string().regex(/^[a-z0-9_]{1,80}$/),expectedLevel:z.number().int().min(1).max(80),expectedXp:z.number().int().min(0).max(10000),targetLevel:z.number().int().min(2).max(80).optional()}).strict();
 app.post("/train",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify()}catch{return reply.code(401).send({error:"authentication_required"})}
  const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const parsed=trainingInput.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_training"});
  const {characterId,expectedLevel,expectedXp,targetLevel}=parsed.data,db=await pool.connect();
  try{
   await db.query("BEGIN");
   const reject=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error})};
   const account=await db.query("SELECT id FROM accounts WHERE id=$1 AND status='active' AND token_version=$2 FOR UPDATE",[c.sub,c.tokenVersion]);
   const player=await db.query("SELECT id FROM players WHERE id=$1 AND account_id=$2 FOR UPDATE",[c.playerId,c.sub]);
   if(!account.rowCount||!player.rowCount)return await reject(401,"authentication_required");
   if(retiredPlayableIds.includes(characterId))return await reject(404,"character_not_owned");
   if(STARTER_PARTY.includes(characterId))await db.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,$2) ON CONFLICT DO NOTHING",[c.playerId,characterId]);
   const row=(await db.query("SELECT id,level,xp::text,ascension FROM owned_characters WHERE player_id=$1 AND char_id=$2 FOR UPDATE",[c.playerId,characterId])).rows[0];
   if(!row)return await reject(404,"character_not_owned");
   if(row.level!==expectedLevel||Number(row.xp)!==expectedXp)return await reject(409,"progression_changed_refresh");
   if(row.level>=20*(row.ascension+1))return await reject(409,"level_cap_reached");
   const target=targetLevel??row.level+1;
   if(target<=row.level||target>20*(row.ascension+1))return await reject(409,"invalid_training_target");
   const charges:number[]=[];
   for(let level=row.level;level<target;level++)charges.push(Math.max(1,xpToNext(level)-(level===row.level?expectedXp:0)));
   const cost=charges.reduce((sum,charge)=>sum+charge,0);
   const wallet=(await db.query("UPDATE player_currencies SET balance=balance-$2 WHERE player_id=$1 AND currency_id='gold' AND balance >= $2 RETURNING balance::text",[c.playerId,cost])).rows[0];
   if(!wallet)return await reject(409,"insufficient_gold");
   // One atomic wallet update, with per-level ledger entries for existing audit semantics.
   let remaining=BigInt(wallet.balance)+BigInt(cost);
   for(let i=0;i<charges.length;i++){
    const charge=charges[i]!;remaining-=BigInt(charge);
    await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',$2,$3,'character_training','character',$4,$5)",[c.playerId,-charge,remaining.toString(),row.id,"train:"+row.id+":"+(row.level+i)]);
   }
   await db.query("UPDATE owned_characters SET level=$2,xp=0 WHERE id=$1",[row.id,target]);
   await db.query("COMMIT");return {ok:true,characterId,level:target,levelsGained:target-row.level,goldSpent:cost,balance:wallet.balance};
  }catch(e){await db.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"training_unavailable"})}finally{db.release()}
 });
 const upgradeInput=z.object({characterId:z.string().regex(/^[a-z0-9_]{1,80}$/),action:z.enum(["ascend","awaken"]),expectedTier:z.number().int().min(0).max(5)}).strict();
 app.post("/upgrade",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
  const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const parsed=upgradeInput.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_upgrade"});
  const {characterId,action,expectedTier}=parsed.data;
  const db=await pool.connect();
  try{
   await db.query("BEGIN");
   const reject=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error});};
   const account=await db.query("SELECT id FROM accounts WHERE id=$1 AND status='active' AND token_version=$2 FOR UPDATE",[c.sub,c.tokenVersion]);
   const player=await db.query("SELECT id FROM players WHERE id=$1 AND account_id=$2 FOR UPDATE",[c.playerId,c.sub]);
   if(!account.rowCount||!player.rowCount)return await reject(401,"authentication_required");
   const id=c.playerId;
   if(retiredPlayableIds.includes(characterId))return await reject(404,"character_not_owned");
   if(["kael","gerald","lilith"].includes(characterId))await db.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,$2) ON CONFLICT DO NOTHING",[id,characterId]);
   const row=(await db.query("SELECT id,char_id,level,ascension,awakening,dupes FROM owned_characters WHERE player_id=$1 AND char_id=$2 FOR UPDATE",[id,characterId])).rows[0];
   if(!row)return await reject(404,"character_not_owned");
   const tier=action==="ascend"?row.ascension:row.awakening;
   if(tier!==expectedTier)return await reject(409,"progression_changed_refresh");
   if(action==="awaken"){
    if(tier>=5)return await reject(409,"maximum_awakening");
    if(row.dupes<2)return await reject(409,"insufficient_duplicates");
    await db.query("UPDATE owned_characters SET awakening=awakening+1,dupes=dupes-2 WHERE id=$1",[row.id]);
   }else{
    if(tier>=3)return await reject(409,"maximum_ascension");
    if(row.level!==20*(tier+1))return await reject(409,"level_cap_required");
    const gold=800*(tier+1),dew=tier+1,ref="ascend:"+row.id+":"+tier;
    const wallet=await db.query("UPDATE player_currencies SET balance=balance-$2 WHERE player_id=$1 AND currency_id='gold' AND balance >= $2 RETURNING balance::text",[id,gold]);
    if(!wallet.rowCount)return await reject(409,"insufficient_gold");
    const item=await db.query("UPDATE inventory_items SET quantity=quantity-$2 WHERE player_id=$1 AND item_id='dew_of_awakening' AND quantity >= $2 RETURNING quantity::text",[id,dew]);
    if(!item.rowCount)return await reject(409,"insufficient_dew");
    await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',$2,$3,'character_ascension','character',$4,$5)",[id,-gold,wallet.rows[0].balance,row.id,ref]);
    await db.query("INSERT INTO item_ledger(player_id,item_id,delta,quantity_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'dew_of_awakening',$2,$3,'character_ascension','character',$4,$5)",[id,-dew,item.rows[0].quantity,row.id,ref]);
    await db.query("UPDATE owned_characters SET ascension=ascension+1,level=level+1 WHERE id=$1",[row.id]);
   }
   const upgraded=(await db.query("SELECT char_id,level,ascension,awakening,dupes FROM owned_characters WHERE id=$1",[row.id])).rows[0];
   await db.query("COMMIT");return {ok:true,character:upgraded};
  }catch(e){await db.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"upgrade_unavailable"});}
  finally{db.release();}
 });
 // Exchange only copies in excess of the seven-star threshold.
 const exchangeInput=z.object({characterId:z.string().regex(/^[a-z0-9_]{1,80}$/),expectedCopies:z.number().int().min(8).max(1000000),quantity:z.number().int().min(1).max(999993).optional(),requestId:z.string().uuid()}).strict();
 app.post("/exchange-mythic-copies",{config:{rateLimit:{max:20,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify()}catch{return reply.code(401).send({error:"authentication_required"})}
  const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const parsed=exchangeInput.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_copy_exchange"});
  const {characterId,expectedCopies,requestId}=parsed.data;
  const quantity=parsed.data.quantity??expectedCopies-7;
  if(quantity>expectedCopies-7)return reply.code(400).send({error:"protected_copies"});
  const db=await pool.connect();
  try{
   await db.query("BEGIN");
   const reject=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error});};
   const account=await db.query("SELECT id FROM accounts WHERE id=$1 AND status='active' AND token_version=$2 FOR UPDATE",[c.sub,c.tokenVersion]);
   const player=await db.query("SELECT id FROM players WHERE id=$1 AND account_id=$2 FOR UPDATE",[c.playerId,c.sub]);
   if(!account.rowCount||!player.rowCount)return await reject(401,"authentication_required");
   if(!ascensionRecipe(characterId))return await reject(400,"mythic_only");
   const row=(await db.query("SELECT id,dupes,awakening FROM owned_characters WHERE player_id=$1 AND char_id=$2 FOR UPDATE",[c.playerId,characterId])).rows[0];
   if(!row)return await reject(404,"character_not_owned");
   const key="mythic-exchange:"+requestId;
   const old=(await db.query("SELECT delta::text,balance_after::text,ref_id FROM currency_ledger WHERE player_id=$1 AND idempotency_key=$2",[c.playerId,key])).rows[0];
   if(old){
    if(String(old.ref_id)!==String(row.id)||Number(old.delta)!==quantity*5000)return await reject(409,"exchange_request_mismatch");
    await db.query("COMMIT");return {ok:true,replayed:true,exchanged:Number(old.delta)/5000,goldGranted:Number(old.delta),balance:old.balance_after};
   }
   const copies=1+row.dupes+2*row.awakening;
   if(copies!==expectedCopies)return await reject(409,"progression_changed_refresh");
   if(copies<=7)return await reject(409,"no_extra_copies");
   const excess=quantity,reward=excess*5000;
   const wallet=(await db.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'gold',$2) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[c.playerId,reward])).rows[0];
   await db.query("UPDATE owned_characters SET awakening=3,dupes=$2 WHERE id=$1",[row.id,copies-7-excess]);
   await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',$2,$3,'mythic_copy_exchange','character',$4,$5)",[c.playerId,reward,wallet.balance,row.id,key]);
   await db.query("COMMIT");return {ok:true,exchanged:excess,goldGranted:reward,balance:wallet.balance};
  }catch(e){await db.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"exchange_unavailable"});}finally{db.release();}
 });
 const skillInput=z.object({characterId:z.string().regex(/^[a-z0-9_]{1,80}$/),skillId:z.string().regex(/^[a-z0-9_]{1,80}$/),expectedLevel:z.number().int().min(1).max(5)}).strict();
 app.post("/skill-upgrade",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
  const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const parsed=skillInput.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_skill_upgrade"});
  const {characterId,skillId,expectedLevel}=parsed.data;
  const def=Object.hasOwn(progressionCharacters,characterId)?progressionCharacters[characterId]:liveDefinition(characterId);
  const skill=Object.hasOwn(progressionSkills,skillId)?progressionSkills[skillId]:undefined;
  if(!def||!skill||retiredPlayableIds.includes(characterId)||![...(def.skills??[]),def.ultimate].includes(skillId)||!["damage","heal","shield","buff","debuff"].includes(skill.kind))return reply.code(400).send({error:"skill_not_available"});
  const db=await pool.connect();
  try{
   await db.query("BEGIN");
   const reject=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error});};
   const account=await db.query("SELECT id FROM accounts WHERE id=$1 AND status='active' AND token_version=$2 FOR UPDATE",[c.sub,c.tokenVersion]);
   const player=await db.query("SELECT id FROM players WHERE id=$1 AND account_id=$2 FOR UPDATE",[c.playerId,c.sub]);
   if(!account.rowCount||!player.rowCount)return await reject(401,"authentication_required");
   const id=c.playerId;
   if(["kael","gerald","lilith"].includes(characterId))await db.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,$2) ON CONFLICT DO NOTHING",[id,characterId]);
   const row=(await db.query("SELECT id,level,skill_levels FROM owned_characters WHERE player_id=$1 AND char_id=$2 FOR UPDATE",[id,characterId])).rows[0];
   if(!row)return await reject(404,"character_not_owned");
   const level=Number(row.skill_levels[skillId]??1);
   if(level!==expectedLevel)return await reject(409,"progression_changed_refresh");
   if(level>=5)return await reject(409,"maximum_skill_level");
   if(row.level<level*5)return await reject(409,"character_level_required");
   const gold=(skill.ultimate===true?150:100)*level,petals=level,ref="skill:"+row.id+":"+skillId+":"+level;
   const wallet=await db.query("UPDATE player_currencies SET balance=balance-$2 WHERE player_id=$1 AND currency_id='gold' AND balance >= $2 RETURNING balance::text",[id,gold]);
   if(!wallet.rowCount)return await reject(409,"insufficient_gold");
   const item=await db.query("UPDATE inventory_items SET quantity=quantity-$2 WHERE player_id=$1 AND item_id='moonpetal' AND quantity >= $2 RETURNING quantity::text",[id,petals]);
   if(!item.rowCount)return await reject(409,"insufficient_moonpetal");
   await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',$2,$3,'skill_upgrade','character',$4,$5)",[id,-gold,wallet.rows[0].balance,row.id,ref]);
   await db.query("INSERT INTO item_ledger(player_id,item_id,delta,quantity_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'moonpetal',$2,$3,'skill_upgrade','character',$4,$5)",[id,-petals,item.rows[0].quantity,row.id,ref]);
   await db.query("UPDATE owned_characters SET skill_levels=jsonb_set(skill_levels,ARRAY[$2],to_jsonb($3::int),true) WHERE id=$1",[row.id,skillId,level+1]);
   await db.query("COMMIT");return {ok:true,characterId,skillId,level:level+1};
  }catch(e){await db.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"skill_upgrade_unavailable"});}
  finally{db.release();}
 });
 const gearInput=z.object({characterId:z.string().regex(/^[a-z0-9_]{1,80}$/),slot:z.enum(["weapon","armor","accessory"]),action:z.enum(["equip","unequip","enhance","reroll"]),itemId:z.string().regex(/^[a-z0-9_]{0,80}$/),expectedItem:z.string().regex(/^[a-z0-9_]{0,80}$/),expectedLevel:z.number().int().min(0).max(8),expectedRerollStat:z.enum(["","hp","atk","def","spd","crit","crit_dmg"]).optional(),expectedRerollValue:z.number().min(0).max(10000).optional(),requestId:z.string().uuid()}).strict();
 app.post("/equipment",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
  const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const parsed=gearInput.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_equipment_request"});
  const {characterId,slot,action,itemId,expectedItem,expectedLevel,expectedRerollStat,expectedRerollValue,requestId}=parsed.data;
  const db=await pool.connect();
  try{
   await db.query("BEGIN");
   const reject=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error});};
   const account=await db.query("SELECT id FROM accounts WHERE id=$1 AND status='active' AND token_version=$2 FOR UPDATE",[c.sub,c.tokenVersion]);
   const player=await db.query("SELECT id FROM players WHERE id=$1 AND account_id=$2 FOR UPDATE",[c.playerId,c.sub]);
   if(!account.rowCount||!player.rowCount)return await reject(401,"authentication_required");
   const id=c.playerId;
   const previous=await db.query("SELECT payload=$3::jsonb AS same FROM equipment_actions WHERE player_id=$1 AND request_id=$2",[id,requestId,JSON.stringify(parsed.data)]);
   if(previous.rowCount){if(!previous.rows[0].same)return await reject(409,"request_id_conflict");await db.query("COMMIT");return {ok:true,replayed:true};}
   if(retiredPlayableIds.includes(characterId))return await reject(404,"character_not_owned");
   if(["kael","gerald","lilith"].includes(characterId))await db.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,$2) ON CONFLICT DO NOTHING",[id,characterId]);
   const owned=(await db.query("SELECT id FROM owned_characters WHERE player_id=$1 AND char_id=$2 FOR UPDATE",[id,characterId])).rows[0];
   if(!owned)return await reject(404,"character_not_owned");
   const current=(await db.query("SELECT item_id,enhancement_level,reroll_stat,reroll_value FROM character_equipment WHERE player_id=$1 AND character_id=$2 AND slot=$3 FOR UPDATE",[id,owned.id,slot])).rows[0];
   if((current?.item_id??"")!==expectedItem||Number(current?.enhancement_level??0)!==expectedLevel)return await reject(409,"equipment_changed_refresh");
   let serial=0;
   const changeItem=async(item:string,delta:number)=>{
    const q=delta>0?await db.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=inventory_items.quantity+EXCLUDED.quantity RETURNING quantity::text",[id,item,delta]):await db.query("UPDATE inventory_items SET quantity=quantity+$3 WHERE player_id=$1 AND item_id=$2 AND quantity >= -($3::bigint) RETURNING quantity::text",[id,item,delta]);
    if(!q.rowCount)return false;
    await db.query("INSERT INTO item_ledger(player_id,item_id,delta,quantity_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'equipment_action','character',$5,$6)",[id,item,delta,q.rows[0].quantity,owned.id,"equipment:"+requestId+":"+(serial++)]);
    return true;
   };
   if(action==="equip"||action==="unequip"){
    if(action==="equip"){
     const def=Object.hasOwn(progressionItems,itemId)?progressionItems[itemId]:undefined;
     if(!def||def.category!=="equipment"||def.slot!==slot)return await reject(400,"invalid_equipment_slot");
     if(current?.item_id===itemId)return await reject(409,"already_equipped");
     if(!await changeItem(itemId,-1))return await reject(409,"item_not_owned");
    }else if(!current)return await reject(409,"slot_empty");
    if(current){
     if(Number(current.enhancement_level)>0||current.reroll_stat!=null)await db.query("INSERT INTO stored_equipment_progress(player_id,item_id,enhancement_level,reroll_stat,reroll_value) VALUES($1,$2,$3,$4,$5)",[id,current.item_id,current.enhancement_level,current.reroll_stat,current.reroll_value]);
     await changeItem(current.item_id,1);
     await db.query("DELETE FROM character_equipment WHERE player_id=$1 AND character_id=$2 AND slot=$3",[id,owned.id,slot]);
    }
    if(action==="equip"){
     const stored=(await db.query("SELECT id,enhancement_level,reroll_stat,reroll_value FROM stored_equipment_progress WHERE player_id=$1 AND item_id=$2 ORDER BY enhancement_level DESC,(reroll_stat IS NOT NULL) DESC,id LIMIT 1 FOR UPDATE",[id,itemId])).rows[0];
     if(stored)await db.query("DELETE FROM stored_equipment_progress WHERE id=$1",[stored.id]);
     await db.query("INSERT INTO character_equipment(player_id,character_id,slot,item_id,enhancement_level,reroll_stat,reroll_value) VALUES($1,$2,$3,$4,$5,$6,$7)",[id,owned.id,slot,itemId,stored?.enhancement_level??0,stored?.reroll_stat??null,stored?.reroll_value??null]);
    }
   }else if(action==="reroll"){
    if(!current)return await reject(409,"slot_empty");
    const def=Object.hasOwn(progressionItems,current.item_id)?progressionItems[current.item_id]:undefined;
    if(!def||def.category!=="equipment"||def.slot!==slot)return await reject(400,"invalid_equipment_slot");
    if(expectedRerollStat===undefined||expectedRerollStat!==(current.reroll_stat??"")||expectedRerollValue===undefined||expectedRerollValue!==Number(current.reroll_value??0))return await reject(409,"equipment_changed_refresh");
    const stats=def.stats??{};
    let candidates=["hp","atk","def","spd","crit","crit_dmg"].filter(stat=>Number.isFinite(stats[stat])&&Number(stats[stat])>0);
    if(!candidates.length)return await reject(409,"no_rerollable_stats");
    if(candidates.length>1)candidates=candidates.filter(stat=>stat!==current.reroll_stat);
    const stat=candidates[randomInt(candidates.length)]!;
    const value=Number(Math.max(["crit","crit_dmg"].includes(stat)?0.001:1,Number(stats[stat])*0.10).toFixed(4));
    if(value>10000)return await reject(400,"invalid_equipment_stats");
    const wallet=await db.query("UPDATE player_currencies SET balance=balance-120 WHERE player_id=$1 AND currency_id='gold' AND balance>=120 RETURNING balance::text",[id]);
    if(!wallet.rowCount)return await reject(409,"insufficient_gold");
    if(!await changeItem("gothic_shard",-1))return await reject(409,"insufficient_gothic_shard");
    await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',-120,$2,'equipment_reroll','character',$3,$4)",[id,wallet.rows[0].balance,owned.id,"equipment:"+requestId]);
    await db.query("UPDATE character_equipment SET reroll_stat=$4,reroll_value=$5 WHERE player_id=$1 AND character_id=$2 AND slot=$3",[id,owned.id,slot,stat,value]);
   }else{
    if(!current)return await reject(409,"slot_empty");
    const def=Object.hasOwn(progressionItems,current.item_id)?progressionItems[current.item_id]:undefined;
    if(!def||def.category!=="equipment"||def.slot!==slot)return await reject(400,"invalid_equipment_slot");
    const level=Number(current.enhancement_level),cap=({common:3,uncommon:4,rare:5,epic:6,legendary:7,mythic:8} as Record<string,number>)[def.rarity??"common"]??5;
    if(level>=cap)return await reject(409,"maximum_enhancement");
    const gold=180*(level+1),sap=level+1,shards=Math.max(0,level-4);
    const wallet=await db.query("UPDATE player_currencies SET balance=balance-$2 WHERE player_id=$1 AND currency_id='gold' AND balance >= $2 RETURNING balance::text",[id,gold]);
    if(!wallet.rowCount)return await reject(409,"insufficient_gold");
    if(!await changeItem("glade_sap",-sap))return await reject(409,"insufficient_glade_sap");
    if(shards>0&&!await changeItem("gothic_shard",-shards))return await reject(409,"insufficient_gothic_shard");
    await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',$2,$3,'equipment_enhancement','character',$4,$5)",[id,-gold,wallet.rows[0].balance,owned.id,"equipment:"+requestId]);
    await db.query("UPDATE character_equipment SET enhancement_level=enhancement_level+1 WHERE player_id=$1 AND character_id=$2 AND slot=$3",[id,owned.id,slot]);
   }
   await db.query("INSERT INTO equipment_actions(player_id,request_id,payload) VALUES($1,$2,$3::jsonb)",[id,requestId,JSON.stringify(parsed.data)]);
   await db.query("COMMIT");return {ok:true,replayed:false};
  }catch(e){await db.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"equipment_unavailable"});}
  finally{db.release();}
 });
 const partyInput=z.object({characterIds:z.array(z.string().regex(/^[a-z0-9_]{1,80}$/)).min(1).max(4)}).strict();
 app.post("/party",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
  const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const parsed=partyInput.safeParse(req.body);
  if(!parsed.success||new Set(parsed.data.characterIds).size!==parsed.data.characterIds.length)return reply.code(400).send({error:"invalid_party"});
  const ids=parsed.data.characterIds;
  if(ids.some(id=>id.startsWith("livechar_"))&&req.headers["x-reverie-character-content"]!=="1")return reply.code(400).send({error:"compatible_client_required"});
  if(ids.some(id=>retiredPlayableIds.includes(id)||!Object.hasOwn(progressionCharacters,id)&&!liveDefinition(id)))return reply.code(400).send({error:"invalid_party_character"});
  const db=await pool.connect();
  try{
   await db.query("BEGIN");
   const reject=async(code:number,error:string)=>{await db.query("ROLLBACK");return reply.code(code).send({error});};
   const account=await db.query("SELECT id FROM accounts WHERE id=$1 AND status='active' AND token_version=$2 FOR UPDATE",[c.sub,c.tokenVersion]);
   const player=await db.query("SELECT id FROM players WHERE id=$1 AND account_id=$2 FOR UPDATE",[c.playerId,c.sub]);
   if(!account.rowCount||!player.rowCount)return await reject(401,"authentication_required");
   const id=c.playerId;
   if((await db.query("SELECT 1 FROM co_op_lobby_members m JOIN co_op_lobbies l ON l.id=m.lobby_id WHERE m.player_id=$1 AND l.status IN ('open','in_world')",[id])).rowCount)return await reject(409,"expedition_party_locked");
   if((await db.query("SELECT 1 FROM pvp_queue_tickets WHERE player_id=$1 AND status IN ('waiting','matched') AND expires_at>now()",[id])).rowCount)return await reject(409,"pvp_party_locked");
   if((await db.query("SELECT 1 FROM pvp_match_players p JOIN pvp_matches m ON m.id=p.match_id WHERE p.player_id=$1 AND m.status IN ('queued','active')",[id])).rowCount)return await reject(409,"pvp_party_locked");
   await db.query("INSERT INTO owned_characters(player_id,char_id) SELECT $1,unnest($2::text[]) ON CONFLICT DO NOTHING",[id,STARTER_PARTY]);
   const rows=await db.query("SELECT id,char_id FROM owned_characters WHERE player_id=$1 AND char_id=ANY($2::text[])",[id,ids]);
   if(rows.rowCount!==ids.length)return await reject(404,"character_not_owned");
   const mapping=new Map(rows.rows.map(r=>[r.char_id,r.id]));
   await db.query("DELETE FROM party_members WHERE player_id=$1",[id]);
   for(let i=0;i<ids.length;i++)await db.query("INSERT INTO party_members(player_id,slot,character_id) VALUES($1,$2,$3)",[id,i+1,mapping.get(ids[i]!)]);
   await db.query("COMMIT");return {ok:true,party:ids};
  }catch(e){await db.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"party_unavailable"});}
  finally{db.release();}
 });
 app.post("/pull",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
  try{await req.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
  const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({error:"authentication_required"});
  const parsed=input.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_summon"});
  const {bannerId,count,requestId}=parsed.data;
  const currency=parsed.data.currency??"crystals";
  const release=await summonAdmission.acquire(c.playerId);
  if(!release)return reply.code(503).header("Retry-After","2").send({error:"summon_server_busy"});
  const db=await pool.connect().catch(e=>{req.log.error(e);return null;});
  if(!db){release();return reply.code(503).send({error:"summon_unavailable"});}

  try{
   await db.query("BEGIN");
   const account=await db.query("SELECT id FROM accounts WHERE id=$1 AND status='active' AND token_version=$2 FOR UPDATE",[c.sub,c.tokenVersion]);
   const owner=await db.query("SELECT id FROM players WHERE id=$1 AND account_id=$2 FOR UPDATE",[c.playerId,c.sub]);
   if(!account.rowCount||!owner.rowCount){await db.query("ROLLBACK");return reply.code(401).send({error:"authentication_required"});}
   const id=c.playerId;
   const old=(await db.query("SELECT id,banner_id,pull_count,currency_id,cost,pity_after FROM gacha_pulls WHERE player_id=$1 AND idempotency_key=$2",[id,requestId])).rows[0];
   if(old){
    if(old.banner_id!==bannerId||old.pull_count!==count||old.currency_id!==currency){await db.query("ROLLBACK");return reply.code(409).send({error:"request_id_conflict"});}
    const previous=await db.query("SELECT character_id,rarity,featured,roll_index AS index,is_new,awakening_gain,reward_kind,reward_items FROM gacha_pull_results WHERE pull_id=$1 ORDER BY roll_index",[old.id]);
    const wallet=await db.query("SELECT balance::text FROM player_currencies WHERE player_id=$1 AND currency_id=$2",[id,old.currency_id]); const progress=await paidProgress(db,id);
    await db.query("COMMIT");return {ok:true,results:previous.rows.map(({reward_kind,reward_items,...r})=>reward_kind==="mob_reward"?{...r,kind:reward_kind,items:reward_items}:reward_kind==="upgrade_card"?{...r,kind:reward_kind,...reward_items}:{...describeRoll(r),...reward_items}),pity:old.pity_after,paidProgress:progress,spent:Number(old.cost),currency:old.currency_id,balance:wallet.rows[0]?.balance??"0",requestId,replayed:true};
   }
   // Resolve committed retries before checking a current schedule or revision.
   let catalog;try{catalog=currentBannerCatalog();}catch(e){req.log.error(e);await db.query("ROLLBACK");return reply.code(503).send({error:"summon_catalog_unavailable"});}
   const banner=catalog[bannerId];
   if(!banner){await db.query("ROLLBACK");return reply.code(400).send({error:"unknown_banner"});}
   if(banner.featured.some(id=>id.startsWith("livechar_"))&&req.headers["x-reverie-character-content"]!=="1"){await db.query("ROLLBACK");return reply.code(400).send({error:"compatible_client_required"});}
   if((bannerId.startsWith("live_")||parsed.data.catalogRevision!==undefined)&&parsed.data.catalogRevision!==banner.revision){await db.query("ROLLBACK");return reply.code(409).send({error:"banner_changed_refresh"});}
   if(currency!==PAID_CURRENCY&&currency!==banner.cost.currency){await db.query("ROLLBACK");return reply.code(400).send({error:"invalid_currency"});}
   // Paid live banners require historical compensation support before activation.
   if(bannerId.startsWith("live_")&&currency===PAID_CURRENCY){await db.query("ROLLBACK");return reply.code(400).send({error:"live_banner_crystals_only"});}
   // Replays resolve before this check: stale new paid requests must not spend.
   const totalBefore=await paidTotal(db,id);
   if(currency===PAID_CURRENCY&&parsed.data.expectedPaidTotal!==undefined&&parsed.data.expectedPaidTotal!==totalBefore){
    await db.query("ROLLBACK");return reply.code(409).send({error:"paid_progress_changed"});
   }
   const cost=banner.cost[count===10?"ten":"single"];
   if(!Number.isSafeInteger(cost)||cost<=0)throw new Error("invalid_banner_cost");
   const wallet=await db.query("UPDATE player_currencies SET balance=balance-$3 WHERE player_id=$1 AND currency_id=$2 AND balance >= $3 RETURNING balance::text",[id,currency,cost]);
   if(!wallet.rowCount){await db.query("ROLLBACK");return reply.code(409).send({error:"insufficient_currency"});}
   const balance=wallet.rows[0].balance;
   const pity=(await db.query<Pity>("SELECT legendary,featured,epic_streak FROM banner_pity WHERE player_id=$1 AND banner_id=$2 FOR UPDATE",[id,bannerId])).rows[0]??emptyPity();
   const paidBefore=Number(BigInt(totalBefore)%BigInt(PAID_MILESTONE));
   const outcome=rollBanner(banner,pity,count,undefined,currency===PAID_CURRENCY?paidBefore:undefined);
   await db.query("INSERT INTO owned_characters(player_id,char_id) SELECT $1,unnest($2::text[]) ON CONFLICT DO NOTHING",[id,["kael","gerald","lilith"]]);
   const results:Roll[]=[];
   for(const r of outcome.results){
    if(r.kind==="mob_reward"||r.kind==="upgrade_card"){
     const {guaranteed:_guaranteed,...stored}=r;results.push({...stored,is_new:false,awakening_gain:0});
     continue;
    }
    const added=await db.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING id",[id,r.character_id]);
    let gain=0;
    if(!added.rowCount){
     const row=(await db.query("SELECT dupes,awakening FROM owned_characters WHERE player_id=$1 AND char_id=$2 FOR UPDATE",[id,r.character_id])).rows[0];
     gain=row.dupes+1>=2&&row.awakening<5?1:0;
     await db.query("UPDATE owned_characters SET dupes=dupes+1-$3*2,awakening=awakening+$3 WHERE player_id=$1 AND char_id=$2",[id,r.character_id,gain]);
    }
    const {guaranteed:_guaranteed,...stored}=r; results.push({...stored,is_new:!!added.rowCount,awakening_gain:gain});
   }
   const pullContentId=bannerId.startsWith("live_")?"summon-live-"+banner.revision.slice(0,32):contentId;
   await db.query("INSERT INTO content_versions(id,manifest_hash,manifest) VALUES($1,$2,$3::jsonb) ON CONFLICT DO NOTHING",[pullContentId,bannerId.startsWith("live_")?banner.revision:contentHash,JSON.stringify(bannerId.startsWith("live_")?{kind:"summon",bannerId,banner}:{kind:"summon"})]);
   const hash=createHash("sha256").update(JSON.stringify(results)).digest("hex");
   const pull=(await db.query("INSERT INTO gacha_pulls(player_id,banner_id,content_version_id,pull_count,currency_id,cost,pity_before,pity_after,result_hash,idempotency_key) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id",[id,bannerId,pullContentId,count,currency,cost,JSON.stringify(pity),JSON.stringify(outcome.pity),hash,requestId])).rows[0].id;

   // Material rewards and summon history commit together. A replay returns
   // the stored result ID without repeating this inventory mutation.
   const materialDefs:Record<string,{name:string;rarity:string}>={
    moonpetal:{name:"Moonpetal",rarity:"rare"},dew_of_awakening:{name:"Dew of Awakening",rarity:"epic"},gothic_shard:{name:"Gothic Shard",rarity:"rare"}
   };
   for(const r of results){
    if(r.kind!=="mob_reward")continue;
    for(const [item,amount] of Object.entries(r.items??{})){
     const def=materialDefs[item];
     if(!def||!Number.isSafeInteger(amount)||amount<=0)throw new Error("invalid_mob_reward");
     await db.query("INSERT INTO items(id,display_name,category,rarity) VALUES($1,$2,'material',$3) ON CONFLICT(id) DO NOTHING",[item,def.name,def.rarity]);
     const stock=await db.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=inventory_items.quantity+EXCLUDED.quantity RETURNING quantity::text",[id,item,amount]);
     await db.query("INSERT INTO item_ledger(player_id,item_id,delta,quantity_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'gacha_mob_reward','gacha_pull',$5,$6)",[id,item,amount,stock.rows[0].quantity,pull,"summon:"+requestId+":"+r.index+":"+item]);
    }
   }
   for(const r of results){
    if(r.kind!=="upgrade_card")continue;
    let serial=0;
    const change=async(item:string,delta:number)=>{
     const def=upgradeCard(item);
     if(!def)throw new Error("unknown_upgrade_card");
     await db.query("INSERT INTO items(id,display_name,category,rarity) VALUES($1,$2,'material',$3) ON CONFLICT(id) DO NOTHING",[item,def.name+" "+def.rarity+" Card",def.rarity]);
     const row=delta>0
      ? await db.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=inventory_items.quantity+EXCLUDED.quantity RETURNING quantity::text",[id,item,delta])
      : await db.query("UPDATE inventory_items SET quantity=quantity+$3 WHERE player_id=$1 AND item_id=$2 AND quantity>=-($3::bigint) RETURNING quantity::text",[id,item,delta]);
     if(!row.rowCount)throw new Error("insufficient_upgrade_cards");
     await db.query("INSERT INTO item_ledger(player_id,item_id,delta,quantity_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'gacha_card_fusion','gacha_pull',$5,$6)",[id,item,delta,row.rows[0].quantity,pull,"card:"+requestId+":"+r.index+":"+(serial++)]);
     return Number(row.rows[0].quantity);
    };
    let current=r.character_id;
    let count=await change(current,1);
    r.fusions=[];
    for(let step=0;step<2;step++){
     const card=upgradeCard(current);
     if(!card)break;
     while(count>=card.cost){
      count=await change(current,-card.cost);
      const next=upgradeCard(card.target);
      if(next){
       await change(card.target,1);
       r.fusions.push({id:card.target,name:next.name+" Epic Card"});
      }else{
       const added=await db.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING id",[id,card.target]);
       if(!added.rowCount){
        const owned=(await db.query("SELECT dupes,awakening FROM owned_characters WHERE player_id=$1 AND char_id=$2 FOR UPDATE",[id,card.target])).rows[0];
        const gain=owned.dupes+1>=2&&owned.awakening<5?1:0;
        await db.query("UPDATE owned_characters SET dupes=dupes+1-$3*2,awakening=awakening+$3 WHERE player_id=$1 AND char_id=$2",[id,card.target,gain]);
       }
       r.fusions.push({id:card.target,name:card.name+" Legendary",is_new:!!added.rowCount});
      }
     }
     if(step===0)r.card_count=count;
     // Only cascade into Epic if this step actually created a card.
     if(!upgradeCard(card.target)||!r.fusions.some(f=>f.id===card.target))break;
     current=card.target;
     count=Number((await db.query("SELECT quantity::text FROM inventory_items WHERE player_id=$1 AND item_id=$2",[id,current])).rows[0]?.quantity??0);
    }
   }
   for(const r of results){
    const acquisitions=r.rarity==="legendary"&&!r.kind?[r.character_id]:(r.fusions??[]).map(f=>f.id);
    let serial=0;
    for(const legendary of acquisitions){
     const recipe=mythicRecipe(legendary);
     if(!recipe)continue;
     const change=async(delta:number)=>{
      await db.query("INSERT INTO items(id,display_name,category,rarity) VALUES($1,$2,'material','legendary') ON CONFLICT(id) DO NOTHING",[recipe.item,legendary+" Mythic Progress"]);
      const q=delta>0?await db.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=inventory_items.quantity+EXCLUDED.quantity RETURNING quantity::text",[id,recipe.item,delta]):await db.query("UPDATE inventory_items SET quantity=quantity+$3 WHERE player_id=$1 AND item_id=$2 AND quantity>=-($3::bigint) RETURNING quantity::text",[id,recipe.item,delta]);
      if(!q.rowCount)throw new Error("insufficient_mythic_progress");
      await db.query("INSERT INTO item_ledger(player_id,item_id,delta,quantity_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'mythic_fusion','gacha_pull',$5,$6)",[id,recipe.item,delta,q.rows[0].quantity,pull,"mythic:"+requestId+":"+r.index+":"+(serial++)]);
      return Number(q.rows[0].quantity);
     };
     let count=await change(1);
     while(count>=recipe.cost){
      count=await change(-recipe.cost);
      const added=await db.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING id",[id,recipe.target]);
      if(!added.rowCount){
       const owned=(await db.query("SELECT dupes,awakening FROM owned_characters WHERE player_id=$1 AND char_id=$2 FOR UPDATE",[id,recipe.target])).rows[0];
       const gain=owned.dupes+1>=2&&owned.awakening<5?1:0;
       await db.query("UPDATE owned_characters SET dupes=dupes+1-$3*2,awakening=awakening+$3 WHERE player_id=$1 AND char_id=$2",[id,recipe.target,gain]);
      }
      (r.fusions??=[]).push({id:recipe.target,name:recipe.target.replace(/_/g," "),is_new:!!added.rowCount});
     }
     if(r.rarity==="legendary")r.mythic_count=count;
    }
    if(r.mythic_count!==undefined)r.fusions??=[];
   }
   for(const r of results){
    const acquisitions=r.rarity==="mythic"&&!r.kind?[r.character_id]:(r.fusions??[]).map(f=>f.id);
    let serial=0;
    for(const mythic of acquisitions){
     const recipe=ascensionRecipe(mythic);
     if(!recipe)continue;
     await db.query("INSERT INTO items(id,display_name,category,rarity) VALUES($1,$2,'material','mythic') ON CONFLICT(id) DO NOTHING",[recipe.item,mythic+" Ascension Progress"]);
     const q=await db.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,1) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=inventory_items.quantity+1 WHERE inventory_items.quantity<$3 RETURNING quantity::text",[id,recipe.item,recipe.cost]);
     const count=q.rowCount?Number(q.rows[0].quantity):recipe.cost;
     if(q.rowCount){
      await db.query("INSERT INTO item_ledger(player_id,item_id,delta,quantity_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,1,$3,'mythic_ascension','gacha_pull',$4,$5)",[id,recipe.item,count,pull,"ascension:"+requestId+":"+r.index+":"+(serial++)]);
      if(count===recipe.cost){
       await db.query("UPDATE owned_characters SET ascension=3 WHERE player_id=$1 AND char_id=$2",[id,mythic]);
       (r.fusions??=[]).push({id:mythic,name:mythic.replace(/_/g," ")+" - Fully Ascended",fully_ascended:true});
      }
     }
     if(count>=recipe.cost)await db.query("UPDATE owned_characters SET ascension=3 WHERE player_id=$1 AND char_id=$2 AND ascension<3",[id,mythic]);
     if(r.rarity==="mythic")r.ascended_count=count;
    }
    if(r.ascended_count!==undefined)r.fusions??=[];
   }
   const storedRows=results.map(r=>({roll_index:r.index,character_id:r.character_id,rarity:r.rarity,featured:r.featured,is_new:r.is_new,awakening_gain:r.awakening_gain,reward_kind:r.kind??"character",reward_items:r.kind==="upgrade_card"?{items:r.items,card_count:r.card_count,fusions:r.fusions}:r.kind==="mob_reward"?r.items??{}:{...(r.mythic_count!==undefined||r.ascended_count!==undefined?{mythic_count:r.mythic_count,ascended_count:r.ascended_count,fusions:r.fusions}:{}),...(r.paid_guaranteed?{paid_guaranteed:true}:{})}}));
   await db.query("INSERT INTO gacha_pull_results(pull_id,roll_index,character_id,rarity,featured,is_new,awakening_gain,reward_kind,reward_items) SELECT $1,r.* FROM jsonb_to_recordset($2::jsonb) AS r(roll_index integer,character_id text,rarity text,featured boolean,is_new boolean,awakening_gain integer,reward_kind text,reward_items jsonb)",[pull,JSON.stringify(storedRows)]);
   await db.query("UPDATE gacha_pulls SET result_hash=$2 WHERE id=$1",[pull,createHash("sha256").update(JSON.stringify(results)).digest("hex")]);
   await db.query("INSERT INTO banner_pity(player_id,banner_id,legendary,featured,epic_streak) VALUES($1,$2,$3,$4,$5) ON CONFLICT(player_id,banner_id) DO UPDATE SET legendary=EXCLUDED.legendary,featured=EXCLUDED.featured,epic_streak=EXCLUDED.epic_streak",[id,bannerId,outcome.pity.legendary,outcome.pity.featured,outcome.pity.epic_streak]);
   await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'gacha_pull','gacha_pull',$5,$6)",[id,currency,-cost,balance,pull,"summon:"+requestId]);
   await db.query("COMMIT");
   return {ok:true,results,pity:outcome.pity,paidProgress:(paidBefore+(currency===PAID_CURRENCY?count:0))%PAID_MILESTONE,spent:cost,currency,balance,requestId,replayed:false};
  }catch(e){await db.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"summon_unavailable"});}
  finally{try{db.release();}finally{release();}}
 });
};
