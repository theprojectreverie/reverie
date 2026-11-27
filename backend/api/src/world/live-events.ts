import {revisionHistory,currentState,nextHistory,type Control} from "./live-content-revisions.js";
import {z} from "zod";
import {join} from "node:path";
import {contentDirectory,readDocument,withPublishLock,atomicDocument} from "./live-content-store.js";
const reward=z.object({currency:z.enum(["gold","crystals"]),amount:z.number().int().positive()}).strict().refine(r=>r.amount<=(r.currency==="gold"?10000:500),"reward_limit");
// Repeatable encounters already supported by the authoritative story battle service.
export const seasonalEncounterIds=["rose_slime_garden_1","rose_slime_garden_2","rose_slime_garden_3","rose_slime_garden_4","rose_slime_garden_5","rose_slime_garden_6","crownling_garden_1","crownling_garden_2","crownling_garden_3","royal_gate_patrol_1","royal_gate_patrol_2"] as const;
const objective=z.object({type:z.literal("story_victories"),groups:z.array(z.enum(seasonalEncounterIds)).min(1).max(11).refine(g=>new Set(g).size===g.length),required:z.number().int().min(1).max(30)}).strict();
export const eventShopItems=["moonpetal","glade_sap","dew_of_awakening","hollow_heart","gothic_shard","blight_resin","royal_seal"] as const;
const shopOffer=z.object({item:z.enum(eventShopItems),quantity:z.number().int().min(1).max(10),currency:z.enum(["gold","crystals"]),price:z.number().int().min(1)}).strict().refine(o=>o.price<=(o.currency==="gold"?10000:500),"shop_price_limit");
const draft=z.object({id:z.string().regex(/^event_[a-z0-9_]{1,60}$/),name:z.string().trim().min(1).max(60),description:z.string().trim().max(240),startsAt:z.string().datetime(),endsAt:z.string().datetime(),objective:objective.optional(),shop:shopOffer.optional(),reward}).strict();
const entry=draft.extend({publishedBy:z.string().uuid(),publishedAt:z.string().datetime(),history:revisionHistory.optional()});
export type LiveEvent=z.infer<typeof entry>;
const manifest=z.object({schema:z.literal(1),events:z.array(entry).max(500)}).strict();
const path=()=>join(contentDirectory(),"events.json");
function validateSchedule(rows:LiveEvent[]){const ids=new Set<string>();const edges:number[][]=[];for(const r of rows){if(ids.has(r.id)||Date.parse(r.startsAt)>=Date.parse(r.endsAt))throw Error("invalid_event_schedule");ids.add(r.id);if(r.history?.some(h=>h.state.economics))throw Error("event_economics_forbidden");if(!currentState(r.history).cancelled)edges.push([Date.parse(r.startsAt),1],[Date.parse(r.endsAt),-1]);}edges.sort((a,b)=>a[0]!-b[0]!||a[1]!-b[1]!);let concurrent=0;for(const edge of edges){concurrent+=edge[1]!;if(concurrent>3)throw Error("too_many_active_events");}}

export function readEvents():LiveEvent[]{const raw=readDocument(path());if(raw===undefined)return [];const rows=manifest.parse(raw).events;validateSchedule(rows);return rows;}
export function appendEvent(value:unknown,actor:string,publish:boolean){const clean=draft.parse(value);if(Date.parse(clean.startsAt)>=Date.parse(clean.endsAt))throw Error("invalid_event_schedule");const run=()=>{const rows=readEvents();if(rows.some(r=>r.id===clean.id))throw Error("event_id_exists");if(rows.length>=500)throw Error("event_limit");const row={...clean,publishedBy:actor,publishedAt:new Date().toISOString()};validateSchedule([...rows,row]);if(publish)atomicDocument(path(),{schema:1,events:[...rows,row]});return row;};return publish?withPublishLock(path(),run):run();}
export function activeEvents(now=Date.now()){return readEvents().filter(r=>!currentState(r.history).cancelled&&Date.parse(r.startsAt)<=now&&now<Date.parse(r.endsAt)).map(({publishedAt,publishedBy,history,...r})=>r);}

export function changeEvent(id:string,control:Control,actor:string,publish:boolean){const run=()=>{const rows=readEvents();const index=rows.findIndex(r=>r.id===id);if(index<0)throw Error("content_not_found");const row=rows[index]!;if(Date.parse(row.endsAt)<=Date.now())throw Error("content_expired");const next={...row,history:nextHistory(row.history,control,actor,"event")};rows[index]=next;validateSchedule(rows);if(publish)atomicDocument(path(),{schema:1,events:rows});return next;};return publish?withPublishLock(path(),run):run();}

type ProgressDB={query:(sql:string,values?:unknown[])=>Promise<{rows:Array<Record<string,unknown>>}>};
export async function eventProgress(db:ProgressDB,playerId:string,event:Pick<LiveEvent,"objective"|"startsAt"|"endsAt">){
 if(!event.objective)return {progress:1,required:1,eligible:true};
 const {groups,required}=event.objective;
 const q=await db.query(`SELECT LEAST(count(*),$5::bigint)::int AS progress FROM story_battle_sessions WHERE player_id=$1 AND group_id=ANY($2::text[]) AND status='victory' AND created_at >= $3::timestamptz AND finished_at >= $3::timestamptz AND finished_at < $4::timestamptz AND settled_at IS NOT NULL AND settled_at < $4::timestamptz AND state->'view'->>'status'='victory' AND jsonb_array_length(CASE WHEN jsonb_typeof(state->'actions')='array' THEN state->'actions' ELSE '[]'::jsonb END)>0`,[playerId,groups,event.startsAt,event.endsAt,required]);
 const progress=Number(q.rows[0]?.progress??0);return {progress,required,eligible:progress>=required};
}
