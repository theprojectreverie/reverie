-- Persistent-world event-log retention maintenance.
-- Run daily using the deployment scheduler; repeat until zero rows are deleted.
-- Keep 30 days of history to bound storage while allowing ordinary reconnect recovery.
-- Each batch is capped at 1,000 rows to limit lock duration and WAL pressure.
WITH doomed AS (
 SELECT server_id,sequence
 FROM game_server_world_events
 WHERE created_at < now() - interval '30 days'
 ORDER BY created_at,server_id,sequence
 LIMIT 1000
)
DELETE FROM game_server_world_events e
USING doomed d
WHERE e.server_id=d.server_id AND e.sequence=d.sequence;
