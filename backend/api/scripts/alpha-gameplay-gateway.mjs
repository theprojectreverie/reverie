import http from "node:http";
import {pathToFileURL} from "node:url";
const UUID="[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}";
const paths={
 GET:{auth:["wallet"],chat:["moderation-status","stickers","contacts","messages","blocks"],guilds:["me","competition","search"],social:["championship-hall","season-challenges","season-results","leaderboard","friend-profile","profile","companion-name","menu-character","search","summary","friends"],summon:["state","history"],"daily-quests":["","weekly","monthly","achievements","history"],"co-op":["lobbies/current"],pvp:["queue/status"]},
 POST:{auth:["register","login","refresh","logout","logout-all","suspension-appeal"],chat:["reports","moderation-ack","messages","block","unblock"],guilds:["competition/claim","raid/start","raid/action","raid/abandon","raid/claim","shop/buy","perks/purchase","treasury/donate","missions/claim","create","apply","invite","application","invitation","cancel","role","kick","leave","settings"],social:["showcase","leaderboard/visibility","season-challenges/claim","season-challenges/claim-all","season-results/claim","profile","companion-name","menu-character","title","friends"],summon:["train","upgrade","skill-upgrade","equipment","party","pull"],"daily-quests":["achievements/claim","achievements/claim-all","claim","claim-all","weekly/claim","weekly/claim-all","monthly/claim","monthly/claim-all"],"co-op":["lobbies","lobbies/join","friend-invites","friend-invites/respond"],pvp:["queue/join","queue/leave"],progression:["milestones"],"tutorial-spar":[""],"gerald-story":[""],"gardens-story":[""],"royal-gate-story":[""]}
};
const allowed=new Set();
for(const [method,groups] of Object.entries(paths))for(const [prefix,items] of Object.entries(groups))for(const item of items){const path="/v1/"+prefix+(item?"/"+item:"");allowed.add(method+" "+path);if(!item)allowed.add(method+" "+path+"/");}
const dynamic=[["POST",new RegExp("^/v1/co-op/lobbies/"+UUID+"/leave$")],["POST",new RegExp("^/v1/pvp/matches/"+UUID+"/(action|surrender)$")],["GET",new RegExp("^/v1/pvp/matches/"+UUID+"/events$")]];
function pathOf(url){if(typeof url!=="string"||url.length>2048||!url.startsWith("/")||url.startsWith("//"))return null;const p=url.split("?")[0];return /^\/[a-zA-Z0-9_/-]*$/.test(p)&&!p.includes("//")?p:null;}
function permitted(method,path){return allowed.has(method+" "+path)||dynamic.some(([m,re])=>m===method&&re.test(path));}
function json(res,status,data){res.writeHead(status,{"Content-Type":"application/json","Cache-Control":"no-store","X-Content-Type-Options":"nosniff"});res.end(JSON.stringify(data));}
const requestHeaders=(req,body)=>{const h={host:"127.0.0.1:8787",accept:"application/json","x-reverie-alpha":"1"};if(typeof req.headers.authorization==="string"&&req.headers.authorization.length<4096)h.authorization=req.headers.authorization;if(body){h["content-type"]="application/json";h["content-length"]=String(body.length)}return h;};
export function createGateway({upstreamPort=8787,maxSockets=20,maxRequests=32}={}){
 let inflight=0,sockets=0,windowStart=Date.now(),count=0;
 function rate(){if(Date.now()-windowStart>=60000){windowStart=Date.now();count=0}return ++count<=600}
 const server=http.createServer({requestTimeout:12000,headersTimeout:5000,maxHeaderSize:8192},async(req,res)=>{
  const path=pathOf(req.url);
  if(!rate())return json(res,429,{error:"alpha_rate_limited"});
  if(!path)return json(res,400,{error:"invalid_path"});
  if(req.method==="GET"&&path==="/health"){
   const probe=http.get({hostname:"127.0.0.1",port:upstreamPort,path:"/health",timeout:2000},r=>{
    r.resume();r.on("end",()=>{if(!res.writableEnded)json(res,r.statusCode===200?200:503,{service:"Reverie",status:r.statusCode===200?"ok":"unavailable",gameplayOpen:r.statusCode===200})});
   });
   probe.on("timeout",()=>probe.destroy());probe.on("error",()=>{if(!res.writableEnded)json(res,503,{service:"Reverie",status:"unavailable",gameplayOpen:false})});return;
  }
  if(!permitted(req.method,path))return json(res,404,{error:"not_found"});
  if(inflight>=maxRequests)return json(res,503,{error:"alpha_busy"});
  inflight++;
  try{
   let body;
   if(req.method==="POST"){
    if(!/^application\/json(?:;|$)/i.test(req.headers["content-type"]??""))return json(res,415,{error:"json_required"});
    const chunks=[];let size=0;
    for await(const chunk of req){size+=chunk.length;if(size>16384){res.setHeader("Connection","close");return json(res,413,{error:"body_too_large"})}chunks.push(chunk);}
    body=Buffer.concat(chunks);
    if(path==="/v1/auth/register"){
     let data;try{data=JSON.parse(body.toString("utf8"))}catch{return json(res,400,{error:"invalid_registration"})}
     if(!data||typeof data.inviteCode!=="string"||!/^[A-Za-z0-9_-]{32,100}$/.test(data.inviteCode))return json(res,403,{error:"alpha_invite_required"});
     if(typeof data.password!=="string"||data.password.length<8||data.password.length>128)return json(res,400,{error:"password_length_invalid"});
    }
    if(path==="/v1/summon/pull"){
     let data;try{data=JSON.parse(body.toString("utf8"))}catch{return json(res,400,{error:"invalid_request"})}
     if(data?.currency==="paid_moonstones")return json(res,403,{error:"paid_summons_disabled_in_alpha"});
    }
   }
   await new Promise(resolve=>{
    const up=http.request({hostname:"127.0.0.1",port:upstreamPort,path:req.url,method:req.method,headers:requestHeaders(req,body),timeout:15000},r=>{
     if(r.statusCode>=500){r.resume();json(res,503,{error:"service_unavailable"});resolve();return}
     if(r.statusCode>=300&&r.statusCode<400){r.resume();json(res,502,{error:"unexpected_redirect"});resolve();return}
     const h={"Content-Type":r.headers["content-type"]??"application/json","Cache-Control":"no-store","X-Content-Type-Options":"nosniff"};
     if(r.headers["retry-after"])h["Retry-After"]=r.headers["retry-after"];
     res.writeHead(r.statusCode??502,h);r.pipe(res);r.on("end",resolve);r.on("error",()=>{res.destroy();resolve()});
    });
    up.on("timeout",()=>up.destroy());up.on("error",()=>{if(!res.headersSent)json(res,502,{error:"backend_unavailable"});else res.destroy();resolve()});
    res.on("close",()=>{if(!res.writableEnded)up.destroy();resolve()});up.end(body);
   });
  }catch{if(!res.headersSent)json(res,400,{error:"invalid_request"});else res.destroy()}finally{inflight--}
 });
 server.on("upgrade",(req,socket,head)=>{
  if(!rate()||req.method!=="GET"||pathOf(req.url)!=="/v1/realtime"||sockets>=maxSockets||req.headers.upgrade?.toLowerCase()!=="websocket"||!req.headers.authorization){socket.end("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n");return}
  sockets++;let released=false;const release=()=>{if(!released){released=true;sockets--}};
  socket.on("close",release);socket.on("error",()=>socket.destroy());
  const headers={...requestHeaders(req),upgrade:"websocket",connection:"Upgrade","sec-websocket-key":req.headers["sec-websocket-key"],"sec-websocket-version":req.headers["sec-websocket-version"]};
  if(!headers["sec-websocket-key"]||headers["sec-websocket-version"]!=="13"){socket.destroy();return}
  const up=http.request({hostname:"127.0.0.1",port:upstreamPort,path:req.url,method:"GET",headers,timeout:5000});
  up.on("upgrade",(r,peer,buffer)=>{
   socket.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: "+r.headers["sec-websocket-accept"]+"\r\n\r\n");
   if(buffer.length)socket.write(buffer);if(head.length)peer.write(head);
   peer.on("error",()=>socket.destroy());peer.on("close",()=>socket.destroy());socket.on("close",()=>peer.destroy());
   socket.pipe(peer);peer.pipe(socket);
  });
  up.on("response",r=>{r.resume();socket.end("HTTP/1.1 "+(r.statusCode===401?"401 Unauthorized":"403 Forbidden")+"\r\nConnection: close\r\n\r\n")});
  up.on("error",()=>socket.destroy());up.on("timeout",()=>up.destroy());socket.on("close",()=>up.destroy());up.end();
 });
 server.maxConnections=64;
 server.on("connect",(_req,socket)=>socket.destroy());
 server.on("clientError",(_err,socket)=>socket.destroy());
 return server;
}
if(import.meta.url===pathToFileURL(process.argv[1]??"").href)createGateway().listen(8791,"127.0.0.1",()=>console.log("Reverie gameplay gateway candidate listening on loopback 8791"));