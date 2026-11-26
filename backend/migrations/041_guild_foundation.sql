-- Extend the base guild schema without replacing existing tables.
ALTER TABLE guilds ADD COLUMN IF NOT EXISTS emblem text NOT NULL DEFAULT 'moon' CHECK(emblem IN ('moon','star','shield','flame','rose','crown'));
CREATE INDEX IF NOT EXISTS guild_members_guild_idx ON guild_members(guild_id,joined_at);
CREATE UNIQUE INDEX IF NOT EXISTS guild_one_leader_idx ON guild_members(guild_id) WHERE guild_rank='leader';
CREATE TABLE IF NOT EXISTS guild_requests (
 guild_id uuid NOT NULL REFERENCES guilds(id) ON DELETE CASCADE,
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 kind text NOT NULL CHECK(kind IN ('application','invitation')),
 sender_id uuid REFERENCES players(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT now()+interval '7 days',
 PRIMARY KEY(guild_id,player_id,kind),
 CHECK((kind='invitation')=(sender_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS guild_requests_player_idx ON guild_requests(player_id,expires_at);