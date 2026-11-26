import type {PoolClient} from "pg";
import {mythicRecipe,ascensionRecipe} from "./summon.js";

// Same duplicate, Mythic fusion and ascension rules as a normal acquisition.
// Called only inside a locked, idempotent administrator decision transaction.
export async function grantPaidCompensation(db:PoolClient,player:string,character:string,reference:string){
 const acquisitions:Array<{characterId:string;isNew:boolean;awakeningGain:number}>=[];
 async function acquire(id:string){
  const inserted=await db.query("INSERT INTO owned_characters(player_id,char_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING id",[player,id]);
  let gain=0;
  if(!inserted.rowCount){
   const row=(await db.query("SELECT dupes,awakening FROM owned_characters WHERE player_id=$1 AND char_id=$2 FOR UPDATE",[player,id])).rows[0];
   gain=row.dupes+1>=2&&row.awakening<5?1:0;
   await db.query("UPDATE owned_characters SET dupes=dupes+1-$3*2,awakening=awakening+$3 WHERE player_id=$1 AND char_id=$2",[player,id,gain]);
  }
  acquisitions.push({characterId:id,isNew:!!inserted.rowCount,awakeningGain:gain});
 }
 let serial=0;
 async function progress(item:string,name:string,rarity:string,delta:number,cap?:number){
  await db.query("INSERT INTO items(id,display_name,category,rarity) VALUES($1,$2,'material',$3) ON CONFLICT DO NOTHING",[item,name,rarity]);
  const row=delta>0?await db.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=inventory_items.quantity+EXCLUDED.quantity WHERE ($4::bigint IS NULL OR inventory_items.quantity<$4) RETURNING quantity::text",[player,item,delta,cap??null]):await db.query("UPDATE inventory_items SET quantity=quantity+$3 WHERE player_id=$1 AND item_id=$2 AND quantity>=-($3::bigint) RETURNING quantity::text",[player,item,delta]);
  if(!row.rowCount){if(cap!==undefined&&delta>0)return cap;throw new Error("compensation_progress_failed");}
  await db.query("INSERT INTO item_ledger(player_id,item_id,delta,quantity_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'paid_guarantee_compensation','gacha_pull',$5,$6)",[player,item,delta,row.rows[0].quantity,reference.split(":")[0],"compensation:"+reference+":"+(serial++)]);
  return Number(row.rows[0].quantity);
 }
 await acquire(character);
 const recipe=mythicRecipe(character);
 if(recipe){
  let n=await progress(recipe.item,character+" Mythic Progress","legendary",1);
  while(n>=recipe.cost){
   n=await progress(recipe.item,character+" Mythic Progress","legendary",-recipe.cost);
   await acquire(recipe.target);
  }
 }
 for(const a of acquisitions){
  const recipe=ascensionRecipe(a.characterId);if(!recipe)continue;
  const n=await progress(recipe.item,a.characterId+" Ascension Progress","mythic",1,recipe.cost);
  if(n===recipe.cost)await db.query("UPDATE owned_characters SET ascension=3 WHERE player_id=$1 AND char_id=$2",[player,a.characterId]);
 }
 return {acquisitions};
}
