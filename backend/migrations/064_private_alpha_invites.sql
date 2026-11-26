CREATE TABLE IF NOT EXISTS reverie_alpha_invites (
 token_hash text PRIMARY KEY CHECK(length(token_hash)=64),
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL,
 used_at timestamptz,
 used_by uuid REFERENCES accounts(id) ON DELETE SET NULL,
 CHECK(expires_at>created_at)
);