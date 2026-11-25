import { Pool } from 'pg';
import { readFile } from 'node:fs/promises';
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
try {
  const sql = await readFile(new URL('../../migrations/016_persistent_world_event_log.sql', import.meta.url), 'utf8');
  await pool.query(sql);
  const check = await pool.query("SELECT to_regclass('public.game_server_world_events') AS table_name, EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='game_servers' AND column_name='next_event_sequence') AS has_sequence");
  if (check.rows[0]?.table_name !== 'game_server_world_events' || !check.rows[0]?.has_sequence) throw new Error('Migration 016 verification failed');
  console.log('Migration 016 applied and verified: durable persistent-world event log');
} finally { await pool.end(); }
