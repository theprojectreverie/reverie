-- Preserve terminal matchmaking outcomes without leaving players blocked by stale matched tickets.
ALTER TABLE pvp_queue_tickets
 DROP CONSTRAINT IF EXISTS pvp_queue_tickets_status_check;
ALTER TABLE pvp_queue_tickets
 ADD CONSTRAINT pvp_queue_tickets_status_check
 CHECK(status IN('waiting','matched','cancelled','expired','completed'));
CREATE INDEX IF NOT EXISTS pvp_queue_player_recent_idx
 ON pvp_queue_tickets(player_id,created_at DESC);
