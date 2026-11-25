-- Short-lived, single-use credentials for player-to-world handoff.
CREATE TABLE IF NOT EXISTS game_server_join_tickets (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 server_id uuid NOT NULL REFERENCES game_servers(id) ON DELETE CASCADE,
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 ticket_hash text NOT NULL UNIQUE,
 expires_at timestamptz NOT NULL,
 consumed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS game_server_join_tickets_expiry_idx
 ON game_server_join_tickets(expires_at) WHERE consumed_at IS NULL;
CREATE INDEX IF NOT EXISTS game_server_join_tickets_player_idx
 ON game_server_join_tickets(player_id,created_at DESC);
