CREATE TABLE IF NOT EXISTS reverie_chat_mutes (
 player_id uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
 muted_until timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS reverie_moderation_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 actor_account_id uuid NOT NULL,
 target_player_id uuid NOT NULL,
 target_name text NOT NULL,
 action text NOT NULL CHECK(action IN ('warn','mute','unmute')),
 reason text NOT NULL CHECK(length(reason) BETWEEN 8 AND 300),
 muted_until timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS reverie_moderation_target_idx ON reverie_moderation_audit(target_player_id,id DESC);
-- The sender lock is shared with the moderation transaction, so a committed
-- mute applies to all later inserts even across API processes.
CREATE OR REPLACE FUNCTION reverie_enforce_chat_mute() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('reverie-chat:'||NEW.sender_id::text,0));
 IF EXISTS(SELECT 1 FROM reverie_chat_mutes WHERE player_id=NEW.sender_id AND muted_until>clock_timestamp()) THEN
  RAISE EXCEPTION 'chat_muted' USING ERRCODE='P0001';
 END IF;
 RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS reverie_mute_recent_chat ON recent_chat_messages;
CREATE TRIGGER reverie_mute_recent_chat BEFORE INSERT ON recent_chat_messages FOR EACH ROW EXECUTE FUNCTION reverie_enforce_chat_mute();
DROP TRIGGER IF EXISTS reverie_mute_private_chat ON private_chat_messages;
CREATE TRIGGER reverie_mute_private_chat BEFORE INSERT ON private_chat_messages FOR EACH ROW EXECUTE FUNCTION reverie_enforce_chat_mute();