ALTER TABLE paid_guarantee_reviews ADD COLUMN IF NOT EXISTS decided_at timestamptz,
 ADD COLUMN IF NOT EXISTS decided_by uuid,
 ADD COLUMN IF NOT EXISTS decision_note text,
 ADD COLUMN IF NOT EXISTS granted_character_id text,
 ADD COLUMN IF NOT EXISTS grant_details jsonb;
CREATE INDEX IF NOT EXISTS paid_guarantee_reviews_pending_idx ON paid_guarantee_reviews(requested_at,pull_id,roll_index) WHERE status='pending_review';
