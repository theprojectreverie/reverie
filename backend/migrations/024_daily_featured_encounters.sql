ALTER TABLE online_daily_quests ADD COLUMN IF NOT EXISTS encounter_credits text[] NOT NULL DEFAULT '{}';
