CREATE TABLE IF NOT EXISTS reverie_account_suspensions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 actor_account_id uuid NOT NULL,
 target_name text NOT NULL,
 reason text NOT NULL CHECK(length(reason) BETWEEN 8 AND 300),
 suspension_version integer NOT NULL CHECK(suspension_version>=0),
 created_at timestamptz NOT NULL DEFAULT now(),
 suspended_until timestamptz NOT NULL,
 ended_at timestamptz,
 ended_by uuid,
 end_reason text,
 CHECK(suspended_until>created_at),
 CHECK((ended_at IS NULL AND ended_by IS NULL AND end_reason IS NULL) OR (ended_at IS NOT NULL AND end_reason IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS reverie_one_open_suspension ON reverie_account_suspensions(account_id) WHERE ended_at IS NULL;
CREATE INDEX IF NOT EXISTS reverie_suspension_history ON reverie_account_suspensions(created_at DESC);