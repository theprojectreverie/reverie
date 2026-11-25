-- Keep player world position when an assignment is released or a socket disconnects.
ALTER TABLE game_server_player_state
 DROP CONSTRAINT IF EXISTS game_server_player_state_server_id_player_id_fkey;
ALTER TABLE game_server_player_state
 ADD CONSTRAINT game_server_player_state_server_fk FOREIGN KEY(server_id)
 REFERENCES game_servers(id) ON DELETE CASCADE;
ALTER TABLE game_server_player_state
 ADD CONSTRAINT game_server_player_state_player_fk FOREIGN KEY(player_id)
 REFERENCES players(id) ON DELETE CASCADE;
