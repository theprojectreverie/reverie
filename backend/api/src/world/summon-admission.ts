// Limit concurrent summon transactions before they reserve shared DB connections.
// PostgreSQL row locks remain the authority across different API processes.
type Release=()=>void;
type Waiting={player:string;resolve:(release:Release|null)=>void;timer:ReturnType<typeof setTimeout>};
export class SummonAdmission {
 private readonly active=new Set<string>();
 private readonly waiting:Waiting[]=[];
 constructor(private readonly maximum=6,private readonly maxWaiting=48,private readonly timeoutMs=4000){
  if(maximum<1||maxWaiting<0||timeoutMs<1)throw new Error("invalid_summon_admission");
 }
 get activeCount(){return this.active.size;}
 get queuedCount(){return this.waiting.length;}
 private lease(player:string):Release{
  this.active.add(player);
  let released=false;
  return ()=>{
   if(released)return;released=true;this.active.delete(player);this.drain();
  };
 }
 private drain(){
  while(this.active.size<this.maximum){
   const i=this.waiting.findIndex(entry=>!this.active.has(entry.player));
   if(i<0)return;
   const entry=this.waiting.splice(i,1)[0]!;
   clearTimeout(entry.timer);entry.resolve(this.lease(entry.player));
  }
 }
 async acquire(player:string):Promise<Release|null>{
  if(this.active.size<this.maximum&&!this.active.has(player)&&this.waiting.length===0)return this.lease(player);
  if(this.waiting.length>=this.maxWaiting)return null;
  return new Promise(resolve=>{
   const entry:Waiting={player,resolve,timer:setTimeout(()=>{
    const i=this.waiting.indexOf(entry);if(i>=0){this.waiting.splice(i,1);resolve(null);this.drain();}
   },this.timeoutMs)};
   this.waiting.push(entry);this.drain();
  });
 }
}
export const summonAdmission=new SummonAdmission();
