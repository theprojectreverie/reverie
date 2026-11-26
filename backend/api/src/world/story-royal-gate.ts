import type {PoolClient} from "pg";
import {readFileSync} from "node:fs";
import {grantPartyXp} from "./character-xp.js";
import {verifiedStoryVictories,readVerifiedOpeningProgress} from "./story-progression-proof.js";
import {gateEncounterIds} from "./story-encounter-admission.js";
import {readElathraAudience} from "./story-elathra.js";
const questId="royal_gate_patrol";
const content=(name:string)=>JSON.parse(readFileSync(new URL("../../../../resources/data/"+name+".json",import.meta.url),"utf8"));
const def=content("quests")[questId],items=content("items");
export function gatePatrolProgress(wins:readonly string[],claimed:boolean){
 const defeated=gateEncounterIds.filter(id=>wins.includes(id));
 return {questId,state:claimed?"complete": "active",progress:defeated.length,required:gateEncounterIds.length,defeated,willowFieldsUnlocked:claimed&&defeated.length===gateEncounterIds.length};
}
export async function gateQuestEligible(db:PoolClient,id:string){return (await readVerifiedOpeningProgress(db,id)).geraldDefeated&&(await readElathraAudience(db,id)).royalGateUnlocked;}
export async function readGatePatrol(db:PoolClient,id:string){
 const wins=await verifiedStoryVictories(db,id,gateEncounterIds);
 const receipt=(await db.query<{rewards:unknown}>("SELECT rewards FROM story_royal_gate_patrol WHERE player_id=$1",[id])).rows[0];
 return {...gatePatrolProgress(wins,!!receipt),rewards:receipt?.rewards??null};
}
// Called only inside the player's authenticated transaction. Distinct patrol
// groups are required, not two replays of the same monster. No client reward amounts.
export async function settleGatePatrol(db:PoolClient,id:string){
 const progress=await readGatePatrol(db,id);
 if(progress.state==="complete"||progress.progress!==progress.required)return progress;
 if(!await gateQuestEligible(db,id))throw new Error("gate_quest_progression_required");
 const reward=def.rewards as {gold:number;crystals:number;xp:number;items:Record<string,number>};
 if(![reward.gold,reward.crystals,reward.xp,...Object.values(reward.items)].every(n=>Number.isSafeInteger(n)&&n>=0))throw new Error("invalid_patrol_reward");
 const insert=await db.query("INSERT INTO story_royal_gate_patrol(player_id,rewards) VALUES($1,$2::jsonb) ON CONFLICT DO NOTHING RETURNING player_id",[id,JSON.stringify(reward)]);
 if(!insert.rowCount)return readGatePatrol(db,id);
 for(const currency of ["gold","crystals"] as const){const amount=reward[currency];if(!amount)continue;
  const balance=(await db.query<{balance:string}>("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,$2,$3) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[id,currency,amount])).rows[0]!.balance;
  await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'story_quest_complete','story_quest',$5,$6)",[id,currency,amount,balance,questId,"gate-patrol:"+currency]);
 }
 for(const [itemId,amount] of Object.entries(reward.items)){if(!amount)continue;const item=items[itemId];if(!item||item.category!=="material")throw new Error("invalid_patrol_item");
  await db.query("INSERT INTO items(id,display_name,category,rarity) VALUES($1,$2,$3,$4) ON CONFLICT(id) DO NOTHING",[itemId,item.name,item.category,item.rarity]);
  const quantity=(await db.query<{quantity:string}>("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=inventory_items.quantity+EXCLUDED.quantity RETURNING quantity::text",[id,itemId,amount])).rows[0]!.quantity;
  await db.query("INSERT INTO item_ledger(player_id,item_id,delta,quantity_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'story_quest_complete','story_quest',$5,$6)",[id,itemId,amount,quantity,questId,"gate-patrol:"+itemId]);
 }
 const party=await grantPartyXp(db,id,reward.xp);await db.query("UPDATE owned_characters SET bond=bond+5 WHERE player_id=$1 AND char_id=ANY($2::text[])",[id,party.map(p=>p.characterId)]);
 return readGatePatrol(db,id);
}
