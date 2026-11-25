-- Durable authoritative PvP turn state and replay sequence.
ALTER TABLE pvp_matches ADD COLUMN IF NOT EXISTS state jsonb;
ALTER TABLE pvp_matches ADD COLUMN IF NOT EXISTS state_sequence bigint NOT NULL DEFAULT 0 CHECK(state_sequence>=0);
ALTER TABLE pvp_matches ADD COLUMN IF NOT EXISTS next_event_sequence bigint NOT NULL DEFAULT 1 CHECK(next_event_sequence>0);
ALTER TABLE pvp_matches ADD COLUMN IF NOT EXISTS turn_player_id uuid REFERENCES players(id) ON DELETE SET NULL;
ALTER TABLE pvp_matches ADD COLUMN IF NOT EXISTS expires_at timestamptz;

-- Keep this migration safe to re-apply in development and recovery workflows.
DO $$ BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM pg_constraint
  WHERE conname='pvp_matches_state_object'
    AND conrelid='pvp_matches'::regclass
 ) THEN
  ALTER TABLE pvp_matches
   ADD CONSTRAINT pvp_matches_state_object
   CHECK(state IS NULL OR jsonb_typeof(state)='object');
 END IF;
END $$;

CREATE INDEX IF NOT EXISTS pvp_matches_active_expiry_idx
 ON pvp_matches(expires_at) WHERE status IN('queued','active');
