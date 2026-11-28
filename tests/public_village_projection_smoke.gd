extends SceneTree

func _initialize():
 call_deferred("run")
func run():
 var SYNC=load("res://scripts/online/story_village_progression_sync.gd")
 assert(OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")=="1")
 assert(SYNC.use_public_solo(true,true,false,false))
 assert(not SYNC.use_public_solo(false,true,false,false))
 assert(not SYNC.use_public_solo(true,false,false,false))
 assert(not SYNC.use_public_solo(true,true,true,false))
 assert(not SYNC.use_public_solo(true,true,false,true))
 var sync=SYNC.new()
 root.add_child(sync)
 sync._owner="qa-owner"
 var states=[]
 for i in range(SYNC.QUESTS.size()):
  states.append({"quest":SYNC.QUESTS[i],"state":"complete" if i<2 else "active" if i==2 else "not_started","progress":2 if i==0 else 1 if i==1 else 0,"total":2 if i==0 else 3 if i==2 else 1})
 var snapshot={"ok":true,"playerId":"qa-owner","wins":["village_slime_1","village_slime_2","village_crimson_encounter"],"quests":states}
 assert(sync.apply_status(snapshot))
 assert(sync.party_ids()==["kael","crimson_witch_legendary"])
 assert(sync.ready_for_group("village_crownling_1","village_clear_ruins"))
 assert(not sync.ready_for_group("village_nyx_encounter","village_nyx_duel"))
 assert(not sync.ready_for_group("village_crimson_encounter","village_crimson_duel"))
 var wrong=snapshot.duplicate(true)
 wrong.playerId="other"
 assert(not sync.apply_status(wrong))
 assert(sync.party_ids()==["kael","crimson_witch_legendary"])
 sync._fresh=false
 assert(not sync.ready_for_group("village_crownling_1","village_clear_ruins"))
 assert(sync.party_ids()==["kael"])
 print("PUBLIC SOLO SELECTION, VERIFIED PARTY PROJECTION, ACCOUNT SCOPE AND STALE STATUS PASS")
 sync.queue_free()
 await process_frame
 quit(0)