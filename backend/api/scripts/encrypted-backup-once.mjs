// Explicit operator invocation only; no background job is installed.
import {spawn} from "node:child_process";
import {randomBytes} from "node:crypto";
import {mkdir,realpath} from "node:fs/promises";
import {join,resolve,relative,isAbsolute} from "node:path";
import {fileURLToPath} from "node:url";
import {encryptArchive,parseBackupKey,rotationCandidates} from "./encrypted-backup.mjs";
import {runBackupCycle} from "./backup-cycle.mjs";
const u=new URL(process.env.DATABASE_URL);
if(process.env.NODE_ENV==="production"||!["127.0.0.1","localhost","[::1]"].includes(u.hostname))throw Error("Local development only; configure a separate production backup service");
if(!process.argv.includes("--execute"))throw Error("Explicit --execute required; this exports sensitive local database contents");
const key=parseBackupKey(process.env.REVERIE_BACKUP_KEY_HEX);
const root=await realpath(fileURLToPath(new URL("../../../",import.meta.url)));
if(!process.env.REVERIE_BACKUP_DIR||!isAbsolute(process.env.REVERIE_BACKUP_DIR))throw Error("Absolute private backup directory required");
const dir=resolve(process.env.REVERIE_BACKUP_DIR);
const inside=relative(root,dir);if(inside===""||(!inside.startsWith("..")&&!isAbsolute(inside)))throw Error("Keep backups outside repository");
await mkdir(dir,{recursive:true,mode:0o700});
const actual=await realpath(dir),rel=relative(root,actual);
if(rel===""||(!rel.startsWith("..")&&!isAbsolute(rel)))throw Error("Resolved backup path is inside repository");
const result=await runBackupCycle({dir:actual,scheduled:process.argv.includes("--scheduled"),backup:async()=>{
 const stamp=new Date().toISOString().replace(/[-:]/g,"").replace(/\.[0-9]+/,"");
 const name="reverie-"+stamp+"-"+randomBytes(6).toString("hex")+".rvbak";
 const exe=process.env.REVERIE_PG_BIN?join(process.env.REVERIE_PG_BIN,process.platform==="win32"?"pg_dump.exe":"pg_dump"):"pg_dump";
 const env={...process.env,PGHOST:u.hostname.replace(/^\[|\]$/g,""),PGPORT:u.port||"5432",PGUSER:decodeURIComponent(u.username),PGPASSWORD:decodeURIComponent(u.password),PGSSLMODE:"disable"};
 for(const k of Object.keys(env))if(k!=="PGPASSWORD"&&/SECRET|TOKEN|PASSWORD|DATABASE_URL|BACKUP_KEY|STRIPE/i.test(k))delete env[k];
 const child=spawn(exe,["--format=custom","--no-owner","--no-privileges","--dbname",decodeURIComponent(u.pathname.slice(1))],{env,stdio:["ignore","pipe","ignore"],windowsHide:true});
 const done=new Promise((resolve,reject)=>{child.once("error",reject);child.once("exit",code=>code===0?resolve():reject(Error("pg_dump failed: "+code)));});done.catch(()=>{});
 const timeout=setTimeout(()=>child.kill(),2*60*60*1000);timeout.unref();
 try{await encryptArchive(child.stdout,join(actual,name),key,()=>done);}catch(e){child.kill();await done.catch(()=>{});throw e;}finally{clearTimeout(timeout);}
 return {name};
}});
console.log(JSON.stringify({...result,rotationCandidates:result.status==="encrypted_archive_verified"?await rotationCandidates(actual):[],retention:"review_only"}));
