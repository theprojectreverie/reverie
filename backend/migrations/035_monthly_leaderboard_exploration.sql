CREATE TABLE IF NOT EXISTS online_season_exploration (
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 season_start date NOT NULL,
 region_id text NOT NULL,
 objective_id text NOT NULL,
 PRIMARY KEY(player_id,season_start,region_id,objective_id)
);
-- Only retained validated server events have trustworthy historical timestamps.
INSERT INTO online_season_exploration(player_id,season_start,region_id,objective_id)
SELECT DISTINCT e.actor_player_id,date_trunc('month',e.created_at AT TIME ZONE 'UTC')::date,e.payload->>'regionId',e.payload->>'objectiveId'
FROM co_op_world_events e JOIN players p ON p.id=e.actor_player_id
WHERE e.event_type='interaction' AND e.payload->>'kind'='exploration_objective'
AND (e.payload->>'regionId',e.payload->>'objectiveId') IN (
 ('six_zone_willow_fields','willow_bridge'),('six_zone_willow_fields','willow_ruins'),
 ('six_zone_elderwood_grove','elderwood_memorial'),('six_zone_elderwood_grove','elderwood_pillar'),
 ('six_zone_forsaken_ruins','ruins_western_brazier'),('six_zone_forsaken_ruins','ruins_central_brazier'),
 ('six_zone_forsaken_ruins','ruins_eastern_brazier'),('six_zone_forsaken_ruins','cassien_resurrection'))
ON CONFLICT DO NOTHING;
