import {z} from "zod";
import {join} from "node:path";
import {readFileSync} from "node:fs";
import {createHash} from "node:crypto";
import {characterDrafts,animationSlots,bundledCharacterDefinitions} from "./live-character-drafts.js";
import {contentDirectory,readDocument,withPublishLock,atomicDocument,readArtwork} from "./live-content-store.js";
const publication=z.object({draftId:z.string().regex(/^draft_[a-z0-9_]{1,60}$/),characterId:z.string().regex(/^[a-z0-9_]{1,64}$/),revision:z.string().regex(/^[a-f0-9]{64}$/),actor:z.string().uuid(),at:z.string().datetime(),snapshot:z.record(z.string(),z.unknown()).optional()}).strict();
const manifest=z.object({schema:z.literal(1),packs:z.array(publication).max(20)}).strict();
const path=()=>join(contentDirectory(),"character-packs.json");
const baseBanners=JSON.parse(readFileSync(new URL("../../../../resources/data/banners.json",import.meta.url),"utf8")) as Record<string,{mythic_fusion?:Record<string,{target:string}>}>;
function buildPair(d:ReturnType<typeof characterDrafts>[number]){
 if(d.characterId.length>52||d.characterId.endsWith("_mythic")||!d.portrait)throw Error("new_character_identity_or_portrait_required");
 const source=bundledCharacterDefinitions[d.template];const mythicTemplate=Object.values(baseBanners).map(b=>b.mythic_fusion?.[d.template]?.target).find(Boolean);const mythic=mythicTemplate?bundledCharacterDefinitions[mythicTemplate]:undefined;
 if(!source||source.rarity!=="legendary"||!mythic||mythic.rarity!=="mythic"||source.gacha_enabled===false||mythic.gacha_enabled===false)throw Error("legendary_mythic_template_pair_required");
 const id=d.characterId,mid=id+"_mythic",rare="upgrade_"+id+"_rare",epic="upgrade_"+id+"_epic",progress="legendary_progress_"+id,ascension="mythic_ascension_"+mid;
 const clone=(t:typeof source,name:string,title:string)=>{const {assets,variant_of,...rules}=t;return {...rules,name,title,lore:d.lore,gacha_enabled:true};};
 return {definitions:{[id]:clone(source,d.name,d.title),[mid]:clone(mythic,d.name+" (Mythic Aspect)",d.title+" · Mythic Aspect")},items:{[rare]:{name:d.name+" Rare Card",category:"material",rarity:"rare"},[epic]:{name:d.name+" Epic Card",category:"material",rarity:"epic"},[progress]:{name:d.name+" Mythic Progress",category:"material",rarity:"legendary"},[ascension]:{name:d.name+" Mythic Ascension Progress",category:"material",rarity:"mythic"}},upgrade_cards:{[rare]:{name:d.name,rarity:"rare" as const,portrait_id:id,target:epic,cost:20},[epic]:{name:d.name,rarity:"epic" as const,portrait_id:id,target:id,cost:10}},mythic_fusion:{[id]:{target:mid,cost:7,item:progress}},mythic_ascension:{[mid]:{cost:7,item:ascension}},rare,epic,mythic:mid};
}
function records(){const raw=readDocument(path());return raw===undefined?[]:manifest.parse(raw).packs;}
function makePack(d:ReturnType<typeof characterDrafts>[number],verify=true){
 if(d.animations.length!==animationSlots.length||!animationSlots.every(slot=>d.animations.some(a=>a.slot===slot)))throw Error("complete_animation_pack_required");
 if(d.animations.reduce((n,a)=>n+a.columns*a.rows*128*128,0)>3000000)throw Error("pack_pixel_budget_exceeded");
 if(verify)for(const a of d.animations){const png=readArtwork(a.artwork);if(png.readUInt32BE(16)!==a.columns*128||png.readUInt32BE(20)!==a.rows*128||png[25]!==6)throw Error("atlas_requires_exact_rgba_128_grid");}
 if(verify&&d.portrait)readArtwork(d.portrait);
 const body={characterId:d.characterId,template:d.template,mode:d.mode,animations:d.animations,...(d.heightCm?{heightCm:d.heightCm}:{}),...(d.portrait?{portrait:d.portrait}:{}),...(d.mode==="new_character"?buildPair(d):{})};
 return {...body,revision:createHash("sha256").update(JSON.stringify(body)).digest("hex")};
}
export function publishCharacterPack(draftId:string,actor:string,publish:boolean,expectedRevision?:string){const run=()=>{const d=characterDrafts().find(r=>r.id===draftId);if(!d)throw Error("draft_not_found");if(d.mode==="new_character"&&process.env.REVERIE_LIVE_NEW_CHARACTERS_PILOT!=="1")throw Error("new_character_runtime_not_enabled");const pack=makePack(d),rows=records();const prior=rows.filter(r=>r.characterId===d.characterId).at(-1);if(prior){if(!expectedRevision||expectedRevision!==prior.revision||prior.revision===pack.revision)throw Error("character_pack_already_published");const old=publishedCharacterPacks().find(p=>p.characterId===d.characterId)!;if(old.mode!==pack.mode||old.template!==pack.template||JSON.stringify(old.definitions??{})!==JSON.stringify(pack.definitions??{}))throw Error("published_character_definition_immutable");}else if(expectedRevision)throw Error("character_pack_revision_conflict");if(!prior&&new Set(rows.map(r=>r.characterId)).size>=4)throw Error("active_pack_limit");if(rows.length>=20)throw Error("pack_history_limit");const row={draftId,characterId:d.characterId,revision:pack.revision,actor,at:new Date().toISOString(),snapshot:pack};if(publish)atomicDocument(path(),{schema:1,packs:[...rows,row]});return {published:publish,pack};};return publish?withPublishLock(path(),run):run();}
export function publishedCharacterPacks(){const history=records();if(!history.length)return [];const rows=[...new Map(history.map(r=>[r.characterId,r])).values()];const drafts=characterDrafts();return rows.map(r=>{const d=drafts.find(x=>x.id===r.draftId);if(!d||d.characterId!==r.characterId)throw Error("character_pack_missing");const pack=r.snapshot as ReturnType<typeof makePack>|undefined??makePack(d,false);const {revision,...body}=pack;if(pack.characterId!==r.characterId||createHash("sha256").update(JSON.stringify(body)).digest("hex")!==r.revision||pack.revision!==r.revision)throw Error("character_pack_revision_mismatch");return pack;});}
export function publishedCharacterArtwork(hash:string){return publishedCharacterPacks().some(p=>p.portrait===hash||p.animations.some(a=>a.artwork===hash));}

export function liveCharacterPack(id:string){if(!id.startsWith("livechar_"))return undefined;return publishedCharacterPacks().find(p=>p.mode==="new_character"&&(p.characterId===id||p.mythic===id));}
export function liveDefinitions(){return Object.assign(Object.create(null),...publishedCharacterPacks().map(p=>p.definitions??{})) as Record<string,{name:string;rarity:string;gacha_enabled?:boolean;skills?:string[];ultimate?:string;[key:string]:unknown}>;}
export function liveDefinition(id:string){return id.startsWith("livechar_")?liveDefinitions()[id]:undefined;}
export function liveCard(id:string){if(!id.startsWith("upgrade_livechar_"))return undefined;return publishedCharacterPacks().map(p=>p.upgrade_cards?.[id]).find(Boolean);}
export function liveMythicRecipe(id:string){return liveCharacterPack(id)?.mythic_fusion?.[id];}
export function liveAscensionRecipe(id:string){return liveCharacterPack(id)?.mythic_ascension?.[id];}
