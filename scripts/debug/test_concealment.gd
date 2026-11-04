extends SceneTree

# Tests Concealment (scripts/npcs/concealment.gd, docs/WORLD_SCHEMA.md §9.1): a woodwise watcher in the
# wilds is hard for the player to see
# - the visibility function: distance, their stealth, the player's stealth, night, lamp light and
#   glare, cover (props on world_obstacle), moving, revealed, indoors and in towns
# - who hides: anyone with stealth and woodwise (Renna, a generic ranger), nobody else
# - on a body: faded to nothing far off in the trees, the prompt hidden and no talking while unseen,
#   shown when it speaks, is struck or looses an arrow; it still witnesses what it sees
# Fakes only: no API calls, nothing reaches ./chroma, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_concealment.gd

const Concealment = preload("res://scripts/npcs/concealment.gd")
const CharacterTypes = preload("res://scripts/npcs/character_types.gd")
const Witnesses = preload("res://scripts/world/witnesses.gd")
const LAMP = preload("res://scripts/world/physics/lamp.gd")
const FOREST = "res://scenes/exterior/forest_path.tscn"
const VILLAGE = "res://scenes/game_world.tscn"

var failures: int = 0
var world_state: Node
var stats: Node
var physics: Node
var gm: Node
var scene: Node2D
var player: Node2D
var saved_minutes: int
var saved_stealth: float
var saved_weather: Dictionary
var save_existed: bool

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	stats = root.get_node("PlayerStats")
	physics = root.get_node("WorldPhysics")
	var dyn = root.get_node_or_null("DynamicNPCRegistry")
	gm = dyn.generics if dyn and "generics" in dyn else null
	saved_minutes = world_state.game_minutes
	saved_stealth = stats.get_skill("stealth")
	saved_weather = physics.weather_override.duplicate(true)
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	world_state.set_idle_clock_rate(0.0)
	physics.set_weather("clear", Vector2.ZERO, -1)
	stats.set_skill("stealth", 0.0)

	print("============================================================")
	print("🧪 CONCEALMENT TEST")
	print("============================================================\n")

	_test_function()
	_test_who_hides()
	_test_where()
	await _test_on_a_body()
	await _test_generic_ranger()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================

func _o(extra: Dictionary = {}) -> Dictionary:
	var o = {"concealment": 45.0, "cover": 1.0, "wild": true, "moving": false, "revealed": false,
		"sight": 1.0, "glare": 1.0, "perception": 0.0, "distance": 0.0}
	o.merge(extra, true)
	return o

func _test_function():
	print("The visibility function")
	var trees = Concealment.spot_range(_o())
	var open = Concealment.spot_range(_o({"cover": 0.0}))
	_check("Among trees they are made out nearer than on open ground (%.0f vs %.0f px)" % [trees, open], trees < open and open < Concealment.SPOT_RANGE)
	_check("Close by they are drawn in full", Concealment.visibility(_o({"distance": trees * 0.5})) == 1.0)
	_check("Far off they are not drawn at all", Concealment.visibility(_o({"distance": trees * 1.1})) == 0.0)
	var mid = Concealment.visibility(_o({"distance": trees * 0.85}))
	_check("Between, they fade (%.2f)" % mid, mid > 0.0 and mid < 1.0)
	_check("More stealth hides them nearer", Concealment.spot_range(_o({"concealment": 80.0})) < trees)
	_check("No stealth: drawn as anyone at any distance", Concealment.visibility(_o({"concealment": 0.0, "distance": 5000.0})) == 1.0)
	var keen = Concealment.spot_range(_o({"perception": 100.0}))
	_check("The player's stealth spots them farther (%.0f vs %.0f px)" % [keen, trees], keen > trees)
	var night = Concealment.spot_range(_o({"sight": 0.3}))
	_check("At night they are made out much nearer (%.0f px)" % night, night < trees * 0.5)
	_check("The player standing in light sees less of them in the dark (glare)", Concealment.spot_range(_o({"sight": 0.3, "glare": 0.6})) < night)
	_check("Moving shows them", Concealment.visibility(_o({"moving": true, "distance": trees * 2.0})) == 1.0)
	_check("Revealed (an arrow, a blow, a word) shows them", Concealment.visibility(_o({"revealed": true, "distance": trees * 2.0})) == 1.0)
	_check("Out of the wilds (indoors, a town) they are drawn as anyone", Concealment.visibility(_o({"wild": false, "distance": trees * 2.0})) == 1.0)

