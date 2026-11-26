import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {persistOperationalSample,readOperationalHistory,pruneOperationalHistory} from "../src/world/operational-metrics.ts";
assert.ok(config.NODE_ENV!=="production"&&["127.0.0.1","localhost","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const id="history_qa_"+randomBytes(6).toString("hex"),other=id+"_other";
const sample={at:new Date(Date.now()-1000).toISOString(),requests:100,p95UpperMs:50,serverErrors:2,rateLimited:3,databaseMs:4,databaseStatus:"ok",waiting:0,residentMiB:100};
try{
 await persistOperationalSample(pool,id,sample);
 await persistOperationalSample(pool,id,{...sample,requests:999});
 await persistOperationalSample(pool,other,{...sample,requests:1});
 await persistOperationalSample(pool,id,{...sample,at:new Date(Date.now()-25*3600000).toISOString()});
 assert.deepEqual(await readOperationalHistory(pool,id),[sample]);
 assert.equal((await readOperationalHistory(pool,other))[0].requests,1);
 assert.equal(await pruneOperationalHistory(pool,id),1);
 assert.equal(await pruneOperationalHistory(pool,id),0);
 assert.deepEqual(await readOperationalHistory(pool,id),[sample]);
 console.log("PASS persisted observations, duplicate prevention, time-window filtering, instance isolation and retention");
}finally{await pool.query("DELETE FROM api_operational_history WHERE instance_id=ANY($1)",[[id,other]]);await pool.end();console.log("PASS history fixtures removed");}
