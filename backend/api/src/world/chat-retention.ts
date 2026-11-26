export const RECENT_CHAT_CLEANUP_SQL="WITH doomed AS (SELECT id FROM recent_chat_messages WHERE created_at<now()-interval '30 minutes' ORDER BY created_at LIMIT 1000 FOR UPDATE SKIP LOCKED) DELETE FROM recent_chat_messages m USING doomed d WHERE m.id=d.id";
export function createChatRetention(runBatch:()=>Promise<number>,onError:(error:unknown)=>void){
 let running:Promise<void>|undefined;
 let closed=false;
 const tick=():Promise<void>=>{
  if(closed)return Promise.resolve();
  if(running)return running;
  running=(async()=>{
   try{
    // Bound each cycle to 10,000 deletions and yield between database batches.
    for(let i=0;i<10&&!closed;i++){
     if(await runBatch()<1000)break;
    }
   }catch(e){onError(e);}
  })().finally(()=>{running=undefined;});
  return running;
 };
 return {tick,close:async()=>{closed=true;await running;}};
}