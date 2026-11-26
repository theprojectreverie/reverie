import assert from 'node:assert/strict';
import {featuredEncounter,encounterCredit,rows,activityRows,monthlyTiming} from '../src/routes/daily-quests.ts';
const tags=['gardens','gate','willow','cassien','revienna','willow',null];
const dates=['2026-11-23','2026-11-24','2026-11-25','2026-11-26','2026-11-27','2026-11-28','2026-11-29'];
for(let i=0;i<dates.length;i++){
 const date=dates[i],tag=tags[i];
 assert.equal(featuredEncounter(date)?.tag??null,tag);
 const base={date,victories:3,shared_victories:0,claimed:[],encounter_credits:[]};
 assert.equal(rows(base)[2].can_claim,false);
 if(tag)assert.equal(rows({...base,encounter_credits:[tag]})[2].can_claim,true);
 assert.equal(rows({...base,shared_victories:1})[2].can_claim,true);
 assert.equal(rows({...base,encounter_credits:['unrelated']})[2].can_claim,false);
 assert.equal(rows({...base,shared_victories:1,claimed:['shared']})[2].can_claim,false);
 assert.equal(rows(base).reduce((a,r)=>a+r.gold,0),1200);
 assert.equal(rows(base).reduce((a,r)=>a+r.crystals,0),140);
}
assert.equal(encounterCredit('six_zone_forsaken_ruins','cassien_encounter'),'cassien');
assert.equal(encounterCredit('six_zone_ruined_tower','revienna_encounter'),'revienna');
assert.equal(encounterCredit('six_zone_willow_fields','cassien_encounter'),null);
assert.equal(encounterCredit('six_zone_royal_gate','royal_gate_patrol_1'),'gate');
assert.equal(encounterCredit('six_zone_royal_gardens','rose_slime_garden_1'),'gardens');
console.log('PASS seven UTC rotation days, alternatives, unmatched encounters, no double claim, fixed reward budget');

const fresh={date:'2026-11-26',victories:3,shared_victories:1,claimed:[],encounter_credits:[]};
assert.ok(activityRows(fresh).every(x=>!x.can_claim));
assert.equal(activityRows({...fresh,claimed:['checkin']})[0].can_claim,true);
assert.equal(activityRows({...fresh,claimed:['checkin','activity_1','bonus']})[1].can_claim,false);
assert.equal(activityRows({...fresh,claimed:['checkin','victories','shared']})[1].can_claim,true);
assert.equal(activityRows({...fresh,claimed:['checkin','victories','shared','activity_3']})[1].can_claim,false);
console.log('PASS activity thresholds, no self-counting and duplicate prevention');

for(const [date,next] of [['2026-01-01','2026-02-01'],['2026-02-01','2026-03-01'],['2028-02-01','2028-03-01'],['2026-04-01','2026-05-01'],['2026-12-01','2027-01-01']])assert.equal(monthlyTiming(date).resetAt,Date.parse(next+'T00:00:00Z'));
console.log('PASS monthly reset for 28, 29, 30, 31-day months and year rollover');
