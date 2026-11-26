CREATE TABLE IF NOT EXISTS co_op_friend_invites (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 lobby_id uuid NOT NULL REFERENCES co_op_lobbies(id) ON DELETE CASCADE,
 sender_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 recipient_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 expires_at timestamptz NOT NULL DEFAULT (now()+interval '10 minutes'),
 UNIQUE(lobby_id,recipient_id),
 CHECK(sender_id<>recipient_id)
);
CREATE INDEX IF NOT EXISTS co_op_friend_invites_recipient_idx ON co_op_friend_invites(recipient_id,expires_at);