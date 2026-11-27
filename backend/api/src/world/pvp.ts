export type PvpStatus = { id: string; turns: number; potency: number };
export type PvpUnit = {
  uid: string; ownerId: string; team: 1 | 2; charId: string; element: string; ascension?: number;
  maxHp: number; hp: number; atk: number; defense: number; speed: number;
  critChance: number; critDamage?: number; energy: number; shield: number;
  skillIds: string[]; ultimateId?: string; passiveId?: string; skillLevels?: Record<string,number>;
  cooldowns: Record<string, number>; statuses: PvpStatus[];
};
export type PvpSkill = {
  id: string; kind: "damage" | "heal" | "shield" | "buff" | "debuff";
  power: number; element?: string; target: "single_enemy" | "all_enemies" | "single_ally" | "all_allies" | "self";
  scalingStat?: "atk" | "def" | "hp" | "spd"; critBonus?: number;
  energyGain?: number; cooldownTurns?: number; ultimate?: boolean;
  cleanse?: boolean; lifesteal?: number; statuses?: Array<{id:string;chance?:number;turns?:number;potency?:number}>;
};
export type PvpState = {
  matchId: string; seed: number; sequence: number; turn: number;
  turnPlayerId: string; units: PvpUnit[]; status: "active" | "completed";
  winnerId?: string; passiveFlags?: string[]; bonds?: Record<string,{gauge:number;uses:number}>; skillbook?: Record<string,PvpSkill>;
};
export type PvpAction = { playerId: string; actorUid: string; skillId: string; targetUids: string[]; sequence: number };
export type PvpResult = { ok: true; state: PvpState; events: Array<Record<string, unknown>> } |
  { ok: false; reason: "match_finished" | "wrong_turn" | "unknown_actor" | "not_owned" | "unknown_skill" | "skill_not_equipped" | "cooldown" | "ultimate_not_ready" | "invalid_targets" | "invalid_sequence" | "stunned" | "bond_not_ready" };

