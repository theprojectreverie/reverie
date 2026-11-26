-- Private conversations are stored separately from ephemeral world/party chat.
CREATE TABLE IF NOT EXISTS private_chat_messages (
 id uuid PRIMARY KEY,
 sender_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 recipient_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 body text NOT NULL CHECK(char_length(body) BETWEEN 1 AND 200),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 read_at timestamptz,
 CHECK(sender_id<>recipient_id)
);
CREATE INDEX IF NOT EXISTS private_chat_pair_idx ON private_chat_messages(sender_id,recipient_id,created_at DESC,id);
CREATE INDEX IF NOT EXISTS private_chat_unread_idx ON private_chat_messages(recipient_id,sender_id) WHERE read_at IS NULL;