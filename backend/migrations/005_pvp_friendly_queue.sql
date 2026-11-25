-- Friendly-duel matchmaking reservations. A queued match is not combat-ready until
-- a server-authoritative roster and persisted runtime state are attached.
CREATE TABLE IF NOT EXISTS pvp_queue_tickets (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 mode text NOT NULL DEFAULT 'friendly_duel' CHECK(mode='friendly_duel'),
 status text NOT NULL DEFAULT 'waiting' CHECK(status IN('waiting','matched','cancelled','expired')),
 match_id uuid REFERENCES pvp_matches(id) ON DELETE SET NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT (now()+interval '5 minutes'),
 matched_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS pvp_queue_one_waiting_ticket_per_player
 ON pvp_queue_tickets(player_id) WHERE status='waiting';
CREATE INDEX IF NOT EXISTS pvp_queue_waiting_fifo_idx
 ON pvp_queue_tickets(created_at,id) WHERE status='waiting';
CREATE INDEX IF NOT EXISTS pvp_queue_match_idx ON pvp_queue_tickets(match_id) WHERE match_id IS NOT NULL;
