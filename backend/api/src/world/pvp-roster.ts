import {ascendedBonds} from "./summon.js";
import type {PvpSkill,PvpState,PvpUnit} from "./pvp.js";

type JsonRecord=Record<string,unknown>;
export type OwnedPvpCharacter={
 id:string;char_id:string;level:number;ascension:number;awakening:number;bond:number;dupes?:number;skill_levels?:Record<string,number>;
 equipment?:Array<{slot:string;item_id:string;enhancement_level?:number;reroll_stat?:string|null;reroll_value?:number}>;
};
export type PvpRosterContent={characters:Record<string,JsonRecord>;skills:Record<string,JsonRecord>;items:Record<string,JsonRecord>};
export type PvpRosterResult={ok:true;units:PvpUnit[];skillbook:Record<string,PvpSkill>}|{ok:false;reason:string};

const SLOTS=["weapon","armor","accessory"] as const;
const SET_BONUSES:Record<string,Record<number,Record<string,number>>>={
 greenward_wayfarer:{2:{hp:40,def:4},3:{spd:5,crit:0.02}}
};
const record=(v:unknown):v is JsonRecord=>typeof v==="object"&&v!==null&&!Array.isArray(v);
const finite=(v:unknown,fallback=0):number=>typeof v==="number"&&Number.isFinite(v)?v:fallback;

function effectiveStat(def:JsonRecord,stat:string,level:number,ascension:number):number{
 const base=record(def.base)?finite(def.base[stat]):0;
 const growth=record(def.growth)?finite(def.growth[stat]):0;
 if(["hp","atk","def"].includes(stat))return (base+growth*(level-1))*(1+0.10*ascension);
 if(stat==="spd")return (base+growth*(level-1))*(1+0.02*(level-1));
 if(stat==="crit"||stat==="crit_dmg")return base+growth*(level-1)+0.005*ascension;
 return base+growth*(level-1);
}

