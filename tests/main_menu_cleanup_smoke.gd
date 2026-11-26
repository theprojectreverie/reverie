extends SceneTree
func _initialize():call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var menu=load("res://scenes/ui/main_menu.tscn").instantiate();root.add_child(menu)
 for i in range(8):await process_frame
 var hub=menu.get_node("ReferenceInterface");var bottom=hub.get_node("BottomNavigation");var rail=hub.get_node("LeftRail")
 assert(bottom.get_child_count()==7 and rail.get_child_count()==4)
 for b in bottom.get_children():
  assert(b.visible and not b.text.is_empty() and b.pressed.get_connections().size()>0)
 for b in rail.get_children():assert(b.visible and b.pressed.get_connections().size()>0)
 for b in hub.get_node("CurrencyBar").get_children():
  if b.name=="PaidCurrency" and OS.get_name() not in ["Android","iOS","Web"]:
   assert(b.mouse_filter==Control.MOUSE_FILTER_STOP and b.focus_mode==Control.FOCUS_ALL and b.text.ends_with("+") and b.pressed.get_connections().size()>0)
  else:assert(b.mouse_filter==Control.MOUSE_FILTER_IGNORE and b.focus_mode==Control.FOCUS_NONE)
 for pair in [["BottomNavigation/WorldButton","WorldMapOverlay"],["BottomNavigation/CharactersButton","CharactersOverlay"],["BottomNavigation/InventoryButton","InventoryOverlay"],["BottomNavigation/SummonButton","SummonOverlay"],["LeftRail/EventsButton","DailyQuestsOverlay"],["LeftRail/CalendarButton","DailyRewardsOverlay"],["SettingsShortcut","SettingsOverlay"]]:
  hub.get_node(pair[0]).pressed.emit();await process_frame
  assert(menu.has_node(pair[1]),pair[1]);menu.get_node(pair[1]).queue_free();await process_frame
 print("SEVEN OVERLAY ROUTES PASS")
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/main_menu_cleanup.png")
 print("MAIN MENU CLEANUP PASS: 7 bottom and 4 rail buttons")
 menu.queue_free();await process_frame;quit(0)
