// Explicit, local filesystem verification. No network upload is performed.
import {realpath} from "node:fs/promises";
import {isAbsolute,relative} from "node:path";
import {fileURLToPath} from "node:url";
import {parseBackupKey} from "./encrypted-backup.mjs";
import {checkBackup} from "./backup-verification.mjs";
if(!process.argv.includes("--execute"))throw Error("Explicit --execute required");
const root=await realpath(fileURLToPath(new URL("../../../",import.meta.url)));
async function privateDirectory(value){
 if(!value||!isAbsolute(value))throw Error("Absolute existing private directory required");
 const path=await realpath(value),rel=relative(root,path);
 if(rel===""||(!rel.startsWith("..")&&!isAbsolute(rel)))throw Error("Directory must be outside repository");
 return path;
}
const dir=await privateDirectory(process.env.REVERIE_BACKUP_DIR);
const replicaDir=process.env.REVERIE_BACKUP_REPLICA_DIR?await privateDirectory(process.env.REVERIE_BACKUP_REPLICA_DIR):undefined;
const report=await checkBackup({dir,replicaDir,key:parseBackupKey(process.env.REVERIE_BACKUP_KEY_HEX),copy:process.argv.includes("--copy")});
console.log(JSON.stringify(report));
if(report.status==="locked")process.exitCode=2;
else if(report.primary!=="verified"||report.schedule!=="current"||!["verified","not_configured"].includes(report.replica))process.exitCode=1;
