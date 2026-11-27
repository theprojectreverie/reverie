import test from "node:test";
import assert from "node:assert/strict";
import {buildBannerCatalog,parseLiveManifest} from "../src/world/live-banners.js";
import {banners,rollBanner,emptyPity} from "../src/world/summon.js";
const row={id:"live_cassien_test",name:"Test Oath",subtitle:"Test event",template:"crimson_oath",featured:"cassien_legendary",startsAt:"2026-11-27T00:00:00Z",endsAt:"2026-11-28T00:00:00Z"};
const at=Date.parse(row.startsAt);
test("scheduled live banners activate at exact UTC boundaries, preserve base rules and revision",()=>{
 const entries=parseLiveManifest({schema:1,banners:[row]});assert.equal(buildBannerCatalog(entries,at-1)[row.id],undefined);
 const active=buildBannerCatalog(entries,at)[row.id]!;assert.deepEqual(active.featured,["cassien_mythic"]);assert.deepEqual(active.pool.mythic,active.featured);assert.deepEqual(active.rates,banners.crimson_oath!.rates);assert.deepEqual(active.cost,banners.crimson_oath!.cost);
 assert.equal(active.revision,buildBannerCatalog(entries,at+1)[row.id]!.revision);assert.notEqual(active.revision,buildBannerCatalog([{...row,name:"Changed"}],at)[row.id]!.revision);assert.equal(buildBannerCatalog(entries,Date.parse(row.endsAt))[row.id],undefined);
 assert.equal(rollBanner(active,emptyPity(),10,()=>0,90).results[9]!.character_id,"cassien_mythic");
});
test("rejects unsupported content, duplicate IDs, invalid dates, economics overrides and overlapping tabs",()=>{
 for(const rows of [[{...row,featured:"missing"}],[{...row,id:"crimson_oath"}],[row,row],[{...row,endsAt:row.startsAt}],[{...row,rates:{common:1}}],[row,{...row,id:"live_two"},{...row,id:"live_three"}]])assert.throws(()=>parseLiveManifest({schema:1,banners:rows}));
});

import {controlSchema,nextHistory,currentState} from "../src/world/live-content-revisions.js";
const owner="11111111-1111-4111-8111-111111111111";
const economics={ratesBps:{common:6000,rare:2500,epic:1000,legendary:450,mythic:50},featuredBps:6000,single:100,ten:900};
test("cancel, edit and rollback are append-only, enforce CAS and invalidate stale catalog revisions",()=>{
 const original=buildBannerCatalog([row],at)[row.id]!;
 const edit=controlSchema.parse({action:"economics",expected:0,reason:"Seasonal discount",economics});let history=nextHistory([],edit,owner,"banner");
 const updated=buildBannerCatalog([{...row,history}],at)[row.id]!;assert.equal(updated.cost.ten,900);assert.equal(updated.rates.legendary,.045);assert.notEqual(updated.revision,original.revision);assert.equal(updated.hard_pity,original.hard_pity);
 assert.throws(()=>nextHistory(history,edit,owner,"banner"),/revision_conflict/);
 history=nextHistory(history,{action:"cancel",expected:1,reason:"Emergency pause"},owner,"banner");assert.equal(buildBannerCatalog([{...row,history}],at)[row.id],undefined);
 history=nextHistory(history,{action:"rollback",expected:2,target:0,reason:"Restore original rules"},owner,"banner");const restored=buildBannerCatalog([{...row,history}],at)[row.id]!;assert.deepEqual(restored.cost,original.cost);assert.deepEqual(restored.rates,original.rates);assert.notEqual(restored.revision,original.revision);assert.equal(history.length,3);assert.equal(currentState(history).cancelled,false);
 assert.throws(()=>nextHistory([],edit,owner,"event"),/banner_economics_only/);
 for(const invalid of [{...economics,ten:1001},{...economics,ratesBps:{...economics.ratesBps,common:5000}},{...economics,single:0}])assert.equal(controlSchema.safeParse({...edit,economics:invalid}).success,false);
});