function skillFromContent(id:string,raw:JsonRecord):PvpSkill|null{
 const kinds=["damage","heal","shield","buff","debuff"];
 const targets=["single_enemy","all_enemies","single_ally","all_allies","self"];
 if(!kinds.includes(String(raw.kind))||!targets.includes(String(raw.target)))return null;
 const elements=["fire","wind","earth","water","light","dark","neutral"];
 if(typeof raw.power!=="number"||!Number.isFinite(raw.power)||raw.power<0||raw.power>1000||
  (raw.element!==undefined&&(typeof raw.element!=="string"||!elements.includes(raw.element)))||
  (raw.scaling_stat!==undefined&&(typeof raw.scaling_stat!=="string"||!["atk","def","hp","spd"].includes(raw.scaling_stat)))||
  (raw.crit_bonus!==undefined&&(typeof raw.crit_bonus!=="number"||!Number.isFinite(raw.crit_bonus)||raw.crit_bonus<0||raw.crit_bonus>1))||
  (raw.energy_gain!==undefined&&(!Number.isInteger(raw.energy_gain)||Number(raw.energy_gain)<0||Number(raw.energy_gain)>100))||
  (raw.cooldown_turns!==undefined&&(!Number.isInteger(raw.cooldown_turns)||Number(raw.cooldown_turns)<0||Number(raw.cooldown_turns)>20))||
  (raw.lifesteal!==undefined&&(typeof raw.lifesteal!=="number"||!Number.isFinite(raw.lifesteal)||raw.lifesteal<0||raw.lifesteal>1))||
  (raw.ultimate!==undefined&&typeof raw.ultimate!=="boolean")||
  (raw.cleanse!==undefined&&typeof raw.cleanse!=="boolean"))return null;
 const allyTarget=raw.target==="single_ally"||raw.target==="all_allies"||raw.target==="self";
 if((raw.kind==="heal"||raw.kind==="shield"||raw.kind==="buff")&&!allyTarget)return null;
 if((raw.kind==="damage"||raw.kind==="debuff")&&allyTarget)return null;
 if(raw.target==="self"&&!["heal","shield","buff"].includes(String(raw.kind)))return null;
 if((raw.kind==="buff"||raw.kind==="debuff")&&(!Array.isArray(raw.statuses)||raw.statuses.length===0))return null;
 if(raw.statuses!==undefined&&!Array.isArray(raw.statuses))return null;
 const rawStatuses=(raw.statuses??[]) as unknown[];
 if(rawStatuses.length>16||rawStatuses.some(s=>!record(s)||typeof s.id!=="string"||!s.id.length||
  (s.chance!==undefined&&(typeof s.chance!=="number"||!Number.isFinite(s.chance)||s.chance<0||s.chance>1))||
  (s.turns!==undefined&&(!Number.isInteger(s.turns)||Number(s.turns)<1||Number(s.turns)>20))||
  (s.potency!==undefined&&(typeof s.potency!=="number"||!Number.isFinite(s.potency)||s.potency<0||s.potency>1))))return null;
 const statuses=rawStatuses.map(s=>{const item=s as JsonRecord;return {
  id:String(item.id),...(item.chance!==undefined?{chance:finite(item.chance)}:{}),
  ...(item.turns!==undefined?{turns:finite(item.turns)}:{}),...(item.potency!==undefined?{potency:finite(item.potency)}:{})
 };});
 return {
  id,kind:raw.kind as PvpSkill["kind"],power:finite(raw.power),target:raw.target as PvpSkill["target"],
  ...(typeof raw.element==="string"?{element:raw.element}:{}),
  ...(typeof raw.scaling_stat==="string"&&["atk","def","hp","spd"].includes(raw.scaling_stat)?{scalingStat:raw.scaling_stat as PvpSkill["scalingStat"]}:{}),
  ...(raw.crit_bonus!==undefined?{critBonus:finite(raw.crit_bonus)}:{}),
  ...(raw.energy_gain!==undefined?{energyGain:finite(raw.energy_gain)}:{}),
  ...(raw.cooldown_turns!==undefined?{cooldownTurns:finite(raw.cooldown_turns)}:{}),
  ...(raw.lifesteal!==undefined?{lifesteal:finite(raw.lifesteal)}:{}),
  ...(raw.ultimate===true?{ultimate:true}:{}),
  ...(raw.cleanse===true?{cleanse:true}:{}),
  ...(statuses?{statuses}:{})
 };
}

