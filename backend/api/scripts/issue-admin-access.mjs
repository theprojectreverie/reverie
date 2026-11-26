import {randomBytes,createHash} from "node:crypto";
import {mkdirSync,readFileSync,writeFileSync,renameSync,existsSync} from "node:fs";
import {join} from "node:path";
import {pool} from "../dist/db.js";
import {config} from "../dist/config.js";
import assert from "node:assert/strict";
assert.ok(config.NODE_ENV==="development"&&["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const name=process.argv[2]?.trim();if(!name)throw Error("Provide exact assigned staff player name");
const allowed=[...config.STAFF_OWNER_ACCOUNT_IDS.split(","),...config.DEVELOPER_ACCOUNT_IDS.split(",")].map(x=>x.trim()).filter(x=>/^[0-9a-f-]{36}$/i.test(x));
try{
 const q=await pool.query("SELECT a.id,p.name FROM accounts a JOIN players p ON p.account_id=a.id WHERE lower(p.name)=lower($1) AND a.status='active' AND (a.id=ANY($2::uuid[]) OR EXISTS(SELECT 1 FROM reverie_staff_roles r WHERE r.account_id=a.id))",[name,allowed]);
 if(q.rowCount!==1)throw Error("Exact active staff account not found");
 const p=q.rows[0],dir=join(process.env.LOCALAPPDATA,"Reverie","AdminGateway");mkdirSync(dir,{recursive:true});
 const file=join(dir,"access.json"),data=existsSync(file)?JSON.parse(readFileSync(file,"utf8")):{entries:[]};
 const code=randomBytes(32).toString("base64url");
 data.entries=data.entries.filter(e=>e.accountId!==p.id);
 data.entries.push({accountId:p.id,name:p.name,hash:createHash("sha256").update(code).digest("hex")});
 writeFileSync(file+".tmp",JSON.stringify(data),{mode:0o600});renameSync(file+".tmp",file);
 const out=join(dir,"access-"+p.id+".txt");writeFileSync(out,"Reverie staff access\nAccount: "+p.name+"\nURL: https://reverie.tailad29fa.ts.net:10000/developer\nAccess code: "+code+"\nKeep private; delete this file after storing securely.\n",{mode:0o600});
 console.log("Access credential created/rotated. Previous gate sessions revoked. Private credential file: "+out);
}finally{await pool.end()}