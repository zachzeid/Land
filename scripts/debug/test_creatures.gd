extends SceneTree

# Tests the creatures' places and the people's arms (docs/PLAYER_SYSTEMS.md §3):
# - CreatureSpawns markers in forest_path, iron_hollow and capitol_warrens: every marker (and the
#   offsets the spawner adds for a pack) stands on open ground a bear's body fits on, reachable on foot
#   from the scene's default spawn, and walled in on every side (inside the boundary). The spawner's
#   _inside_walls ray is not the test here: it is for its fallback ring, and tents and shanties on
#   the world_solid layer would pull a marker that stands behind one; markers are used as placed
# - culls: a creature killed in a place stays gone on re-entry the same day and after a save and load
#   (GenericManager's save, inside WorldState's "generics" block), and comes back once its
#   regrow_days have passed; wolves in days, the bear far longer
# - loadouts (resources/combat/loadouts.json): main NPCs and generic archetypes resolve hits with their
#   weapon and wear their armour; a minor carries nothing even if the body was given a blade
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_creatures.gd

const SpawnerScript = preload("res://scripts/combat/creature_spawner.gd")
const CreatureScript = preload("res://scripts/combat/creature.gd")
const SCENES = {
	"forest_path": "res://scenes/exterior/forest_path.tscn",
	"iron_hollow_camp": "res://scenes/exterior/iron_hollow.tscn",
	"capitol_warrens": "res://scenes/capitol/capitol_warrens.tscn",
}
const BODY = Vector2(60, 40)   # the largest creature body (the bear)
const CELL = 16.0
const REACH = 1100.0           # how far the walk search may go from the spawn point
const DAY = 1440

var world_state: Node
var registry: Node
var failures: int = 0
var saved_minutes: int
var save_existed: bool
var BaseNPCScript
var GenericNPCScript

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	registry = root.get_node("WorldRegistry")
	world_state.set_idle_clock_rate(0.0)
	var director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	saved_minutes = world_state.game_minutes
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	BaseNPCScript = load("res://scripts/npcs/base_npc.gd")
	GenericNPCScript = load("res://scripts/generics/generic_npc.gd")
	print("============================================================")
	print("🧪 CREATURES AND ARMS TEST")
	print("============================================================\n")

	for loc in SCENES:
		await _test_markers(loc, SCENES[loc])
	await _test_culls()
	await _test_loadouts()

	world_state.game_minutes = saved_minutes
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================
# MARKERS
# =============================================================================

## The most of one creature a visit can bring here (the spawner fans a pack out by (24, 18) a head)
func _pack(loc: String) -> int:
	var most = 1
	for def in CreatureScript.definitions().values():
		for w in def.get("where", []):
			if str(w.get("location", "")) == loc:
				most = maxi(most, int(w.get("count", [1, 1])[1]))
	return most

func _test_markers(loc: String, path: String) -> void:
	print("\nCreature spawns: %s" % loc)
	var scene: Node2D = load(path).instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame
	var holder = scene.get_node_or_null("CreatureSpawns")
	var markers: Array = holder.get_children().filter(func(m): return m is Marker2D) if holder else []
	_check("%s has CreatureSpawns markers (%d)" % [loc, markers.size()], markers.size() >= 4)
	_check("...at the scene's origin (the spawner reads marker positions as placed)", holder != null and holder.position == Vector2.ZERO)
	var start: Vector2 = scene.get_node("SpawnPoints/default").position
	var reach = _walkable_from(scene, start)
	var pack = _pack(loc)
	for m in markers:
		var spots: Array = []
		for k in pack:
			spots.append(m.position + Vector2(24 * k, 18 * k))
		var open = spots.all(func(p): return _fits(scene, p))
		var walk = spots.all(func(p): return reach.has(_cell(p)))
		_check("%s %s: open ground for a pack of %d, reachable from the spawn on foot" % [loc, m.name, pack], open and walk)
		_check("%s %s: walled in on every side (not out past the boundary)" % [loc, m.name], _enclosed(scene, m.position))
		_check("%s %s: not on top of the arrival point" % [loc, m.name], m.position.distance_to(start) > 120.0)
	scene.queue_free()
	await process_frame
	await physics_frame

## A ray each way from p meets a wall within the scene: the marker is inside the boundary
func _enclosed(scene: Node2D, p: Vector2) -> bool:
	var space = scene.get_viewport().get_world_2d().direct_space_state
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var q = PhysicsRayQueryParameters2D.create(scene.global_position + p, scene.global_position + p + d * REACH, 0xFFFF)
		q.collide_with_areas = false
		var blocked = false
		var exclude: Array = []
		for _i in 16:  # look past bodies that are not walls (the player, an NPC)
			q.exclude = exclude
			var hit = space.intersect_ray(q)
			if hit.is_empty():
				break
			if hit.collider is StaticBody2D:
				blocked = true
				break
			exclude.append(hit.rid)
		if not blocked:
			return false
	return true

