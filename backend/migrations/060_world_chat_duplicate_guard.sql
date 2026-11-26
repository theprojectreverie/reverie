-- Public text only. Reuse existing retained messages rather than retaining
-- another copy of text or inspecting private conversations.
CREATE INDEX IF NOT EXISTS recent_chat_world_sender_time_idx ON recent_chat_messages(sender_id,created_at DESC) WHERE channel='world';
CREATE OR REPLACE FUNCTION reverie_world_chat_fingerprint(value text) RETURNS text
LANGUAGE sql IMMUTABLE STRICT AS $$
 SELECT lower(regexp_replace(btrim(normalize(value,NFKC)), '[[:space:]]+', ' ', 'g'))
$$;
CREATE OR REPLACE FUNCTION reverie_enforce_world_duplicate_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE fingerprint text; repeats integer;
BEGIN
 IF NEW.channel<>'world' THEN RETURN NEW; END IF;
 fingerprint:=reverie_world_chat_fingerprint(NEW.body);
 -- Permit ordinary short reactions and stickers; the general rate cap still applies.
 IF char_length(fingerprint)<12 OR fingerprint ~ '^\[sticker:[a-z_]+\]$' THEN RETURN NEW; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('reverie-chat:'||NEW.sender_id::text,0));
 SELECT count(*) INTO repeats FROM (
  SELECT 1 FROM recent_chat_messages m
  WHERE m.sender_id=NEW.sender_id AND m.channel='world'
   AND m.created_at>=clock_timestamp()-interval '60 seconds'
   AND reverie_world_chat_fingerprint(m.body)=fingerprint
  LIMIT 3
 ) duplicate_matches;
 IF repeats>=3 THEN RAISE EXCEPTION 'chat_duplicate_spam' USING ERRCODE='P0001'; END IF;
 RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS reverie_world_duplicate_guard ON recent_chat_messages;
CREATE TRIGGER reverie_world_duplicate_guard BEFORE INSERT ON recent_chat_messages FOR EACH ROW EXECUTE FUNCTION reverie_enforce_world_duplicate_guard();