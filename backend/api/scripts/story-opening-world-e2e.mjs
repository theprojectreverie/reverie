import { randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import { createServer, createConnection } from "node:net";
import { existsSync,readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import websocket from "@fastify/websocket";
import WebSocket from "ws";
import { config } from "../src/config.ts";
import { pool } from "../src/db.ts";
import { gameServerRoutes } from "../src/routes/game-servers.ts";
import { persistentWorldRealtimeRoutes } from "../src/routes/persistent-world-realtime.ts";
import { runMovementLoadProbe } from "./movement-load-probe.mjs";
import { runClusterProbe } from "./cluster-load-probe.mjs";

const N=2;
const openingRegion=process.env.REVERIE_E2E_OPENING_REGION;
if(!["story_training_ground","story_village","story_royal_gardens","story_royal_gate"].includes(openingRegion)||config.NODE_ENV==="production")throw new Error("Opening test requires local nonproduction region");
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
const app = Fastify({ logger: false });
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
    env: { ...process.env, REVERIE_E2E_DISABLE_LOCAL_SAVE: "1", REVERIE_API_BASE_URL: base, REVERIE_SERVER_BOOTSTRAP_SECRET: bootstrap, REVERIE_SERVER_KEY: key, REVERIE_SERVER_NAME: "Reverie "+N+" Player E2E", REVERIE_SERVER_REGION: openingRegion, REVERIE_SERVER_HOST: "127.0.0.1", REVERIE_SERVER_PORT: String(port), REVERIE_SERVER_MAX_PLAYERS: String(N), REVERIE_SERVER_ENDPOINT: endpoint },
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
  socket.on("message", raw => {
    let message;
    try { message = JSON.parse(String(raw)); } catch { return; }
    messages.push(message);
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
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve, reject, timer: setTimeout(() => {
        const i = waiters.indexOf(waiter);
        if (i >= 0) waiters.splice(i, 1);
        reject(new Error("WebSocket message timeout"));
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

  const progressPath=base+"/v1/game-servers/story-opening";
  const initial=await requestJson(progressPath,{headers:authHeaders(tokens[0])});
  assert(initial.status===200&&initial.body.progress.tutorialComplete===false,"authenticated opening progress is initially incomplete");
  assert((await requestJson(progressPath)).status===401,"unauthenticated progression access denied");
  if(openingRegion==="story_village"){
    const requestJoin=()=>requestJson(base+"/v1/game-servers/"+serverId+"/join",{method:"POST",headers:authHeaders(tokens[0]),body:"{}"});
    const denied=await requestJoin();assert(denied.status===403&&denied.body.error==="story_progression_required","village join requires verified tutorial victory");
    await pool.query("INSERT INTO story_milestone_reaches(player_id,milestone_id) VALUES($1,'village') ON CONFLICT DO NOTHING",[playerRows[0].id]);
    assert((await requestJoin()).status===403,"client telemetry cannot unlock the village");
    assert(!(await requestJson(progressPath,{headers:authHeaders(tokens[0])})).body.servers.some(s=>s.id===serverId),"locked village excluded from eligible story directory");
    // Disposable fixture only; opening-progression E2E separately tests real combat victory.
    for(const player of playerRows)await pool.query("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,status,finished_at,state) VALUES($1,'tutorial_fairy_spar',ARRAY['kael'],'victory',now(),$2::jsonb)",[player.id,JSON.stringify({view:{status:"victory"},actions:[{kind:"skill"}]})]);
    const unlocked=await requestJson(progressPath,{headers:authHeaders(tokens[0])});assert(unlocked.body.progress.tutorialComplete&&unlocked.body.servers.some(s=>s.id===serverId),"verified tutorial unlocks village directory");
  }
  if(["story_royal_gardens","story_royal_gate"].includes(openingRegion)){
    const join=()=>requestJson(base+"/v1/game-servers/"+serverId+"/join",{method:"POST",headers:authHeaders(tokens[0]),body:"{}"});
    assert((await join()).status===403,"garden entry requires verified opening progression");
    for(const player of playerRows)await pool.query("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,status,finished_at,state) VALUES($1,'tutorial_fairy_spar',ARRAY['kael'],'victory',now(),$2::jsonb)",[player.id,JSON.stringify({view:{status:"victory"},actions:[{kind:"skill"}]})]);
    assert((await join()).status===403,"tutorial victory alone does not unlock gardens");
    // Test-only proof records, not actual boss victories; settlement is covered separately.
    for(const player of playerRows)await pool.query("INSERT INTO story_battle_sessions(player_id,group_id,party_ids,status,finished_at,settled_at,rewards,state) VALUES($1,'gerald_boss_encounter',ARRAY['kael'],'victory',now(),now(),'{}'::jsonb,$2::jsonb)",[player.id,JSON.stringify({view:{status:"victory"},actions:[{kind:"skill"}]})]);
    if(openingRegion==="story_royal_gate"){
      assert((await join()).status===403,"both opening victories alone do not unlock the Royal Gate");
      await pool.query("INSERT INTO story_milestone_reaches(player_id,milestone_id) VALUES($1,'royal_gate') ON CONFLICT DO NOTHING",[playerRows[0].id]);
      assert((await join()).status===403,"client telemetry cannot unlock the Royal Gate");
      for(const player of playerRows)await pool.query("INSERT INTO story_elathra_audience(player_id) VALUES($1)",[player.id]);
      assert((await join()).status===403,"hearing Elathra alone does not unlock the Royal Gate");
      assert(!(await requestJson(progressPath,{headers:authHeaders(tokens[0])})).body.servers.some(s=>s.id===serverId),"locked Royal Gate excluded from directory");
      // Disposable fixture represents prior completed audience; its actual quest transaction has a separate E2E.
      for(const player of playerRows)await pool.query("UPDATE story_elathra_audience SET completed_at=now() WHERE player_id=$1",[player.id]);
      const unlocked=await requestJson(progressPath,{headers:authHeaders(tokens[0])});
      assert(unlocked.body.progress.royalGateUnlocked&&unlocked.body.servers.some(s=>s.id===serverId),"verified audience unlocks Royal Gate directory");
    }else{
      assert((await requestJson(progressPath,{headers:authHeaders(tokens[0])})).body.servers.some(s=>s.id===serverId),"both verified victories unlock isolated garden directory");
    }
  }
  const joinTickets = await Promise.all(tokens.map(token => requestJson(base + "/v1/game-servers/" + serverId + "/join", {
    method: "POST", headers: authHeaders(token), body: "{}"
  })));
  assert(joinTickets.every(result => result.status === 200 && result.body.joinTicket), "all eight players receive unique join tickets");
  assert(new Set(joinTickets.map(result => result.body.joinTicket)).size === N, "eight player tickets are unique");
  clients = await connectWave(endpoint, tokens, joinTickets, serverId);
  const legacyStatus=await new Promise((resolve,reject)=>{
    const socket=new WebSocket(base.replace("http:","ws:")+"/v1/world/realtime?serverId="+serverId,{headers:authHeaders(tokens[0])});
    socket.on("unexpected-response",(_req,res)=>{res.resume();socket.terminate();resolve(res.statusCode);});
    socket.on("error",()=>{});socket.on("open",()=>{socket.terminate();reject(new Error("Legacy story socket accepted"));});
  });
  assert(legacyStatus===403,"legacy API socket cannot bypass dedicated story transport");
  const firstSnapshot = clients.reduce((best, client) => client.admission.members.length > best.members.length ? client.admission : best, clients[0].admission);
  const firstMemberIds = new Set(firstSnapshot.members.map(member => member.playerId));
  assert(clients.every(client => client.admission.type === "world_joined"), "all eight concurrent WebSocket admissions succeed");
  assert(firstSnapshot.members.length === N && playerRows.every(player => firstMemberIds.has(player.id)), "latest concurrent admission snapshot contains all eight players");
  await waitForLeaseCount(N);
  assert(true, "eight durable PostgreSQL connection leases are active");

  const manifest=JSON.parse(readFileSync(new URL("../../../resources/data/story_opening_regions.json",import.meta.url),"utf8"));
  const [x,y]=manifest[openingRegion].spawn;
  assert(clients.every(c=>c.admission.members.some(m=>m.playerId===c.admission.playerId&&m.x===x&&m.y===y)),"all players start at the authored server spawn");
  await new Promise(resolve=>setTimeout(resolve,100));
  clients[0].socket.send(JSON.stringify({type:"position",x:10000,y:10000}));
  await clients[0].waitFor(m=>m.type==="rejected"&&m.reason==="region_bounds");
  const [bossX,bossY]=manifest[openingRegion].encounter.position;
  clients[0].socket.send(JSON.stringify({type:"position",x:bossX,y:bossY}));
  await clients[0].waitFor(m=>m.type==="rejected"&&m.reason==="movement_too_fast");
  clients.forEach((c,i)=>c.socket.send(JSON.stringify({type:"position",x:x+i+1,y})));
  await waitForPositionCount(N);
  const positions=await pool.query("select player_id,x,y from game_server_player_state where server_id=$1",[serverId]);
  assert(playerRows.every((p,i)=>positions.rows.some(r=>r.player_id===p.id&&Number(r.x)===x+i+1&&Number(r.y)===y)),"only valid near-spawn movements were committed");
  clients.forEach(c=>c.socket.terminate());clients=[];await waitForLeaseCount(0);
  await pool.query("update game_servers set status='offline',heartbeat_at=NULL,stopped_at=now() where id=$1",[serverId]);
  await stopGodot(port);godot=startGodot(base,bootstrap,serverKey,port);await waitForServerReady(serverId,port);
  const tickets=await Promise.all(tokens.map(token=>requestJson(base+"/v1/game-servers/"+serverId+"/reconnect",{method:"POST",headers:authHeaders(token),body:"{}"})));
  clients=await connectWave(endpoint,tokens,tickets,serverId);
  assert(clients.every((c,i)=>c.admission.members.some(m=>m.playerId===c.admission.playerId&&m.x===x+i+1&&m.y===y)),"server restart restores the committed opening positions");
  clients.forEach(c=>c.socket.terminate());clients=[];await waitForLeaseCount(0);
  await pool.query("update game_servers set status='offline',heartbeat_at=NULL,stopped_at=now() where id=$1",[serverId]);await stopGodot(port);
  console.log("PASS opening transport "+openingRegion);finished=true;
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
