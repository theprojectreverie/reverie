CREATE INDEX IF NOT EXISTS currency_ledger_paid_player_id_idx ON currency_ledger(player_id,id DESC) WHERE currency_id='paid_moonstones';