func _test_who_hides():
	print("\nWho hides")
	var ranger = CharacterTypes.resolve("ranger")
	_check("A ranger in the wilds hides with their full stealth (%.0f)" % CharacterTypes.wild_concealment(ranger, true),
		CharacterTypes.wild_concealment(ranger, true) == CharacterTypes.skill(ranger, "stealth") and CharacterTypes.can_hide(ranger))
	_check("...and not at all out of them", CharacterTypes.wild_concealment(ranger, false) == 0.0)
	_check("Renna can hide (stealth %.0f)" % CharacterTypes.skill(CharacterTypes.of_key("renna"), "stealth"), CharacterTypes.can_hide(CharacterTypes.of_key("renna")))
	_check("Ordinary folk cannot", not CharacterTypes.can_hide(CharacterTypes.neutral()))
	var stealthy = CharacterTypes.neutral()
	stealthy.skills = {"stealth": 70.0}
	_check("Stealth without woodwise is not enough", not CharacterTypes.can_hide(stealthy))
	var woodwise = CharacterTypes.neutral()
	woodwise.traits = ["woodwise"]
	_check("Woodwise without stealth is not enough", not CharacterTypes.can_hide(woodwise))
	woodwise.skills = {"stealth": 30.0}
	_check("Any kind with both can (not only rangers)", CharacterTypes.can_hide(woodwise))

func _test_where():
	print("\nWhere")
	var forest = Node2D.new()
	forest.scene_file_path = FOREST
	_check("The forest path is the wilds", Concealment.is_wild(forest))
	var village = Node2D.new()
	village.scene_file_path = VILLAGE
	_check("Thornhaven (a village) is not", not Concealment.is_wild(village))
	var floor_room = Node2D.new()
	floor_room.scene_file_path = FOREST
	var floor = Node2D.new()
	floor.name = "Floor"
	floor_room.add_child(floor)
	_check("Under a roof (a Floor) is not", not Concealment.is_wild(floor_room))
	_check("A scene the world does not know is not", not Concealment.is_wild(Node2D.new()))
	for n in [forest, village, floor_room]:
		n.free()

# =============================================================================

func _new_scene(path: String) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = Node2D.new()
	scene.name = "ConcealmentScene"
	scene.scene_file_path = path
	root.add_child(scene)
	player = Node2D.new()
	player.name = "Player"
	player.add_to_group("player")
	scene.add_child(player)

func _tree_at(at: Vector2) -> void:
	var body = StaticBody2D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(28, 28)
	shape.shape = rect
	body.add_child(shape)
	scene.add_child(body)
	body.global_position = at

func _renna(at: Vector2) -> Node2D:
	var npc = load("res://scenes/npcs/renna.tscn").instantiate()
	scene.add_child(npc)
	npc.global_position = at
	return npc

func _set_hour(hour: int) -> void:
	world_state.game_minutes = (saved_minutes / 1440) * 1440 + hour * 60

func _settle(npc: Node) -> Node:
	await physics_frame
	await physics_frame
	var c = npc.get_node_or_null("Concealment")
	if c:
		c.settle()
	return c