export function buildPvpRoster(ownerId:string,team:1|2,owned:OwnedPvpCharacter[],content:PvpRosterContent,uniqueOwnedCharacterCount?:number):PvpRosterResult{
 if(typeof ownerId!=="string"||!ownerId.trim()||(team!==1&&team!==2)||!Array.isArray(owned)||owned.length<1||owned.length>4)return {ok:false,reason:"party_size_invalid"};
 const seen=new Set<string>();
 const uniqueOwned=new Set<string>();
 if(owned.some(c=>!record(c)||typeof c.id!=="string"||!c.id.trim()||typeof c.char_id!=="string"||!c.char_id.trim()||
  !Number.isInteger(c.level)||c.level<1||!Number.isInteger(c.ascension)||c.ascension<0||c.ascension>3||
  !Number.isInteger(c.awakening)||c.awakening<0||c.awakening>5||!Number.isInteger(c.bond)||c.bond<0||
  (c.equipment!==undefined&&!Array.isArray(c.equipment))))return {ok:false,reason:"owned_character_invalid"};
 for(const c of owned)uniqueOwned.add(c.char_id);
 if(uniqueOwned.size!==owned.length)return {ok:false,reason:"owned_character_invalid"};
 const collectionCount=uniqueOwnedCharacterCount??uniqueOwned.size;
 if(!Number.isSafeInteger(collectionCount)||collectionCount<uniqueOwned.size||collectionCount<1)return {ok:false,reason:"owned_character_count_invalid"};
 const collectionBonus=1+Math.min(0.15,0.01*Math.floor(collectionCount/3));
 const units:PvpUnit[]=[];
 const skillbook:Record<string,PvpSkill>={};
 for(const instance of owned){
  if(!instance.id||!instance.char_id||seen.has(instance.id))return {ok:false,reason:"owned_character_invalid"};
  seen.add(instance.id);
  const definition=content.characters[instance.char_id];
  if(!record(definition)||!record(definition.base)||(definition.growth!==undefined&&!record(definition.growth)))return {ok:false,reason:"character_content_missing"};
  if(["common","rare","epic"].includes(String(definition.rarity))&&!["kael","gerald","lilith"].includes(instance.char_id))return {ok:false,reason:"character_not_playable"};
  const level=Math.max(1,Math.min(20*(Math.max(0,Math.min(3,Math.trunc(instance.ascension)))+1),Math.trunc(instance.level)));
  const ascension=Math.max(0,Math.min(3,Math.trunc(instance.ascension)));
  const awakening=Math.max(0,Math.min(5,Math.trunc(instance.awakening)));
  const bond=Math.max(0,Math.trunc(instance.bond));
  const rank=definition.rarity==="mythic"?Math.min(6,2*awakening+Math.max(0,Math.trunc(instance.dupes??0))):awakening;
  const power=(1+0.085*(level-1))*(1+0.10*ascension)*(1+0.04*rank);
  const stats:Record<string,number>={
   hp:effectiveStat(definition,"hp",level,ascension)*power*collectionBonus,
   atk:effectiveStat(definition,"atk",level,ascension)*power*collectionBonus*(1+Math.floor(bond/10)*0.02),
   def:effectiveStat(definition,"def",level,ascension)*power*collectionBonus,
   spd:effectiveStat(definition,"spd",level,ascension)*(1+0.02*(level-1)),
   crit:effectiveStat(definition,"crit",level,ascension),
   crit_dmg:effectiveStat(definition,"crit_dmg",level,ascension)
  };
  const equipment=Array.isArray(instance.equipment)?instance.equipment:[];
  if(equipment.length>3||equipment.some(e=>!record(e)||!SLOTS.includes(e.slot as typeof SLOTS[number])||typeof e.item_id!=="string"||!e.item_id.trim()||!Number.isInteger(e.enhancement_level??0)||Number(e.enhancement_level??0)<0||Number(e.enhancement_level??0)>8||(e.reroll_stat!==undefined&&e.reroll_stat!==null&&![ "hp","atk","def","spd","crit","crit_dmg" ].includes(String(e.reroll_stat)))||(e.reroll_value!==undefined&&(!Number.isFinite(Number(e.reroll_value))||Number(e.reroll_value)<0||Number(e.reroll_value)>10000))||(e.reroll_stat!=null&&e.reroll_value===undefined))||
   new Set(equipment.map(e=>e.slot)).size!==equipment.length)return {ok:false,reason:"equipment_content_invalid"};
  const equipped=new Map(equipment.map(e=>[e.slot,e.item_id]));
  const sets:Record<string,number>={};
  let equipmentElement="";
  for(const slot of SLOTS){
   const itemId=equipped.get(slot);
   if(!itemId)continue;
   const item=content.items[itemId];
   if(!record(item)||item.category!=="equipment"||item.slot!==slot)return {ok:false,reason:"equipment_content_invalid"};
   if(typeof item.set_id==="string"&&item.set_id)sets[item.set_id]=(sets[item.set_id]??0)+1;
   if(!equipmentElement&&typeof item.element==="string"&&item.element!=="neutral")equipmentElement=item.element;
   const itemStats=record(item.stats)?item.stats:{};
   const equippedEntry=equipment.find(e=>e.slot===slot);
   const cap=({common:3,uncommon:4,rare:5,epic:6,legendary:7,mythic:8} as Record<string,number>)[String(item.rarity??"common")]??5;
   if((equippedEntry?.enhancement_level??0)>cap)return {ok:false,reason:"equipment_content_invalid"};
   const enhancement=1+0.08*(equippedEntry?.enhancement_level??0);
   for(const key of ["hp","atk","def","spd","crit","crit_dmg"])stats[key]=finite(stats[key])+finite(itemStats[key])*enhancement;
   if(equippedEntry?.reroll_stat)stats[equippedEntry.reroll_stat]=finite(stats[equippedEntry.reroll_stat])+finite(equippedEntry.reroll_value);
  }
  for(const [setId,count] of Object.entries(sets)){
   for(const [thresholdText,bonus] of Object.entries(SET_BONUSES[setId]??{})){
    if(count<Number(thresholdText))continue;
    for(const [key,value] of Object.entries(bonus))stats[key]=finite(stats[key])+value;
   }
  }
  const charSkills=Array.isArray(definition.skills)?definition.skills:[];
  if(charSkills.length<1||charSkills.length>8||charSkills.some(id=>typeof id!=="string"))return {ok:false,reason:"character_skill_list_invalid"};
  const ultimateId=typeof definition.ultimate==="string"?definition.ultimate:"";
  const skillIds=charSkills as string[];
  for(const id of [...skillIds,ultimateId]){
   const raw=content.skills[id];
   if(!id||!record(raw))return {ok:false,reason:"skill_content_missing"};
   const parsed=skillFromContent(id,raw);
   if(!parsed)return {ok:false,reason:"skill_content_invalid"};
   skillbook[id]=parsed;
  }
  const skillLevels=instance.skill_levels??{};
  if(!record(skillLevels)||Object.entries(skillLevels).some(([id,n])=>![...skillIds,ultimateId].includes(id)||!Number.isInteger(n)||Number(n)<1||Number(n)>5))return {ok:false,reason:"skill_levels_invalid"};
  units.push({
   uid:"p_"+instance.id,ownerId,team,charId:instance.char_id,ascension,
   element:equipmentElement||String(definition.element??"neutral"),
   maxHp:stats.hp??0,hp:stats.hp??0,atk:stats.atk??0,defense:stats.def??0,speed:stats.spd??0,
   critChance:Math.max(0,Math.min(1,stats.crit??0)),critDamage:stats.crit_dmg??0,energy:0,shield:0,
   skillIds,ultimateId,skillLevels,passiveId:record(definition.passive)&&typeof definition.passive.id==="string"?definition.passive.id:undefined,cooldowns:{},statuses:[]
  });
 }
 for(const bond of ascendedBonds){
  if(!bond.members.every(id=>owned.some(c=>c.char_id===id&&c.ascension===3)))continue;
  for(const unit of units){
   if(!bond.members.includes(unit.charId))continue;
   if(bond.stat==="def")unit.defense*=bond.multiplier;
   if(bond.stat==="atk")unit.atk*=bond.multiplier;
  }
 }
 return {ok:true,units,skillbook};
}

