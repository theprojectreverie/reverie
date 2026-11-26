import type {PoolClient} from "pg";
import {retiredPlayableIds} from "./summon.js";
export const STARTER_PARTY=["kael","gerald","lilith"];
export const xpToNext=(level:number)=>100+(level-1)*85;
export function gainCharacterXp(level:number,xp:number,ascension:number,amount:number){
 if(!Number.isSafeInteger(level)||level<1||!Number.isSafeInteger(xp)||xp<0||!Number.isInteger(ascension)||ascension<0||ascension>3||!Number.isSafeInteger(amount)||amount<=0)throw new Error("invalid_character_xp");
 const cap=20*(ascension+1),previous=level;
 xp+=amount;
 while(level<cap&&xp>=xpToNext(level)){xp-=xpToNext(level);level++;}
 if(level>=cap)xp=0;
 return {level,xp,levelsGained:level-previous};
}
// Caller must hold the player lock and include this in the verified defeat transaction.
export async function grantPartyXp(db:PoolClient,playerId:string,amount:number){
 await db.query("INSERT INTO owned_characters(player_id,char_id) SELECT $1,unnest($2::text[]) ON CONFLICT DO NOTHING",[playerId,STARTER_PARTY]);
 const selected=await db.query<{id:string;char_id:string;level:number;xp:string;ascension:number}>("SELECT oc.id,oc.char_id,oc.level,oc.xp::text,oc.ascension FROM party_members pm JOIN owned_characters oc ON oc.id=pm.character_id AND oc.player_id=pm.player_id WHERE pm.player_id=$1 AND NOT(oc.char_id=ANY($2::text[])) ORDER BY pm.slot FOR UPDATE OF oc",[playerId,retiredPlayableIds]);
 const party=selected.rowCount?selected:await db.query<{id:string;char_id:string;level:number;xp:string;ascension:number}>("SELECT id,char_id,level,xp::text,ascension FROM owned_characters WHERE player_id=$1 AND char_id=ANY($2::text[]) ORDER BY char_id FOR UPDATE",[playerId,STARTER_PARTY]);
 const updates=[];
 for(const row of party.rows){
  const next=gainCharacterXp(row.level,Number(row.xp),row.ascension,amount);
  await db.query("UPDATE owned_characters SET level=$2,xp=$3 WHERE id=$1",[row.id,next.level,next.xp]);
  updates.push({characterId:row.char_id,...next});
 }
 return updates;
}
