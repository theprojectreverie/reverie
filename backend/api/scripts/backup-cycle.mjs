// Durable scheduling decisions; the external scheduler invokes a short-lived job.
import {open,readFile,rename,unlink,lstat} from "node:fs/promises";
import {randomBytes} from "node:crypto";
import {join} from "node:path";
const DAY=86400000,HOUR=3600000;
const archiveName=/^reverie-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{12}\.rvbak$/;
const stateName=".reverie-backup-state.json";
export async function readBackupState(dir){
 const file=join(dir,stateName);
 let info;
 try{info=await lstat(file);}catch(e){if(e.code==="ENOENT")return {version:1,lastAttempt:null,lastSuccess:null,archive:null,status:"never_run"};throw e;}
 if(!info.isFile()||info.size>4096)throw Error("Invalid backup state; operator review required");
 let state;
 try{state=JSON.parse(await readFile(file,"utf8"));}catch{throw Error("Invalid backup state; operator review required");}
 const time=v=>v===null||(Number.isSafeInteger(v)&&v>=0);
 if(state?.version!==1||!time(state.lastAttempt)||!time(state.lastSuccess)||
    !["never_run","running","failed","verified"].includes(state.status)||
    !(state.archive===null||(typeof state.archive==="string"&&archiveName.test(state.archive)))||
    (state.lastSuccess===null)!==(state.archive===null)||
    (state.lastSuccess!==null&&state.lastAttempt===null)||
    (state.status==="verified"&&(state.lastSuccess===null||state.lastAttempt===null)))
  throw Error("Invalid backup state; operator review required");
 return state;
}
async function saveState(dir,state){
 const target=join(dir,stateName),temp=target+".partial-"+randomBytes(8).toString("hex");
 try{
  const h=await open(temp,"wx",0o600);
  try{await h.writeFile(JSON.stringify(state));await h.sync();}finally{await h.close();}
  await rename(temp,target);
 }finally{await unlink(temp).catch(()=>{});}
}
export async function runBackupCycle({dir,backup,scheduled=false,now=Date.now}){
 const lockPath=join(dir,".reverie-backup.lock");
 let lock;
 try{lock=await open(lockPath,"wx",0o600);}
 catch(e){if(e.code==="EEXIST")return {status:"locked"};throw e;}
 try{
  let state=await readBackupState(dir);
  const t=now();
  if(!Number.isSafeInteger(t)||t<0||[state.lastAttempt,state.lastSuccess].some(v=>v!==null&&v>t))
   throw Error("Backup clock moved backwards; operator review required");
  if(scheduled){
   if(state.lastSuccess!==null&&t-state.lastSuccess<DAY){
    // Do not skip a scheduled run if its recorded archive is missing or not a regular file.
    try{if((await lstat(join(dir,state.archive))).isFile())return {status:"not_due",nextDueAt:new Date(state.lastSuccess+DAY).toISOString()};}catch(e){if(e.code!=="ENOENT")throw e;}
   }
   if(state.lastAttempt!==null&&t-state.lastAttempt<HOUR)return {status:"retry_cooldown",nextDueAt:new Date(state.lastAttempt+HOUR).toISOString()};
  }
  state={...state,lastAttempt:t,status:"running"};
  await saveState(dir,state);
  try{
   const result=await backup();
   if(typeof result?.name!=="string"||!archiveName.test(result.name)||!(await lstat(join(dir,result.name))).isFile())
    throw Error("No published archive");
   state={...state,lastSuccess:Math.max(t,now()),archive:result.name,status:"verified"};
   await saveState(dir,state);
   return {...result,status:"encrypted_archive_verified",nextDueAt:new Date(state.lastSuccess+DAY).toISOString()};
  }catch(e){
   await saveState(dir,{...state,status:"failed"});
   throw e;
  }
 }finally{await lock.close();await unlink(lockPath);}
}
