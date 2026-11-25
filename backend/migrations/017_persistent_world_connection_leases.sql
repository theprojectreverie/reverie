-- Cross-process leases for persistent-world WebSocket connections.
-- A lease expires automatically if an API process crashes without running close handlers.
CREATE TABLE IF NOT EXISTS game_server_player_connections (
 connection_id uuid PRIMARY KEY,
 server_id uuid NOT NULL,
 player_id uuid NOT NULL,
 lease_expires_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(server_id,player_id) REFERENCES game_server_players(server_id,player_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS game_server_player_connections_active_idx
 ON game_server_player_connections(server_id,player_id,lease_expires_at);
CREATE INDEX IF NOT EXISTS game_server_player_connections_expiry_idx
 ON game_server_player_connections(lease_expires_at);