func _test_on_a_body():
	print("\nOn a body: Renna on the forest path")
	_set_hour(12)
	await _new_scene(FOREST)
	var renna = _renna(Vector2(300, 0))
	_tree_at(Vector2(330, 0))
	_tree_at(Vector2(270, 10))
	var c = await _settle(renna)
	_check("Renna gets a Concealment", c != null)
	if c == null:
		return
	var o = c.current_opts()
	_check("...in the wilds, among trees (cover %.2f)" % o.cover, o.wild and o.cover == 1.0)
	var reach = Concealment.spot_range(o)
	player.global_position = renna.global_position + Vector2(reach * 1.2, 0)
	c.settle()
	_check("Far off among the trees by day she is not drawn (%.0f px, range %.0f)" % [reach * 1.2, reach], c.alpha == 0.0 and renna.modulate.a == 0.0 and not c.seen)
	_check("...her name label is hidden", renna.get_node("NameLabel").modulate.a == 0.0)
	renna._on_interaction_area_body_entered(player)
	_check("...no prompt even with the player beside the trigger", not renna.get_node("InteractionPrompt").visible)
	_check("...and the player cannot talk to her", not renna.is_seen_by_player())
	var started = [false]
	renna.dialogue_started.connect(func(_id): started[0] = true)
	var key = InputEventAction.new()
	key.action = "interact"
	key.pressed = true
	renna.is_in_conversation = true  # stop a real greeting if the guard failed
	renna._unhandled_input(key)
	renna.is_in_conversation = false
	_check("...pressing interact does nothing", not started[0])
	_check("She still witnesses what she sees", renna.npc_id in Witnesses.in_sight(scene, player.global_position, {"hour": 12}))

	# Fades, no popping
	player.global_position = renna.global_position + Vector2(reach * 0.4, 0)
	c._physics_process(0.1)
	_check("Coming close she fades in, not pops (%.2f)" % c.alpha, c.alpha > 0.0 and c.alpha < 0.5)
	for i in 10:
		c._physics_process(0.1)
	_check("...and is drawn in full", c.alpha == 1.0 and c.seen)
	_check("...the prompt shows now the player is beside her", renna.get_node("InteractionPrompt").visible and renna.is_seen_by_player())
	renna._on_interaction_area_body_exited(player)

	# Open ground
	var open = _renna(Vector2(-900, 0))
	var co = await _settle(open)
	_check("On open ground she shows farther off (%.0f vs %.0f px)" % [Concealment.spot_range(co.current_opts()), reach], Concealment.spot_range(co.current_opts()) > reach)
	open.queue_free()

	# Night, and a lamp
	_set_hour(23)
	player.global_position = renna.global_position + Vector2(reach * 0.6, 0)
	c.settle()
	_check("At night, nearer than by day's range, she is not seen (%.0f px)" % (reach * 0.6), not c.seen)
	var lantern = Node2D.new()
	lantern.name = "Lantern"
	scene.add_child(lantern)
	lantern.global_position = renna.global_position
	var lamp = LAMP.new()
	lamp.exposure = "outdoors"
	lamp.lit = true
	lantern.add_child(lamp)
	await physics_frame
	c.settle()
	_check("A lit lamp beside her gives her away", c.seen)
	lantern.queue_free()
	await physics_frame
	_set_hour(12)

	# The player's eye
	player.global_position = renna.global_position + Vector2(reach * 1.2, 0)
	stats.set_skill("stealth", 100.0)
	c.settle()
	_check("A player with stealth 100 makes her out at that distance", c.seen)
	stats.set_skill("stealth", 0.0)

	# Moving
	c.settle()
	_check("(unseen again)", not c.seen)
	renna.velocity = Vector2(60, 0)
	c._physics_process(0.016)
	for i in 30:
		c._physics_process(0.016)
	_check("Moving, she is seen", c.seen)
	renna.velocity = Vector2.ZERO
	c._last_pos = renna.global_position
	c._physics_process(0.016)
	c.settle()
	_check("Still again, she fades from sight", not c.seen)

	# Shot, struck, speech
	var arrow = Node2D.new()
	arrow.set_script(_shot_script())
	arrow.shooter = renna
	scene.add_child(arrow)
	c.settle()
	_check("An arrow she looses shows where it came from", c.seen and c.is_revealed())
	c._reveal_until_ms = 0
	arrow.queue_free()
	c.settle()
	_check("...for a few seconds only", not c.seen)
	root.get_node("Combat").hit_landed.emit({"target": renna, "attacker": player})
	c.settle()
	_check("Struck, she is seen", c.seen)
	c._reveal_until_ms = 0
	c.settle()
	renna.dialogue_response_ready.emit(renna.npc_id, "You walk loud for someone on the King's road.")
	c.settle()
	_check("Speaking to the player, she is seen", c.seen)
	c._reveal_until_ms = 0
	renna.is_in_conversation = true
	c.settle()
	_check("...and stays seen while they talk", c.seen)
	renna.is_in_conversation = false

	# Out of the wilds
	print("\nOn a body: Renna in Thornhaven")
	await _new_scene(VILLAGE)
	var town = _renna(Vector2(0, 0))
	_tree_at(Vector2(20, 0))
	_tree_at(Vector2(-20, 0))
	var ct = await _settle(town)
	player.global_position = Vector2(2000, 0)
	ct.settle()
	_check("In a village she is drawn as anyone, however far", ct.alpha == 1.0 and ct.seen)

	print("\nOn a body: ordinary folk")
	await _new_scene(FOREST)
	var BaseNPC = load("res://scripts/npcs/base_npc.gd")
	var folk = BaseNPC.new()
	folk.npc_id = "nobody_in_particular"
	scene.add_child(folk)
	await process_frame
	_check("Ordinary folk get no Concealment", folk.get_node_or_null("Concealment") == null and folk.is_seen_by_player())

func _test_generic_ranger():
	print("\nOn a body: a generic ranger")
	if gm == null or gm.get_instance("gen_ranger_1") == null:
		_check("GenericManager has gen_ranger_1", false)
		return
	await _new_scene(FOREST)
	var npc = load("res://scenes/npcs/generic_npc.tscn").instantiate()
	npc.setup("gen_ranger_1", gm)
	scene.add_child(npc)
	npc.global_position = Vector2(0, 0)
	var c = await _settle(npc)
	_check("A generic ranger gets a Concealment", c != null)
	if c:
		player.global_position = Vector2(Concealment.SPOT_RANGE, 0)
		c.settle()
		_check("...and is unseen at the edge of open sight", not c.seen)

func _shot_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = "extends Node2D\nvar shooter = null\n"
	s.reload()
	return s

func _restore() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
	stats.set_skill("stealth", saved_stealth)
	physics.weather_override = saved_weather
	world_state.game_minutes = saved_minutes
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
