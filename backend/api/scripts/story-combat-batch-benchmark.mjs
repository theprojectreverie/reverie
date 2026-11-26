import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {mkdtemp,writeFile,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
const exe=process.env.REVERIE_STORY_GODOT;assert.ok(exe);
const project=fileURLToPath(new URL("../../../",import.meta.url));
const run=promisify(execFile),marker="STORY_COMBAT_RESULT ";
const make=(id,level,bond=0,equipment=[])=>({char_id:id,level,xp:"0",ascension:0,awakening:0,bond,dupes:0,skill_levels:{},equipment});
const basic={groupId:"rose_slime_garden_1",seed:42,party:[make("kael",1),make("gerald",1),make("lilith",1)],collectionCount:3,actions:[]};
const solo={...basic,groupId:"gerald_boss_encounter",seed:888,party:[make("kael",12,20,[{slot:"weapon",item_id:"gladewood_bow",enhancement_level:2}])],collectionCount:12};
const other={...basic,groupId:"revienna_encounter",seed:24,party:[make("lilith",20),make("kael",10)],collectionCount:7};
async function simulate(input,batch=false){
 const dir=await mkdtemp(join(tmpdir(),"reverie-batch-qa-"));
 try{
  const path=join(dir,"input.json");await writeFile(path,JSON.stringify(input));
  const env={REVERIE_E2E_DISABLE_LOCAL_SAVE:"1",REVERIE_STORY_WORKER:"1",APPDATA:dir,XDG_DATA_HOME:dir,XDG_CONFIG_HOME:dir,HOME:dir,USERPROFILE:dir,TEMP:dir,TMP:dir};
  for(const key of ["PATH","SystemRoot","WINDIR","LD_LIBRARY_PATH"])if(process.env[key])env[key]=process.env[key];
  const {stdout}=await run(exe,["--headless","--path",project,"res://tools/story_combat_worker.tscn","--",...(batch?["--batch"]:[]),path],{env,timeout:30000,maxBuffer:4*1024*1024,windowsHide:true});
  const results=stdout.split(/\r?\n/).filter(l=>l.startsWith(marker)).map(l=>JSON.parse(l.slice(marker.length)));
  assert.equal(results.length,batch?input.length:1);return batch?results:results[0];
 }finally{await rm(dir,{recursive:true,force:true});}
}
const initial=await simulate(basic);assert.ok(initial.ok,JSON.stringify(initial));
const actor=initial.units.find(u=>u.uid===initial.actorUid);const foe=initial.units.find(u=>u.team===1);
const acted={...basic,actions:[{kind:"skill",actorUid:actor.uid,skillId:actor.skills[0],targetUids:[foe.uid]}]};
const invalid={...basic,actions:[{kind:"defend",actorUid:"wrong"}]};
const jobs=[basic,solo,other,acted,invalid,basic,solo,acted];
let start=performance.now();const isolated=[];for(const job of jobs)isolated.push(await simulate(job));const cold=performance.now()-start;
assert.ok(isolated.every((r,i)=>i===4?!r.ok:r.ok),JSON.stringify(isolated.map(r=>r.reason)));
start=performance.now();const batch=await simulate(jobs,true);const warm=performance.now()-start;
assert.deepEqual(batch,isolated);assert.deepEqual(batch[0],batch[5]);assert.deepEqual(batch[1],batch[6]);assert.deepEqual(batch[3],batch[7]);
console.log(JSON.stringify({jobs:jobs.length,isolatedMs:Math.round(cold),batchMs:Math.round(warm),speedup:Number((cold/warm).toFixed(2))}));
console.log("PASS batch matches isolated processes exactly, including gear, mixed rosters, invalid action and repeated state");
