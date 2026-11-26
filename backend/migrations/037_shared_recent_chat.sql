-- Short-lived shared world/party history and one distributed send budget per player.
CREATE TABLE IF NOT EXISTS recent_chat_messages (
 id uuid PRIMARY KEY,
 sender_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 channel text NOT NULL CHECK(channel IN ('world','party')),
 party_id uuid REFERENCES co_op_lobbies(id) ON DELETE CASCADE,
 sender_name text NOT NULL,
 avatar text NOT NULL,
 title text NOT NULL,
 body text NOT NULL CHECK(char_length(body) BETWEEN 1 AND 200),
 reply_to uuid,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK((channel='party')=(party_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS recent_chat_world_idx ON recent_chat_messages(created_at DESC,id DESC) WHERE channel='world';
CREATE INDEX IF NOT EXISTS recent_chat_party_idx ON recent_chat_messages(party_id,created_at DESC,id DESC) WHERE channel='party';
CREATE INDEX IF NOT EXISTS recent_chat_expiry_idx ON recent_chat_messages(created_at);
CREATE TABLE IF NOT EXISTS chat_send_limits (
 player_id uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
 sent_at_ms bigint[] NOT NULL CHECK(cardinality(sent_at_ms)<=5)
);