import { readFile, access } from "node:fs/promises";
import { createHash, randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

const envText = await readFile(new URL("../.env", import.meta.url), "utf8");
for (const line of envText.split(/\r?\n/)) {
  const match = line.match(/^\s*([A-Z0-9_]+)=(.*)\s*$/);
  if (match && !process.env[match[1]]) process.env[match[1]] = match[2].replace(/^[\"']|[\"']$/g, "");
}
const [{ default: Fastify }, { default: jwtPlugin }, { default: websocketPlugin }, { config }, { pool }, { gameServerRoutes }, { persistentWorldRealtimeRoutes }, { default: WebSocket }] = await Promise.all([
  import("fastify"), import("@fastify/jwt"), import("@fastify/websocket"),
  import("../src/config.ts"), import("../src/db.ts"),
  import("../src/routes/game-servers.ts"), import("../src/routes/persistent-world-realtime.ts"),
  import("ws")
]);

const projectRoot = resolve(fileURLToPath(new URL("../../../", import.meta.url)));
const godotExe = process.env.GODOT_CONSOLE_EXE || "C:\\Users\\quoth\\Downloads\\Godot_4.7.2_runtime\\Godot_v4.7.2-stable_win64_console.exe";
const bootstrapSecret = config.GAME_SERVER_BOOTSTRAP_SECRET;
if (!bootstrapSecret || bootstrapSecret.length < 32) throw new Error("GAME_SERVER_BOOTSTRAP_SECRET must be configured for the dedicated-server E2E test.");
await access(godotExe);

const app = Fastify({ logger: false });
let serverId = "";
let accountIds = [];
let godot = null;
let socketA = null;
let socketB = null;
let socketA2 = null;
let socketB2 = null;
let godotOutput = "";
let finished = false;
const suffix = randomBytes(6).toString("hex");
const serverKey = "reverie-dedicated-e2e-" + suffix;
const emailA = "dedicated-e2e-a-" + suffix + "@example.test";
const emailB = "dedicated-e2e-b-" + suffix + "@example.test";
const playerNameA = "DediA" + suffix;
const playerNameB = "DediB" + suffix;

function check(condition, message, detail = "") {
  if (!condition) throw new Error("FAIL " + message + (detail ? " — " + detail : ""));
  console.log("PASS " + message + (detail ? " — " + detail : ""));
}
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function freePort() {
  const server = createServer();
  await new Promise((resolve, reject) => server.once("error", reject).listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}
async function waitFor(fn, label, timeoutMs = 20000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await fn();
    if (value) return value;
    if (godot && godot.exitCode !== null) throw new Error("Godot dedicated server exited while waiting for " + label + ". Output:\n" + godotOutput);
    await sleep(200);
  }
  throw new Error("Timed out waiting for " + label + ". Godot output:\n" + godotOutput);
}
async function requestJson(url, options = {}) {
  const response = await fetch(url, options);
  return { status: response.status, body: await response.json().catch(() => ({})) };
}
function authHeaders(token) {
  return { "content-type": "application/json", authorization: "Bearer " + token };
}
class SocketClient {
  constructor(socket) {
    this.socket = socket;
    this.messages = [];
    this.waiters = [];
    this.closed = false;
    socket.on("message", raw => {
      let message;
      try { message = JSON.parse(String(raw)); } catch { return; }
      this.messages.push(message);
      for (const waiter of [...this.waiters]) if (waiter.predicate(message)) {
        this.waiters.splice(this.waiters.indexOf(waiter), 1);
        clearTimeout(waiter.timer);
        waiter.resolve(message);
      }
    });
    socket.on("close", (code, reason) => {
      this.closed = true;
      this.closeInfo = { code, reason: String(reason) };
      for (const waiter of [...this.waiters]) {
        this.waiters.splice(this.waiters.indexOf(waiter), 1);
        clearTimeout(waiter.timer);
        waiter.reject(new Error("dedicated socket closed " + code + ": " + String(reason)));
      }
    });
    socket.on("error", error => { this.socketError = error; });
  }
  waitFor(predicate, timeoutMs = 8000) {
    const index = this.messages.findIndex(predicate);
    if (index >= 0) return Promise.resolve(this.messages.splice(index, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve, reject, timer: setTimeout(() => {
        const i = this.waiters.indexOf(waiter);
        if (i >= 0) this.waiters.splice(i, 1);
        reject(new Error("dedicated socket message timeout"));
      }, timeoutMs) };
      this.waiters.push(waiter);
    });
  }
  send(value) { this.socket.send(JSON.stringify(value)); }
  close() { if (this.socket && this.socket.readyState !== WebSocket.CLOSED) this.socket.terminate(); }
}
async function connectWithTicket(url, ticket, expectedServerId) {
  const socket = new WebSocket(url);
  const client = new SocketClient(socket);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("dedicated WebSocket open timeout")), 8000);
    socket.once("open", () => { clearTimeout(timer); resolve(); });
    socket.once("error", error => { clearTimeout(timer); reject(error); });
  });
  const challenge = await client.waitFor(message => message.type === "ticket_required");
  check(challenge.serverId === expectedServerId, "standalone Godot server challenges with its registered identity");
  client.send({ type: "join_ticket", ticket });
  const admission = await client.waitFor(message => message.type === "world_joined" || message.type === "rejected", 10000);
  return { client, admission };
}
function startGodot(apiBase, port) {
  const env = {
    ...process.env,
    REVERIE_API_BASE_URL: apiBase,
    REVERIE_SERVER_BOOTSTRAP_SECRET: bootstrapSecret,
    REVERIE_SERVER_KEY: serverKey,
    REVERIE_SERVER_NAME: "Dedicated E2E " + suffix,
    REVERIE_SERVER_REGION: "castle_royal_gardens",
    REVERIE_SERVER_PORT: String(port),
    REVERIE_SERVER_HOST: "127.0.0.1"
  };
  godot = spawn(godotExe, ["--headless", "--path", projectRoot, "--script", "res://tests/online_dedicated_server_launcher.gd"], {
    cwd: projectRoot, env, windowsHide: true, stdio: ["ignore", "pipe", "pipe"]
  });
  godot.stdout.on("data", chunk => { godotOutput += chunk.toString(); });
  godot.stderr.on("data", chunk => { godotOutput += chunk.toString(); });
  return godot;
}
async function stopGodot() {
  if (!godot) return;
  const child = godot;
  if (child.exitCode === null) {
    const exited = new Promise(resolve => child.once("exit", resolve));
    child.kill();
    await Promise.race([exited, sleep(2500)]);
    if (child.exitCode === null) {
      const killer = spawn("taskkill", ["/PID", String(child.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" });
      await Promise.race([new Promise(resolve => killer.once("exit", resolve)), sleep(2500)]);
    }
  }
  await sleep(500);
  godot = null;
}

try {
  await app.register(jwtPlugin, { secret: config.JWT_SECRET });
  await app.register(websocketPlugin);
  await app.register(gameServerRoutes, { prefix: "/v1/game-servers" });
  await app.register(persistentWorldRealtimeRoutes, { prefix: "/v1" });
  await app.listen({ host: "127.0.0.1", port: 0 });
  const address = app.server.address();
  if (!address || typeof address === "string") throw new Error("Fastify test API failed to bind.");
  const apiBase = "http://127.0.0.1:" + address.port;

  const accounts = await pool.query(
    "insert into accounts(email,password_hash,email_verified,status) values($1,'$argon2id$dedicated-e2e',true,'active'),($2,'$argon2id$dedicated-e2e',true,'active') returning id,email",
    [emailA, emailB]
  );
  const accountA = accounts.rows.find(row => row.email === emailA).id;
  const accountB = accounts.rows.find(row => row.email === emailB).id;
  accountIds = [accountA, accountB];
  const players = await pool.query(
    "insert into players(account_id,name) values($1,$2),($3,$4) returning id,name,account_id",
    [accountA, playerNameA, accountB, playerNameB]
  );
  const playerA = players.rows.find(row => row.account_id === accountA).id;
  const playerB = players.rows.find(row => row.account_id === accountB).id;
  const versionA = (await pool.query("select token_version from accounts where id=$1", [accountA])).rows[0].token_version;
  const versionB = (await pool.query("select token_version from accounts where id=$1", [accountB])).rows[0].token_version;
  const tokenA = app.jwt.sign({ sub: accountA, playerId: playerA, tokenVersion: versionA });
  const tokenB = app.jwt.sign({ sub: accountB, playerId: playerB, tokenVersion: versionB });

  const port = await freePort();
  const endpoint = "ws://127.0.0.1:" + port;
  startGodot(apiBase, port);
  const registered = await waitFor(async () => {
    const row = await pool.query("select id,status,endpoint_url from game_servers where server_key=$1", [serverKey]);
    return row.rows[0]?.status === "online" ? row.rows[0] : null;
  }, "Godot server registration, event recovery and listener startup");
  serverId = registered.id;
  check(registered.endpoint_url === endpoint, "Godot registers the configured standalone WebSocket endpoint");
  await waitFor(async () => {
    const row = await pool.query("select 1 from pg_indexes where schemaname='public' and tablename='game_server_world_events' and indexname='game_server_world_events_event_id_idx'");
    return row.rowCount === 1;
  }, "idempotency index");

  const joinA = await requestJson(apiBase + "/v1/game-servers/" + serverId + "/join", { method: "POST", headers: authHeaders(tokenA), body: "{}" });
  const joinB = await requestJson(apiBase + "/v1/game-servers/" + serverId + "/join", { method: "POST", headers: authHeaders(tokenB), body: "{}" });
  check(joinA.status === 200 && joinA.body.joinTicket, "player A receives a one-time ticket for the standalone Godot server");
  check(joinB.status === 200 && joinB.body.joinTicket, "player B receives a separate one-time ticket");

  const connectedA = await connectWithTicket(endpoint, joinA.body.joinTicket, serverId);
  socketA = connectedA.client;
  check(connectedA.admission.type === "world_joined" && connectedA.admission.playerId === playerA, "player A is admitted by the standalone Godot process");
  const connectedB = await connectWithTicket(endpoint, joinB.body.joinTicket, serverId);
  socketB = connectedB.client;
  check(connectedB.admission.type === "world_joined" && connectedB.admission.playerId === playerB, "player B is admitted by the standalone Godot process");
  check(connectedB.admission.members.some(member => member.playerId === playerA), "player B snapshot includes player A");

  await sleep(100);
  socketA.send({ type: "position", x: 20, y: 20 });
  const moveA = await socketB.waitFor(message => message.type === "position" && message.playerId === playerA);
  check(moveA.x === 20 && moveA.y === 20 && moveA.sequence > 0, "Godot movement is broadcast only after its PostgreSQL event commit");
  await sleep(100);
  socketB.send({ type: "position", x: 40, y: 40 });
  const moveB = await socketA.waitFor(message => message.type === "position" && message.playerId === playerB);
  check(moveB.x === 40 && moveB.y === 40 && moveB.sequence > moveA.sequence, "second player movement shares the same monotonic database sequence");

  const persisted = await pool.query(
    "select player_id,x,y from game_server_player_state where server_id=$1 and player_id=any($2::uuid[]) order by player_id",
    [serverId, [playerA, playerB]]
  );
  check(persisted.rowCount === 2 && persisted.rows.every(row =>
    (row.player_id === playerA && row.x === 20 && row.y === 20) ||
    (row.player_id === playerB && row.x === 40 && row.y === 40)
  ), "both standalone-authoritative positions are persisted in PostgreSQL");

  socketA.send({ type: "replay_request", lastSequence: 0 });
  const replayed = await socketA.waitFor(message => message.type === "position" && message.playerId === playerA && message.x === 20);
  const replayComplete = await socketA.waitFor(message => message.type === "replay_complete");
  check(replayed.sequence > 0 && replayComplete.lastSequence >= moveB.sequence, "standalone Godot replay reads the durable PostgreSQL event log");

  const leaseBefore = await pool.query(
    "select player_id,connection_id,lease_expires_at from game_server_player_connections where server_id=$1 and player_id=any($2::uuid[]) order by player_id",
    [serverId, [playerA, playerB]]
  );
  check(leaseBefore.rowCount === 2, "both standalone clients own durable PostgreSQL connection leases");
  const initialLeaseExpiry = Math.min(...leaseBefore.rows.map(row => new Date(row.lease_expires_at).getTime()));
  await waitFor(async () => {
    const rows = await pool.query(
      "select min(lease_expires_at) as expiry from game_server_player_connections where server_id=$1 and player_id=any($2::uuid[])",
      [serverId, [playerA, playerB]]
    );
    return rows.rows[0]?.expiry && new Date(rows.rows[0].expiry).getTime() > initialLeaseExpiry + 5000;
  }, "Godot's periodic connection-lease renewal", 22000);
  check(true, "Godot renews both PostgreSQL connection leases while clients remain connected");

  await stopGodot();
  await pool.query("update game_servers set status='offline',heartbeat_at=now(),stopped_at=now() where id=$1", [serverId]);
  const savedSequence = Number((await pool.query("select next_event_sequence from game_servers where id=$1", [serverId])).rows[0].next_event_sequence);
  startGodot(apiBase, port);
  const restarted = await waitFor(async () => {
    const row = await pool.query("select id,status,endpoint_url from game_servers where server_key=$1", [serverKey]);
    return row.rows[0]?.status === "online" ? row.rows[0] : null;
  }, "Godot process restart and durable event recovery");
  check(restarted.id === serverId, "restarted Godot process reuses the same persistent server identity");
  check(Number((await pool.query("select next_event_sequence from game_servers where id=$1", [serverId])).rows[0].next_event_sequence) >= savedSequence, "event sequence survives the dedicated-process restart");

  const assignmentA = await pool.query("select 1 from game_server_players where server_id=$1 and player_id=$2", [serverId, playerA]);
  const assignmentB = await pool.query("select 1 from game_server_players where server_id=$1 and player_id=$2", [serverId, playerB]);
  const reconnectPathA = assignmentA.rowCount ? "reconnect" : "join";
  const reconnectPathB = assignmentB.rowCount ? "reconnect" : "join";
  const reconnectA = await requestJson(apiBase + "/v1/game-servers/" + serverId + "/" + reconnectPathA, { method: "POST", headers: authHeaders(tokenA), body: "{}" });
  const reconnectB = await requestJson(apiBase + "/v1/game-servers/" + serverId + "/" + reconnectPathB, { method: "POST", headers: authHeaders(tokenB), body: "{}" });
  check(reconnectA.status === 200 && reconnectA.body.joinTicket && reconnectB.status === 200 && reconnectB.body.joinTicket, "both players receive fresh tickets after the dedicated process restart");
  const reconnectedA = await connectWithTicket(endpoint, reconnectA.body.joinTicket, serverId);
  socketA2 = reconnectedA.client;
  check(reconnectedA.admission.type === "world_joined" && reconnectedA.admission.playerId === playerA, "player A reconnects to the restarted Godot process");
  const reconnectedB = await connectWithTicket(endpoint, reconnectB.body.joinTicket, serverId);
  socketB2 = reconnectedB.client;
  check(reconnectedB.admission.type === "world_joined" && reconnectedB.admission.playerId === playerB, "player B reconnects to the restarted Godot process");
  const recoveredMemberA = reconnectedB.admission.members.find(member => member.playerId === playerA);
  const recoveredMemberB = reconnectedB.admission.members.find(member => member.playerId === playerB);
  check(recoveredMemberA?.x === 20 && recoveredMemberA?.y === 20 && recoveredMemberB?.x === 40 && recoveredMemberB?.y === 40,
    "restarted Godot process restores both player positions from PostgreSQL event history",
    JSON.stringify({ recoveredMemberA, recoveredMemberB }));

  const replayAfterRestart = await pool.query(
    "select count(*)::int as count from game_server_world_events where server_id=$1 and sequence<=$2",
    [serverId, savedSequence]
  );
  check(replayAfterRestart.rows[0]?.count >= 4, "durable world-event history remains intact across process restart");

  console.log("DEDICATED_WORLD_E2E_SUMMARY all checks passed");
  finished = true;
} catch (error) {
  console.error("DEDICATED_WORLD_E2E_FAILURE", error?.stack ?? error);
  console.error("GODOT_OUTPUT\n" + godotOutput);
  process.exitCode = 1;
} finally {
  socketA?.close();
  socketB?.close();
  socketA2?.close();
  socketB2?.close();
  await stopGodot().catch(error => console.error("Godot shutdown warning", error.message));
  if (serverId) await pool.query("delete from game_servers where id=$1", [serverId]).catch(error => console.error("server cleanup failed", error.message));
  if (accountIds.length) await pool.query("delete from accounts where id=any($1::uuid[])", [accountIds]).catch(error => console.error("account cleanup failed", error.message));
  await app.close().catch(error => console.error("Fastify close failed", error.message));
  await pool.end().catch(() => {});
  if (finished) console.log("DEDICATED_WORLD_E2E_CLEANUP complete");
  process.exit(finished ? 0 : 1);
}
