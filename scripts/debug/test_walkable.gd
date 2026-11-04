extends SceneTree

# Tests that the world can still be walked now that scene bodies sit on world_solid (layer 3) and
# world_obstacle (layer 4), which both the player (mask 14) and NPCs (mask 12) collide with:
# - every Marker2D (spawn points, npc_ markers, wake points; not CreatureSpawns, whose markers are a
#   creature's centre and test_creatures.gd's) and every NPC body baked into a scene
#   stands clear of every solid body, with the real body size (Godot shape queries, mask 12)
# - from the default spawn point, a coarse grid flood fill (player-sized shape queries) reaches every
#   SceneTrigger, TravelPoint, StoryItem, Bed and baked NPC's InteractionArea, and every spawn point
#   lies in that same walkable region (arriving anywhere, the player can get everywhere)
# - the fill never leaves the scene: the walls and bounds hold
# - where the NpcSpawner places roster and generic NPCs, at every hour of a day, with the roster NPCs
#   home and away, is clear ground, out of the doorways, and walls off no door or item
# - the four new taverns line up with their exteriors: the door outside names a marker inside, the
#   way out names the exterior's from_<tavern> marker, and both ends are walkable
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_walkable.gd

const Spawner = preload("res://scripts/world/npc_spawner.gd")
const GAME_WORLD_SCRIPT = "res://scripts/world/game_world.gd"
const SCENE_TRIGGER = "res://scripts/world/scene_trigger.gd"
const PLAYER_BODY = Vector2(32, 48)   # scenes/player/player.tscn: feet at the origin, body above
const SOLID_MASK = 12                 # world_solid + world_obstacle
const WALK_MASK = 14                  # what the player bumps into: those and NPCs (layer 2)
const CELL = 8.0                      # flood fill step: a quarter of the player's width
const MAX_HALF = 2000.0               # never fill further than this from the origin

## Scene path -> location id. thornhaven_square.tscn is left out: no location loads it (game_world.tscn
## is the square) and it has no bounds of its own
const SCENES = {
	"res://scenes/exterior/ferrisford.tscn": "ferrisford",
	"res://scenes/exterior/fort_ashguard.tscn": "fort_ashguard",
	"res://scenes/exterior/greystone_mines.tscn": "greystone_mines",
	"res://scenes/exterior/iron_hollow.tscn": "iron_hollow_camp",
	"res://scenes/game_world.tscn": "thornhaven_town_square",
	"res://scenes/interiors/brackenmoor_abbey.tscn": "brackenmoor_abbey",
	"res://scenes/interiors/kingsroad_waystation.tscn": "kingsroad_waystation",
	"res://scenes/interiors/ferrisford_tavern.tscn": "ferrisford_tavern",
	"res://scenes/interiors/greystone_tavern.tscn": "greystone_tavern",
	"res://scenes/capitol/capitol_docks_tavern.tscn": "capitol_docks_tavern",
	"res://scenes/capitol/capitol_market_inn.tscn": "capitol_market_inn",
}

## The new taverns and the exterior each opens onto
const TAVERNS = {
	"ferrisford_tavern": "ferrisford",
	"greystone_tavern": "greystone_mines",
	"capitol_docks_tavern": "capitol_docks",
	"capitol_market_inn": "capitol_market",
}

## Stands in for an NPC body when the spawner places one: where it goes, and that it is in the way
class Dummy extends CharacterBody2D:
	var npc_id: String = ""
	var is_alive: bool = true
	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		var c = CollisionShape2D.new()
		c.shape = RectangleShape2D.new()
		c.shape.size = PLAYER_BODY
		c.position = Vector2(0, -PLAYER_BODY.y / 2.0)
		add_child(c)

var failures: int = 0
var registry: Node

func _init():
	await process_frame
	await process_frame
	registry = root.get_node("WorldRegistry")
	root.get_node("WorldState").set_idle_clock_rate(0.0)
	print("============================================================")
	print("🧪 WALKABLE TEST")
	print("============================================================\n")

	for path in SCENES:
		await _test_scene(path, SCENES[path])
	await _test_tavern_doors()

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

## ===== ONE SCENE =====

