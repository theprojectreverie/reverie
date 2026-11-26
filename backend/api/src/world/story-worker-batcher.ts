/** Coalesce short bursts into isolated bounded worker processes. */
export class StoryWorkerBatcher<I,O>{
 private pending:Array<{input:I;resolve:(value:O|null)=>void;timer:ReturnType<typeof setTimeout>}>=[];
 private active=0;
 private outstanding=0;
 private flushTimer:ReturnType<typeof setTimeout>|undefined;
 constructor(private readonly execute:(inputs:I[])=>Promise<O[]>,private readonly maxActive=2,private readonly maxBatch=4,private readonly maxOutstanding=8,private readonly windowMs=25,private readonly waitMs=15000){
  if([maxActive,maxBatch,maxOutstanding,windowMs,waitMs].some(n=>!Number.isSafeInteger(n)||n<1))throw new Error("invalid_batcher_limits");
 }
 submit(input:I):Promise<O|null>{
  if(this.outstanding>=this.maxOutstanding)return Promise.resolve(null);
  this.outstanding++;
  return new Promise(resolve=>{
   const entry={input,resolve,timer:setTimeout(()=>{const i=this.pending.indexOf(entry);if(i>=0){this.pending.splice(i,1);this.outstanding--;resolve(null);}},this.waitMs)};
   this.pending.push(entry);
   this.schedule();
  });
 }
 private schedule(){
  if(this.active>=this.maxActive||!this.pending.length||this.flushTimer!==undefined)return;
  this.flushTimer=setTimeout(()=>{this.flushTimer=undefined;this.flush();},this.windowMs);
 }
 private flush(){
  while(this.active<this.maxActive&&this.pending.length){
   const batch=this.pending.splice(0,this.maxBatch);this.active++;
   for(const job of batch)clearTimeout(job.timer);
   void this.process(batch);
  }
 }
 private async process(batch:typeof this.pending){
  try{
   const results=await this.execute(batch.map(job=>job.input));
   if(results.length!==batch.length)throw new Error("batch_result_count_mismatch");
   batch.forEach((job,i)=>job.resolve(results[i]!));
  }catch{batch.forEach(job=>job.resolve(null));}
  finally{this.active--;this.outstanding-=batch.length;this.schedule();}
 }
}
