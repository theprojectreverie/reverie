import type {PoolClient} from "pg";
import {sequencePvpEvents} from "./pvp-runtime.js";
// Caller owns the transaction. Lock the match before its queue tickets,
// matching the action/surrender lock order.
export async function expirePlayerMatches(db:PoolClient,playerId:string){
 const due=await db.query<{id:string;next_event_sequence:string}>(
 "SELECT m.id,m.next_event_sequence::text FROM pvp_matches m JOIN pvp_match_players mp ON mp.match_id=m.id WHERE mp.player_id=$1 AND m.status IN ('queued','active') AND m.expires_at<=clock_timestamp() ORDER BY m.id FOR UPDATE OF m",[playerId]);
 for(const row of due.rows){
  const batch=sequencePvpEvents(Number(row.next_event_sequence),[{type:"match_expired",reason:"timeout"}]);
  if(!batch)throw Error("event_sequence_exhausted");
  await db.query("INSERT INTO pvp_events(match_id,sequence,actor_player_id,event) VALUES($1,$2,NULL,$3::jsonb)",[row.id,batch.events[0]!.sequence,JSON.stringify(batch.events[0]!.event)]);
  await db.query("UPDATE pvp_matches SET status='expired',next_event_sequence=$2,completed_at=clock_timestamp(),expires_at=NULL,result=$3::jsonb WHERE id=$1",[row.id,batch.nextSequence,JSON.stringify({reason:"timeout",winnerId:null})]);
  await db.query("UPDATE pvp_queue_tickets SET status='expired' WHERE match_id=$1 AND status='matched'",[row.id]);
 }
 return due.rows.length;
}