-- Private invite-code access and serialized world-event sequence allocation.
ALTER TABLE co_op_lobbies ADD COLUMN IF NOT EXISTS invite_code_hash text;
ALTER TABLE co_op_lobbies ADD COLUMN IF NOT EXISTS next_event_sequence bigint NOT NULL DEFAULT 1 CHECK(next_event_sequence>0);
CREATE UNIQUE INDEX IF NOT EXISTS co_op_lobbies_invite_hash_uq ON co_op_lobbies(invite_code_hash) WHERE invite_code_hash IS NOT NULL;
