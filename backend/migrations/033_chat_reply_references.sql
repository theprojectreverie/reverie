-- Store only the reply reference, never a duplicated private message body.
ALTER TABLE private_chat_messages ADD COLUMN IF NOT EXISTS reply_to uuid REFERENCES private_chat_messages(id) ON DELETE SET NULL;
