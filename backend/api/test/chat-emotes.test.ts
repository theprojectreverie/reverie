import test from "node:test";
import assert from "node:assert/strict";
import Fastify from "fastify";
import jwt from "@fastify/jwt";

test("chat sticker and emoji delivery respects channel access, blocks and rate limits", async t => {
  process.env.NODE_ENV = "test";
  process.env.DATABASE_URL = "postgresql://unused:unused@127.0.0.1:1/unused";
  process.env.JWT_SECRET = "isolated-chat-test-secret-at-least-32-characters";
  const {pool} = await import("../src/db.js");
  const {chatRoutes} = await import("../src/routes/chat.js");
  const a = "11111111-1111-4111-8111-111111111111";
  const b = "22222222-2222-4222-8222-222222222222";
  const c = "33333333-3333-4333-8333-333333333333";
  let blocked = false;
  let ownsMythic = false;
  let friends = true;
  let now = 1800000000000;
  const privateRows: any[] = [];
  const recentRows:any[]=[];
  const budgets=new Map<string,number[]>();
  const originalNow = Date.now;
  const originalQuery = pool.query;
  const originalConnect = pool.connect;
  Date.now = () => now;
  const query = async (sql: string, args: any[] = []) => {
    if (sql.includes("a.token_version=$3")) return {rows: args[2] === 1 && [a,b,c].includes(args[0]) ? [{id:args[0],name:args[0]===a?"Alice":"Bob",avatar:"kael_avatar",title_id:""}] : []};
    if(sql.includes("INSERT INTO chat_send_limits")){
      const times=(budgets.get(args[0])??[]).filter(t=>now-t<10000);
      if(times.length>=5||now-(times.at(-1)??0)<1000)return {rows:[],rowCount:0};
      budgets.set(args[0],[...times,now]);return {rows:[{player_id:args[0]}],rowCount:1};
    }
    if(sql.includes("INSERT INTO recent_chat_messages")){
      recentRows.push({id:args[0],playerId:args[1],channel:args[2],partyId:args[3],name:args[4],avatar:args[5],title:args[6],text:args[7],replyTo:args[8],at:now});
      return {rows:[{at:now}],rowCount:1};
    }
    if(sql.includes("FROM recent_chat_messages m JOIN players")){
      return {rows:recentRows.filter(r=>r.channel===args[1]&&r.at>=now-1800000&&(!blocked||args[0]!==b||r.playerId!==a)&&(args[1]==="world"||r.partyId===args[2])).slice().reverse()};
    }
    if (sql.includes("FROM co_op_lobby_members")) return {rows: args[0]===c ? [] : [{lobby_id:"party",joined_at:new Date(now-60000)}]};
    if (sql.includes("SELECT f.updated_at FROM friendships")) return {rows: friends&&!blocked&&[a,b].includes(args[0])&&[a,b].includes(args[1]) ? [{updated_at:new Date(now-60000)}] : []};
    if (sql.includes("FROM owned_characters") && sql.includes("char_id=ANY")) return {rows:ownsMythic&&args[0]===a?[{char_id:"ravienna_mythic"}]:[]};
    if (sql.includes("FROM gacha_pulls g")) return {rows:[]};
    if (sql.includes("SELECT blocked_id AS id FROM blocks")) return {rows: blocked&&args[0]===b ? [{id:a}] : []};
    if (sql.includes("INSERT INTO private_chat_messages")) {
      privateRows.push({id:args[0],playerId:args[1],recipientId:args[2],text:args[3],name:"Alice",avatar:"kael_avatar",title_id:"",at:now});
      return {rows:[{at:now}]};
    }
    if (sql.includes("FROM private_chat_messages m JOIN players")) return {rows:privateRows.filter(r=>[args[0],args[1]].includes(r.playerId)&&[args[0],args[1]].includes(r.recipientId)).slice().reverse()};
    if (sql.startsWith("UPDATE private_chat_messages") || sql.startsWith("SELECT id FROM players") || ["BEGIN","COMMIT","ROLLBACK"].includes(sql)) return {rows:[]};
    throw new Error("Unexpected mock database query: "+sql);
  };
  (pool as any).query = query;
  (pool as any).connect = async () => ({query,release(){}});
  const app = Fastify();
  t.after(async()=>{Date.now=originalNow;(pool as any).query=originalQuery;(pool as any).connect=originalConnect;await app.close();await pool.end();});
  await app.register(jwt,{secret:process.env.JWT_SECRET!});
  await app.register(chatRoutes,{prefix:"/v1/chat"});
  const headers = (id:string,version=1)=>({authorization:"Bearer "+app.jwt.sign({sub:id,playerId:id,tokenVersion:version})});
  const send = (id:string,text:string,channel="world",recipientId?:string) => app.inject({method:"POST",url:"/v1/chat/messages",headers:headers(id),payload:{channel,text,...(recipientId?{recipientId}:{})}});
  const read = (id:string,channel="world",recipientId?:string)=>app.inject({method:"GET",url:"/v1/chat/messages?channel="+channel+(recipientId?"&recipientId="+recipientId:""),headers:headers(id)});
  const sticker = "[sticker:lilith_ghost_plush]";
  const sent = await send(a,sticker);
  assert.equal(sent.statusCode,201,sent.body);
  assert.equal(sent.json().message.text,sticker);
  const received = await read(b); assert.equal(received.statusCode,200,received.body); assert.equal(received.json().messages[0].text,sticker);
  assert.equal((await send(a,sticker)).statusCode,429);
  now+=1200;
  const emoji = "Hello "+String.fromCodePoint(0x1f600,0x1f525);
  assert.equal((await send(a,emoji)).statusCode,201);
  assert.equal((await read(b)).json().messages[1].text,emoji);
  blocked=true;
  assert.equal((await read(b)).json().messages.length,0);
  blocked=false;
  now+=1200;
  assert.equal((await send(a,"[sticker:gerald_chibi]","party")).statusCode,201);
  assert.equal((await read(b,"party")).json().messages[0].text,"[sticker:gerald_chibi]");
  assert.equal((await read(c,"party")).statusCode,403);
  assert.equal((await read(c)).json().messages.length,2);
  now+=1200;
  assert.equal((await send(a,"[sticker:revienna_fallen_matron]","private",b)).statusCode,201);
  assert.equal((await read(b,"private",a)).json().messages[0].text,"[sticker:revienna_fallen_matron]");
  assert.equal((await read(c,"private",a)).statusCode,403);
  friends=false;
  assert.equal((await read(b,"private",a)).statusCode,403);
  now+=1200;
  assert.equal((await send(a,"a".repeat(201)+String.fromCodePoint(0x1f600))).statusCode,400);
  assert.equal((await send(a,"\u0000")).statusCode,400);
  now+=11000;
  const marker="[sticker:ravienna_mythic]";
  const unlocked=(id:string)=>app.inject({method:"GET",url:"/v1/chat/stickers",headers:headers(id)});
  assert.deepEqual((await unlocked(a)).json().unlocked,[]);
  assert.equal((await send(a,marker)).json().error,"sticker_locked");
  ownsMythic=true;
  assert.deepEqual((await unlocked(a)).json().unlocked,["ravienna_mythic"]);
  assert.deepEqual((await unlocked(b)).json().unlocked,[]);
  assert.equal((await send(b,marker)).statusCode,403);
  assert.equal((await send(a,marker)).statusCode,201);
  assert.ok((await read(b)).json().messages.some((m:any)=>m.text===marker));
  ownsMythic=false;
  assert.equal((await send(a,marker)).statusCode,403);
  assert.equal((await app.inject({method:"GET",url:"/v1/chat/messages"})).statusCode,401);
  assert.equal((await app.inject({method:"GET",url:"/v1/chat/messages",headers:headers(a,2)})).statusCode,401);
});