import type {Pool,PoolClient} from "pg";
import {readFileSync} from "node:fs";
type Db=Pool|PoolClient;
const content=JSON.parse(readFileSync(new URL("../../../../resources/data/items.json",import.meta.url),"utf8")) as Record<string,{name:string;category:string;rarity:string}>;
export const offers=[
 {id:"moonpetal",itemId:"moonpetal",quantity:5,cost:25,level:1,limit:4},
 {id:"gothic_shard",itemId:"gothic_shard",quantity:3,cost:40,level:2,limit:3},
 {id:"dew",itemId:"dew_of_awakening",quantity:1,cost:60,level:3,limit:3},
 {id:"royal_seal",itemId:"royal_seal",quantity:1,cost:90,level:5,limit:2},
 {id:"hollow_heart",itemId:"hollow_heart",quantity:1,cost:140,level:8,limit:1}
] as const;
for(const o of offers)if(content[o.itemId]?.category!=="material")throw new Error("invalid_guild_shop_catalogue");
const weekSql="date_trunc('week',now() AT TIME ZONE 'UTC')::date";
export async function grantGuildTokens(db:PoolClient,id:string,amount:number,ref:string){
 const key="guild-mission-token:"+ref;
 const existing=await db.query("SELECT 1 FROM currency_ledger WHERE player_id=$1 AND idempotency_key=$2",[id,key]);
 if(existing.rowCount)return;
 const w=(await db.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'guild_tokens',$2) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[id,amount])).rows[0];
 await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'guild_tokens',$2,$3,'guild_mission_token','guild_mission',$4,$5)",[id,amount,w.balance,ref,key]);
}
export async function guildShop(db:Db,id:string,guildId:string){
 const r=(await db.query("SELECT g.level,to_char("+weekSql+",'YYYY-MM-DD') AS week,COALESCE((SELECT balance FROM player_currencies WHERE player_id=$1 AND currency_id='guild_tokens'),0)::text AS balance FROM guild_members m JOIN guilds g ON g.id=m.guild_id WHERE m.player_id=$1 AND g.id=$2",[id,guildId])).rows[0];
 if(!r)return null;
 const count=await db.query<{offer_id:string;n:number}>("SELECT offer_id,count(*)::int AS n FROM guild_shop_purchases WHERE player_id=$1 AND week_start=$2 GROUP BY offer_id",[id,r.week]);
 return {week:r.week,balance:r.balance,offers:offers.map(o=>{const purchased=count.rows.find(c=>c.offer_id===o.id)?.n??0;return {...o,name:content[o.itemId]!.name,rarity:content[o.itemId]!.rarity,purchased,canBuy:purchased<o.limit&&r.level>=o.level&&BigInt(r.balance)>=BigInt(o.cost)};})};
}
type Receipt={offerId:string;itemId:string;quantity:number;cost:number;week:string};
export async function buyGuildOffer(db:PoolClient,id:string,guildId:string,requestId:string,week:string,offerId:string):Promise<{ok:true;replayed:boolean;receipt:Receipt}|{ok:false;reason:string}>{
 const fail=(reason:string)=>({ok:false as const,reason});
 // Called inside the guild mutation transaction, which serializes membership and shop writes.
 const m=(await db.query("SELECT g.level FROM guild_members m JOIN guilds g ON g.id=m.guild_id WHERE m.player_id=$1 AND m.guild_id=$2",[id,guildId])).rows[0];
 if(!m)return fail("guild_membership_required");
 const prior=(await db.query("SELECT guild_id,offer_id,item_id,quantity,cost,to_char(week_start,'YYYY-MM-DD') AS week FROM guild_shop_purchases WHERE player_id=$1 AND request_id=$2",[id,requestId])).rows[0];
 if(prior){
  if(prior.guild_id!==guildId||prior.offer_id!==offerId||prior.week!==week)return fail("guild_shop_request_conflict");
  return {ok:true,replayed:true,receipt:{offerId:prior.offer_id,itemId:prior.item_id,quantity:prior.quantity,cost:prior.cost,week:prior.week}};
 }
 const o=offers.find(x=>x.id===offerId);
 if(!o)return fail("unknown_guild_offer");
 const state=await guildShop(db,id,guildId);
 if(!state||state.week!==week)return fail("guild_shop_week_changed");
 if(m.level<o.level)return fail("guild_level_required");
 if((state.offers.find(x=>x.id===offerId)?.purchased??o.limit)>=o.limit)return fail("guild_shop_weekly_limit");
 const debit=await db.query("UPDATE player_currencies SET balance=balance-$2 WHERE player_id=$1 AND currency_id='guild_tokens' AND balance>=$2 RETURNING balance::text",[id,o.cost]);
 if(!debit.rowCount)return fail("insufficient_guild_tokens");
 const item=content[o.itemId]!;
 await db.query("INSERT INTO items(id,display_name,category,rarity) VALUES($1,$2,'material',$3) ON CONFLICT(id) DO NOTHING",[o.itemId,item.name,item.rarity]);
 const stock=(await db.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=inventory_items.quantity+EXCLUDED.quantity RETURNING quantity::text",[id,o.itemId,o.quantity])).rows[0];
 const key="guild-shop:"+requestId;
 await db.query("INSERT INTO guild_shop_purchases(player_id,request_id,guild_id,week_start,offer_id,item_id,quantity,cost) VALUES($1,$2,$3,$4,$5,$6,$7,$8)",[id,requestId,guildId,week,o.id,o.itemId,o.quantity,o.cost]);
 await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'guild_tokens',-$2::bigint,$3,'guild_shop_purchase','guild_shop',$4,$5)",[id,o.cost,debit.rows[0].balance,requestId,key]);
 await db.query("INSERT INTO item_ledger(player_id,item_id,delta,quantity_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'guild_shop_purchase','guild_shop',$5,$6)",[id,o.itemId,o.quantity,stock.quantity,requestId,key]);
 return {ok:true,replayed:false,receipt:{offerId:o.id,itemId:o.itemId,quantity:o.quantity,cost:o.cost,week}};
}