func _test_scene(path: String, location_id: String) -> void:
	var name = path.get_file().get_basename()
	print("\n%s" % name)
	var scene = await _mount(path)
	if scene == null:
		_check("%s: scene loads" % name, false)
		return
	var space = scene.get_world_2d().direct_space_state

	var bad: Array = []
	# CreatureSpawns markers are a creature's centre, not feet: test_creatures.gd checks those
	for m in _all(scene).filter(func(n): return n is Marker2D and n.get_parent().name != "CreatureSpawns"):
		if not _clear(space, m.global_position, PLAYER_BODY):
			bad.append("%s %s" % [m.name, m.global_position])
	_check("%s: every marker on clear ground%s" % [name, _list(bad)], bad.is_empty())

	bad = []
	for npc in _baked_npcs(scene):
		var body = _body_size(npc)
		if not _clear(space, npc.global_position, body) or _triggers(scene).any(func(t): return _player_rect(npc.global_position).intersects(_rect_of(t))):
			bad.append("%s %s" % [npc.name, npc.global_position])
	_check("%s: every NPC baked in stands clear, out of the doorways%s" % [name, _list(bad)], bad.is_empty())

	var start = _start(scene)
	var fill = _flood(space, start, _extent(scene))
	_check("%s: the walls hold (the walk never leaves the scene)" % name, not fill.leaked)
	bad = []
	for target in _targets(scene):
		if not _reaches(fill, _rect_of(target)):
			bad.append("%s %s" % [_label(target), target.global_position])
	_check("%s: every door, way out, item, bed and NPC reached from the spawn%s" % [name, _list(bad)], bad.is_empty())
	bad = []
	var points = scene.find_child("SpawnPoints", true, false)
	for m in (points.get_children() if points else []):
		if m is Marker2D and not fill.cells.has(_cell(m.global_position)):
			bad.append(str(m.name))
	_check("%s: every spawn point in the same walkable ground%s" % [name, _list(bad)], bad.is_empty())

	if location_id != "":
		bad = await _spawner_misplaced(scene, location_id, space)
		_check("%s: NPCs placed by the spawner, every hour of a day, stand clear and wall nothing off%s" % [name, _list(bad)], bad.is_empty())
	await _unmount(scene)

## ===== TAVERN DOORS =====

func _test_tavern_doors() -> void:
	print("\nTavern doors")
	for id in TAVERNS:
		var exterior: String = TAVERNS[id]
		# which marker each end names, read before mounting (one scene in the physics space at a time)
		var way_out = _door_spawns(registry.get_location_scene(id), exterior)
		var way_in = _door_spawns(registry.get_location_scene(exterior), id)
		_check("%s: one way out to %s" % [id, exterior], way_out.size() == 1)
		_check("%s: one door in %s" % [id, exterior], way_in.size() == 1)
		if way_out.size() != 1 or way_in.size() != 1:
			continue

		var outside = await _mount(registry.get_location_scene(exterior))
		var space = outside.get_world_2d().direct_space_state
		var door = _triggers(outside).filter(func(t): return str(t.target_location) == id)[0]
		var fill = _flood(space, _start(outside), _extent(outside))
		_check("%s: the door in %s is reached from its spawn" % [id, exterior], _reaches(fill, _rect_of(door)))
		var back = _marker(outside, way_out[0])
		_check("%s: leaving lands on %s's %s, clear and walkable" % [id, exterior, way_out[0]],
			back != null and _clear(space, back.global_position, PLAYER_BODY) and fill.cells.has(_cell(back.global_position)))
		_check("%s: ...not standing in the door (no bounce back in)" % id, back != null and not _player_rect(back.global_position).intersects(_rect_of(door)))
		await _unmount(outside)

		var inside = await _mount(registry.get_location_scene(id))
		space = inside.get_world_2d().direct_space_state
		var exit = _triggers(inside).filter(func(t): return str(t.target_location) == exterior)[0]
		var arrive = _marker(inside, way_in[0])
		_check("%s: entering lands on the %s marker inside, clear" % [id, way_in[0]], arrive != null and _clear(space, arrive.global_position, PLAYER_BODY))
		if arrive != null:
			_check("%s: ...from where the way out is reached" % id, _reaches(_flood(space, arrive.global_position, _extent(inside)), _rect_of(exit)))
			_check("%s: ...not standing in it (no bounce straight out)" % id, not _player_rect(arrive.global_position).intersects(_rect_of(exit)))
		await _unmount(inside)

## The target_spawn_point of every SceneTrigger in a scene that leads to target
func _door_spawns(path: String, target: String) -> Array:
	var scene = load(path).instantiate()
	var out = _triggers(scene).filter(func(t): return str(t.target_location) == target).map(func(t): return str(t.target_spawn_point))
	scene.free()
	return out

## ===== NPC SPAWNER =====

