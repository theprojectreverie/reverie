import assert from "node:assert/strict";
import {once} from "node:events";
import {mkdtemp,writeFile,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {createGateway} from "./alpha-gameplay-gateway.mjs";
const dir=await mkdtemp(join(tmpdir(),"reverie-web-gateway-"));
await writeFile(join(dir,"index.html"),"<html>Reverie test</html>");
await writeFile(join(dir,"index.pck"),"test pack");
await writeFile(join(dir,"private.txt"),"must not be served");
const gateway=createGateway({webRoot:dir,upstreamPort:1,registrationMode:"open"});
gateway.listen(0,"127.0.0.1");await once(gateway,"listening");
try{
 const base="http://127.0.0.1:"+gateway.address().port;
 const home=await fetch(base+"/");assert.equal(home.status,200);assert.equal(await home.text(),"<html>Reverie test</html>");
 const head=await fetch(base+"/index.pck",{method:"HEAD"});assert.equal(head.status,200);assert.equal(head.headers.get("content-length"),"9");
 assert.equal((await fetch(base+"/index.pck")).status,200);
 for(const path of ["/private.txt","/v1/developer/activity","/v1/shop/catalog","/ready","//index.html"])assert.ok([400,404].includes((await fetch(base+path)).status),path);
 console.log("PASS static browser files, HEAD, private-file exclusion and protected route isolation");
}finally{await new Promise(r=>gateway.close(r));await rm(dir,{recursive:true,force:true});}