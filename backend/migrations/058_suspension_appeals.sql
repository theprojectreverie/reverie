CREATE TABLE IF NOT EXISTS reverie_suspension_appeals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 suspension_id uuid NOT NULL UNIQUE REFERENCES reverie_account_suspensions(id) ON DELETE CASCADE,
 statement text NOT NULL CHECK(length(statement) BETWEEN 10 AND 1000),
 created_at timestamptz NOT NULL DEFAULT now(),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','closed')),
 reviewed_by uuid,
 review_note text,
 reviewed_at timestamptz,
 CHECK((status='pending' AND reviewed_by IS NULL AND review_note IS NULL AND reviewed_at IS NULL) OR
 (status<>'pending' AND reviewed_by IS NOT NULL AND review_note IS NOT NULL AND length(review_note) BETWEEN 8 AND 300 AND reviewed_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS reverie_appeal_queue_idx ON reverie_suspension_appeals(status,created_at,id);