// Local, synthetic restore drill. Never dumps actual player rows.
import pg from "pg";
import assert from "node:assert/strict";
import {randomBytes,randomUUID,createHash} from "node:crypto";
import {execFile,spawn} from "node:child_process";
import {promisify} from "node:util";
import {mkdtemp,readFile,rm,stat,writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import {performance} from "node:perf_hooks";
import {createServer} from "node:net";
import {createReadStream,createWriteStream} from "node:fs";
import {encryptArchive,verifyArchive} from "./encrypted-backup.mjs";
import {planRecovery} from "./backup-recovery-plan.mjs";
const run=promisify(execFile);
const u=new URL(process.env.DATABASE_URL);
assert.ok(["127.0.0.1","localhost","[::1]"].includes(u.hostname)&&process.env.NODE_ENV!=="production","loopback development only");
const dir=await mkdtemp(join(tmpdir(),"reverie-restore-qa-"));
const suffix=randomBytes(6).toString("hex"),source="reverie_qa_src_"+suffix,target="reverie_qa_dst_"+suffix;
const tools=process.env.REVERIE_PG_BIN??"";
const executable=name=>tools?join(tools,name+(process.platform==="win32"?".exe":"")):name;
const env={...process.env,PGHOST:u.hostname.replace(/^\[|\]$/g,""),PGPORT:u.port||"5432",PGUSER:decodeURIComponent(u.username),PGPASSWORD:decodeURIComponent(u.password),PGSSLMODE:"disable"};
delete env.DATABASE_URL;
const base=decodeURIComponent(u.pathname.slice(1));assert.ok(base&&base!==source&&base!==target);
const tempPassword=randomBytes(24).toString("hex"),dataDir=join(dir,"cluster"),pwFile=join(dir,"password.txt");
let admin,src,dst,clusterStarted=false;
let drillEnv,port;
const dbUrl=name=>{const v=new URL("postgresql://127.0.0.1");v.port=String(port);v.username="restore_qa";v.password=tempPassword;v.pathname="/"+name;return v.toString();};
const schema=join(dir,"schema.dump"),backup=join(dir,"synthetic.dump"),created=[];
const invoke=async(name,args,commandEnv=drillEnv??env)=>{await run(executable(name),args,{env:commandEnv,timeout:120000,windowsHide:true,maxBuffer:1024*1024});};
const restore=async(file,database)=>invoke("pg_restore",["--exit-on-error","--single-transaction","--no-owner","--no-privileges","--dbname",database,file]);
const capture=async db=>{
 const q=await db.query(`SELECT
 (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM accounts a) accounts,
 (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM players p) players,
 (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.player_id,c.currency_id) FROM player_currencies c) wallet,
 (SELECT jsonb_agg(to_jsonb(l) ORDER BY l.id) FROM currency_ledger l) ledger,
 (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM game_servers s) servers,
 (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.player_id) FROM game_server_player_state s) positions,
 (SELECT jsonb_agg(to_jsonb(e) ORDER BY e.sequence) FROM game_server_world_events e) events,
 (SELECT jsonb_agg(to_jsonb(w) ORDER BY w.server_id) FROM game_server_world_state w) checkpoints,
 (SELECT jsonb_agg(to_jsonb(i) ORDER BY i.id) FROM regional_server_incidents i) incidents`);
 return q.rows[0];
};
try{
 const listener=createServer();
 await new Promise((resolve,reject)=>listener.once("error",reject).listen(0,"127.0.0.1",resolve));port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
 drillEnv={...env,PGHOST:"127.0.0.1",PGPORT:String(port),PGUSER:"restore_qa",PGPASSWORD:tempPassword};
 await writeFile(pwFile,tempPassword+"\n",{mode:0o600});
 await invoke("initdb",["-D",dataDir,"-U","restore_qa","--auth=scram-sha-256","--pwfile="+pwFile,"--no-locale","--encoding=UTF8"],drillEnv);
 await rm(pwFile,{force:true});
 // On Windows postgres can inherit the launcher pipe handles. Use ignored
 // stdio so the long-lived child cannot keep execFile waiting for pipe EOF.
 await new Promise((resolve,reject)=>{
  const child=spawn(executable("pg_ctl"),["-D",dataDir,"-l",join(dir,"postgres.log"),"-o","-h 127.0.0.1 -p "+port,"-w","start"],{env:drillEnv,windowsHide:true,stdio:"ignore"});
  child.once("error",reject);child.once("exit",code=>code===0?resolve():reject(Error("Temporary PostgreSQL start failed: "+code)));
 });clusterStarted=true;
 admin=new pg.Client({connectionString:dbUrl("postgres")});
 await admin.connect();
 for(const name of [source,target]){await admin.query('CREATE DATABASE "'+name+'" TEMPLATE template0');created.push(name);}
 // Schema only from the current local database. No real accounts, payments,
 // credentials, chat or player progress are exported.
 await invoke("pg_dump",["--schema-only","--format=custom","--no-owner","--no-privileges","--file",schema,"--dbname",base],env);
 await restore(schema,source);
 src=new pg.Client({connectionString:dbUrl(source)});await src.connect();
 const a=(await src.query("INSERT INTO accounts(email,password_hash,email_verified,status) VALUES('restore-fixture@example.test','test-only-no-login',true,'active') RETURNING id")).rows[0].id;
 const p=(await src.query("INSERT INTO players(account_id,name) VALUES($1,'RestoreFixture') RETURNING id",[a])).rows[0].id;
 const s=(await src.query("INSERT INTO game_servers(server_key,display_name,region_id,status,next_event_sequence) VALUES('restore-fixture','Restore fixture','qa_restore','offline',1) RETURNING id")).rows[0].id;
 await src.query("INSERT INTO currencies(id,display_name) VALUES('gold','Gold')");
 await src.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'gold',1500)",[p]);
 await src.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',1500,1500,'coop_monster_defeat','monster','qa','restore-fixture')",[p]);
 await src.query("INSERT INTO game_server_players(server_id,player_id) VALUES($1,$2)",[s,p]);
 await src.query("INSERT INTO game_server_player_state(server_id,player_id,x,y) VALUES($1,$2,123.5,456.25)",[s,p]);
 await src.query("INSERT INTO game_server_world_events(server_id,sequence,event_type,player_id,payload,event_id) VALUES($1,1,'position',$2,$3,$4)",[s,p,JSON.stringify({x:123.5,y:456.25}),randomUUID()]);
 await src.query("INSERT INTO game_server_world_state(server_id,revision,state) VALUES($1,1,$2)",[s,JSON.stringify({positions:{[p]:{x:123.5,y:456.25}},sequence:1})]);
 await src.query("INSERT INTO regional_server_incidents(server_id,kind,initial_reason,current_reason,acknowledged_at,acknowledged_by,acknowledgment_note) VALUES($1,'availability','offline_reserved','offline_reserved',now(),$2,'Restore drill')",[s,a]);
 const expected=await capture(src);
 const t=performance.now();await invoke("pg_dump",["--format=custom","--no-owner","--no-privileges","--file",backup,"--dbname",source]);
 const dumpMs=Math.round(performance.now()-t);
 const digest=createHash("sha256").update(await readFile(backup)).digest("hex"),size=(await stat(backup)).size;
 const encrypted=join(dir,"synthetic.rvbak"),decrypted=join(dir,"authenticated.dump"),key=randomBytes(32);
 await encryptArchive(createReadStream(backup),encrypted,key);
 await verifyArchive(encrypted,key,createWriteStream(decrypted,{flags:"wx",mode:0o600}));
 assert.equal(createHash("sha256").update(await readFile(decrypted)).digest("hex"),digest);
 await assert.rejects(verifyArchive(encrypted,randomBytes(32)));
 // Exercise the actual operator runner, not just the encryption helper.
 // Only the disposable source DB URL and random test key are passed to it.
 const scheduledDir=join(dir,"scheduled"),runner=fileURLToPath(new URL("./encrypted-backup-once.mjs",import.meta.url));
 const scheduledEnv={...drillEnv,DATABASE_URL:dbUrl(source),NODE_ENV:"development",REVERIE_BACKUP_DIR:scheduledDir,REVERIE_BACKUP_KEY_HEX:key.toString("hex"),REVERIE_PG_BIN:tools};
 const scheduled=async()=>JSON.parse((await run(process.execPath,[runner,"--execute","--scheduled"],{env:scheduledEnv,timeout:30000,windowsHide:true})).stdout.trim());
 const first=await scheduled();assert.equal(first.status,"encrypted_archive_verified");
 assert.equal((await scheduled()).status,"not_due");
 const replicaDir=join(dir,"replica");
 await (await import("node:fs/promises")).mkdir(replicaDir);
 const verifier=fileURLToPath(new URL("./backup-verify-once.mjs",import.meta.url));
 const verified=JSON.parse((await run(process.execPath,[verifier,"--execute","--copy"],{env:{...scheduledEnv,REVERIE_BACKUP_REPLICA_DIR:replicaDir},timeout:30000,windowsHide:true})).stdout.trim());
 assert.equal(verified.primary,"verified");assert.equal(verified.replica,"verified");
 // Simulate complete loss of the primary archive, not merely a second copy.
 // The path belongs exclusively to this synthetic temporary drill.
 await rm(join(scheduledDir,first.name));
 const lostPrimary=JSON.parse((await run(process.execPath,[verifier,"--execute"],{env:{...scheduledEnv,REVERIE_BACKUP_REPLICA_DIR:replicaDir},timeout:30000,windowsHide:true}).catch(error=>{if(error.code!==1)throw error;return error;})).stdout.trim());
 assert.equal(lostPrimary.primary,"missing");assert.equal(lostPrimary.replica,"authenticated_uncompared");
 // Simulate an unusable newer generation in both storage directories.
 const later=Date.now()+3600000;
 const laterStamp=new Date(later).toISOString().replace(/[-:]/g,"").replace(/\.[0-9]+/,"");
 const damagedName="reverie-"+laterStamp+"-"+randomBytes(6).toString("hex")+".rvbak";
 await writeFile(join(scheduledDir,damagedName),"damaged synthetic primary");
 await writeFile(join(replicaDir,damagedName),"damaged synthetic replica");
 const recovery=await planRecovery({dir:scheduledDir,replicaDir,key,now:later+1000});
 assert.equal(recovery.status,"older_authenticated");
 assert.equal(recovery.candidate.name,first.name);
 assert.equal(recovery.candidate.source,"replica");
 const scheduledDump=join(dir,"scheduled-authenticated.dump");
 await verifyArchive(join(replicaDir,recovery.candidate.name),key,createWriteStream(scheduledDump,{flags:"wx",mode:0o600}));
 const t2=performance.now();await restore(scheduledDump,target);const restoreMs=Math.round(performance.now()-t2);
 dst=new pg.Client({connectionString:dbUrl(target)});await dst.connect();
 assert.deepEqual(await capture(dst),expected);
 await assert.rejects(dst.query("INSERT INTO game_server_player_state(server_id,player_id,x,y) VALUES($1,$2,0,0)",[s,randomUUID()]),e=>e.code==="23503");
 await assert.rejects(dst.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',1,1501,'coop_monster_defeat','monster','qa','restore-fixture')",[p]),e=>e.code==="23505");
 console.log("PASS actual scheduled encrypted dump, repeat invocation skipped, verified older replica restore after primary archive loss and newer archive corruption");
 console.log("RESTORE_DRILL_PASS "+JSON.stringify({bytes:size,dumpMs,restoreMs,sha256:digest,verified:["accounts","players","wallet","currency ledger","server registry","positions","events","checkpoints","incident acknowledgments"],foreignKey:true,idempotency:true}));
}finally{
 await src?.end().catch(()=>{});await dst?.end().catch(()=>{});
 await admin?.end().catch(()=>{});
 if(clusterStarted)await invoke("pg_ctl",["-D",dataDir,"-m","fast","-w","stop"],drillEnv);
 await rm(dir,{recursive:true,force:true});
 console.log("PASS disposable databases and synthetic archives removed");
}
