import type {PoolClient} from "pg";
import {verifiedStoryVictories,TUTORIAL_GROUP} from "./story-progression-proof.js";

export const TUTORIAL_SUMMON_CHARACTER = "kael_legendary";
type Receipt = {character_id:string;rarity:"legendary";featured:false;index:0;is_new:boolean};

/** Caller must authenticate and lock the player row in a transaction.
 * One fixed introductory gift, separate from banner pulls and pity. */
export async function claimTutorialSummon(db:PoolClient,playerId:string){
 const player=await db.query("SELECT settings->'tutorial_summon_v1' AS receipt FROM players WHERE id=$1 FOR UPDATE",[playerId]);
 if(!player.rowCount)return {ok:false,reason:"authentication_required"} as const;
 const prior=player.rows[0].receipt as Receipt|null;
 if(prior?.character_id===TUTORIAL_SUMMON_CHARACTER&&prior.rarity==="legendary")return {ok:true,results:[prior],replayed:true} as const;
 if(!(await verifiedStoryVictories(db,playerId,[TUTORIAL_GROUP])).includes(TUTORIAL_GROUP))return {ok:false,reason:"tutorial_victory_required"} as const;
 const grant=await db.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING id",[playerId,TUTORIAL_SUMMON_CHARACTER]);
 const receipt:Receipt={character_id:TUTORIAL_SUMMON_CHARACTER,rarity:"legendary",featured:false,index:0,is_new:grant.rowCount===1};
 await db.query("UPDATE players SET settings=jsonb_set(COALESCE(settings,'{}'::jsonb),'{tutorial_summon_v1}',$2::jsonb,true) WHERE id=$1",[playerId,JSON.stringify(receipt)]);
 return {ok:true,results:[receipt],replayed:false} as const;
}
