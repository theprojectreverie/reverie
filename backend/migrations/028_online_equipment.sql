ALTER TABLE character_equipment DROP CONSTRAINT IF EXISTS character_equipment_enhancement_range;
ALTER TABLE character_equipment DROP CONSTRAINT IF EXISTS character_equipment_enhancement_level_check;
ALTER TABLE character_equipment ADD CONSTRAINT character_equipment_enhancement_range CHECK(enhancement_level BETWEEN 0 AND 8);
CREATE TABLE IF NOT EXISTS stored_equipment_progress (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 item_id text NOT NULL REFERENCES items(id),
 enhancement_level smallint NOT NULL CHECK(enhancement_level BETWEEN 0 AND 8),
 reroll_stat text,
 reroll_value numeric(12,4),
 CHECK((reroll_stat IS NULL AND reroll_value IS NULL) OR (reroll_stat IN ('hp','atk','def','spd','crit','crit_dmg') AND reroll_value BETWEEN 0 AND 10000))
);
CREATE INDEX IF NOT EXISTS stored_equipment_player_item_idx ON stored_equipment_progress(player_id,item_id);
CREATE TABLE IF NOT EXISTS equipment_actions (
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 request_id uuid NOT NULL,
 payload jsonb NOT NULL,
 PRIMARY KEY(player_id,request_id)
);