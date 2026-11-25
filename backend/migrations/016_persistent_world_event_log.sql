-- Durable, monotonically sequenced event history for persistent regional worlds.
ALTER TABLE game_servers
 ADD COLUMN IF NOT EXISTS next_event_sequence bigint NOT NULL DEFAULT 0
 CHECK(next_event_sequence >= 0);

CREATE TABLE IF NOT EXISTS game_server_world_events (
 server_id uuid NOT NULL REFERENCES game_servers(id) ON DELETE CASCADE,
 sequence bigint NOT NULL CHECK(sequence > 0),
 event_type text NOT NULL CHECK(event_type IN ('position','emote','player_joined','player_left')),
 player_id uuid REFERENCES players(id) ON DELETE SET NULL,
 payload jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(server_id,sequence)
);
CREATE INDEX IF NOT EXISTS game_server_world_events_retention_idx
 ON game_server_world_events(created_at);
