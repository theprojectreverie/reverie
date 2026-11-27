import type {FastifyPluginAsync,FastifyReply,FastifyRequest} from "fastify";
import {z} from "zod";
import {config} from "../config.js";
import {pool} from "../db.js";
import {createAlphaDashboard} from "../world/alpha-dashboard.js";
import {staffActivityAccess,staffOwners} from "./staff.js";
import {moderationAccess,suspensionAccess} from "./moderation.js";
import {liveContentAdmin} from "./live-content-admin.js";
import {liveContentHtml,liveContentScript} from "./live-content-dashboard.js";
import {readBackupHealth} from "../world/backup-health.js";
import {operationalSnapshot,readOperationalHistory} from "../world/operational-metrics.js";

type Claims={sub?:string;playerId?:string;tokenVersion?:number};
type Queryable={query:(sql:string,values?:unknown[])=>Promise<{rows:Array<Record<string,unknown>>}>};
type DashboardOptions={developerAccountIds:string;database:Queryable;staffAccess?:(id:string)=>Promise<boolean>;incidentMonitoring?:boolean;metrics?:()=>ReturnType<typeof operationalSnapshot>|Promise<ReturnType<typeof operationalSnapshot>&{persistentHistory?:boolean}>;backupHealth?:()=>ReturnType<typeof readBackupHealth>;alphaSnapshot?:ReturnType<typeof createAlphaDashboard>};
const accountId=z.string().uuid();

export function createDeveloperRoutes({developerAccountIds,database,staffAccess,incidentMonitoring=false,metrics,backupHealth,alphaSnapshot}:DashboardOptions):FastifyPluginAsync{
 const allowedAccounts=new Set(developerAccountIds.split(",").map(value=>value.trim()).filter(value=>accountId.safeParse(value).success));
 return async app=>{
  await app.register(liveContentAdmin(staffOwners,database));
  app.get("/developer",async(_request,reply)=>reply.type("text/html; charset=utf-8").header("Cache-Control","no-store").header("Content-Security-Policy","default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src data:; form-action 'self'; base-uri 'none'; frame-ancestors 'none'").send(dashboardHtml));
  // Infrastructure visibility is restricted to configured developers and owners;
  // activity-only staff roles do not grant infrastructure permissions.
  app.get("/v1/developer/server-health",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(request:FastifyRequest,reply:FastifyReply)=>{
   reply.header("Cache-Control","no-store");
   let claims:Claims;
   try{await request.jwtVerify();claims=request.user as Claims;}catch{return reply.code(401).send({error:"authentication_required"});}
   if(!accountId.safeParse(claims.sub).success||!accountId.safeParse(claims.playerId).success||!Number.isInteger(claims.tokenVersion))return reply.code(401).send({error:"authentication_required"});
   if(!allowedAccounts.has(claims.sub!)&&!staffOwners.has(claims.sub!))return reply.code(403).send({error:"server_health_access_required"});
   const session=await database.query("SELECT a.token_version,a.status FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=$1 AND p.id=$2",[claims.sub,claims.playerId]);
   if(session.rows[0]?.status!=="active"||session.rows[0]?.token_version!==claims.tokenVersion)return reply.code(401).send({error:"session_revoked"});
   const result=await database.query(`WITH health AS (
    SELECT s.id,s.display_name,s.region_id,s.status,s.build_version,s.max_players,
     CASE WHEN s.heartbeat_at IS NULL THEN NULL ELSE GREATEST(0,floor(extract(epoch FROM (now()-s.heartbeat_at))))::int END AS heartbeat_seconds,
     (SELECT count(*)::int FROM game_server_players p WHERE p.server_id=s.id) AS reserved,
     (SELECT count(DISTINCT c.player_id)::int FROM game_server_player_connections c WHERE c.server_id=s.id AND c.lease_expires_at>now()) AS connected,
     CASE WHEN s.status='starting' AND s.started_at>now()-interval '60 seconds' THEN 'starting'
      WHEN s.status IN ('online','starting','draining') AND (s.heartbeat_at IS NULL OR s.heartbeat_at<=now()-interval '60 seconds') THEN 'stale'
      WHEN s.status='online' AND s.endpoint_url IS NULL THEN 'unavailable'
      ELSE s.status END AS health
    FROM game_servers s
   ), marked AS (
    SELECT *,CASE WHEN health='online' AND reserved>=max_players THEN 'full'
     WHEN health='online' AND reserved>=max_players*0.8 THEN 'capacity' ELSE health END AS state FROM health
   )
   SELECT count(*)::int AS total,
    count(*) FILTER(WHERE health='online')::int AS online,
    count(*) FILTER(WHERE health IN ('stale','unavailable'))::int AS unhealthy,
    count(*) FILTER(WHERE state IN ('capacity','full'))::int AS pressured,
    COALESCE(sum(max_players) FILTER(WHERE health='online'),0)::int AS slots,
    COALESCE(sum(reserved) FILTER(WHERE health='online'),0)::int AS reserved,
    COALESCE(sum(connected) FILTER(WHERE health IN ('online','draining')),0)::int AS connected,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('name',display_name,'region',region_id,'status',status,'state',state,'build',build_version,'capacity',max_players,'reserved',reserved,'connected',connected,'heartbeatSeconds',heartbeat_seconds) ORDER BY priority,region_id,display_name,id) FROM
     (SELECT *,CASE WHEN state IN ('stale','unavailable','full','capacity') THEN 0 WHEN state IN ('online','starting','draining') THEN 1 ELSE 2 END AS priority FROM marked ORDER BY priority,region_id,display_name,id LIMIT 200) visible),'[]'::jsonb) AS servers
   FROM marked`);
   const r=result.rows[0]??{};
   const history=incidentMonitoring?(await database.query(`SELECT
     (SELECT count(*)::int FROM regional_server_incidents WHERE resolved_at IS NULL) AS open_count,
     COALESCE((SELECT jsonb_agg(jsonb_build_object('id',i.id::text,'name',s.display_name,'region',s.region_id,'kind',i.kind,'initialReason',i.initial_reason,'reason',i.current_reason,'openedAt',i.opened_at,'resolvedAt',i.resolved_at,'resolution',i.resolution,'acknowledgedAt',i.acknowledged_at,'acknowledgmentNote',i.acknowledgment_note) ORDER BY (i.resolved_at IS NOT NULL),i.opened_at DESC,i.id DESC)
     FROM (SELECT * FROM regional_server_incidents ORDER BY (resolved_at IS NOT NULL),opened_at DESC,id DESC LIMIT 50) i JOIN game_servers s ON s.id=i.server_id),'[]'::jsonb) AS incidents`)).rows[0]:null;
   return {alpha:alphaSnapshot?await alphaSnapshot().catch(()=>null):null,backupHealth:await backupHealth?.()??{status:"not_configured"},metrics:await metrics?.()??null,incidentMonitoring,openIncidents:Number(history?.open_count??0),incidents:history?.incidents??[],total:Number(r.total??0),online:Number(r.online??0),unhealthy:Number(r.unhealthy??0),pressured:Number(r.pressured??0),slots:Number(r.slots??0),reserved:Number(r.reserved??0),connected:Number(r.connected??0),servers:r.servers??[],asOf:new Date().toISOString()};
  });
  app.post("/v1/developer/server-incidents/:id/acknowledge",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(request:FastifyRequest,reply:FastifyReply)=>{
   reply.header("Cache-Control","no-store");
   let claims:Claims;
   try{await request.jwtVerify();claims=request.user as Claims;}catch{return reply.code(401).send({error:"authentication_required"});}
   if(!accountId.safeParse(claims.sub).success||!accountId.safeParse(claims.playerId).success||!Number.isInteger(claims.tokenVersion))return reply.code(401).send({error:"authentication_required"});
   if(!allowedAccounts.has(claims.sub!)&&!staffOwners.has(claims.sub!))return reply.code(403).send({error:"server_health_access_required"});
   const session=await database.query("SELECT a.token_version,a.status FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=$1 AND p.id=$2",[claims.sub,claims.playerId]);
   if(session.rows[0]?.status!=="active"||session.rows[0]?.token_version!==claims.tokenVersion)return reply.code(401).send({error:"session_revoked"});
   if(!incidentMonitoring)return reply.code(503).send({error:"incident_monitoring_disabled"});
   const params=z.object({id:z.string().regex(/^[1-9][0-9]{0,18}$/).refine(v=>BigInt(v)<=9223372036854775807n)}).safeParse(request.params);
   const body=z.object({note:z.string().trim().min(3).max(300)}).strict().safeParse(request.body);
   if(!params.success||!body.success)return reply.code(400).send({error:"invalid_acknowledgment"});
   // Recheck account session inside the write, and leave resolved_at untouched.
   const updated=await database.query(`UPDATE regional_server_incidents i SET acknowledged_at=now(),acknowledged_by=$2,acknowledgment_note=$3
     WHERE i.id=$1::bigint AND i.resolved_at IS NULL AND i.acknowledged_at IS NULL
     AND EXISTS(SELECT 1 FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=$2 AND p.id=$4 AND a.status='active' AND a.token_version=$5)
     RETURNING i.id::text,i.acknowledged_at`,[params.data.id,claims.sub,body.data.note,claims.playerId,claims.tokenVersion]);
   if(!updated.rows.length)return reply.code(409).send({error:"incident_not_open_or_already_acknowledged"});
   return {id:updated.rows[0]!.id,acknowledgedAt:updated.rows[0]!.acknowledged_at};
  });
  app.get("/v1/developer/activity",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(request:FastifyRequest,reply:FastifyReply)=>{
   let claims:Claims;
   try{await request.jwtVerify();claims=request.user as Claims;}catch{return reply.code(401).send({error:"authentication_required"});}
   if(!claims.sub||!claims.playerId||!Number.isInteger(claims.tokenVersion))return reply.code(401).send({error:"authentication_required"});
   if(!allowedAccounts.has(claims.sub)&&!(staffAccess&&accountId.safeParse(claims.sub).success&&await staffAccess(claims.sub)))return reply.code(403).send({error:"developer_access_required"});
   const session=await database.query("SELECT token_version,status FROM accounts WHERE id=$1",[claims.sub]);
   if(session.rows[0]?.status!=="active"||session.rows[0]?.token_version!==claims.tokenVersion)return reply.code(401).send({error:"session_revoked"});
   const result=await database.query(
    `WITH activity_signals AS (
      SELECT player_id,region_id,1 AS source_priority
      FROM player_presence
      WHERE state<>'offline' AND last_heartbeat_at>now()-interval '45 seconds'
      UNION ALL
      SELECT c.player_id,s.region_id,2 AS source_priority
      FROM game_server_player_connections c
      JOIN game_servers s ON s.id=c.server_id
      WHERE c.lease_expires_at>now() AND s.status='online' AND s.heartbeat_at>now()-interval '60 seconds'
     ), active_players AS (
      SELECT DISTINCT ON(player_id) player_id,region_id
      FROM activity_signals
      ORDER BY player_id,source_priority,region_id
     ), zone_counts AS (
      SELECT region_id,count(*)::int AS players
      FROM active_players WHERE region_id IS NOT NULL
      GROUP BY region_id
     )
     SELECT (SELECT count(*)::int FROM active_players) AS online_players,
       COALESCE((SELECT jsonb_agg(jsonb_build_object('regionId',region_id,'players',players) ORDER BY players DESC,region_id) FROM zone_counts),'[]'::jsonb) AS zones`);
   const row=result.rows[0]??{};
   const progression=await database.query(
    `WITH daily AS (
      SELECT player_id,victories,shared_victories,claimed FROM online_daily_quests
      WHERE quest_day>=((CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date-29)
     ), weekly AS (
      SELECT player_id,claimed FROM online_weekly_quests
      WHERE week_start>=((CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date-29)
     ), region_arrivals AS (
      SELECT s.region_id,count(DISTINCT e.player_id)::int AS players
      FROM game_server_world_events e JOIN game_servers s ON s.id=e.server_id
      WHERE e.event_type='player_joined' AND e.player_id IS NOT NULL AND e.created_at>now()-interval '30 days'
      GROUP BY s.region_id
     ), milestone_totals AS (
      SELECT milestone_id,count(*)::int AS players FROM story_milestone_reaches GROUP BY milestone_id
     )
     SELECT
      (SELECT jsonb_build_object('checkin',count(*) FILTER(WHERE 'checkin'=ANY(claimed)),'victories',count(*) FILTER(WHERE 'victories'=ANY(claimed)),'shared',count(*) FILTER(WHERE 'shared'=ANY(claimed)),'bonus',count(*) FILTER(WHERE 'bonus'=ANY(claimed))) FROM daily) AS daily_claims,
      (SELECT count(DISTINCT player_id)::int FROM daily WHERE cardinality(claimed)>0) AS daily_players,
      (SELECT COALESCE(sum(victories),0)::int FROM daily) AS expedition_victory_credits,
      (SELECT COALESCE(sum(shared_victories),0)::int FROM daily) AS shared_victory_days,
      (SELECT jsonb_build_object('checkins',count(*) FILTER(WHERE 'checkins'=ANY(claimed)),'victories',count(*) FILTER(WHERE 'victories'=ANY(claimed)),'shared',count(*) FILTER(WHERE 'shared'=ANY(claimed)),'bonus',count(*) FILTER(WHERE 'bonus'=ANY(claimed))) FROM weekly) AS weekly_claims,
      (SELECT count(DISTINCT player_id)::int FROM weekly WHERE cardinality(claimed)>0) AS weekly_players,
      COALESCE((SELECT jsonb_agg(jsonb_build_object('regionId',region_id,'players',players) ORDER BY players DESC,region_id) FROM region_arrivals),'[]'::jsonb) AS region_arrivals,
      COALESCE((SELECT jsonb_agg(jsonb_build_object('milestoneId',milestone_id,'players',COALESCE(t.players,0)) ORDER BY ordinal) FROM (VALUES ('village',1),('royal_gardens',2),('royal_gate',3),('willow_fields',4),('elderwood_grove',5),('forsaken_ruins',6),('ruined_tower',7),('chapter_complete',8)) AS m(milestone_id,ordinal) LEFT JOIN milestone_totals t USING(milestone_id)),'[]'::jsonb) AS story_milestones,
      (SELECT min(reached_at) FROM story_milestone_reaches) AS story_coverage_since`);
   const history=progression.rows[0]??{};
   return reply.header("Cache-Control","no-store").send({
    onlinePlayers:Number(row.online_players??0),zones:row.zones??[],serverHealthAccess:allowedAccounts.has(claims.sub)||staffOwners.has(claims.sub),staffManagement:staffOwners.has(claims.sub),liveContentManagement:staffOwners.has(claims.sub),moderation:staffAccess?await moderationAccess(claims.sub):false,suspensions:staffAccess?await suspensionAccess(claims.sub):false,
    progression:{windowDays:30,dailyClaims:history.daily_claims??{},dailyPlayers:Number(history.daily_players??0),expeditionVictoryCredits:Number(history.expedition_victory_credits??0),sharedVictoryDays:Number(history.shared_victory_days??0),weeklyClaims:history.weekly_claims??{},weeklyPlayers:Number(history.weekly_players??0),regionArrivals:history.region_arrivals??[],storyMilestones:history.story_milestones??[],storyCoverageSince:history.story_coverage_since??null},
    asOf:new Date().toISOString()
   });
  });
 };
}

