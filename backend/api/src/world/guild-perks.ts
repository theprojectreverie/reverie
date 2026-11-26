import type {Pool,PoolClient} from "pg";
type Db=Pool|PoolClient;
export const BASE_GUILD_CAPACITY=30;
export const guildPerks=[
 {id:"hall_1",title:"Expanded Guild Hall",level:3,cost:5000,capacity:35,requires:null},
 {id:"hall_2",title:"Grand Guild Hall",level:5,cost:12000,capacity:40,requires:"hall_1"},
 {id:"hall_3",title:"Sovereign Guild Hall",level:10,cost:25000,capacity:45,requires:"hall_2"}
] as const;
export async function purchasedPerks(db:Db,guildId:string){
 const q=await db.query<{perk_id:string}>("SELECT perk_id FROM guild_perks WHERE guild_id=$1",[guildId]);
 return new Set(q.rows.map(r=>r.perk_id));
}
export async function guildCapacity(db:Db,guildId:string){
 const owned=await purchasedPerks(db,guildId);
 return Math.max(BASE_GUILD_CAPACITY,...guildPerks.filter(p=>owned.has(p.id)).map(p=>p.capacity));
}
export async function perkState(db:Db,guildId:string,level:number,role:string,gold:bigint){
 const owned=await purchasedPerks(db,guildId);
 return guildPerks.map(p=>({...p,owned:owned.has(p.id),canPurchase:role==="leader"&&!owned.has(p.id)&&level>=p.level&&gold>=BigInt(p.cost)&&(!p.requires||owned.has(p.requires))}));
}