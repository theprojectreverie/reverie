-- Idempotency keys prevent duplicate durable events when a dedicated server retries
-- after a timeout where PostgreSQL may already have committed the first request.
ALTER TABLE game_server_world_events
 ADD COLUMN IF NOT EXISTS event_id uuid;

CREATE UNIQUE INDEX IF NOT EXISTS game_server_world_events_event_id_idx
 ON game_server_world_events(server_id,event_id)
 WHERE event_id IS NOT NULL;
