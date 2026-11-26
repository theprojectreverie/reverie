extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 var screen=load("res://scenes/ui/chat_screen.tscn").instantiate()
 root.add_child(screen)
 await process_frame
 assert(screen._layout!=null)
 var message={"kind":"mythic_summon","channel":"world","playerId":"test","name":"Summoner","characterId":"ravienna_mythic","text":"Summoner summoned Mythic Revienna!"}
 screen._render([message,{"playerId":"ordinary","name":"Player","text":"Hello"}])
 var history=screen._layout.get_node("History")
 assert(history.get_parsed_text().contains("[MYTHIC SUMMON] Summoner summoned Mythic Revienna!"))
 assert(history.get_parsed_text().contains("Hello"))
 assert(screen._layout.get_node("PlayerActions/Players").item_count==1)
 screen.queue_free()
 await process_frame
 print("MYTHIC WORLD CHAT SPECIAL RENDER PASS")
 quit(0)
