-- Account session query support and bounded active-session lookup.
CREATE INDEX IF NOT EXISTS account_sessions_active_account_idx
 ON account_sessions(account_id,created_at DESC,id DESC)
 WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS account_sessions_expiry_cleanup_idx
 ON account_sessions(expires_at)
 WHERE revoked_at IS NULL;