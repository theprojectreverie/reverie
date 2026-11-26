CREATE TABLE IF NOT EXISTS story_royal_gate_patrol (
 player_id uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
 completed_at timestamptz NOT NULL DEFAULT now(),
 rewards jsonb NOT NULL
);
