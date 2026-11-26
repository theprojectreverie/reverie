import test from "node:test";
import assert from "node:assert/strict";
import {findSequenceWindow,verifiedWindowSupersession} from "../scripts/cluster-load-probe.mjs";
test("find exact received sequence window without crossing gaps",()=>{
 const ranges=[[10,20],[22,25],[26,40]];
 assert.deepEqual(findSequenceWindow(ranges,20),[10,20]);
 assert.equal(findSequenceWindow(ranges,21),null);
 assert.deepEqual(findSequenceWindow(ranges,26),[26,40]);
 assert.equal(findSequenceWindow(ranges,41),null);
});
test("supersession requires a later sample in the exact received window",()=>{
 const missing={round:14,sequence:20};
 const later={round:15,sequence:25};
 assert.equal(verifiedWindowSupersession([10,30],missing,[missing,later],(sample,end)=>sample===later&&end===30),true);
 assert.equal(verifiedWindowSupersession([10,24],missing,[missing,later],()=>true),false);
 assert.equal(verifiedWindowSupersession([21,30],missing,[missing,later],()=>true),false);
 assert.equal(verifiedWindowSupersession(null,missing,[later],()=>true),false);
 assert.equal(verifiedWindowSupersession([10,30],undefined,[later],()=>true),false);
 assert.equal(verifiedWindowSupersession([10,30],missing,[missing,later],()=>false),false);
 assert.equal(verifiedWindowSupersession([10,30],missing,[{round:13,sequence:25}],()=>true),false);
});
