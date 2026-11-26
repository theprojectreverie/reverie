import type {PoolClient} from "pg";
import {readFileSync} from "node:fs";
import {readVerifiedOpeningProgress} from "./story-progression-proof.js";
import {openingContains} from "./story-opening-geometry.js";
import {grantPartyXp} from "./character-xp.js";
const questId="elathra_first_audience";
const definition=JSON.parse(readFileSync(new URL("../../../../resources/data/quests.json",import.meta.url),"utf8"))[questId];
export const ELATHRA_POSITION={x:2179,y:1400,radius:164}; // 140 interaction + 24 authored patrol
export type AudienceStep="not_started"|"active"|"complete";
export function audienceTransition(state:AudienceStep,operation:"hear"|"accept"):{ok:true;state:AudienceStep;replayed:boolean}|{ok:false;reason:string}{
 if(state==="complete"||(state==="active"&&operation==="hear"))return {ok:true,state,replayed:true};
 if(state==="not_started"&&operation==="accept")return {ok:false,reason:"audience_hear_first"};
 return {ok:true,state:operation==="hear"?"active":"complete",replayed:false};
}
export async function readElathraAudience(db:PoolClient,id:string){
 const row=(await db.query<{completed_at:Date|null}>("SELECT completed_at FROM story_elathra_audience WHERE player_id=$1",[id])).rows[0];
 const state:AudienceStep=!row?"not_started":row.completed_at?"complete":"active";
 return {questId,state,step:state==="complete"?2:state==="active"?1:0,royalGateUnlocked:state==="complete"};
}
// Caller holds authenticated player lock. Neither client quest flags nor telemetry count.
export async function advanceElathraAudience(db:PoolClient,id:string,operation:"hear"|"accept"){
 if(!(await readVerifiedOpeningProgress(db,id)).geraldDefeated)return {ok:false as const,reason:"story_progression_required"};
 const current=await readElathraAudience(db,id);
 const next=audienceTransition(current.state,operation);if(!next.ok)return next;
 if(next.replayed)return {ok:true as const,audience:current,replayed:true,rewards:null};
 const p=(await db.query<{x:number;y:number}>(`SELECT p.x,p.y FROM game_server_player_state p JOIN game_servers s ON s.id=p.server_id JOIN game_server_players a ON a.server_id=s.id AND a.player_id=p.player_id WHERE p.player_id=$1 AND s.region_id='story_royal_gardens' AND s.status='online' AND s.heartbeat_at>now()-interval '60 seconds' AND p.updated_at>now()-interval '15 seconds' AND EXISTS(SELECT 1 FROM game_server_player_connections c WHERE c.server_id=s.id AND c.player_id=p.player_id AND c.lease_expires_at>now())`,[id])).rows[0];
 if(!p||!openingContains("story_royal_gardens",p)||Math.hypot(p.x-ELATHRA_POSITION.x,p.y-ELATHRA_POSITION.y)>ELATHRA_POSITION.radius)return {ok:false as const,reason:"audience_position_required"};
 if((await db.query("SELECT 1 FROM story_battle_sessions WHERE player_id=$1 AND status='active' LIMIT 1",[id])).rowCount)return {ok:false as const,reason:"battle_in_progress"};
 if(operation==="hear")await db.query("INSERT INTO story_elathra_audience(player_id) VALUES($1)",[id]);
 else{
  const xp=definition.rewards.xp;if(!Number.isSafeInteger(xp)||xp<=0||definition.rewards.gold!==0||definition.rewards.crystals!==0)throw new Error("invalid_elathra_reward");
  const party=await grantPartyXp(db,id,xp);
  await db.query("UPDATE owned_characters SET bond=bond+5 WHERE player_id=$1 AND char_id=ANY($2::text[])",[id,party.map(p=>p.characterId)]);
  await db.query("UPDATE story_elathra_audience SET completed_at=now() WHERE player_id=$1 AND completed_at IS NULL",[id]);
 }
 return {ok:true as const,audience:await readElathraAudience(db,id),replayed:false,rewards:operation==="accept"?{xp:definition.rewards.xp,bond:5}:null};
}
