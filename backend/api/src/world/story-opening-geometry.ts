import {readFileSync} from "node:fs";
import type {WorldPosition} from "./movement.js";
type Pair=[number,number];
type OpeningRegion={spawn:Pair;outline:Pair[];encounter:{groupId:string;position:Pair;radius:number};nextRegion:string};
const data=JSON.parse(readFileSync(new URL("../../../../resources/data/story_opening_regions.json",import.meta.url),"utf8")) as Record<string,OpeningRegion>;
export function openingRegion(id:string):OpeningRegion|undefined{return Object.hasOwn(data,id)?data[id]:undefined;}
export function openingContains(id:string,p:WorldPosition):boolean{
 const region=openingRegion(id);if(!region||!Number.isFinite(p.x)||!Number.isFinite(p.y))return false;
 let inside=false;
 for(let i=0,j=region.outline.length-1;i<region.outline.length;j=i++){
  const [ax,ay]=region.outline[j]!,[bx,by]=region.outline[i]!;
  const cross=(p.x-ax)*(by-ay)-(p.y-ay)*(bx-ax);
  if(Math.abs(cross)<1e-8&&p.x>=Math.min(ax,bx)&&p.x<=Math.max(ax,bx)&&p.y>=Math.min(ay,by)&&p.y<=Math.max(ay,by))return true;
  if((ay>p.y)!==(by>p.y)&&p.x<(bx-ax)*(p.y-ay)/(by-ay)+ax)inside=!inside;
 }
 return inside;
}
export function openingSpawn(id:string):WorldPosition|undefined{
 const r=openingRegion(id);return r?{x:r.spawn[0],y:r.spawn[1]}:undefined;
}
export function openingEncounterInRange(id:string,groupId:string,p:WorldPosition):boolean{
 const r=openingRegion(id);return !!r&&r.encounter.groupId===groupId&&openingContains(id,p)&&Math.hypot(p.x-r.encounter.position[0],p.y-r.encounter.position[1])<=r.encounter.radius;
}
