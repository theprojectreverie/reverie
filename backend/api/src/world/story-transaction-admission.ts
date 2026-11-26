import type {Pool,PoolClient} from "pg";

type Rejected={ok:false;reason:"story_request_busy"|"story_player_busy"};
type Outcome={ok:boolean};
/** Internal boundary for authenticated story requests. Admit BEFORE pool.connect().
 * The underlying service still takes DB locks for cross-process correctness.
 * Each API process reserves at least four of its twelve pool slots for other work.
 */
export class StoryTransactionAdmission {
 private readonly active=new Set<string>();
 constructor(private readonly database:Pick<Pool,"connect">,private readonly maxActive=8){
  if(!Number.isSafeInteger(maxActive)||maxActive<1)throw new Error("invalid_story_admission_limit");
 }
 async run<T extends Outcome>(playerId:string,operation:(db:PoolClient)=>Promise<T>):Promise<T|Rejected>{
  if(this.active.has(playerId))return {ok:false,reason:"story_player_busy"};
  if(this.active.size>=this.maxActive)return {ok:false,reason:"story_request_busy"};
  this.active.add(playerId);
  let db:PoolClient|undefined;
  let broken:Error|undefined;
  try{
   db=await this.database.connect();
   await db.query("BEGIN");
   const result=await operation(db);
   await db.query(result.ok?"COMMIT":"ROLLBACK");
   return result;
  }catch(error){
   if(db){try{await db.query("ROLLBACK");}catch(rollbackError){broken=rollbackError instanceof Error?rollbackError:new Error("story_rollback_failed");}}
   throw error;
  }finally{
   try{db?.release(broken);}finally{this.active.delete(playerId);}
  }
 }
}
