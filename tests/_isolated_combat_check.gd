extends SceneTree
const Runner = preload("res://tests/test_runner.gd")
func _initialize() -> void:
	call_deferred("_run_isolated")
func _run_isolated() -> void:
	var runner = Runner.new()
	runner._test_combat()
	runner._test_combat_cooldowns()
	runner._test_combat_engine_ownership()
	print("ISOLATED_COMBAT_LOGIC: %d passed, %d failed" % [runner.passed, runner.failed])
	for failure in runner.failures:
		push_error("ISOLATED_COMBAT_FAIL: " + failure)
	quit(0 if runner.failed == 0 else 1)

