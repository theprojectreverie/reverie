import http from "node:http";
import {randomBytes,createHash} from "node:crypto";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {pathToFileURL} from "node:url";
const digest=x=>createHash("sha256").update(x).digest("hex");
const publicOrigin="https://reverie.tailad29fa.ts.net:10000";
const uuid="[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}";
const getPaths=new Set(["/developer","/v1/developer/activity","/v1/developer/server-health","/v1/developer/staff/","/v1/developer/staff/statistics","/v1/developer/moderation/","/v1/developer/moderation/players","/v1/developer/moderation/suspensions","/v1/developer/moderation/appeals","/v1/developer/moderation/reports","/v1/developer/rewards/players","/v1/developer/rewards/history"]);
const postPaths=new Set(["/v1/auth/login","/v1/auth/refresh","/v1/auth/logout","/v1/developer/staff/","/v1/developer/moderation/","/v1/developer/moderation/suspensions","/v1/developer/moderation/appeals","/v1/developer/moderation/reports","/v1/developer/rewards/grant"]);
const valid=(method,path)=>method==="GET"?(getPaths.has(path)||new RegExp("^/v1/developer/moderation/players/"+uuid+"$").test(path)):method==="POST"&&(postPaths.has(path)||/^\/v1\/developer\/server-incidents\/[0-9]{1,19}\/acknowledge$/.test(path));
const gateHtml='<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Reverie staff access</title><style>body{background:#17131e;color:#eee7df;font:16px system-ui;margin:0;padding:24px}main{max-width:440px;margin:12vh auto;background:#25202d;border:1px solid #65536c;border-radius:16px;padding:24px}input,button{box-sizing:border-box;width:100%;padding:14px;margin-top:12px;border-radius:8px;font:inherit}input{background:#16131c;color:#fff;border:1px solid #78668b}button{background:#d2af79;color:#18131c;border:0;font-weight:600}</style><main><h1>Reverie staff access</h1><p>Enter your individual administration access code, then sign in with your assigned Reverie account.</p><form method="post" action="/admin-access"><label for="code">Private access code</label><input id="code" name="code" type="password" autocomplete="off" required maxlength="64"><button>Continue</button></form><p>Keep your access code private. Request a replacement from the owner if needed.</p></main></html>';
function json(res,status,data){res.writeHead(status,{"content-type":"application/json","cache-control":"no-store","x-content-type-options":"nosniff"});res.end(JSON.stringify(data))}
function gate(res){res.writeHead(200,{"content-type":"text/html; charset=utf-8","cache-control":"no-store","content-security-policy":"default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'","referrer-policy":"no-referrer","x-content-type-options":"nosniff"});res.end(gateHtml)}
function redirect(res,cookie){res.writeHead(303,{"location":"/developer","cache-control":"no-store",...(cookie?{"set-cookie":cookie}:{})});res.end()}
function claims(token){try{return JSON.parse(Buffer.from(token.split(".")[1],"base64url").toString("utf8"))}catch{return null}}
async function body(req,max=16384){const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>max)throw Error("body_too_large");chunks.push(chunk)}return Buffer.concat(chunks)}
export function createAdminGateway({accessFile,origin=publicOrigin,upstreamPort=8787}){
 const sessions=new Map();let attempts=0,requests=0,windowStart=Date.now(),inflight=0;
 function access(){try{const data=JSON.parse(readFileSync(accessFile,"utf8"));return Array.isArray(data.entries)?data.entries:[]}catch{return []}}
 function session(req){const cookie=(req.headers.cookie??"").split(";").map(x=>x.trim()).find(x=>x.startsWith("__Host-reverie-admin="));if(!cookie)return null;const key=digest(cookie.slice("__Host-reverie-admin=".length)),s=sessions.get(key);if(!s||s.expires<=Date.now()){sessions.delete(key);return null}const entry=access().find(e=>e.hash===s.hash&&e.accountId===s.accountId);if(!entry){sessions.delete(key);return null}return {...s,key,entry}}
 const server=http.createServer({requestTimeout:12000,headersTimeout:5000,maxHeaderSize:8192},async(req,res)=>{
  const now=Date.now();if(now-windowStart>=60000){windowStart=now;requests=0;attempts=0;for(const [key,s] of sessions)if(s.expires<=now)sessions.delete(key)}
  if(++requests>300)return json(res,429,{error:"admin_gateway_rate_limited"});
  const raw=req.url??"",path=raw.split("?")[0];if(raw.length>2048||!/^\/[a-zA-Z0-9_/-]*$/.test(path)||path.includes("//"))return json(res,404,{error:"not_found"});
  if(req.method==="POST"&&req.headers.origin!==origin)return json(res,403,{error:"origin_required"});
  if(req.method==="GET"&&(path==="/"||path==="/admin-access"))return session(req)?redirect(res):gate(res);
  if(req.method==="POST"&&path==="/admin-access"){
   if(++attempts>12)return json(res,429,{error:"too_many_access_attempts"});
   if(!/^application\/x-www-form-urlencoded(?:;|$)/i.test(req.headers["content-type"]??""))return json(res,415,{error:"form_required"});
   try{
    const params=new URLSearchParams((await body(req,512)).toString("utf8")),code=params.get("code");
    const entry=typeof code==="string"&&/^[A-Za-z0-9_-]{43}$/.test(code)?access().find(e=>e.hash===digest(code)):null;
    if(!entry)return json(res,403,{error:"invalid_access_code"});
    if(sessions.size>=100)return json(res,503,{error:"session_limit"});
    const prior=session(req);if(prior)sessions.delete(prior.key);
    const rawToken=randomBytes(32).toString("base64url");sessions.set(digest(rawToken),{hash:entry.hash,accountId:entry.accountId,expires:now+8*3600000});
    return redirect(res,"__Host-reverie-admin="+rawToken+"; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=28800");
   }catch{return json(res,400,{error:"invalid_access_form"})}
  }
  if(!valid(req.method,path))return json(res,404,{error:"not_found"});
  const s=session(req);if(!s)return req.method==="GET"&&path==="/developer"?gate(res):json(res,401,{error:"admin_access_required"});
  if(path!=="/developer"&&!["/v1/auth/login","/v1/auth/refresh","/v1/auth/logout"].includes(path)){
   const bearer=req.headers.authorization;
   // Bind the second access gate to the assigned account. The private API
   // independently verifies the JWT signature, session version and role.
   if(typeof bearer!=="string"||!bearer.startsWith("Bearer ")||claims(bearer.slice(7))?.sub!==s.accountId)return json(res,403,{error:"assigned_account_required"});
  }
  if(inflight>=8)return json(res,503,{error:"admin_gateway_busy"});inflight++;
  try{
   let payload;
   if(req.method==="POST"){
    if(!/^application\/json(?:;|$)/i.test(req.headers["content-type"]??""))return json(res,415,{error:"json_required"});
    payload=await body(req);
    if(path==="/v1/auth/login"){
     const data=JSON.parse(payload.toString("utf8"));
     if(typeof data.playerName!=="string"||data.playerName.trim().toLowerCase()!==s.entry.name.toLowerCase())return json(res,403,{error:"assigned_account_required"});
    }
   }
   const headers={host:"127.0.0.1:8787",accept:req.headers.accept??"application/json"};
   if(typeof req.headers.authorization==="string")headers.authorization=req.headers.authorization;
   if(payload){headers["content-type"]="application/json";headers["content-length"]=payload.length}
   await new Promise(resolve=>{
    const up=http.request({hostname:"127.0.0.1",port:upstreamPort,path:raw,method:req.method,headers,timeout:10000},r=>{
     const h={"content-type":r.headers["content-type"]??"application/json","cache-control":"no-store","x-content-type-options":"nosniff","referrer-policy":"no-referrer"};
     if(r.headers["content-security-policy"])h["content-security-policy"]=r.headers["content-security-policy"];
     if(r.headers["retry-after"])h["retry-after"]=r.headers["retry-after"];
     if(r.statusCode>=300&&r.statusCode<400){r.resume();json(res,502,{error:"unexpected_redirect"});resolve();return}
     if((path==="/v1/auth/login"||path==="/v1/auth/refresh")&&r.statusCode===200){
      const parts=[];let n=0;r.on("data",x=>{n+=x.length;if(n>65536)r.destroy();else parts.push(x)});
      r.on("end",()=>{try{const data=JSON.parse(Buffer.concat(parts).toString("utf8"));if(claims(data.accessToken)?.sub!==s.accountId)json(res,403,{error:"assigned_account_required"});else{res.writeHead(200,h);res.end(JSON.stringify(data))}}catch{json(res,502,{error:"invalid_auth_response"})}resolve()});
     }else{
      if(path==="/v1/auth/logout"){sessions.delete(s.key);h["set-cookie"]="__Host-reverie-admin=; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=0"}
      res.writeHead(r.statusCode??502,h);r.pipe(res);r.on("end",resolve);
     }
     r.on("error",()=>{if(!res.headersSent)json(res,502,{error:"backend_unavailable"});else res.destroy();resolve()});
    });
    up.on("timeout",()=>up.destroy());up.on("error",()=>{if(!res.headersSent)json(res,502,{error:"backend_unavailable"});else res.destroy();resolve()});res.on("close",()=>{if(!res.writableEnded)up.destroy();resolve()});up.end(payload);
   });
  }catch{if(!res.headersSent)json(res,400,{error:"invalid_request"});else res.destroy()}finally{inflight--}
 });
 server.maxConnections=32;server.on("upgrade",(_req,s)=>s.destroy());server.on("connect",(_req,s)=>s.destroy());server.on("clientError",(_e,s)=>s.destroy());return server;
}
if(import.meta.url===pathToFileURL(process.argv[1]??"").href){
 const accessFile=join(process.env.LOCALAPPDATA,"Reverie","AdminGateway","access.json");
 createAdminGateway({accessFile}).listen(8792,"127.0.0.1",()=>console.log("Private administration gateway ready on loopback 8792"));
}