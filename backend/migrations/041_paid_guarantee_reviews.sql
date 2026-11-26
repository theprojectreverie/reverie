CREATE TABLE IF NOT EXISTS paid_guarantee_reviews (
 pull_id uuid NOT NULL REFERENCES gacha_pulls(id) ON DELETE CASCADE,
 roll_index integer NOT NULL CHECK (roll_index>=0 AND roll_index<10),
 requested_at timestamptz NOT NULL DEFAULT now(),
 status text NOT NULL DEFAULT 'pending_review' CHECK(status IN ('pending_review','resolved','rejected')),
 PRIMARY KEY(pull_id,roll_index)
);
