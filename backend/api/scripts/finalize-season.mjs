import {pool} from '../src/db.ts';
import {freezeSeason} from '../src/world/season-rewards.ts';
import {playerTitles} from '../src/routes/daily-quests.ts';
const season=process.argv[2];
if(!season){console.error('Usage: finalize-season.mjs YYYY-MM-01');await pool.end();process.exit(1);}
const db=await pool.connect();
try{await db.query('BEGIN');const finalized=await freezeSeason(db,season,playerTitles.map(t=>t.id));await db.query('COMMIT');console.log(finalized?'Season finalized: '+season:'Not yet eligible or already finalized: '+season);}
catch(e){await db.query('ROLLBACK');console.error(e.message);process.exitCode=1;}finally{db.release();await pool.end();}
