INSERT INTO currencies(id,display_name,is_premium) VALUES ('paid_moonstones','Paid Moonstones',true) ON CONFLICT(id) DO NOTHING;
CREATE INDEX IF NOT EXISTS gacha_paid_moonstones_player_idx ON gacha_pulls(player_id) WHERE currency_id='paid_moonstones';
