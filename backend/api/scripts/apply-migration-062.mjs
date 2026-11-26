import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
assert.ok(config.NODE_ENV!=="production"&&["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname),"Local development database required");
const db=await pool.connect();try{await db.query("BEGIN");await db.query("SET LOCAL lock_timeout='5s'");await db.query(await readFile(new URL("../../migrations/062_elathra_story_audience.sql",import.meta.url),"utf8"));assert.ok((await db.query("SELECT to_regclass('public.story_elathra_audience') AS audience")).rows[0].audience);await db.query("COMMIT");console.log("Migration 062 applied and verified on local database");}catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();await pool.end();}
