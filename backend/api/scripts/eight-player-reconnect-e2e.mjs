import { randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import { createServer, createConnection } from "node:net";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import rateLimit from "@fastify/rate-limit";
import websocket from "@fastify/websocket";
import WebSocket from "ws";
import { config } from "../src/config.ts";
import { pool } from "../src/db.ts";
import { gameServerRoutes } from "../src/routes/game-servers.ts";
import { persistentWorldRealtimeRoutes } from "../src/routes/persistent-world-realtime.ts";
import { runMovementLoadProbe } from "./movement-load-probe.mjs";
import { runClusterProbe } from "./cluster-load-probe.mjs";

const N=Number(process.env.REVERIE_E2E_PLAYERS??8);
if(!Number.isInteger(N)||N<2||N>100)throw new RangeError("REVERIE_E2E_PLAYERS must be an integer from 2 to 100");
if(!["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname))throw new Error("World load test requires a local database");
const assert = (ok, label, detail = "") => {
  if(N!==8)label=label.replace(/eight/gi,String(N));
  console.log((ok ? "PASS " : "FAIL ") + label + (detail ? " — " + detail : ""));
  if (!ok) throw new Error(label + (detail ? ": " + detail : ""));
};
const suffix = randomBytes(6).toString("hex");
const serverKey = "reverie-"+N+"-player-" + suffix;
const emails = Array.from({ length: N }, (_, i) => `reverie-world-${suffix}-${i}@example.test`);
const names = Array.from({ length: N }, (_, i) => `World${i}${suffix}`.slice(0, 20));
const realQuotas=process.env.REVERIE_E2E_REAL_RATE_LIMITS==="1";
const app = Fastify({ logger: false, ...(realQuotas?{bodyLimit:16384}:{}) });
// Optional test-only failure after commit: simulate a lost acknowledgement.
// Never enabled outside this disposable loopback fixture.
let droppedBatch = null;
let retriedBatch = false;
if (process.env.REVERIE_E2E_DROP_BATCH_ACK === "1") {
  app.addHook("onSend", async (req, reply, payload) => {
    if (!req.url.endsWith("/events/batch") || reply.statusCode !== 200) return payload;
    const response = JSON.parse(String(payload));
    const events = req.body?.events;
    if (!Array.isArray(events) || !events.every(e => e.type === "position")) return payload;
    const ids = events.map(e => e.eventId);
    if (!droppedBatch && ids.length > 1) {
      droppedBatch = { ids, sequences: response.events.map(e => e.sequence) };
      reply.code(503);
      return JSON.stringify({ error: "test_lost_acknowledgement" });
    }
    if (droppedBatch && JSON.stringify(ids) === JSON.stringify(droppedBatch.ids)) {
      if (!response.duplicate || JSON.stringify(response.events.map(e => e.sequence)) !== JSON.stringify(droppedBatch.sequences)) {
        throw new Error("Batch retry changed the durable event sequences");
      }
      retriedBatch = true;
    }
    return payload;
  });
}

// Test-only temporary pre-commit failure. Does not stop or modify PostgreSQL.
let outageStarted=0, outageFailures=0;
if(process.env.REVERIE_E2E_PERSISTENCE_OUTAGE==="1"){
  app.addHook("preHandler",async(req,reply)=>{
    if(!req.url.endsWith("/events/batch"))return;
    const events=req.body?.events;
    if(!outageStarted&&Array.isArray(events)&&events.some(e=>e.type==="position"&&e.payload?.x===21&&e.payload?.y===30))outageStarted=Date.now();
    if(outageStarted&&Date.now()-outageStarted<3000){
      outageFailures++;
      return reply.code(503).send({error:"test_persistence_unavailable"});
    }
  });
}
let serverId = "";
let godot = null;
let clients = [];
let accountIds = [];
let finished = false;

async function requestJson(url, options = {}) {
  const response = await fetch(url, options);
  return { status: response.status, body: await response.json().catch(() => ({})) };
}
const authHeaders = token => ({ "content-type": "application/json", authorization: "Bearer " + token });
async function allocatePort() {
  const listener = createServer();
  await new Promise((resolve, reject) => listener.once("error", reject).listen(0, "127.0.0.1", resolve));
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  return port;
}
function startGodot(base, bootstrap, key, port) {
  const root = fileURLToPath(new URL("../../../", import.meta.url));
  const bin = process.env.REVERIE_GODOT_BIN ?? "C:\\Users\\quoth\\Downloads\\Godot_4.7.2_runtime\\Godot_v4.7.2-stable_win64.exe";
  if (!existsSync(bin)) throw new Error("Godot runtime not found: " + bin);
  const endpoint = "ws://127.0.0.1:" + port;
  const child = spawn(bin, ["--headless", "--path", root, "res://scenes/online/dedicated_world_server.tscn"], {
    cwd: root,
    env: { ...process.env, REVERIE_E2E_DISABLE_LOCAL_SAVE: "1", REVERIE_API_BASE_URL: base, REVERIE_SERVER_BOOTSTRAP_SECRET: bootstrap, REVERIE_SERVER_KEY: key, REVERIE_SERVER_NAME: "Reverie "+N+" Player E2E", REVERIE_SERVER_REGION: "castle_royal_gardens", REVERIE_SERVER_HOST: "127.0.0.1", REVERIE_SERVER_PORT: String(port), REVERIE_SERVER_MAX_PLAYERS: String(N), REVERIE_SERVER_ENDPOINT: endpoint },
    stdio: ["ignore", "pipe", "pipe"]
  });
  let output = "";
  child.stdout.on("data", chunk => output += chunk.toString());
  child.stderr.on("data", chunk => output += chunk.toString());
  return { child, endpoint, getOutput: () => output };
}
let transportRetries=0;
const allTestSockets=new Set();
async function connectWithTicket(endpoint, token, ticket, expectedServerId) {
  // Only retry an unopened transport. The single-use ticket has not been sent.
  for(let attempt=0;attempt<5;attempt++){
    try{return await connectOnce(endpoint,token,ticket,expectedServerId);}
    catch(error){
      if(error?.code!=="ECONNREFUSED"||attempt===4)throw error;
      transportRetries++;
      await new Promise(resolve=>setTimeout(resolve,100*(attempt+1)+Math.random()*150));
    }
  }
}
async function connectOnce(endpoint, token, ticket, expectedServerId) {
  const socket = new WebSocket(endpoint, { headers: { authorization: "Bearer " + token } });
  allTestSockets.add(socket);
  socket.once("close",()=>allTestSockets.delete(socket));
  const messages = [];
  const waiters = [];
  let closeDetail=null;
  socket.on("close",(code,reason)=>{
    closeDetail="code="+code+" reason="+String(reason);
    for(const waiter of waiters.splice(0)){clearTimeout(waiter.timer);waiter.reject(new Error("WebSocket closed during wait: "+closeDetail));}
  });
  socket.on("message", raw => {
    let message;
    try { message = JSON.parse(String(raw)); } catch { return; }
    messages.push(message);
    if(process.env.REVERIE_E2E_CLUSTER_MODE&&messages.length>512)messages.shift();
    for (const waiter of [...waiters]) {
      if (waiter.predicate(message)) {
        waiters.splice(waiters.indexOf(waiter), 1);
        clearTimeout(waiter.timer);
        waiter.resolve(message);
      }
    }
  });
  const waitFor = (predicate, timeout = 10000) => {
    const found = messages.findIndex(predicate);
    if (found >= 0) return Promise.resolve(messages.splice(found, 1)[0]);
    if(closeDetail!==null)return Promise.reject(new Error("WebSocket already closed: "+closeDetail));
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve, reject, timer: setTimeout(() => {
        const i = waiters.indexOf(waiter);
        if (i >= 0) waiters.splice(i, 1);
        reject(new Error("WebSocket message timeout; readyState="+socket.readyState+"; received types="+messages.slice(-8).map(m=>m.type).join(",")));
      }, timeout) };
      waiters.push(waiter);
    });
  };
  try {
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("WebSocket open timeout")), 10000);
    socket.once("open", () => { clearTimeout(timer); resolve(); });
    socket.once("error", error => { clearTimeout(timer); reject(error); });
  });
  const challenge = await waitFor(message => message.type === "ticket_required");
  assert(challenge.serverId === expectedServerId, "socket challenge is scoped to the registered world");
  socket.send(JSON.stringify({ type: "join_ticket", ticket, lastEventSequence: 0, interestWindows: process.env.REVERIE_E2E_INTEREST_PROBE === "1" || process.env.REVERIE_E2E_CLUSTER_MODE === "interest" }));
  const admission = await waitFor(message => message.type === "world_joined" || message.type === "rejected");
  if (admission.type !== "world_joined") throw new Error("Player admission rejected: " + JSON.stringify(admission));
  if(admission.interestWindows===true){
    if(Object.hasOwn(admission.worldState??{},"playerPositions")||Object.hasOwn(admission.worldState??{},"playerProfiles"))throw new Error("negotiated admission duplicated member state");
  }
  return { socket, admission, waitFor };
  } catch (error) { socket.terminate(); throw error; }
}
async function connectWave(endpoint, tokens, tickets, expectedServerId) {
  const connected = [];
  const waveSize = 8;
  try {
    for (let start = 0; start < tickets.length; start += waveSize) {
      const wave = await Promise.allSettled(tickets.slice(start, start + waveSize).map((result, index) =>
        connectWithTicket(endpoint, tokens[start + index], result.body.joinTicket, expectedServerId)));
      connected.push(...wave.filter(result => result.status === "fulfilled").map(result => result.value));
      const failed = wave.find(result => result.status === "rejected");
      if (failed) throw failed.reason;
    }
    return connected;
  } catch (error) {
    connected.forEach(client => client.socket.terminate());
    throw error;
  }
}
async function waitForLeaseCount(expected) {
  const started = Date.now();
  while (Date.now() - started < 12000) {
    const result = await pool.query("select count(*)::int as count from game_server_player_connections where server_id=$1 and lease_expires_at>now()", [serverId]);
    if (result.rows[0].count === expected) return;
    await new Promise(resolve => setTimeout(resolve, 150));
  }
  const final = await pool.query("select count(*)::int as count from game_server_player_connections where server_id=$1 and lease_expires_at>now()", [serverId]);
  throw new Error("Lease count did not reach " + expected + "; got " + final.rows[0].count);
}
async function waitForPositionCount(expected) {
  const started = Date.now();
  while (Date.now() - started < 10000) {
    const result = await pool.query("select count(*)::int as count from game_server_player_state where server_id=$1", [serverId]);
    if (result.rows[0].count === expected) return;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  const final = await pool.query("select count(*)::int as count from game_server_player_state where server_id=$1", [serverId]);
  throw new Error("Position count did not reach " + expected + "; got " + final.rows[0].count);
}
async function waitForServerReady(expectedId, expectedPort) {
  const expectedEndpoint = "ws://127.0.0.1:" + expectedPort;
  for (let i = 0; i < 120; i++) {
    if (!godot || godot.child.exitCode !== null) throw new Error("Godot server exited during restart: " + (godot?.getOutput() ?? ""));
    const row = await pool.query("select id,status,endpoint_url,max_players from game_servers where server_key=$1", [serverKey]);
    if (row.rows[0]?.id === expectedId && row.rows[0]?.status === "online" && row.rows[0]?.endpoint_url === expectedEndpoint && row.rows[0]?.max_players === N) return row.rows[0];
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  throw new Error("Replacement dedicated server did not become ready: " + (godot?.getOutput().slice(-1500) ?? ""));
}
async function stopGodot(port) {
  if (!godot?.child || godot.child.exitCode !== null) { godot = null; return; }
  const child = godot.child;
  child.kill("SIGKILL");
  // On Windows the console launcher can outlive its GUI child handle briefly.
  // Confirm the actual WebSocket listener is gone before reusing the port.
  for (let i = 0; i < 50; i++) {
    const listening = await new Promise(resolve => {
      const socket = createConnection({ host: "127.0.0.1", port });
      socket.once("connect", () => { socket.destroy(); resolve(true); });
      socket.once("error", () => resolve(false));
      socket.setTimeout(300, () => { socket.destroy(); resolve(false); });
    });
    if (!listening) { godot = null; return; }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error("Dedicated server WebSocket listener did not stop");
}

try {
  const bootstrap = config.GAME_SERVER_BOOTSTRAP_SECRET;
  assert(Boolean(bootstrap), "server bootstrap secret is configured for isolated dedicated-server test");
  if(realQuotas){await app.register(rateLimit,{max:100,timeWindow:"1 minute"});console.log("REAL_API_QUOTAS_ENABLED");}
  await app.register(jwt, { secret: config.JWT_SECRET });
  await app.register(websocket);
  await app.register(gameServerRoutes, { prefix: "/v1/game-servers" });
  await app.register(persistentWorldRealtimeRoutes, { prefix: "/v1" });
  await app.listen({ host: "127.0.0.1", port: 0 });
  const address = app.server.address();
  if (!address || typeof address === "string") throw new Error("API test listener failed to bind");
  const base = "http://127.0.0.1:" + address.port;

  const accountRows = await pool.query(
    "insert into accounts(email,password_hash,email_verified,status) select email,'$argon2id$e2e-placeholder',true,'active' from unnest($1::text[]) email returning id,email",
    [emails]
  );
  accountIds = accountRows.rows.map(row => row.id);
  const playerResult = await pool.query(
    "insert into players(account_id,name) select account_id,name from unnest($1::uuid[],$2::text[]) as v(account_id,name) returning id,account_id,name",
    [accountIds, names]
  );
  const playerRows = playerResult.rows;
  assert(playerRows.length === N, "eight isolated player identities are created");
  const versions = await pool.query("select id,token_version from accounts where id=any($1::uuid[])", [accountIds]);
  const tokens = playerRows.map(player => {
    const version = versions.rows.find(row => row.id === player.account_id).token_version;
    return app.jwt.sign({ sub: player.account_id, playerId: player.id, playerName: player.name, tokenVersion: version });
  });

  const port = await allocatePort();
  const endpoint = "ws://127.0.0.1:" + port;
  godot = startGodot(base, bootstrap, serverKey, port);
  let online = false;
  for (let i = 0; i < 120; i++) {
    if (godot.child.exitCode !== null) throw new Error("Godot server exited: " + godot.getOutput());
    const row = await pool.query("select id,status,endpoint_url,max_players from game_servers where server_key=$1", [serverKey]);
    if (row.rows[0]?.status === "online" && row.rows[0]?.endpoint_url === endpoint && row.rows[0]?.max_players === N) {
      serverId = row.rows[0].id;
      online = true;
      break;
    }
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  assert(online, "headless Godot dedicated server registers an eight-slot world and becomes live", godot.getOutput().slice(-1000));

  const joinTickets = await Promise.all(tokens.map(token => requestJson(base + "/v1/game-servers/" + serverId + "/join", {
    method: "POST", headers: authHeaders(token), body: "{}"
  })));
  assert(joinTickets.every(result => result.status === 200 && result.body.joinTicket), "all eight players receive unique join tickets");
  assert(new Set(joinTickets.map(result => result.body.joinTicket)).size === N, "eight player tickets are unique");
  clients = await connectWave(endpoint, tokens, joinTickets, serverId);
  const firstSnapshot = clients.reduce((best, client) => client.admission.members.length > best.members.length ? client.admission : best, clients[0].admission);
  const firstMemberIds = new Set(firstSnapshot.members.map(member => member.playerId));
  assert(clients.every(client => client.admission.type === "world_joined"), "all eight concurrent WebSocket admissions succeed");
  assert(firstSnapshot.members.length === N && playerRows.every(player => firstMemberIds.has(player.id)), "latest concurrent admission snapshot contains all eight players");
  await waitForLeaseCount(N);
  assert(true, "eight durable PostgreSQL connection leases are active");

  // The dedicated server intentionally ignores movement arriving within 40 ms
  // of admission; wait past that guard before the first authoritative proposals.
  await new Promise(resolve => setTimeout(resolve, 100));
  await Promise.all(clients.map(client => {
    client.socket.send(JSON.stringify({ type: "position", x: 20, y: 30 }));
    return Promise.resolve();
  }));
  await waitForPositionCount(N);
  const persisted = await pool.query("select count(*)::int as count from game_server_player_state where server_id=$1 and player_id=any($2::uuid[])", [serverId, playerRows.map(row => row.id)]);
  assert(persisted.rows[0].count === N, "all eight players persist authoritative positions");
  if (process.env.REVERIE_E2E_DROP_BATCH_ACK === "1") {
    for (let i = 0; i < 100 && !retriedBatch; i++) await new Promise(resolve => setTimeout(resolve, 50));
    assert(retriedBatch, "lost batch acknowledgement retries the identical IDs and original sequences");
    const committed = await pool.query("select count(*)::int as count from game_server_world_events where server_id=$1 and event_id=any($2::uuid[])", [serverId, droppedBatch.ids]);
    assert(committed.rows[0].count === droppedBatch.ids.length, "retry does not duplicate durable events");
  }

  if (process.env.REVERIE_E2E_INTEREST_PROBE === "1") {
    assert(N === 4, "interest pilot uses four disposable players");
    assert(clients.every(c => c.admission.interestWindows === true), "all clients negotiate interest windows");
    const moving = clients[0], moverId = playerRows[0].id, observerId = playerRows[1].id;
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    const positionAt = async x => {
      for (let i=0;i<100;i++) {
        const q=await pool.query("select sequence::text from game_server_world_events where server_id=$1 and player_id=$2 and event_type='position' and (payload->>'x')::double precision=$3 order by sequence desc limit 1",[serverId,moverId,x]);
        if(q.rows[0])return Number(q.rows[0].sequence);
        await pause(50);
      }
      throw new Error("position not committed: "+x);
    };
    await pause(150);
    for (const x of [100,180,260,340,420]) {
      moving.socket.send(JSON.stringify({type:"position",x,y:30}));
      await pause(150);
    }
    const farSequence = await positionAt(420);
    const far = await clients[1].waitFor(m=>m.type==="world_position_window"&&m.sequence>=farSequence);
    const moverFar = await moving.waitFor(m=>m.type==="world_position_window"&&m.sequence>=farSequence);
    assert(!far.members.some(m=>m.playerId===moverId), "distant mover excluded from observer window");
    assert(moverFar.members.length===0, "isolated mover receives no distant members");
    assert(far.members.length===2, "nearby stationary members remain visible");
    assert(far.fromSequence<=farSequence&&far.sequence>=farSequence, "filtered movement advances durable cursor");
    for (const x of [340,260,180,100,21]) {
      moving.socket.send(JSON.stringify({type:"position",x,y:30}));
      await pause(150);
    }
    const nearSequence=await positionAt(21);
    const near=await clients[1].waitFor(m=>m.type==="world_position_window"&&m.sequence>=nearSequence);
    const moverNear=await moving.waitFor(m=>m.type==="world_position_window"&&m.sequence>=nearSequence);
    assert(near.members.some(m=>m.playerId===moverId&&m.x===21), "returning mover reappears with latest committed position");
    assert(moverNear.members.some(m=>m.playerId===observerId&&m.x===20), "stationary observer reappears when receiver moves into range");
    assert(near.members.length===3&&moverNear.members.length===3, "all nearby players restored without reconnect");
    // Radius 150, exit radius 180. Observer is at x=20.
    let boundarySequence=nearSequence;
    const boundary=async(x,visible,label)=>{
      moving.socket.send(JSON.stringify({type:"position",x,y:30}));
      await pause(150);
      const q=await pool.query("select sequence::text from game_server_world_events where server_id=$1 and player_id=$2 and event_type='position' and (payload->>'x')::double precision=$3 and sequence>$4 order by sequence desc limit 1",[serverId,moverId,x,boundarySequence]);
      assert(q.rows.length===1,"boundary movement committed: "+x);
      boundarySequence=Number(q.rows[0].sequence);
      const window=await clients[1].waitFor(m=>m.type==="world_position_window"&&m.sequence>=boundarySequence);
      assert(window.members.some(m=>m.playerId===moverId)===visible,label);
    };
    await boundary(95,true,"inside entry radius");
    await boundary(175,true,"existing avatar retained outside entry radius");
    await boundary(185,true,"boundary oscillation does not flicker");
    await boundary(205,false,"avatar removed beyond exit radius");
    await boundary(185,false,"avatar stays absent in hysteresis band");
    await boundary(165,true,"avatar returns inside entry radius");
    console.log("INTEREST_HYSTERESIS_PASS");
    console.log("INTEREST_WINDOW_PROBE_PASS farMembers="+far.members.length+" isolatedMembers="+moverFar.members.length+" returnedMembers="+near.members.length);
  }
  if (process.env.REVERIE_E2E_CLUSTER_MODE) {
    await runClusterProbe({clients,playerRows,pool,serverId,mode:process.env.REVERIE_E2E_CLUSTER_MODE,serverPid:godot.child.pid});
    if(process.env.REVERIE_E2E_CHECKPOINT_VERIFY==="1"){
      const deadline=Date.now()+35000;
      let checkpoint;
      do{
        checkpoint=(await pool.query("select revision::int,state from game_server_world_state where server_id=$1",[serverId])).rows[0];
        if(checkpoint?.revision>=2)break;
        await new Promise(resolve=>setTimeout(resolve,100));
      }while(Date.now()<deadline);
      assert(checkpoint?.revision>=2,"periodic world checkpoint has saved at least twice");
      const state=checkpoint.state,cursor=Number(state.eventSequence);
      assert(Number.isSafeInteger(cursor)&&cursor>0,"checkpoint identifies its durable sequence");
      const positions=(await pool.query("select distinct on (player_id) player_id,payload from game_server_world_events where server_id=$1 and event_type='position' and sequence<=$2 order by player_id,sequence desc",[serverId,cursor])).rows;
      assert(positions.length===N,"checkpoint cursor has durable positions for every player");
      assert(playerRows.every(player=>Object.hasOwn(state.playerProfiles??{},player.id)&&Object.hasOwn(state.playerPositions??{},player.id)),"checkpoint includes all authenticated profiles and positions");
      assert(positions.every(row=>Number(state.playerPositions[row.player_id]?.x)===Number(row.payload.x)&&Number(state.playerPositions[row.player_id]?.y)===Number(row.payload.y)),"checkpoint positions match the committed event cursor exactly");
      console.log("LIVE_CHECKPOINT_VERIFIED "+JSON.stringify({revision:checkpoint.revision,cursor,players:N,bytes:Buffer.byteLength(JSON.stringify(state))}));
    }

  }
  const movementRounds = Number(process.env.REVERIE_E2E_MOVEMENT_ROUNDS || 0);
  if (movementRounds !== 0) {
    await runMovementLoadProbe({ clients, playerRows, rounds: movementRounds, pool, serverId });
    if(process.env.REVERIE_E2E_PERSISTENCE_OUTAGE==="1"){
      assert(outageFailures>=2,"temporary persistence failures were injected");
      console.log("PERSISTENCE_OUTAGE_RECOVERED failedRequests="+outageFailures);
    }
  }


  const savedPositions=async()=>new Map((await pool.query("select player_id,x,y from game_server_player_state where server_id=$1 and player_id=any($2::uuid[])",[serverId,playerRows.map(row=>row.id)])).rows.map(row=>[row.player_id,{x:Number(row.x),y:Number(row.y)}]));
  const beforeDisconnect=await savedPositions();
  assert(beforeDisconnect.size===N,"all eight saved coordinates captured before disconnect");
  const exactCoordinates=(members)=>members.length===N&&members.every(member=>{
    const expected=beforeDisconnect.get(member.playerId);
    return expected&&expected.x===Number(member.x)&&expected.y===Number(member.y);
  });
  const exactDatabase=async()=>{
    const current=await savedPositions();
    return current.size===N&&[...beforeDisconnect].every(([id,pos])=>current.get(id)?.x===pos.x&&current.get(id)?.y===pos.y);
  };
  clients.forEach(client => client.socket.terminate());
  await waitForLeaseCount(0);
  assert(true, "simultaneous eight-client disconnect releases every connection lease");

  const reconnectTickets = await Promise.all(tokens.map(token => requestJson(base + "/v1/game-servers/" + serverId + "/reconnect", {
    method: "POST", headers: authHeaders(token), body: "{}"
  })));
  assert(reconnectTickets.every(result => result.status === 200 && result.body.joinTicket), "all eight clients obtain fresh reconnect tickets during the grace window");
  const reconnectClients = await connectWave(endpoint, tokens, reconnectTickets, serverId);
  clients = reconnectClients;
  const recoveredSnapshot = reconnectClients.reduce((best, client) => client.admission.members.length > best.members.length ? client.admission : best, reconnectClients[0].admission);
  const recoveredIds = new Set(recoveredSnapshot.members.map(member => member.playerId));
  assert(reconnectClients.every(client => client.admission.type === "world_joined"), "eight-client reconnect storm is admitted successfully");
  assert(recoveredSnapshot.members.length === N && playerRows.every(player => recoveredIds.has(player.id)), "reconnect snapshot restores the complete eight-player party");
  await waitForLeaseCount(N);
  const recoveredPositions = await pool.query("select count(*)::int as count from game_server_player_state where server_id=$1 and player_id=any($2::uuid[])", [serverId, playerRows.map(row => row.id)]);
  assert(recoveredPositions.rows[0].count === N, "all eight authoritative positions survive the reconnect storm");
  assert(exactCoordinates(recoveredSnapshot.members)&&await exactDatabase(),"all eight exact coordinates restored in reconnect snapshot and database");

  // Simulate a regional process restart after all eight players are live again.
  clients.forEach(client => client.socket.terminate());
  clients = [];
  await waitForLeaseCount(0);
  await pool.query("update game_servers set status='offline',heartbeat_at=NULL,stopped_at=now() where id=$1", [serverId]);
  await stopGodot(port);
  assert(true, "first eight-player regional process stopped");

  godot = startGodot(base, bootstrap, serverKey, port);
  await waitForServerReady(serverId, port);
  assert(true, "replacement Godot process reclaimed the same regional server identity");
  const restartTickets = await Promise.all(tokens.map(token => requestJson(base + "/v1/game-servers/" + serverId + "/reconnect", {
    method: "POST", headers: authHeaders(token), body: "{}"
  })));
  assert(restartTickets.every(result => result.status === 200 && result.body.joinTicket), "all eight players receive reconnect tickets after the regional restart");
  const restartClients = await connectWave(endpoint, tokens, restartTickets, serverId);
  clients = restartClients;
  assert(restartClients.every(client => client.admission.type === "world_joined"), "all eight clients are admitted by the replacement process");
  const restartSnapshot = restartClients.reduce((best, client) => client.admission.members.length > best.members.length ? client.admission : best, restartClients[0].admission);
  const restartMemberIds = new Set(restartSnapshot.members.map(member => member.playerId));
  assert(restartSnapshot.members.length === N && playerRows.every(player => restartMemberIds.has(player.id)), "replacement process snapshot restores all eight party members");
  await waitForLeaseCount(N);
  const restartPositions = await pool.query("select count(*)::int as count from game_server_player_state where server_id=$1 and player_id=any($2::uuid[])", [serverId, playerRows.map(row => row.id)]);
  assert(restartPositions.rows[0].count === N, "all eight durable player positions survive the regional process restart");
  assert(exactCoordinates(restartSnapshot.members)&&await exactDatabase(),"all eight exact coordinates restored in restart snapshot and database");

  clients.forEach(client => client.socket.terminate());
  clients = [];
  await waitForLeaseCount(0);
  await pool.query("update game_servers set status='offline',heartbeat_at=NULL,stopped_at=now() where id=$1", [serverId]);
  await stopGodot(port);
  assert(true, "replacement eight-player test server stopped cleanly");
  console.log("TRANSPORT_RETRIES "+transportRetries);
  finished = true;
} catch (error) {
  console.error("EIGHT_PLAYER_E2E_FAILURE", error?.stack ?? error);
  console.error("DEDICATED_SERVER_DIAGNOSTICS",godot?.child?.exitCode,godot?.getOutput().slice(-12000));
  process.exitCode = 1;
} finally {
  allTestSockets.forEach(socket=>{try{socket.terminate();}catch{}});
  clients.forEach(client => { try { client.socket.terminate(); } catch {} });
  if (godot?.child && godot.child.exitCode === null) godot.child.kill();
  if (serverId) await pool.query("update game_servers set status='offline',heartbeat_at=NULL,stopped_at=now() where id=$1", [serverId]).catch(() => {});
  if (serverId) await pool.query("delete from game_servers where id=$1", [serverId]).catch(error => console.error("server cleanup failed", error.message));
  if (accountIds.length) await pool.query("delete from accounts where id=any($1::uuid[])", [accountIds]).catch(error => console.error("account cleanup failed", error.message));
  if (serverId) {
    const residue = await pool.query(
      "select (select count(*)::int from game_servers where id=$1) as servers,(select count(*)::int from accounts where id=any($2::uuid[])) as accounts,(select count(*)::int from game_server_join_tickets where server_id=$1) as tickets,(select count(*)::int from game_server_player_state where server_id=$1) as positions,(select count(*)::int from game_server_world_events where server_id=$1) as events,(select count(*)::int from game_server_player_connections where server_id=$1) as connections",
      [serverId, accountIds]
    ).catch(error => { console.error("cleanup verification failed", error.message); return null; });
    const clean = residue !== null && Object.values(residue.rows[0]).every(value => Number(value) === 0);
    if (clean) console.log((N===8?"EIGHT_PLAYER":"WORLD_"+N+"_PLAYER")+"_CLEANUP_VERIFIED " + JSON.stringify(residue.rows[0]));
    else { console.error("EIGHT_PLAYER_CLEANUP_FAILED", residue?.rows[0] ?? null); finished = false; }
  }
  await app.close().catch(() => {});
  await pool.end().catch(() => {});
  if (finished) console.log((N===8?"EIGHT_PLAYER":"WORLD_"+N+"_PLAYER")+"_E2E_CLEANUP complete");
  process.exit(finished ? 0 : 1);
}
