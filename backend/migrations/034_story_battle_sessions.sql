CREATE TABLE IF NOT EXISTS story_battle_sessions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 group_id text NOT NULL,
 party_ids text[] NOT NULL CHECK (cardinality(party_ids) BETWEEN 1 AND 4),
 status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','victory','defeat','abandoned')),
 state jsonb NOT NULL DEFAULT '{}'::jsonb,
 rewards jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),
 finished_at timestamptz,
 settled_at timestamptz,
 CHECK ((rewards IS NULL) = (settled_at IS NULL)),
 CHECK (settled_at IS NULL OR status='victory')
);
CREATE INDEX IF NOT EXISTS story_battle_sessions_player_idx ON story_battle_sessions(player_id,created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS story_battle_revienna_once_idx
 ON story_battle_sessions(player_id,group_id) WHERE group_id='revienna_encounter' AND settled_at IS NOT NULL;
