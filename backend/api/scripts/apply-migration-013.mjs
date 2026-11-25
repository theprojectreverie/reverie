import { Pool } from 'pg';
import { readFile } from 'node:fs/promises';
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
try {
  const sql = await readFile(new URL('../../migrations/013_game_server_join_tickets.sql', import.meta.url), 'utf8');
  await pool.query(sql);
  const check = await pool.query("SELECT to_regclass('public.game_server_join_tickets') AS table_name");
  if (check.rows[0]?.table_name !== 'game_server_join_tickets') throw new Error('Migration verification failed');
  console.log('Migration 013 applied and verified:', check.rows[0].table_name);
} finally { await pool.end(); }
