import Fastify from "fastify";
import helmet from "@fastify/helmet";
import jwt from "@fastify/jwt";
import rateLimit from "@fastify/rate-limit";
import websocket from "@fastify/websocket";
import {config} from "./config.js";
import {pool} from "./db.js";
import {startWorldEventRetention,WORLD_EVENT_RETENTION_SQL,WORLD_POSITION_RETENTION_SQL} from "./world/world-event-retention.js";
import {authRoutes} from "./routes/auth.js";
import {coopRoutes} from "./routes/coop.js";
import {chatRoutes} from "./routes/chat.js";
import {guildRoutes} from "./routes/guilds.js";
import {socialRoutes} from "./routes/social.js";
import {summonRoutes} from "./routes/summon.js";
import {shopRoutes} from "./routes/shop.js";
import {paymentReviewRoutes} from "./routes/payment-review.js";
import {dailyQuestRoutes,playerTitles} from "./routes/daily-quests.js";
import {finalizeDueSeasons,startSeasonFinalizer} from "./world/season-rewards.js";
import {finalizeDueGuildSeasons} from "./world/guild-league-rewards.js";
import {pvpQueueRoutes} from "./routes/pvp-queue.js";
import {pvpMatchRoutes} from "./routes/pvp-match.js";
import {realtimeRoutes} from "./routes/realtime.js";
import {gameServerRoutes} from "./routes/game-servers.js";
import {persistentWorldRealtimeRoutes} from "./routes/persistent-world-realtime.js";
import {moderationRoutes} from "./routes/moderation.js";
import {staffRoutes} from "./routes/staff.js";
import {developerRoutes} from "./routes/developer.js";
import {ownerRewardRoutes} from "./routes/owner-rewards.js";
import {scanServerIncidents,startServerIncidentMonitor} from "./world/server-incidents.js";
import {attachOperationalMetrics,startOperationalSampling} from "./world/operational-metrics.js";
import {createSharedRateLimitStore,startSharedRateLimitCleanup} from "./world/shared-rate-limit.js";
import {compensationRoutes} from "./routes/compensation.js";
import {tutorialSparRoutes} from "./routes/tutorial-spar.js";
import {geraldStoryPilotRoutes} from "./routes/gerald-story-pilot.js";
import {gardensStoryPilotRoutes} from "./routes/gardens-story-pilot.js";
import {royalGateStoryPilotRoutes} from "./routes/royal-gate-story-pilot.js";
import {storyProgressionRoutes} from "./routes/story-progression.js";
import {trustLocalProxy} from "./world/proxy-trust.js";
import {alphaRateKey,installAlphaAccess} from "./world/alpha-access.js";
const app=Fastify({logger:true,trustProxy:config.TRUST_LOCAL_REVERSE_PROXY==="1"?trustLocalProxy:false,bodyLimit:16384});
attachOperationalMetrics(app);
await app.register(helmet);
await app.register(rateLimit,{max:100,timeWindow:"1 minute",skipOnError:false,keyGenerator:req=>alphaRateKey(app,req),
 ...(config.SHARED_RATE_LIMIT_NAMESPACE?{store:createSharedRateLimitStore(pool,config.SHARED_RATE_LIMIT_NAMESPACE,config.JWT_SECRET)}:{})});
