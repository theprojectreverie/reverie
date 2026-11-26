CREATE TABLE IF NOT EXISTS guild_perks (
 guild_id uuid NOT NULL REFERENCES guilds(id) ON DELETE CASCADE,
 perk_id text NOT NULL CHECK(perk_id IN ('hall_1','hall_2','hall_3')),
 gold_cost integer NOT NULL CHECK(gold_cost>0),
 purchased_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(guild_id,perk_id)
);