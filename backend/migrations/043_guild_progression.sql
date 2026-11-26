-- Claim identity is account-wide per UTC day, surviving guild disbanding.
CREATE TABLE IF NOT EXISTS guild_mission_claims (
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 guild_id uuid REFERENCES guilds(id) ON DELETE SET NULL,
 mission_day date NOT NULL,
 mission_id text NOT NULL CHECK(mission_id IN ('checkin','victories','daily_duties')),
 xp integer NOT NULL CHECK(xp>0),
 claimed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(player_id,mission_day,mission_id)
);
CREATE INDEX IF NOT EXISTS guild_mission_rank_idx ON guild_mission_claims(guild_id,mission_day,player_id);