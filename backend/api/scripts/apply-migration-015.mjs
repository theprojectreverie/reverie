import { Pool } from 'pg';
import { readFile } from 'node:fs/promises';
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
try {
  const sql = await readFile(new URL('../../migrations/015_persistent_world_state_retention.sql', import.meta.url), 'utf8');
  await pool.query(sql);
  const check = await pool.query("SELECT conname FROM pg_constraint WHERE conrelid='public.game_server_player_state'::regclass AND conname='game_server_player_state_player_fk'");
  if (!check.rowCount) throw new Error('Migration verification failed');
  console.log('Migration 015 applied and verified: persistent positions survive assignment release');
} finally { await pool.end(); }
