// The server owns the chapter order, position requirements and recruitment.
export const villageStages=[
 {quest:"village_clear_approach",groups:["village_slime_1","village_slime_2"],positions:[[-1910,192],[-1740,220]]},
 {quest:"village_crimson_duel",groups:["village_crimson_encounter"],positions:[[-1550,260]],recruit:"crimson_witch_legendary"},
 {quest:"village_clear_ruins",groups:["village_crownling_1","village_crownling_2","village_crownling_3"],positions:[[-1300,500],[-1000,800],[-750,1100]]},
 {quest:"village_nyx_duel",groups:["village_nyx_encounter"],positions:[[-500,1500]],recruit:"nyx"},
 {quest:"village_gerald_trial",groups:["gerald_boss_encounter"],positions:[[13,2865]]}
] as const;
export const villageGroups:readonly string[]=villageStages.flatMap(s=>[...s.groups]);
export const villageRecruit=(group:string)=>group==="village_crimson_encounter"?"crimson_witch_legendary":group==="village_nyx_encounter"?"nyx":null;
export const villageProgressionEnabled=()=>process.env.NODE_ENV!=="production"&&process.env.REVERIE_VILLAGE_PROGRESSION_PILOT==="1";
export function villageStageFor(group:string){return villageStages.findIndex(s=>(s.groups as readonly string[]).includes(group));}
export function villageParty(group:string):string[]{
 const stage=villageStageFor(group);
 if(stage===2)return ["kael","crimson_witch_legendary"];
 if(stage===4)return ["kael","crimson_witch_legendary","nyx"];
 return ["kael"];
}
export function villageProgress(wins:readonly string[]){
 const completed=new Set(wins);
 const legacy=completed.has("gerald_boss_encounter")&&!completed.has("village_nyx_encounter");
 return villageStages.map((stage,index)=>({
  quest:stage.quest,progress:legacy?stage.groups.length:stage.groups.filter(g=>completed.has(g)).length,
  total:stage.groups.length,state:legacy||stage.groups.every(g=>completed.has(g))?"complete":villageStages.slice(0,index).every(s=>s.groups.every(g=>completed.has(g)))?"active":"not_started"
 }));
}
export function villageAdmission(group:string,wins:readonly string[],position:{x:number;y:number}|null):string|null{
 const i=villageStageFor(group);if(i<0)return "encounter_not_enabled";
 if(!wins.includes("tutorial_fairy_spar"))return "story_progression_required";
 if(wins.includes(group)||wins.includes("gerald_boss_encounter"))return "already_claimed";
 if(!villageStages.slice(0,i).every(s=>s.groups.every(g=>wins.includes(g))))return "story_progression_required";
 const stage=villageStages[i]!,p=stage.positions[(stage.groups as readonly string[]).indexOf(group)]!;
 if(!position||!Number.isFinite(position.x)||!Number.isFinite(position.y)||Math.hypot(position.x-p[0]!,position.y-p[1]!)>95)return "encounter_position_required";
 return null;
}
