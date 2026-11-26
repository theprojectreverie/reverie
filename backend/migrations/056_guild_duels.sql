ALTER TABLE pvp_queue_tickets DROP CONSTRAINT IF EXISTS pvp_queue_tickets_mode_check;
ALTER TABLE pvp_queue_tickets ADD CONSTRAINT pvp_queue_tickets_mode_check CHECK(mode IN ('friendly_duel','guild_duel'));
ALTER TABLE pvp_queue_tickets ADD COLUMN IF NOT EXISTS guild_id uuid;
ALTER TABLE pvp_matches DROP CONSTRAINT IF EXISTS pvp_matches_mode_check;
ALTER TABLE pvp_matches ADD CONSTRAINT pvp_matches_mode_check CHECK(mode IN ('friendly_duel','ranked_duel','team_skirmish','guild_duel'));
ALTER TABLE pvp_match_players ADD COLUMN IF NOT EXISTS guild_id uuid;
CREATE INDEX IF NOT EXISTS pvp_queue_mode_waiting_idx ON pvp_queue_tickets(mode,created_at,id) WHERE status='waiting';