-- Optional deployment maintenance: repeat in batches until no expired rows remain.
-- Active API instances already run a bounded cleanup each minute.
WITH doomed AS (
 SELECT id FROM recent_chat_messages
 WHERE created_at<now()-interval '30 minutes'
 ORDER BY created_at LIMIT 1000 FOR UPDATE SKIP LOCKED
)
DELETE FROM recent_chat_messages m USING doomed d WHERE m.id=d.id;