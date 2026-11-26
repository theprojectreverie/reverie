-- Keep donations in the existing double-sided wallet and guild bank ledgers.
ALTER TABLE guild_bank_ledger ADD COLUMN IF NOT EXISTS request_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS guild_bank_donation_request_idx ON guild_bank_ledger(player_id,request_id) WHERE request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS guild_bank_gold_history_idx ON guild_bank_ledger(guild_id,created_at DESC,id DESC) WHERE currency_id='gold';
CREATE INDEX IF NOT EXISTS currency_ledger_guild_donation_idx ON currency_ledger(player_id,created_at DESC) WHERE reason='guild_donation' AND currency_id='gold';