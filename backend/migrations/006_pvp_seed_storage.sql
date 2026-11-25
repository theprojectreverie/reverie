-- Retain the server-only seed needed for deterministic battle resolution.
ALTER TABLE pvp_matches ADD COLUMN IF NOT EXISTS server_seed bytea;
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pvp_matches_server_seed_length') THEN
  ALTER TABLE pvp_matches ADD CONSTRAINT pvp_matches_server_seed_length CHECK (server_seed IS NULL OR octet_length(server_seed)=32);
 END IF;
END $$;
