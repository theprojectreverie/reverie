CREATE TABLE IF NOT EXISTS api_operational_history (
 instance_id text NOT NULL CHECK(instance_id ~ '^[a-zA-Z0-9_-]{1,48}$'),
 sampled_at timestamptz NOT NULL,
 sample jsonb NOT NULL CHECK(jsonb_typeof(sample)='object' AND octet_length(sample::text)<=2048),
 PRIMARY KEY(instance_id,sampled_at)
);
