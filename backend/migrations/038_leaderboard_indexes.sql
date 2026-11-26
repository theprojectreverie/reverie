-- Restrict the leaderboard ledger index to authoritative positive gold credits.
CREATE INDEX IF NOT EXISTS currency_ledger_rankings_idx ON currency_ledger(player_id,reason,created_at) INCLUDE(ref_id)
 WHERE currency_id='gold' AND delta>0 AND reason IN ('coop_monster_defeat','online_achievement');
CREATE INDEX IF NOT EXISTS online_season_champions_idx ON online_season_results(season_start,category,player_id) INCLUDE(score) WHERE rank=1;
CREATE INDEX IF NOT EXISTS online_season_unclaimed_idx ON online_season_results(player_id,season_start,category) WHERE gold>0 AND claimed_at IS NULL;
CREATE INDEX IF NOT EXISTS players_global_rankings_idx ON players(id) WHERE settings->'global_rankings'='true'::jsonb;
