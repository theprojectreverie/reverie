import type {PoolClient} from "pg";
// Caller must hold the account row lock. Only restore suspensions owned by this
// feature, never legacy bans or manually changed account versions.
export async function currentSuspension(db:PoolClient,accountId:string,version:number){
 const q=await db.query("SELECT id,reason,suspended_until,suspended_until<=clock_timestamp() AS expired FROM reverie_account_suspensions WHERE account_id=$1 AND suspension_version=$2 AND ended_at IS NULL",[accountId,version]);
 return q.rows[0];
}
export async function expireSuspension(db:PoolClient,accountId:string,version:number,id:string){
 const q=await db.query("UPDATE accounts SET status='active',updated_at=now() WHERE id=$1 AND status='suspended' AND token_version=$2 RETURNING id",[accountId,version]);
 if(!q.rowCount)return false;
 await db.query("UPDATE reverie_account_suspensions SET ended_at=now(),end_reason='Expired automatically' WHERE id=$1 AND ended_at IS NULL",[id]);
 return true;
}