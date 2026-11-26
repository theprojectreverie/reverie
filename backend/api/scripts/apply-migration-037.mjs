import { Pool } from 'pg';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const url=process.env.DATABASE_URL;
assert.ok(url,'DATABASE_URL must be configured');
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(url).hostname)||process.env.REVERIE_ALLOW_REMOTE_MIGRATION==='037','Explicit migration approval required');
const pool=new Pool({connectionString:url});
const db=await pool.connect();
try{
 await db.query('BEGIN');
 await db.query("SET LOCAL lock_timeout='5s'");
 await db.query(await readFile(new URL('../../migrations/037_shared_recent_chat.sql',import.meta.url),'utf8'));
 const r=await db.query("SELECT to_regclass('public.recent_chat_messages') AS messages,to_regclass('public.chat_send_limits') AS limits,to_regclass('public.recent_chat_party_idx') AS party_idx,to_regclass('public.recent_chat_world_idx') AS world_idx");
 assert.ok(r.rows[0]?.messages&&r.rows[0]?.limits&&r.rows[0]?.party_idx&&r.rows[0]?.world_idx,'Shared chat migration verification failed');
 await db.query('COMMIT');
 console.log('Migration 037 applied and verified');
}catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();await pool.end();}