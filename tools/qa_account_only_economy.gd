extends Node
func _ready():call_deferred("run")
func run():
 var summon=load("res://scenes/ui/gacha_screen.tscn").instantiate()
 add_child(summon)
 assert(summon._online_mode and not summon._online_switch.visible)
 assert(not summon.summon_available(1,1,"crystals"))
 var local_balance=GameState.inventory_domain.currency("crystals")
 summon._pull(1)
 await get_tree().process_frame
 assert(GameState.inventory_domain.currency("crystals")==local_balance)
 summon.queue_free()
 await get_tree().process_frame
 AuthGateway.api_base_url=OS.get_environment("QA_API")
 assert(AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))==OK)
 var auth=await AuthGateway.auth_result
 assert(auth[1])
 summon=load("res://scenes/ui/gacha_screen.tscn").instantiate()
 add_child(summon)
 for i in range(200):
  if not summon._summon_flow.online_loading and not summon._summon_flow.online_state.is_empty():break
  await get_tree().create_timer(0.05).timeout
 assert(summon.summon_currency("crystals")==120)
 await summon._toggle_online(false)
 assert(summon._online_mode and summon.summon_currency("crystals")==120)
 summon._pull(1)
 for i in range(300):
  if summon._results_layer is SummonRevealOverlay:summon._results_layer.skip_all()
  if not summon._summon_busy:break
  await get_tree().create_timer(0.05).timeout
 assert(not summon._summon_busy and summon._result_cards==1)
 assert(summon.summon_currency("crystals")==0)
 summon.queue_free()
 await get_tree().process_frame
 var collection=load("res://scenes/ui/collection_screen.tscn").instantiate()
 add_child(collection)
 for i in range(200):
  if collection.has_node("OnlineCollectionOverlay") and collection.get_node("OnlineCollectionOverlay")._collection_visible():break
  await get_tree().create_timer(0.05).timeout
 assert(collection._grid==null)
 var account=collection.get_node("OnlineCollectionOverlay")
 assert(account.collection_only and account._collection_visible() and not account.get_node("OnlineRosterDialog").visible and not collection._shell.visible)
 assert(account._summon_flow.online_state.roster.any(func(row):return row.char_id=="ravienna_mythic"))
 assert(not account._collection_body().get_node("Collection/CompareProgress").visible)
 collection.queue_free()
 await get_tree().process_frame
 var inventory=load("res://scenes/ui/inventory_screen.tscn").instantiate()
 add_child(inventory)
 inventory._set_inventory_mode(false)
 assert(inventory._online_mode and inventory._local_layout==null and not inventory._inventory_mode.visible)
 for i in range(200):
  if not AuthGateway.online_wallet.is_empty() and AuthGateway.online_currencies.get("crystals",-1)==0:break
  await get_tree().create_timer(0.05).timeout
 assert(AuthGateway.online_currencies.get("crystals",-1)==0)
 print("PASS account-only summons, actual pulled Mythic appears in Party, inventory shares account wallet; offline requests blocked")
 inventory.queue_free()
 await get_tree().process_frame
 # Allow the reveal close fade and final one-shot cues to finish before shutdown.
 await get_tree().create_timer(1.0).timeout
 var previous_player=str(AuthGateway.current_player().get("id",""))
 var switching=load("res://scenes/ui/gacha_screen.tscn").instantiate()
 add_child(switching)
 for i in range(200):
  if switching._account_state_ready():break
  await get_tree().create_timer(0.05).timeout
 assert(switching._account_state_ready())
 switching._show_online_roster()
 switching._select_current_online_character("ravienna_mythic")
 assert(switching._online_selected.get("char_id")=="ravienna_mythic")
 var grid=switching.get_node("OnlineRosterDialog/BodyScroll/Collection/Scroll/Grid")
 var api=AuthGateway.api_base_url
 AuthGateway.api_base_url=api+"/unavailable"
 assert(not await switching._summon_flow.refresh_online_state())
 print("PASS failed API request")
 assert(grid.get_child_count()==0 and switching._online_selected.is_empty())
 assert(not switching.summon_available(1,1,"crystals"))
 AuthGateway.api_base_url=api
 await switching._refresh_live_collection()
 assert(switching._account_state_ready() and grid.get_child_count()>0)
 switching._select_current_online_character("ravienna_mythic")
 AuthGateway.logout()
 assert(grid.get_child_count()==0 and switching._online_selected.is_empty())
 assert(not switching._account_state_ready())
 assert(AuthGateway.login(OS.get_environment("QA_NAME_B"),OS.get_environment("QA_PASSWORD"))==OK)
 var second=await AuthGateway.auth_result
 while second[0]!="login":second=await AuthGateway.auth_result
 assert(second[1] and str(AuthGateway.current_player().get("id",""))!=previous_player)
 for i in range(200):
  if switching._account_state_ready() and grid.get_child_count()>0:break
  await get_tree().create_timer(0.05).timeout
 assert(switching._account_state_ready())
 assert(switching.summon_currency("crystals")==777)
 assert(not switching._summon_flow.online_state.roster.any(func(row):return row.char_id=="ravienna_mythic"))
 switching._select_current_online_character("ravienna_mythic")
 assert(switching._online_selected.is_empty())
 print("PASS disconnection clears collection, reconnect restores current account, logout clears old portraits, second account gets separate wallet and roster")
 switching.queue_free()
 await get_tree().process_frame
 await AudioDirector.drain_for_shutdown()
 get_tree().quit(0)