const clamp = (n:number,min:number,max:number) => Math.max(min,Math.min(max,n));
const SUPPORTED_STATUSES = new Set(["atk_up","atk_down","def_up","def_down","spd_up","spd_down","burn","poison","stun","blind","regen","shield","bond_guard","bond_survive","eclipse_curse"]);
const CLEANSABLE_STATUSES = new Set(["burn","poison","stun","blind","atk_down","def_down","spd_down","eclipse_curse"]);
const MAX_STATUS_TURNS = 20;
const MAX_STATUS_POTENCY = 1;
function randomStream(seed:number, sequence:number): () => number {
  let x = (Math.imul(seed >>> 0, 1664525) + Math.imul(sequence >>> 0, 1013904223)) >>> 0;
  return () => { x ^= x << 13; x ^= x >>> 17; x ^= x << 5; return (x >>> 0) / 4294967296; };
}
function alive(unit:PvpUnit):boolean { return unit.hp > 0; }
function elementMultiplierFor(attacker:string, defender:string):number {
  const beats:Record<string,string>={fire:"wind",wind:"earth",earth:"water",water:"fire"};
  if(attacker==="neutral"||defender==="neutral"||attacker===defender) return 1;
  if((attacker==="light"&&defender==="dark")||(attacker==="dark"&&defender==="light")) return 1.5;
  if(beats[attacker]===defender) return 1.5;
  if(beats[defender]===attacker) return 0.75;
  return 1;
}
function applyStatus(unit:PvpUnit, id:string, turns:number, potency:number):void {
  const existing=unit.statuses.find(s=>s.id===id);
  if(existing){ existing.turns=Math.max(existing.turns,turns); existing.potency=Math.max(existing.potency,potency); }
  else unit.statuses.push({id,turns,potency});
}
function stat(unit:PvpUnit, name:string):number {
  let base=name==="def"?unit.defense:name==="hp"?unit.maxHp:name==="spd"?unit.speed:unit.atk;
  if(name==="def"&&unit.passiveId==="deep_roots")base*=1.15;
  if(name==="spd"&&unit.passiveId!=="whisperstep")base*=1;
  const up=unit.statuses.filter(s=>s.id===name+"_up").reduce((a,s)=>a+s.potency,0);
  const down=unit.statuses.filter(s=>s.id===name+"_down").reduce((a,s)=>a+s.potency,0);
  return Math.max(1,base*clamp(1+up-down,0.25,3));
}
function isRecord(value:unknown):value is Record<string,unknown> { return typeof value==="object" && value!==null && !Array.isArray(value); }
function validNumbers(u:PvpUnit):boolean {
  return typeof u.uid==="string" && u.uid.length>0 && typeof u.ownerId==="string" && u.ownerId.length>0 &&
    (u.team===1||u.team===2) && typeof u.charId==="string" && u.charId.length>0 &&
    typeof u.element==="string" && u.element.length>0 &&
    (u.ascension===undefined||(Number.isInteger(u.ascension)&&u.ascension>=0&&u.ascension<=3)) &&
    [u.maxHp,u.hp,u.atk,u.defense,u.speed,u.critChance,u.critDamage??1.6,u.energy,u.shield].every(Number.isFinite) &&
    u.maxHp>0 && u.hp>=0 && u.hp<=u.maxHp && u.atk>0 && u.defense>=0 && u.speed>0 &&
    u.critChance>=0 && u.critChance<=1 && (u.critDamage??1.6)>=1 && (u.critDamage??1.6)<=5 &&
    u.energy>=0 && u.energy<=100 && u.shield>=0 && u.shield<=u.maxHp*10 && Array.isArray(u.skillIds) &&
    u.skillIds.every(id=>typeof id==="string"&&id.length>0) && new Set(u.skillIds).size===u.skillIds.length &&
    (u.skillLevels===undefined||(isRecord(u.skillLevels)&&Object.entries(u.skillLevels).every(([id,n])=>(u.skillIds.includes(id)||u.ultimateId===id)&&Number.isInteger(n)&&Number(n)>=1&&Number(n)<=5))) &&
    (u.ultimateId===undefined||(typeof u.ultimateId==="string"&&u.ultimateId.length>0&&!u.skillIds.includes(u.ultimateId))) &&
    (u.passiveId===undefined||(typeof u.passiveId==="string"&&u.passiveId.length>0)) &&
    Array.isArray(u.statuses) && u.statuses.length<=16 && u.statuses.every(s=>isRecord(s)&&typeof s.id==="string"&&SUPPORTED_STATUSES.has(s.id)&&Number.isInteger(s.turns)&&Number(s.turns)>0&&Number(s.turns)<=MAX_STATUS_TURNS&&Number.isFinite(s.potency)&&Number(s.potency)>=0&&Number(s.potency)<=MAX_STATUS_POTENCY) && new Set(u.statuses.map(s=>(s as PvpStatus).id)).size===u.statuses.length &&
    isRecord(u.cooldowns) && Object.entries(u.cooldowns).every(([id,n])=>(u.skillIds.includes(id)||u.ultimateId===id)&&Number.isInteger(n)&&Number(n)>=0&&Number(n)<=100);
}
function validSkill(skill:PvpSkill,key:string):boolean {
  const kinds=["damage","heal","shield","buff","debuff"];
  const targets=["single_enemy","all_enemies","single_ally","all_allies","self"];
  if(!Array.isArray(skill.statuses??[]) || skill.id!==key || !kinds.includes(skill.kind) || !targets.includes(skill.target) ||
    !Number.isFinite(skill.power) || skill.power<0 || skill.power>1000 ||
    (skill.critBonus!==undefined && (!Number.isFinite(skill.critBonus)||skill.critBonus<0||skill.critBonus>1)) ||
    (skill.energyGain!==undefined && (!Number.isInteger(skill.energyGain)||skill.energyGain<0||skill.energyGain>100)) ||
    (skill.cooldownTurns!==undefined && (!Number.isInteger(skill.cooldownTurns)||skill.cooldownTurns<0||skill.cooldownTurns>20)) ||
    (skill.lifesteal!==undefined && (!Number.isFinite(skill.lifesteal)||skill.lifesteal<0||skill.lifesteal>1)) ||
    !(skill.statuses??[]).every(s=>isRecord(s)&&typeof s.id==="string"&&s.id.length>0&&
      (s.chance===undefined||(Number.isFinite(s.chance)&&s.chance>=0&&s.chance<=1))&&
      (s.turns===undefined||(Number.isInteger(s.turns)&&s.turns>0&&s.turns<=MAX_STATUS_TURNS))&&
      (s.potency===undefined||(Number.isFinite(s.potency)&&s.potency>=0&&s.potency<=MAX_STATUS_POTENCY))&&SUPPORTED_STATUSES.has(s.id)&&!["bond_guard","bond_survive","eclipse_curse"].includes(s.id))) return false;
  const allyTarget=skill.target==="single_ally"||skill.target==="all_allies"||skill.target==="self";
  if((skill.kind==="heal"||skill.kind==="shield"||skill.kind==="buff")&&!allyTarget) return false;
  if((skill.kind==="damage"||skill.kind==="debuff")&&allyTarget) return false;
  if(skill.target==="self"&&skill.kind!=="heal"&&skill.kind!=="shield"&&skill.kind!=="buff") return false;
  if((skill.kind==="buff"||skill.kind==="debuff")&&(skill.statuses?.length??0)===0) return false;
  return true;
}
function targetsFor(state:PvpState, actor:PvpUnit, skill:PvpSkill, ids:string[]):PvpUnit[]|null {
  if(skill.target==="self") return ids.length===0 ? [actor] : null;
  const allies=skill.target==="single_ally"||skill.target==="all_allies";
  const all=skill.target==="all_enemies"||skill.target==="all_allies";
  const candidates=state.units.filter(u=>alive(u) && (allies ? u.team===actor.team : u.team!==actor.team));
  const chosen=all?candidates:candidates.filter(u=>ids.includes(u.uid));
  if(!all && (ids.length!==1 || chosen.length!==1)) return null;
  if(all && ids.length!==0) return null;
  return chosen.length?chosen:null;
}
const BOND_PAIRS:Record<string,readonly string[]>={beyond_death:["gerald_mythic","lilith_mythic"],eternal_eclipse:["cassien_mythic","ravienna_mythic"]};
function bondPair(state:PvpState,actor:PvpUnit,id:string):PvpUnit[]{
 const members=BOND_PAIRS[id];if(!members||!members.includes(actor.charId))return [];
 const pair=members.map(charId=>state.units.find(u=>u.team===actor.team&&u.charId===charId&&u.ascension===3&&alive(u)));
 return pair.every(u=>u!==undefined)?pair as PvpUnit[]:[];
}
function chargeBond(state:PvpState,actor:PvpUnit){
 for(const id of Object.keys(BOND_PAIRS)){
  if(bondPair(state,actor,id).length!==2)continue;
  const key=actor.team+":"+id;state.bonds??={};const bond=state.bonds[key]??={gauge:0,uses:0};
  if(bond.uses<2)bond.gauge=Math.min(100,bond.gauge+25);
 }
}
function bondDamage(state:PvpState,unit:PvpUnit,amount:number,events:Record<string,unknown>[],redirect=true):{dealt:number;absorbed:number}{
 if(redirect&&unit.statuses.some(s=>s.id==="bond_guard")){
  const guardian=state.units.find(u=>u.team===unit.team&&u.charId==="gerald_mythic"&&alive(u)&&u.uid!==unit.uid);
  if(guardian){const transfer=amount*0.35;amount-=transfer;const result=bondDamage(state,guardian,transfer,events,false);
   events.push({type:"status_damage",targetUid:guardian.uid,status:"bond_guard",amount:result.dealt,absorbed:result.absorbed});
   if(!alive(guardian))events.push({type:"defeat",targetUid:guardian.uid});
  }
 }
 const before=unit.hp;const absorbed=Math.min(unit.shield,amount);unit.shield-=absorbed;unit.hp=Math.max(0,unit.hp-(amount-absorbed));
 if(before>0&&!alive(unit)&&unit.statuses.some(s=>s.id==="bond_survive")){
  unit.hp=1;unit.statuses=unit.statuses.filter(s=>s.id!=="bond_survive");
  events.push({type:"status",targetUid:unit.uid,status:"bond_survive",turns:0});
 }
 return {dealt:before-unit.hp,absorbed};
}
function applyBond(state:PvpState,actor:PvpUnit,id:string,events:Record<string,unknown>[],fresh:Set<string>){
 const pair=bondPair(state,actor,id);const key=actor.team+":"+id;const bond=state.bonds![key]!;
 bond.gauge=0;bond.uses++;
 events.push({type:"bond",bond_id:id,actorUid:actor.uid,memberUids:pair.map(u=>u.uid)});
 const status=(u:PvpUnit,name:string,turns:number,potency:number)=>{applyStatus(u,name,turns,potency);fresh.add(u.uid+":"+name);events.push({type:"status",targetUid:u.uid,status:name,turns});};
 const heal=(u:PvpUnit,amount:number)=>{const before=u.hp;u.hp=Math.min(u.maxHp,u.hp+amount);events.push({type:"heal",targetUid:u.uid,amount:Math.round(u.hp-before)});};
 if(id==="beyond_death"){
  for(const ally of state.units.filter(u=>u.team===actor.team&&alive(u))){
   heal(ally,ally.maxHp*0.5);const amount=Math.min(ally.maxHp*10-ally.shield,ally.maxHp*0.3);ally.shield+=amount;
   events.push({type:"shield",targetUid:ally.uid,amount:Math.round(amount)});
   if(ally!==pair[0])status(ally,"bond_guard",2,0.35);
  }
  for(const sibling of pair)status(sibling,"bond_survive",2,1);
 }else{
  const combined=pair.reduce((sum,u)=>sum+stat(u,"atk"),0);let dealt=0;
  for(const foe of state.units.filter(u=>u.team!==actor.team&&alive(u))){
   if(!alive(foe))continue;
   let multiplier=1;if(foe.passiveId==="rooted"&&foe.hp/foe.maxHp<0.5)multiplier*=0.9;
   if(state.units.some(u=>u.team===foe.team&&u.uid!==foe.uid&&alive(u)&&u.passiveId==="hold_the_line"))multiplier*=0.94;
   const result=bondDamage(state,foe,Math.max(1,Math.round(4.5*combined*combined/(combined+stat(foe,"def"))*multiplier)),events);
   dealt+=result.dealt;events.push({type:"damage",actorUid:actor.uid,targetUid:foe.uid,amount:result.dealt,absorbed:result.absorbed,crit:false,skillId:id});
   if(alive(foe)){status(foe,"def_down",2,0.4);status(foe,"eclipse_curse",3,0.05);}else events.push({type:"defeat",targetUid:foe.uid});
  }
  for(const ally of state.units.filter(u=>u.team===actor.team&&alive(u))){ally.statuses=ally.statuses.filter(s=>!CLEANSABLE_STATUSES.has(s.id));events.push({type:"status",targetUid:ally.uid,status:"cleanse",turns:0});}
  for(const member of pair)if(alive(member))heal(member,dealt*0.125);
 }
}
export function resolvePvpAction(state:PvpState, action:PvpAction, skillbook:Record<string,PvpSkill>):PvpResult {
  if(state.status!=="active") return {ok:false,reason:"match_finished"};
  if(state.passiveFlags!==undefined&&(!Array.isArray(state.passiveFlags)||state.passiveFlags.length>64||state.passiveFlags.some(v=>typeof v!=="string"||v.length>160)||new Set(state.passiveFlags).size!==state.passiveFlags.length))return {ok:false,reason:"unknown_actor"};
  if(typeof state.matchId!=="string"||state.matchId.length===0||typeof state.turnPlayerId!=="string"||state.turnPlayerId.length===0||!Number.isSafeInteger(state.sequence)||state.sequence<0||!Number.isSafeInteger(state.turn)||state.turn<1||!Number.isSafeInteger(state.seed)||!Array.isArray(state.units)||state.units.length<2||!state.units.every(validNumbers)||new Set(state.units.map(u=>u.uid)).size!==state.units.length||new Set(state.units.map(u=>u.ownerId)).size!==2) return {ok:false,reason:"unknown_actor"};
  const ownerTeams=new Map(state.units.map(u=>[u.ownerId,u.team]));
  if(new Set(ownerTeams.values()).size!==2||!ownerTeams.has(state.turnPlayerId)||state.units.some(u=>ownerTeams.get(u.ownerId)!==u.team)||!state.units.some(u=>u.team===1&&alive(u))||!state.units.some(u=>u.team===2&&alive(u))) return {ok:false,reason:"unknown_actor"};
  if(!action||typeof action.playerId!=="string"||typeof action.actorUid!=="string"||typeof action.skillId!=="string"||!Array.isArray(action.targetUids)||!action.targetUids.every(id=>typeof id==="string")||!Number.isSafeInteger(action.sequence)) return {ok:false,reason:"invalid_sequence"};
  if(action.playerId!==state.turnPlayerId) return {ok:false,reason:"wrong_turn"};
  if(action.sequence!==state.sequence+1) return {ok:false,reason:"invalid_sequence"};
  const actor=state.units.find(u=>u.uid===action.actorUid);
  if(!actor || !alive(actor)) return {ok:false,reason:"unknown_actor"};
  if(actor.ownerId!==action.playerId) return {ok:false,reason:"not_owned"};
  if(!validNumbers(actor)) return {ok:false,reason:"unknown_actor"};
  const isStunned=actor.statuses.some(s=>s.id==="stun");
  const isBond=!isStunned&&Object.prototype.hasOwnProperty.call(BOND_PAIRS,action.skillId);
  if(state.bonds!==undefined&&(!isRecord(state.bonds)||Object.entries(state.bonds).some(([key,b])=>!["1:beyond_death","1:eternal_eclipse","2:beyond_death","2:eternal_eclipse"].includes(key)||!isRecord(b)||!Number.isInteger(b.gauge)||Number(b.gauge)<0||Number(b.gauge)>100||!Number.isInteger(b.uses)||Number(b.uses)<0||Number(b.uses)>2)))return {ok:false,reason:"unknown_actor"};
  if(isBond){
   const bond=state.bonds?.[actor.team+":"+action.skillId];
   if(bondPair(state,actor,action.skillId).length!==2||!bond||bond.gauge<100||bond.uses>=2)return {ok:false,reason:"bond_not_ready"};
   if(action.targetUids.length!==0)return {ok:false,reason:"invalid_targets"};
  }
  let skill:PvpSkill;
  if(isStunned) skill={id:"__stun_skip",kind:"buff",power:0,target:"self"};
  else if(isBond) skill={id:action.skillId,kind:"buff",power:0,target:"self"};
  else {
    if(!isRecord(skillbook)||!Object.prototype.hasOwnProperty.call(skillbook,action.skillId)) return {ok:false,reason:"unknown_skill"};
    const selectedSkill=skillbook[action.skillId];
    if(!selectedSkill||!isRecord(selectedSkill)) return {ok:false,reason:"unknown_skill"};
    skill=selectedSkill;
  }
  if(!isStunned&&!isBond){
    const isEquippedUltimate=actor.ultimateId===skill.id;
    if(skill.ultimate ? !isEquippedUltimate : (!actor.skillIds.includes(skill.id) || isEquippedUltimate)) return {ok:false,reason:"skill_not_equipped"};
    if((actor.cooldowns[skill.id]??0)>0) return {ok:false,reason:"cooldown"};
    if(skill.ultimate && actor.energy<100) return {ok:false,reason:"ultimate_not_ready"};
    if(!validSkill(skill,action.skillId)) return {ok:false,reason:"unknown_skill"};
  }
  const targets=isStunned||isBond ? [actor] : targetsFor(state,actor,skill,action.targetUids);
  if(!targets) return {ok:false,reason:"invalid_targets"};
  const next: PvpState=structuredClone(state);
  const nextActor=next.units.find(u=>u.uid===actor.uid)!;
  const skillMultiplier=1+0.05*((nextActor.skillLevels?.[skill.id]??1)-1);
  const nextTargets=targets.map(t=>next.units.find(u=>u.uid===t.uid)!);
  const rng=randomStream(state.seed,action.sequence);
  const events:Array<Record<string,unknown>>=[];
  const newlyAppliedStatuses=new Set<string>();
  if(isStunned) events.push({type:"turn_skipped",playerId:action.playerId,actorUid:actor.uid,reason:"stun"});
  else if(isBond) applyBond(next,nextActor,skill.id,events,newlyAppliedStatuses);
  else {
    if(skill.ultimate) nextActor.energy=0;
    else nextActor.energy=clamp(nextActor.energy+(skill.energyGain??20),0,100);
    if((skill.cooldownTurns??0)>0) nextActor.cooldowns[skill.id]=(skill.cooldownTurns??0)+1;
  }
  for(const target of (isStunned||isBond ? [] : nextTargets)){
    if(skill.kind==="damage"){
      const blind=nextActor.statuses.find(s=>s.id==="blind");
      if(blind&&rng()<0.3){events.push({type:"attack_missed",actorUid:actor.uid,targetUid:target.uid,reason:"blind",skillId:skill.id});continue;}
      const scaling=stat(nextActor,skill.scalingStat??"atk");
      const defense=stat(target,"def");
      const elementMultiplier=elementMultiplierFor(skill.element??"neutral",target.element);
      let passiveMultiplier=1;
      if(target.passiveId==="rooted"&&target.hp/target.maxHp<0.5)passiveMultiplier*=0.90;
      if(next.units.some(u=>u.ownerId===target.ownerId&&u.uid!==target.uid&&u.hp>0&&u.passiveId==="hold_the_line"))passiveMultiplier*=0.94;
      if(nextActor.passiveId==="nothing_to_lose"&&nextActor.hp/nextActor.maxHp<0.4)passiveMultiplier*=1.12;
      if(nextActor.passiveId==="hollow_crown"&&(skill.element??"neutral")==="dark"&&target.statuses.some(s=>["burn","poison","stun","blind","atk_down","def_down","spd_down"].includes(s.id)))passiveMultiplier*=1.15;
      if(nextActor.passiveId==="patient_weaver"&&target.statuses.some(s=>s.id==="stun"))passiveMultiplier*=1.2;
      let raw=skill.power*skillMultiplier*(scaling/(scaling+defense))*1.6*elementMultiplier*passiveMultiplier*(0.95+rng()*0.10);
      const crit=rng()<clamp(nextActor.critChance+(skill.critBonus??0),0,1);
      if(crit) raw*=nextActor.critDamage??1.6;
      const damage=Math.max(1,Math.round(raw));
      const {absorbed,dealt}=bondDamage(next,target,damage,events);
      target.energy=clamp(target.energy+8,0,100);
      nextActor.energy=clamp(nextActor.energy+6,0,100);
      events.push({type:"damage",actorUid:actor.uid,targetUid:target.uid,amount:dealt,absorbed,crit,skillId:skill.id});
      const passiveLifesteal=nextActor.passiveId==="sanguine_waltz"?0.20:0;
      const lifesteal=Math.min(1,(skill.lifesteal??0)+passiveLifesteal);
      if(lifesteal>0&&dealt>0){
        const before=nextActor.hp;
        nextActor.hp=Math.min(nextActor.maxHp,nextActor.hp+Math.round(dealt*lifesteal));
        if(nextActor.hp>before)events.push({type:"lifesteal",actorUid:actor.uid,amount:nextActor.hp-before,skillId:skill.id});
      }

      if(crit&&nextActor.passiveId==="ashen_wake"){applyStatus(target,"burn",2,0.05);newlyAppliedStatuses.add(target.uid+":burn");events.push({type:"status",targetUid:target.uid,status:"burn",turns:2,passiveId:"ashen_wake"});}
      if(target.hp===0) events.push({type:"defeat",targetUid:target.uid});
    } else if(skill.kind==="heal"){
      const before=target.hp; target.hp=Math.min(target.maxHp,target.hp+target.maxHp*skill.power*skillMultiplier/100);
      events.push({type:"heal",targetUid:target.uid,amount:Math.round(target.hp-before)});
      if(nextActor.passiveId==="tidecall"){const amount=target.maxHp*0.08;target.shield+=amount;events.push({type:"passive_shield",targetUid:target.uid,amount:Math.round(amount),passiveId:"tidecall"});}
      if(skill.cleanse) target.statuses=target.statuses.filter(s=>!CLEANSABLE_STATUSES.has(s.id));
    } else if(skill.kind==="shield"){
      const amount=target.maxHp*skill.power*skillMultiplier/100; target.shield+=amount;
      events.push({type:"shield",targetUid:target.uid,amount:Math.round(amount)});
    }
    for(const status of skill.statuses??[]){
      if(rng()<(status.chance??1)) {
        const scaledStatus=(skill.kind==="buff"||skill.kind==="debuff")&&["atk_up","atk_down","def_up","def_down","spd_up","spd_down","regen","burn","poison","shield"].includes(status.id);
        applyStatus(target,status.id,status.turns??1,Math.min(MAX_STATUS_POTENCY,(status.potency??0)*(scaledStatus?skillMultiplier:1)));
        newlyAppliedStatuses.add(target.uid+":"+status.id);
        events.push({type:"status",targetUid:target.uid,status:status.id,turns:status.turns??1});
      }
    }
  }
  if(!isStunned&&!isBond)chargeBond(next,nextActor);
  // A status duration counts completed turns of its owner. Newly applied effects
  // are not shortened on the same action that created them.
  for(const unit of next.units.filter(u=>u.ownerId===action.playerId)) {
    const remaining:PvpStatus[]=[];
    for(const status of [...unit.statuses]) {
      if(!unit.statuses.some(s=>s.id===status.id))continue;
      if(newlyAppliedStatuses.has(unit.uid+":"+status.id)) { remaining.push(status); continue; }
      // Burn and poison deal flat authored damage at the end of their owner's
      // action. Shields absorb this damage before HP, just like direct attacks.
      if((status.id==="burn"||status.id==="poison"||status.id==="eclipse_curse")&&alive(unit)&&status.potency>0) {
        const damage=Math.min(unit.maxHp,Math.max(1,Math.round(unit.maxHp*status.potency)));
        const {absorbed,dealt}=bondDamage(next,unit,damage,events);
        events.push({type:"status_damage",targetUid:unit.uid,status:status.id,amount:dealt,absorbed});
        if(unit.hp===0) events.push({type:"defeat",targetUid:unit.uid});
      } else if(status.id==="regen"&&alive(unit)&&status.potency>0) {
        const before=unit.hp; unit.hp=Math.min(unit.maxHp,unit.hp+Math.round(unit.maxHp*status.potency));
        if(unit.hp>before) events.push({type:"status_heal",targetUid:unit.uid,status:status.id,amount:unit.hp-before});
      } else if(status.id==="shield"&&alive(unit)&&status.potency>0) {
        const before=unit.shield; unit.shield=Math.min(unit.maxHp*10,unit.shield+Math.round(unit.maxHp*status.potency));
        if(unit.shield>before) events.push({type:"status_shield",targetUid:unit.uid,status:status.id,amount:unit.shield-before});
      }
      const turns=status.turns-1;
      if(turns>0) remaining.push({...status,turns});
      else events.push({type:"status_expired",targetUid:unit.uid,status:status.id});
    }
    unit.statuses=remaining.filter(s=>unit.statuses.some(old=>old.id===s.id));
  }
  if(!isStunned&&skill.kind==="heal"&&nextActor.passiveId==="dawnkeeper"){const flag=nextActor.uid+":dawnkeeper";next.passiveFlags??=[];if(!next.passiveFlags.includes(flag)){nextActor.energy=clamp(nextActor.energy+20,0,100);next.passiveFlags.push(flag);events.push({type:"passive_energy",actorUid:nextActor.uid,amount:20,passiveId:"dawnkeeper"});}}
  const nextPlayer=next.units.find(u=>u.ownerId!==action.playerId && alive(u))?.ownerId ?? action.playerId;
  for(const unit of next.units.filter(u=>u.ownerId===nextPlayer))
    for(const id of Object.keys(unit.cooldowns)) { unit.cooldowns[id]=Math.max(0,(unit.cooldowns[id]??0)-1); if(unit.cooldowns[id]===0) delete unit.cooldowns[id]; }
  next.sequence=action.sequence; next.turn+=1; next.turnPlayerId=nextPlayer;
  const livingOwners=[...new Set(next.units.filter(alive).map(u=>u.ownerId))];
  if(livingOwners.length<=1){next.status="completed";next.winnerId=livingOwners[0]??"";events.push({type:"match_completed",winnerId:next.winnerId});}
  return {ok:true,state:next,events};
}
