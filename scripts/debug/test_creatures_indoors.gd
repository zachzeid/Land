extends SceneTree

# Tests that creatures stay out of buildings (docs/WORLD_SCHEMA.md "Buildings"):
# - the rule is data: world.json `building`, else kind "interior"; the Pit and the Old Workings are
#   dug, not built; a location not yet in world.json counts as a building
# - no creatures.json `where` names a building, and in every location's scene no CreatureSpawns
#   marker (nor the offsets a pack fans out by) stands in a building location, inside a world_solid
#   body (a building's footprint) or in a doorway (any SceneTrigger, or a "building_zones" Area2D)
# - the spawner refuses a planted indoor marker (in a house, at its door, in a building location) and
#   still uses the open one
# - a creature chasing its quarry to a door stops outside, loiters, gives up and walks home; fleeing
#   toward a door it stops at the edge; shoved in, it steps back out; it never sets off a SceneTrigger
# Fakes only: no API calls, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_creatures_indoors.gd

const SpawnerScript = preload("res://scripts/combat/creature_spawner.gd")
const CreatureScript = preload("res://scripts/combat/creature.gd")
const TriggerScript = preload("res://scripts/world/scene_trigger.gd")
const WORLD_PATH = "res://resources/world/world.json"
const DT = 0.1

var failures: int = 0
var world_state: Node
var saved_minutes: int
var save_existed: bool
var set_aside: Array = []

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	world_state.set_idle_clock_rate(0.0)
	var director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	saved_minutes = world_state.game_minutes
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	print("============================================================")
	print("🧪 CREATURES STAY OUTDOORS TEST")
	print("============================================================\n")

	_test_rule()
	await _test_all_scenes()
	await _test_planted()
	await _test_pursuit()
	await _test_flee_and_shove()
	await _test_real_door()
	for p in set_aside:
		if is_instance_valid(p):
			p.add_to_group("player")

	world_state.game_minutes = saved_minutes
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _locations() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(WORLD_PATH))
	return parsed.get("locations", []) if parsed is Dictionary else []

# =============================================================================
# THE RULE
# =============================================================================

func _test_rule() -> void:
	print("\nWhat counts as a building")
	for id in ["thornhaven_tavern", "thornhaven_blacksmith", "thornhaven_chapel", "council_hall", "healer_hut",
			"kingsroad_waystation", "brackenmoor_abbey", "abbey_undercroft", "capitol_palace", "ashdown_manor"]:
		_check("%s is a building" % id, CreatureScript.is_building(id))
	for id in ["the_pit", "old_workings", "forest_path", "iron_hollow_camp", "greystone_mines", "capitol_warrens", "ferrisford"]:
		_check("%s is not" % id, not CreatureScript.is_building(id))
	_check("An interior added later defaults to a building", CreatureScript.location_is_building({"id": "x", "kind": "interior"}))
	_check("...unless it says `building: false` (a cave)", not CreatureScript.location_is_building({"kind": "interior", "building": false}))
	_check("An exterior is open ground unless it says `building: true`", not CreatureScript.location_is_building({"kind": "exterior"})
		and CreatureScript.location_is_building({"kind": "exterior", "building": true}))
	_check("A door to a location not yet in world.json counts as a way indoors", CreatureScript.is_building("a_tavern_not_yet_written"))
	var homes: Array = []
	for def in CreatureScript.definitions().values():
		for w in def.get("where", []):
			if CreatureScript.is_building(str(w.get("location", ""))):
				homes.append("%s@%s" % [def.id, w.location])
	_check("No creature lives in a building location %s" % [homes], homes.is_empty())

# =============================================================================
# EVERY SCENE
# =============================================================================

func _pack(loc: String) -> int:
	var most = 1
	for def in CreatureScript.definitions().values():
		for w in def.get("where", []):
			if str(w.get("location", "")) == loc:
				most = maxi(most, int(w.get("count", [1, 1])[1]))
	return most

