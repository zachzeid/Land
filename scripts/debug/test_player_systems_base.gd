extends SceneTree

# Tests the shared Phase 0 base of the player systems (docs/PLAYER_SYSTEMS.md §8):
# - the new deed kinds record, weigh in reputation and spread
# - Witnesses.in_sight: line of sight through open ground, blocked by a wall (world_solid), not by a
#   prop (world_obstacle); shorter at night and with stealth
# - children are never combat targets (world.json minor: Rook)
# - StorylineDirector.decide_situation: a soul's Lines refuse an option; nothing is applied
# - the six system autoloads exist, save under player_systems, and the input actions exist
# No API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_player_systems_base.gd

const Witnesses = preload("res://scripts/world/witnesses.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	var world_state = root.get_node("WorldState")
	world_state.set_idle_clock_rate(0.0)
	var director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	print("============================================================")
	print("🧪 PLAYER SYSTEMS BASE TEST")
	print("============================================================\n")

	print("New deed kinds")
	var pe = root.get_node("PlayerEvents")
	for kind in ["feat", "crafted", "fled", "fire", "trespass", "solved", "fell"]:
		var id = pe.record(kind, "the stranger did a %s thing" % kind, [], {"witnesses": [], "spread": false})
		_check("%s records" % kind, id != "" and pe.get_event(id).kind == kind)
	var Rep = load("res://scripts/world_state/reputation.gd")
	_check("A feat raises standing, a fire lowers it", Rep.KIND_WEIGHTS.feat > 0 and Rep.KIND_WEIGHTS.fire < 0 and "fire" in Rep.HOSTILE)

	print("\nLine of sight")
	var scene = Node2D.new()
	root.add_child(scene)
	var viewer = _npc("test_viewer_001", Vector2(0, 0))
	var behind = _npc("test_behind_001", Vector2(0, 300))
	var barrel_side = _npc("test_barrel_001", Vector2(-300, 0))
	var far = _npc("test_far_001", Vector2(2000, 0))
	for n in [viewer, behind, barrel_side, far]:
		scene.add_child(n)
	scene.add_child(_body(Vector2(100, 150), Vector2(400, 20), 4))   # a wall between (100,0) and (0,300)
	scene.add_child(_body(Vector2(-150, 0), Vector2(20, 60), 8))     # a barrel between (100,0) and (-300,0)
	await physics_frame
	await physics_frame
	var seen = Witnesses.in_sight(scene, Vector2(100, 0), {"hour": 12})
	_check("Seen across open ground", "test_viewer_001" in seen)
	_check("Not through a wall (world_solid)", not "test_behind_001" in seen)
	_check("A barrel (world_obstacle) does not hide a standing person", "test_barrel_001" in seen)
	_check("Not beyond sight range", not "test_far_001" in seen)
	_check("Night halves the range; stealth shortens it", Witnesses.sight_range({"hour": 23}) < Witnesses.sight_range({"hour": 12}) and Witnesses.sight_range({"hour": 12, "stealth": 100}) < Witnesses.sight_range({"hour": 12}))
	scene.queue_free()

	print("\nChildren")
	var registry = root.get_node("WorldRegistry")
	var combat = root.get_node("Combat")
	_check("Rook is a minor (world.json)", registry.is_minor("rook") and registry.is_minor(registry.get_npc_id("rook")))
	_check("...and can never be a combat target", not combat.can_target("rook"))
	_check("An adult can be", combat.can_target("varn") and not registry.is_minor("varn"))

	print("\nSituation decisions")
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	var hook = {"id": "test_strike", "type": "react", "situation": "A fight",
		"options": [{"id": "strike_elena", "label": "Strike Elena", "appeal": {}, "harms": ["elena"], "effects": []},
			{"id": "stand_back", "label": "Stand back", "appeal": {}, "effects": []}]}
	var decision: Dictionary = await director.decide_situation("bjorn", hook)
	_check("Bjorn's harm:elena Line refuses striking her", decision.get("choice", "") == "stand_back")
	_check("A soul-less NPC passes", (await director.decide_situation("nobody_at_all", hook)).choice == "pass")

	print("\nAutoloads, save, input")
	for name in world_state.PLAYER_SYSTEMS:
		_check("%s is an autoload with save/load" % name, root.get_node_or_null(name) != null and root.get_node(name).has_method("save") and root.get_node(name).has_method("load_from_dict"))
	_check("WorldState saves a player_systems block for each", world_state.save().get("player_systems", {}).keys().size() == world_state.PLAYER_SYSTEMS.size())
	for action in ["attack", "heavy_attack", "block", "dodge", "sprint", "use_item", "inventory", "craft"]:
		_check("Input action %s" % action, InputMap.has_action(action))
	var taken = {}
	for action in ["interact", "open_journal", "inner_voice", "attack", "heavy_attack", "block", "dodge", "sprint", "use_item", "inventory", "craft"]:
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				taken[e.physical_keycode] = taken.get(e.physical_keycode, []) + [action]
	_check("No key is bound to two actions", taken.values().all(func(a): return a.size() == 1))

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

class _Body extends Node2D:
	var npc_id: String = ""
	var is_alive: bool = true

func _npc(id: String, at: Vector2) -> Node2D:
	var n = _Body.new()
	n.npc_id = id
	n.position = at
	n.add_to_group("npcs")
	return n

func _body(at: Vector2, size: Vector2, layer: int) -> StaticBody2D:
	var b = StaticBody2D.new()
	b.position = at
	b.collision_layer = layer
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	b.add_child(shape)
	return b

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
