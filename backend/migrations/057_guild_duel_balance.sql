ALTER TABLE pvp_queue_tickets ADD COLUMN IF NOT EXISTS guild_joined_at timestamptz;
ALTER TABLE pvp_queue_tickets ADD COLUMN IF NOT EXISTS party_power bigint CHECK(party_power IS NULL OR party_power>0);
CREATE INDEX IF NOT EXISTS guild_duel_recent_player_idx ON pvp_match_players(player_id,match_id) WHERE guild_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS guild_duel_recent_match_idx ON pvp_matches(started_at,id) WHERE mode='guild_duel';