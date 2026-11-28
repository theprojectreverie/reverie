import {villageGroups} from "./village-progression.js";
import type {PoolClient} from "pg";

export const TUTORIAL_GROUP="tutorial_fairy_spar";
export const VILLAGE_GROUP="gerald_boss_encounter";
export const FINALE_GROUP="revienna_encounter";
export const MIRENE_GROUP="mirene_encounter";
export function isOneTimeStoryEncounter(groupId:string):boolean{
 return [TUTORIAL_GROUP,VILLAGE_GROUP,MIRENE_GROUP,FINALE_GROUP,...villageGroups].includes(groupId);
}
/** A server-produced terminal view is required. Tutorial has no reward ledger. */
export async function verifiedStoryVictories(db:PoolClient,playerId:string,groups:readonly string[]):Promise<string[]>{
 return (await db.query<{group_id:string}>(`SELECT DISTINCT group_id FROM story_battle_sessions
  WHERE player_id=$1 AND group_id=ANY($2::text[]) AND status='victory' AND finished_at IS NOT NULL
  AND state->'view'->>'status'='victory'
  AND jsonb_typeof(state->'actions')='array'
  AND jsonb_array_length(CASE WHEN jsonb_typeof(state->'actions')='array' THEN state->'actions' ELSE '[]'::jsonb END)>0
  AND (group_id=$3 OR settled_at IS NOT NULL)`,[playerId,groups,TUTORIAL_GROUP])).rows.map(r=>r.group_id);
}
export async function readVerifiedOpeningProgress(db:PoolClient,playerId:string){
 const wins=await verifiedStoryVictories(db,playerId,[TUTORIAL_GROUP,VILLAGE_GROUP]);
 const tutorialComplete=wins.includes(TUTORIAL_GROUP);
 const geraldDefeated=tutorialComplete&&wins.includes(VILLAGE_GROUP);
 return {tutorialComplete,geraldDefeated,next:!tutorialComplete?TUTORIAL_GROUP:!geraldDefeated?VILLAGE_GROUP:"royal_gardens"};
}

/** Separate story namespace; existing co-op regions are never reclassified. */
export function eligibleOpeningRegions(progress:{tutorialComplete:boolean;geraldDefeated:boolean;royalGateUnlocked?:boolean},gardensEnabled:boolean):string[]{
 const regions=["story_training_ground"];
 if(progress.tutorialComplete){regions.push("story_village");if(gardensEnabled&&progress.geraldDefeated){regions.push("story_royal_gardens");if(progress.royalGateUnlocked===true)regions.push("story_royal_gate");}}
 return regions;
}
export function openingRegionAllowed(region:string,progress:{tutorialComplete:boolean;geraldDefeated:boolean;royalGateUnlocked?:boolean},gardensEnabled:boolean):boolean{
 return !["story_training_ground","story_village","story_royal_gardens","story_royal_gate"].includes(region)||eligibleOpeningRegions(progress,gardensEnabled).includes(region);
}
