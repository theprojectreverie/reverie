CREATE TABLE IF NOT EXISTS guild_league_finalizations (
 season_start date PRIMARY KEY,
 finalized_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS guild_league_results (
 season_start date NOT NULL REFERENCES guild_league_finalizations(season_start),
 guild_id uuid NOT NULL,
 guild_name text NOT NULL,
 emblem text NOT NULL,
 points bigint NOT NULL CHECK(points>0),
 rank integer NOT NULL CHECK(rank>0),
 contributors integer NOT NULL CHECK(contributors BETWEEN 1 AND 30),
 PRIMARY KEY(season_start,guild_id)
);
CREATE TABLE IF NOT EXISTS guild_league_rewards (
 season_start date NOT NULL REFERENCES guild_league_finalizations(season_start),
 player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
 guild_id uuid NOT NULL,
 rank integer NOT NULL CHECK(rank BETWEEN 1 AND 3),
 tokens integer NOT NULL CHECK(tokens>0),
 points bigint NOT NULL CHECK(points>=200),
 claimed_at timestamptz,
 PRIMARY KEY(season_start,player_id),
 FOREIGN KEY(season_start,guild_id) REFERENCES guild_league_results(season_start,guild_id)
);
CREATE INDEX IF NOT EXISTS guild_league_results_guild_idx ON guild_league_results(guild_id,season_start DESC);
CREATE INDEX IF NOT EXISTS guild_league_rewards_player_idx ON guild_league_rewards(player_id,season_start DESC);