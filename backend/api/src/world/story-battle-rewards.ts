import {villageProgressionEnabled,villageRecruit,villageGroups,villageStageFor,villageStages,villageParty} from "./village-progression.js";
import {verifiedStoryVictories} from "./story-progression-proof.js";
import {randomInt} from "node:crypto";
import {readFileSync} from "node:fs";
import type {PoolClient} from "pg";
import {gainCharacterXp} from "./character-xp.js";
import {liveDefinition} from "./live-character-packs.js";
import {retiredPlayableIds} from "./summon.js";
import {isOneTimeStoryEncounter} from "./story-progression-proof.js";
import {recordOnlineDailyVictory} from "../routes/daily-quests.js";

type Rewards={gold:number;crystals:number;ancient_coins:number;xp:number;items:Record<string,number>};
type Drop={item:string;chance:number;min:number;max:number};
type Group={level:number;region:string;rewards?:Partial<Rewards>;drops?:Drop[]};
type Item={name:string;category:string;rarity:string};
const content=(name:string)=>JSON.parse(readFileSync(new URL("../../../../resources/data/"+name+".json",import.meta.url),"utf8"));
const groups=content("enemy_groups") as Record<string,Group>;
const items=content("items") as Record<string,Item>;
const characters={...content("main_characters"),...content("characters")};
const rewardKeys=["gold","crystals","ancient_coins"] as const;
export function storyReward(groupId:string,random:()=>number=()=>randomInt(0,1000000000)/1000000000):Rewards{
 const group=groups[groupId];
 if(!group||groupId==="tutorial_fairy_spar")throw new Error("not_rewarded_story_encounter");
 const base=group.rewards??{};
 const scale=1+0.12*Math.max(0,group.level-1);
 const reward:Rewards={gold:Math.round((base.gold??0)*scale),crystals:Math.round((base.crystals??0)*scale),xp:Math.round((base.xp??0)*scale),ancient_coins:base.ancient_coins??0,items:{...base.items}};
 for(const drop of group.drops??[]){
  if(drop.chance>=1||(drop.chance>0&&random()<drop.chance)){
   const min=Math.max(1,drop.min),max=Math.max(min,drop.max);
   reward.items[drop.item]=(reward.items[drop.item]??0)+min+Math.min(max-min,Math.floor(random()*(max-min+1)));
  }
 }
 for(const n of [...rewardKeys.map(k=>reward[k]),reward.xp,...Object.values(reward.items)])if(!Number.isSafeInteger(n)||n<0)throw new Error("invalid_story_reward");
 for(const id of Object.keys(reward.items))if(!items[id]||items[id]!.category!=="material"||!["common","rare","epic","legendary","mythic"].includes(items[id]!.rarity))throw new Error("invalid_story_reward_item");
 return reward;
}
type Session={id:string;player_id:string;group_id:string;party_ids:string[];status:string;rewards:Rewards|null;settled_at:Date|null};
export type Settlement={ok:true;replayed:boolean;rewards:Rewards}|{ok:false;reason:string};
/**
 * Internal settlement only. No HTTP route accepts victory, party or reward
 * amounts from clients. The combat service must persist victory in the same
 * trusted server database. Caller MUST open a transaction and commit or roll
 * back the entire result. Always lock player before battle, as wallet routes do.
 */
