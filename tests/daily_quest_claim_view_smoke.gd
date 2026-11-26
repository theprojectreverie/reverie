extends SceneTree
func _initialize():call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var auth=root.get_node("AuthGateway")
 var original=auth._player.duplicate(true)
 auth._player={"id":"qa-view-account-a"}
 var claimed={"playerId":"qa-view-account-a","date":"2026-11-26","rows":[{"id":"checkin","claimed":true,"can_claim":false,"progress":1,"target":1}]}
 var stale=claimed.duplicate(true);stale.rows[0].claimed=false;stale.rows[0].can_claim=true;stale.rows[0].progress=0
 assert(auth.remember_quest_status(claimed,false).rows[0].claimed)
 var reopened=auth.remember_quest_status(stale,false)
 assert(reopened.rows[0].claimed and not reopened.rows[0].can_claim and reopened.rows[0].progress==1)
 assert(auth.remember_quest_status(stale,true).rows[0].can_claim)
 var next_day=stale.duplicate(true);next_day.date="2026-11-27"
 assert(auth.remember_quest_status(next_day,false).rows[0].can_claim)
 assert(auth.remember_quest_status(claimed,false).is_empty())
 auth._player={"id":"qa-view-account-b"}
 stale.playerId="qa-view-account-b"
 assert(auth.remember_quest_status(stale,false).rows[0].can_claim)
 auth._player=original
 print("DAILY QUEST VIEW PASS: reopen, stale response, new day, weekly and account isolation")
 quit(0)
