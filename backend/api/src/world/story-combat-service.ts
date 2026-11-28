import {villageProgressionEnabled,villageGroups,villageParty} from "./village-progression.js";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {randomInt,createHash} from "node:crypto";
import {mkdtemp,writeFile,rm} from "node:fs/promises";
import {readFileSync,readdirSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import type {PoolClient} from "pg";
import {z} from "zod";
import {STARTER_PARTY} from "./character-xp.js";
import {liveDefinitions} from "./live-character-packs.js";
import {retiredPlayableIds} from "./summon.js";
import {settleStoryVictory} from "./story-battle-rewards.js";
import {StoryWorkerQueue} from "./story-worker-queue.js";
import {StoryWorkerBatcher} from "./story-worker-batcher.js";
import {StoryTransactionAdmission} from "./story-transaction-admission.js";
import {pool} from "../db.js";
import {isOneTimeStoryEncounter,TUTORIAL_GROUP} from "./story-progression-proof.js";
// Future authenticated route handlers must enter through this shared gate.
export const storyTransactionAdmission=new StoryTransactionAdmission(pool,8);

const run=promisify(execFile);
const project=fileURLToPath(new URL("../../../../",import.meta.url));
const groups=JSON.parse(readFileSync(join(project,"resources/data/enemy_groups.json"),"utf8")) as Record<string,unknown>;
export const actionSchema=z.discriminatedUnion("kind",[
 z.object({kind:z.literal("skill"),actorUid:z.string().min(1).max(100),skillId:z.string().min(1).max(100),targetUids:z.array(z.string().min(1).max(100)).max(1)}).strict(),
 z.object({kind:z.literal("defend"),actorUid:z.string().min(1).max(100)}).strict(),
 z.object({kind:z.literal("end_turn"),actorUid:z.string().min(1).max(100)}).strict(),
]);
type Action=z.infer<typeof actionSchema>;
type PartyRow={char_id:string;level:number;xp:string;ascension:number;awakening:number;bond:number;dupes:number;skill_levels:Record<string,number>;equipment:unknown[]};
type Snapshot={ok:true;status:"active"|"victory"|"defeat";actorUid:string;sequence:number;round:number;units:unknown[];events:unknown[]};
type Rejected={ok:false;reason:string};
type WorkerResult=Snapshot|Rejected;
type Stored={seed:number;party:PartyRow[];collectionCount:number;actions:Action[];version:string;view:Snapshot};
type Row={id:string;group_id:string;status:string;state:Stored;rewards:unknown};
type Result={ok:true;battleId:string;view:Snapshot;rewards:unknown;replayed:boolean}|Rejected;
const MAX_ACTIONS=256;
// At most eight admitted transactions; the local pool has twelve connections.
const workerQueue=new StoryWorkerQueue(2,6,15000);
// Fingerprint actual authored inputs and the shared combat implementation.
export function fingerprint(){
 const hash=createHash("sha256");
 for(const dir of ["scripts/combat","resources/data"]){
  for(const name of readdirSync(join(project,dir)).sort()){
   if(!/\.(gd|json)$/.test(name))continue;
   hash.update(dir+"/"+name);hash.update(readFileSync(join(project,dir,name)));
  }
 }
 for(const name of ["tools/story_combat_worker.gd","scripts/gacha/character_upgrade_card.gd","scripts/core/components/game_roster_domain_component.gd"]){
  hash.update(name);hash.update(readFileSync(join(project,name)));
 }
 return hash.digest("hex");
}
type ReplayInput=Pick<Stored,"seed"|"party"|"collectionCount"|"actions"> & {groupId:string;definitions?:Record<string,unknown>};
// Experimental opt-in. A failed process never commits any combat outcome.
const batcher=new StoryWorkerBatcher<ReplayInput,WorkerResult>(async inputs=>{
 const exe=process.env.REVERIE_STORY_GODOT;if(!exe)throw new Error("story_worker_unconfigured");
 const dir=await mkdtemp(join(tmpdir(),"reverie-story-batch-"));
 try{
  const input=join(dir,"input.json");await writeFile(input,JSON.stringify(inputs),{mode:0o600});
  const env:NodeJS.ProcessEnv={REVERIE_E2E_DISABLE_LOCAL_SAVE:"1",REVERIE_STORY_WORKER:"1",APPDATA:dir,XDG_DATA_HOME:dir,XDG_CONFIG_HOME:dir,HOME:dir,USERPROFILE:dir,TEMP:dir,TMP:dir};
  for(const key of ["PATH","SystemRoot","WINDIR","LD_LIBRARY_PATH"])if(process.env[key])env[key]=process.env[key];
  const {stdout}=await run(exe,["--headless","--path",project,"res://tools/story_combat_worker.tscn","--","--batch",input],{env,timeout:10000,maxBuffer:4*1024*1024,windowsHide:true});
  const lines=stdout.split(/\r?\n/).filter(l=>l.startsWith("STORY_COMBAT_RESULT "));
  if(lines.length!==inputs.length)throw new Error("story_worker_invalid_output");
  return lines.map((line,i)=>{
   const result=JSON.parse(line.slice("STORY_COMBAT_RESULT ".length)) as WorkerResult;
   if(result.ok&&(!["active","victory","defeat"].includes(result.status)||result.sequence!==inputs[i]!.actions.length||!Array.isArray(result.units)||!Array.isArray(result.events)))throw new Error("story_worker_invalid_output");
   if(result.ok!==true&&(result.ok!==false||typeof result.reason!=="string"))throw new Error("story_worker_invalid_output");
   return result;
  });
 }finally{await rm(dir,{recursive:true,force:true});}
});
export async function replayStoryCombat(groupId:string,state:Pick<Stored,"seed"|"party"|"collectionCount"|"actions">):Promise<WorkerResult>{
 const exe=process.env.REVERIE_STORY_GODOT;
 if(!exe)return {ok:false,reason:"story_worker_unconfigured"};
 if(state.actions.length>MAX_ACTIONS)return {ok:false,reason:"action_limit"};
 const live=liveDefinitions();const definitions=Object.fromEntries(state.party.filter(p=>p.char_id.startsWith("livechar_")&&Object.hasOwn(live,p.char_id)).map(p=>[p.char_id,live[p.char_id]]));
 const trustedInput={groupId,...state,definitions};
 if(process.env.REVERIE_STORY_BATCH_WORKERS==="1")return await batcher.submit(trustedInput)??{ok:false,reason:"story_worker_busy"};
 const release=await workerQueue.acquire();
 if(!release)return {ok:false,reason:"story_worker_busy"};
 let dir:string|undefined;
 try{
  dir=await mkdtemp(join(tmpdir(),"reverie-story-worker-"));
  const input=join(dir,"input.json");
  await writeFile(input,JSON.stringify(trustedInput),{mode:0o600});
  // Do not forward DB credentials or auth tokens into the child process.
  const env:NodeJS.ProcessEnv={REVERIE_E2E_DISABLE_LOCAL_SAVE:"1",REVERIE_STORY_WORKER:"1",APPDATA:dir,XDG_DATA_HOME:dir,XDG_CONFIG_HOME:dir,HOME:dir,USERPROFILE:dir,TEMP:dir,TMP:dir};
  for(const key of ["PATH","SystemRoot","WINDIR","LD_LIBRARY_PATH"])if(process.env[key])env[key]=process.env[key];
  const {stdout}=await run(exe,["--headless","--path",project,"res://tools/story_combat_worker.tscn","--",input],{env,timeout:10000,maxBuffer:1024*1024,windowsHide:true});
  const lines=stdout.split(/\r?\n/).filter(l=>l.startsWith("STORY_COMBAT_RESULT "));
  if(lines.length!==1)return {ok:false,reason:"story_worker_invalid_output"};
  const result=JSON.parse(lines[0]!.slice("STORY_COMBAT_RESULT ".length)) as WorkerResult;
  if(result.ok&&(!["active","victory","defeat"].includes(result.status)||result.sequence!==state.actions.length||!Array.isArray(result.units)||!Array.isArray(result.events)))return {ok:false,reason:"story_worker_invalid_output"};
  return result;
 }catch{return {ok:false,reason:"story_worker_failed"};}
 finally{try{if(dir)await rm(dir,{recursive:true,force:true});}finally{release();}}
}
async function playerLock(db:PoolClient,id:string){
 return !!(await db.query("SELECT id FROM players WHERE id=$1 FOR UPDATE",[id])).rowCount;
}
const output=(row:Row,replayed:boolean):Result=>({ok:true,battleId:row.id,view:row.state.view,rewards:row.rewards,replayed});
/**
 * Internal battle service. Caller holds a DB transaction and has independently
 * verified world encounter eligibility. Not yet registered as a public route.
 */
export async function startStoryBattle(db:PoolClient,id:string,groupId:string):Promise<Result>{
 if(!Object.hasOwn(groups,groupId))return {ok:false,reason:"unknown_encounter"};
 if(!await playerLock(db,id))return {ok:false,reason:"player_not_found"};
 const active=(await db.query<Row>("SELECT id,group_id,status,state,rewards FROM story_battle_sessions WHERE player_id=$1 AND status='active' ORDER BY created_at DESC LIMIT 1 FOR UPDATE",[id])).rows[0];
 if(active)return active.group_id===groupId&&active.state.view?output(active,true):{ok:false,reason:"battle_in_progress"};
 if(isOneTimeStoryEncounter(groupId)&&(await db.query("SELECT 1 FROM story_battle_sessions WHERE player_id=$1 AND group_id=$2 AND status='victory' AND (settled_at IS NOT NULL OR group_id=$3) LIMIT 1",[id,groupId,TUTORIAL_GROUP])).rowCount)return {ok:false,reason:"already_claimed"};
 await db.query("INSERT INTO owned_characters(player_id,char_id) SELECT $1,unnest($2::text[]) ON CONFLICT DO NOTHING",[id,STARTER_PARTY]);
 const roster=(await db.query<PartyRow>("SELECT char_id,level,xp::text,ascension,awakening,bond,dupes,skill_levels FROM owned_characters WHERE player_id=$1 AND NOT(char_id=ANY($2::text[])) ORDER BY char_id FOR UPDATE",[id,retiredPlayableIds])).rows;
 const selected=(await db.query<{char_id:string}>("SELECT oc.char_id FROM party_members pm JOIN owned_characters oc ON oc.id=pm.character_id AND oc.player_id=pm.player_id WHERE pm.player_id=$1 AND NOT(oc.char_id=ANY($2::text[])) ORDER BY pm.slot",[id,retiredPlayableIds])).rows.map(r=>r.char_id);
 const ids=villageProgressionEnabled()&&villageGroups.includes(groupId)?villageParty(groupId):groupId==="gerald_boss_encounter"||groupId==="tutorial_fairy_spar"?["kael"]:selected.length?selected:STARTER_PARTY;
 const gear=(await db.query("SELECT oc.char_id,e.slot,e.item_id,e.enhancement_level,e.reroll_stat,e.reroll_value FROM character_equipment e JOIN owned_characters oc ON oc.id=e.character_id AND oc.player_id=e.player_id WHERE e.player_id=$1",[id])).rows;
 const party=ids.map(char_id=>{const row=roster.find(r=>r.char_id===char_id);return row?{...row,equipment:gear.filter(e=>e.char_id===char_id)}:null;});
 if(party.some(r=>r===null)||party.length<1||party.length>4)return {ok:false,reason:"invalid_party"};
 const base={seed:randomInt(1,2147483647),party:party as PartyRow[],collectionCount:roster.length,actions:[] as Action[]};
 const version=fingerprint();
 const view=await replayStoryCombat(groupId,base);
 if(version!==fingerprint())return {ok:false,reason:"battle_content_changed"};
 if(!view.ok)return view;
 if(view.status!=="active")return {ok:false,reason:"invalid_initial_battle"};
 const state:Stored={...base,version,view};
 const row=(await db.query<Row>("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,state) VALUES($1,$2,$3,$4) RETURNING id,group_id,status,state,rewards",[id,groupId,ids,JSON.stringify(state)])).rows[0]!;
 return output(row,false);
}
export async function actStoryBattle(db:PoolClient,id:string,battleId:string,sequence:number,raw:unknown):Promise<Result>{
 const parsed=actionSchema.safeParse(raw);
 if(!parsed.success||!Number.isSafeInteger(sequence)||sequence<1||sequence>MAX_ACTIONS)return {ok:false,reason:"invalid_action"};
 if(!await playerLock(db,id))return {ok:false,reason:"player_not_found"};
 const row=(await db.query<Row>("SELECT id,group_id,status,state,rewards FROM story_battle_sessions WHERE id=$1 AND player_id=$2 FOR UPDATE",[battleId,id])).rows[0];
 if(!row||!row.state.view)return {ok:false,reason:"battle_not_found"};
 const state=row.state;
 if(row.status!=="abandoned"&&sequence===state.actions.length&&JSON.stringify(actionSchema.parse(state.actions[sequence-1]))===JSON.stringify(parsed.data))return output(row,true);
 if(row.status!=="active")return {ok:false,reason:"battle_finished"};
 if(sequence!==state.actions.length+1)return {ok:false,reason:"invalid_sequence"};
 if(state.version!==fingerprint())return {ok:false,reason:"battle_content_changed"};
 if(parsed.data.actorUid!==state.view.actorUid)return {ok:false,reason:"wrong_actor"};
 const next={...state,actions:[...state.actions,parsed.data]};
 const view=await replayStoryCombat(row.group_id,{seed:next.seed,party:next.party,collectionCount:next.collectionCount,actions:next.actions});
 if(!view.ok)return view;
 if(state.version!==fingerprint())return {ok:false,reason:"battle_content_changed"};
 next.view=view;
 await db.query("UPDATE story_battle_sessions SET state=$2,status=$3,finished_at=CASE WHEN $3='active' THEN NULL ELSE now() END WHERE id=$1",[battleId,JSON.stringify(next),view.status]);
 if(view.status==="victory"&&row.group_id!=="tutorial_fairy_spar"){
  const settlement=await settleStoryVictory(db,id,battleId);
  if(!settlement.ok)throw new Error("story_settlement_failed:"+settlement.reason); // caller rolls back whole final action
  row.rewards=settlement.rewards;
 }
 row.state=next;row.status=view.status;
 return output(row,false);
}

// Recovery reads the persisted view; neither seed nor trusted roster leaves
// this internal service. Authentication and encounter routing are API concerns.
export async function resumeStoryBattle(db:PoolClient,id:string,battleId:string):Promise<Result>{
 if(!await playerLock(db,id))return {ok:false,reason:"player_not_found"};
 const row=(await db.query<Row>("SELECT id,group_id,status,state,rewards FROM story_battle_sessions WHERE id=$1 AND player_id=$2",[battleId,id])).rows[0];
 if(!row||!row.state.view)return {ok:false,reason:"battle_not_found"};
 if(row.status==="abandoned")return {ok:false,reason:"battle_abandoned"};
 return output(row,true);
}
export async function abandonStoryBattle(db:PoolClient,id:string,battleId:string):Promise<{ok:true;status:"abandoned";replayed:boolean}|Rejected>{
 if(!await playerLock(db,id))return {ok:false,reason:"player_not_found"};
 const row=(await db.query<Row>("SELECT id,group_id,status,state,rewards FROM story_battle_sessions WHERE id=$1 AND player_id=$2 FOR UPDATE",[battleId,id])).rows[0];
 if(!row||!row.state.view)return {ok:false,reason:"battle_not_found"};
 if(row.status==="abandoned")return {ok:true,status:"abandoned",replayed:true};
 if(row.status!=="active")return {ok:false,reason:"battle_finished"};
 await db.query("UPDATE story_battle_sessions SET status='abandoned',finished_at=now() WHERE id=$1",[battleId]);
 return {ok:true,status:"abandoned",replayed:false};
}
