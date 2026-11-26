extends Node
var state := "not_started"
var responses: Array[Dictionary] = []
var calls: Array[String] = []
func audience_state() -> String:
	return state
func submit_audience(choice: String) -> Dictionary:
	calls.append(choice)
	await get_tree().process_frame
	var result := responses.pop_front() as Dictionary
	if not result.is_empty():state = str(result.audience.state)
	return result
