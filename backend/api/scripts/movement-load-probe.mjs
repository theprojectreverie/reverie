// Optional bounded loopback load probe. Uses only the parent test's disposable identities.
import { performance } from "node:perf_hooks";

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const percentile = (sorted, q) => Math.round(sorted[Math.max(0, Math.ceil(sorted.length * q) - 1)] * 10) / 10;

export async function runMovementLoadProbe({ clients, playerRows, rounds, pool, serverId }) {
  if (!Number.isInteger(rounds) || rounds < 1 || rounds > 100) {
    throw new RangeError("REVERIE_E2E_MOVEMENT_ROUNDS must be an integer from 1 to 100");
  }
  const playerIds = playerRows.map(row => row.id);
  const playerIndex = new Map(playerIds.map((id, i) => [id, i]));
  const sent = new Map();
  const receipts = new Set();
  const latency = [];
  const rejected = [];
  const listeners = clients.map((client, receiver) => {
    const listener = raw => {
      let event;
      try { event = JSON.parse(String(raw)); } catch { return; }
      if (event.type === "rejected") rejected.push(event.reason);
      if (event.type !== "position") return;
      const sender = playerIndex.get(event.playerId);
      if (sender === undefined || sender === receiver) return;
      const round = event.x - 20;
      const key = sender + ":" + round;
      if (!sent.has(key) || event.y !== 30 + sender) return;
      const receipt = key + ":" + receiver;
      if (receipts.has(receipt)) return;
      receipts.add(receipt);
      latency.push(performance.now() - sent.get(key));
    };
    client.socket.on("message", listener);
    return listener;
  });
  const expected = clients.length * (clients.length - 1) * rounds;
  try {
    const started = performance.now();
    for (let round = 1; round <= rounds; round++) {
      // Five position proposals per second per player, well below the 40 ms input guard.
      await sleep(Math.max(0, started + round * 200 - performance.now()));
      for (let i = 0; i < clients.length; i++) {
        if (clients[i].socket.readyState !== 1) throw new Error("Movement probe socket closed");
        sent.set(i + ":" + round, performance.now());
        clients[i].socket.send(JSON.stringify({ type: "position", x: 20 + round, y: 30 + i }));
      }
    }
    const sendingMs = performance.now() - started;
    const drainStart = performance.now();
    while (receipts.size < expected && performance.now() - drainStart < 20000) await sleep(50);
    const final = await pool.query("select player_id,x,y from game_server_player_state where server_id=$1", [serverId]);
    const positionsMatch = playerIds.every((id, i) => final.rows.some(row => row.player_id === id && Number(row.x) === 20 + rounds && Number(row.y) === 30 + i));
    latency.sort((a,b) => a-b);
    const metrics = {
      players: clients.length, rounds, proposals: sent.size,
      deliveries: receipts.size, expectedDeliveries: expected,
      sendSeconds: Math.round(sendingMs / 10) / 100,
      drainMs: Math.round(performance.now() - drainStart),
      p50Ms: latency.length ? percentile(latency, .5) : null,
      p95Ms: latency.length ? percentile(latency, .95) : null,
      maxMs: latency.length ? percentile(latency, 1) : null,
      rejected: rejected.length, positionsMatch
    };
    console.log("MOVEMENT_LOAD_RESULT " + JSON.stringify(metrics));
    if (receipts.size !== expected || rejected.length || !positionsMatch) throw new Error("Movement load probe lost updates or final positions");
  } finally {
    clients.forEach((client, i) => client.socket.off("message", listeners[i]));
  }
}
