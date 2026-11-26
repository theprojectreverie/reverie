extends SceneTree
func _initialize():call_deferred("run")
func wait_until(check:Callable,seconds:float=15.0)->bool:
 var deadline=Time.get_ticks_msec()+int(seconds*1000)
 while not check.call():
  if Time.get_ticks_msec()>deadline:return false
  await process_frame
 return true
func fail(message:String):
 push_error(message);quit(1)
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var auth=root.get_node("AuthGateway")
 auth.api_base_url=OS.get_environment("QA_API")
 if auth.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:fail("login");return
 var result=await auth.auth_result
 if not result[1]:fail("authentication");return
 var menu=load("res://scenes/ui/main_menu.tscn").instantiate();root.add_child(menu)
 await process_frame
 var paid=menu.get_node("ReferenceInterface/CurrencyBar/PaidCurrency")
 if not paid.text.ends_with("+") or paid.mouse_filter!=Control.MOUSE_FILTER_STOP:fail("paid shop entry unavailable");return
 paid.pressed.emit();await process_frame
 var main_shop=menu.get_node_or_null("MoonstoneShopOverlay")
 if main_shop==null:fail("main menu shop not opened");return
 if not await wait_until(func():return not main_shop._busy and main_shop._packages.size()==3):fail("main menu catalogue unavailable");return
 main_shop.close_screen();await process_frame
 if menu.has_node("MoonstoneShopOverlay"):fail("shop close failed");return
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/moonstone_main_menu.png")
 menu.queue_free();await process_frame
 print("PASS signed-in main menu Paid Moonstone plus opens and closes shop")
 var gacha=load("res://scenes/ui/gacha_screen.tscn").instantiate();root.add_child(gacha)
 await process_frame
 var button=gacha.find_child("HeaderMoonstoneShop",true,false)
 if button==null:fail("shop shortcut missing");return
 button.pressed.emit();await process_frame
 var shop=gacha.get_node_or_null("MoonstoneShop")
 if shop==null:fail("shop overlay missing");return
 if not await wait_until(func():return not shop._busy and shop._packages.size()==3):fail("catalogue unavailable");return
 if OS.get_environment("QA_STRIPE_MANUAL")=="1":
  if not shop._enabled or not shop._manual_verification:fail("manual mode not enabled");return
  if not shop._layout.get_node("Description").text.contains("No webhook listener"):fail("missing manual notice");return
  if OS.get_environment("QA_STRIPE_CANCEL")=="1":
   var small=shop._layout.get_node("Packages/Small")
   small.pressed.emit()
   if not shop._purchase_confirm.visible:fail("small confirmation missing");return
   shop._purchase_confirm.confirmed.emit();shop._purchase_confirm.hide()
   if not await wait_until(func():return not shop._busy and not shop._pending.is_empty()):fail("cancel fixture pending missing");return
   var cancel=shop._layout.get_node("Actions/Cancel")
   if cancel.disabled:fail("cancel button disabled");return
   cancel.pressed.emit()
   if not await wait_until(func():return not shop._busy and shop._pending.is_empty()):fail("cancel failed");return
   if small.disabled or not cancel.disabled:fail("shop not unlocked after cancellation");return
   if int(auth.online_currencies.get("paid_moonstones",0))!=0:fail("cancel granted currency");return
   if not shop._layout.get_node("Status").text.contains("closed or expired"):fail("cancel status missing");return
   print("PASS Godot Cancel pending checkout, no credit, shop unlocked")
  if OS.get_environment("QA_STRIPE_SPENDING")=="1":
   shop._layout.get_node("WalletActions/Spending").pressed.emit()
   if not await wait_until(func():return not shop._busy and shop._spending_dialog.visible):fail("spending dialog missing");return
   shop._spending_dialog.get_node("Body/Daily").text="0"
   shop._spending_dialog.confirmed.emit()
   if not await wait_until(func():return not shop._busy and not shop._spending_dialog.visible):fail("limit save missing");return
   shop._layout.get_node("Packages/Small").pressed.emit()
   if not shop._purchase_confirm.visible or not shop._pending.is_empty():fail("confirmation missing");return
   shop._purchase_confirm.confirmed.emit();shop._purchase_confirm.hide()
   if not await wait_until(func():return not shop._busy):fail("limit response missing");return
   if not shop._pending.is_empty() or not shop._unconfirmed.is_empty() or not shop._layout.get_node("Status").text.contains("spending limit"):fail("limit not enforced");return
   shop._layout.get_node("WalletActions/Spending").pressed.emit()
   if not await wait_until(func():return not shop._busy and shop._spending_dialog.visible):fail("spending reopen missing");return
   if shop._spending_dialog.get_node("Body/Daily").text!="0.00":fail("limit not persisted");return
   shop._spending_dialog.get_node("Body/Daily").text=""
   shop._spending_dialog.confirmed.emit()
   if not await wait_until(func():return not shop._busy and not shop._spending_dialog.visible):fail("limit clear missing");return
   print("PASS Godot spending dialog, stored zero limit, checkout blocked, limit cleared")
  var medium=shop._layout.get_node("Packages/Medium")
  if medium.disabled:fail("manual package disabled");return
  medium.pressed.emit()
  if not shop._purchase_confirm.visible or not shop._pending.is_empty():fail("medium confirmation missing");return
  shop._purchase_confirm.confirmed.emit();shop._purchase_confirm.hide()
  if not await wait_until(func():return not shop._busy and not shop._pending.is_empty()):fail("pending checkout");return
  if not medium.disabled:fail("second checkout enabled while pending");return
  if OS.get_environment("QA_STRIPE_AUTO")=="1":
   # Simulate returning from the browser; do not press Refresh.
   shop.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
   if not await wait_until(func():return not shop._busy and shop._pending.is_empty() and int(auth.online_currencies.get("paid_moonstones",0))==600):fail("automatic credit missing");return
   if not shop._layout.get_node("Status").text.contains("verified!"):fail("automatic success notice missing");return
   print("PASS automatic verification on browser return, no manual refresh")
  elif OS.get_environment("QA_STRIPE_AUTO")=="reopen":
   shop.close_screen();await process_frame
   button.pressed.emit();await process_frame
   shop=gacha.get_node_or_null("MoonstoneShop")
   if shop==null:fail("reopen failed");return
   if not await wait_until(func():return not shop._busy and shop._pending.is_empty() and int(auth.online_currencies.get("paid_moonstones",0))==600):fail("reopen recovery missing");return
   print("PASS automatic pending order recovery after shop reopen")
  elif OS.get_environment("QA_STRIPE_AUTO")=="timer":
   if not await wait_until(func():return not shop._busy and shop._pending.is_empty() and int(auth.online_currencies.get("paid_moonstones",0))==600,20.0):fail("timed verification missing");return
   print("PASS bounded polling verifies purchase without user action")
  else:
   shop._layout.get_node("Actions/Refresh").pressed.emit()
   if not await wait_until(func():return not shop._busy and shop._pending.is_empty() and int(auth.online_currencies.get("paid_moonstones",0))==600):fail("verified credit missing");return
  var refresh=shop._layout.get_node("Actions/Refresh")
  refresh.pressed.emit()
  if not await wait_until(func():return not shop._busy):fail("repeat refresh");return
  if int(auth.online_currencies.get("paid_moonstones",0))!=600:fail("duplicate credit");return
  shop._layout.get_node("WalletActions/LedgerButton").pressed.emit()
  if not await wait_until(func():return not shop._ledger_busy and shop._ledger.visible):fail("ledger unavailable");return
  var entries=shop.get_node("LedgerDialog/Body/Scroll/Entries")
  if entries.get_child_count()!=1:fail("ledger entry count");return
  var found=false
  for label in entries.find_children("*","Label",true,false):
   if label.text.contains("Verified test purchase") and label.text.contains("+600"):found=true
  if not found:fail("ledger credit missing");return
  if not shop.get_node("LedgerDialog/Body/Summary").text.contains("600 Paid Moon Stones"):fail("ledger balance missing");return
  shop._ledger.hide()
  var save=shop._layout.get_node("ReceiptActions/Save")
  if save.disabled:fail("receipt button disabled");return
  save.pressed.emit()
  if not await wait_until(func():return not shop._busy and shop._receipt_dialog.visible):fail("receipt dialog missing");return
  var receipt_path=OS.get_environment("TEMP")+"/reverie-qa-"+str(Time.get_ticks_usec())+".txt"
  shop._receipt_dialog.file_selected.emit(receipt_path)
  shop._receipt_dialog.hide()
  var receipt=FileAccess.get_file_as_string(receipt_path)
  DirAccess.remove_absolute(receipt_path)
  if not receipt.contains("600 Paid Moonstones") or not receipt.contains("EUR 6.00") or not receipt.contains("NOT A TAX INVOICE"):fail("receipt export invalid");return
  print("PASS verified receipt saved through in-game file dialog")
  print("PASS real Godot manual checkout, pending lock, refresh, history, ledger and wallet")
 else:
  if shop._enabled:fail("sandbox enabled without credentials");return
  for b in shop._layout.get_node("Packages").get_children():
   if not b.disabled:fail("checkout enabled");return
  if not shop._layout.get_node("Status").text.contains("not connected"):fail("missing unavailable notice");return
  print("PASS actual Godot summon shortcut, server catalogue, disabled checkout and online balance")
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/stripe_shop_preview.png")
 gacha.queue_free();await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately();await create_timer(.4).timeout;quit(0)
