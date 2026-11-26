// Operator-only inventory. No plaintext output, writes to backups, or restore.
import {realpath} from "node:fs/promises";
import {isAbsolute,relative} from "node:path";
import {fileURLToPath} from "node:url";
import {parseBackupKey} from "./encrypted-backup.mjs";
import {planRecovery} from "./backup-recovery-plan.mjs";
if(!process.argv.includes("--execute"))throw Error("Explicit --execute required");
const root=await realpath(fileURLToPath(new URL("../../../",import.meta.url)));
async function privateDirectory(value){
 if(!value||!isAbsolute(value))throw Error("Absolute existing private directory required");
 const path=await realpath(value),rel=relative(root,path);
 if(rel===""||(!rel.startsWith("..")&&!isAbsolute(rel)))throw Error("Directory must be outside repository");
 return path;
}
const result=await planRecovery({dir:await privateDirectory(process.env.REVERIE_BACKUP_DIR),replicaDir:process.env.REVERIE_BACKUP_REPLICA_DIR?await privateDirectory(process.env.REVERIE_BACKUP_REPLICA_DIR):undefined,key:parseBackupKey(process.env.REVERIE_BACKUP_KEY_HEX)});
console.log(JSON.stringify(result));
if(!result.candidate)process.exitCode=1;
