CREATE INDEX IF NOT EXISTS gacha_pulls_recent_world_chat_idx ON gacha_pulls (created_at DESC, id);
