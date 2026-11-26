INSERT INTO currencies(id,display_name,is_premium) VALUES('guild_tokens','Guild Tokens',false) ON CONFLICT(id) DO NOTHING;
CREATE TABLE IF NOT EXISTS guild_shop_purchases (
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 request_id uuid NOT NULL,
 guild_id uuid REFERENCES guilds(id) ON DELETE SET NULL,
 week_start date NOT NULL,
 offer_id text NOT NULL,
 item_id text NOT NULL REFERENCES items(id),
 quantity integer NOT NULL CHECK(quantity>0),
 cost integer NOT NULL CHECK(cost>0),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(player_id,request_id)
);
CREATE INDEX IF NOT EXISTS guild_shop_week_idx ON guild_shop_purchases(player_id,week_start,offer_id);