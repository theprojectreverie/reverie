import type {PoolClient} from "pg";
import {verifiedStoryVictories,TUTORIAL_GROUP,VILLAGE_GROUP,MIRENE_GROUP} from "./story-progression-proof.js";
import {startStoryBattle,storyTransactionAdmission} from "./story-combat-service.js";

type EncounterRule={region:string;x:number;y:number;radius:number;requires:readonly string[];cooldownSeconds:number};
// Pilot allowlist: authored zone 01 RoseSlime1..6 and Crownling1..3 positions. The 113 radius
// combines the NPC interaction radius (85) and authored roaming radius (28).
// No shared co-op encounter or story boss is enabled by this policy.
const rule=(x:number,y:number):EncounterRule=>({region:"story_royal_gardens",x,y,radius:113,requires:[TUTORIAL_GROUP,VILLAGE_GROUP],cooldownSeconds:15});
const gateRule=(x:number,y:number):EncounterRule=>({...rule(x,y),region:"story_royal_gate",requires:[TUTORIAL_GROUP,VILLAGE_GROUP,MIRENE_GROUP]});
const rules:Readonly<Record<string,EncounterRule>>=Object.freeze({
 rose_slime_garden_1:rule(-1100,2200),rose_slime_garden_2:rule(-800,1850),rose_slime_garden_3:rule(-1450,1500),
 rose_slime_garden_4:rule(700,2250),rose_slime_garden_5:rule(1200,1750),rose_slime_garden_6:rule(950,1000),
 crownling_garden_1:rule(-900,2100),crownling_garden_2:rule(550,2100),crownling_garden_3:rule(1100,1500),
 [MIRENE_GROUP]:{...rule(2179,1080),radius:120,cooldownSeconds:0},
 royal_gate_patrol_1:gateRule(-65,1200),royal_gate_patrol_2:gateRule(75,1840),
});
export const gardenEncounterIds=Object.freeze(Object.keys(rules).filter(id=>rules[id]!.region==="story_royal_gardens"));
export function isGardenEncounter(groupId:string):boolean{return gardenEncounterIds.includes(groupId);}
export const gateEncounterIds=Object.freeze(Object.keys(rules).filter(id=>rules[id]!.region==="story_royal_gate"));
export function isGateEncounter(id:string):boolean{return gateEncounterIds.includes(id);}
type Proof={audienceComplete?:boolean;region:string;x:number;y:number;fresh:boolean;live:boolean;victories:readonly string[];coolingDown:boolean};
type Decision={ok:true}|{ok:false;reason:string};
export function evaluateStoryEncounter(groupId:string,proof:Proof|null):Decision{
 if(!Object.hasOwn(rules,groupId))return {ok:false,reason:"encounter_not_enabled"};
 const r=rules[groupId]!;
 if(!proof||!proof.live||!proof.fresh)return {ok:false,reason:"world_position_unverified"};
 if(proof.region!==r.region)return {ok:false,reason:"wrong_encounter_region"};
 if(!Number.isFinite(proof.x)||!Number.isFinite(proof.y)||Math.hypot(proof.x-r.x,proof.y-r.y)>r.radius)return {ok:false,reason:"encounter_out_of_range"};
 if(!r.requires.every(id=>proof.victories.includes(id)))return {ok:false,reason:"encounter_progression_required"};
 if((r.region==="story_royal_gate"||groupId===MIRENE_GROUP)&&proof.audienceComplete!==true)return {ok:false,reason:"encounter_progression_required"};
 if(proof.coolingDown)return {ok:false,reason:"encounter_respawning"};
 return {ok:true};
}
/** DB-owned evidence only. The caller has already authenticated the account.
 * No coordinates, progression flags, or victory claims are accepted from clients.
 * Restricted to the isolated story region; never accepts a shared co-op position.
 */
export async function verifyStoryEncounter(db:PoolClient,playerId:string,groupId:string):Promise<Decision>{
 if(!Object.hasOwn(rules,groupId))return {ok:false,reason:"encounter_not_enabled"};
 const r=rules[groupId]!;
 if(!(await db.query("SELECT id FROM players WHERE id=$1 FOR UPDATE",[playerId])).rowCount)return {ok:false,reason:"player_not_found"};
 const position=(await db.query<{region:string;x:number;y:number;fresh:boolean;live:boolean}>(`SELECT s.region_id AS region,p.x,p.y,
   p.updated_at>now()-interval '15 seconds' AS fresh,
   (s.status='online' AND s.heartbeat_at>now()-interval '60 seconds' AND EXISTS(
      SELECT 1 FROM game_server_player_connections c WHERE c.server_id=s.id AND c.player_id=p.player_id AND c.lease_expires_at>now()
   )) AS live
   FROM game_server_player_state p JOIN game_servers s ON s.id=p.server_id
   JOIN game_server_players a ON a.server_id=p.server_id AND a.player_id=p.player_id
   WHERE p.player_id=$1`,[playerId])).rows[0];
 if(!position)return evaluateStoryEncounter(groupId,null);
 const victories=await verifiedStoryVictories(db,playerId,r.requires);
 const coolingDown=!!(await db.query("SELECT 1 FROM story_battle_sessions WHERE player_id=$1 AND group_id=$2 AND status='victory' AND settled_at>now()-($3::int * interval '1 second') LIMIT 1",[playerId,groupId,r.cooldownSeconds])).rowCount;
 const audienceComplete=(r.region==="story_royal_gate"||groupId===MIRENE_GROUP)&&!!(await db.query("SELECT 1 FROM story_elathra_audience WHERE player_id=$1 AND completed_at IS NOT NULL",[playerId])).rowCount;
 return evaluateStoryEncounter(groupId,{...position,victories,coolingDown,audienceComplete});
}
// Internal pilot boundary; no public registration. A separate trusted solo-world
// entry chain must also exclude shared-combat reward paths before enabling it.
export const startVerifiedStoryEncounter=(playerId:string,groupId:string)=>storyTransactionAdmission.run(playerId,async db=>{
 const allowed=await verifyStoryEncounter(db,playerId,groupId);
 if(!allowed.ok)return allowed;
 return startStoryBattle(db,playerId,groupId);
});
