ALTER TABLE recent_chat_messages ADD COLUMN IF NOT EXISTS guild_id uuid REFERENCES guilds(id) ON DELETE CASCADE;
ALTER TABLE recent_chat_messages DROP CONSTRAINT IF EXISTS recent_chat_messages_channel_check;
ALTER TABLE recent_chat_messages DROP CONSTRAINT IF EXISTS recent_chat_messages_check;
ALTER TABLE recent_chat_messages DROP CONSTRAINT IF EXISTS recent_chat_scope_check;
ALTER TABLE recent_chat_messages ADD CONSTRAINT recent_chat_scope_check CHECK(
 (channel='world' AND party_id IS NULL AND guild_id IS NULL)
 OR (channel='party' AND party_id IS NOT NULL AND guild_id IS NULL)
 OR (channel='guild' AND party_id IS NULL AND guild_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS recent_chat_guild_idx ON recent_chat_messages(guild_id,created_at DESC,id DESC) WHERE channel='guild';