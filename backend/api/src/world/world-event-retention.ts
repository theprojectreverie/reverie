// Keep the existing 30-day policy. Retain at least the latest 1,000
// sequences per server as extra protection for replay and recent retries.
export const WORLD_EVENT_RETENTION_SQL=`WITH doomed AS (
 SELECT e.server_id,e.sequence FROM game_server_world_events e
 JOIN game_servers s ON s.id=e.server_id
 WHERE e.created_at<now()-interval '30 days'
 AND e.sequence<=s.next_event_sequence-1000
 ORDER BY e.created_at,e.server_id,e.sequence
 LIMIT 1000 FOR UPDATE OF e SKIP LOCKED
) DELETE FROM game_server_world_events e USING doomed d
 WHERE e.server_id=d.server_id AND e.sequence=d.sequence`;
// Optional shorter movement retention. Non-movement history keeps 30 days;
// the latest 1,000 sequences remain protected irrespective of event type.
export const WORLD_POSITION_RETENTION_SQL=WORLD_EVENT_RETENTION_SQL.replace(
 "e.created_at<now()-interval '30 days'",
 "e.created_at<now()-make_interval(hours=>$1::int) AND (e.event_type='position' OR e.created_at<now()-interval '30 days')"
);
export function startWorldEventRetention(runBatch:()=>Promise<number>,onRemoved:(count:number)=>void,onError:(error:unknown)=>void,intervalMs=10000){
 let stopped=false;
 let active:Promise<void>|undefined;
 const tick=()=>{
  if(stopped||active)return;
  active=Promise.resolve().then(async()=>{
   let total=0;
   for(let i=0;i<10&&!stopped;i++){
    const rows=await runBatch();total+=rows;
    if(rows<1000)break;
   }
   if(total)onRemoved(total);
  }).catch(onError).finally(()=>{active=undefined;});
 };
 const timer=setInterval(tick,intervalMs);timer.unref();
 tick();
 return async()=>{stopped=true;clearInterval(timer);await active;};
}
