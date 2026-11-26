import {createHash,randomBytes} from "node:crypto";
import {createReadStream,createWriteStream} from "node:fs";
import {open,link,unlink,lstat,rename,realpath} from "node:fs/promises";
import {pipeline} from "node:stream/promises";
import {join,relative,isAbsolute} from "node:path";
import {readBackupState} from "./backup-cycle.mjs";
import {verifyArchive} from "./encrypted-backup.mjs";
const DAY=86400000;
export const reportName=".reverie-backup-verification.json";
async function regular(file){
 try{return (await lstat(file)).isFile();}catch(e){if(e.code==="ENOENT")return false;throw e;}
}
async function digest(file){
 const hash=createHash("sha256");for await(const b of createReadStream(file))hash.update(b);return hash.digest("hex");
}
export async function copyVerifiedArchive(source,destination,key){
 if(!await regular(source))throw Error("Missing source archive");
 await verifyArchive(source,key);
 const expected=await digest(source);
 if(await regular(destination)){
  await verifyArchive(destination,key);
  if(await digest(destination)!==expected)throw Error("Existing replica differs");
  return "already_verified";
 }
 const temp=destination+".partial-"+randomBytes(8).toString("hex");
 try{
  await pipeline(createReadStream(source),createWriteStream(temp,{flags:"wx",mode:0o600}));
  await verifyArchive(temp,key);
  if(await digest(temp)!==expected)throw Error("Replica checksum mismatch");
  const h=await open(temp,"r+");try{await h.sync();}finally{await h.close();}
  await link(temp,destination);
  return "copied";
 }finally{await unlink(temp).catch(()=>{});}
}
async function publishReport(dir,report){
 const target=join(dir,reportName),temp=target+".partial-"+randomBytes(8).toString("hex");
 try{
  const h=await open(temp,"wx",0o600);try{await h.writeFile(JSON.stringify(report));await h.sync();}finally{await h.close();}
  await rename(temp,target);
 }finally{await unlink(temp).catch(()=>{});}
}
export async function checkBackup({dir,key,replicaDir,copy=false,now=Date.now}){
 const primary=await realpath(dir);
 let mirror;
 if(replicaDir){
  mirror=await realpath(replicaDir);
  const a=relative(primary,mirror),b=relative(mirror,primary);
  const contained=x=>x===""||(!x.startsWith("..")&&!isAbsolute(x));
  if(contained(a)||contained(b))throw Error("Replica must be a separate directory");
 }
 if(copy&&!mirror)throw Error("Replica directory required");
 const lockPath=join(primary,".reverie-backup.lock");
 let lock;
 try{lock=await open(lockPath,"wx",0o600);}catch(e){if(e.code==="EEXIST")return {status:"locked"};throw e;}
 try{
  const t=now(),report={version:1,checkedAt:new Date(t).toISOString(),lastSuccessAt:null,backupAgeHours:null,primary:"unknown",replica:mirror?"unknown":"not_configured",schedule:"unknown"};
  let state;
  try{state=await readBackupState(primary);}catch{report.primary="invalid_state";await publishReport(primary,report);return report;}
  if(!state.archive){report.primary="missing";report.schedule=state.lastAttempt!==null&&state.lastAttempt>t?"clock_error":state.status==="failed"||state.status==="running"?"last_attempt_failed":"never_run";}
  else{
   if(state.lastSuccess>t){report.schedule="clock_error";}
   else{
    report.lastSuccessAt=new Date(state.lastSuccess).toISOString();
    report.backupAgeHours=Math.round((t-state.lastSuccess)/360000)/10;
    report.schedule=t-state.lastSuccess>26*3600000?"overdue":(state.status==="failed"||state.status==="running")?"last_attempt_failed":"current";
   }
   const file=join(primary,state.archive);
   if(!await regular(file))report.primary="missing";
   else try{await verifyArchive(file,key);report.primary="verified";}catch{report.primary="verification_failed";}
   if(mirror){
    const dest=join(mirror,state.archive);
    if(copy&&report.primary==="verified"){
     try{await copyVerifiedArchive(file,dest,key);}catch{report.replica="copy_failed";}
    }
    if(report.replica!=="copy_failed"){
     if(!await regular(dest))report.replica="missing";
     else try{
      await verifyArchive(dest,key);
      report.replica=report.primary==="verified"?(await digest(file)===await digest(dest)?"verified":"mismatch"):"authenticated_uncompared";
     }catch{report.replica="verification_failed";}
    }
   }
  }
  await publishReport(primary,report);return report;
 }finally{await lock.close();await unlink(lockPath);}
}