await app.register(jwt,{secret:config.JWT_SECRET,sign:{expiresIn:config.ACCESS_TOKEN_TTL_SECONDS}});
await app.register(websocket);
installAlphaAccess(app);
await app.register(authRoutes,{prefix:"/v1/auth"});
await app.register(coopRoutes,{prefix:"/v1/co-op"});
await app.register(chatRoutes,{prefix:"/v1/chat"});
await app.register(guildRoutes,{prefix:"/v1/guilds"});
await app.register(socialRoutes,{prefix:"/v1/social"});
await app.register(summonRoutes,{prefix:"/v1/summon"});
await app.register(shopRoutes,{prefix:"/v1/shop"});
await app.register(paymentReviewRoutes,{prefix:"/v1/developer/payments"});
await app.register(dailyQuestRoutes,{prefix:"/v1/daily-quests"});
await app.register(pvpQueueRoutes,{prefix:"/v1/pvp"});
await app.register(pvpMatchRoutes,{prefix:"/v1/pvp/matches"});
await app.register(realtimeRoutes,{prefix:"/v1"});
await app.register(gameServerRoutes,{prefix:"/v1/game-servers"});
await app.register(persistentWorldRealtimeRoutes,{prefix:"/v1"});
await app.register(storyProgressionRoutes,{prefix:"/v1/progression"});
await app.register(tutorialSparRoutes,{prefix:"/v1/tutorial-spar"});
if(config.NODE_ENV!=="production"&&process.env.REVERIE_GERALD_STORY_PILOT==="1")await app.register(geraldStoryPilotRoutes,{prefix:"/v1/gerald-story"});
if(config.NODE_ENV!=="production"&&process.env.REVERIE_GARDENS_STORY_PILOT==="1")await app.register(gardensStoryPilotRoutes,{prefix:"/v1/gardens-story"});
if(config.NODE_ENV!=="production"&&process.env.REVERIE_GARDENS_STORY_PILOT==="1")await app.register(royalGateStoryPilotRoutes,{prefix:"/v1/royal-gate-story"});
await app.register(developerRoutes);
await app.register(ownerRewardRoutes(),{prefix:"/v1/developer/rewards"});
await app.register(staffRoutes,{prefix:"/v1/developer/staff"});
await app.register(moderationRoutes,{prefix:"/v1/developer/moderation"});
await app.register(compensationRoutes,{prefix:"/v1/developer/compensation"});
app.get("/health",async(_req,reply)=>{try{await pool.query("SELECT 1");return{status:"ok",service:"reverie-online-api",database:"ok"};}catch{return reply.code(503).send({status:"degraded",database:"unavailable"});}});
// Private readiness check: the proxy must not expose this path publicly.
app.get("/ready",{config:{rateLimit:false}},async(req,reply)=>{
 reply.header("Cache-Control","no-store");
 if(!trustLocalProxy(req.raw.socket.remoteAddress??"",0)||req.headers["x-forwarded-for"]!==undefined)return reply.code(404).send({error:"not_found"});
 try{
  await pool.query(Object.assign({text:config.SHARED_RATE_LIMIT_NAMESPACE?"SELECT 1 FROM api_rate_limit_buckets LIMIT 0":"SELECT 1"},{query_timeout:3000}));
  return {status:"ready"};
 }catch{return reply.code(503).send({status:"not_ready"});}
});
let stopSeasonFinalizer:(()=>Promise<void>)|undefined;
let stopGuildLeagueFinalizer:(()=>Promise<void>)|undefined;
let stopWorldEventRetention:(()=>Promise<void>)|undefined;
let stopServerIncidents:(()=>Promise<void>)|undefined;
let stopOperationalSampling:(()=>Promise<void>)|undefined;
let stopRateLimitCleanup:(()=>Promise<void>)|undefined;
app.addHook("onClose",async()=>{await stopSeasonFinalizer?.();await stopGuildLeagueFinalizer?.();await stopWorldEventRetention?.();await stopServerIncidents?.();await stopOperationalSampling?.();await stopRateLimitCleanup?.();await pool.end();});
app.addHook("onReady",async()=>{
 if(config.SHARED_RATE_LIMIT_NAMESPACE)stopRateLimitCleanup=startSharedRateLimitCleanup(pool,config.SHARED_RATE_LIMIT_NAMESPACE,error=>app.log.warn({err:error},"Shared quota cleanup failed"));
 stopOperationalSampling=startOperationalSampling(pool,15000,config.OPERATIONAL_HISTORY_INSTANCE_ID?{instanceId:config.OPERATIONAL_HISTORY_INSTANCE_ID,onError:error=>app.log.warn({err:error},"Operational history persistence failed")}:undefined);
 if(config.SERVER_INCIDENT_MONITOR_ENABLED==="1"){
  stopServerIncidents=startServerIncidentMonitor(()=>scanServerIncidents(pool),result=>{
   for(const incident of result.opened)app.log.warn({incident},"Regional server incident opened");
   for(const incident of result.resolved)app.log.info({incident},"Regional server incident cleared");
  },error=>app.log.error({err:error},"Regional incident scan failed; will retry"));
 }

 if(config.WORLD_EVENT_RETENTION_ENABLED==="1"){
  stopWorldEventRetention=startWorldEventRetention(
   async()=>(await (config.WORLD_POSITION_RETENTION_HOURS===720
    ?pool.query(WORLD_EVENT_RETENTION_SQL)
    :pool.query(WORLD_POSITION_RETENTION_SQL,[config.WORLD_POSITION_RETENTION_HOURS]))).rowCount??0,
   rows=>app.log.info({rows},"Expired persistent world events removed"),
   error=>app.log.warn({err:error},"World event retention failed; will retry"));
 }
 stopGuildLeagueFinalizer=startSeasonFinalizer(finalizeDueGuildSeasons,seasons=>app.log.info({seasons},"Guild league finalized"),error=>app.log.error({err:error},"Guild league finalization failed; will retry"));
 stopSeasonFinalizer=startSeasonFinalizer(()=>finalizeDueSeasons(playerTitles.map(t=>t.id)),seasons=>app.log.info({seasons},"Season standings finalized"),error=>app.log.error({err:error},"Season finalization failed; will retry"));
});
try{await app.listen({host:config.HOST,port:config.PORT});}catch(e){app.log.error(e);process.exit(1);}
