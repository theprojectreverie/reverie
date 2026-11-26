import test from "node:test";
import assert from "node:assert/strict";
import {runInNewContext} from "node:vm";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {compensationDashboardHtml} from "../src/routes/compensation-dashboard.js";
process.env.DATABASE_URL??="postgres://localhost/reverie_test";
process.env.JWT_SECRET??="test-secret-that-is-long-enough-for-jwt";
const {makeCompensationRoutes}=await import("../src/routes/compensation.js");

test("review dashboard is a read-only shell with no embedded account data",async()=>{
 const app=Fastify();
 await app.register(jwt,{secret:"isolated-test-secret"});
 await app.register(makeCompensationRoutes(""),{prefix:"/v1/developer/compensation"});
 try{
  const page=await app.inject({url:"/v1/developer/compensation/dashboard"});
  assert.equal(page.statusCode,200);
  assert.equal(page.headers["cache-control"],"no-store");
  assert.match(String(page.headers["content-security-policy"]),/connect-src 'self'/);
  assert.match(page.body,/Read-only review mode/);
  assert.doesNotMatch(page.body,/\/decide|localStorage|sessionStorage|innerHTML/);
 }finally{await app.close();}
});

class Element{
 textContent="";className="";value="";disabled=false;children:Element[]=[];
 listeners:Record<string,(event?:any)=>any>={};
 classList={add:(_v:string)=>{},remove:(_v:string)=>{}};
 append(...children:Element[]){this.children.push(...children);}
 replaceChildren(){this.children=[];}
 addEventListener(name:string,listener:(event?:any)=>any){this.listeners[name]=listener;}
}
function browser(){
 const nodes=new Map<string,Element>();
 const get=(id:string)=>{if(!nodes.has(id))nodes.set(id,new Element());return nodes.get(id)!};
 const responses:Array<any>=[];
 const requests:Array<{url:string;options:any}>=[];
 const document={getElementById:get,createElement:()=>new Element()};
 const script=compensationDashboardHtml.match(/<script>([\s\S]*?)<\/script>/)![1]!;
 runInNewContext(script,{document,fetch:async(url:string,options:any)=>{requests.push({url,options});const r=responses.shift();return typeof r==="function"?r():r;},Date,Number,String,encodeURIComponent,Array,Error});
 return {get,responses,requests};
}
const ok=(data:any)=>({ok:true,status:200,json:async()=>data});
test("dashboard renders escaped record text, filters and clears records on sign-out",async()=>{
 const b=browser();b.get("filter").value="pending_review";b.get("password").value="fixture";
 const literal="<img src=x onerror=alert(1)>";
 b.responses.push(ok({accessToken:"fixture"}),ok({reviews:[{banner_id:"banner_test",status:"pending_review",player_id:"fixture-player",pull_id:"fixture-pull",roll_index:9,recorded_character:literal,recorded_featured:false,suggestedCharacter:null}]}));
 await b.get("login").listeners.submit!({preventDefault(){}});
 assert.equal(b.get("password").value,"");
 assert.equal(b.get("reviews").children.length,1);
 const fields=b.get("reviews").children[0]!.children[2]!.children;
 assert.ok(fields.some(e=>e.textContent===literal));
 assert.ok(fields.some(e=>e.textContent==="Original banner not verified"));
 b.get("filter").value="resolved";b.responses.push(ok({reviews:[]}));
 await b.get("filter").listeners.change!();
 assert.match(b.requests.at(-1)!.url,/status=resolved$/);
 assert.equal(b.get("status").textContent,"No reviews in this status.");
 b.get("logout").listeners.click!();
 assert.equal(b.get("reviews").children.length,0);
 assert.equal(b.get("status").textContent,"No data loaded.");
});
test("dashboard denies access and ignores in-flight records after sign-out",async()=>{
 const b=browser();b.get("filter").value="pending_review";
 b.responses.push(ok({accessToken:"fixture"}),{ok:false,status:403});
 await b.get("login").listeners.submit!({preventDefault(){}});
 assert.match(b.get("error").textContent,/does not have compensation support access/);
 assert.equal(b.get("reviews").children.length,0);
 let finish:(v:any)=>void=()=>{};
 b.responses.push(ok({accessToken:"fixture"}),()=>new Promise(resolve=>{finish=resolve;}));
 const pending=b.get("login").listeners.submit!({preventDefault(){}});
 await new Promise(resolve=>setImmediate(resolve));
 b.get("logout").listeners.click!();
 finish(ok({reviews:[{banner_id:"stale"}]}));
 await pending;
 assert.equal(b.get("reviews").children.length,0);
});
