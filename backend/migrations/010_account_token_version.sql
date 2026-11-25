-- Version access tokens per account so logout-all invalidates issued JWTs.
ALTER TABLE accounts
 ADD COLUMN IF NOT EXISTS token_version integer NOT NULL DEFAULT 0;
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='accounts_token_version_nonnegative') THEN
  ALTER TABLE accounts ADD CONSTRAINT accounts_token_version_nonnegative CHECK (token_version >= 0);
 END IF;
END $$;
