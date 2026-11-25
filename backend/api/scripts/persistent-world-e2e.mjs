import { mkdir, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { fork, spawn } from "node:child_process";
import { createServer } from "node:net";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
const envText = await readFile(new URL("../.env", import.meta.url), "utf8");
for (const line of envText.split(/\r?\n/)) {
  const match = line.match(/^\s*([A-Z0-9_]+)=(.*)\s*$/);
  if (match && !process.env[match[1]]) process.env[match[1]] = match[2].replace(/^["']|["']$/g, "");
}
const [{ default: Fastify }, { default: jwtPlugin }, { default: websocketPlugin }, { config }, { pool }, { gameServerRoutes }, { persistentWorldRealtimeRoutes }, { default: WebSocket }] = await Promise.all([
  import("fastify"), import("@fastify/jwt"), import("@fastify/websocket"),
  import("../src/config.ts"), import("../src/db.ts"),
  import("../src/routes/game-servers.ts"), import("../src/routes/persistent-world-realtime.ts"),
  import("ws")
]);
const checks = [];
function check(ok, label, detail = "") {
  checks.push({ ok, label, detail });
  console.log((ok ? "PASS " : "FAIL ") + label + (detail ? " — " + detail : ""));
  if (!ok) throw new Error(label + (detail ? ": " + detail : ""));
}
const digest = value => createHash("sha256").update(value).digest("hex");
const suffix = randomBytes(6).toString("hex");
const serverKey = "reverie-e2e-" + suffix;
const dedicatedServerKey = "reverie-godot-e2e-" + suffix;
const emailA = "reverie-e2e-" + suffix + "-a@example.test";
const emailB = "reverie-e2e-" + suffix + "-b@example.test";
const emailC = "reverie-e2e-" + suffix + "-c@example.test";
const emailD = "reverie-e2e-" + suffix + "-d@example.test";
const playerNameA = ("E2EA" + suffix).slice(0, 20);
const playerNameB = ("E2EB" + suffix).slice(0, 20);
const playerNameC = ("E2EC" + suffix).slice(0, 20);
const playerNameD = ("E2ED" + suffix).slice(0, 20);
const app = Fastify({ logger: false });
let serverId = "", accountA = "", accountB = "", accountC = "", accountD = "", playerA = "", playerB = "", playerC = "", playerD = "";
let socketA, socketB, socketReuse, worker, finished = false;
let dedicatedServerId = "", dedicatedProcess = null, dedicatedSocketA = null, dedicatedSocketB = null, dedicatedSocketC = null, dedicatedSocketD = null, clientProcess = null, clientProcessB = null;
const clientMarkerDir = join(process.cwd(), "persistent-world-client-e2e-" + suffix);
const clientMarkerDirB = join(process.cwd(), "persistent-world-client-b-e2e-" + suffix);
class SocketClient {
  constructor(socket) {
    this.socket = socket; this.messages = []; this.waiters = []; this.closed = false;
    socket.on("message", raw => {
      let message; try { message = JSON.parse(String(raw)); } catch { return; }
      this.messages.push(message);
      for (const waiter of [...this.waiters]) if (waiter.predicate(message)) {
        this.waiters.splice(this.waiters.indexOf(waiter), 1); clearTimeout(waiter.timer); waiter.resolve(message);
      }
    });
    socket.on("close", (code, reason) => {
      this.closed = true; this.closeInfo = { code, reason: String(reason) };
      for (const waiter of [...this.waiters]) {
        this.waiters.splice(this.waiters.indexOf(waiter), 1); clearTimeout(waiter.timer);
        waiter.reject(new Error("socket closed " + code + ": " + String(reason)));
      }
    });
    socket.on("error", error => { this.socketError = error; });
  }
  waitFor(predicate, timeoutMs = 6000) {
    const index = this.messages.findIndex(predicate);
    if (index >= 0) return Promise.resolve(this.messages.splice(index, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve, reject, timer: setTimeout(() => {
        const i = this.waiters.indexOf(waiter); if (i >= 0) this.waiters.splice(i, 1);
        reject(new Error("websocket message timeout"));
      }, timeoutMs) };
      this.waiters.push(waiter);
    });
  }
  send(value) { this.socket.send(JSON.stringify(value)); }
  close() { if (this.socket && this.socket.readyState !== WebSocket.CLOSED) this.socket.terminate(); }
}
async function connectWithTicket(url, token, ticket, expectedServerId) {
  const socket = new WebSocket(url, { headers: { authorization: "Bearer " + token } });
  const client = new SocketClient(socket);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("websocket open timeout")), 6000);
    socket.once("open", () => { clearTimeout(timer); resolve(); });
    socket.once("error", error => { clearTimeout(timer); reject(error); });
  });
  const challenge = await client.waitFor(m => m.type === "ticket_required");
  check(challenge.serverId === expectedServerId, "world socket challenges with the correct server ID");
  client.send({ type: "join_ticket", ticket, lastEventSequence: 0 });
  const admission = await client.waitFor(m => m.type === "world_joined" || m.type === "rejected", 8000);
  return { client, admission };
}
async function connectDedicatedWithTicket(url, ticket) {
  const socket = new WebSocket(url);
  const client = new SocketClient(socket);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("dedicated Godot WebSocket open timeout")), 8000);
    socket.once("open", () => { clearTimeout(timer); resolve(); });
    socket.once("error", error => { clearTimeout(timer); reject(error); });
  });
  const challenge = await client.waitFor(m => m.type === "ticket_required", 8000);
  client.send({ type: "join_ticket", ticket, lastEventSequence: 0 });
  const admission = await client.waitFor(m => m.type === "world_joined" || m.type === "rejected", 10000);
  return { client, challenge, admission };
}

async function allocateTcpPort() {
  const listener = createServer();
  await new Promise((resolve, reject) => listener.once("error", reject).listen(0, "127.0.0.1", resolve));
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  return port;
}

