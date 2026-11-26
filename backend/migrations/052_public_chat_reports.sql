CREATE TABLE IF NOT EXISTS reverie_chat_reports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 reporter_id uuid NOT NULL,
 message_id uuid NOT NULL,
 target_player_id uuid NOT NULL,
 target_name text NOT NULL,
 message_text text NOT NULL,
 message_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','resolved','dismissed')),
 reviewed_by uuid,
 review_note text,
 reviewed_at timestamptz,
 UNIQUE(reporter_id,message_id),
 CHECK((status='pending' AND reviewed_by IS NULL AND reviewed_at IS NULL AND review_note IS NULL) OR
 (status<>'pending' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND length(review_note) BETWEEN 8 AND 300))
);
CREATE INDEX IF NOT EXISTS reverie_reports_queue_idx ON reverie_chat_reports(status,created_at,id);
CREATE INDEX IF NOT EXISTS reverie_reports_reporter_idx ON reverie_chat_reports(reporter_id,created_at);