export function createInitialPvpState(matchId:string,seed:number,first: {playerId:string;team:1|2;units:PvpUnit[]},second:{playerId:string;team:1|2;units:PvpUnit[]}):PvpState|null{
 if(!matchId||!Number.isSafeInteger(seed)||first.team===second.team||first.playerId===second.playerId||
  first.units.length<1||second.units.length<1)return null;
 const units=[...first.units,...second.units];
 for(const ownerId of [first.playerId,second.playerId]){if(units.some(u=>u.ownerId===ownerId&&u.passiveId==="small_miracles"))for(const ally of units.filter(u=>u.ownerId===ownerId))ally.energy=Math.min(100,ally.energy+10);}
 if(units.some(u=>u.ownerId!==first.playerId&&u.ownerId!==second.playerId))return null;
 const firstAura=first.units.some(u=>u.passiveId==="whisperstep")?1.08:1;
 const firstSpeed=first.units.reduce((max,u)=>Math.max(max,u.speed*firstAura),Number.NEGATIVE_INFINITY);
 const secondAura=second.units.some(u=>u.passiveId==="whisperstep")?1.08:1;
 const secondSpeed=second.units.reduce((max,u)=>Math.max(max,u.speed*secondAura),Number.NEGATIVE_INFINITY);
 const turnPlayerId=firstSpeed>=secondSpeed?first.playerId:second.playerId;
 return {matchId,seed,sequence:0,turn:1,turnPlayerId,units,status:"active",passiveFlags:[]};
}
