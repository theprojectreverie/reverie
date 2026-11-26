CREATE TABLE IF NOT EXISTS online_ranking_visibility_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 enabled boolean NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS online_ranking_visibility_history_idx ON online_ranking_visibility_events(player_id,changed_at DESC,id DESC);
-- Capture the initial opt-in state once; no retrospective participation claims.
INSERT INTO online_ranking_visibility_events(player_id,enabled)
SELECT p.id,true FROM players p WHERE p.settings->'global_rankings'='true'::jsonb
AND NOT EXISTS(SELECT 1 FROM online_ranking_visibility_events e WHERE e.player_id=p.id);
CREATE TABLE IF NOT EXISTS online_season_finalizations (
 season_start date PRIMARY KEY,
 finalized_at timestamptz NOT NULL DEFAULT now(),
 CHECK (extract(day from season_start)=1)
);
CREATE TABLE IF NOT EXISTS online_season_results (
 season_start date NOT NULL REFERENCES online_season_finalizations(season_start) ON DELETE CASCADE,
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 category text NOT NULL CHECK(category IN ('combat','exploration','achievements')),
 score integer NOT NULL CHECK(score>0),
 rank integer NOT NULL CHECK(rank>0),
 gold integer NOT NULL CHECK(gold>=0),
 claimed_at timestamptz,
 PRIMARY KEY(season_start,player_id,category)
);
CREATE INDEX IF NOT EXISTS online_season_result_player_idx ON online_season_results(player_id,season_start DESC);
