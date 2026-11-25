-- Persistent regional game-server registry and world ownership.
-- Apply after 011_pvp_queue_terminal_status.sql.
CREATE TABLE IF NOT EXISTS game_servers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 server_key text NOT NULL UNIQUE CHECK(server_key ~ '^[a-z0-9][a-z0-9_-]{2,63}$'),
 display_name text NOT NULL CHECK(length(display_name) BETWEEN 3 AND 48),
 region_id text NOT NULL CHECK(region_id ~ '^[a-z0-9_]{2,48}$'),
 status text NOT NULL DEFAULT 'starting' CHECK(status IN('starting','online','draining','maintenance','offline')),
 endpoint_url text,
 server_secret_hash text UNIQUE,
 max_players integer NOT NULL DEFAULT 100 CHECK(max_players BETWEEN 1 AND 1000),
 build_version text NOT NULL DEFAULT 'development',
 heartbeat_at timestamptz,
 started_at timestamptz,
 stopped_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(endpoint_url IS NULL OR endpoint_url ~ '^wss?://')
);
CREATE INDEX IF NOT EXISTS game_servers_directory_idx
 ON game_servers(region_id,status,display_name);
CREATE INDEX IF NOT EXISTS game_servers_heartbeat_idx
 ON game_servers(heartbeat_at) WHERE status IN('starting','online','draining');

-- A character can occupy only one persistent world server at a time.
CREATE TABLE IF NOT EXISTS game_server_players (
 server_id uuid NOT NULL REFERENCES game_servers(id) ON DELETE CASCADE,
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 joined_at timestamptz NOT NULL DEFAULT now(),
 last_seen_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(server_id,player_id),
 UNIQUE(player_id)
);
CREATE INDEX IF NOT EXISTS game_server_players_server_idx
 ON game_server_players(server_id,joined_at);

-- Versioned server-owned world state survives process restarts and deployments.
CREATE TABLE IF NOT EXISTS game_server_world_state (
 server_id uuid PRIMARY KEY REFERENCES game_servers(id) ON DELETE CASCADE,
 revision bigint NOT NULL DEFAULT 0 CHECK(revision>=0),
 state jsonb NOT NULL DEFAULT '{}'::jsonb,
 saved_at timestamptz NOT NULL DEFAULT now()
);
