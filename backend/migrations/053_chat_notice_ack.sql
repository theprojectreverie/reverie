-- Acknowledgements are separate from immutable moderation action evidence.
CREATE TABLE IF NOT EXISTS reverie_notice_acknowledgements (
 notice_id bigint NOT NULL REFERENCES reverie_moderation_audit(id) ON DELETE CASCADE,
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 acknowledged_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(notice_id,player_id)
);