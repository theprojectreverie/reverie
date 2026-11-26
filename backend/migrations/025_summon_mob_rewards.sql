ALTER TABLE gacha_pull_results ADD COLUMN IF NOT EXISTS reward_items jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE gacha_pull_results ADD COLUMN IF NOT EXISTS reward_kind text NOT NULL DEFAULT 'character';
INSERT INTO items(id,display_name,category,rarity) VALUES
 ('moonpetal','Moonpetal','material','rare'),
 ('dew_of_awakening','Dew of Awakening','material','epic'),
 ('gothic_shard','Gothic Shard','material','rare')
ON CONFLICT(id) DO NOTHING;
