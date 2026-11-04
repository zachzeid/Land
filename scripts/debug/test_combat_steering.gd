extends SceneTree

# Tests what the windowed QA of fights found (scripts/debug/qa/qa_combat.gd):
# - a fighter closing on its foe goes round what stands between them (a well, a house, a tree), and
#   out of a pocket that opens away from the foe, instead of stopping at it or dithering along it
# - a body giving ground into a wall turns aside and keeps to one side
# - nobody strikes a person who has yielded: a fighter whose NPC foe yields lets them go, and the
#   fight ends for both
# - a fighter set on a child by any road has no fight: it ends at once
# - an arrow can be seen in flight (it draws itself, over the people it passes)
# Fakes only: no API calls, nothing reaches ./chroma, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_combat_steering.gd

const AI = preload("res://scripts/combat/combat_ai.gd")

class FakeStats extends RefCounted:
	var stamina: float = 1000.0
	var health: float = 1000.0
	func get_stamina() -> float:
		return stamina
	func spend_stamina(_amount: float) -> bool:
		return true
	func get_skill(_skill: String) -> float:
		return 0.0
	func use_skill(_skill: String, _d: float = 1.0, _c: Dictionary = {}) -> Dictionary:
		return {"gained": 0.0, "level": 0.0, "milestone": 0}
	func damage(amount: float, _type: String = "blunt", _source: String = "") -> Dictionary:
		health -= amount
		return {"health": health, "staggered": false, "dead": false}

class FakeInventory extends RefCounted:
	func get_equipped(_slot: String) -> Dictionary:
		return {}
	func wear(_slot: String, _amount: float = 1.0) -> Dictionary:
		return {"broke": false}
	func has(_item_id: String, _qty: int = 1) -> bool:
		return true
	func remove(_item_id: String, _qty: int = 1) -> bool:
		return true

class FakePlayer extends Node2D:
	var is_alive: bool = true

class FakeBody extends StaticBody2D:
	var npc_id: String = ""
	var is_alive: bool = true

var failures: int = 0
var world_state: Node
var director: Node
var registry: Node
var pe: Node
var combat: Node
var gm: Node
var scene: Node2D
var GenericNPCScript
var saved_pe: Dictionary
var save_existed: bool

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	director = root.get_node("StorylineDirector")
	registry = root.get_node("WorldRegistry")
	pe = root.get_node("PlayerEvents")
	combat = root.get_node("Combat")
	var dyn = root.get_node_or_null("DynamicNPCRegistry")
	gm = dyn.generics if dyn and "generics" in dyn else null
	GenericNPCScript = load("res://scripts/generics/generic_npc.gd")
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	saved_pe = pe.save()
	world_state.set_idle_clock_rate(0.0)
	pe.capture_enabled = false
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	director.set_agency_mode("offline")

	print("============================================================")
	print("🧪 COMBAT STEERING TEST")
	print("============================================================\n")

	_check("GenericManager is running", gm != null)
	await _test_round_an_obstacle()
	await _test_out_of_a_pocket()
	await _test_giving_ground()
	await _test_yielded_foe()
	await _test_set_on_a_child()
	await _test_arrow_seen()

	if is_instance_valid(scene):
		scene.queue_free()
	combat.stats_provider = null
	combat.inventory_provider = null
	combat.set_test_clock(-1.0)
	combat.reset()
	pe.load_from_dict(saved_pe)
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================

func _test_round_an_obstacle():
	print("Closing on a foe round what stands between them")
	var player = await _fresh_scene()
	player.position = Vector2(0, 70)
	_wall(Vector2(0, 0), Vector2(64, 64))      # the well, the foe just past it
	_wall(Vector2(-70, 110), Vector2(40, 20))  # benches either side of the way in
	_wall(Vector2(70, 110), Vector2(40, 20))
	var soldier = _generic_body("gen_garrison_soldier_1", Vector2(0, -120))
	await _settle()
	_fight(soldier, player)
	var closest = await _run_fight(soldier, player, 6.0)
	_check("A soldier on the far side of a well reaches the player round it (closest %.0f px)" % closest, closest <= 60.0)
	_check("...and the path it found starts clear of the well", soldier.path_to(player.global_position).size() > 0)

func _test_out_of_a_pocket():
	print("\n...out of a pocket that opens away from the foe")
	var player = await _fresh_scene()
	player.position = Vector2(0, 160)
	# A U of walls round the soldier, open to the north, the player to the south
	_wall(Vector2(0, 40), Vector2(140, 16))
	_wall(Vector2(-70, -10), Vector2(16, 116))
	_wall(Vector2(70, -10), Vector2(16, 116))
	var soldier = _generic_body("gen_garrison_soldier_2", Vector2(0, 0))
	await _settle()
	_fight(soldier, player)
	var flips = [0]
	var closest = await _run_fight(soldier, player, 8.0, flips)
	_check("A soldier in a pocket comes out of it and reaches the player (closest %.0f px)" % closest, closest <= 60.0)
	_check("...without dithering back and forth along the wall (%d reversals)" % flips[0], flips[0] <= 2)

