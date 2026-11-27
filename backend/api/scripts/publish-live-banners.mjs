// Operator-only local publishing command; no HTTP admin write endpoint.
import {readFileSync,writeFileSync,renameSync,mkdirSync,existsSync,unlinkSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {parseLiveManifest,bannerManifestPath} from '../src/world/live-banners.ts';
import {withPublishLock,atomicDocument,readArtwork} from "../src/world/live-content-store.ts";
const [source,flag]=process.argv.slice(2);if(!source||!['--publish','--preview'].includes(flag))throw Error('Usage: node --import tsx scripts/publish-live-banners.mjs <draft.json> --preview|--publish');
const target=bannerManifestPath();
const rows=parseLiveManifest(JSON.parse(readFileSync(source,'utf8')));
const run=()=>{const prior=existsSync(target)?parseLiveManifest(JSON.parse(readFileSync(target,'utf8'))):[];
for(const old of prior){const next=rows.find(r=>r.id===old.id);if(!next||JSON.stringify(next)!==JSON.stringify(old))throw Error('Existing banner IDs and schedules are immutable: '+old.id);}
for(const row of rows)if(row.artwork)readArtwork(row.artwork);
console.log(JSON.stringify({target,count:rows.length,newEntries:rows.filter(r=>!prior.some(p=>p.id===r.id)).map(r=>({id:r.id,featured:r.featured,startsAt:r.startsAt,endsAt:r.endsAt}))},null,2));
if(flag==='--publish'){atomicDocument(target,{schema:1,banners:rows});console.log('PUBLISHED');}};
if(flag==='--publish')withPublishLock(target,run);else run();
