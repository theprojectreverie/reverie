CREATE TABLE IF NOT EXISTS online_monthly_quests (
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 month_start date NOT NULL,
 claimed text[] NOT NULL DEFAULT '{}',
 PRIMARY KEY(player_id,month_start)
);
