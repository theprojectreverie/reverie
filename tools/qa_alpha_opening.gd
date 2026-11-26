extends Node
const FLOW=preload("res://scripts/game/components/main_gameplay_flow_component.gd")
func _ready():call_deferred("run")
func fail(message:String):
 push_error("OPENING QA: "+message)
 get_tree().quit(1)
func run():
 TouchInput.using_touch=true
 if not FLOW.needs_opening_cinematic({}) or FLOW.needs_opening_cinematic({"kael_opening_seen":true}) or FLOW.needs_opening_cinematic({"tutorial_complete":true}):
  fail("opening save decision");return
 GameState.session_domain.loaded_from_save=true
 if not FLOW.needs_opening_cinematic({}):fail("saved account skipped opening");return
 var intro=load("res://scenes/ui/opening_cinematic.tscn").instantiate()
 add_child(intro)
 await get_tree().process_frame
 if intro.sequence_component.shots.size()!=12:fail("shot count");return
 for shot in intro.sequence_component.shots:
  if not load(str(shot.image)) is Texture2D:fail("missing image");return
 if intro.get_node("Artwork").texture==null or intro.get_node("Caption").text.is_empty():fail("first shot");return
 intro.input_component.advance_requested.emit()
 await get_tree().create_timer(0.7).timeout
 if intro.playback_component.shot_index!=1:fail("advance");return
 intro.input_component.skip_requested.emit()
 await intro.finished
 intro.queue_free()
 await get_tree().process_frame
 var flags:Dictionary=GameState.quest_domain.flags.duplicate(true)
 var title=load("res://scenes/ui/title_screen.tscn").instantiate()
 add_child(title)
 await get_tree().process_frame
 title.actions_component._show_extras()
 await get_tree().process_frame
 var dialog:AcceptDialog
 for child in title.get_children():
  if child is AcceptDialog:dialog=child
 if dialog==null:fail("extras dialog");return
 dialog.custom_action.emit(&"replay_dream")
 await get_tree().process_frame
 var replay=get_node_or_null("OpeningCinematicReplay")
 if replay==null or title.visible:fail("dream replay missing");return
 if replay.get_node("Artwork").texture==null:fail("replay artwork");return
 replay.input_component.skip_requested.emit()
 await replay.finished
 await get_tree().process_frame
 await get_tree().process_frame
 if not title.visible or get_node_or_null("OpeningCinematicReplay")!=null:fail("title not restored");return
 if GameState.quest_domain.flags!=flags:fail("replay changed story flags");return
 print("PASS opening save policy, all 12 images, caption, advance, skip, safe title replay")
 title.queue_free()
 await get_tree().process_frame
 await AudioDirector.drain_for_shutdown()
 await get_tree().process_frame
 get_tree().quit()
