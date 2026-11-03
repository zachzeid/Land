extends SceneTree

# Tests the fixes made when the six slices were merged (docs/PLAYER_SYSTEMS.md):
# - every StaticBody2D in every scene sits on world_solid (4) or world_obstacle (8) or another
#   named layer, never the player's own layer 1, which nothing collides with or sees against
# - PlayerEvents.set_outcome: a fire deed's end changes its summary and its reputation weight,
#   "burned" is final, unknown ids refuse
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_integration_fixes.gd

const Rep = preload("res://scripts/world_state/reputation.gd")
const SCENE_DIRS = ["res://scenes/exterior", "res://scenes/interiors", "res://scenes/capitol", "res://scenes/puzzles", "res://scenes/world"]

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	_test_layers()
	_test_set_outcome()
	print("")
	if failures == 0:
		print("✅ ALL TESTS PASSED")
	else:
		print("❌ %d CHECK(S) FAILED" % failures)
	quit(0 if failures == 0 else 1)

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ✓ " + what)
	else:
		print("  ✗ " + what)
		failures += 1

func _test_layers() -> void:
	print("\n== static bodies are on a layer something collides with")
	var bad: Array = []
	var scanned = 0
	for dir in SCENE_DIRS:
		var d = DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if not f.ends_with(".tscn"):
				continue
			scanned += 1
			var text = FileAccess.get_file_as_string(dir + "/" + f)
			for block in text.split("\n[node "):
				if not block.contains("type=\"StaticBody2D\""):
					continue
				var header = block.get_slice("\n", 0)
				var m = RegEx.create_from_string("collision_layer = (\\d+)").search(block)
				var layer = int(m.get_string(1)) if m else 1
				if layer & 1:
					bad.append("%s %s" % [f, header.get_slice("\"", 1)])
	_check(scanned > 20, "scanned %d scenes" % scanned)
	_check(bad.is_empty(), "no StaticBody2D on the player's layer 1 %s" % [bad.slice(0, 6)])

func _test_set_outcome() -> void:
	print("\n== a fire deed's outcome")
	var pe = root.get_node("PlayerEvents")
	pe.capture_enabled = false
	var id = str(pe.record("fire", "set fire to Bjorn's woodpile", ["bjorn"], {"witnesses": []}))
	_check(id != "", "fire deed recorded")
	var open_w = Rep.kind_weight(pe.get_event(id))
	_check(pe.set_outcome(id, "doused"), "doused accepted")
	var doused_w = Rep.kind_weight(pe.get_event(id))
	_check(doused_w > open_w, "a fire put out weighs less (%s > %s)" % [doused_w, open_w])
	_check(pe.get_event(id).summary.ends_with("it was put out"), "summary says it was put out")
	_check(pe.set_outcome(id, "burned"), "burned accepted after doused")
	var burned_w = Rep.kind_weight(pe.get_event(id))
	_check(burned_w < open_w, "a fire that burned through weighs more (%s < %s)" % [burned_w, open_w])
	_check(not pe.set_outcome(id, "doused"), "burned is final")
	_check(pe.get_event(id).summary == "set fire to Bjorn's woodpile; it burned through", "summary has one ending, not two")
	_check(not pe.set_outcome("pe_no_such", "doused"), "unknown id refused")
