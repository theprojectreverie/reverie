CREATE TABLE IF NOT EXISTS reverie_currency_grants (
 request_id uuid PRIMARY KEY,
 actor_account_id uuid NOT NULL,
 actor_name text NOT NULL,
 target_player_id uuid NOT NULL,
 target_name text NOT NULL,
 currency_id text NOT NULL REFERENCES currencies(id),
 amount bigint NOT NULL CHECK(amount BETWEEN 1 AND 1000000),
 balance_after bigint NOT NULL CHECK(balance_after>=0),
 note text NOT NULL CHECK(length(note) BETWEEN 8 AND 300),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS reverie_currency_grants_recent_idx ON reverie_currency_grants(created_at DESC);