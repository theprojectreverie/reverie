ALTER TABLE regional_server_incidents ADD COLUMN IF NOT EXISTS acknowledged_at timestamptz;
ALTER TABLE regional_server_incidents ADD COLUMN IF NOT EXISTS acknowledged_by uuid REFERENCES accounts(id) ON DELETE SET NULL;
ALTER TABLE regional_server_incidents ADD COLUMN IF NOT EXISTS acknowledgment_note text CHECK(length(acknowledgment_note) BETWEEN 3 AND 300);
