import { Pool } from 'pg';
import { fork } from 'node:child_process';
const marker = 'reverie-notify-cross-process-' + process.pid + '-' + Date.now();
const child = fork(new URL('./test-world-notify-child.mjs', import.meta.url), [], { stdio: ['ignore', 'inherit', 'inherit', 'ipc'] });
const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 1 });
try {
 await new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error('Child listener startup timed out')), 8000);
  child.on('message', message => { if (message?.type === 'ready') { clearTimeout(timer); resolve(); } });
  child.on('error', reject);
 });
 const received = new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error('Cross-process PostgreSQL NOTIFY timed out')), 8000);
  child.on('message', message => { if (message?.type === 'received') { clearTimeout(timer); resolve(message.payload); } });
 });
 await pool.query('SELECT pg_notify($1,$2)', ['reverie_world_events', marker]);
 const payload = await received;
 if (payload !== marker) throw new Error('Cross-process notification payload mismatch');
 console.log('PostgreSQL cross-process LISTEN/NOTIFY smoke: PASS');
} finally {
 child.kill();
 await pool.end();
}