## Whether a creature's body fits at p without touching a wall, tree, tent or prop (any static body)
func _fits(scene: Node2D, p: Vector2) -> bool:
	var space = scene.get_viewport().get_world_2d().direct_space_state
	var shape = RectangleShape2D.new()
	shape.size = BODY
	var q = PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, scene.global_position + p)
	q.collision_mask = 0xFFFF
	q.collide_with_areas = false
	for hit in space.intersect_shape(q, 16):
		if hit.collider is StaticBody2D:
			return false
	return true

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / CELL), roundi(p.y / CELL))

## Cells a creature's body can walk to from `start` (4-way flood over open cells)
func _walkable_from(scene: Node2D, start: Vector2) -> Dictionary:
	var seen: Dictionary = {}
	var open_cache: Dictionary = {}
	var queue: Array = [_cell(start)]
	seen[_cell(start)] = true
	var limit = int(REACH / CELL)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or absi(n.x) > limit or absi(n.y) > limit:
				continue
			if not open_cache.has(n):
				open_cache[n] = _fits_small(scene, Vector2(n) * CELL)
			if open_cache[n]:
				seen[n] = true
				queue.append(n)
	return seen

## A walking test body (a wolf's size): what fits through the gaps between trees
func _fits_small(scene: Node2D, p: Vector2) -> bool:
	var space = scene.get_viewport().get_world_2d().direct_space_state
	var shape = RectangleShape2D.new()
	shape.size = Vector2(30, 20)
	var q = PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, scene.global_position + p)
	q.collision_mask = 0xFFFF
	q.collide_with_areas = false
	for hit in space.intersect_shape(q, 16):
		if hit.collider is StaticBody2D:
			return false
	return true

# =============================================================================
# CULLS
# =============================================================================

func _test_culls() -> void:
	print("\nCulls: the dead stay dead until they regrow")
	_check("Wolves regrow in days, the bear far longer (wolf %d, bear %d days)" % [SpawnerScript.regrow_minutes("wolf") / DAY, SpawnerScript.regrow_minutes("bear") / DAY],
		SpawnerScript.regrow_minutes("wolf") <= 7 * DAY and SpawnerScript.regrow_minutes("wolf") >= 2 * DAY and SpawnerScript.regrow_minutes("bear") >= 60 * DAY)
	var generics = root.get_node("DynamicNPCRegistry").generics
	var spawner: Node = generics.creature_spawner if generics and generics.creature_spawner else null
	_check("GenericManager runs the creature spawner", spawner != null)
	if spawner == null:
		return
	var saved_culls = spawner.culls.duplicate(true)
	spawner.culls.clear()
	var day = 0
	while _count(spawner.plan_for("forest_path", day, day * DAY), "wolf") < 2:
		day += 1
	world_state.game_minutes = day * DAY + 600
	var wolves = _count(spawner.plan_for("forest_path", day), "wolf")
	var scene = Node2D.new()
	root.add_child(scene)
	var made: Array = spawner.spawn_into("forest_path", scene, day)
	var boars = _count_nodes(made, "boar")
	var wolf = made.filter(func(c): return c.creature_id == "wolf")[0]
	wolf.take_hit({"damage": 999.0, "type": "cut", "staggered": false, "killed": true}, null)
	await process_frame
	_check("A wolf killed in the Darkwood is a cull there (%s)" % [spawner.culls.get("forest_path", [])], spawner.culled("forest_path", "wolf") == 1)
	var again: Array = spawner.spawn_into("forest_path", scene, day)
	await process_frame
	_check("Re-entering the same day, one wolf fewer (%d -> %d)" % [wolves, _count_nodes(again, "wolf")], _count_nodes(again, "wolf") == wolves - 1)
	_check("...and the other creatures there are the same as before", _count_nodes(again, "boar") == boars)

	# Through the save: GenericManager carries the spawner's state; WorldState's save holds it
	var ws_save: Dictionary = world_state.save()
	_check("WorldState's save holds the culls (generics.creatures)", ws_save.get("generics", {}).get("creatures", {}).get("culls", {}).has("forest_path"))
	var text = JSON.stringify(generics.save())
	spawner.culls.clear()
	_check("(cleared, the wolf would be back)", _count(spawner.plan_for("forest_path", day), "wolf") == wolves)
	generics.load_from_dict(JSON.parse_string(text))
	_check("After a load the wolf is still dead", spawner.culled("forest_path", "wolf") == 1 and _count(spawner.plan_for("forest_path", day), "wolf") == wolves - 1)
	var fresh = SpawnerScript.new()
	fresh.load_from_dict(JSON.parse_string(text).get("creatures", {}))
	_check("A new spawner loaded from that save knows it too", fresh.culled("forest_path", "wolf", world_state.game_minutes) == 1)
	fresh.free()

	# Regrowth
	var killed_at = int(spawner.culls.forest_path[0].at)
	var back = killed_at + SpawnerScript.regrow_minutes("wolf")
	_check("A day before it regrows the place is still thin", spawner.culled("forest_path", "wolf", back - DAY) == 1)
	_check("Once regrow_days have passed, the wolf is back", spawner.culled("forest_path", "wolf", back) == 0)
	spawner.prune(back)
	_check("...and the save forgets it", not spawner.culls.has("forest_path"))
	spawner.note_cull("iron_hollow_camp", "bear", 1000)
	_check("A bear killed on the ridge is still gone a season later", spawner.culled("iron_hollow_camp", "bear", 1000 + 60 * DAY) == 1)
	_check("Culls belong to the place: a Darkwood kill does not thin the Warrens", spawner.culled("capitol_warrens", "wolf", back - DAY) == 0)

	for c in scene.get_children():
		c.queue_free()
	scene.queue_free()
	spawner.culls = saved_culls
	await process_frame

