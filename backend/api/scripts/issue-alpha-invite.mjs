import {randomBytes,createHash} from "node:crypto";
import {pool} from "../dist/db.js";
import {config} from "../dist/config.js";
import assert from "node:assert/strict";
assert.ok(config.NODE_ENV==="development"&&["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const count=Number(process.argv[2]??1);
if(!Number.isInteger(count)||count<1||count>10)throw Error("Choose 1-10 invitations");
const db=await pool.connect();
try{
 await db.query("BEGIN");
 await db.query("SELECT pg_advisory_xact_lock(568923412)");
 const existing=Number((await db.query("SELECT count(*) FROM reverie_alpha_invites WHERE used_at IS NOT NULL OR expires_at>clock_timestamp()")).rows[0].count);
 if(existing+count>20)throw Error("Initial alpha enrollment limit reached");
 const codes=[];
 for(let i=0;i<count;i++){const code=randomBytes(32).toString("base64url");await db.query("INSERT INTO reverie_alpha_invites(token_hash,expires_at) VALUES($1,now()+interval '7 days')",[createHash("sha256").update(code).digest("hex")]);codes.push(code)}
 await db.query("COMMIT");
 console.log("Single-use invitations valid for seven days. Share each privately with one tester.");
 for(const code of codes)console.log(code);
}catch(e){await db.query("ROLLBACK");throw e}finally{db.release();await pool.end()}