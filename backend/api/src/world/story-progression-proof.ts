import type {PoolClient} from "pg";

export const TUTORIAL_GROUP="tutorial_fairy_spar";
export const VILLAGE_GROUP="gerald_boss_encounter";
export const FINALE_GROUP="revienna_encounter";
export function isOneTimeStoryEncounter(groupId:string):boolean{
 return [TUTORIAL_GROUP,VILLAGE_GROUP,FINALE_GROUP].includes(groupId);
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
