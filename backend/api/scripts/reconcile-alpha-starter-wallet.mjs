import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {grantStarterWallet,starterWalletStatus,STARTER_WALLET} from "../src/world/starter-wallet.ts";
import assert from "node:assert/strict";
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname)&&config.NODE_ENV!=="production","local alpha database only");
const apply=process.argv.includes("--apply");
const counts={eligible:0,already_granted:0,review:0,granted:0};
const ids=STARTER_WALLET.map(([id])=>id);
try{
 const candidates=(await pool.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE a.status='active' AND EXISTS(SELECT 1 FROM reverie_alpha_invites i WHERE i.used_by=a.id AND i.used_at IS NOT NULL) ORDER BY p.id")).rows;
 for(const {id} of candidates){
  const db=await pool.connect();
  try{
   await db.query("BEGIN");
   if(apply){
    const active=await db.query("SELECT a.id FROM accounts a JOIN players p ON p.account_id=a.id WHERE p.id=$1 AND a.status='active' AND EXISTS(SELECT 1 FROM reverie_alpha_invites i WHERE i.used_by=a.id AND i.used_at IS NOT NULL) FOR UPDATE OF a",[id]);
    if(!active.rowCount){counts.review++;await db.query("ROLLBACK");continue;}
    const status=await grantStarterWallet(db,id);counts[status]++;await db.query("COMMIT");
   }
   else{
    await db.query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY");
    const wallet=(await db.query("SELECT currency_id,balance::text FROM player_currencies WHERE player_id=$1 AND currency_id=ANY($2::text[])",[id,ids])).rows;
    const ledger=(await db.query("SELECT currency_id,idempotency_key,reason FROM currency_ledger WHERE player_id=$1 AND currency_id=ANY($2::text[])",[id,ids])).rows;
    counts[starterWalletStatus(wallet,ledger)]++;
    await db.query("ROLLBACK");
   }
  }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 }
 console.log(JSON.stringify({mode:apply?"apply":"dry-run",activeEnrolled:candidates.length,...counts}));
}finally{await pool.end();}