## Every spot the spawner gives a roster or generic NPC present here, hour by hour, that is not clear
## or stands in a doorway, and every door or item those NPCs wall off (the player's mask has the npc
## layer, so people standing in a gap close it)
func _spawner_misplaced(scene: Node, location_id: String, space: PhysicsDirectSpaceState2D) -> Array:
	var bad: Array = []
	var dyn = root.get_node("DynamicNPCRegistry")
	var manager = dyn.generics if "generics" in dyn else null
	var seen: Dictionary = {}
	# with the roster NPCs who live here present, and with them all away: generics take other spots
	for roster_here in [true, false]:
		bad.append_array(await _spawner_day(scene, location_id, space, manager, roster_here, seen))
	if manager:
		manager.test_now = -1
	return bad

func _spawner_day(scene: Node, location_id: String, space: PhysicsDirectSpaceState2D, manager, roster_here: bool, seen: Dictionary) -> Array:
	var bad: Array = []
	var spawner = Spawner.new()
	spawner.initialize_spawned = false
	spawner.instancer = func(key: String, _scene_path: String) -> Node:
		if not key.begins_with("gen_") and not roster_here:
			return null
		var d = Dummy.new()
		d.npc_id = key if key.begins_with("gen_") else registry.get_npc_id(key)
		return d
	root.add_child(spawner)
	var doors = _triggers(scene).map(func(t): return _rect_of(t))
	var targets = _targets(scene)
	var extent = _extent(scene)
	var open_fill = _flood(space, _start(scene), extent)
	for hour in 24:
		if manager:
			manager.test_now = hour * 60
		# a fresh placement each hour, as on arriving: the spawner's own NPCs are cleared first
		_free_dummies(scene)
		spawner.reconcile(location_id, scene)
		await physics_frame
		var placed: Array = []
		for n in scene.get_children():
			if not (n is Dummy):
				continue
			placed.append(n.position)
			if seen.has(n.position):
				continue
			var in_door = doors.any(func(r): return _player_rect(n.global_position).intersects(r))
			if in_door or not _clear(space, n.global_position, PLAYER_BODY):
				seen[n.position] = true
				bad.append("%s@%02d:00 %s%s" % [n.npc_id, hour, n.global_position, " in a doorway" if in_door else ""])
		placed.sort()
		if seen.has(placed):
			continue
		seen[placed] = true
		var fill = _flood(space, _start(scene), extent, WALK_MASK)
		for t in targets:
			if is_instance_valid(t) and _reaches(open_fill, _rect_of(t)) and not _reaches(fill, _rect_of(t)):
				bad.append("%s walled off by NPCs@%02d:00" % [_label(t), hour])
	_free_dummies(scene)
	spawner.free()
	return bad

func _free_dummies(scene: Node) -> void:
	for n in scene.get_children():   # the spawner adds its NPCs to the scene root
		if n is Dummy:
			n.remove_from_group("npcs")
			n.get_parent().remove_child(n)
			n.free()

## ===== GEOMETRY =====

## Free of solid bodies for a body of this size standing (feet) at pos
func _clear(space: PhysicsDirectSpaceState2D, pos: Vector2, size: Vector2, mask: int = SOLID_MASK) -> bool:
	var shape = RectangleShape2D.new()
	shape.size = size - Vector2(2, 2)   # touching a wall is standing beside it, not in it
	var q = PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, pos + Vector2(0, -size.y / 2.0))
	q.collision_mask = mask
	q.collide_with_bodies = true
	q.collide_with_areas = false
	return space.intersect_shape(q, 1).is_empty()

func _player_rect(pos: Vector2) -> Rect2:
	return Rect2(pos + Vector2(-PLAYER_BODY.x / 2.0, -PLAYER_BODY.y), PLAYER_BODY)

func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(roundi(pos.x / CELL), roundi(pos.y / CELL))

## Breadth-first over CELL steps from start, through every spot the player's body fits.
## {cells: {Vector2i: true}, leaked: bool (reached the edge of the extent)}
func _flood(space: PhysicsDirectSpaceState2D, start: Vector2, extent: Rect2, mask: int = SOLID_MASK) -> Dictionary:
	var cells: Dictionary = {}
	var leaked = false
	var lo = _cell(extent.position)
	var hi = _cell(extent.end)
	var first = _cell(start)
	if not _clear(space, Vector2(first) * CELL, PLAYER_BODY, mask):
		# the start is the marker itself: nudge to the nearest clear cell, as the body would slide
		for r in range(1, 6):
			for d in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
				if cells.is_empty() and _clear(space, Vector2(first + d) * CELL, PLAYER_BODY, mask):
					cells[first + d] = true
	else:
		cells[first] = true
	var todo: Array = cells.keys()
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if cells.has(n):
				continue
			if n.x < lo.x or n.y < lo.y or n.x > hi.x or n.y > hi.y:
				leaked = true
				continue
			if _clear(space, Vector2(n) * CELL, PLAYER_BODY, mask):
				cells[n] = true
				todo.append(n)
	return {"cells": cells, "leaked": leaked}