func _test_giving_ground():
	print("\n...giving ground into a wall")
	var player = await _fresh_scene()
	player.position = Vector2(100, 0)
	_wall(Vector2(-30, 0), Vector2(16, 300))
	var ranger = _generic_body("gen_ranger_4", Vector2(0, 0))
	await _settle()
	_fight(ranger, player)
	var v = ranger.steer_round(Vector2(-90, 0), 1.0 / 60.0)
	_check("Backing into a wall, a ranger turns aside along it (%s)" % v, absf(v.y) > 50.0 and v.x <= 0.5)
	var again = ranger.steer_round(Vector2(-90, 0), 1.0 / 60.0)
	_check("...and keeps to the same side (%s then %s)" % [v, again], signf(again.y) == signf(v.y))
	_check("Nothing in the way: the step is left as it is", ranger.steer_round(Vector2(90, 0), 1.0 / 60.0) == Vector2(90, 0))

func _test_yielded_foe():
	print("\nNobody strikes a person who has yielded")
	await _fresh_scene()
	var soldier = _generic_body("gen_garrison_soldier_1", Vector2(0, 0))
	var grunt = _generic_body("gen_hollow_grunt_1", Vector2(30, 0))
	await _settle()
	_fight(soldier, grunt)
	_fight(grunt, soldier)
	grunt.combat_state = "yield"
	var hp = grunt.health
	soldier.combat_tick(0.1)
	_check("The soldier's fight with a yielded grunt ends (%s)" % soldier.combat_state, soldier.combat_state == "")
	_check("...the grunt is let go (%s) and not struck again (%.0f -> %.0f)" % [grunt.combat_state, hp, grunt.health], grunt.combat_state == "" and grunt.health == hp)
	var ranger = _generic_body("gen_ranger_4", Vector2(-200, 0))
	await _settle()
	_fight(ranger, grunt)
	grunt.combat_state = "yield"
	grunt.combat_foe = soldier  # yielded to someone else: still nobody looses at them
	var arrows = ranger.arrows_left()
	ranger.combat_tick(0.1)
	_check("A ranger set on someone who yielded to another holds the shot and stands down", ranger.combat_state == "" and ranger.arrows_left() == arrows)

func _test_set_on_a_child():
	print("\n...nor anyone at a child")
	await _fresh_scene()
	var soldier = _generic_body("gen_garrison_soldier_1", Vector2(0, 0))
	var rook = FakeBody.new()
	rook.npc_id = registry.get_npc_id("rook")
	rook.position = Vector2(100, 0)
	rook.collision_layer = 2
	rook.add_to_group("npcs")
	scene.add_child(rook)
	await _settle()
	_fight(soldier, rook)
	soldier.combat_tick(0.1)
	_check("A fighter set on Rook has no fight: it ends at once (%s)" % soldier.combat_state, soldier.combat_state == "" and soldier.velocity == Vector2.ZERO)

func _test_arrow_seen():
	print("\nAn arrow in flight can be seen")
	var player = await _fresh_scene()
	player.position = Vector2(300, 0)
	var ranger = _generic_body("gen_ranger_4", Vector2(0, 0))
	await _settle()
	var p = combat.shoot(ranger, combat.weapon_of(ranger), player)
	_check("The arrow is drawn over the people it passes (z %d)" % (p.z_index if p else -1), p != null and p.z_index > 10 and p.is_visible_in_tree() and p.has_method("_draw"))
	await _settle()
	_check("...and flies", p != null and is_instance_valid(p) and p.global_position.x > 0.0)

# =============================================================================

## Lets the fight run on its own physics for `seconds`; the closest the fighter came to the foe.
## flips[0]: how many times its x velocity reversed while it made no headway
func _run_fight(npc, foe, seconds: float, flips: Array = [0]) -> float:
	var closest = INF
	var last_vx = 0.0
	for i in int(seconds * 60.0):
		await physics_frame
		if not is_instance_valid(npc) or npc.combat_state == "":
			break
		closest = minf(closest, npc.global_position.distance_to(foe.global_position))
		var vx = npc.velocity.x
		if absf(vx) > 30.0 and absf(last_vx) > 30.0 and signf(vx) != signf(last_vx):
			flips[0] += 1
		if absf(vx) > 30.0:
			last_vx = vx
		if closest <= 50.0:
			break
	return closest

func _fresh_scene() -> FakePlayer:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = Node2D.new()
	scene.name = "SteeringTestScene"
	root.add_child(scene)
	combat.stats_provider = FakeStats.new()
	combat.inventory_provider = FakeInventory.new()
	combat.reset()
	combat.set_test_clock(100.0)
	var p = FakePlayer.new()
	p.name = "Player"
	p.add_to_group("player")
	scene.add_child(p)
	return p

func _generic_body(id: String, at: Vector2):
	var n = GenericNPCScript.new()
	n.setup(id, gm)
	n.position = at
	n.collision_layer = 2
	n.collision_mask = 12  # walls and props, as generic_npc.tscn
	n.add_to_group("npcs")
	n.add_to_group("generics")
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(20, 24)
	shape.shape = rect
	shape.position = Vector2(0, -12)  # feet at the origin, body above, as the NPC scenes
	n.add_child(shape)
	scene.add_child(n)
	return n

func _fight(npc, foe) -> void:
	npc.combat_state = "fight"
	npc.combat_foe = foe
	npc._fight = {"foe_key": AI.key_of(foe), "band": "steady", "harm_recorded": true, "help_recorded": true, "last_hit_ms": Time.get_ticks_msec()}
	npc._attack_cooldown = 0.0

func _wall(at: Vector2, size: Vector2) -> StaticBody2D:
	var w = StaticBody2D.new()
	w.position = at
	w.collision_layer = 4
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	w.add_child(shape)
	scene.add_child(w)
	return w

func _settle() -> void:
	await physics_frame
	await physics_frame

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
