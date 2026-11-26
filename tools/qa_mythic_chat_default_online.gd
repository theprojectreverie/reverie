extends Node
func _ready(): call_deferred("run")
func run():
 AuthGateway.api_base_url=OS.get_environment("QA_API")
 assert(AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))==OK)
 var auth=await AuthGateway.auth_result
 assert(auth[1])
 var screen=load("res://scenes/ui/gacha_screen.tscn").instantiate()
 add_child(screen)
 assert(screen._online_mode)
 for i in range(200):
  if not screen._summon_flow.online_loading and not screen._summon_flow.online_state.is_empty():break
  await get_tree().create_timer(0.05).timeout
 assert(screen.summon_currency("crystals")==120)
 var local_balance=GameState.inventory_domain.currency("crystals")
 screen._pull(1)
 for i in range(300):
  if screen._results_layer is SummonRevealOverlay:
   screen._results_layer.skip_all()
  if not screen._summon_busy:break
  await get_tree().create_timer(0.05).timeout
 assert(not screen._summon_busy and screen._result_cards==1)
 assert(screen.summon_currency("crystals")==0 and GameState.inventory_domain.currency("crystals")==local_balance)
 print("PASS authenticated default online pull, local wallet unchanged")
 screen.queue_free()
 await get_tree().process_frame
 get_tree().quit(0)