export async function settleStoryVictory(db:PoolClient,playerId:string,battleId:string):Promise<Settlement>{
 const player=await db.query("SELECT id FROM players WHERE id=$1 FOR UPDATE",[playerId]);
 if(!player.rowCount)return {ok:false,reason:"player_not_found"};
 const row=(await db.query<Session>("SELECT * FROM story_battle_sessions WHERE id=$1 AND player_id=$2 FOR UPDATE",[battleId,playerId])).rows[0];
 if(!row)return {ok:false,reason:"battle_not_found"};
 if(row.status!=="victory")return {ok:false,reason:"victory_not_verified"};
 if(row.rewards&&row.settled_at)return {ok:true,replayed:true,rewards:row.rewards};
 if(row.group_id==="tutorial_fairy_spar"||!groups[row.group_id])return {ok:false,reason:"not_rewarded_story_encounter"};
 if(isOneTimeStoryEncounter(row.group_id)){
  const prior=await db.query("SELECT 1 FROM story_battle_sessions WHERE player_id=$1 AND group_id=$2 AND settled_at IS NOT NULL",[playerId,row.group_id]);
  if(prior.rowCount)return {ok:false,reason:"already_claimed"};
 }
 if(row.party_ids.length<1||row.party_ids.length>4||new Set(row.party_ids).size!==row.party_ids.length||row.party_ids.some(id=>(!characters[id]&&!liveDefinition(id))||retiredPlayableIds.includes(id)))return {ok:false,reason:"invalid_battle_party"};
 const owned=await db.query<{id:string;char_id:string;level:number;xp:string;ascension:number}>("SELECT id,char_id,level,xp::text,ascension FROM owned_characters WHERE player_id=$1 AND char_id=ANY($2::text[]) FOR UPDATE",[playerId,row.party_ids]);
 if(owned.rows.length!==row.party_ids.length)return {ok:false,reason:"battle_party_not_owned"};
 const reward=storyReward(row.group_id);
 const village=villageProgressionEnabled()&&villageGroups.includes(row.group_id);
 if(village){
  const stage=villageStages[villageStageFor(row.group_id)]!;
  const wins=await verifiedStoryVictories(db,playerId,[...stage.groups]);
  if(stage.groups.every(g=>g===row.group_id||wins.includes(g))){
   const quest=content("quests")[stage.quest]?.rewards;
   reward.xp+=Number(quest?.xp??0);reward.gold+=Number(quest?.gold??0);
  }
 }

 const ref=row.id;
 for(const currency of rewardKeys){
  const amount=reward[currency];
  if(!amount)continue;
  const balance=(await db.query<{balance:string}>("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,$2,$3) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[playerId,currency,amount])).rows[0]!.balance;
  await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'story_battle_defeat','story_battle',$5,$6)",[playerId,currency,amount,balance,ref,"story:"+ref+":"+currency]);
 }
 for(const [id,amount] of Object.entries(reward.items)){
  if(!amount)continue;
  const item=items[id]!;
  await db.query("INSERT INTO items(id,display_name,category,rarity) VALUES($1,$2,$3,$4) ON CONFLICT(id) DO NOTHING",[id,item.name,item.category,item.rarity]);
  const stock=(await db.query<{quantity:string}>("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=inventory_items.quantity+EXCLUDED.quantity RETURNING quantity::text",[playerId,id,amount])).rows[0]!.quantity;
  await db.query("INSERT INTO item_ledger(player_id,item_id,delta,quantity_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'story_battle_defeat','story_battle',$5,$6)",[playerId,id,amount,stock,ref,"story:"+ref+":"+id]);
 }
 // Use the participating party snapshot, not the subsequently selected party.
 for(const member of owned.rows){
  const next=reward.xp?gainCharacterXp(member.level,Number(member.xp),member.ascension,reward.xp):{level:member.level,xp:Number(member.xp)};
  await db.query("UPDATE owned_characters SET level=$2,xp=$3,bond=bond+2 WHERE id=$1",[member.id,next.level,next.xp]);
 }
 if(village){
  const recruit=villageRecruit(row.group_id);
  if(recruit){
   await db.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,$2) ON CONFLICT DO NOTHING",[playerId,recruit]);
   const ids=recruit==="nyx"?villageParty("gerald_boss_encounter"):villageParty("village_crownling_1");
   const members=(await db.query<{id:string;char_id:string}>("SELECT id,char_id FROM owned_characters WHERE player_id=$1 AND char_id=ANY($2::text[])",[playerId,ids])).rows;
   if(members.length!==ids.length)throw new Error("village_recruitment_party_missing");
   await db.query("DELETE FROM party_members WHERE player_id=$1",[playerId]);
   for(let i=0;i<ids.length;i++)await db.query("INSERT INTO party_members(player_id,slot,character_id) VALUES($1,$2,$3)",[playerId,i+1,members.find(m=>m.char_id===ids[i])!.id]);
  }
 }
 await db.query("UPDATE players SET xp=xp+$2 WHERE id=$1",[playerId,Math.floor(reward.xp/2)]);
 await recordOnlineDailyVictory(db,playerId,false,groups[row.group_id]!.region,row.group_id);
 await db.query("UPDATE story_battle_sessions SET rewards=$2,settled_at=now() WHERE id=$1",[ref,JSON.stringify(reward)]);
 return {ok:true,replayed:false,rewards:reward};
}
