CREATE TABLE IF NOT EXISTS online_daily_quests (
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 quest_day date NOT NULL,
 victories integer NOT NULL DEFAULT 0 CHECK(victories BETWEEN 0 AND 3),
 shared_victories integer NOT NULL DEFAULT 0 CHECK(shared_victories BETWEEN 0 AND 1),
 claimed text[] NOT NULL DEFAULT '{}',
 PRIMARY KEY(player_id,quest_day)
);