## Some walkable cell puts the player's body over this rect (Area2D overlap is what fires them)
func _reaches(fill: Dictionary, rect: Rect2) -> bool:
	var grown = rect.grow_individual(PLAYER_BODY.x / 2.0, 0.0, PLAYER_BODY.x / 2.0, PLAYER_BODY.y)
	var lo = _cell(grown.position)
	var hi = _cell(grown.end)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var c = Vector2i(x, y)
			if fill.cells.has(c) and _player_rect(Vector2(c) * CELL).intersects(rect):
				return true
	return false

## The global rect of a node's first CollisionShape2D (no rotation in these scenes)
func _rect_of(node: Node) -> Rect2:
	for c in node.get_children():
		if c is CollisionShape2D and c.shape:
			var r: Rect2 = c.shape.get_rect()
			return Rect2(c.global_position + r.position * c.global_scale, r.size * c.global_scale)
	return Rect2(node.global_position, Vector2.ONE)

## Everything the solid bodies cover, grown a little: the fill may not leave it
func _extent(scene: Node) -> Rect2:
	var out = Rect2()
	var any = false
	for n in _all(scene):
		if n is StaticBody2D and (n.collision_layer & SOLID_MASK):
			var r = _rect_of(n)
			out = r if not any else out.merge(r)
			any = true
	out = out.grow(CELL * 2)
	return out.intersection(Rect2(-MAX_HALF, -MAX_HALF, MAX_HALF * 2, MAX_HALF * 2))

## ===== SCENE QUERIES =====

func _mount(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var scene = load(path).instantiate()
	if scene.get_script() and scene.get_script().resource_path == GAME_WORLD_SCRIPT:
		scene.set_script(null)   # GameWorld would start the opening and initialize NPCs (ChromaDB)
	root.add_child(scene)
	await physics_frame
	await physics_frame
	return scene

func _unmount(scene: Node) -> void:
	scene.get_parent().remove_child(scene)
	scene.free()
	await physics_frame

func _start(scene: Node) -> Vector2:
	var m = _marker(scene, "default")
	if m:
		return m.global_position
	var player = scene.find_child("Player", true, false)
	return player.global_position if player is Node2D else Vector2.ZERO

func _marker(scene: Node, marker_name: String) -> Node2D:
	var points = scene.find_child("SpawnPoints", true, false)
	var m = points.find_child(marker_name, false, false) if points else null
	return m if m is Marker2D else null

func _triggers(scene: Node) -> Array:
	return _all(scene).filter(func(n): return n.get_script() != null and n.get_script().resource_path == SCENE_TRIGGER)

func _baked_npcs(scene: Node) -> Array:
	return _all(scene).filter(func(n): return n is CharacterBody2D and "npc_id" in n and not (n is Dummy))

## What the player must be able to walk into: doors, travel points, items, beds, NPCs to talk to
func _targets(scene: Node) -> Array:
	var out: Array = []
	for n in _all(scene):
		if n is Area2D and (n is Interactable or (n.get_script() and n.get_script().resource_path == SCENE_TRIGGER)):
			if not _under_npc(n):
				out.append(n)
	for npc in _baked_npcs(scene):
		var area = npc.get_node_or_null("InteractionArea")
		if area:
			out.append(area)
	return out

func _under_npc(n: Node) -> bool:
	var p = n.get_parent()
	while p:
		if p is CharacterBody2D:
			return true
		p = p.get_parent()
	return false

func _label(n: Node) -> String:
	return str(n.get_parent().name) + "/" + str(n.name) if n.name == "InteractionArea" else str(n.name)

func _body_size(npc: Node) -> Vector2:
	var c = npc.get_node_or_null("CollisionShape2D")
	return c.shape.size if c and c.shape is RectangleShape2D else PLAYER_BODY

func _all(node: Node) -> Array:
	var out: Array = [node]
	for c in node.get_children():
		out.append_array(_all(c))
	return out

func _list(items: Array) -> String:
	return "" if items.is_empty() else " (" + ", ".join(items) + ")"

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1
