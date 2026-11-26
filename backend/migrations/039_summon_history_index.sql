CREATE INDEX IF NOT EXISTS gacha_pulls_player_history_idx ON gacha_pulls(player_id, created_at DESC, id DESC);
