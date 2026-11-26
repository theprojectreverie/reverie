import http from "node:http";
import net from "node:net";
// This listener is deliberately status-only. Never forward arbitrary paths
// to the private API or expose an internal address in a response.
const port=Number(process.env.REVERIE_ALPHA_GATEWAY_PORT||8790);
const upstreamPort=Number(process.env.REVERIE_ALPHA_UPSTREAM_PORT||8787);
const maxRequests=120, windowMs=60000;
let start=Date.now(),requests=0;
function json(res,code,body,head=false){
 const data=JSON.stringify(body);
 res.writeHead(code,{"content-type":"application/json; charset=utf-8","content-length":Buffer.byteLength(data),"cache-control":"no-store","x-content-type-options":"nosniff","referrer-policy":"no-referrer","content-security-policy":"default-src 'none'","connection":"close"});
 res.end(head?undefined:data);
}
function rateAllowed(){
 const now=Date.now();if(now-start>=windowMs){start=now;requests=0;}
 return ++requests<=maxRequests;
}
const server=http.createServer({maxHeaderSize:8192,requestTimeout:5000,headersTimeout:5000,keepAliveTimeout:1000},(req,res)=>{
 const head=req.method==="HEAD";
 if(!rateAllowed()){res.setHeader("retry-after","60");return json(res,429,{error:"rate_limited"},head);}
 // Exact status paths only. Ignore the single known browser referral tag
 // on these read-only responses, never forward user-controlled URLs.
 const path=req.url?.replace(/\?utm_source=chatgpt\.com$/,"");
 if(!["GET","HEAD"].includes(req.method)||!["/","/health","/alpha/status"].includes(path)||req.headers.upgrade||req.headers["transfer-encoding"]||Number(req.headers["content-length"]||0)!==0)return json(res,404,{error:"not_found"},head);
 if(path!=="/health")return json(res,200,{service:"Reverie",status:"private_alpha_preparation",gameplayOpen:false},head);
 const probe=http.get({hostname:"127.0.0.1",port:upstreamPort,path:"/health",timeout:2000},up=>{
  up.resume();up.once("end",()=>{if(!res.writableEnded)json(res,up.statusCode===200?200:503,{service:"Reverie",status:up.statusCode===200?"ok":"unavailable",gameplayOpen:false},head)});
 });
 probe.once("timeout",()=>probe.destroy());probe.once("error",()=>{if(!res.writableEnded)json(res,503,{service:"Reverie",status:"unavailable",gameplayOpen:false},head)});
});
server.maxConnections=32;
server.on("upgrade",(_req,socket)=>socket.end("HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"));
server.on("connect",(_req,socket)=>socket.destroy());
server.on("clientError",(_err,socket)=>socket.destroy());
server.listen(port,"127.0.0.1",()=>console.log("Reverie status-only gateway listening on loopback port "+server.address().port));