function startGodotDedicatedServer(base, bootstrap, key, port) {
  const projectRoot = fileURLToPath(new URL("../../../", import.meta.url));
  const godotBin = process.env.REVERIE_GODOT_BIN ?? "C:\\Users\\quoth\\Downloads\\Godot_4.7.2_runtime\\Godot_v4.7.2-stable_win64.exe";
  if (!existsSync(godotBin)) throw new Error("Godot runtime not found: " + godotBin);
  const endpoint = "ws://127.0.0.1:" + port;
  const child = spawn(godotBin, ["--headless", "--path", projectRoot, "res://scenes/online/dedicated_world_server.tscn"], {
    cwd: projectRoot,
    env: { ...process.env, REVERIE_API_BASE_URL: base, REVERIE_SERVER_BOOTSTRAP_SECRET: bootstrap, REVERIE_SERVER_KEY: key, REVERIE_SERVER_NAME: "Reverie Godot E2E", REVERIE_SERVER_REGION: "castle_royal_gardens", REVERIE_SERVER_HOST: "127.0.0.1", REVERIE_SERVER_PORT: String(port), REVERIE_SERVER_ENDPOINT: endpoint },
    stdio: ["ignore", "pipe", "pipe"]
  });
  let output = "";
  child.stdout.on("data", chunk => { output += chunk.toString(); });
  child.stderr.on("data", chunk => { output += chunk.toString(); });
  return { child, endpoint, getOutput: () => output };
}
function startGodotReconnectClient(base, token, serverId, ticket, endpoint, playerId, markerDir, expectedX, expectedY, expectedRemoteId, expectedRemoteX, expectedRemoteY, peerMarkerDir) {
  const projectRoot = fileURLToPath(new URL("../../../", import.meta.url));
  const godotBin = process.env.REVERIE_GODOT_BIN ?? "C:\\Users\\quoth\\Downloads\\Godot_4.7.2_runtime\\Godot_v4.7.2-stable_win64.exe";
  const clientArgs = process.env.REVERIE_E2E_GUI_CLIENTS === "1"
    ? ["--path", projectRoot, "res://tests/persistent_world_client_reconnect_e2e.tscn"]
    : ["--headless", "--path", projectRoot, "res://tests/persistent_world_client_reconnect_e2e.tscn"];
  const child = spawn(godotBin, clientArgs, {
    cwd: projectRoot,
    env: { ...process.env, REVERIE_E2E_API_BASE: base, REVERIE_E2E_ACCESS_TOKEN: token, REVERIE_E2E_SERVER_ID: serverId, REVERIE_E2E_JOIN_TICKET: ticket, REVERIE_E2E_ENDPOINT: endpoint, REVERIE_E2E_PLAYER_ID: playerId, REVERIE_E2E_MARKER_DIR: markerDir, REVERIE_E2E_PEER_MARKER_DIR: peerMarkerDir, REVERIE_E2E_DISABLE_LOCAL_SAVE: "1", REVERIE_E2E_EXPECTED_X: String(expectedX), REVERIE_E2E_EXPECTED_Y: String(expectedY), REVERIE_E2E_EXPECTED_REMOTE_ID: expectedRemoteId, REVERIE_E2E_EXPECTED_REMOTE_X: String(expectedRemoteX), REVERIE_E2E_EXPECTED_REMOTE_Y: String(expectedRemoteY) },
    stdio: ["ignore", "pipe", "pipe"]
  });
  let output = "";
  child.stdout.on("data", chunk => { output += chunk.toString(); });
  child.stderr.on("data", chunk => { output += chunk.toString(); });
  return { child, getOutput: () => output };
}
async function waitForMarker(markerName, timeoutMs = 30000, predicate = () => true, markerDir = clientMarkerDir, processRef = clientProcess) {
  const markerPath = join(markerDir, markerName);
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (existsSync(markerPath)) {
      try {
        const value = JSON.parse(await readFile(markerPath, "utf8"));
        if (predicate(value)) return value;
      } catch {}
    }
    if (processRef?.child?.exitCode !== null && processRef?.child?.exitCode !== undefined) {
      const failurePath = join(markerDir, "failure.json");
      let failureDetail = "";
      if (existsSync(failurePath)) {
        try { failureDetail = JSON.stringify(JSON.parse(await readFile(failurePath, "utf8"))); } catch {}
      }
      throw new Error("Godot reconnect client exited early: " + processRef.child.exitCode + " " + failureDetail + " " + processRef.getOutput());
    }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error("Timed out waiting for Godot reconnect client marker " + markerName + ". Output: " + (processRef?.getOutput() ?? ""));
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, options);
  return { status: response.status, body: await response.json().catch(() => ({})) };
}
function authHeaders(token) { return { "content-type": "application/json", authorization: "Bearer " + token }; }

