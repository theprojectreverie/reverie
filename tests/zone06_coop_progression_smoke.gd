extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["ravienna_resurrected"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn")
 await scene_changed
 for i in range(8):await process_frame
 var zone=current_scene
 var boss=zone.get_node("ReviennaEncounter")
 var sync=zone.get_node_or_null("CoopWorldSync")
 if sync==null:
  sync=load("res://scripts/online/coop_world_sync_component.gd").new()
  sync.name="CoopWorldSync"
  zone.add_child(sync)
 sync.active_world=zone
 sync.active_region_id="six_zone_ruined_tower"
 sync.local_player_id="local"
 var gateway=root.get_node("MultiplayerGateway")
 gateway.standalone_expedition_region="six_zone_ruined_tower"
 gateway.standalone_expedition_id="isolated-test"
 var nav=load("res://scripts/world/six_zone_reverie/expedition_navigation.gd")
 assert(not nav.resolve(zone).ready)
 sync._snapshot_ready=true
 var warning={"name":"Eclipse Verdict","targetId":"local","resolveAt":2000}
 sync._apply_monster_state({"monsterId":"revienna_encounter","hp":850,"phase":2,"warning":warning})
 assert(boss.coop_hp==850 and boss.coop_phase==2 and boss._is_warning_target())
 assert(nav.resolve(zone).ready and not nav.resolve(zone).complete)
 sync._apply_monster_state({"kind":"boss_guard","monsterId":"cassien_encounter","playerId":"local","resolveAt":2000})
 assert(boss.coop_guard_ack==0)
 sync._apply_monster_state({"kind":"boss_guard","monsterId":"revienna_encounter","playerId":"local","resolveAt":1000})
 assert(boss.coop_guard_ack==0)
 sync._apply_monster_state({"kind":"boss_guard","monsterId":"revienna_encounter","playerId":"ally","resolveAt":2000})
 assert(boss.coop_guard_ack==0)
 sync._apply_monster_state({"kind":"boss_guard","monsterId":"revienna_encounter","playerId":"local","resolveAt":2000})
 assert(boss.coop_guard_ack==2000)
 warning={"name":"Eclipse Verdict","targetId":"ally","resolveAt":2000,"guardAcknowledged":true}
 sync._apply_monster_state({"monsterId":"revienna_encounter","hp":850,"phase":2,"warning":warning})
 assert(boss.coop_guard_ack==0 and not boss._is_warning_target())
 warning={"name":"Eclipse Verdict","targetId":"local","resolveAt":3000,"guardAcknowledged":true}
 sync._apply_monster_state({"monsterId":"revienna_encounter","hp":400,"phase":3,"warning":warning})
 assert(boss.coop_guard_ack==3000)
 print("BOSS GUARD TARGET, DEADLINE, BOSS ID AND RECOVERY ACK PASS")
 var resolved={"monsterId":"revienna_encounter","hp":400,"phase":3,"resolvedSpecial":"Eclipse Verdict","guarded":true}
 sync._apply_monster_state(resolved,false)
 assert(boss.coop_special_count==0 and boss.coop_guard_ack==0)
 sync._apply_monster_state(resolved,true)
 assert(boss.coop_special_count==1 and boss.coop_guard_count==1)
 sync._apply_monster_state({"monsterId":"revienna_encounter","hp":0,"phase":3})
 assert(boss.defeated and not boss.can_interact())
 assert(nav.resolve(zone).complete and not nav.resolve(zone).valid)
 assert(not gs.quest_domain.flags.get("revienna_defeated",false))
 assert(not gs.quest_domain.flags.get("revienna_solo_reward_claimed",false))
 print("SHARED VICTORY, NO SOLO FLAGS OR PAYOUT, REPLAY COUNTERS PASS")
 gateway.standalone_expedition_id=""
 gateway.standalone_expedition_region=""
 current_scene.queue_free()
 for i in range(10):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.5).timeout
 quit(0)
