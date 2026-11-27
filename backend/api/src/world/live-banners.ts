import {resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {contentDirectory,readDocument,withPublishLock,atomicDocument,readArtwork} from "./live-content-store.js";
import {createHash} from "node:crypto";
import {z} from "zod";
import {liveCharacterPack} from "./live-character-packs.js";
import {revisionHistory,currentState,nextHistory,type Control} from "./live-content-revisions.js";
import {banners,contentHash,type Banner} from "./summon.js";
const entry=z.object({id:z.string().regex(/^live_[a-z0-9_]{1,65}$/),name:z.string().trim().min(1).max(60),subtitle:z.string().trim().max(120),template:z.string().min(1),featured:z.string().min(1),startsAt:z.string().datetime(),endsAt:z.string().datetime(),artwork:z.string().regex(/^[a-f0-9]{64}$/).optional(),publishedBy:z.string().uuid().optional(),publishedAt:z.string().datetime().optional(),history:revisionHistory.optional()}).strict();
const manifest=z.object({schema:z.literal(1),banners:z.array(entry).max(500)}).strict();
export type LiveEntry=z.infer<typeof entry>;
export type CatalogBanner=Banner & {name?:string;subtitle?:string;revision:string;startsAt?:string;endsAt?:string;artwork?:string};
export function parseLiveManifest(value:unknown):LiveEntry[]{
 const rows=manifest.parse(value).banners;const ids=new Set<string>();
 for(const row of rows){const template=Object.hasOwn(banners,row.template)?banners[row.template]:undefined;
  if(ids.has(row.id)||!template||(!template.pool.legendary.includes(row.featured)&&!(liveCharacterPack(row.featured)?.characterId===row.featured&&liveCharacterPack(row.featured)?.template&&template.pool.legendary.includes(liveCharacterPack(row.featured)!.template)))||(!template?.mythic_fusion?.[row.featured]?.target&&!liveCharacterPack(row.featured)?.mythic)||Date.parse(row.startsAt)>=Date.parse(row.endsAt))throw Error("invalid_live_banner");ids.add(row.id);
 }
 // Bound simultaneous tabs and response size; historical rows may remain for audits.
 const edges=rows.filter(r=>!currentState(r.history).cancelled).flatMap(r=>[[Date.parse(r.startsAt),1],[Date.parse(r.endsAt),-1]]).sort((a,b)=>a[0]!-b[0]!||a[1]!-b[1]!);
 let concurrent=0;for(const [,delta] of edges){concurrent+=delta!;if(concurrent>2)throw Error("too_many_active_live_banners");}
 return rows;
}
export const defaultLiveManifest=new URL("../../live-content/banners.json",import.meta.url);
export function bannerManifestPath(){return resolve(process.env.REVERIE_LIVE_BANNERS_FILE||(process.env.REVERIE_LIVE_CONTENT_DIR?resolve(contentDirectory(),"banners.json"):fileURLToPath(defaultLiveManifest)));}
export function runtimeEntries():LiveEntry[]{const raw=readDocument(bannerManifestPath());return raw===undefined?[]:parseLiveManifest(raw);}
export function appendLiveBanner(value:unknown,actor:string,publish:boolean){
 const clean=entry.omit({publishedBy:true,publishedAt:true,history:true}).parse(value);if(clean.artwork)readArtwork(clean.artwork);
 const path=bannerManifestPath();const run=()=>{const old=runtimeEntries();if(old.some(r=>r.id===clean.id))throw Error("banner_id_exists");const row={...clean,publishedBy:actor,publishedAt:new Date().toISOString()};const rows=parseLiveManifest({schema:1,banners:[...old,row]});if(publish)atomicDocument(path,{schema:1,banners:rows});return row;};return publish?withPublishLock(path,run):run();
}
const revision=(value:unknown)=>createHash("sha256").update(contentHash).update(JSON.stringify(value)).digest("hex");
export function buildBannerCatalog(rows:LiveEntry[],now=Date.now()):Record<string,CatalogBanner>{
 const result:Record<string,CatalogBanner>=Object.create(null);
 for(const [id,banner] of Object.entries(banners))if(!banner.retired)result[id]={...banner,revision:revision([id,banner])};
 for(const row of rows){const state=currentState(row.history);if(state.cancelled||now<Date.parse(row.startsAt)||now>=Date.parse(row.endsAt))continue;
  const base=banners[row.template]!;const p=liveCharacterPack(row.featured);const template:Banner=p&&p.characterId===row.featured?{...base,pool:{...base.pool,legendary:[...base.pool.legendary,p.characterId],mythic:[...base.pool.mythic,p.mythic!],rare:[...base.pool.rare,p.rare!],epic:[...base.pool.epic,p.epic!]},upgrade_cards:{...base.upgrade_cards,...p.upgrade_cards},mythic_fusion:{...base.mythic_fusion,...p.mythic_fusion},mythic_ascension:{...base.mythic_ascension,...p.mythic_ascension}}:base;const mythic=template.mythic_fusion?.[row.featured]?.target; if(!mythic)throw Error("invalid_live_mythic_feature");const e=state.economics;result[row.id]={...template,pool:{...template.pool,mythic:[mythic]},retired:false,...(e?{rates:Object.fromEntries(Object.entries(e.ratesBps).map(([k,v])=>[k,v/10000])) as Banner["rates"],featured_rate:e.featuredBps/10000,cost:{currency:"crystals",single:e.single,ten:e.ten}}:{}),name:row.name,subtitle:row.subtitle,featured:[mythic],featured_rate:1,startsAt:row.startsAt,endsAt:row.endsAt,...(row.artwork?{artwork:row.artwork}:{}),revision:revision([row,template])};
 }return result;
}
export function currentBannerCatalog(now=Date.now()):Record<string,CatalogBanner>{return buildBannerCatalog(runtimeEntries(),now);}
export function historicalBannerName(id:string):string|undefined{
 const base=Object.hasOwn(banners,id)?banners[id] as Banner & {name?:string}:undefined;
 if(base)return base.name;
 try{return runtimeEntries().find(row=>row.id===id)?.name;}catch{return undefined;}
}

export function changeBanner(id:string,control:Control,actor:string,publish:boolean){const path=bannerManifestPath();const run=()=>{const rows=runtimeEntries();const index=rows.findIndex(r=>r.id===id);if(index<0)throw Error("content_not_found");const row=rows[index]!;if(Date.parse(row.endsAt)<=Date.now())throw Error("content_expired");const next={...row,history:nextHistory(row.history,control,actor,"banner")};rows[index]=next;parseLiveManifest({schema:1,banners:rows});if(publish)atomicDocument(path,{schema:1,banners:rows});return next;};return publish?withPublishLock(path,run):run();}
