-- Sandbox payment orders only. Live payments are deliberately disabled in the API.
CREATE TABLE IF NOT EXISTS stripe_sandbox_orders (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 request_id uuid NOT NULL,
 package_id text NOT NULL,
 stones integer NOT NULL CHECK (stones > 0),
 amount_cents integer NOT NULL CHECK (amount_cents > 0),
 currency text NOT NULL CHECK (currency='eur'),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','credited','expired','refund_review','refunded')),
 session_id text UNIQUE,
 payment_intent_id text UNIQUE,
 created_at timestamptz NOT NULL DEFAULT now(),
 credited_at timestamptz,
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(player_id,request_id)
);
CREATE INDEX IF NOT EXISTS stripe_sandbox_orders_player_time_idx ON stripe_sandbox_orders(player_id,created_at DESC);
