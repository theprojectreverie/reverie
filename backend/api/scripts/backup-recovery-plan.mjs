// Bounded, read-only recovery planning. Never restores into the live database.
import {createHash} from "node:crypto";
import {createReadStream} from "node:fs";
import {readdir,lstat,realpath,open,unlink} from "node:fs/promises";
import {join,relative,isAbsolute} from "node:path";
import {verifyArchive} from "./encrypted-backup.mjs";
const pattern=/^reverie-(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z-[a-f0-9]{12}\.rvbak$/;
function archiveTime(name){
 const m=pattern.exec(name);if(!m)return null;
 const iso=m[1]+"-"+m[2]+"-"+m[3]+"T"+m[4]+":"+m[5]+":"+m[6]+".000Z";
 const n=Date.parse(iso);return Number.isFinite(n)&&new Date(n).toISOString()===iso?n:null;
}
async function hash(file){const h=createHash("sha256");for await(const chunk of createReadStream(file))h.update(chunk);return h.digest("hex");}
async function inspect(dir,name,key){
 if(!dir)return {status:"not_configured"};
 const file=join(dir,name);
 let info;try{info=await lstat(file);}catch(e){return {status:e.code==="ENOENT"?"missing":"unavailable"};}
 if(!info.isFile())return {status:"not_regular"};
 try{await verifyArchive(file,key);return {status:"authenticated",sha256:await hash(file)};}
 catch{return {status:"verification_failed"};}
}
export async function planRecovery({dir,replicaDir,key,limit=7,now=Date.now()}){
 if(!Number.isInteger(limit)||limit<1||limit>30)throw Error("Recovery scan limit must be 1?30");
 const primary=await realpath(dir),replica=replicaDir?await realpath(replicaDir):null;
 if(replica){
  const contains=r=>r===""||(!r.startsWith("..")&&!isAbsolute(r));
  if(contains(relative(primary,replica))||contains(relative(replica,primary)))throw Error("Separate directories required");
 }
 // Coordinate with backup creation and independent replication.
 const lockPath=join(primary,".reverie-backup.lock");let lock;
 try{lock=await open(lockPath,"wx",0o600);}catch(e){if(e.code==="EEXIST")return {status:"locked",candidate:null,examined:[]};throw e;}
 try{
  const names=new Set();
  for(const folder of [primary,replica].filter(Boolean))
   for(const entry of await readdir(folder,{withFileTypes:true})){
    const time=archiveTime(entry.name);
    if(time!==null&&time<=now)names.add(entry.name);
   }
  const sorted=[...names].sort().reverse(),examined=[];
  let candidate=null;
  for(const name of sorted.slice(0,limit)){
   const p=await inspect(primary,name,key),r=await inspect(replica,name,key);
   const both=p.status==="authenticated"&&r.status==="authenticated";
   const conflict=both&&p.sha256!==r.sha256;
   const row={name,primary:p.status,replica:r.status,agreement:conflict?"conflict":both?"identical":"not_compared"};
   examined.push(row);
   // Conflicting authenticated copies need operator investigation; never pick
   // one arbitrarily. A single authenticated copy is usable for a restore drill.
   if(!conflict&&(p.status==="authenticated"||r.status==="authenticated")){
    candidate={name,source:p.status==="authenticated"?"primary":"replica",archiveTime:new Date(archiveTime(name)).toISOString(),ageHours:Math.round((now-archiveTime(name))/360000)/10,replicated:both};
    break;
   }
  }
  return {status:candidate?(examined.length===1?"latest_authenticated":"older_authenticated"):"no_authenticated_candidate",candidate,examined,availableNames:sorted.length,limit,requiresRestoreVerification:true};
 }finally{await lock.close();await unlink(lockPath);}
}
