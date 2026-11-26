extends Node
func _ready():call_deferred("run")
func run():
 AuthGateway.api_base_url=OS.get_environment("QA_API")
 assert(AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))==OK)
 var auth=await AuthGateway.auth_result
 assert(auth[1])
 assert(await AuthGateway.refresh_account_roster())
 var local_roster=GameState.roster_domain.roster.map(func(c):return c.to_dict().duplicate(true))
 var flow=load("res://scenes/ui/gacha_screen.tscn").instantiate()
 add_child(flow)
 for i in range(200):
  if not flow._summon_flow.online_loading and not flow._summon_flow.online_state.is_empty():break
  await get_tree().create_timer(0.05).timeout
 assert(flow.summon_currency("crystals")==120)
 flow._pull(1)
 for i in range(300):
  if flow._results_layer is SummonRevealOverlay:flow._results_layer.skip_all()
  if not flow._summon_busy:break
  await get_tree().create_timer(0.05).timeout
 assert(not flow._summon_busy and flow._result_cards==1)
 var result=await flow._summon_flow._online_call("/party",{"characterIds":["ravienna_mythic","kael"]})
 assert(result.get("ok",false))
 assert(await AuthGateway.refresh_account_roster())
 # A request already underway when the party changed may finish first.
 for i in range(200):
  if AuthGateway.account_roster.get("party",[])==["ravienna_mythic","kael"]:break
  await get_tree().create_timer(0.05).timeout
 assert(AuthGateway.account_roster.party==["ravienna_mythic","kael"])
 var party=GameState.roster_domain.party_instances()
 assert(party.size()==2 and party[0].char_id=="ravienna_mythic")
 var units=CombatFactory.player_units()
 assert(units.size()==2 and units[0].def_id=="ravienna_mythic")
 assert(units[0].uid=="p_account:ravienna_mythic")
 assert(GameState.roster_domain.roster.map(func(c):return c.to_dict())==local_roster)
 assert(not GameState.roster_domain.owns_character("ravienna_mythic"))
 print("PASS actual Mythic pull -> server party -> combat units; legacy save roster untouched")
 flow.queue_free()
 await get_tree().process_frame
 get_tree().quit(0)
