extends CombatSessionComponent
## Test-only transport double. No login, network or persistent rewards.
var responses: Array[Dictionary] = []
var requests: Array[Dictionary] = []

func spar_owner_is_current() -> bool:
	return true

func _spar_request(payload: Dictionary) -> Dictionary:
	requests.append(payload.duplicate(true))
	await get_tree().process_frame
	if responses.is_empty():
		push_error("Unexpected fixture request: " + str(payload.get("operation")))
		return {}
	return responses.pop_front()
