CREATE TABLE IF NOT EXISTS online_weekly_quests (
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 week_start date NOT NULL,
 claimed text[] NOT NULL DEFAULT '{}',
 PRIMARY KEY(player_id,week_start)
);