export const developerRoutes=createDeveloperRoutes({alphaSnapshot:config.PUBLIC_ALPHA_MONITOR_ENABLED==="1"?createAlphaDashboard(pool):undefined,developerAccountIds:config.DEVELOPER_ACCOUNT_IDS,staffAccess:staffActivityAccess,incidentMonitoring:config.SERVER_INCIDENT_MONITOR_ENABLED==="1",backupHealth:()=>readBackupHealth(config.BACKUP_HEALTH_REPORT_PATH),metrics:async()=>{
 const snapshot=operationalSnapshot(pool),id=config.OPERATIONAL_HISTORY_INSTANCE_ID;
 if(!id)return {...snapshot,persistentHistory:false};
 try{return {...snapshot,history:await readOperationalHistory(pool,id),persistentHistory:true};}
 catch{return {...snapshot,persistentHistory:false};}
},database:{query:(sql,values)=>pool.query(sql,values)}});

const dashboardHtml=`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"><title>Reverie · Developer activity</title>
<style>
:root{font-family:Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;color:#f3eee8;background:#111316;font-synthesis:none}*{box-sizing:border-box}body{margin:0;min-height:100vh;background:radial-gradient(ellipse at 78% -12%,#3e3045 0,transparent 42%),#111316}.shell{max-width:1050px;margin:auto;padding:48px 28px}.top{display:flex;align-items:center;gap:14px;margin-bottom:70px}.mark{width:42px;height:42px;border-radius:14px;background:linear-gradient(145deg,#f2c988,#b77a56);display:grid;place-items:center;color:#211b1d;font-size:23px}.eyebrow,.label{color:#a7a0a6;text-transform:uppercase;letter-spacing:.13em;font-size:11px}.brand{font-size:15px;font-weight:650;letter-spacing:.06em}.intro{max-width:680px;margin-bottom:38px}.intro .eyebrow{color:#d7aa77}.intro h1{font-size:clamp(34px,6vw,54px);letter-spacing:-.045em;margin:13px 0 12px;font-weight:600}.intro p{color:#aaa5a7;line-height:1.65;margin:0}.grid{display:grid;grid-template-columns:1fr 1.45fr;gap:18px}.card{background:#1b1d21;border:1px solid #303136;border-radius:18px;padding:25px;box-shadow:0 18px 50px #0002}.label{font-size:10px}.count{font-size:76px;line-height:1.1;letter-spacing:-.06em;margin-top:24px;font-variant-numeric:tabular-nums}.hint,.meta{color:#88858b;font-size:12px;margin-top:8px}.zone-head{display:flex;justify-content:space-between;align-items:center}.zone-list{list-style:none;margin:24px 0 0;padding:0;display:grid;gap:18px}.zone-row{display:grid;grid-template-columns:minmax(110px,1fr) 2fr 35px;gap:14px;align-items:center;font-size:13px}.zone-name{color:#ded9d6;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.bar{height:7px;background:#313137;border-radius:9px;overflow:hidden}.fill{height:100%;background:linear-gradient(90deg,#bd8b68,#e5c190);border-radius:9px;transition:width .35s}.zone-count{text-align:right;color:#b9b2ad;font-variant-numeric:tabular-nums}.footer{display:flex;justify-content:space-between;align-items:center;margin-top:20px}.button,.submit{border:1px solid #51464c;background:#262327;color:#e8ddd5;border-radius:9px;padding:9px 13px;cursor:pointer;font:inherit;font-size:12px}.button:hover,.submit:hover{background:#373037}.status{font-size:12px;color:#aaa5a7}.signin{max-width:440px;margin:45px auto}.signin h2{font-size:22px;margin:0 0 7px}.signin p{font-size:13px;line-height:1.6;color:#aaa5a7;margin:0 0 24px}.field{display:grid;gap:7px;margin:14px 0}.field label{font-size:12px;color:#c5bdba}.field input{background:#111316;color:#f3eee8;border:1px solid #39383d;border-radius:9px;padding:12px;font:inherit;outline:none}.field input:focus{border-color:#b98f70}.submit{width:100%;margin-top:6px;background:#775747;border-color:#8b6653;padding:11px}.error{min-height:18px;color:#ef9b91;font-size:12px;margin-top:12px}.hidden{display:none}@media(max-width:700px){.shell{padding:30px 18px}.top{margin-bottom:52px}.grid{grid-template-columns:1fr}.count{font-size:64px}.zone-row{grid-template-columns:minmax(95px,1fr) 1.4fr 30px}}
</style></head><body><main class="shell"><header class="top"><div class="mark">✳</div><div><div class="brand">REVERIE</div><div class="eyebrow">Developer console</div></div></header>
<section id="signin" class="card signin"><h2>Sign in to activity</h2><p>Use a developer account configured for this server. This dashboard shows anonymous, aggregate activity only.</p><form id="login"><div class="field"><label for="name">Player name</label><input id="name" autocomplete="username" required minlength="3"></div><div class="field"><label for="password">Password</label><input id="password" type="password" autocomplete="current-password" required></div><button class="submit">Sign in</button><div id="error" class="error" role="status"></div></form></section>
<section id="dashboard" class="hidden"><div class="intro"><div class="eyebrow">Live world pulse</div><h1>Players in Reverie</h1><p>A quiet, real time view of who's exploring and where the world is gathering.</p></div><div class="grid"><article class="card"><div class="label">Currently online</div><div id="online" class="count">—</div><div class="hint">Unique active player sessions</div></article><article class="card"><div class="zone-head"><div class="label">Multiplayer zones</div><div class="label">Players</div></div><ul id="zones" class="zone-list"></ul><div id="empty" class="hint">No active zone activity yet.</div></article></div>
<section style="margin-top:54px"><div class="intro" style="margin-bottom:24px"><div class="eyebrow">Server records · last 30 days</div><h2 style="font-size:28px;letter-spacing:-.035em;margin:10px 0">Quest activity &amp; regional reach</h2><p>Reward claims and region arrivals the backend can verify.</p></div><div class="grid"><article class="card"><div class="label">Online quest progression</div><div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin:18px 0"><div style="padding:13px;background:#151619;border-radius:12px"><div id="victory-credits" style="font-size:25px;font-variant-numeric:tabular-nums">—</div><div class="hint">Expedition victory credits</div></div><div style="padding:13px;background:#151619;border-radius:12px"><div id="shared-days" style="font-size:25px;font-variant-numeric:tabular-nums">—</div><div class="hint">Shared-victory days</div></div><div style="padding:13px;background:#151619;border-radius:12px"><div id="daily-players" style="font-size:25px;font-variant-numeric:tabular-nums">—</div><div class="hint">Players claiming daily rewards</div></div><div style="padding:13px;background:#151619;border-radius:12px"><div id="weekly-players" style="font-size:25px;font-variant-numeric:tabular-nums">—</div><div class="hint">Players claiming weekly rewards</div></div></div><div style="display:grid;grid-template-columns:1fr 1fr;gap:16px"><div><div class="label">Daily claims</div><ul class="zone-list" style="margin:12px 0 0;gap:8px"><li class="zone-row" style="grid-template-columns:1fr 32px"><span class="zone-name">Adventurer's Check-in</span><span id="daily-checkin" class="zone-count">0</span></li><li class="zone-row" style="grid-template-columns:1fr 32px"><span class="zone-name">Expedition Duty</span><span id="daily-victories" class="zone-count">0</span></li><li class="zone-row" style="grid-template-columns:1fr 32px"><span class="zone-name">United Front</span><span id="daily-shared" class="zone-count">0</span></li><li class="zone-row" style="grid-template-columns:1fr 32px"><span class="zone-name">Daily Devotion</span><span id="daily-bonus" class="zone-count">0</span></li></ul></div><div><div class="label">Weekly claims</div><ul class="zone-list" style="margin:12px 0 0;gap:8px"><li class="zone-row" style="grid-template-columns:1fr 32px"><span class="zone-name">Faithful Adventurer</span><span id="weekly-checkins" class="zone-count">0</span></li><li class="zone-row" style="grid-template-columns:1fr 32px"><span class="zone-name">Expedition Veteran</span><span id="weekly-victories" class="zone-count">0</span></li><li class="zone-row" style="grid-template-columns:1fr 32px"><span class="zone-name">Together We Stand</span><span id="weekly-shared" class="zone-count">0</span></li><li class="zone-row" style="grid-template-columns:1fr 32px"><span class="zone-name">Weekly Devotion</span><span id="weekly-bonus" class="zone-count">0</span></li></ul></div></div><div class="hint" style="margin-top:18px">A claim is recorded only after the server confirms its reward. Victory credits are written with the server-owned expedition payout.</div></article><article class="card"><div class="zone-head"><div class="label">Distinct players entering each zone</div><div class="label">Players</div></div><ul id="region-arrivals" class="zone-list"></ul><div id="region-arrivals-empty" class="hint">No retained region arrivals in this window.</div><div class="hint" style="margin-top:18px">Counts come from durable player-joined events in the last 30 days; retained history may be shorter.</div></article></div><div class="card" style="margin-top:18px"><div class="zone-head"><div class="label">Story milestone funnel · post-update observations</div><div class="label">Unique players</div></div><ul id="story-milestones" class="zone-list" style="margin-top:18px"></ul><div id="story-milestones-empty" class="hint">No signed-in milestone reaches recorded yet.</div><div id="story-coverage" class="hint" style="margin-top:14px">Coverage starts with post-update transitions; existing saves are not backfilled.</div><div class="hint" style="margin-top:8px">Counts are independent first reaches, not a matched cohort. Returning saves may first appear at a later stage. Fewer reaches do not confirm abandonment; offline and unsigned play are not included.</div><div class="hint" style="margin-top:8px">Chapter completion is recorded when the player confirms the ending.</div></div></section>
<section id="player-directory" class="card hidden" style="margin-top:30px"><div class="eyebrow">Staff player directory</div><h2>Find a player</h2><p class="hint">Search by the beginning of a player name (at least three characters). Account and disciplinary information only.</p><form id="player-search-form"><div class="field"><label for="player-search">Player name</label><input id="player-search" minlength="3" maxlength="20" required></div><button class="button" id="player-search-submit">Search players</button></form><p id="player-search-status" class="status" role="status"></p><div id="player-search-results"></div><div id="player-detail" style="overflow-wrap:anywhere"></div></section>
<section id="mod-panel" class="card hidden" style="margin-top:30px"><div class="eyebrow">Staff moderation</div><h2>World chat and player discipline</h2><p class="hint">Public world messages only. Private messages are not visible here. Moderators can warn and mute for up to 24 hours; admins and owners can mute for up to 7 days and unmute. Staff accounts are protected.</p><button id="mod-load" class="button">Refresh moderation</button><h3>Recent public chat</h3><div id="mod-messages" style="max-height:320px;overflow:auto;overflow-wrap:anywhere"></div><form id="mod-form"><div class="field"><label for="mod-name">Exact player name</label><input id="mod-name" required maxlength="32"></div><div class="field"><label for="mod-action">Action</label><select id="mod-action" style="background:#111316;color:#f3eee8;padding:10px"><option value="warn">Warning</option><option value="mute">Timed mute</option><option value="unmute">Unmute (admin / owner)</option></select></div><div class="field"><label for="mod-minutes">Mute duration (minutes)</label><input id="mod-minutes" type="number" min="5" max="10080" value="30" required></div><div class="field"><label for="mod-reason">Reason (8-300 characters, visible to player)</label><input id="mod-reason" minlength="8" maxlength="300" required></div><button id="mod-submit" class="button">Apply moderation action</button></form><p id="mod-status" class="status" role="status"></p><h3>Active mutes</h3><div id="mod-mutes"></div><h3>Player reports</h3><p class="hint">Reported public messages are preserved as evidence. Reviewing a report does not automatically punish the player.</p><div class="field"><label for="report-filter">Review status</label><select id="report-filter" style="background:#111316;color:#f3eee8;padding:10px"><option value="pending">Pending</option><option value="resolved">Resolved</option><option value="dismissed">Dismissed</option></select></div><button id="report-load" class="button">Load reports</button><p id="report-status" class="status" role="status"></p><div id="report-list" style="overflow-wrap:anywhere"></div><h3>Recent moderation history</h3><div id="mod-audit" style="overflow-wrap:anywhere"></div></section>
<section id="server-health-panel" class="card hidden" style="margin-top:30px"><div class="eyebrow">Infrastructure ? read only</div><h2>Online gameplay infrastructure</h2><h3>Worldwide alpha gateway</h3><div id="alpha-network" class="status" style="white-space:pre-line;line-height:1.8;overflow-wrap:anywhere"></div><div id="alpha-enrollment" class="status" style="white-space:pre-line;line-height:1.8;margin-top:12px"></div><div id="alpha-realtime" class="status" style="white-space:pre-line;line-height:1.8;margin-top:12px"></div><p class="hint">Public HTTPS is tested from this host, not from an independent internet connection. Socket counts cover authenticated public co-op connections in this API process, not every signed-in player. Enrollment limit is not simultaneous capacity. Invite-only alpha; paid purchases, paid summons and persistent regional worlds are restricted.</p><h3 style="margin-top:28px">Regional server health (separate pilot)</h3><p class="hint">Registry and live lease snapshots. A stale heartbeat does not establish a process crash. Offline servers may be intentionally retired.</p><div id="server-health-summary" class="status" style="margin:16px 0"></div><p id="server-health-status" class="status" role="status"></p><div id="server-health-rows" style="display:grid;gap:10px"></div><h3 style="margin-top:28px">API and database performance</h3><div id="operational-metrics" class="status" style="line-height:1.8;white-space:pre-line"></div><p class="hint">Single API process, rolling HTTP window of approximately 60 seconds. Latency values are histogram upper bounds, not player movement latency.</p><h3 style="margin-top:28px">Performance history</h3><p class="hint">Last hour on this API instance. Samples every 15 seconds. Gaps indicate missing observations, not zero latency.</p><p id="performance-history-mode" class="hint"></p><div id="performance-history" style="display:grid;gap:14px"></div><h3 style="margin-top:28px">Backup health</h3><div id="backup-health" class="status" role="status" style="white-space:pre-line;line-height:1.8"></div><p class="hint">Independent verification report. A verified replica does not establish that it is offsite or that a full restore has succeeded.</p><h3 style="margin-top:28px">Incident history</h3><p id="incident-summary" class="status" role="status"></p><div id="incident-rows" style="display:grid;gap:10px"></div><p class="hint">Observed conditions, not confirmed crashes. Closed incidents may indicate a server was intentionally taken offline. Latest 50 records, open incidents first.</p></section>
<section id="suspension-panel" class="card hidden" style="margin-top:30px"><div class="eyebrow">Admin / owner only</div><h2>Temporary account suspensions</h2><p class="hint">Revokes sign-in sessions and restricts online gameplay. Admins may suspend up to 7 days; the owner up to 30 days. Staff and existing bans are protected. Players may sign in again after expiry.</p><form id="suspension-form"><div class="field"><label for="suspension-name">Exact player name</label><input id="suspension-name" required minlength="3" maxlength="32"></div><div class="field"><label for="suspension-action">Action</label><select id="suspension-action" style="background:#111316;color:#f3eee8;padding:10px"><option value="suspend">Suspend temporarily</option><option value="lift">Lift suspension</option></select></div><div class="field"><label for="suspension-minutes">Duration (minutes)</label><input id="suspension-minutes" type="number" value="60" min="5" max="43200" required></div><div class="field"><label for="suspension-reason">Reason (8-300 characters, shown to player)</label><input id="suspension-reason" required minlength="8" maxlength="300"></div><button id="suspension-submit" class="button">Apply account action</button></form><p id="suspension-status" class="status" role="status"></p><button id="suspension-load" class="button">Load suspension history</button><div id="suspension-list" style="overflow-wrap:anywhere"></div><h3>Suspension appeals</h3><p class="hint">Independent review only. Approval lifts the original active suspension. Review notes are visible to the player while suspended.</p><div class="field"><label for="appeal-filter">Appeal status</label><select id="appeal-filter" style="background:#111316;color:#f3eee8;padding:10px"><option value="pending">Pending</option><option value="approved">Approved</option><option value="rejected">Rejected</option><option value="closed">Closed</option></select></div><button id="appeal-load" class="button">Load appeals</button><p id="appeal-status" class="status" role="status"></p><div id="appeal-list" style="overflow-wrap:anywhere"></div></section>
${liveContentHtml}
<section id="rewards-panel" class="card hidden" style="margin-top:30px"><div class="eyebrow">Owner only</div><h2>Player rewards and currency grants</h2><p class="hint">Select an exact player, check the wallet, and confirm a positive grant. Administrative credits are not purchases. Paid summoning remains restricted in public alpha. Limit: 1,000,000 per grant.</p><form id="reward-search"><div class="field"><label for="reward-name">Player name (at least 3 characters)</label><input id="reward-name" minlength="3" maxlength="32" required></div><button class="button">Search wallets</button></form><div id="reward-players" style="display:grid;gap:8px;margin:12px 0"></div><p id="reward-selected" class="status"></p><form id="reward-form"><div class="field"><label for="reward-currency">Currency</label><select id="reward-currency"><option value="crystals">Summoning Crystals (free Moonstones)</option><option value="gems">Gems</option><option value="paid_moonstones">Paid Moonstones</option><option value="gold">Gold</option></select></div><div class="field"><label for="reward-amount">Amount</label><input id="reward-amount" type="number" min="1" max="1000000" required></div><div class="field"><label for="reward-note">Reason (8-300 characters)</label><input id="reward-note" minlength="8" maxlength="300" required></div><button id="reward-submit" class="button" disabled>Confirm grant</button></form><p id="reward-status" class="status" role="status"></p><button id="reward-history-load" class="button">Load grant history</button><button id="reward-history-next" class="button" disabled>Older grants</button><div id="reward-history" style="display:grid;gap:10px;overflow-wrap:anywhere"></div></section>
<section id="staff-panel" class="card hidden" style="margin-top:30px"><div class="eyebrow">Owner only</div><h2>Staff management</h2><p class="hint">Assign access to existing Reverie accounts. Analysts can view activity. Moderators and admins can also moderate world chat. Financial privileges are separate.</p><form id="staff-form"><div class="field"><label for="staff-name">Exact player name</label><input id="staff-name" required minlength="3" maxlength="32"></div><div class="field"><label for="staff-role">Role</label><select id="staff-role" style="background:#111316;color:#f3eee8;padding:10px;border:1px solid #39383d;border-radius:9px"><option value="analyst">Analyst</option><option value="moderator">Moderator</option><option value="admin">Admin</option><option value="revoke">Revoke access</option></select></div><div class="field"><label for="staff-note">Reason (8-300 characters)</label><input id="staff-note" required minlength="8" maxlength="300"></div><button id="staff-submit" class="button">Apply role change</button></form><p id="staff-status" class="status" role="status"></p><button id="staff-load" class="button">Load staff and audit history</button><h3>Staff accounts</h3><div id="staff-roles" style="overflow-wrap:anywhere"></div><h3>Recent permission changes</h3><div id="staff-audit" style="overflow-wrap:anywhere"></div><h3>Staff activity statistics</h3><p class="hint">Completed actions in the selected period, including former staff with retained actions. Counts are not performance scores. Appeal approval counts once, not as a separate manual lift. Automatic expiry is excluded.</p><div class="field"><label for="staff-stat-days">Period</label><select id="staff-stat-days" style="background:#111316;color:#f3eee8;padding:10px"><option value="7">Last 7 days</option><option value="30" selected>Last 30 days</option><option value="90">Last 90 days</option></select></div><button id="staff-stat-load" class="button">Load activity statistics</button><p id="staff-stat-status" class="status" role="status"></p><div id="staff-stat-list" style="overflow-wrap:anywhere"></div></section>
<div class="footer"><div id="updated" class="status">Waiting for the first update…</div><a class="button" href="/v1/developer/compensation/dashboard">Compensation reviews</a><button id="refresh" class="button">Refresh now</button><button id="logout" class="button">Sign out</button></div></section></main>
<script>
let token=null,refreshToken=null,expiresAt=0,timer=null,generation=0,busy=false;const signin=document.querySelector('#signin'),dashboard=document.querySelector('#dashboard'),error=document.querySelector('#error');
function pretty(id){return id.replace(/^six_zone_/,'').replaceAll('_',' ').replace(/\\b\\w/g,c=>c.toUpperCase())}
const STORY_LABELS={village:'Village',royal_gardens:'Royal Gardens',royal_gate:'Royal Gate',willow_fields:'Willow Fields',elderwood_grove:'Elderwood Grove',forsaken_ruins:'Forsaken Ruins',ruined_tower:'Ruined Tower',chapter_complete:'Chapter Complete'};
function renderZoneBars(selector,emptySelector,zones){const list=document.querySelector(selector);list.replaceChildren();document.querySelector(emptySelector).classList.toggle('hidden',zones.length>0);const max=Math.max(1,...zones.map(z=>z.players));for(const z of zones){const li=document.createElement('li');li.className='zone-row';const name=document.createElement('span');name.className='zone-name';name.textContent=pretty(z.regionId);const bar=document.createElement('div');bar.className='bar';const fill=document.createElement('div');fill.className='fill';fill.style.width=(100*z.players/max)+'%';bar.append(fill);const count=document.createElement('span');count.className='zone-count';count.textContent=z.players;li.append(name,bar,count);list.append(li)}}
function renderStoryMilestones(p){const rows=p.storyMilestones??[],list=document.querySelector('#story-milestones');list.replaceChildren();const total=rows.reduce((sum,row)=>sum+Number(row.players),0);const max=Math.max(1,...rows.map(row=>Number(row.players)));document.querySelector('#story-milestones-empty').classList.toggle('hidden',total>0);for(const row of rows){const li=document.createElement('li');li.className='zone-row';li.style.gridTemplateColumns='minmax(105px,1fr) 2fr 40px';const name=document.createElement('span');name.className='zone-name';name.textContent=STORY_LABELS[row.milestoneId]??'Story milestone';const bar=document.createElement('div');bar.className='bar';const fill=document.createElement('div');fill.className='fill';fill.style.width=(100*Number(row.players)/max)+'%';bar.append(fill);const count=document.createElement('span');count.className='zone-count';count.textContent=Number(row.players);li.append(name,bar,count);list.append(li)}const coverage=p.storyCoverageSince?new Date(p.storyCoverageSince).toLocaleDateString():'No reaches recorded yet';document.querySelector('#story-coverage').textContent='Coverage since first reported reach: '+coverage+'. No pre-update saves are backfilled.'}
function renderProgression(p){document.querySelector('#victory-credits').textContent=p.expeditionVictoryCredits;document.querySelector('#shared-days').textContent=p.sharedVictoryDays;document.querySelector('#daily-players').textContent=p.dailyPlayers;document.querySelector('#weekly-players').textContent=p.weeklyPlayers;for(const key of ['checkin','victories','shared','bonus']){document.querySelector('#daily-'+key).textContent=p.dailyClaims[key]??0;document.querySelector('#weekly-'+(key==='checkin'?'checkins':key)).textContent=p.weeklyClaims[key==='checkin'?'checkins':key]??0}renderZoneBars('#region-arrivals','#region-arrivals-empty',p.regionArrivals);renderStoryMilestones(p)}
function renderPerformanceHistory(samples){
 const container=document.querySelector('#performance-history');container.replaceChildren();
 if(!samples.length){const empty=document.createElement('p');empty.className='hint';empty.textContent='No samples recorded yet.';container.append(empty);return}
 const end=Date.parse(samples[samples.length-1].at),start=end-3600000;
 for(const [label,key,unit] of [['HTTP p95 upper bound','p95UpperMs','ms'],['Database round trip','databaseMs','ms'],['Requests per rolling minute','requests',''],['Server errors per rolling minute','serverErrors',''],['Pool waiting','waiting',''],['API resident memory','residentMiB','MiB']]){
  const group=document.createElement('div'),caption=document.createElement('div');caption.className='hint';
  const values=samples.filter(s=>s[key]!==null&&Number.isFinite(s[key])),max=Math.max(1,...values.map(s=>s[key]));
  const last=samples[samples.length-1][key];caption.textContent=label+' ? latest '+(last===null?'unavailable':last+' '+unit)+' ? scale 0?'+max+' '+unit;
  const plot=document.createElement('div');plot.style.position='relative';plot.style.height='56px';plot.style.background='#151619';plot.style.borderRadius='6px';
  plot.setAttribute('aria-label',label+' over last hour');plot.setAttribute('role','img');
  for(const s of values){const mark=document.createElement('span');mark.style.position='absolute';mark.style.left=Math.max(0,Math.min(99.5,100*(Date.parse(s.at)-start)/3600000))+'%';mark.style.bottom='0';mark.style.width='0.45%';mark.style.height=Math.max(2,100*s[key]/max)+'%';mark.style.background='#c49a70';mark.title=new Date(s.at).toLocaleTimeString()+' ? '+s[key]+' '+unit;plot.append(mark)}
  group.append(caption,plot);container.append(group);
 }
}
function renderAlpha(a){
 const label=p=>({open:'OPEN',closed:'STATUS ONLY / CLOSED',unavailable:'UNREACHABLE',unknown:'UNRECOGNIZED RESPONSE'}[p?.state]??'UNKNOWN')+(p?' | '+p.durationMs+' ms | checked '+new Date(p.checkedAt).toLocaleTimeString():'');
 document.querySelector('#alpha-network').textContent=a?['Public HTTPS: '+label(a.network.public),'Local restricted gateway: '+label(a.network.local)].join('\\n'):'Alpha monitoring unavailable or not configured.';
 document.querySelector('#alpha-enrollment').textContent=a?['Enrolled accounts: '+a.enrollment.enrolled+' ('+a.enrollment.active+' active)','Unused valid invitations: '+a.enrollment.unused,'Consumed invitations: '+a.enrollment.consumed,'Remaining invitation allocation: '+a.enrollment.remaining+' / '+a.enrollment.issuanceLimit].join('\\n'):'';
 document.querySelector('#alpha-realtime').textContent=a?['Public co-op WebSocket connections: '+a.realtime.connections,'Distinct connected players: '+a.realtime.players+' | connected lobbies: '+a.realtime.lobbies,'Enrolled players with recent presence (45s): '+a.recentPresence+' | associated lobbies: '+a.recentLobbies].join('\\n'):'';
}
function renderServerHealth(d){
 renderAlpha(d.alpha);
 const rows=document.querySelector('#server-health-rows');rows.replaceChildren();
 document.querySelector('#server-health-summary').textContent=d.online+' online / '+d.total+' registered ? '+d.unhealthy+' unhealthy ? '+d.pressured+' near capacity or full ? '+d.reserved+'/'+d.slots+' reserved slots ? '+d.connected+' connected players';
 for(const s of d.servers??[]){
  const card=document.createElement('div');card.style.padding='12px';card.style.background='#151619';card.style.borderRadius='10px';
  const heading=document.createElement('div');heading.textContent=s.name+' ? '+pretty(s.region);heading.style.overflowWrap='anywhere';
  const state=document.createElement('div');state.className='hint';state.textContent=s.state.toUpperCase()+' ? '+s.reserved+'/'+s.capacity+' reserved ? '+s.connected+' connected ? heartbeat '+(s.heartbeatSeconds===null?'not recorded':s.heartbeatSeconds+'s ago')+' ? '+s.build;
  if(['stale','unavailable','full','capacity'].includes(s.state))state.style.color='#efb28b';
  const bar=document.createElement('div');bar.className='bar';bar.style.marginTop='10px';const fill=document.createElement('div');fill.className='fill';fill.style.width=Math.min(100,100*s.reserved/Math.max(1,s.capacity))+'%';bar.append(fill);card.append(heading,state,bar);rows.append(card);
 }
 const m=d.metrics;
 document.querySelector('#operational-metrics').textContent=m?[
  'HTTP: '+m.http.requests+' requests / '+m.http.windowSeconds+'s ? '+m.http.serverErrors+' server errors ? '+m.http.rateLimited+' rate limited',
  'HTTP p50 ? '+(m.http.p50UpperMs??'?')+' ms ? p95 ? '+(m.http.p95UpperMs??'?')+' ms',
  'Database: '+m.database.status+' ? round trip '+(m.database.roundTripMs??'?')+' ms ? '+m.database.poolWaiting+' waiting / '+m.database.poolTotal+' connections',
  'Database sampled: '+(m.database.sampledAt?new Date(m.database.sampledAt).toLocaleTimeString():'not yet'),
  'API: '+m.process.residentMiB+' MiB RAM ? '+m.process.uptimeSeconds+'s uptime ? event loop p95 '+(m.process.eventLoopP95Ms??'?')+' ms'
 ].join(String.fromCharCode(10)):'Performance metrics unavailable.';
 renderPerformanceHistory(m?.history??[]);
 document.querySelector('#performance-history-mode').textContent=m?.persistentHistory?'Persisted across restarts for this configured instance.':'In-memory history only; resets on restart.';

 const b=d.backupHealth??{status:'not_configured'};
 const backupLabel={not_configured:'Verification report not configured',report_unavailable:'Verification report unavailable or invalid',report_stale:'Verification report overdue',attention:'Backup requires attention',healthy:'Primary and replica verified'};
 document.querySelector('#backup-health').textContent=[backupLabel[b.status]??'Unknown backup state',...(b.checkedAt?['Checked: '+new Date(b.checkedAt).toLocaleString(),'Last backup: '+(b.lastSuccessAt?new Date(b.lastSuccessAt).toLocaleString():'None'),'Age: '+(b.backupAgeHours??'?')+' hours','Primary: '+b.primary.replaceAll('_',' ')+' ? Replica: '+b.replica.replaceAll('_',' '),'Schedule: '+b.schedule.replaceAll('_',' ')]:[])].join(String.fromCharCode(10));
 const incidents=document.querySelector('#incident-rows');incidents.replaceChildren();
 const summary=document.querySelector('#incident-summary');
 summary.textContent=d.incidentMonitoring?(d.openIncidents+' open incident(s) ? '+(d.incidents??[]).length+' displayed'):'Incident monitoring is disabled.';
 const reasons={stale:'Stale heartbeat',unavailable:'Transport unavailable',offline_reserved:'Offline with reserved players',capacity:'At least 80% occupied',full:'Full'};
 if(d.incidentMonitoring)for(const i of d.incidents??[]){
  const row=document.createElement('div');row.style.padding='12px';row.style.background='#151619';row.style.borderRadius='10px';
  const name=document.createElement('div');name.textContent=i.name+' ? '+pretty(i.region)+' ? '+(reasons[i.reason]??i.reason);
  const detail=document.createElement('div');detail.className='hint';detail.textContent=(i.resolvedAt?'Closed: '+(i.resolution==='server_inactive'?'Server inactive':'Condition cleared'):'OPEN')+' ? Detected '+new Date(i.openedAt).toLocaleString()+(i.resolvedAt?' ? Closed '+new Date(i.resolvedAt).toLocaleString():'');
  if(!i.resolvedAt)detail.style.color='#efb28b';
  row.append(name,detail);
  if(i.acknowledgedAt){const ack=document.createElement('div');ack.className='hint';ack.textContent='Acknowledged '+new Date(i.acknowledgedAt).toLocaleString()+' ? '+(i.acknowledgmentNote??'');row.append(ack)}
  else if(!i.resolvedAt){
   const note=document.createElement('input');note.placeholder='Acknowledgment note';note.maxLength=300;note.style.marginTop='8px';note.style.maxWidth='100%';
   const button=document.createElement('button');button.className='button';button.textContent='Acknowledge';button.style.marginTop='8px';
   button.addEventListener('click',async()=>{
    const text=note.value.trim();if(text.length<3){summary.textContent='Enter an acknowledgment note (3?300 characters).';return}
    const g=generation;button.disabled=true;
    try{const response=await request('/v1/developer/server-incidents/'+encodeURIComponent(i.id)+'/acknowledge',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({note:text})});if(g!==generation)return;
     if(!response.ok){summary.textContent='Acknowledgment not saved (HTTP '+response.status+'). Refresh to see current state.';return}
     await refreshServerHealth(g,true);
    }catch(e){if(g===generation)summary.textContent='Acknowledgment request failed. Refresh and retry.'}
    finally{button.disabled=false}
   });
   row.append(note,button);
  }
  incidents.append(row);
 }
 document.querySelector('#server-health-status').textContent=(d.total>(d.servers??[]).length?'Showing first 200 servers, warnings first. ':'')+'Updated '+new Date(d.asOf).toLocaleTimeString()+(d.total===0?' ? No registered servers.':'');
}
function clearServerHealth(){renderAlpha(null);document.querySelector('#alpha-network').textContent='';document.querySelector('#server-health-panel').classList.add('hidden');document.querySelector('#server-health-summary').textContent='';document.querySelector('#server-health-status').textContent='';document.querySelector('#server-health-rows').replaceChildren();document.querySelector('#incident-rows').replaceChildren();document.querySelector('#incident-summary').textContent='';document.querySelector('#operational-metrics').textContent='';document.querySelector('#performance-history').replaceChildren();document.querySelector('#backup-health').textContent=''}
async function refreshServerHealth(g,allowed){
 if(!allowed){clearServerHealth();return}
 document.querySelector('#server-health-panel').classList.remove('hidden');
 try{
  const r=await request('/v1/developer/server-health',{headers:{Authorization:'Bearer '+token}});
  if(g!==generation)return;
  if(r.status===403||r.status===401){clearServerHealth();return}
  if(!r.ok)throw Error('Server health unavailable (HTTP '+r.status+').');
  const data=await r.json();if(g===generation)renderServerHealth(data);
 }catch(e){if(g===generation)document.querySelector('#server-health-status').textContent='Health snapshot may be stale. '+(e.message||'Connection failed.')}
}
async function request(path,options={}){
 const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),12000);
 try{return await fetch(path,{...options,cache:'no-store',signal:controller.signal})}
 finally{clearTimeout(timeout)}
}
function schedule(delay=15000){clearTimeout(timer);if(token)timer=setTimeout(refresh,delay)}
function clearSession(message=''){
 generation++;token=null;refreshToken=null;expiresAt=0;busy=false;clearTimeout(timer);
 dashboard.classList.add('hidden');signin.classList.remove('hidden');error.textContent=message;
 clearServerHealth();
 document.querySelector('#refresh').disabled=false;
 document.querySelector('#staff-panel').classList.add('hidden');clearRewards();clearLiveContent();
 document.querySelector('#mod-panel').classList.add('hidden');
 clearPlayerDirectory();
 document.querySelector('#suspension-panel').classList.add('hidden');
 document.querySelector('#suspension-list').replaceChildren();
 document.querySelector('#appeal-list').replaceChildren();
 document.querySelector('#appeal-status').textContent='';
 for(const id of ['suspension-name','suspension-reason'])document.querySelector('#'+id).value='';
 document.querySelector('#suspension-status').textContent='';
 for(const id of ['mod-messages','mod-mutes','mod-audit','report-list'])document.querySelector('#'+id).replaceChildren();
 for(const id of ['mod-name','mod-reason'])document.querySelector('#'+id).value='';
 document.querySelector('#mod-status').textContent='';document.querySelector('#report-status').textContent='';
 document.querySelector('#staff-roles').replaceChildren();
 document.querySelector('#staff-audit').replaceChildren();
 document.querySelector('#staff-stat-list').replaceChildren();
 document.querySelector('#staff-stat-status').textContent='';
 document.querySelector('#staff-status').textContent='';
 document.querySelector('#staff-name').value='';
 document.querySelector('#staff-note').value='';
}
function applySession(d){
 if(typeof d.accessToken!=='string'||typeof d.refreshToken!=='string')throw new Error('Invalid sign-in response.');
 token=d.accessToken;refreshToken=d.refreshToken;expiresAt=Date.now()+Number(d.expiresIn||900)*1000;
}
async function renew(g){
 if(!refreshToken){clearSession('Your session expired. Please sign in again.');return false}
 const r=await request('/v1/auth/refresh',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({refreshToken})});
 if(g!==generation)return false;
 if(r.status===401||r.status===403){clearSession('Your session expired. Please sign in again.');return false}
 if(!r.ok)throw new Error('Session renewal failed (HTTP '+r.status+').');
 const d=await r.json();if(g!==generation)return false;applySession(d);return true;
}
async function refresh(){
 if(!token||busy)return;
 const g=generation,button=document.querySelector('#refresh'),status=document.querySelector('#updated');
 busy=true;button.disabled=true;status.textContent='Refreshing activity...';
 let delay=15000;
 try{
  if(Date.now()>=expiresAt-60000&&!await renew(g))return;
  let r=await request('/v1/developer/activity',{headers:{Authorization:'Bearer '+token}});
  if(g!==generation)return;
  if(r.status===401){if(!await renew(g))return;r=await request('/v1/developer/activity',{headers:{Authorization:'Bearer '+token}})}
  if(g!==generation)return;
  if(r.status===401||r.status===403){clearSession(r.status===403?'This account does not have developer dashboard access.':'Your session expired. Please sign in again.');return}
  if(!r.ok){if(r.status===429)delay=Math.max(15000,Number(r.headers.get('retry-after')||30)*1000);throw new Error('Activity request failed (HTTP '+r.status+').')}
  const d=await r.json();if(g!==generation)return;
  document.querySelector('#online').textContent=d.onlinePlayers;
  document.querySelector('#staff-panel').classList.toggle('hidden',d.staffManagement!==true);if(d.staffManagement===true)document.querySelector('#rewards-panel').classList.remove('hidden');else clearRewards();
  if(d.liveContentManagement===true)document.querySelector('#live-content-panel').classList.remove('hidden');else clearLiveContent();
  document.querySelector('#mod-panel').classList.toggle('hidden',d.moderation!==true);
  if(d.moderation===true)document.querySelector('#player-directory').classList.remove('hidden');else clearPlayerDirectory();
  if(directoryAdminAllowed&&d.suspensions!==true){directorySequence++;document.querySelector('#player-detail').replaceChildren();directoryShowsAdmin=false;}directoryAdminAllowed=d.suspensions===true;
  document.querySelector('#suspension-panel').classList.toggle('hidden',d.suspensions!==true);
  renderZoneBars('#zones','#empty',d.zones??[]);renderProgression(d.progression);
  status.textContent='Updated '+new Date(d.asOf).toLocaleTimeString();
  await refreshServerHealth(g,d.serverHealthAccess===true);
 }catch(err){if(g===generation)status.textContent=(err.name==='AbortError'?'Request timed out.':err.message||'Connection issue.')+' Retrying automatically.'}
 finally{if(g===generation){busy=false;button.disabled=false;schedule(delay)}}
}
document.querySelector('#login').addEventListener('submit',async e=>{
 e.preventDefault();error.textContent='';const button=document.querySelector('.submit');
 if(button.disabled)return;
 button.disabled=true;button.textContent='Signing in...';const g=++generation;
 try{
  const r=await request('/v1/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({playerName:document.querySelector('#name').value.trim(),password:document.querySelector('#password').value})});
  if(g!==generation)return;
  if(r.status===429)throw new Error('Too many sign-in attempts. Wait '+(r.headers.get('retry-after')||'900')+' seconds and retry.');
  if(r.status===401||r.status===400)throw new Error('Sign in failed. Check the account and password.');
  if(r.status===403){const d=await r.json();if(d.error==='account_suspended')throw new Error('Account suspended until '+new Date(d.suspendedUntil).toLocaleString()+': '+d.reason);throw new Error('Sign-in access restricted.')}
  if(!r.ok)throw new Error('Server returned HTTP '+r.status+'. Try again.');
  const d=await r.json();if(g!==generation)return;applySession(d);
  document.querySelector('#password').value='';signin.classList.add('hidden');dashboard.classList.remove('hidden');await refresh();
 }catch(err){if(g===generation){clearSession(err.name==='AbortError'?'Sign-in request timed out. Try again.':err.message||'Connection failed. Try again.')}}
 finally{button.disabled=false;button.textContent='Sign in'}
});
let reportBusy=false;
async function loadReports(change=null){
 if(!token||reportBusy)return;
 const g=generation,status=document.querySelector('#report-status'),root=document.querySelector('#report-list'),filter=document.querySelector('#report-filter');
 reportBusy=true;status.textContent='Loading...';
 try{
  const headers={Authorization:'Bearer '+token,'Content-Type':'application/json'};
  if(change){
   const r=await request('/v1/developer/moderation/reports',{method:'POST',headers,body:JSON.stringify(change)});
   if(g!==generation)return;
   if(!r.ok){const d=await r.json();throw new Error(d.error||'Review failed.')}
  }
  const r=await request('/v1/developer/moderation/reports?status='+encodeURIComponent(filter.value),{headers});
  if(g!==generation)return;
  if(!r.ok)throw new Error('Report access denied or session expired.');
  const d=await r.json();if(g!==generation)return;
  root.replaceChildren();
  for(const row of d.reports){
   const card=document.createElement('div');card.className='card';card.style.marginTop='12px';
   const line=(text)=>{const p=document.createElement('p');p.textContent=text;card.append(p)};
   line(row.target_name+' | '+new Date(row.message_at).toLocaleString());line(row.message_text);
   if(row.status==='pending'){
    const select=document.createElement('button');select.className='button';select.textContent='Select for moderation';select.addEventListener('click',()=>{document.querySelector('#mod-name').value=row.target_name});card.append(select);
    for(const decision of ['resolved','dismissed']){
     const b=document.createElement('button');b.className='button';b.textContent=decision==='resolved'?'Resolve':'Dismiss';
     b.addEventListener('click',()=>{const note=window.prompt('Review reason (8-300 characters)');if(note&&note.trim().length>=8&&note.trim().length<=300)loadReports({id:row.id,status:decision,note:note.trim()})});card.append(b);
    }
   }else line(row.status+' by '+(row.reviewer||'Former staff')+' | '+row.review_note);
   root.append(card);
  }
  status.textContent=d.reports.length?d.reports.length+' reports':'No reports in this queue.';
 }catch(e){if(g===generation)status.textContent='Could not load reports: '+(e.message||'connection error')}
 finally{reportBusy=false}
}
document.querySelector('#report-load').addEventListener('click',()=>loadReports());
document.querySelector('#report-filter').addEventListener('change',()=>loadReports());
let appealBusy=false;
async function loadAppeals(change=null){
 if(!token||appealBusy)return;
 const g=generation,status=document.querySelector('#appeal-status'),root=document.querySelector('#appeal-list'),filter=document.querySelector('#appeal-filter');
 appealBusy=true;status.textContent='Loading...';
 try{
  const headers={Authorization:'Bearer '+token,'Content-Type':'application/json'};
  if(change){
   const r=await request('/v1/developer/moderation/appeals',{method:'POST',headers,body:JSON.stringify(change)});
   if(g!==generation)return;
   if(!r.ok){const d=await r.json();throw new Error(d.error||'Review failed.')}
  }
  const r=await request('/v1/developer/moderation/appeals?status='+encodeURIComponent(filter.value),{headers});
  if(g!==generation)return;
  if(!r.ok)throw new Error('Appeal access denied or session expired.');
  const d=await r.json();if(g!==generation)return;
  root.replaceChildren();
  for(const row of d.appeals){
   const card=document.createElement('div');card.className='card';card.style.marginTop='12px';
   const line=text=>{const p=document.createElement('p');p.textContent=text;card.append(p)};
   line(row.target_name+' | '+row.status+' | until '+new Date(row.suspended_until).toLocaleString());
   line('Suspension by '+row.imposed_by+': '+row.reason);line('Appeal: '+row.statement);
   if(row.status==='pending'){
    if(row.conflict)line('Independent reviewer required.');
    else for(const decision of row.actionable?['approve','reject']:['close']){
     const b=document.createElement('button');b.className='button';b.textContent=decision==='approve'?'Approve and lift':decision==='reject'?'Reject':'Close inactive appeal';
     b.addEventListener('click',()=>{const note=window.prompt('Review reason (8-300 characters)');if(note&&note.trim().length>=8&&note.trim().length<=300&&window.confirm('Confirm '+decision+'?'))loadAppeals({id:row.id,decision,note:note.trim()})});card.append(b);
    }
   }else line('Review: '+row.reviewer+' | '+row.review_note);
   root.append(card);
  }
  status.textContent=d.appeals.length?d.appeals.length+' appeals':'No appeals in this queue.';
 }catch(e){if(g===generation)status.textContent='Could not complete request: '+(e.message||'connection error')}
 finally{appealBusy=false}
}
document.querySelector('#appeal-load').addEventListener('click',()=>loadAppeals());
document.querySelector('#appeal-filter').addEventListener('change',()=>loadAppeals());
let suspensionBusy=false;
async function loadSuspensions(change=null){
 if(!token||suspensionBusy)return;
 const g=generation,status=document.querySelector('#suspension-status'),root=document.querySelector('#suspension-list'),submit=document.querySelector('#suspension-submit');
 suspensionBusy=true;submit.disabled=true;status.textContent='Loading...';
 try{
  const headers={Authorization:'Bearer '+token,'Content-Type':'application/json'};
  if(change){
   const r=await request('/v1/developer/moderation/suspensions',{method:'POST',headers,body:JSON.stringify(change)});
   if(g!==generation)return;
   if(!r.ok){const d=await r.json();throw new Error(d.error||'Account action failed.')}
  }
  const r=await request('/v1/developer/moderation/suspensions',{headers});
  if(g!==generation)return;
  if(!r.ok)throw new Error('Access denied or session expired.');
  const d=await r.json();if(g!==generation)return;
  root.replaceChildren();
  for(const row of d.suspensions){
   const p=document.createElement('p');p.className='hint';
   p.textContent=row.target_name+' | '+row.status+' | until '+new Date(row.suspended_until).toLocaleString()+' | '+row.actor+' | '+row.reason+(row.end_reason?' | End: '+row.end_reason:'');
   root.append(p);
  }
  status.textContent=change?'Account action saved.':(d.suspensions.length?'Suspension history loaded.':'No suspension records.');
 }catch(e){if(g===generation)status.textContent='Could not complete request: '+(e.message||'connection error')}
 finally{suspensionBusy=false;submit.disabled=false}
}
document.querySelector('#suspension-load').addEventListener('click',()=>loadSuspensions());
document.querySelector('#suspension-form').addEventListener('submit',e=>{
 e.preventDefault();
 const action=document.querySelector('#suspension-action').value;
 const change={action,playerName:document.querySelector('#suspension-name').value.trim(),reason:document.querySelector('#suspension-reason').value.trim()};
 if(action==='suspend')change.minutes=Number(document.querySelector('#suspension-minutes').value);
 if(window.confirm('Confirm '+action+' for '+change.playerName+'?'))loadSuspensions(change);
});
let directorySequence=0,directoryShowsAdmin=false,directoryAdminAllowed=false;
function clearPlayerDirectory(){
 directorySequence++;
 directoryShowsAdmin=false;
 document.querySelector('#player-directory').classList.add('hidden');
 for(const id of ['player-search-results','player-detail'])document.querySelector('#'+id).replaceChildren();
 document.querySelector('#player-search').value='';
 document.querySelector('#player-search-status').textContent='';
}
async function directoryFetch(path){
 const seq=++directorySequence,g=generation,status=document.querySelector('#player-search-status');
 status.textContent='Loading...';
 try{
  const r=await request('/v1/developer/moderation/players'+path,{headers:{Authorization:'Bearer '+token}});
  if(seq!==directorySequence||g!==generation)return null;
  if(r.status===401||r.status===403){clearPlayerDirectory();return null}
  if(!r.ok)throw Error('Player lookup failed (HTTP '+r.status+').');
  const d=await r.json();
  if(seq!==directorySequence||g!==generation)return null;
  status.textContent='';return d;
 }catch(e){if(seq===directorySequence&&g===generation)status.textContent=e.message||'Player lookup unavailable.';return null}
}
function directoryText(root,text,tag='p'){
 const node=document.createElement(tag);node.textContent=text;root.append(node);return node;
}
async function searchPlayers(){
 if(!token)return;
 const q=document.querySelector('#player-search').value.trim();
 const root=document.querySelector('#player-search-results');
 root.replaceChildren();document.querySelector('#player-detail').replaceChildren();directoryShowsAdmin=false;
 const d=await directoryFetch('?q='+encodeURIComponent(q));if(!d)return;
 document.querySelector('#player-search-status').textContent=d.more?'Showing first 20 matches. Refine your search.':d.players.length+' matching players';
 for(const row of d.players){
  const button=document.createElement('button');button.className='button';button.textContent=row.name+' | Lv. '+row.level+' | '+row.status;
  button.addEventListener('click',()=>openPlayer(row.id));root.append(button);
 }
}
async function openPlayer(id){
 if(!token)return;
 const root=document.querySelector('#player-detail');root.replaceChildren();directoryShowsAdmin=false;
 const d=await directoryFetch('/'+encodeURIComponent(id));if(!d)return;
 const p=d.player;
 directoryText(root,p.name,'h3');
 directoryText(root,'Level '+p.level+' | '+p.status+(p.protectedAccount?' | Protected staff':''));
 directoryText(root,'Joined '+new Date(p.createdAt).toLocaleDateString()+' | '+(p.mutedUntil?'Muted until '+new Date(p.mutedUntil).toLocaleString():'No active chat mute'));
 function shortcut(label,target){
  const b=document.createElement('button');b.className='button';b.textContent=label;b.addEventListener('click',()=>{const field=document.querySelector('#'+target);field.value=p.name;field.focus();field.scrollIntoView({block:'center'})});root.append(b);
 }
 if(d.canModerate)shortcut('Open chat moderation','mod-name');
 if(d.canSuspend)shortcut('Open suspension controls','suspension-name');
 directoryText(root,'Report counts (not findings of misconduct)','h3');
 directoryText(root,d.reports.map(r=>r.status+': '+r.total).join(' | ')||'No reports.');
 directoryText(root,'Chat disciplinary history (latest 50)','h3');
 if(!d.history.length)directoryText(root,'No actions recorded.');
 for(const a of d.history)directoryText(root,new Date(a.created_at).toLocaleString()+' | '+a.action+' | '+a.actor+' | '+a.reason+(a.muted_until?' | until '+new Date(a.muted_until).toLocaleString():''));
 directoryShowsAdmin=Array.isArray(d.suspensions);
 if(directoryShowsAdmin){
  directoryText(root,'Account suspension history (latest 50)','h3');
  if(!d.suspensions.length)directoryText(root,'No suspensions recorded.');
  for(const s of d.suspensions)directoryText(root,new Date(s.created_at).toLocaleString()+' | '+s.actor+' | '+s.reason+' | until '+new Date(s.suspended_until).toLocaleString()+(s.end_reason?' | End: '+s.end_reason:''));
 }
}
document.querySelector('#player-search-form').addEventListener('submit',e=>{e.preventDefault();searchPlayers()});
let modBusy=false;
async function modRequest(change=null){
 if(!token||modBusy)return;
 const g=generation,status=document.querySelector('#mod-status'),submit=document.querySelector('#mod-submit'),load=document.querySelector('#mod-load');
 modBusy=true;submit.disabled=true;load.disabled=true;status.textContent='Loading...';
 try{
  const headers={Authorization:'Bearer '+token,'Content-Type':'application/json'};
  if(change){
   const r=await request('/v1/developer/moderation/',{method:'POST',headers,body:JSON.stringify(change)});
   if(g!==generation)return;
   if(!r.ok){const d=await r.json();throw new Error(d.error||'Action failed.')}
  }
  const r=await request('/v1/developer/moderation/',{headers});
  if(g!==generation)return;
  if(!r.ok)throw new Error('Moderation access denied or session expired.');
  const d=await r.json();if(g!==generation)return;
  function fill(id,rows,format,selectPlayer=false){
   const root=document.querySelector('#'+id);root.replaceChildren();
   if(!rows.length){const p=document.createElement('p');p.className='hint';p.textContent='No records.';root.append(p)}
   for(const row of rows){const p=document.createElement('p');p.className='hint';p.textContent=format(row);
    if(selectPlayer){const b=document.createElement('button');b.className='button';b.textContent='Select player';b.addEventListener('click',()=>{document.querySelector('#mod-name').value=row.name});p.append(b)}
    root.append(p)}
  }
  fill('mod-messages',d.messages,x=>new Date(x.created_at).toLocaleTimeString()+' | '+x.name+': '+x.text,true);
  fill('mod-mutes',d.mutes,x=>x.name+' | until '+new Date(x.muted_until).toLocaleString(),true);
  fill('mod-audit',d.audit,x=>new Date(x.created_at).toLocaleString()+' | '+x.actor+' | '+x.target+' | '+x.action+' | '+x.reason);
  status.textContent=change?'Action saved.':'Moderation updated.';
  if(change){document.querySelector('#mod-name').value='';document.querySelector('#mod-reason').value=''}
 }catch(e){if(g===generation)status.textContent='Could not complete request: '+(e.message||'connection error')}
 finally{modBusy=false;submit.disabled=false;load.disabled=false}
}
document.querySelector('#mod-load').addEventListener('click',()=>modRequest());
document.querySelector('#mod-form').addEventListener('submit',e=>{
 e.preventDefault();
 const action=document.querySelector('#mod-action').value;
 const change={action,playerName:document.querySelector('#mod-name').value.trim(),reason:document.querySelector('#mod-reason').value.trim()};
 if(action==='mute')change.minutes=Number(document.querySelector('#mod-minutes').value);
 if(window.confirm('Apply '+change.action+' to '+change.playerName+'?'))modRequest(change);
});
let staffStatsSequence=0;
async function loadStaffStatistics(){
 if(!token)return;
 const g=generation,seq=++staffStatsSequence,status=document.querySelector('#staff-stat-status'),root=document.querySelector('#staff-stat-list'),days=document.querySelector('#staff-stat-days').value;
 root.replaceChildren();status.textContent='Loading...';
 try{
  const r=await request('/v1/developer/staff/statistics?days='+encodeURIComponent(days),{headers:{Authorization:'Bearer '+token}});
  if(g!==generation||seq!==staffStatsSequence)return;
  if(!r.ok)throw Error('Statistics unavailable (HTTP '+r.status+').');
  const d=await r.json();if(g!==generation||seq!==staffStatsSequence)return;
  for(const row of d.staff){
   const card=document.createElement('div');card.className='card';card.style.marginTop='12px';
   const line=(text,tag='p')=>{const p=document.createElement(tag);p.textContent=text;card.append(p)};
   line(row.name+' | '+row.role.replaceAll('_',' '),'h3');
   line(row.total+' recorded actions | '+(row.last_action?'Last action '+new Date(row.last_action).toLocaleString():'No actions this period'));
   line('Warnings '+row.warnings+' | Mutes '+row.mutes+' | Unmutes '+row.unmutes);
   line('Suspensions '+row.suspensions+' | Manual lifts '+row.manual_lifts);
   line('Reports resolved '+row.reports_resolved+' | dismissed '+row.reports_dismissed);
   line('Appeals approved '+row.appeals_approved+' | rejected '+row.appeals_rejected+' | closed '+row.appeals_closed);
   line('Role changes '+row.role_changes);root.append(card);
  }
  status.textContent=d.staff.length+' staff records | Last '+d.days+' days'+(d.more?' | Showing first 500':'');
 }catch(e){if(g===generation&&seq===staffStatsSequence)status.textContent=e.message||'Statistics unavailable.'}
}
document.querySelector('#staff-stat-load').addEventListener('click',loadStaffStatistics);
document.querySelector('#staff-stat-days').addEventListener('change',loadStaffStatistics);
let staffBusy=false;
async function staffRequest(change=null){
 if(!token||staffBusy)return;
 const g=generation,status=document.querySelector('#staff-status'),submit=document.querySelector('#staff-submit'),load=document.querySelector('#staff-load');
 staffBusy=true;submit.disabled=true;load.disabled=true;status.textContent='Loading...';
 try{
  const headers={Authorization:'Bearer '+token,'Content-Type':'application/json'};
  if(change){
   const r=await request('/v1/developer/staff/',{method:'POST',headers,body:JSON.stringify(change)});
   if(g!==generation)return;
   if(!r.ok){const d=await r.json();throw new Error(d.error||'Role change failed.')}
  }
  const r=await request('/v1/developer/staff/',{headers});
  if(g!==generation)return;
  if(!r.ok)throw new Error('Staff access denied or session expired. Refresh and try again.');
  const d=await r.json();if(g!==generation)return;
  const roles=document.querySelector('#staff-roles'),audit=document.querySelector('#staff-audit');roles.replaceChildren();audit.replaceChildren();
  function entry(target,value){const p=document.createElement('p');p.className='hint';p.textContent=value;target.append(p)}
  if(!d.roles.length)entry(roles,'No staff assigned yet.');
  for(const item of d.roles)entry(roles,item.name+' - '+item.role);
  if(!d.audit.length)entry(audit,'No changes recorded yet.');
  for(const item of d.audit)entry(audit,new Date(item.created_at).toLocaleString()+' | '+item.actor+' | '+item.target+' | '+(item.previous_role||'none')+' -> '+(item.new_role||'revoked')+' | '+item.note);
  status.textContent=change?'Role change saved.':'Staff list updated.';
  if(change){document.querySelector('#staff-name').value='';document.querySelector('#staff-note').value=''}
 }catch(e){if(g===generation)status.textContent='Could not complete request: '+(e.message||'connection error')}
 finally{staffBusy=false;submit.disabled=false;load.disabled=false}
}
document.querySelector('#staff-load').addEventListener('click',()=>staffRequest());
document.querySelector('#staff-form').addEventListener('submit',e=>{
 e.preventDefault();
 const change={playerName:document.querySelector('#staff-name').value.trim(),role:document.querySelector('#staff-role').value,note:document.querySelector('#staff-note').value.trim()};
 if(window.confirm('Apply '+change.role+' to '+change.playerName+'?'))staffRequest(change);
});
let rewardTarget=null,rewardBusy=false,rewardSequence=0,rewardPending=null,rewardCursor=null;
function clearRewards(){rewardSequence++;rewardTarget=null;rewardBusy=false;rewardPending=null;rewardCursor=null;document.querySelector('#rewards-panel').classList.add('hidden');for(const id of ['#reward-players','#reward-history'])document.querySelector(id).replaceChildren();for(const id of ['#reward-selected','#reward-status'])document.querySelector(id).textContent='';for(const id of ['#reward-name','#reward-amount','#reward-note'])document.querySelector(id).value='';document.querySelector('#reward-submit').disabled=true;document.querySelector('#reward-history-next').disabled=true}
async function rewardRequest(path,body){const r=await request('/v1/developer/rewards/'+path,{headers:{Authorization:'Bearer '+token,...(body?{'Content-Type':'application/json'}:{})},...(body?{method:'POST',body:JSON.stringify(body)}:{})});const d=await r.json();if(!r.ok)throw Error(d.error||'HTTP '+r.status);return d}
function walletText(p){return p.name+' | '+p.status+' | Crystals: '+(p.balances.crystals??'0')+' | Gems: '+(p.balances.gems??'0')+' | Paid: '+(p.balances.paid_moonstones??'0')+' | Gold: '+(p.balances.gold??'0')}
document.querySelector('#reward-search').addEventListener('submit',async e=>{e.preventDefault();if(!token||rewardBusy)return;const g=generation,seq=++rewardSequence,status=document.querySelector('#reward-status');rewardTarget=null;rewardPending=null;document.querySelector('#reward-submit').disabled=true;document.querySelector('#reward-selected').textContent='';const list=document.querySelector('#reward-players');list.replaceChildren();try{const d=await rewardRequest('players?q='+encodeURIComponent(document.querySelector('#reward-name').value.trim()));if(g!==generation||seq!==rewardSequence)return;for(const p of d.players){const b=document.createElement('button');b.className='button';b.textContent=walletText(p);b.disabled=p.status!=='active';b.addEventListener('click',()=>{if(rewardBusy||seq!==rewardSequence)return;rewardTarget=p;rewardPending=null;document.querySelector('#reward-selected').textContent=walletText(p);document.querySelector('#reward-submit').disabled=false});list.append(b)}status.textContent=d.players.length?(d.more?'First 20 matches. Refine search.':'Select a wallet.'):'No matching player.'}catch(e){if(g===generation&&seq===rewardSequence)status.textContent=e.message}});
document.querySelector('#reward-form').addEventListener('submit',async e=>{e.preventDefault();if(!token||!rewardTarget||rewardBusy)return;const data={targetId:rewardTarget.id,currency:document.querySelector('#reward-currency').value,amount:Number(document.querySelector('#reward-amount').value),note:document.querySelector('#reward-note').value.trim()};if(!Number.isSafeInteger(data.amount)||data.amount<1||data.amount>1000000||data.note.length<8)return;if(!window.confirm('Grant '+data.amount+' '+data.currency+' to '+rewardTarget.name+'? This changes the live wallet.'))return;const key=JSON.stringify(data);if(!rewardPending||rewardPending.key!==key)rewardPending={key,id:crypto.randomUUID()};const g=generation,seq=rewardSequence,status=document.querySelector('#reward-status');rewardBusy=true;document.querySelector('#reward-submit').disabled=true;try{const d=await rewardRequest('grant',{...data,requestId:rewardPending.id});if(g!==generation||seq!==rewardSequence)return;rewardTarget.balances[d.currency]=d.balanceAfter;document.querySelector('#reward-selected').textContent=walletText(rewardTarget);status.textContent='Grant recorded: '+d.amount+' '+d.currency+' to '+d.target+' (balance after grant: '+d.balanceAfter+').';rewardPending=null;document.querySelector('#reward-amount').value='';document.querySelector('#reward-note').value='';await loadRewardHistory(false)}catch(e){if(g===generation&&seq===rewardSequence)status.textContent='Grant not confirmed: '+e.message+'. Retry unchanged to reuse the same request ID.'}finally{if(g===generation&&seq===rewardSequence){rewardBusy=false;document.querySelector('#reward-submit').disabled=!rewardTarget}}});
async function loadRewardHistory(older){if(!token)return;const g=generation,seq=rewardSequence;try{const d=await rewardRequest('history'+(older&&rewardCursor?'?before='+encodeURIComponent(rewardCursor):''));if(g!==generation||seq!==rewardSequence)return;const list=document.querySelector('#reward-history');if(!older)list.replaceChildren();for(const row of d.grants){const div=document.createElement('div');div.className='hint';div.textContent=new Date(row.created_at).toLocaleString()+' | '+row.actor_name+' -> '+row.target_name+' | +'+row.amount+' '+row.currency_id+' | balance '+row.balance_after+' | '+row.note;list.append(div)}rewardCursor=d.next;document.querySelector('#reward-history-next').disabled=!rewardCursor}catch(e){if(g===generation&&seq===rewardSequence)document.querySelector('#reward-status').textContent=e.message}}
document.querySelector('#reward-history-load').addEventListener('click',()=>loadRewardHistory(false));
document.querySelector('#reward-history-next').addEventListener('click',()=>loadRewardHistory(true));
document.querySelector('#refresh').addEventListener('click',refresh);
document.querySelector('#logout').addEventListener('click',()=>{
 const old=refreshToken;clearSession();
 if(old)request('/v1/auth/logout',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({refreshToken:old})}).catch(()=>{});
});
${liveContentScript}
</script></body></html>`;
