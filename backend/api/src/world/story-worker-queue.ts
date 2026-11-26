/** Process-local, bounded FIFO admission. Waiting jobs never spawn workers. */
export class StoryWorkerQueue {
 private active=0;
 private waiting:Array<{resolve:(release:(()=>void)|null)=>void;timer:ReturnType<typeof setTimeout>}>=[];
 constructor(private readonly concurrency:number,private readonly maxWaiting:number,private readonly waitMs:number){
  if(!Number.isSafeInteger(concurrency)||concurrency<1||!Number.isSafeInteger(maxWaiting)||maxWaiting<0||!Number.isSafeInteger(waitMs)||waitMs<1)throw new Error("invalid_worker_queue_limits");
 }
 acquire():Promise<(()=>void)|null>{
  if(this.active<this.concurrency&&this.waiting.length===0){this.active++;return Promise.resolve(this.releaseHandle());}
  if(this.waiting.length>=this.maxWaiting)return Promise.resolve(null);
  return new Promise(resolve=>{
   const entry={resolve,timer:setTimeout(()=>{
    const index=this.waiting.indexOf(entry);
    if(index>=0){this.waiting.splice(index,1);resolve(null);}
   },this.waitMs)};
   this.waiting.push(entry);
  });
 }
 private releaseHandle():()=>void{
  let released=false;
  return ()=>{
   if(released)return;
   released=true;
   const next=this.waiting.shift();
   if(next){clearTimeout(next.timer);next.resolve(this.releaseHandle());}
   else this.active--;
  };
 }
}
