-- Apply after backend/schemas/schema.sql. PostgreSQL 16+.
CREATE TABLE IF NOT EXISTS player_presence (
 player_id uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
 state text NOT NULL DEFAULT 'offline' CHECK(state IN('offline','online','in_world','in_lobby','in_battle')),
 region_id text,last_heartbeat_at timestamptz,updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS co_op_lobbies (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),leader_player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 region_id text NOT NULL,status text NOT NULL DEFAULT 'open' CHECK(status IN('open','in_world','closed')),
 max_members smallint NOT NULL DEFAULT 4 CHECK(max_members BETWEEN 2 AND 4),
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS co_op_lobbies_region_status_idx ON co_op_lobbies(region_id,status);
CREATE TABLE IF NOT EXISTS co_op_lobby_members (
 lobby_id uuid NOT NULL REFERENCES co_op_lobbies(id) ON DELETE CASCADE,
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 role text NOT NULL DEFAULT 'member' CHECK(role IN('leader','member')),
 joined_at timestamptz NOT NULL DEFAULT now(),last_ack_sequence bigint NOT NULL DEFAULT 0 CHECK(last_ack_sequence>=0),
 PRIMARY KEY(lobby_id,player_id),UNIQUE(player_id)
);
CREATE INDEX IF NOT EXISTS co_op_lobby_members_player_idx ON co_op_lobby_members(player_id);
CREATE TABLE IF NOT EXISTS co_op_world_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,lobby_id uuid NOT NULL REFERENCES co_op_lobbies(id) ON DELETE CASCADE,
 sequence bigint NOT NULL CHECK(sequence>0),
 event_type text NOT NULL CHECK(event_type IN('player_joined','player_left','position','interaction','emote','region_transition')),
 actor_player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,payload jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(lobby_id,sequence)
);
CREATE INDEX IF NOT EXISTS co_op_world_events_replay_idx ON co_op_world_events(lobby_id,sequence);
CREATE TABLE IF NOT EXISTS pvp_matches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),mode text NOT NULL DEFAULT 'friendly_duel' CHECK(mode IN('friendly_duel','ranked_duel','team_skirmish')),
 status text NOT NULL DEFAULT 'queued' CHECK(status IN('queued','active','completed','cancelled','expired')),
 content_version_id text REFERENCES content_versions(id),server_seed_hash text,result jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),started_at timestamptz,completed_at timestamptz
);
CREATE TABLE IF NOT EXISTS pvp_match_players (
 match_id uuid NOT NULL REFERENCES pvp_matches(id) ON DELETE CASCADE,player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 team smallint NOT NULL CHECK(team IN(1,2)),rating_before integer,rating_after integer,ready_at timestamptz,PRIMARY KEY(match_id,player_id)
);
CREATE INDEX IF NOT EXISTS pvp_match_players_player_idx ON pvp_match_players(player_id,match_id);
CREATE TABLE IF NOT EXISTS pvp_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,match_id uuid NOT NULL REFERENCES pvp_matches(id) ON DELETE CASCADE,
 sequence bigint NOT NULL CHECK(sequence>0),actor_player_id uuid REFERENCES players(id) ON DELETE SET NULL,
 event jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(match_id,sequence)
);
CREATE UNIQUE INDEX IF NOT EXISTS friendships_pair_order_uq ON friendships(LEAST(player_id,friend_id),GREATEST(player_id,friend_id));
