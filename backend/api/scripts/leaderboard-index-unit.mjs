import pg from 'pg';
import assert from 'node:assert/strict';
if(!['localhost','127.0.0.1','[::1]'].includes(new URL(process.env.DATABASE_URL).hostname))throw Error('Not local');
const p=new pg.Pool({connectionString:process.env.DATABASE_URL});
const c=await p.connect();
try{
 await c.query('BEGIN');
 // Small development DB: prove index eligibility, not a production speed benchmark.
 await c.query('SET LOCAL enable_seqscan=off');
 const queries=[
 ['combat',"SELECT count(*) FROM currency_ledger WHERE player_id='00000000-0000-0000-0000-000000000000' AND reason='coop_monster_defeat' AND currency_id='gold' AND delta>0 AND created_at>='2026-11-01T00:00:00Z' AND created_at<'2026-12-01T00:00:00Z'",'currency_ledger_rankings_idx'],
 ['champions',"SELECT player_id,score FROM online_season_results WHERE season_start='2026-11-01' AND category='combat' AND rank=1 ORDER BY player_id LIMIT 26",'online_season_champions_idx'],
 ['unclaimed',"SELECT season_start,category FROM online_season_results WHERE player_id='00000000-0000-0000-0000-000000000000' AND gold>0 AND claimed_at IS NULL ORDER BY season_start,category",'online_season_unclaimed_idx']
 ];
 for(const [label,sql,idx] of queries){
  const plan=JSON.stringify((await c.query('EXPLAIN (FORMAT JSON) '+sql)).rows);
  assert.ok(plan.includes(idx),label+' plan did not choose '+idx);
  console.log('PASS index eligible:',label,idx);
 }
}finally{await c.query('ROLLBACK');c.release();await p.end();}
