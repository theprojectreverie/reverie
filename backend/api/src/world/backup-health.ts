import {lstat,readFile} from "node:fs/promises";
import {isAbsolute} from "node:path";
import {z} from "zod";
const report=z.object({
 version:z.literal(1),
 checkedAt:z.string().datetime(),
 lastSuccessAt:z.string().datetime().nullable(),
 backupAgeHours:z.number().finite().nonnegative().nullable(),
 primary:z.enum(["unknown","invalid_state","missing","verified","verification_failed"]),
 replica:z.enum(["unknown","not_configured","copy_failed","missing","verified","mismatch","authenticated_uncompared","verification_failed"]),
 schedule:z.enum(["unknown","never_run","clock_error","overdue","last_attempt_failed","current"])
}).strict();
export async function readBackupHealth(path:string|undefined,now=Date.now()){
 if(!path)return {status:"not_configured" as const};
 if(!isAbsolute(path))return {status:"report_unavailable" as const};
 try{
  const info=await lstat(path);
  if(!info.isFile()||info.size>4096)return {status:"report_unavailable" as const};
  const parsed=report.safeParse(JSON.parse(await readFile(path,"utf8")));
  if(!parsed.success)return {status:"report_unavailable" as const};
  const r=parsed.data,checked=Date.parse(r.checkedAt),success=r.lastSuccessAt?Date.parse(r.lastSuccessAt):null;
  if(checked>now||success!==null&&success>checked)return {status:"report_unavailable" as const};
  const age=success===null?null:Math.round((now-success)/360000)/10;
  const stale=now-checked>26*3600000;
  const schedule=age!==null&&age>26?"overdue":r.schedule;
  return {status:stale?"report_stale":r.primary!=="verified"||schedule!=="current"||r.replica!=="verified"?"attention":"healthy",checkedAt:r.checkedAt,lastSuccessAt:r.lastSuccessAt,backupAgeHours:age,primary:r.primary,replica:r.replica,schedule};
 }catch{return {status:"report_unavailable" as const};}
}
