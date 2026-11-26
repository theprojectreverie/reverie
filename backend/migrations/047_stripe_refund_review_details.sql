-- Test-only refund review metadata. Existing orders and wallets are not modified.
ALTER TABLE stripe_sandbox_orders ADD COLUMN IF NOT EXISTS refunded_cents integer NOT NULL DEFAULT 0 CHECK(refunded_cents >= 0 AND refunded_cents <= amount_cents);
ALTER TABLE stripe_sandbox_orders ADD COLUMN IF NOT EXISTS dispute_seen boolean NOT NULL DEFAULT false;
ALTER TABLE stripe_sandbox_orders ADD COLUMN IF NOT EXISTS review_reason text;