func _test_all_scenes() -> void:
	print("\nEvery location's scene: markers outdoors")
	var scanned = 0
	var with_markers = 0
	for loc in _locations():
		var path = str(loc.get("scene", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var scene: Node = load(path).instantiate()
		root.add_child(scene)
		await physics_frame
		await physics_frame
		scanned += 1
		var holder = scene.find_child("CreatureSpawns", true, false)
		var markers: Array = holder.get_children().filter(func(m): return m is Marker2D) if holder else []
		if not markers.is_empty():
			with_markers += 1
			_check("%s: has creature markers and is not a building" % loc.id, not CreatureScript.location_is_building(loc))
			var blocked = SpawnerScript.Blocked.new(scene)
			var space = scene.get_viewport().get_world_2d().direct_space_state
			var bad: Array = []
			for m in markers:
				for k in _pack(str(loc.id)):
					var p: Vector2 = holder.position + m.position + Vector2(24 * k, 18 * k)
					var why = blocked.why(p)
					var q = PhysicsPointQueryParameters2D.new()
					q.position = scene.get_global_transform() * p
					q.collision_mask = SpawnerScript.SOLID_MASK
					q.collide_with_areas = false
					# only this scene's bodies (the project's main scene may also stand in the tree)
					var hits = space.intersect_point(q, 8).filter(func(h): return h.collider is Node and scene.is_ancestor_of(h.collider))
					if why == "" and not hits.is_empty():
						why = "building (physics: %s)" % scene.get_path_to(hits[0].collider)
					if why != "":
						bad.append("%s+%d %s" % [m.name, k, why])
			_check("%s: %d markers, none in a building footprint or doorway %s" % [loc.id, markers.size(), bad], bad.is_empty())
		root.remove_child(scene)
		scene.free()  # now, so its bodies are gone from the space before the next scene is read
		await physics_frame
		await physics_frame
	_check("Scanned every built location's scene (%d, %d with markers)" % [scanned, with_markers], scanned >= 20 and with_markers >= 5)

# =============================================================================
# A PLANTED HOUSE
# =============================================================================

## A house (world_solid body, 200x200 at the origin) with its tavern door below it at (0, 130),
## and the given markers
func _house(markers: Dictionary) -> Node2D:
	var scene = Node2D.new()
	scene.name = "PlantedHouse"
	root.add_child(scene)
	var house = StaticBody2D.new()
	house.name = "House"
	house.collision_layer = 4
	var cs = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(200, 200)
	cs.shape = shape
	house.add_child(cs)
	scene.add_child(house)
	var door = Area2D.new()
	door.name = "Door"
	door.set_script(TriggerScript)
	door.set("target_location", "thornhaven_tavern")
	door.position = Vector2(0, 130)
	var dcs = CollisionShape2D.new()
	var dshape = RectangleShape2D.new()
	dshape.size = Vector2(60, 40)
	dcs.shape = dshape
	door.add_child(dcs)
	scene.add_child(door)
	var holder = Node2D.new()
	holder.name = "CreatureSpawns"
	scene.add_child(holder)
	for n in markers:
		var m = Marker2D.new()
		m.name = n
		m.position = markers[n]
		holder.add_child(m)
	return scene

func _test_planted() -> void:
	print("\nThe spawner refuses indoor markers")
	var spawner = SpawnerScript.new()
	root.add_child(spawner)
	spawner.enabled = false
	var day = 0
	while spawner.plan_for("forest_path", day, day * 1440).is_empty():
		day += 1
	var scene = _house({"InTheHouse": Vector2(10, -20), "AtTheDoor": Vector2(0, 135), "Open": Vector2(500, 0)})
	await physics_frame
	var made: Array = spawner.spawn_into("forest_path", scene, day)
	var whys = spawner.last_report.get("refused", []).map(func(r): return r.why)
	_check("A marker inside the house is refused (%s)" % [whys], "building" in whys)
	_check("...and one in its doorway", "doorway" in whys)
	_check("The open marker is used: %d creatures, all out on open ground" % made.size(),
		not made.is_empty() and made.all(func(c): return c.position.distance_to(Vector2(500, 0)) < 120.0))
	for c in made:
		c.queue_free()
	scene.queue_free()
	await process_frame

	scene = _house({"InTheHouse": Vector2(0, 0), "AtTheDoor": Vector2(20, 120)})
	await physics_frame
	made = spawner.spawn_into("forest_path", scene, day)
	_check("Only indoor markers: nothing spawns (not even on the fallback ring)", made.is_empty())
	scene.queue_free()
	await process_frame

	# A creatures.json entry naming a building is refused at spawn time too
	var rat: Dictionary = CreatureScript.definitions()["rat"]
	rat.where.append({"location": "thornhaven_tavern", "count": [2, 2], "chance": 1.0})
	scene = Node2D.new()
	root.add_child(scene)
	_check("(a planted rat entry for the Rusty Nail is in the plan)", not spawner.plan_for("thornhaven_tavern", 0, 0).is_empty())
	made = spawner.spawn_into("thornhaven_tavern", scene, 0)
	_check("...but no rat spawns in the tavern (%s)" % [spawner.last_report.get("refused", [])], made.is_empty())
	rat.where.pop_back()
	scene.queue_free()
	spawner.queue_free()
	await process_frame

# =============================================================================
# PURSUIT, FLIGHT, SHOVES
# =============================================================================

## The only "player" while a test runs (any other player body is set aside, see _restore_players)
func _quarry(scene: Node, at: Vector2) -> Node2D:
	for other in get_nodes_in_group("player"):
		other.remove_from_group("player")
		set_aside.append(other)
	var p = Node2D.new()
	p.name = "Quarry"
	p.position = at
	scene.add_child(p)
	p.add_to_group("player")
	return p

func _wolf(scene: Node, at: Vector2) -> Node:
	var w = SpawnerScript.instance("wolf")
	w.position = at
	w.zone_root = scene
	w.set_physics_process(false)  # stepped by hand: the test owns its position
	scene.add_child(w)
	w.home = at
	return w

## Steps a creature n times; returns whether it ever stood in a doorway
func _run(c: Node, n: int, each: Callable = Callable()) -> bool:
	var entered = false
	for i in n:
		c.global_position += c.think(DT) * DT
		if not c.zone_at(c.global_position).is_empty():
			entered = true
		if each.is_valid():
			each.call(i)
	return entered

func _test_pursuit() -> void:
	print("\nA quarry who goes indoors is safe")
	var scene = _house({})
	await physics_frame
	var player = _quarry(scene, Vector2(0, 300))
	var wolf = _wolf(scene, Vector2(0, 500))
	wolf.think(DT)
	_check("The wolf has its quarry in the open (%s)" % wolf.state, wolf.target == player and wolf.state == "stalk")
	player.position = Vector2(0, 135)  # into the tavern door
	var states: Dictionary = {}
	var entered = _run(wolf, 30, func(_i): states[wolf.state] = true)
	_check("It follows to the door and stops outside (never in the doorway; at %s)" % wolf.position, not entered)
	_check("...and loiters there (%s)" % [states.keys()], states.has("loiter") and wolf.state == "loiter")
	_check("...without a strike at a quarry in the door", wolf._cooldown <= 0.0)
	_run(wolf, int(CreatureScript.LOITER_SECONDS / DT) + 2)
	_check("Then it loses interest and turns for home (%s)" % wolf.state, wolf.state == "return" and wolf.target == null)
	_run(wolf, 200)
	_check("...and walks back to its spot (%s, home %s)" % [wolf.position, wolf.home], wolf.state == "idle" and wolf.position.distance_to(wolf.home) <= CreatureScript.HOME_RADIUS + 2.0)
	player.position = Vector2(0, 300)
	wolf.think(DT)
	_check("It does not take up the same quarry again at once", wolf.target == null)
	wolf.take_hit({"damage": 1.0, "type": "cut", "staggered": false, "killed": false}, player)
	_check("...unless struck by it", wolf.target == player)
	scene.queue_free()
	await process_frame

func _test_flee_and_shove() -> void:
	print("\nFleeing, shoved, at a trigger")
	var scene = _house({})
	await physics_frame
	var player = _quarry(scene, Vector2(0, 340))
	var wolf = _wolf(scene, Vector2(0, 200))
	wolf.health = wolf.max_health * 0.1  # badly hurt: it runs, and the door is behind it
	var states: Dictionary = {}
	wolf.target = player
	var entered = _run(wolf, 30, func(_i): states[wolf.state] = true)
	_check("A wolf fleeing toward a door stops at its edge (%s, %s)" % [wolf.position, states.keys()], states.has("flee") and not entered)

	wolf.global_position = Vector2(0, 140)  # shoved, knocked or placed into the doorway
	var out = _run(wolf, 1)
	var steps = 1
	while not wolf.zone_at(wolf.global_position).is_empty() and steps < 20:
		_run(wolf, 1)
		steps += 1
	_check("Shoved into a doorway, it steps straight back out (%d steps, at %s)" % [steps, wolf.position], out and wolf.zone_at(wolf.global_position).is_empty() and steps < 20)

	var door: Area2D = scene.get_node("Door")
	var fired = [0]
	door.triggered.connect(func(_t): fired[0] += 1)
	_check("A creature is not on the layer doors listen to (layer %d, door mask %d)" % [wolf.collision_layer, door.collision_mask], wolf.collision_layer & door.collision_mask == 0)
	door._on_body_entered(wolf)
	_check("...and a creature in a door neither opens it nor is carried through", fired[0] == 0 and not door.player_in_range and wolf.get_parent() == scene)
	var bare = CreatureScript.new()
	bare.setup("rat")
	scene.add_child(bare)
	_check("A bare creature body is moved off the player layer (%d)" % bare.collision_layer, bare.collision_layer & door.collision_mask == 0)
	scene.queue_free()
	await process_frame

func _test_real_door() -> void:
	print("\nThe Rusty Nail's door in Thornhaven")
	var scene: Node2D = load("res://scenes/game_world.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	var door: Area2D = scene.get_node("Tavern/DoorTrigger")
	var at: Vector2 = door.global_position
	var player = _quarry(scene, at + Vector2(0, 200))
	var wolf = _wolf(scene, at + Vector2(0, 420))
	wolf.think(DT)
	_check("A wolf in the square has its quarry", wolf.target == player)
	player.global_position = at
	var entered = _run(wolf, 25)
	_check("Its quarry goes in at the tavern door: it stays outside (%s) and loiters (%s)" % [wolf.global_position - at, wolf.state], not entered and wolf.state == "loiter")
	_run(wolf, int(CreatureScript.LOITER_SECONDS / DT) + 2)
	_check("...then gives up", wolf.state in ["return", "idle"] and wolf.target == null)
	scene.queue_free()
	await process_frame

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
