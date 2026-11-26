extends Node

func _ready():
 call_deferred("run")

func wait_for(check:Callable)->bool:
 var end=Time.get_ticks_msec()+15000
 while not check.call():
  if Time.get_ticks_msec()>end:return false
  await get_tree().process_frame
 return true

func fail(message:String):
 push_error("UPGRADE QA: "+message)
 get_tree().quit(1)

func run():
 TouchInput.using_touch=true
 AuthGateway.api_base_url=OS.get_environment("QA_API")
 if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:fail("login start");return
 var auth=await AuthGateway.auth_result
 if not auth[1]:fail("login");return
 var screen:GachaScreen=load("res://scenes/ui/gacha_screen.tscn").instantiate()
 add_child(screen)
 if not await wait_for(func():return not screen._summon_flow.online_state.is_empty() and not screen._summon_flow.online_loading):fail("load");return
 screen._show_online_roster()
 screen._set_collection_section("Progression")
 var root=screen.get_node("OnlineRosterDialog/BodyScroll/Collection")
 var chooser:OptionButton=root.get_node("UpgradeCharacter")
 if not chooser.visible or chooser.disabled:fail("character picker");return
 for i in chooser.item_count:
  if chooser.get_item_metadata(i)=="kael":
   chooser.select(i)
   chooser.item_selected.emit(i)
   break
 if screen._online_selected.get("char_id")!="kael":fail("character selection");return
 var train:Button=root.get_node("UpgradeRow/Train")
 if not train.disabled:fail("training must stop at level cap");return
 for i in chooser.item_count:
  if chooser.get_item_metadata(i)=="gerald":
   chooser.select(i)
   chooser.item_selected.emit(i)
   break
 if train.disabled or not train.text.contains("100 gold"):fail("fresh character training");return
 train.pressed.emit()
 if not await wait_for(func():return not screen._upgrade_busy and int(screen._online_selected.get("level",0))==2):fail("training failed");return
 if screen.summon_currency("gold")!=1900:fail("training cost");return
 for i in chooser.item_count:
  if chooser.get_item_metadata(i)=="kael":
   chooser.select(i)
   chooser.item_selected.emit(i)
   break
 print("PASS level-one character training through actual upgrade UI")
 var ascend:Button=root.get_node("UpgradeRow/Ascend")
 var awaken:Button=root.get_node("UpgradeRow/Awaken")
 if ascend.disabled or awaken.disabled:fail("valid upgrades blocked");return
 # Trigger an ordinary read and tap while it is in flight.
 screen._refresh_live_collection()
 if not screen._summon_flow.online_loading:fail("refresh fixture");return
 ascend.pressed.emit()
 if not await wait_for(func():return not screen._upgrade_busy and int(screen._online_selected.get("ascension",0))==1):fail("ascension during refresh");return
 if int(screen._online_selected.level)!=21 or not ascend.disabled or awaken.disabled:fail("ascension state");return
 awaken.pressed.emit()
 if not await wait_for(func():return not screen._upgrade_busy and int(screen._online_selected.get("awakening",0))==1):fail("awakening");return
 if not awaken.disabled:fail("duplicate requirement");return
 var skills:OptionButton=root.get_node("SkillRow/Skill")
 for i in skills.item_count:
  if skills.get_item_metadata(i)=="ember_lance":
   skills.select(i)
   skills.item_selected.emit(i)
   break
 var upgrade:Button=root.get_node("SkillRow/Upgrade")
 if upgrade.disabled:fail("valid skill blocked");return
 upgrade.pressed.emit()
 if not await wait_for(func():return not screen._upgrade_busy and int(screen._online_selected.get("skill_levels",{}).get("ember_lance",1))==2):fail("skill upgrade");return
 if screen.summon_currency("gold")!=1000:fail("wallet deduction");return
 if not root.get_node("UpgradeStatus").text.contains("Saved"):fail("visible status");return
 if not root.get_node("UpgradeHint").text.contains("Lv 40"):fail("next tier requirements");return
 print("PASS actual touch-mode upgrade UI: character picker, ascension during refresh, awakening, skill upgrade, costs, feedback")
 screen.queue_free()
 await get_tree().process_frame
 get_tree().quit()