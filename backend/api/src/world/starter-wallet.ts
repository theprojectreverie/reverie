import type {PoolClient} from "pg";
export const STARTER_WALLET=[["gold",500],["crystals",1500]] as const;
type WalletRow={currency_id:string;balance:string};
type LedgerRow={currency_id:string;idempotency_key:string|null;reason:string};
export function starterWalletStatus(wallet:WalletRow[],ledger:LedgerRow[]){
 const grants=STARTER_WALLET.filter(([id])=>ledger.some(r=>r.currency_id===id&&r.idempotency_key==="starter-grant:"+id&&r.reason==="starter_grant"));
 if(grants.length===2)return "already_granted";
 if(grants.length||ledger.length||wallet.length!==2||STARTER_WALLET.some(([id])=>!wallet.some(r=>r.currency_id===id&&r.balance==="0")))return "review";
 return "eligible";
}
/** Within caller transaction. Lock player first, then wallet in consistent order.
 * Never infer missing entitlement from a spent balance alone. */
export async function grantStarterWallet(db:PoolClient,playerId:string){
 const lock=await db.query("SELECT id FROM players WHERE id=$1 FOR UPDATE",[playerId]);
 if(!lock.rowCount)throw new Error("starter_player_missing");
 const wallet=(await db.query<WalletRow>("SELECT currency_id,balance::text FROM player_currencies WHERE player_id=$1 AND currency_id=ANY($2::text[]) ORDER BY currency_id FOR UPDATE",[playerId,STARTER_WALLET.map(([id])=>id)])).rows;
 const ledger=(await db.query<LedgerRow>("SELECT currency_id,idempotency_key,reason FROM currency_ledger WHERE player_id=$1 AND currency_id=ANY($2::text[])",[playerId,STARTER_WALLET.map(([id])=>id)])).rows;
 const status=starterWalletStatus(wallet,ledger);
 if(status!=="eligible")return status;
 for(const [currency,amount] of STARTER_WALLET){
  const updated=await db.query("UPDATE player_currencies SET balance=balance+$3 WHERE player_id=$1 AND currency_id=$2 RETURNING balance",[playerId,currency,amount]);
  if(updated.rowCount!==1)throw new Error("starter_currency_missing");
  await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'starter_grant','registration',$5,$6)",[playerId,currency,amount,updated.rows[0].balance,playerId,"starter-grant:"+currency]);
 }
 return "granted";
}