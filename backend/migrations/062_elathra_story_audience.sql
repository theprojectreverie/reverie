CREATE TABLE IF NOT EXISTS story_elathra_audience (
 player_id uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
 heard_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,
 CHECK(completed_at IS NULL OR completed_at>=heard_at)
);
