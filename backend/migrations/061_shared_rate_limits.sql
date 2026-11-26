CREATE TABLE IF NOT EXISTS api_rate_limit_buckets (
 namespace text NOT NULL CHECK(length(namespace) BETWEEN 1 AND 48),
 bucket_hash text NOT NULL CHECK(length(bucket_hash)=64),
 hits integer NOT NULL CHECK(hits BETWEEN 1 AND 2147483647),
 expires_at timestamptz NOT NULL,
 PRIMARY KEY(namespace,bucket_hash)
);
CREATE INDEX IF NOT EXISTS api_rate_limit_expiry_idx ON api_rate_limit_buckets(namespace,expires_at);
