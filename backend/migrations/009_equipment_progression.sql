-- Persist equipment enhancement and reroll progression for authoritative PvP roster builds.
ALTER TABLE character_equipment
 ADD COLUMN IF NOT EXISTS enhancement_level smallint NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS reroll_stat text,
 ADD COLUMN IF NOT EXISTS reroll_value numeric(12,4);
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='character_equipment_enhancement_range' AND conrelid='character_equipment'::regclass) THEN
  ALTER TABLE character_equipment ADD CONSTRAINT character_equipment_enhancement_range CHECK(enhancement_level BETWEEN 0 AND 5);
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='character_equipment_reroll_pair' AND conrelid='character_equipment'::regclass) THEN
  ALTER TABLE character_equipment ADD CONSTRAINT character_equipment_reroll_pair CHECK(
   (reroll_stat IS NULL AND reroll_value IS NULL) OR
   (reroll_stat IN('hp','atk','def','spd','crit','crit_dmg') AND reroll_value IS NOT NULL AND reroll_value>=0 AND reroll_value<=10000)
  );
 END IF;
END $$;
