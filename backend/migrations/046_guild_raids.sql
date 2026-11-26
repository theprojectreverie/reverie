CREATE TABLE IF NOT EXISTS guild_raids (
 guild_id uuid NOT NULL REFERENCES guilds(id) ON DELETE CASCADE,
 week_start date NOT NULL,
 hp integer NOT NULL CHECK(hp BETWEEN 0 AND 12000),
 defeated_at timestamptz,
 PRIMARY KEY(guild_id,week_start)
);
CREATE TABLE IF NOT EXISTS guild_raid_attempts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 guild_id uuid REFERENCES guilds(id) ON DELETE SET NULL,
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 week_start date NOT NULL,
 attempt_day date NOT NULL,
 joined_at timestamptz NOT NULL,
 state jsonb NOT NULL,
 status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','victory','defeat','abandoned')),
 damage integer NOT NULL DEFAULT 0 CHECK(damage BETWEEN 0 AND 12000),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS guild_raid_active_player_idx ON guild_raid_attempts(player_id) WHERE status='active';
CREATE INDEX IF NOT EXISTS guild_raid_attempt_day_idx ON guild_raid_attempts(player_id,attempt_day);
CREATE INDEX IF NOT EXISTS guild_raid_contribution_idx ON guild_raid_attempts(guild_id,week_start,player_id);
CREATE TABLE IF NOT EXISTS guild_raid_claims (
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 week_start date NOT NULL,
 guild_id uuid REFERENCES guilds(id) ON DELETE SET NULL,
 claimed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(player_id,week_start)
);