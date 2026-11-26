import test from "node:test";
import assert from "node:assert/strict";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {createDeveloperRoutes} from "../src/routes/developer.js";

const secret="developer-dashboard-test-secret-at-least-32-characters";
const account="11111111-1111-4111-8111-111111111111";
const player="22222222-2222-4222-8222-222222222222";

test("activity endpoint denies missing and non-developer sessions",async()=>{
 let queryCount=0;
 const app=Fastify();
 await app.register(jwt,{secret});
 await app.register(createDeveloperRoutes({developerAccountIds:"",database:{query:async()=>{queryCount++;return{rows:[]};}}}));
 const anonymous=await app.inject({method:"GET",url:"/v1/developer/activity"});
 assert.equal(anonymous.statusCode,401);
 const token=app.jwt.sign({sub:account,playerId:player,tokenVersion:1});
 const denied=await app.inject({method:"GET",url:"/v1/developer/activity",headers:{authorization:`Bearer ${token}`}});
 assert.equal(denied.statusCode,403);
 assert.equal(denied.json().error,"developer_access_required");
 assert.equal(queryCount,0,"denied accounts must not trigger database reads");
 await app.close();
});

test("developer activity returns anonymous totals and zone counts only",async()=>{
 const queries:string[]=[];
 const app=Fastify();
 await app.register(jwt,{secret});
 await app.register(createDeveloperRoutes({developerAccountIds:`not-a-uuid, ${account}`,database:{query:async sql=>{
  queries.push(sql);
  if(sql.includes("SELECT token_version,status"))return{rows:[{token_version:7,status:"active"}]};
  if(sql.includes("WITH activity_signals"))return{rows:[{online_players:3,zones:[{regionId:"six_zone_willow_fields",players:2},{regionId:"six_zone_royal_gate",players:1}]}]};
  return{rows:[{daily_claims:{checkin:2,victories:1,shared:0,bonus:0},daily_players:2,expedition_victory_credits:5,shared_victory_days:1,weekly_claims:{checkins:1,victories:0,shared:0,bonus:0},weekly_players:1,region_arrivals:[{regionId:"six_zone_willow_fields",players:3}],story_milestones:[{milestoneId:"village",players:4},{milestoneId:"chapter_complete",players:1}],story_coverage_since:"2026-12-01T00:00:00.000Z"}]};
 }}}));
 const token=app.jwt.sign({sub:account,playerId:player,tokenVersion:7});
 const response=await app.inject({method:"GET",url:"/v1/developer/activity",headers:{authorization:`Bearer ${token}`}});
 assert.equal(response.statusCode,200);
 assert.equal(response.headers["cache-control"],"no-store");
 const body=response.json();
 assert.equal(body.onlinePlayers,3);
 assert.deepEqual(body.zones,[{regionId:"six_zone_willow_fields",players:2},{regionId:"six_zone_royal_gate",players:1}]);
 assert.deepEqual(body.progression,{windowDays:30,dailyClaims:{checkin:2,victories:1,shared:0,bonus:0},dailyPlayers:2,expeditionVictoryCredits:5,sharedVictoryDays:1,weeklyClaims:{checkins:1,victories:0,shared:0,bonus:0},weeklyPlayers:1,regionArrivals:[{regionId:"six_zone_willow_fields",players:3}],storyMilestones:[{milestoneId:"village",players:4},{milestoneId:"chapter_complete",players:1}],storyCoverageSince:"2026-12-01T00:00:00.000Z"});
 assert.equal("players" in body,false);
 assert.equal("playerId" in body,false);
 assert.equal(queries.length,3);
 assert.match(queries[1]!,/lease_expires_at>now\(\)/);
 assert.match(queries[1]!,/last_heartbeat_at>now\(\)-interval '45 seconds'/);
 assert.match(queries[2]!,/online_daily_quests/);
 assert.match(queries[2]!,/online_weekly_quests/);
 assert.match(queries[2]!,/event_type='player_joined'/);
 assert.match(queries[2]!,/story_milestone_reaches/);
 await app.close();
});

test("revoked developer sessions cannot read activity",async()=>{
 const app=Fastify();
 await app.register(jwt,{secret});
 await app.register(createDeveloperRoutes({developerAccountIds:account,database:{query:async()=>({rows:[{token_version:8,status:"active"}]})}}));
 const staleToken=app.jwt.sign({sub:account,playerId:player,tokenVersion:7});
 const response=await app.inject({method:"GET",url:"/v1/developer/activity",headers:{authorization:`Bearer ${staleToken}`}});
 assert.equal(response.statusCode,401);
 assert.equal(response.json().error,"session_revoked");
 await app.close();
});

test("dashboard shell contains no embedded activity or credentials",async()=>{
 const app=Fastify();
 await app.register(jwt,{secret});
 await app.register(createDeveloperRoutes({developerAccountIds:"",database:{query:async()=>({rows:[]})}}));
 const page=await app.inject({method:"GET",url:"/developer"});
 assert.equal(page.statusCode,200);
 assert.equal(page.headers["cache-control"],"no-store");
 assert.match(page.headers["content-security-policy"]!,/connect-src 'self'/);
 assert.match(page.body,/Developer console/);
 assert.match(page.body,/Story milestone funnel · post-update observations/);
 assert.match(page.body,/No pre-update saves are backfilled/);
 assert.match(page.body,/Fewer reaches do not confirm abandonment/);
 assert.match(page.body,/offline and unsigned play are not included/);
 assert.doesNotMatch(page.body,/playerId|email|Bearer [A-Za-z0-9._-]{20}/);
 await app.close();
});
