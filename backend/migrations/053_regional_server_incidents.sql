CREATE TABLE IF NOT EXISTS regional_server_incidents (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 server_id uuid NOT NULL REFERENCES game_servers(id) ON DELETE CASCADE,
 kind text NOT NULL CHECK(kind IN ('availability','capacity')),
 initial_reason text NOT NULL CHECK(initial_reason IN ('stale','unavailable','offline_reserved','capacity','full')),
 current_reason text NOT NULL CHECK(current_reason IN ('stale','unavailable','offline_reserved','capacity','full')),
 opened_at timestamptz NOT NULL DEFAULT now(),
 resolved_at timestamptz,
 resolution text CHECK(resolution IN ('condition_cleared','server_inactive')),
 CHECK((resolved_at IS NULL)=(resolution IS NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS regional_server_incidents_open_idx ON regional_server_incidents(server_id,kind) WHERE resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS regional_server_incidents_recent_idx ON regional_server_incidents(opened_at DESC,id DESC);
