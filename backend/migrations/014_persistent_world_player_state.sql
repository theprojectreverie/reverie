-- Durable per-player position within a persistent regional world.
CREATE TABLE IF NOT EXISTS game_server_player_state (
 server_id uuid NOT NULL,
 player_id uuid NOT NULL,
 x double precision NOT NULL DEFAULT 0 CHECK(x BETWEEN -100000 AND 100000),
 y double precision NOT NULL DEFAULT 0 CHECK(y BETWEEN -100000 AND 100000),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(server_id,player_id),
 FOREIGN KEY(server_id,player_id) REFERENCES game_server_players(server_id,player_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS game_server_player_state_updated_idx
 ON game_server_player_state(server_id,updated_at DESC);