func _count(plan: Array, id: String) -> int:
	for row in plan:
		if row.creature == id:
			return int(row.n)
	return 0

func _count_nodes(nodes: Array, id: String) -> int:
	return nodes.filter(func(c): return is_instance_valid(c) and c.creature_id == id and c.is_alive).size()

# =============================================================================
# LOADOUTS
# =============================================================================

func _test_loadouts() -> void:
	print("\nLoadouts: people fight with what they carry")
	var combat = root.get_node("Combat")
	var scene = Node2D.new()
	root.add_child(scene)
	var wolf = SpawnerScript.instance("bear")  # a big target (a creature: no deeds recorded)
	wolf.position = Vector2(40, 0)
	scene.add_child(wolf)
	var bjorn = _body(scene, "bjorn")
	var aldric = _body(scene, "aldric")
	var ysolde = _body(scene, "ysolde")
	var rook = _body(scene, "rook")
	rook.combat_weapon = "arming_sword"  # given a blade, a child still carries nothing
	var soldier = _generic(scene, "gen_garrison_soldier_t1", "garrison_soldier")
	var farmer = _generic(scene, "gen_valley_farmer_t1", "valley_farmer")
	await process_frame
	var bp = bjorn.get_combat_profile()
	_check("Bjorn fights with his smith's hammer, in leather (%s, %s)" % [bp.weapon, bp.armour], bp.weapon == "smiths_hammer" and bp.armour == ["leather_jerkin"])
	var hit = combat.resolve_hit(bjorn, wolf, {}, "light")
	_check("...and his hits land as the hammer: blunt, %.0f before resistance" % hit.raw, hit.weapon == "smiths_hammer" and hit.type == "blunt" and hit.raw > 4.0)
	hit = combat.resolve_hit(aldric, wolf, {}, "light")
	_check("Aldric strikes with his steel sword (cut, %.0f)" % hit.raw, hit.weapon == "arming_sword" and hit.type == "cut")
	_check("...and wears his mail", aldric.get_combat_profile().armour == ["mail_shirt"])
	hit = combat.resolve_hit(ysolde, wolf, {}, "light")
	_check("Sister Ysolde carries nothing: bare hands (%s)" % hit.weapon, hit.weapon == "fists")
	var rp = rook.get_combat_profile()
	_check("Rook, a minor, carries nothing even when handed a sword (%s)" % rp.weapon, rp.weapon == "fists" and rp.armour.is_empty() and rp.minor)
	hit = combat.resolve_hit(soldier, wolf, {}, "light")
	_check("A garrison soldier strikes with an iron sword, in jack and helm (%s)" % [soldier.get_combat_profile().armour], hit.weapon == "short_sword" and soldier.get_combat_profile().armour == ["padded_jack", "helm"])
	_check("A valley farmer has no loadout: bare hands", combat.resolve_hit(farmer, wolf, {}, "light").weapon == "fists")
	var blade = combat.resolve_hit(aldric, bjorn, {}, "light")
	var bare = combat.resolve_hit(ysolde, bjorn, {}, "light")
	_check("Armour turns some of a blade (raw %.1f, taken %.1f)" % [blade.raw, blade.damage], blade.damage < blade.raw)
	_check("...and a sword does more than bare hands (%.1f vs %.1f)" % [blade.damage, bare.damage], blade.damage > bare.damage)
	scene.queue_free()
	await process_frame

func _body(scene: Node, key: String) -> Node:
	var n = BaseNPCScript.new()
	n.npc_id = registry.get_npc_id(key) if registry.has_npc(key) else key
	n.npc_name = key.capitalize()
	n.position = Vector2(randi_range(-200, 200), 120)
	n.process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(n)
	return n

func _generic(scene: Node, id: String, archetype: String) -> Node:
	var n = GenericNPCScript.new()
	n.npc_id = id
	n.generic_id = id
	n.archetype_id = archetype
	n.npc_name = archetype.capitalize()
	n.process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(n)
	return n

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
