-- Optional player-controlled sandbox spending limits; existing accounts default to unlimited.
CREATE TABLE IF NOT EXISTS stripe_sandbox_spending_limits (
 player_id uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
 daily_cents integer CHECK(daily_cents BETWEEN 0 AND 100000000),
 monthly_cents integer CHECK(monthly_cents BETWEEN 0 AND 100000000),
 updated_at timestamptz NOT NULL DEFAULT now()
);
