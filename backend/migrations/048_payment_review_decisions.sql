-- Local sandbox support decisions; never change the payment or wallet state.
CREATE TABLE IF NOT EXISTS stripe_sandbox_review_decisions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 order_id uuid NOT NULL REFERENCES stripe_sandbox_orders(id) ON DELETE CASCADE,
 actor_account_id uuid NOT NULL,
 request_id uuid NOT NULL,
 evidence_key text NOT NULL,
 evidence jsonb NOT NULL,
 action text NOT NULL CHECK(action IN ('reviewed_no_adjustment','escalate')),
 note text NOT NULL CHECK(length(note) BETWEEN 8 AND 500),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(actor_account_id,request_id),
 UNIQUE(order_id,evidence_key)
);
CREATE INDEX IF NOT EXISTS stripe_sandbox_review_decisions_order_idx ON stripe_sandbox_review_decisions(order_id,created_at DESC);
