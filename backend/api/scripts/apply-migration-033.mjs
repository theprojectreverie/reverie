import { Pool } from 'pg';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const url=process.env.DATABASE_URL;
assert.ok(url,'DATABASE_URL must be explicitly configured');
const host=new URL(url).hostname;
assert.ok(['localhost','127.0.0.1','[::1]'].includes(host)||process.env.REVERIE_ALLOW_REMOTE_MIGRATION==='033','Remote database migration requires explicit REVERIE_ALLOW_REMOTE_MIGRATION=033');
const pool=new Pool({connectionString:url});
const db=await pool.connect();
try{
 await db.query('BEGIN');
 await db.query("SET LOCAL lock_timeout='5s'");
 await db.query(await readFile(new URL('../../migrations/033_chat_reply_references.sql',import.meta.url),'utf8'));
 const result=await db.query("SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='private_chat_messages' AND column_name='reply_to' AND udt_name='uuid') AS column_ok, EXISTS(SELECT 1 FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey) WHERE c.conrelid='public.private_chat_messages'::regclass AND c.confrelid=c.conrelid AND c.contype='f' AND c.confdeltype='n' AND a.attname='reply_to') AS fk_ok");
 assert.ok(result.rows[0]?.column_ok&&result.rows[0]?.fk_ok,'Migration 033 schema verification failed');
 await db.query('COMMIT');
 console.log('Migration 033 applied and verified: private chat reply references');
}catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();await pool.end();}