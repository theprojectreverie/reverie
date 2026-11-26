-- First story milestone reaches observed after telemetry is enabled.
-- No rows are backfilled from existing local game saves.
CREATE TABLE IF NOT EXISTS story_milestone_reaches (
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 milestone_id text NOT NULL CHECK(milestone_id IN (
  'village','royal_gardens','royal_gate','willow_fields',
  'elderwood_grove','forsaken_ruins','ruined_tower','chapter_complete'
 )),
 reached_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(player_id,milestone_id)
);
CREATE INDEX IF NOT EXISTS story_milestone_reaches_milestone_time_idx
 ON story_milestone_reaches(milestone_id,reached_at);
