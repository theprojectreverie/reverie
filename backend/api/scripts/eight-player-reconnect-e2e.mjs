import { randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import { createServer, createConnection } from "node:net";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import websocket from "@fastify/websocket";
import WebSocket from "ws";
import { config } from "../src/config.ts";
import { pool } from "../src/db.ts";
import { gameServerRoutes } from "../src/routes/game-servers.ts";
import { persistentWorldRealtimeRoutes } from "../src/routes/persistent-world-realtime.ts";

const assert = (ok, label, detail = "") => {
  console.log((ok ? "PASS " : "FAIL ") + label + (detail ? " — " + detail : ""));
  if (!ok) throw new Error(label + (detail ? ": " + detail : ""));
};
const suffix = randomBytes(6).toString("hex");
const serverKey = "reverie-eight-player-" + suffix;
const emails = Array.from({ length: 8 }, (_, i) => `reverie-eight-${suffix}-${i}@example.test`);
const names = Array.from({ length: 8 }, (_, i) => `Eight${i}${suffix}`.slice(0, 20));
const app = Fastify({ logger: false });
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
    env: { ...process.env, REVERIE_API_BASE_URL: base, REVERIE_SERVER_BOOTSTRAP_SECRET: bootstrap, REVERIE_SERVER_KEY: key, REVERIE_SERVER_NAME: "Reverie Eight Player E2E", REVERIE_SERVER_REGION: "castle_royal_gardens", REVERIE_SERVER_HOST: "127.0.0.1", REVERIE_SERVER_PORT: String(port), REVERIE_SERVER_MAX_PLAYERS: "8", REVERIE_SERVER_ENDPOINT: endpoint },
    stdio: ["ignore", "pipe", "pipe"]
  });
  let output = "";
  child.stdout.on("data", chunk => output += chunk.toString());
  child.stderr.on("data", chunk => output += chunk.toString());
  return { child, endpoint, getOutput: () => output };
}
async function connectWithTicket(endpoint, token, ticket, expectedServerId) {
  const socket = new WebSocket(endpoint, { headers: { authorization: "Bearer " + token } });
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
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("WebSocket open timeout")), 10000);
    socket.once("open", () => { clearTimeout(timer); resolve(); });
    socket.once("error", error => { clearTimeout(timer); reject(error); });
  });
  const challenge = await waitFor(message => message.type === "ticket_required");
  assert(challenge.serverId === expectedServerId, "socket challenge is scoped to the registered world");
  socket.send(JSON.stringify({ type: "join_ticket", ticket, lastEventSequence: 0 }));
  const admission = await waitFor(message => message.type === "world_joined" || message.type === "rejected");
  if (admission.type !== "world_joined") throw new Error("Player admission rejected: " + JSON.stringify(admission));
  return { socket, admission, waitFor };
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
    if (row.rows[0]?.id === expectedId && row.rows[0]?.status === "online" && row.rows[0]?.endpoint_url === expectedEndpoint && row.rows[0]?.max_players === 8) return row.rows[0];
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
  assert(playerRows.length === 8, "eight isolated player identities are created");
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
    if (row.rows[0]?.status === "online" && row.rows[0]?.endpoint_url === endpoint && row.rows[0]?.max_players === 8) {
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
  assert(new Set(joinTickets.map(result => result.body.joinTicket)).size === 8, "eight player tickets are unique");
  clients = await Promise.all(joinTickets.map((result, index) => connectWithTicket(endpoint, tokens[index], result.body.joinTicket, serverId)));
  const firstSnapshot = clients.reduce((best, client) => client.admission.members.length > best.members.length ? client.admission : best, clients[0].admission);
  const firstMemberIds = new Set(firstSnapshot.members.map(member => member.playerId));
  assert(clients.every(client => client.admission.type === "world_joined"), "all eight concurrent WebSocket admissions succeed");
  assert(firstSnapshot.members.length === 8 && playerRows.every(player => firstMemberIds.has(player.id)), "latest concurrent admission snapshot contains all eight players");
  await waitForLeaseCount(8);
  assert(true, "eight durable PostgreSQL connection leases are active");

  // The dedicated server intentionally ignores movement arriving within 40 ms
  // of admission; wait past that guard before the first authoritative proposals.
  await new Promise(resolve => setTimeout(resolve, 100));
  await Promise.all(clients.map(client => {
    client.socket.send(JSON.stringify({ type: "position", x: 20, y: 30 }));
    return Promise.resolve();
  }));
  await waitForPositionCount(8);
  const persisted = await pool.query("select count(*)::int as count from game_server_player_state where server_id=$1 and player_id=any($2::uuid[])", [serverId, playerRows.map(row => row.id)]);
  assert(persisted.rows[0].count === 8, "all eight players persist authoritative positions");

  clients.forEach(client => client.socket.terminate());
  await waitForLeaseCount(0);
  assert(true, "simultaneous eight-client disconnect releases every connection lease");

  const reconnectTickets = await Promise.all(tokens.map(token => requestJson(base + "/v1/game-servers/" + serverId + "/reconnect", {
    method: "POST", headers: authHeaders(token), body: "{}"
  })));
  assert(reconnectTickets.every(result => result.status === 200 && result.body.joinTicket), "all eight clients obtain fresh reconnect tickets during the grace window");
  const reconnectClients = await Promise.all(reconnectTickets.map((result, index) => connectWithTicket(endpoint, tokens[index], result.body.joinTicket, serverId)));
  clients = reconnectClients;
  const recoveredSnapshot = reconnectClients.reduce((best, client) => client.admission.members.length > best.members.length ? client.admission : best, reconnectClients[0].admission);
  const recoveredIds = new Set(recoveredSnapshot.members.map(member => member.playerId));
  assert(reconnectClients.every(client => client.admission.type === "world_joined"), "eight-client reconnect storm is admitted successfully");
  assert(recoveredSnapshot.members.length === 8 && playerRows.every(player => recoveredIds.has(player.id)), "reconnect snapshot restores the complete eight-player party");
  await waitForLeaseCount(8);
  const recoveredPositions = await pool.query("select count(*)::int as count from game_server_player_state where server_id=$1 and player_id=any($2::uuid[])", [serverId, playerRows.map(row => row.id)]);
  assert(recoveredPositions.rows[0].count === 8, "all eight authoritative positions survive the reconnect storm");

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
  const restartClients = await Promise.all(restartTickets.map((result, index) => connectWithTicket(endpoint, tokens[index], result.body.joinTicket, serverId)));
  clients = restartClients;
  assert(restartClients.every(client => client.admission.type === "world_joined"), "all eight clients are admitted by the replacement process");
  const restartSnapshot = restartClients.reduce((best, client) => client.admission.members.length > best.members.length ? client.admission : best, restartClients[0].admission);
  const restartMemberIds = new Set(restartSnapshot.members.map(member => member.playerId));
  assert(restartSnapshot.members.length === 8 && playerRows.every(player => restartMemberIds.has(player.id)), "replacement process snapshot restores all eight party members");
  await waitForLeaseCount(8);
  const restartPositions = await pool.query("select count(*)::int as count from game_server_player_state where server_id=$1 and player_id=any($2::uuid[])", [serverId, playerRows.map(row => row.id)]);
  assert(restartPositions.rows[0].count === 8, "all eight durable player positions survive the regional process restart");

  clients.forEach(client => client.socket.terminate());
  clients = [];
  await waitForLeaseCount(0);
  await pool.query("update game_servers set status='offline',heartbeat_at=NULL,stopped_at=now() where id=$1", [serverId]);
  await stopGodot(port);
  assert(true, "replacement eight-player test server stopped cleanly");
  finished = true;
} catch (error) {
  console.error("EIGHT_PLAYER_E2E_FAILURE", error?.stack ?? error);
  process.exitCode = 1;
} finally {
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
    if (clean) console.log("EIGHT_PLAYER_CLEANUP_VERIFIED " + JSON.stringify(residue.rows[0]));
    else { console.error("EIGHT_PLAYER_CLEANUP_FAILED", residue?.rows[0] ?? null); finished = false; }
  }
  await app.close().catch(() => {});
  await pool.end().catch(() => {});
  if (finished) console.log("EIGHT_PLAYER_E2E_CLEANUP complete");
  process.exit(finished ? 0 : 1);
}
