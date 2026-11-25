import { Pool } from 'pg';
import { readFile } from 'node:fs/promises';
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
try {
  const sql = await readFile(new URL('../../migrations/018_persistent_world_event_idempotency.sql', import.meta.url), 'utf8');
  await pool.query(sql);
  const check = await pool.query("SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='game_server_world_events' AND column_name='event_id') AS has_event_id, to_regclass('public.game_server_world_events_event_id_idx') AS index_name");
  if (!check.rows[0]?.has_event_id || check.rows[0]?.index_name !== 'game_server_world_events_event_id_idx') throw new Error('Migration 018 verification failed');
  console.log('Migration 018 applied and verified: idempotent persistent-world event appends');
} finally { await pool.end(); }
