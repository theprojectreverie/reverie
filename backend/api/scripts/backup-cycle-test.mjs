import assert from "node:assert/strict";
import {mkdtemp,rm,readdir,writeFile,unlink} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {randomBytes} from "node:crypto";
import {Readable} from "node:stream";
import {encryptArchive,verifyArchive} from "./encrypted-backup.mjs";
import {runBackupCycle,readBackupState} from "./backup-cycle.mjs";
const dir=await mkdtemp(join(tmpdir(),"reverie-cycle-qa-")),key=randomBytes(32);
const hour=3600000,day=24*hour;
let clock=Date.UTC(2026,10,26,8),calls=0,fail=false;
let unblock,entered;
const gate=new Promise(r=>unblock=r),started=new Promise(r=>entered=r);
const backup=async()=>{
 calls++;
 if(calls===1){entered();await gate;}
 if(fail)throw Error("Synthetic backup failure");
 const stamp=new Date(clock).toISOString().replace(/[-:]/g,"").replace(/\.[0-9]+/,"");
 const name="reverie-"+stamp+"-"+randomBytes(6).toString("hex")+".rvbak";
 await encryptArchive(Readable.from([Buffer.from("synthetic backup "+calls)]),join(dir,name),key);
 return {name};
};
const run=(scheduled=true)=>runBackupCycle({dir,backup,scheduled,now:()=>clock});
try{
 assert.equal((await readBackupState(dir)).status,"never_run");
 const first=run();await started;
 assert.equal((await run()).status,"locked");
 assert.equal((await readBackupState(dir)).status,"running");
 unblock();
 const success=await first;assert.equal(success.status,"encrypted_archive_verified");
 await verifyArchive(join(dir,success.name),key);
 assert.equal((await readBackupState(dir)).lastSuccess,clock);
 assert.equal((await run()).status,"not_due");assert.equal(calls,1);
 // State is loaded anew each invocation, including across a scheduler restart.
 clock+=day-1;assert.equal((await run()).status,"not_due");
 clock+=1;fail=true;
 await assert.rejects(run(),/Synthetic backup failure/);
 const failed=await readBackupState(dir);assert.equal(failed.status,"failed");assert.equal(failed.archive,success.name);
 assert.equal((await run()).status,"retry_cooldown");
 clock+=hour-1;assert.equal((await run()).status,"retry_cooldown");
 clock+=1;fail=false;const retry=await run();assert.equal(retry.status,"encrypted_archive_verified");assert.equal(calls,3);
 await unlink(join(dir,retry.name));clock+=hour;
 const missing=await run();assert.equal(missing.status,"encrypted_archive_verified");
 // Manual operator backups remain possible without waiting for the schedule.
 assert.equal((await run(false)).status,"encrypted_archive_verified");
 clock-=day;await assert.rejects(run(),/clock moved backwards/);clock+=day;
 await writeFile(join(dir,".reverie-backup-state.json"),"{invalid");
 await assert.rejects(run(),/Invalid backup state/);
 assert.ok(!(await readdir(dir)).some(n=>n.endsWith(".lock")||n.includes(".partial-")));
 console.log("PASS durable scheduling, duplicate-run lock, daily cadence, failure retry, missing archive, manual override, clock guard and corrupt-state fail-closed");
}finally{await rm(dir,{recursive:true,force:true});}
