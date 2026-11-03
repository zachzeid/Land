extends SceneTree

# Tests the taverns added so every settlement has its inn (docs/WORLD_SCHEMA.md §16):
# - the Tarred Rope (Ferrisford), the Spoil Heap (Greystone), the Wet Load (the River Quarter) and the
#   Brass Scales (the Lantern Market) are built world.json interiors with LocationData, a tavern block
#   and a walking route from the exterior they open onto; none is a travel point, and each can be
#   reached from Thornhaven
# - each scene loads as a valid interior; its way out names its exterior and a from_<tavern> spawn
#   there, and the exterior's door names the tavern and a spawn point inside
# - one Bed per room (bed.gd), each in its own walled room with a doorway, its rent the block's
#   rent_copper, its keeper the block's keeper, waking at its own SpawnPoints marker on open ground;
#   every StaticBody2D sits on a world layer; Capitol rooms cost more than village rooms
# - the keeper is the tavern_keeper generic population.json puts there, with a marker behind the
#   counter, and patrons who fit the place drink there
# - the settlement rule: every village and town has a tavern, every city two
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_new_taverns.gd

const SCENE_TRIGGER = "res://scripts/world/scene_trigger.gd"
const BED_SCRIPT = "res://scripts/world/bed.gd"
const Manager = preload("res://scripts/generics/generic_manager.gd")
const BaseInterior = preload("res://scripts/world/base_interior.gd")
const PLAYER_BODY = Vector2(32, 48)   # scenes/player/player.tscn: feet at the origin, body above
const SIZES = {"village": 1, "town": 1, "city": 2}
const JOIN_MINUTES = 60   # tools/validators/settlements.py
const PENDING_BLOCKS = ["thornhaven_tavern"]   # settlements.py: counts until the tavern system gives it its block

## id -> [exterior, patron archetypes]
const TAVERNS = {
	"ferrisford_tavern": ["ferrisford", ["carter", "dockhand"]],
	"greystone_tavern": ["greystone_mines", ["miner", "carter"]],
	"capitol_docks_tavern": ["capitol_docks", ["dockhand"]],
	"capitol_market_inn": ["capitol_market", ["courier", "clerk", "pilgrim"]],
}

class FakeDirector extends Node:
	signal round_completed(round_number: int, reason: String, entries: Array)
	func register_soul(_key: String, _text: String, _opts: Dictionary = {}) -> bool:
		return true
	func unregister_soul(_key: String) -> void:
		pass
	func set_soul_tier(_key: String, _tier: String) -> void:
		pass
	func get_soul(_key: String):
		return null

var failures: int = 0
var registry: Node

func _init():
	await process_frame
	await process_frame
	registry = root.get_node("WorldRegistry")
	root.get_node("WorldState").set_idle_clock_rate(0.0)
	print("============================================================")
	print("🧪 NEW TAVERNS TEST")
	print("============================================================\n")

	_test_registration()
	_test_scenes()
	_test_keepers()
	_test_settlements()

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _test_registration() -> void:
	print("Registration")
	var scene_manager = root.get_node("SceneManager")
	for id in TAVERNS:
		var loc: Dictionary = registry.get_location(id)
		var tav = loc.get("tavern")
		_check("%s is a built interior" % id, registry.is_built(id) and loc.get("kind", "") == "interior" and loc.get("settlement", "") in SIZES)
		_check("%s has a tavern block (keeper, rooms >= 1, rent, no brothel)" % id, tav is Dictionary and str(tav.get("keeper", "")) != ""
			and int(tav.get("rooms", 0)) >= 1 and int(tav.get("rent_copper", 0)) > 0 and tav.get("brothel", true) == false)
		_check("%s has LocationData for its scene" % id, scene_manager.get_location(id) != null and scene_manager.get_location(id).scene_path == registry.get_location_scene(id))
		_check("%s: a walking route from %s" % [id, TAVERNS[id][0]], registry.get_route_minutes(TAVERNS[id][0], id) > 0
			and "foot" in registry.get_route(TAVERNS[id][0], id).get("modes", []))
		_check("%s is walked into, not a travel point" % id, not registry.is_travel_point(id))
		_check("%s can be reached from Thornhaven" % id, registry.is_reachable("thornhaven_town_square", id))
		_check("%s's name is canon-safe" % id, not registry.contains_forbidden_concept(registry.get_location_name(id)))
	var rent = func(id): return int(registry.get_location(id).tavern.rent_copper)
	_check("Capitol rooms cost more than village rooms", mini(rent.call("capitol_docks_tavern"), rent.call("capitol_market_inn")) > rent.call("ferrisford_tavern"))
	_check("A night's room is under a labourer's day in the valley's country, more in the Capitol", rent.call("ferrisford_tavern") < 9 and rent.call("capitol_market_inn") > 9)

