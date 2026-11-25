-- Reverie auth-data retention maintenance.
-- Run periodically (for example, daily) using the deployment's scheduler.
-- Deletes only expired/revoked session rows and consumed/expired verification
-- token rows after a 30-day grace period. Raw tokens are never stored here.
-- Each statement is bounded to 1,000 rows to limit lock duration and WAL spikes.
-- Safe to rerun. Execute with the least-privileged role allowed to DELETE these rows.

WITH doomed AS (
    SELECT id
    FROM account_sessions
    WHERE (revoked_at IS NOT NULL AND revoked_at < now() - interval '30 days')
       OR (expires_at < now() - interval '30 days')
    ORDER BY COALESCE(revoked_at, expires_at), id
    LIMIT 1000
)
DELETE FROM account_sessions AS s
USING doomed
WHERE s.id = doomed.id;

WITH doomed AS (
    SELECT id
    FROM email_verification_tokens
    WHERE (consumed_at IS NOT NULL AND consumed_at < now() - interval '30 days')
       OR (expires_at < now() - interval '30 days')
    ORDER BY COALESCE(consumed_at, expires_at), id
    LIMIT 1000
)
DELETE FROM email_verification_tokens AS t
USING doomed
WHERE t.id = doomed.id;

-- Repeat the script until both DELETE statements affect zero rows.
-- Schedule externally; do not start an uncoordinated in-process timer in each API replica.
