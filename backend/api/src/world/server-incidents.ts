import type {Pool} from "pg";
type Transition={id:string;server_id:string;kind:string;current_reason:string;resolution?:string};
export async function scanServerIncidents(pool:Pool,serverIds:string[]|null=null){
 const db=await pool.connect();
 try{
  await db.query("BEGIN");
  const lock=await db.query("SELECT pg_try_advisory_xact_lock(hashtextextended('reverie:server-incidents',0)) AS locked");
  if(!lock.rows[0].locked){await db.query("ROLLBACK");return {opened:[] as Transition[],resolved:[] as Transition[]};}
  // One snapshot of observed conditions, shared by both transitions. Scope is
  // used only by disposable integration tests; the scheduler scans all servers.
  const snapshot=await db.query(`WITH states AS (
   SELECT s.id,s.status,s.endpoint_url,s.max_players,
    (SELECT count(*) FROM game_server_players p WHERE p.server_id=s.id) AS reserved,
    CASE WHEN s.status='starting' AND s.started_at>now()-interval '60 seconds' THEN 'starting'
     WHEN s.status IN ('online','starting','draining') AND (s.heartbeat_at IS NULL OR s.heartbeat_at<=now()-interval '60 seconds') THEN 'stale'
     WHEN s.status='online' AND s.endpoint_url IS NULL THEN 'unavailable'
     ELSE s.status END AS health
   FROM game_servers s WHERE ($1::uuid[] IS NULL OR s.id=ANY($1))
  )
  SELECT id,status,CASE WHEN health IN ('stale','unavailable') THEN health
   WHEN status='offline' AND reserved>0 THEN 'offline_reserved' END AS availability,
   CASE WHEN health='online' AND reserved>=max_players THEN 'full'
    WHEN health='online' AND reserved>=max_players*0.8 THEN 'capacity' END AS capacity
  FROM states`,[serverIds]);
  const observed=JSON.stringify(snapshot.rows);
  const resolved=(await db.query<Transition>(`UPDATE regional_server_incidents i SET resolved_at=now(),
    resolution=CASE WHEN s.status IN ('offline','maintenance') THEN 'server_inactive' ELSE 'condition_cleared' END
   FROM jsonb_to_recordset($1::jsonb) AS s(id uuid,status text,availability text,capacity text)
   WHERE i.server_id=s.id AND i.resolved_at IS NULL AND
    (CASE WHEN i.kind='availability' THEN s.availability ELSE s.capacity END) IS NULL
   RETURNING i.id::text,i.server_id,i.kind,i.current_reason,i.resolution`,[observed])).rows;
  await db.query(`UPDATE regional_server_incidents i SET current_reason=c.reason
   FROM jsonb_to_recordset($1::jsonb) AS s(id uuid,status text,availability text,capacity text)
   CROSS JOIN LATERAL (VALUES ('availability',s.availability),('capacity',s.capacity)) c(kind,reason)
   WHERE i.server_id=s.id AND i.kind=c.kind AND i.resolved_at IS NULL AND c.reason IS NOT NULL AND i.current_reason<>c.reason`,[observed]);
  const opened=(await db.query<Transition>(`INSERT INTO regional_server_incidents(server_id,kind,initial_reason,current_reason)
   SELECT s.id,c.kind,c.reason,c.reason FROM jsonb_to_recordset($1::jsonb) AS s(id uuid,status text,availability text,capacity text)
   CROSS JOIN LATERAL (VALUES ('availability',s.availability),('capacity',s.capacity)) c(kind,reason)
   WHERE c.reason IS NOT NULL ON CONFLICT(server_id,kind) WHERE resolved_at IS NULL DO NOTHING
   RETURNING id::text,server_id,kind,current_reason`,[observed])).rows;
  await db.query("COMMIT");return {opened,resolved};
 }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
}
export function startServerIncidentMonitor(run:()=>ReturnType<typeof scanServerIncidents>,onChanges:(result:Awaited<ReturnType<typeof scanServerIncidents>>)=>void,onError:(error:unknown)=>void,intervalMs=15000){
 let stopped=false,active:Promise<void>|undefined;
 const tick=()=>{
  if(stopped||active)return;
  active=Promise.resolve().then(run).then(result=>{if(result.opened.length||result.resolved.length)onChanges(result);}).catch(onError).finally(()=>{active=undefined;});
 };
 const timer=setInterval(tick,intervalMs);timer.unref();tick();
 return async()=>{stopped=true;clearInterval(timer);await active;};
}