try {
  await mkdir(clientMarkerDir, { recursive: true });
  await mkdir(clientMarkerDirB, { recursive: true });
  const dbInfo = await pool.query("select current_database() as db, inet_server_addr()::text as host, inet_server_port() as port");
  check(dbInfo.rows[0]?.host === "127.0.0.1/32" || dbInfo.rows[0]?.host === "::1/128", "test is connected to local PostgreSQL", JSON.stringify(dbInfo.rows[0]));
  const required = await pool.query("select to_regclass('public.game_servers') as servers,to_regclass('public.game_server_join_tickets') as tickets,to_regclass('public.game_server_player_state') as positions,to_regclass('public.game_server_world_events') as events,to_regclass('public.game_server_player_connections') as leases,exists(select 1 from information_schema.columns where table_schema='public' and table_name='game_server_world_events' and column_name='event_id') as event_id");
  check(Object.values(required.rows[0]).every(Boolean), "persistent-world migrations 012–018 are present");

  await app.register(jwtPlugin, { secret: config.JWT_SECRET });
  await app.register(websocketPlugin);
  await app.register(gameServerRoutes, { prefix: "/v1/game-servers" });
  await app.register(persistentWorldRealtimeRoutes, { prefix: "/v1" });
  await app.listen({ host: "127.0.0.1", port: 0 });
  const address = app.server.address();
  if (!address || typeof address === "string") throw new Error("local Fastify listener did not bind a TCP port");
  const base = "http://127.0.0.1:" + address.port;
  const wsEndpoint = "ws://127.0.0.1:" + address.port + "/v1/world/realtime";
  worker = fork(new URL("./persistent-world-e2e-worker.mjs", import.meta.url), [], { env: process.env, stdio: ["ignore", "inherit", "inherit", "ipc"] });
  const workerPort = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("second API process startup timed out")), 10000);
    worker.on("message", message => { if (message?.type === "ready") { clearTimeout(timer); resolve(message.port); } });
    worker.once("error", error => { clearTimeout(timer); reject(error); });
    worker.once("exit", code => { clearTimeout(timer); reject(new Error("second API process exited during startup: " + code)); });
  });
  const workerWsEndpoint = "ws://127.0.0.1:" + workerPort + "/v1/world/realtime";
  check(Number.isInteger(workerPort) && workerPort > 0, "second independent API process starts with its own WebSocket listener", "pid " + worker.pid);

  const accounts = await pool.query("insert into accounts(email,password_hash,email_verified,status) values($1,'$argon2id$e2e-placeholder',true,'active'),($2,'$argon2id$e2e-placeholder',true,'active'),($3,'$argon2id$e2e-placeholder',true,'active'),($4,'$argon2id$e2e-placeholder',true,'active') returning id,email", [emailA, emailB, emailC, emailD]);
  accountA = accounts.rows.find(r => r.email === emailA).id;
  accountB = accounts.rows.find(r => r.email === emailB).id;
  accountC = accounts.rows.find(r => r.email === emailC).id;
  accountD = accounts.rows.find(r => r.email === emailD).id;
  const players = await pool.query("insert into players(account_id,name) values($1,$2),($3,$4),($5,$6),($7,$8) returning id,name,account_id", [accountA, playerNameA, accountB, playerNameB, accountC, playerNameC, accountD, playerNameD]);
  playerA = players.rows.find(r => r.account_id === accountA).id;
  playerB = players.rows.find(r => r.account_id === accountB).id;
  playerC = players.rows.find(r => r.account_id === accountC).id;
  playerD = players.rows.find(r => r.account_id === accountD).id;
  check(new Set([playerA, playerB, playerC, playerD]).size === 4, "four isolated test player identities created");

  const versions = await pool.query("select id,token_version from accounts where id=any($1::uuid[])", [[accountA, accountB, accountC, accountD]]);
  const versionFor = accountId => versions.rows.find(r => r.id === accountId).token_version;
  const tokenA = app.jwt.sign({ sub: accountA, playerId: playerA, playerName: playerNameA, tokenVersion: versionFor(accountA) });
  const tokenB = app.jwt.sign({ sub: accountB, playerId: playerB, playerName: playerNameB, tokenVersion: versionFor(accountB) });
  const tokenC = app.jwt.sign({ sub: accountC, playerId: playerC, playerName: playerNameC, tokenVersion: versionFor(accountC) });
  const tokenD = app.jwt.sign({ sub: accountD, playerId: playerD, playerName: playerNameD, tokenVersion: versionFor(accountD) });

  const bootstrap = config.GAME_SERVER_BOOTSTRAP_SECRET;
  let serverToken;
  if (bootstrap) {
    const registration = await requestJson(base + "/v1/game-servers/register", {
      method: "POST", headers: { "content-type": "application/json", "x-server-bootstrap-secret": bootstrap },
      body: JSON.stringify({ serverKey, displayName: "Reverie Local E2E", regionId: "castle_royal_gardens", endpointUrl: wsEndpoint, maxPlayers: 8, buildVersion: "local-e2e" })
    });
    check(registration.status === 201 && registration.body.serverId && registration.body.serverToken, "game server registers through authenticated registration route");
    serverId = registration.body.serverId; serverToken = registration.body.serverToken;
    const heartbeat = await requestJson(base + "/v1/game-servers/" + serverId + "/heartbeat", {
      method: "POST", headers: { "content-type": "application/json", authorization: "Bearer " + serverToken },
      body: JSON.stringify({ status: "online" })
    });
    check(heartbeat.status === 200 && heartbeat.body.status === "accepted", "server heartbeat makes the local server joinable");
  } else {
    serverToken = randomBytes(48).toString("base64url");
    const created = await pool.query("insert into game_servers(server_key,display_name,region_id,status,endpoint_url,server_secret_hash,max_players,build_version,heartbeat_at,started_at) values($1,'Reverie Local E2E','castle_royal_gardens','online',$2,$3,8,'local-e2e',now(),now()) returning id", [serverKey, wsEndpoint, digest(serverToken)]);
    serverId = created.rows[0].id;
    check(true, "local game-server fixture created directly because bootstrap secret is not configured");
  }

  const joinA = await requestJson(base + "/v1/game-servers/" + serverId + "/join", { method: "POST", headers: authHeaders(tokenA), body: "{}" });
  const joinB = await requestJson(base + "/v1/game-servers/" + serverId + "/join", { method: "POST", headers: authHeaders(tokenB), body: "{}" });
  check(joinA.status === 200 && joinA.body.joinTicket && joinA.body.endpointUrl === wsEndpoint, "player A receives a short-lived join ticket");
  check(joinB.status === 200 && joinB.body.joinTicket && joinB.body.endpointUrl === wsEndpoint, "player B receives a separate short-lived join ticket");
  check(joinA.body.joinTicket !== joinB.body.joinTicket, "join tickets are unique per player");

  const consumeUrl = base + "/v1/game-servers/" + serverId + "/consume-ticket";
  const consumed = await requestJson(consumeUrl, { method: "POST", headers: authHeaders(serverToken), body: JSON.stringify({ ticket: joinA.body.joinTicket }) });
  check(consumed.status === 200 && consumed.body.status === "accepted" && consumed.body.playerId === playerA, "server REST admission consumes player A's ticket exactly once");
  const replayRest = await requestJson(consumeUrl, { method: "POST", headers: authHeaders(serverToken), body: JSON.stringify({ ticket: joinA.body.joinTicket }) });
  check(replayRest.status === 401 && replayRest.body.error === "join_ticket_invalid_or_expired", "REST ticket replay is rejected");
  const raceTicket = await requestJson(base + "/v1/game-servers/" + serverId + "/reconnect", { method: "POST", headers: authHeaders(tokenA), body: "{}" });
  check(raceTicket.status === 200 && raceTicket.body.joinTicket, "assigned player A receives a ticket for concurrent redemption testing");
  const raceConnectionA = randomUUID();
  const raceConnectionB = randomUUID();
  const racedRedemptions = await Promise.all([
    requestJson(consumeUrl, { method: "POST", headers: authHeaders(serverToken), body: JSON.stringify({ ticket: raceTicket.body.joinTicket, connectionId: raceConnectionA }) }),
    requestJson(consumeUrl, { method: "POST", headers: authHeaders(serverToken), body: JSON.stringify({ ticket: raceTicket.body.joinTicket, connectionId: raceConnectionB }) })
  ]);
  const acceptedRace = racedRedemptions.filter(result => result.status === 200);
  const rejectedRace = racedRedemptions.filter(result => result.status === 401 && result.body.error === "join_ticket_invalid_or_expired");
  check(acceptedRace.length === 1 && rejectedRace.length === 1,
    "two simultaneous redemptions of one ticket produce exactly one accepted connection",
    JSON.stringify(racedRedemptions.map(result => ({ status: result.status, body: result.body }))));
  const racedConnectionId = acceptedRace[0].body.connectionId;
  const raceLeaseRelease = await requestJson(base + "/v1/game-servers/" + serverId + "/connections/" + racedConnectionId, {
    method: "DELETE", headers: authHeaders(serverToken), body: "{}"
  });
  check(raceLeaseRelease.status === 200, "winning concurrent redemption lease can be released cleanly");

  const reconnect = await requestJson(base + "/v1/game-servers/" + serverId + "/reconnect", { method: "POST", headers: authHeaders(tokenA), body: "{}" });
  check(reconnect.status === 200 && reconnect.body.joinTicket, "assigned player A receives a fresh reconnect ticket after the race");

  const socketUrl = wsEndpoint + "?serverId=" + encodeURIComponent(serverId);
  const connectedA = await connectWithTicket(socketUrl, tokenA, reconnect.body.joinTicket, serverId);
  socketA = connectedA.client;
  check(connectedA.admission.type === "world_joined" && connectedA.admission.playerId === playerA, "player A redeems reconnect ticket on persistent-world WebSocket");
  const workerSocketUrl = workerWsEndpoint + "?serverId=" + encodeURIComponent(serverId);
  const connectedB = await connectWithTicket(workerSocketUrl, tokenB, joinB.body.joinTicket, serverId);
  socketB = connectedB.client;
  check(connectedB.admission.type === "world_joined" && connectedB.admission.playerId === playerB, "player B redeems join ticket on persistent-world WebSocket");
  check(connectedB.admission.members.some(m => m.playerId === playerA) && connectedB.admission.members.some(m => m.playerId === playerB), "authoritative snapshot contains both connected players");

  socketA.send({ type: "position", x: 30, y: 44 });
  const moveA = await socketB.waitFor(m => m.type === "position" && m.playerId === playerA);
  check(moveA.x === 30 && moveA.y === 44 && moveA.sequence > 0, "player A movement reaches player B with committed sequence");
  socketB.send({ type: "position", x: 54, y: 66 });
  const moveB = await socketA.waitFor(m => m.type === "position" && m.playerId === playerB);
  check(moveB.x === 54 && moveB.y === 66 && moveB.sequence > moveA.sequence, "player B movement reaches player A in monotonic sequence order");

  const persisted = await pool.query("select player_id,x,y from game_server_player_state where server_id=$1 and player_id=any($2::uuid[]) order by player_id", [serverId, [playerA, playerB]]);
  check(persisted.rowCount === 2 && persisted.rows.every(r => (r.player_id === playerA && r.x === 30 && r.y === 44) || (r.player_id === playerB && r.x === 54 && r.y === 66)), "both authoritative player positions persist in PostgreSQL");

  await new Promise(resolve => setTimeout(resolve, 35));
  socketA.send({ type: "position", x: 500, y: 500 });
  const rejected = await socketA.waitFor(m => m.type === "rejected" && m.reason === "movement_too_fast");
  check(rejected.reason === "movement_too_fast", "server rejects implausible movement jump");
  const unchanged = await pool.query("select x,y from game_server_player_state where server_id=$1 and player_id=$2", [serverId, playerA]);
  check(unchanged.rows[0]?.x === 30 && unchanged.rows[0]?.y === 44, "rejected movement does not overwrite authoritative position");

  socketA.send({ type: "position", x: 5000, y: 44 });
  const rejectedBounds = await socketA.waitFor(m => m.type === "rejected" && m.reason === "region_bounds");
  check(rejectedBounds.reason === "region_bounds", "server rejects movement outside the assigned region's authored map bounds");
  const afterBoundsReject = await pool.query("select x,y from game_server_player_state where server_id=$1 and player_id=$2", [serverId, playerA]);
  check(afterBoundsReject.rows[0]?.x === 30 && afterBoundsReject.rows[0]?.y === 44, "out-of-region movement leaves the authoritative position unchanged");

  socketA.send({ type: "replay_request", lastSequence: 0 });
  const replayed = await socketA.waitFor(m => m.type === "position" && m.playerId === playerA && m.x === 30 && m.y === 44);
  const replayDone = await socketA.waitFor(m => m.type === "replay_complete");
  check(replayed.sequence > 0 && replayDone.lastSequence >= moveB.sequence, "committed world event stream can be replayed");
  const events = await pool.query("select sequence from game_server_world_events where server_id=$1 and event_type='position' and player_id=any($2::uuid[]) order by sequence", [serverId, [playerA, playerB]]);
  check(events.rowCount >= 2 && Number(events.rows[0].sequence) < Number(events.rows[events.rows.length - 1].sequence), "database event log preserves movement sequence order");

  const leaseTicket = await requestJson(base + "/v1/game-servers/" + serverId + "/reconnect", { method: "POST", headers: authHeaders(tokenA), body: "{}" });
  const connectionId = randomUUID();
  const leaseAdmission = await requestJson(consumeUrl, { method: "POST", headers: authHeaders(serverToken), body: JSON.stringify({ ticket: leaseTicket.body.joinTicket, connectionId }) });
  check(leaseAdmission.status === 200 && leaseAdmission.body.connectionId === connectionId, "standalone server ticket redemption creates a durable connection lease", JSON.stringify({status:leaseAdmission.status,body:leaseAdmission.body,leaseTicketStatus:leaseTicket.status}));
  const leaseRenew = await requestJson(base + "/v1/game-servers/" + serverId + "/connections/" + connectionId, { method: "PUT", headers: authHeaders(serverToken), body: "{}" });
  check(leaseRenew.status === 200 && leaseRenew.body.status === "renewed", "standalone server can renew its PostgreSQL connection lease");
  const leaseRow = await pool.query("select connection_id from game_server_player_connections where connection_id=$1", [connectionId]);
  check(leaseRow.rowCount === 1, "renewed standalone lease remains persisted");
  const leaseRelease = await requestJson(base + "/v1/game-servers/" + serverId + "/connections/" + connectionId, { method: "DELETE", headers: authHeaders(serverToken), body: "{}" });
  const leaseAfterRelease = await pool.query("select connection_id from game_server_player_connections where connection_id=$1", [connectionId]);
  check(leaseRelease.status === 200 && leaseAfterRelease.rowCount === 0, "standalone server releases its lease on disconnect", JSON.stringify({status:leaseRelease.status,body:leaseRelease.body,remaining:leaseAfterRelease.rowCount}));

  const durableEventId = randomUUID();
  const durableEventBody = JSON.stringify({ type: "position", eventId: durableEventId, playerId: playerA, payload: { x: 60, y: 70 } });
  const durableAppend = await requestJson(base + "/v1/game-servers/" + serverId + "/events", { method: "POST", headers: authHeaders(serverToken), body: durableEventBody });
  check(durableAppend.status === 200 && durableAppend.body.sequence > moveB.sequence, "standalone server event append commits a PostgreSQL sequence");
  const durableRelay = await socketB.waitFor(m => m.type === "position" && m.playerId === playerA && m.x === 60 && m.y === 70);
  check(durableRelay.sequence === durableAppend.body.sequence, "PostgreSQL notification relays a dedicated-server event across API processes");
  const durableRetry = await requestJson(base + "/v1/game-servers/" + serverId + "/events", { method: "POST", headers: authHeaders(serverToken), body: durableEventBody });
  const idempotentCount = await pool.query("select count(*)::int as count from game_server_world_events where server_id=$1 and event_id=$2", [serverId, durableEventId]);
  check(durableRetry.status === 200 && durableRetry.body.duplicate === true && durableRetry.body.sequence === durableAppend.body.sequence && idempotentCount.rows[0]?.count === 1, "retrying a committed event ID returns the original sequence without duplicating history");
  const conflictingRetry = await requestJson(base + "/v1/game-servers/" + serverId + "/events", {
    method: "POST", headers: authHeaders(serverToken),
    body: JSON.stringify({ type: "position", eventId: durableEventId, playerId: playerA, payload: { x: 61, y: 70 } })
  });
  check(conflictingRetry.status === 409 && conflictingRetry.body.error === "world_event_id_conflict", "reusing an event ID with different content is rejected");
  const durablePosition = await pool.query("select x,y from game_server_player_state where server_id=$1 and player_id=$2", [serverId, playerA]);
  check(durablePosition.rows[0]?.x === 60 && durablePosition.rows[0]?.y === 70, "standalone event append persists authoritative player position");
  const durableReplay = await requestJson(base + "/v1/game-servers/" + serverId + "/events?after=" + moveB.sequence + "&limit=20", { headers: authHeaders(serverToken) });
  check(durableReplay.status === 200 && durableReplay.body.events.some(event => event.sequence === durableAppend.body.sequence), "standalone server can replay committed events after a restart");
  const futureReplay = await requestJson(base + "/v1/game-servers/" + serverId + "/events?after=999999999", { headers: authHeaders(serverToken) });
  check(futureReplay.status === 409 && futureReplay.body.error === "replay_cursor_ahead", "durable replay rejects cursors beyond the committed event sequence");

  const reused = await connectWithTicket(socketUrl, tokenB, joinB.body.joinTicket, serverId);
  socketReuse = reused.client;
  check(reused.admission.type === "rejected" && reused.admission.reason === "join_ticket_invalid_or_expired", "WebSocket rejects an already redeemed ticket");

  const blockedDisconnect = await requestJson(base + "/v1/game-servers/" + serverId + "/disconnect", { method: "POST", headers: authHeaders(serverToken), body: JSON.stringify({ playerId: playerA }) });
  check(blockedDisconnect.status === 409 && blockedDisconnect.body.error === "player_still_connected", "disconnect cleanup refuses to remove a player while a durable connection lease is active");
  socketA.close(); socketB.close();
  for (let i = 0; i < 30; i++) {
    const activeLeases = await pool.query("select count(*)::int as count from game_server_player_connections where server_id=$1 and lease_expires_at>now()", [serverId]);
    if (activeLeases.rows[0].count === 0) break;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  let overflowAppends = 0;
  for (let offset = 0; offset < 205; offset += 20) {
    const batch = Array.from({ length: Math.min(20, 205 - offset) }, () =>
      requestJson(base + "/v1/game-servers/" + serverId + "/events", {
        method: "POST", headers: authHeaders(serverToken),
        body: JSON.stringify({ type: "emote", eventId: randomUUID(), playerId: playerA, payload: { emoteId: "wave" } })
      })
    );
    const results = await Promise.all(batch);
    overflowAppends += results.filter(result => result.status === 200).length;
  }
  check(overflowAppends === 205, "event log accepts more than one replay window of durable events");
  const overflowReplay = await requestJson(base + "/v1/game-servers/" + serverId + "/events?after=0", { headers: authHeaders(serverToken) });
  check(overflowReplay.status === 200 && overflowReplay.body.requiresSnapshot === true && overflowReplay.body.events.length === 200 &&
    overflowReplay.body.positions.some(position => position.playerId === playerA) && overflowReplay.body.positions.some(position => position.playerId === playerB),
    "replay-window overflow returns a bounded event page and authoritative position snapshot");

  const expiryTicket = await requestJson(base + "/v1/game-servers/" + serverId + "/reconnect", { method: "POST", headers: authHeaders(tokenA), body: "{}" });
  const expiredConnectionId = randomUUID();
  const expiryLease = await requestJson(base + "/v1/game-servers/" + serverId + "/consume-ticket", {
    method: "POST", headers: authHeaders(serverToken),
    body: JSON.stringify({ ticket: expiryTicket.body.joinTicket, connectionId: expiredConnectionId })
  });
  await pool.query("update game_server_player_connections set lease_expires_at=now()-interval '1 second' where connection_id=$1", [expiredConnectionId]);
  const expiredDisconnect = await requestJson(base + "/v1/game-servers/" + serverId + "/disconnect", { method: "POST", headers: authHeaders(serverToken), body: JSON.stringify({ playerId: playerA }) });
  const expiredLeaseRemaining = await pool.query("select 1 from game_server_player_connections where connection_id=$1", [expiredConnectionId]);
  check(expiryLease.status === 200 && expiredDisconnect.status === 200 && expiredDisconnect.body.status === "disconnected" && expiredLeaseRemaining.rowCount === 0,
    "expired connection leases are reaped before disconnect and assignment cleanup");
  const disconnectA = await requestJson(base + "/v1/game-servers/" + serverId + "/disconnect", { method: "POST", headers: authHeaders(serverToken), body: JSON.stringify({ playerId: playerA }) });
  const disconnectB = await requestJson(base + "/v1/game-servers/" + serverId + "/disconnect", { method: "POST", headers: authHeaders(serverToken), body: JSON.stringify({ playerId: playerB }) });
  check(disconnectA.status === 200 && disconnectA.body.status === "already_disconnected" && disconnectA.body.sequence === expiredDisconnect.body.sequence,
    "repeated disconnect returns the original committed player_left event sequence");
  check(disconnectB.status === 200 && disconnectB.body.sequence > disconnectA.body.sequence, "second player disconnect receives the next committed event sequence");
  const departed = await pool.query("select player_id from game_server_players where server_id=$1 and player_id=any($2::uuid[])", [serverId, [playerA, playerB]]);
  const leftEvents = await pool.query("select count(*)::int as count from game_server_world_events where server_id=$1 and event_type='player_left' and player_id=any($2::uuid[])", [serverId, [playerA, playerB]]);
  check(departed.rowCount === 0 && leftEvents.rows[0].count === 2, "disconnect atomically removes assignments and persists both player_left events");
  const departedPositions = await pool.query("select player_id from game_server_player_state where server_id=$1 and player_id=any($2::uuid[])", [serverId, [playerA, playerB]]);
  check(departedPositions.rowCount === 0, "disconnected players are excluded from authoritative recovery snapshots");

  if (bootstrap) {
    const offline = await requestJson(base + "/v1/game-servers/" + serverId + "/heartbeat", {
      method: "POST", headers: authHeaders(serverToken), body: JSON.stringify({ status: "offline" })
    });
    check(offline.status === 200 && offline.body.status === "accepted", "server shutdown marks the registered instance offline");
    const staleConnectionId = randomUUID();
    await pool.query("insert into game_server_players(server_id,player_id) values($1,$2) on conflict(server_id,player_id) do nothing", [serverId, playerA]);
    await pool.query("insert into game_server_player_connections(connection_id,server_id,player_id,lease_expires_at) values($1,$2,$3,now()+interval '45 seconds')", [staleConnectionId, serverId, playerA]);
    const restarted = await requestJson(base + "/v1/game-servers/register", {
      method: "POST", headers: { "content-type": "application/json", "x-server-bootstrap-secret": bootstrap },
      body: JSON.stringify({ serverKey, displayName: "Reverie Local E2E Restart", regionId: "castle_royal_gardens", endpointUrl: wsEndpoint, maxPlayers: 8, buildVersion: "local-e2e-restart" })
    });
    const staleLeaseAfterRestart = await pool.query("select 1 from game_server_player_connections where connection_id=$1", [staleConnectionId]);
    check(restarted.status === 201 && restarted.body.serverId === serverId && restarted.body.serverToken !== serverToken && staleLeaseAfterRestart.rowCount === 0,
      "server restart reuses its persistent identity, rotates its bearer token, and clears leases owned by the previous process",
      JSON.stringify({ status: restarted.status, staleLeaseRows: staleLeaseAfterRestart.rowCount }));
    await pool.query("delete from game_server_players where server_id=$1 and player_id=$2", [serverId, playerA]);
    const oldToken = await requestJson(base + "/v1/game-servers/" + serverId + "/heartbeat", {
      method: "POST", headers: authHeaders(serverToken), body: JSON.stringify({ status: "online" })
    });
    check(oldToken.status === 401, "previous process token is invalidated after restart registration");
    serverToken = restarted.body.serverToken;
    const restartedHeartbeat = await requestJson(base + "/v1/game-servers/" + serverId + "/heartbeat", {
      method: "POST", headers: authHeaders(serverToken), body: JSON.stringify({ status: "online" })
    });
    check(restartedHeartbeat.status === 200 && restartedHeartbeat.body.status === "accepted", "restarted server can resume heartbeats with its rotated token");
  }
  if (bootstrap) {
    const godotPort = await allocateTcpPort();
    const godotServer = startGodotDedicatedServer(base, bootstrap, dedicatedServerKey, godotPort);
    dedicatedProcess = godotServer.child;
    let registered = null;
    for (let i = 0; i < 120; i++) {
      if (dedicatedProcess.exitCode !== null) throw new Error("Godot dedicated server exited during startup: " + godotServer.getOutput());
      const q = await pool.query("select id,status,endpoint_url from game_servers where server_key=$1", [dedicatedServerKey]);
      if (q.rows[0]?.status === "online" && q.rows[0]?.endpoint_url === godotServer.endpoint) { registered = q.rows[0]; break; }
      await new Promise(resolve => setTimeout(resolve, 250));
    }
    check(Boolean(registered), "real headless Godot dedicated server registers, recovers PostgreSQL state, and becomes joinable", godotServer.getOutput().slice(-1200));
    dedicatedServerId = registered.id;

    const godotJoinA = await requestJson(base + "/v1/game-servers/" + dedicatedServerId + "/join", { method: "POST", headers: authHeaders(tokenA), body: "{}" });
    const godotJoinB = await requestJson(base + "/v1/game-servers/" + dedicatedServerId + "/join", { method: "POST", headers: authHeaders(tokenB), body: "{}" });
    check(godotJoinA.status === 200 && godotJoinB.status === 200, "two players receive tickets for the live Godot regional server",
      JSON.stringify({ playerA: { status: godotJoinA.status, body: godotJoinA.body }, playerB: { status: godotJoinB.status, body: godotJoinB.body } }));
    const godotA = await connectDedicatedWithTicket(godotServer.endpoint, godotJoinA.body.joinTicket);
    dedicatedSocketA = godotA.client;
    const godotB = await connectDedicatedWithTicket(godotServer.endpoint, godotJoinB.body.joinTicket);
    dedicatedSocketB = godotB.client;
    const godotJoinC = await requestJson(base + "/v1/game-servers/" + dedicatedServerId + "/join", { method: "POST", headers: authHeaders(tokenC), body: "{}" });
    const godotJoinD = await requestJson(base + "/v1/game-servers/" + dedicatedServerId + "/join", { method: "POST", headers: authHeaders(tokenD), body: "{}" });
    check(godotJoinC.status === 200 && godotJoinD.status === 200, "players C and D receive independent tickets for the same four-player regional server");
    const godotC = await connectDedicatedWithTicket(godotServer.endpoint, godotJoinC.body.joinTicket);
    dedicatedSocketC = godotC.client;
    const godotD = await connectDedicatedWithTicket(godotServer.endpoint, godotJoinD.body.joinTicket);
    dedicatedSocketD = godotD.client;
    const fourPlayerSnapshot = new Set(godotD.admission.members.map(member => member.playerId));
    check(godotA.admission.type === "world_joined" && godotA.admission.playerId === playerA &&
      godotB.admission.type === "world_joined" && godotB.admission.playerId === playerB &&
      godotC.admission.type === "world_joined" && godotC.admission.playerId === playerC &&
      godotD.admission.type === "world_joined" && godotD.admission.playerId === playerD &&
      [playerA, playerB, playerC, playerD].every(playerId => fourPlayerSnapshot.has(playerId)),
      "Godot admits four independent players and the fourth snapshot contains the entire connected party");
    const godotLeases = await pool.query("select count(*)::int as count from game_server_player_connections where server_id=$1 and lease_expires_at>now()", [dedicatedServerId]);
    check(godotLeases.rows[0]?.count === 4, "four-player Godot admission creates four PostgreSQL connection leases");
    const initialLeaseExpiry = await pool.query("select min(lease_expires_at) as expiry from game_server_player_connections where server_id=$1", [dedicatedServerId]);
    await new Promise(resolve => setTimeout(resolve, 16000));
    const renewedLeaseExpiry = await pool.query("select min(lease_expires_at) as expiry from game_server_player_connections where server_id=$1", [dedicatedServerId]);
    check(new Date(renewedLeaseExpiry.rows[0].expiry).getTime() - new Date(initialLeaseExpiry.rows[0].expiry).getTime() > 5000, "all four live Godot connection leases renew on the 15-second timer");

    await new Promise(resolve => setTimeout(resolve, 120));
    dedicatedSocketA.send({ type: "position", x: 20, y: 30 });
    const godotMoveA = await dedicatedSocketB.waitFor(m => m.type === "position" && m.playerId === playerA && m.x === 20 && m.y === 30, 10000);
    dedicatedSocketB.send({ type: "position", x: 40, y: 60 });
    const godotMoveB = await dedicatedSocketA.waitFor(m => m.type === "position" && m.playerId === playerB && m.x === 40 && m.y === 60, 10000);
    dedicatedSocketC.send({ type: "position", x: 80, y: 90 });
    const godotMoveC = await dedicatedSocketD.waitFor(m => m.type === "position" && m.playerId === playerC && m.x === 80 && m.y === 90, 10000);
    dedicatedSocketD.send({ type: "position", x: 100, y: 110 });
    const godotMoveD = await dedicatedSocketA.waitFor(m => m.type === "position" && m.playerId === playerD && m.x === 100 && m.y === 110, 10000);
    const godotPositions = await pool.query("select player_id,x,y from game_server_player_state where server_id=$1 and player_id=any($2::uuid[])", [dedicatedServerId, [playerA, playerB, playerC, playerD]]);
    check(godotMoveA.sequence > 0 && godotMoveB.sequence > godotMoveA.sequence && godotMoveC.sequence > godotMoveB.sequence &&
      godotMoveD.sequence > godotMoveC.sequence && godotPositions.rowCount === 4,
      "four-player movement is committed to PostgreSQL and relayed in one monotonic sequence");
    const godotEvents = await pool.query("select count(*)::int as count from game_server_world_events where server_id=$1 and event_type in('player_joined','position')", [dedicatedServerId]);
    check(godotEvents.rows[0]?.count >= 8, "all four player joins and four movement events are stored in the shared durable event log");

    dedicatedSocketA.send({ type: "replay_request", lastSequence: 0 });
    const godotReplay = await dedicatedSocketA.waitFor(m => m.type === "position" && m.playerId === playerA && m.x === 20 && m.y === 30, 10000);
    const godotReplayDone = await dedicatedSocketA.waitFor(m => m.type === "replay_complete", 10000);
    check(godotReplay.sequence === godotMoveA.sequence && godotReplayDone.lastSequence >= godotMoveD.sequence, "Godot replay requests are served from PostgreSQL rather than process memory");

    const dedicatedBaseSequence = godotMoveD.sequence;
    for (let i = 0; i < 205; i++) {
      dedicatedSocketA.send({ type: "position", x: 20 + (i % 5), y: 30 + (i % 3) });
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    const finalOverflowMove = await dedicatedSocketB.waitFor(m => m.type === "position" && m.playerId === playerA && m.x === 24 && m.y === 30, 15000);
    const overflowSequence = Number((await pool.query("select next_event_sequence from game_servers where id=$1", [dedicatedServerId])).rows[0].next_event_sequence);
    check(finalOverflowMove.sequence > dedicatedBaseSequence && overflowSequence - dedicatedBaseSequence >= 205,
      "live Godot movement fills more than one durable replay window before restart");

    dedicatedSocketA.close(); dedicatedSocketB.close(); dedicatedSocketC.close(); dedicatedSocketD.close();
    for (let i = 0; i < 50; i++) {
      const leases = await pool.query("select count(*)::int as count from game_server_player_connections where server_id=$1 and lease_expires_at>now()", [dedicatedServerId]);
      if (leases.rows[0].count === 0) break;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    var releasedLeaseCount = await pool.query("select count(*)::int as count from game_server_player_connections where server_id=$1 and lease_expires_at>now()", [dedicatedServerId]);
    check(releasedLeaseCount.rows[0]?.count === 0, "Godot releases PostgreSQL connection leases when player sockets close");
    const clientTicket = await requestJson(base + "/v1/game-servers/" + dedicatedServerId + "/reconnect", { method: "POST", headers: authHeaders(tokenA), body: "{}" });
    const clientTicketB = await requestJson(base + "/v1/game-servers/" + dedicatedServerId + "/reconnect", { method: "POST", headers: authHeaders(tokenB), body: "{}" });
    check(clientTicket.status === 200 && Boolean(clientTicket.body.joinTicket) && clientTicketB.status === 200 && Boolean(clientTicketB.body.joinTicket),
      "both players receive fresh authenticated reconnect tickets before the regional interruption");
    clientProcess = startGodotReconnectClient(base, tokenA, dedicatedServerId, clientTicket.body.joinTicket, godotServer.endpoint, playerA, clientMarkerDir, 24, 30, playerB, 40, 60, clientMarkerDirB);
    clientProcessB = startGodotReconnectClient(base, tokenB, dedicatedServerId, clientTicketB.body.joinTicket, godotServer.endpoint, playerB, clientMarkerDirB, 40, 60, playerA, 24, 30, clientMarkerDir);
    await Promise.all([
      waitForMarker("initial.json", 20000),
      waitForMarker("initial.json", 20000, () => true, clientMarkerDirB, clientProcessB)
    ]);
    check(true, "two independent production Godot MultiplayerGateway clients redeem tickets and join the same live regional server");
    await pool.query("update game_servers set status='offline',heartbeat_at=NULL,stopped_at=now() where id=$1", [dedicatedServerId]);
    const firstExit = new Promise(resolve => dedicatedProcess.once("exit", resolve));
    dedicatedProcess.kill();
    await Promise.race([firstExit, new Promise(resolve => setTimeout(resolve, 4000))]);
    if (dedicatedProcess.exitCode === null) dedicatedProcess.kill();
    dedicatedProcess = null;
    await pool.query(
      "update game_server_world_state set state=jsonb_set(state,'{eventSequence}',to_jsonb($2::bigint),true) where server_id=$1",
      [dedicatedServerId, dedicatedBaseSequence]
    );

    await Promise.all([
      waitForMarker("reconnecting.json", 15000, marker => Number(marker.attempt) >= 2),
      waitForMarker("reconnecting.json", 15000, marker => Number(marker.attempt) >= 2, clientMarkerDirB, clientProcessB)
    ]);
    check(true, "both production Godot clients detect the same regional process loss and retry fresh reconnect tickets while it is offline");

    const restartedPort = await allocateTcpPort();
    const restartedGodot = startGodotDedicatedServer(base, bootstrap, dedicatedServerKey, restartedPort);
    dedicatedProcess = restartedGodot.child;
    let restartedRow = null;
    for (let i = 0; i < 120; i++) {
      if (dedicatedProcess.exitCode !== null) throw new Error("Godot dedicated server failed after restart: " + restartedGodot.getOutput());
      const q = await pool.query("select id,status,endpoint_url from game_servers where server_key=$1", [dedicatedServerKey]);
      if (q.rows[0]?.status === "online" && q.rows[0]?.endpoint_url === restartedGodot.endpoint) { restartedRow = q.rows[0]; break; }
      await new Promise(resolve => setTimeout(resolve, 250));
    }
    check(Boolean(restartedRow) && restartedRow.id === dedicatedServerId, "Godot process restart reuses the same registered server identity");
    const [clientRecovered, clientRecoveredB] = await Promise.all([
      waitForMarker("recovered.json", 35000),
      waitForMarker("recovered.json", 35000, () => true, clientMarkerDirB, clientProcessB)
    ]);
    const [movementA, movementB] = await Promise.all([
      waitForMarker("movement.json", 10000),
      waitForMarker("movement.json", 10000, () => true, clientMarkerDirB, clientProcessB)
    ]);
    check(movementA.ok === true && movementB.ok === true &&
      movementA.after.x >= movementA.before.x + 15 && movementB.after.x >= movementB.before.x + 15 &&
      movementA.collisionShape === true && movementB.collisionShape === true &&
      movementA.slideCollisions >= 1 && movementB.slideCollisions >= 1 &&
      (movementA.worldCollisionMask & 1) !== 0 && (movementB.worldCollisionMask & 1) !== 0 &&
      Math.hypot(movementA.blockedAfter.x - movementA.contact.x, movementA.blockedAfter.y - movementA.contact.y) <= 2 &&
      Math.hypot(movementB.blockedAfter.x - movementB.contact.x, movementB.blockedAfter.y - movementB.contact.y) <= 2 &&
      Math.hypot(movementA.remote.x - movementB.after.x, movementA.remote.y - movementB.after.y) <= 3 &&
      Math.hypot(movementB.remote.x - movementA.after.x, movementB.remote.y - movementA.after.y) <= 3,
      "actual collision-aware player movement is relayed to the other visible GameScreen client in both directions",
      JSON.stringify({ playerA: movementA, playerB: movementB }));
    check(clientRecovered.ok === true && clientRecoveredB.ok === true &&
      Math.hypot(clientRecovered.x - movementA.after.x, clientRecovered.y - movementA.after.y) <= 0.1 &&
      Math.hypot(clientRecoveredB.x - movementB.after.x, clientRecoveredB.y - movementB.after.y) <= 0.1,
      "both production GameScreen clients restore their own authoritative positions after reconnect and live movement",
      JSON.stringify({ playerA: clientRecovered, playerB: clientRecoveredB }));
    const [remoteAvatarA, remoteAvatarB] = await Promise.all([
      waitForMarker("remote-avatar.json", 5000),
      waitForMarker("remote-avatar.json", 5000, () => true, clientMarkerDirB, clientProcessB)
    ]);
    check(remoteAvatarA.ok && remoteAvatarA.remotePlayerId === playerB && Math.abs(remoteAvatarA.x - 40) <= 0.1 && Math.abs(remoteAvatarA.y - 60) <= 0.1 &&
      remoteAvatarB.ok && remoteAvatarB.remotePlayerId === playerA && Math.abs(remoteAvatarB.x - 24) <= 0.1 && Math.abs(remoteAvatarB.y - 30) <= 0.1,
      "each production Godot client recreates the other real client's remote avatar at the correct restored coordinates",
      JSON.stringify({ playerASeesB: remoteAvatarA, playerBSeesA: remoteAvatarB }));
    const snapshotReconciliation = await waitForMarker("snapshot-reconciliation.json", 5000);
    check(snapshotReconciliation.ok === true && snapshotReconciliation.remoteCreated === true && snapshotReconciliation.duplicateIgnored === true && snapshotReconciliation.staleSnapshotIgnored === true && snapshotReconciliation.absentRemoteRemoved === true,
      "production co-op sync reconciles remote teammates, ignores duplicate and stale updates, and removes absent party members", JSON.stringify(snapshotReconciliation));
    const recoveredDatabasePositions = await pool.query(
      "select player_id,x,y from game_server_player_state where server_id=$1 and player_id=any($2::uuid[])",
      [dedicatedServerId, [playerA, playerB]]
    );
    const recoveredAState = recoveredDatabasePositions.rows.find(row => row.player_id === playerA);
    const recoveredBPosition = recoveredDatabasePositions.rows.find(row => row.player_id === playerB);
    const liveRecoveryLeases = await pool.query(
      "select count(distinct player_id)::int as count from game_server_player_connections where server_id=$1 and player_id=any($2::uuid[]) and lease_expires_at>now()",
      [dedicatedServerId, [playerA, playerB]]
    );
    check(recoveredDatabasePositions.rowCount === 2 &&
      Math.hypot(Number(recoveredAState?.x) - movementA.after.x, Number(recoveredAState?.y) - movementA.after.y) <= 3 &&
      Math.hypot(Number(recoveredBPosition?.x) - movementB.after.x, Number(recoveredBPosition?.y) - movementB.after.y) <= 3 &&
      liveRecoveryLeases.rows[0]?.count === 2,
      "both moved GameScreen players retain their final authoritative positions and live PostgreSQL leases",
      JSON.stringify({ recoveredAState, recoveredBPosition, movementA, movementB, liveLeases: liveRecoveryLeases.rows[0]?.count }));

    dedicatedSocketA.close(); dedicatedSocketB.close();
    await pool.query("update game_servers set status='offline',heartbeat_at=NULL,stopped_at=now() where id=$1", [dedicatedServerId]);
    const secondExit = new Promise(resolve => dedicatedProcess.once("exit", resolve));
    dedicatedProcess.kill();
    await Promise.race([secondExit, new Promise(resolve => setTimeout(resolve, 4000))]);
    if (dedicatedProcess.exitCode === null) dedicatedProcess.kill();
    dedicatedProcess = null;
  }
  console.log("E2E_SUMMARY " + checks.filter(c => c.ok).length + " passed, " + checks.filter(c => !c.ok).length + " failed");
  finished = true;
} catch (error) {
  console.error("E2E_FAILURE", error?.stack ?? error);
  process.exitCode = 1;
} finally {
  socketReuse?.close(); socketA?.close(); socketB?.close(); dedicatedSocketA?.close(); dedicatedSocketB?.close(); dedicatedSocketC?.close(); dedicatedSocketD?.close();
  if (clientProcess?.child && clientProcess.child.exitCode === null) clientProcess.child.kill();
  if (clientProcessB?.child && clientProcessB.child.exitCode === null) clientProcessB.child.kill();
  if (dedicatedProcess && dedicatedProcess.exitCode === null) dedicatedProcess.kill();
  if (worker && worker.exitCode === null) {
    const exited = new Promise(resolve => worker.once("exit", resolve));
    try { worker.send({ type: "stop" }); } catch {}
    const stopped = await Promise.race([exited.then(() => true), new Promise(resolve => setTimeout(() => resolve(false), 3000))]);
    if (!stopped && worker.exitCode === null) {
      worker.kill();
      await Promise.race([exited, new Promise(resolve => setTimeout(resolve, 1000))]);
    }
  }
  if (serverId) await pool.query("delete from game_servers where id=$1", [serverId]).catch(e => console.error("server cleanup failed", e.message));
  if (dedicatedServerId) await pool.query("delete from game_servers where id=$1", [dedicatedServerId]).catch(e => console.error("Godot server cleanup failed", e.message));
  const ids = [accountA, accountB, accountC, accountD].filter(Boolean);
  if (ids.length) await pool.query("delete from accounts where id=any($1::uuid[])", [ids]).catch(e => console.error("account cleanup failed", e.message));
  if (serverId) {
    const residue = await pool.query(
      "select (select count(*)::int from game_servers where server_key=$1) as servers,(select count(*)::int from accounts where email=any($2::text[])) as accounts,(select count(*)::int from game_server_join_tickets where server_id=$3) as tickets,(select count(*)::int from game_server_player_state where server_id=$3) as positions,(select count(*)::int from game_server_world_events where server_id=$3) as events,(select count(*)::int from game_server_player_connections where server_id=$3) as connections",
      [serverKey, [emailA, emailB, emailC, emailD], serverId]
    ).catch(error => { console.error("cleanup verification failed", error.message); return null; });
    const clean = residue !== null && Object.values(residue.rows[0]).every(value => Number(value) === 0);
    if (!clean) { console.error("E2E_CLEANUP_VERIFICATION_FAILED", residue?.rows[0] ?? null); finished = false; }
    else console.log("E2E_CLEANUP_VERIFIED " + JSON.stringify(residue.rows[0]));
  }
  await rm(clientMarkerDir, { recursive: true, force: true }).catch(e => console.error("client marker cleanup failed", e.message));
  await rm(clientMarkerDirB, { recursive: true, force: true }).catch(e => console.error("second client marker cleanup failed", e.message));
  await app.close().catch(e => console.error("Fastify close failed", e.message));
  await pool.end().catch(() => {});
  if (finished) console.log("E2E_CLEANUP complete; temporary server and player accounts removed");
  process.exit(finished ? 0 : 1);
}
