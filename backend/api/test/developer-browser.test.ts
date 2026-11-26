import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import Fastify from "fastify";
import {createDeveloperRoutes} from "../src/routes/developer.js";

test("dashboard browser script recovers expired sessions, exposes errors, and signs out",async()=>{
 const app=Fastify();
 await app.register(createDeveloperRoutes({developerAccountIds:"",database:{query:async()=>({rows:[]})}}));
 const html=(await app.inject({url:"/developer"})).body;
 await app.close();
 const script=html.match(/<script>([\s\S]*?)<\/script>/)![1]!;
 const elements=new Map<string,any>();
 function node(){return {textContent:"",value:"",disabled:false,style:{},children:[],handlers:{} as Record<string,Function>,classList:{add(){},remove(){},toggle(){}},setAttribute() {},addEventListener(k:string,v:Function){this.handlers[k]=v},replaceChildren(){this.children=[]},append(...args:never[]){this.children.push(...args)}}}
 const select=(s:string)=>{if(!elements.has(s))elements.set(s,node());return elements.get(s)};
 const requests:string[]=[];
 let activityCount=0,mode="normal",healthAllowed=true,acknowledged=false;
 const progression={expeditionVictoryCredits:0,sharedVictoryDays:0,dailyPlayers:0,weeklyPlayers:0,dailyClaims:{},weeklyClaims:{},regionArrivals:[],storyMilestones:[]};
 const ctx=vm.createContext({document:{querySelector:select,createElement:node},AbortController,setTimeout:()=>1,clearTimeout:()=>{},fetch:async(path:string)=>{
  requests.push(path);
  if(path.endsWith("/login"))return new Response(JSON.stringify({accessToken:"access",refreshToken:"refresh",expiresIn:900}));
  if(path.endsWith("/refresh"))return new Response(JSON.stringify({accessToken:"new",refreshToken:"rotated",expiresIn:900}));
  if(path.endsWith("/logout"))return new Response(null,{status:204});
  if(path.endsWith("/acknowledge")){acknowledged=true;return new Response(JSON.stringify({id:"1"}));}
  if(path.endsWith("/server-health"))return new Response(JSON.stringify({alpha:{network:{public:{state:"open",durationMs:14,checkedAt:new Date().toISOString()},local:{state:"closed",durationMs:2,checkedAt:new Date().toISOString()}},enrollment:{enrolled:2,active:2,unused:1,consumed:2,remaining:17,issuanceLimit:20},realtime:{connections:2,players:2,lobbies:1},recentPresence:2,recentLobbies:1},total:1,online:1,unhealthy:0,pressured:1,slots:10,reserved:9,connected:8,metrics:{http:{requests:10,windowSeconds:60,serverErrors:1,rateLimited:2,p50UpperMs:10,p95UpperMs:100},database:{status:"ok",roundTripMs:2,poolWaiting:0,poolTotal:4,sampledAt:null},process:{residentMiB:100,uptimeSeconds:10,eventLoopP95Ms:21}},backupHealth:{status:"attention",checkedAt:"2026-11-26T08:00:00Z",lastSuccessAt:"2026-11-25T01:00:00Z",backupAgeHours:31,primary:"verified",replica:"missing",schedule:"overdue"},incidentMonitoring:true,openIncidents:1,incidents:[{id:"1",name:"QA Server",region:"six_zone_willow_fields",kind:"capacity",reason:"capacity",openedAt:"2026-11-26T08:00:00Z",resolvedAt:null,acknowledgedAt:acknowledged?"2026-11-26T08:01:00Z":null,acknowledgmentNote:acknowledged?"Investigating":null}],servers:[{name:"QA Server",region:"six_zone_willow_fields",state:"capacity",reserved:9,capacity:10,connected:8,heartbeatSeconds:3,build:"qa"}],asOf:new Date().toISOString()}));
  activityCount++;
  if(activityCount===1)return new Response(null,{status:401});
  if(mode==="timeout")throw new DOMException("Aborted","AbortError");
  return new Response(JSON.stringify({onlinePlayers:4,zones:[],progression,serverHealthAccess:healthAllowed,asOf:new Date().toISOString()}));
 }});
 new vm.Script(script).runInContext(ctx);
 select("#name").value="QA";select("#password").value="test";
 await select("#login").handlers.submit({preventDefault(){}});
 assert.equal(select("#online").textContent,4);
 assert.match(select("#alpha-network").textContent,/Public HTTPS: OPEN/);
 assert.match(select("#alpha-network").textContent,/STATUS ONLY/);
 assert.match(select("#alpha-enrollment").textContent,/17 \/ 20/);
 assert.match(select("#alpha-realtime").textContent,/connections: 2/);
 assert.match(select("#server-health-summary").textContent,/9\/10 reserved slots/);
 assert.equal(select("#server-health-rows").children.length,1);
 assert.match(select("#server-health-rows").children[0].children[1].textContent,/CAPACITY/);
 assert.match(select("#incident-summary").textContent,/1 open incident/);
 assert.match(select("#backup-health").textContent,/Backup requires attention/);
 assert.match(select("#backup-health").textContent,/Replica: missing/);
 assert.equal(select("#incident-rows").children.length,1);
 assert.match(select("#incident-rows").children[0].children[1].textContent,/OPEN/);
 assert.match(select("#operational-metrics").textContent,/10 requests/);
 const incident=select("#incident-rows").children[0];
 incident.children[2].value="Investigating";
 await incident.children[3].handlers.click();
 assert.ok(requests.includes("/v1/developer/server-incidents/1/acknowledge"));
 assert.match(select("#incident-rows").children[0].children[2].textContent,/Acknowledged/);
 assert.match(select("#incident-rows").children[0].children[1].textContent,/OPEN/);

 healthAllowed=false;
 await select("#refresh").handlers.click();
 assert.equal(select("#server-health-rows").children.length,0);
 assert.equal(select("#server-health-summary").textContent,"");
 assert.equal(select("#alpha-network").textContent,"");
 assert.equal(select("#alpha-enrollment").textContent,"");
 assert.equal(select("#alpha-realtime").textContent,"");
 assert.equal(select("#incident-rows").children.length,0);
 assert.equal(select("#incident-summary").textContent,"");
 assert.equal(select("#backup-health").textContent,"");

 assert.ok(requests.includes("/v1/auth/refresh"));
 assert.equal(select(".submit").disabled,false);
 mode="timeout";await select("#refresh").handlers.click();
 assert.match(select("#updated").textContent,/timed out/);
 assert.equal(select("#refresh").disabled,false);
 mode="normal";await select("#refresh").handlers.click();
 assert.match(select("#updated").textContent,/Updated/);
 select("#logout").handlers.click();
 assert.ok(requests.includes("/v1/auth/logout"));
});