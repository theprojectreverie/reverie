import assert from 'node:assert/strict';
import {setTimeout as delay} from 'node:timers/promises';
import {startSeasonFinalizer,finalizeDueSeasons} from '../src/world/season-rewards.ts';
import {pool} from '../src/db.ts';
import {config} from '../src/config.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
// The real due-query is safe to run before the first production reward season closes.
try {
 const dbClock=(await pool.query("SELECT clock_timestamp() AS now")).rows[0].now;
 if(dbClock<new Date("2027-01-01T00:05:00Z"))assert.deepEqual(await finalizeDueSeasons([]),[]);
 let runs=0,errors=0,concurrent=0,peak=0,finished=[];
 let release;
 const gate=new Promise(resolve=>release=resolve);
 const stop=startSeasonFinalizer(async()=>{
  runs++;concurrent++;peak=Math.max(peak,concurrent);
  try{if(runs===1)throw Error('transient database outage');await gate;return ['2001-01-01'];}
  finally{concurrent--;}
 },seasons=>finished.push(...seasons),()=>errors++,5);
 try{
  for(let i=0;i<100&&runs<2;i++)await delay(5);
  assert.equal(runs,2);assert.equal(errors,1);
  await delay(35);assert.equal(runs,2);assert.equal(peak,1);
  let stopped=false;const pending=stop().then(()=>stopped=true);
  await delay(10);assert.equal(stopped,false);
  release();await pending;assert.equal(stopped,true);assert.deepEqual(finished,['2001-01-01']);
  await delay(20);assert.equal(runs,2);
 }finally{release();await stop();}
 console.log('PASS scheduler retries transient failures, avoids overlapping runs, drains on shutdown, and actual UTC due-season query');
}finally{await pool.end();}
