import {liveDefinitions,liveDefinition,liveCard,liveMythicRecipe,liveAscensionRecipe} from "./live-character-packs.js";
import {randomInt} from "node:crypto";
import {readFileSync} from "node:fs";
import {createHash} from "node:crypto";
export const RARITIES=["common","rare","epic","legendary","mythic"] as const;
export type Rarity=typeof RARITIES[number];
export type Pity={legendary:number;featured:number;epic_streak:number};
export const PAID_MILESTONE=100;
export const PAID_GUARANTEE_POLICY="featured_character_v1";
export const PAID_CURRENCY="paid_moonstones";
export type Roll={paid_guaranteed?:boolean;character_id:string;rarity:Rarity;featured:boolean;index:number;guaranteed?:boolean;is_new?:boolean;awakening_gain?:number;kind?:"mob_reward"|"upgrade_card";items?:Record<string,number>;card_count?:number;mythic_count?:number;ascended_count?:number;fusions?:Array<{id:string;name:string;is_new?:boolean;fully_ascended?:boolean}>};
export type MobReward={name:string;items:Record<string,number>};
export type UpgradeCard={name:string;rarity:"rare"|"epic";portrait_id:string;target:string;cost:number};
export type MythicRecipe={target:string;cost:number;item:string};
export type AscensionRecipe={cost:number;item:string};
export type AscendedBond={id:string;name:string;members:string[];stat:"atk"|"def";multiplier:number};
export type Banner={retired?:boolean;mythic_ascension?:Record<string,AscensionRecipe>;ascended_bonds?:AscendedBond[];mythic_fusion?:Record<string,MythicRecipe>;upgrade_cards?:Record<string,UpgradeCard>;common_rewards?:Record<string,MobReward>;rates:Record<Rarity,number>;paid_rates?:Record<Rarity,number>;pool:Record<Rarity,string[]>;featured:string[];featured_rate:number;hard_pity:number;featured_pity:number;ten_pull_epic_guarantee:boolean;cost:{currency:string;single:number;ten:number}};
const read=(name:string)=>readFileSync(new URL("../../../../resources/data/"+name+".json",import.meta.url),"utf8");
const rawBanners=read("banners"),rawCharacters=read("characters");
export const banners=JSON.parse(rawBanners) as Record<string,Banner>;
const characters=JSON.parse(rawCharacters) as Record<string,{name?:string;rarity:string;gacha_enabled?:boolean}>;
export function summonDisplayName(id:string):string{return (liveDefinition(id)?.name??characters[id]?.name??id).replace(/ \(Mythic Aspect\)$/,"");}
export const retiredCommonIds=Object.keys(characters).filter(id=>characters[id]?.rarity==="common");
export const retiredPlayableIds=Object.keys(characters).filter(id=>["common","rare","epic"].includes(characters[id]!.rarity)&&!["kael","gerald","lilith"].includes(id));
export function collectionCharacterIds(rarity:"legendary"|"mythic"):string[]{
 return [...Object.keys(characters).filter(id=>characters[id]?.rarity===rarity&&!retiredPlayableIds.includes(id)),...Object.entries(liveDefinitions()).filter(([,d])=>d.rarity===rarity).map(([id])=>id)];
}
export function ascensionRecipe(id:string):AscensionRecipe|undefined{
 if(id.startsWith("livechar_"))return liveAscensionRecipe(id);
 for(const banner of Object.values(banners)){const recipe=banner.mythic_ascension?.[id];if(recipe)return recipe;}
 return undefined;
}
export const ascendedBonds=Object.values(banners).find(b=>b.ascended_bonds)?.ascended_bonds??[];
export function mythicRecipe(id:string):MythicRecipe|undefined{
 if(id.startsWith("livechar_"))return liveMythicRecipe(id);
 for(const banner of Object.values(banners)){const recipe=banner.mythic_fusion?.[id];if(recipe)return recipe;}
 return undefined;
}
export function upgradeCard(id:string):UpgradeCard|undefined{
 if(id.startsWith("upgrade_livechar_"))return liveCard(id);
 for(const banner of Object.values(banners)){const card=banner.upgrade_cards?.[id];if(card)return card;}
 return undefined;
}
export function mobReward(id:string):MobReward|undefined{
 for(const banner of Object.values(banners)){
  const reward=banner.common_rewards?.[id];
  if(reward)return reward;
 }
 return undefined;
}
export function describeRoll<T extends {character_id:string;rarity:string}>(roll:T):T & {kind?:"mob_reward"|"upgrade_card";items?:Record<string,number>}{
 const card=upgradeCard(roll.character_id);
 if(card)return {...roll,kind:"upgrade_card",items:{[roll.character_id]:1}};
 const mob=roll.rarity==="common"?mobReward(roll.character_id):undefined;
 return mob?{...roll,kind:"mob_reward",items:{...mob.items}}:roll;
}
export const contentHash=createHash("sha256").update(rawBanners).update(rawCharacters).digest("hex");
export const contentId="summon-"+contentHash.slice(0,32);
export const emptyPity=():Pity=>({legendary:0,featured:0,epic_streak:0});
const secureRandom=()=>randomInt(0,0x100000000)/0x100000000;
export function rollBanner(banner:Banner,pity:Pity,count:1|10,rng:()=>number=secureRandom,paidProgress?:number):{results:Roll[];pity:Pity}{
 const state={...pity};const results:Roll[]=[];
 const rates=paidProgress!==undefined?(banner.paid_rates??banner.rates):banner.rates;
 const definition=(id:string)=>characters[id]??liveDefinition(id);
 const rank=(r:Rarity)=>RARITIES.indexOf(r);
 const pick=(rarity:Rarity,index:number):Roll=>{
  const candidates=banner.pool[rarity]??[];
  if(rarity==="common"){
   if(!candidates.length||candidates.some(id=>!banner.common_rewards?.[id]))throw new Error("invalid_mob_pool");
   const id=candidates[Math.min(candidates.length-1,Math.floor(rng()*candidates.length))]!;
   return describeRoll({character_id:id,rarity,featured:false,index});
  }
  if(rarity==="rare"||rarity==="epic"){
   if(!candidates.length||candidates.some(id=>banner.upgrade_cards?.[id]?.rarity!==rarity))throw new Error("invalid_upgrade_card_pool");
   return describeRoll({character_id:candidates[Math.min(candidates.length-1,Math.floor(rng()*candidates.length))]!,rarity,featured:false,index});
  }
  if(!candidates.length||candidates.some(id=>!definition(id)||definition(id)!.rarity!==rarity||definition(id)!.gacha_enabled===false))throw new Error("invalid_banner_pool:"+rarity);
  const featured=candidates.filter(id=>banner.featured.includes(id));
  const others=candidates.filter(id=>!featured.includes(id));
  const useFeatured=featured.length>0&&(state.featured>=banner.featured_pity||rng()<banner.featured_rate||!others.length);
  const pool=useFeatured?featured:others;
  const id=pool[Math.min(pool.length-1,Math.floor(rng()*pool.length))];
  if(!id)throw new Error("empty_banner_pool");
  return {character_id:id,rarity,featured:useFeatured,index};
 };
 const reset=(r:Roll)=>{if(rank(r.rarity)>=rank("legendary"))state.legendary=0;if(rank(r.rarity)>=rank("epic"))state.epic_streak=0;if(r.featured)state.featured=0;};
 for(let i=0;i<count;i++){
  state.legendary++;state.featured++;state.epic_streak++;
  let rarity:Rarity="common";
  if(state.legendary>=banner.hard_pity)rarity="legendary";
  else{let total=0;const random=rng();for(const r of RARITIES){total+=rates[r]??0;if(random<total){rarity=r;break;}}}
  if(state.featured>=banner.featured_pity&&banner.featured.length>0&&banner.featured.every(id=>banner.pool.mythic.includes(id)))rarity="mythic";
  const milestone=paidProgress!==undefined&&(paidProgress+i+1)%PAID_MILESTONE===0;
  let result:Roll;
  if(milestone){
   const featured=banner.featured.filter(id=>{
    const def=definition(id);
    return def&&def.gacha_enabled!==false&&
      (def.rarity==="legendary"||def.rarity==="mythic")&&
      banner.pool[def.rarity].includes(id);
   });
   if(!featured.length)throw new Error("invalid_paid_featured_pool");
   const id=featured[Math.min(featured.length-1,Math.floor(rng()*featured.length))]!;
   result={character_id:id,rarity:definition(id)!.rarity as Rarity,featured:true,index:i,paid_guaranteed:true};
  }else result=pick(rarity,i);
  reset(result);results.push(result);
 }
 if(count===10&&banner.ten_pull_epic_guarantee&&results.every(r=>rank(r.rarity)<rank("epic"))){
  const floor=RARITIES.slice(2).find(r=>banner.pool[r]?.length);
  if(floor){const result={...pick(floor,9),guaranteed:true};results[9]=result;reset(result);}
 }
 return {results,pity:state};
}