func _test_scenes() -> void:
	print("\nScenes, doors and rooms")
	for id in TAVERNS:
		var tav: Dictionary = registry.get_location(id).tavern
		var exterior_id: String = TAVERNS[id][0]
		var scene = load(registry.get_location_scene(id)).instantiate()
		var outside = load(registry.get_location_scene(exterior_id)).instantiate()
		_check("%s: scene loads" % id, scene != null and outside != null)
		_check("%s: a valid interior (square floor, four walls, spawn points)" % id, BaseInterior.validate_interior_scene(scene).valid)

		var out_ways = _triggers(scene).filter(func(t): return str(t.target_location) == exterior_id)
		_check("%s: a way out to %s" % [id, exterior_id], out_ways.size() == 1)
		if out_ways.size() == 1:
			_check("%s: ...arriving at %s's from_%s" % [id, exterior_id, id], _spawn(outside, str(out_ways[0].target_spawn_point)) != null
				and str(out_ways[0].target_spawn_point) == "from_" + id)
		var in_ways = _triggers(outside).filter(func(t): return str(t.target_location) == id)
		_check("%s: a door in %s" % [id, exterior_id], in_ways.size() == 1)
		if in_ways.size() == 1:
			_check("%s: ...arriving at a spawn point inside" % id, _spawn(scene, str(in_ways[0].target_spawn_point)) != null)

		var beds = _all(scene).filter(func(n): return n.get_script() != null and n.get_script().resource_path == BED_SCRIPT)
		_check("%s: %d Bed node(s), one per room" % [id, int(tav.rooms)], beds.size() == int(tav.rooms))
		_check("%s: every bed's rent is %d copper" % [id, int(tav.rent_copper)], beds.all(func(b): return int(b.rent) == int(tav.rent_copper)))
		_check("%s: every bed names its keeper and its location" % id, beds.all(func(b): return str(b.keeper) == str(tav.keeper) and str(b.location_id) == id))
		var marks: Dictionary = {}
		for b in beds:
			marks[str(b.spawn_point)] = true
		_check("%s: each bed wakes at its own SpawnPoints marker" % id, marks.size() == beds.size() and beds.all(func(b): return _spawn(scene, str(b.spawn_point)) != null))
		var rooms: Dictionary = {}
		for b in beds:
			rooms[b.get_parent()] = true
		_check("%s: each bed is in a walled room of its own with a doorway" % id, beds.all(_in_walled_room) and rooms.size() == beds.size())
		var bodies = _all(scene).filter(func(n): return n is StaticBody2D)
		_check("%s: every StaticBody2D is a wall (layer value 4) or a prop (8)" % id, not bodies.is_empty() and bodies.all(func(n): return n.collision_layer in [4, 8]))
		_check("%s: the keeper has a marker behind the counter" % id, scene.find_child("npc_" + str(tav.keeper), true, false) is Marker2D)

		var solids = _solids(scene)
		var bounds = _bounds(solids)
		var bad: Array = []
		for m in scene.find_child("SpawnPoints", true, false).get_children():
			if not _open(_pos(m), solids, bounds):
				bad.append(str(m.name))
		_check("%s: every spawn point on open ground inside the walls%s" % [id, "" if bad.is_empty() else " (" + ", ".join(bad) + ")"], bad.is_empty())
		var arrive = _spawn(outside, "from_" + id)
		_check("%s: from_%s stands on open ground in %s" % [id, id, exterior_id], arrive != null and _open(_pos(arrive), _solids(outside), _bounds(_solids(outside))))
		var house = outside.find_child(str(in_ways[0].name).trim_suffix("Door"), true, false) if in_ways.size() == 1 else null
		_check("%s: the house in %s is a wall-layer building" % [id, exterior_id], house is StaticBody2D and house.collision_layer == 4)
		scene.free()
		outside.free()

func _test_keepers() -> void:
	print("\nKeepers and patrons")
	var m = Manager.new()
	m.auto_boot = false
	m.use_chromadb = false
	m.write_souls_in_character = false
	m.souls_dir = "user://test_new_taverns_souls"
	m.director_override = FakeDirector.new()
	root.add_child(m)
	m.load_content()
	_check("The tavern_keeper archetype parses", m.archetypes.has("tavern_keeper") and not m.archetype_errors.keys().any(func(f): return str(f).contains("tavern_keeper")))
	m.populate()
	for id in TAVERNS:
		var keeper = str(registry.get_location(id).tavern.keeper)
		var inst = m.get_instance(keeper)
		_check("%s: keeper %s is a tavern_keeper who lives there" % [id, keeper], inst != null and inst.archetype_id == "tavern_keeper" and inst.home == id)
		var here = m.get_ids().filter(func(g): return m.get_instance(g).home == id)
		var kinds: Dictionary = {}
		for g in here:
			kinds[m.get_instance(g).archetype_id] = true
		_check("%s: patrons fit the place (%s)" % [id, ", ".join(TAVERNS[id][1])], TAVERNS[id][1].all(func(a): return kinds.has(a)) and here.size() >= 3)
	m.queue_free()

