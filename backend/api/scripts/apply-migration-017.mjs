import { Pool } from 'pg';
import { readFile } from 'node:fs/promises';
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
try {
 const sql = await readFile(new URL('../../migrations/017_persistent_world_connection_leases.sql', import.meta.url), 'utf8');
 await pool.query(sql);
 const check = await pool.query("SELECT to_regclass('public.game_server_player_connections') AS table_name, count(*)::int AS indexes FROM pg_indexes WHERE schemaname='public' AND tablename='game_server_player_connections'");
 if (check.rows[0]?.table_name !== 'game_server_player_connections' || check.rows[0]?.indexes < 3) throw new Error('Migration 017 verification failed');
 console.log('Migration 017 applied and verified: persistent-world connection leases');
} finally { await pool.end(); }
