extends SceneTree
func _initialize(): call_deferred("run")
func wait_until(check:Callable, seconds:float=12.0)->bool:
 var deadline=Time.get_ticks_msec()+int(seconds*1000)
 while not check.call():
  if Time.get_ticks_msec()>deadline: return false
  await process_frame
 return true
func fail(reason:String):
 push_error("DAILY UI FAIL: "+reason)
 quit(1)
func open_journal(menu):
 menu.get_node("ReferenceInterface/LeftRail/EventsButton").pressed.emit()
 await process_frame
 var journal=menu.get_node_or_null("DailyQuestsOverlay")
 if journal==null: return null
 if not await wait_until(func():return journal._operation.is_empty()): return null
 journal._select_mode(true)
 if not await wait_until(func():return journal._operation.is_empty() and not journal._remote.is_empty()):return null
 return journal
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var auth=root.get_node("AuthGateway")
 auth.api_base_url=OS.get_environment("QA_API")
 if auth.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:fail("login");return
 var result=await auth.auth_result
 if not result[1]:fail("auth");return
 if not await wait_until(func():return auth.online_wallet.has("gold")):fail("wallet");return
 var initial=int(auth.online_wallet.gold)
 var menu=load("res://scenes/ui/main_menu.tscn").instantiate();root.add_child(menu)
 await process_frame
 var journal=await open_journal(menu)
 if journal==null:fail("journal load");return
 var button=journal._layout.get_node("Scroll/Rows").get_child(0).get_node("Row/Reward/Claim")
 if button.disabled or button.text!="Claim":fail("initial eligibility");return
 for i in range(8):button.pressed.emit()
 if not await wait_until(func():return journal._operation.is_empty() and journal._remote.rows[0].claimed):fail("claim result");return
 if not button.disabled or button.text!="Claimed":fail("button state");return
 if not await wait_until(func():return int(auth.online_wallet.get("gold",-1))==initial+150):fail("exact wallet");return
 print("PASS real UI claim, eight clicks, one 150 gold reward")
 await create_timer(6.0).timeout
 if not button.disabled or button.text!="Claimed":fail("poll respawn");return
 journal.close_screen()
 if not await wait_until(func():return not menu.has_node("DailyQuestsOverlay")):fail("close");return
 journal=await open_journal(menu)
 if journal==null or not journal._remote.rows[0].claimed:fail("reopen");return
 button=journal._layout.get_node("Scroll/Rows").get_child(0).get_node("Row/Reward/Claim")
 if not button.disabled:fail("reopened button enabled");return
 journal._toggle_history()
 if not await wait_until(func():return journal._history_loaded):fail("reward history");return
 var count=0
 for entry in journal._history:
  if str(entry.title)=="Adventurer's Check-in":count+=1
 if count!=1:fail("history duplicate");return
 journal._toggle_history()
 if not await wait_until(func():return journal._operation.is_empty()):fail("history return");return
 journal._select_mode(true,true)
 if not await wait_until(func():return journal._operation.is_empty() and not journal._remote.is_empty()):fail("weekly");return
 if int(journal._remote.rows[0].progress)!=1:fail("weekly checkin");return
 journal._select_mode(true,false,true)
 if not await wait_until(func():return journal._operation.is_empty() and not journal._remote.is_empty()):fail("monthly");return
 if int(journal._remote.rows[0].progress)!=1:fail("monthly checkin");return
 journal._select_mode(true)
 if not await wait_until(func():return journal._operation.is_empty() and not journal._remote.is_empty()):fail("daily tab");return
 if not journal._remote.rows[0].claimed:fail("tab respawn");return
 print("PASS poll, reopen, reward history, weekly/monthly credit and tab switching")
 auth.logout()
 if not await wait_until(func():return not auth.is_authenticated()):fail("logout");return
 if auth.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:fail("re-login");return
 result=await auth.auth_result
 if not result[1]:fail("re-auth");return
 if not await wait_until(func():return journal._operation.is_empty() and not journal._remote.is_empty() and auth.online_wallet.has("gold")):fail("re-login refresh");return
 if not journal._remote.rows[0].claimed or int(auth.online_wallet.gold)!=initial+150:fail("re-login duplicate");return
 print("PASS logout/re-login preserves actual claimed state and wallet")
 menu.queue_free();await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately();await create_timer(.4).timeout
 quit(0)