## Settlements as tools/validators/settlements.py groups them: same size, joined by short routes
func _test_settlements() -> void:
	print("\nSettlements")
	var ids: Array = registry.get_location_ids()
	var near: Dictionary = {}
	for a in ids:
		near[a] = ids.filter(func(b): return b != a and registry.get_route_minutes(a, b) >= 0 and registry.get_route_minutes(a, b) <= JOIN_MINUTES)
	var seen: Dictionary = {}
	var found: Array = []
	for id in ids:
		var size = str(registry.get_location(id).get("settlement", ""))
		if not SIZES.has(size) or seen.has(id):
			continue
		var group: Array = []
		var todo: Array = [id]
		seen[id] = true
		while not todo.is_empty():
			var cur = todo.pop_back()
			group.append(cur)
			for nxt in near[cur]:
				if not seen.has(nxt) and str(registry.get_location(nxt).get("settlement", "")) == size:
					seen[nxt] = true
					todo.append(nxt)
		var joined: Dictionary = {}
		for g in group:
			joined[g] = true
			for n in near[g]:
				joined[n] = true
		var taverns = joined.keys().filter(_is_tavern)
		found.append({"size": size, "members": group, "taverns": taverns})
		_check("%s %s (%d places): %d tavern(s), needs %d" % [size, registry.get_area(group[0]), group.size(), taverns.size(), SIZES[size]], taverns.size() >= SIZES[size])
	var sizes = found.map(func(s): return s.size)
	_check("Four settlements: Thornhaven, Ferrisford, Greystone and the Capitol", found.size() == 4 and sizes.count("city") == 1)
	var capitol = found.filter(func(s): return s.size == "city")
	_check("The Capitol's two taverns are the Wet Load and the Brass Scales", not capitol.is_empty()
		and "capitol_docks_tavern" in capitol[0].taverns and "capitol_market_inn" in capitol[0].taverns)
	_check("Not settlements: the fort, the camp, the abbey, the mill", ["fort_ashguard", "iron_hollow_camp", "brackenmoor_abbey", "old_mill", "the_pit"].all(func(i): return not registry.get_location(i).has("settlement")))

## A location with a tavern block (or the Rusty Nail until the tavern system gives it one)
func _is_tavern(id: String) -> bool:
	var loc: Dictionary = registry.get_location(id)
	return loc.get("tavern") is Dictionary or (id in PENDING_BLOCKS and not loc.has("tavern"))

## A Bed whose parent is a RoomN with walls (layer value 4) and a Door
func _in_walled_room(bed: Node) -> bool:
	var room = bed.get_parent()
	var walls = room.get_children().filter(func(c): return c is StaticBody2D and c.collision_layer == 4)
	return str(room.name).begins_with("Room") and walls.size() >= 2 and room.get_node_or_null("Door") != null

func _open(at: Vector2, solids: Array, bounds: Rect2) -> bool:
	var body = Rect2(at - Vector2(PLAYER_BODY.x / 2.0, PLAYER_BODY.y), PLAYER_BODY)
	return bounds.has_area() and bounds.encloses(Rect2(at, Vector2.ONE)) and not solids.any(func(r): return r.intersects(body))

func _triggers(scene: Node) -> Array:
	return _all(scene).filter(func(n): return n.get_script() != null and n.get_script().resource_path == SCENE_TRIGGER)

func _spawn(scene: Node, spawn_name: String) -> Node:
	var points = scene.find_child("SpawnPoints", true, false)
	var m = points.find_child(spawn_name, false, false) if points else null
	return m if m is Marker2D else null

## Rects of every StaticBody2D's rectangle shapes, in scene coordinates
func _solids(scene: Node) -> Array:
	var out: Array = []
	for n in _all(scene):
		if n is StaticBody2D:
			for c in n.get_children():
				if c is CollisionShape2D and c.shape is RectangleShape2D:
					var size: Vector2 = c.shape.size
					out.append(Rect2(_pos(c) - size / 2.0, size))
	return out

## The inner rectangle of the walls: the largest box the solids at the edges close in
func _bounds(solids: Array) -> Rect2:
	if solids.is_empty():
		return Rect2()
	var outer = solids[0]
	for r in solids:
		outer = outer.merge(r)
	var left = outer.position.x
	var right = outer.end.x
	var top = outer.position.y
	var bottom = outer.end.y
	for r in solids:
		if r.size.y > outer.size.y * 0.8:
			if r.get_center().x < outer.get_center().x:
				left = maxf(left, r.end.x)
			else:
				right = minf(right, r.position.x)
		if r.size.x > outer.size.x * 0.8:
			if r.get_center().y < outer.get_center().y:
				top = maxf(top, r.end.y)
			else:
				bottom = minf(bottom, r.position.y)
	return Rect2(left, top, right - left, bottom - top)

## Position in scene coordinates (no rotation or scale on these nodes)
func _pos(n: Node) -> Vector2:
	var p = Vector2.ZERO
	var cur = n
	while cur and cur.get_parent() != null:
		if cur is Node2D:
			p += cur.position
		cur = cur.get_parent()
	return p

func _all(node: Node) -> Array:
	var out: Array = [node]
	for c in node.get_children():
		out.append_array(_all(c))
	return out

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
