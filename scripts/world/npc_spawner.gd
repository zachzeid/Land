extends Node
class_name NpcSpawner
# NpcSpawner - Puts world.json NPCs into whichever scene matches where they are
# After a scene loads (SceneManager), and whenever an NPC sets off or arrives:
# - roster NPCs whose location (WorldState npc_states, else world.json home) is this scene's
#   location, who are alive and not travelling, are shown, or instanced if the scene lacks them
# - roster NPCs baked into the scene who are elsewhere or on the road are hidden (baked) or
#   freed (spawned by us)
# NPCs not on the roster (dynamic NPCs) are left alone. A missing NPC scene is a warning, never an error
# Generic NPCs (docs/WORLD_SCHEMA.md §9): every instance present at this location (not travelling or
# away, inside its hours) gets a generic_npc.tscn body; bodies of instances no longer here are freed

const SPAWNED_META = "spawned_by_npc_spawner"
const GENERIC_META = "generic_id"
const SPAWN_OFFSET = Vector2(56, 0)
const GENERIC_SCENE = "res://scenes/npcs/generic_npc.tscn"
const GENERIC_RING = 150.0  # generics stand around the default spawn point, past the roster NPCs
const MIN_SPACING = 48.0    # nobody is placed closer than this to another NPC or the player's spawn
const RING_STEP = 56.0      # further rings, when the near ones are full
const RING_SLOTS = 16       # places per ring
const FLOOR_MARGIN = 40.0   # keep clear of an interior's walls
const BLOCK_BOX = Vector2(30, 46)       # an NPC's footprint, for _blocked
const BLOCK_OFFSET = Vector2(0, -24)    # its centre above the feet

## Initialize spawned NPCs the way GameWorld does: initialize(use_chromadb, false)
@export var use_chromadb: bool = true
@export var initialize_spawned: bool = true
## Tests swap the instancer: Callable(key: String, scene_path: String) -> Node (null = skip)
var instancer: Callable = Callable()
## Spawn generic instances too (tests of the roster alone can turn it off)
@export var spawn_generics: bool = true

var last_report: Dictionary = {}  # {"location", "shown", "hidden", "spawned", "freed", "skipped"}

## Make the scene match the world. scene_root: the loaded scene (only its NPCs are touched)
func reconcile(location_id: String, scene_root: Node) -> Dictionary:
	var report = {"location": location_id, "shown": [], "hidden": [], "spawned": [], "freed": [], "skipped": [],
		"generics_spawned": [], "generics_freed": [], "generics_kept": []}
	last_report = report
	var registry = get_node_or_null("/root/WorldRegistry")
	if registry == null or scene_root == null or location_id == "":
		return report
	var wanted: Dictionary = {}
	for key in registry.get_npc_keys():
		if should_be_at(key, location_id):
			wanted[key] = true

	var present: Dictionary = {}
	for npc in _scene_npcs(scene_root):
		var key = registry.get_npc_key(str(npc.npc_id))
		if key == "":
			continue  # not a roster NPC: SceneManager's own filter handles it
		if wanted.has(key) and not present.has(key):
			present[key] = true
			_show(npc, location_id)
			report.shown.append(key)
		elif npc.has_meta(SPAWNED_META):
			npc.remove_from_group("npcs")
			npc.queue_free()
			report.freed.append(key)
		else:
			_hide(npc)
			report.hidden.append(key)

	var taken: Array = _taken_spots(scene_root)
	var index = 0
	for key in wanted:
		if present.has(key):
			continue
		var npc = _instance(key, registry.get_npc_scene(key))
		if npc == null:
			report.skipped.append(key)
			continue
		npc.set_meta(SPAWNED_META, true)
		if "home_location" in npc:
			npc.home_location = registry.get_npc_home(key)
		if npc is Node2D:
			npc.position = _spawn_position(scene_root, key, index, taken)
		index += 1
		scene_root.add_child(npc)
		if not npc.is_in_group("npcs"):
			npc.add_to_group("npcs")
		_show(npc, location_id)
		report.spawned.append(key)
		if initialize_spawned and npc.has_method("initialize"):
			npc.initialize(use_chromadb, false)  # async; BaseNPC guards double initialization
	if not (report.spawned.is_empty() and report.hidden.is_empty() and report.freed.is_empty() and report.skipped.is_empty()):
		print("[NpcSpawner] %s: shown %s, spawned %s, hidden %s, freed %s, skipped %s" % [location_id, report.shown, report.spawned, report.hidden, report.freed, report.skipped])
	if spawn_generics:
		_reconcile_generics(location_id, scene_root, report, taken)
	return report

## Generic instances present here get a body; bodies of instances that left (or went home) are freed
func _reconcile_generics(location_id: String, scene_root: Node, report: Dictionary, taken: Array = []) -> void:
	var registry = get_node_or_null("/root/DynamicNPCRegistry")
	var manager = registry.generics if registry and "generics" in registry else null
	if manager == null:
		return
	var wanted: Dictionary = {}
	for id in manager.get_present_ids(location_id):
		wanted[id] = true
	var present: Dictionary = {}
	for npc in _scene_npcs(scene_root):
		if not npc.has_meta(GENERIC_META):
			continue
		var id = str(npc.get_meta(GENERIC_META))
		if wanted.has(id) and not present.has(id):
			present[id] = true
			_show(npc, location_id)
			report.generics_kept.append(id)
		else:
			npc.remove_from_group("npcs")
			npc.queue_free()
			report.generics_freed.append(id)
	if taken.is_empty():
		taken = _taken_spots(scene_root)
	var ids: Array = wanted.keys()
	ids.sort()  # the same order every visit, so the same people get the same spots
	var index = 0
	for id in ids:
		if present.has(id):
			continue
		var npc = _instance(id, GENERIC_SCENE)
		if npc == null:
			report.skipped.append(id)
			continue
		npc.set_meta(GENERIC_META, id)
		npc.set_meta(SPAWNED_META, true)
		if npc.has_method("setup"):
			npc.setup(id, manager)
		elif "npc_id" in npc:
			npc.npc_id = id
		if npc is Node2D:
			npc.position = _generic_position(scene_root, id, manager, index, taken)
		index += 1
		scene_root.add_child(npc)
		if not npc.is_in_group("npcs"):
			npc.add_to_group("npcs")
		_show(npc, location_id)
		report.generics_spawned.append(id)
		if initialize_spawned and npc.has_method("initialize"):
			npc.initialize(use_chromadb, false)  # GenericNPC uses ChromaDB only once promoted
	if not (report.generics_spawned.is_empty() and report.generics_freed.is_empty()):
		print("[NpcSpawner] %s: generics spawned %s, freed %s" % [location_id, report.generics_spawned, report.generics_freed])

## A Marker2D named npc_<id> if the scene has one, else on a ring around the default spawn point
## The angle comes from the instance seed, so a generic stands in the same place every visit when
## that place is free; otherwise the next free slot outward (never on top of anyone)
func _generic_position(scene_root: Node, id: String, manager: Node, index: int, taken: Array = []) -> Vector2:
	var marker = scene_root.find_child("npc_" + id, true, false)
	if marker is Node2D:
		var at = marker.position if marker.get_parent() == scene_root else marker.global_position
		taken.append(at)
		return at
	var inst = manager.get_instance(id)
	var start = posmod(inst.seed_value if inst else index * 37, 360)
	return _free_spot(scene_root, _default_spawn(scene_root), GENERIC_RING, start, taken)

## The default spawn point (where the player arrives), or the origin
func _default_spawn(scene_root: Node) -> Vector2:
	var spawn_points = scene_root.find_child("SpawnPoints", true, false)
	var fallback = spawn_points.find_child("default", false, false) if spawn_points else null
	return fallback.global_position if fallback is Node2D else Vector2.ZERO

## Where people already stand: every NPC body in the scene, and the player's spawn point
func _taken_spots(scene_root: Node) -> Array:
	var taken: Array = [_default_spawn(scene_root)]
	for npc in _scene_npcs(scene_root):
		if npc is Node2D and npc.visible:
			taken.append(npc.position if npc.get_parent() == scene_root else npc.global_position)
	return taken

## The first slot on rings around center (radius, then RING_STEP further out), starting at
## start_degrees, at least MIN_SPACING from every taken spot and inside the floor; it joins taken
func _free_spot(scene_root: Node, center: Vector2, radius: float, start_degrees: int, taken: Array) -> Vector2:
	var bounds = _floor_bounds(scene_root)
	var first_inside = Vector2.INF
	for ring in 6:
		for slot in RING_SLOTS:
			var angle = deg_to_rad(float(start_degrees) + slot * 360.0 / RING_SLOTS)
			var spot = center + Vector2(cos(angle), sin(angle) * 0.6) * (radius + RING_STEP * ring)
			if bounds.size != Vector2.ZERO and not bounds.has_point(spot):
				continue
			if _blocked(scene_root, spot):
				continue
			if first_inside == Vector2.INF:
				first_inside = spot
			if taken.all(func(t): return t.distance_to(spot) >= MIN_SPACING):
				taken.append(spot)
				return spot
	var fallback = first_inside if first_inside != Vector2.INF else center
	taken.append(fallback)
	return fallback  # a full room: crowded, but inside it

## Whether an NPC standing at spot (scene-root space) would be inside a wall, building or prop
## (layers 3-4, the NPC's own mask) or in a doorway or travel point (areas on layers 5-6)
func _blocked(scene_root: Node, spot: Vector2) -> bool:
	if not (scene_root is Node2D) or not scene_root.is_inside_tree():
		return false
	var space = scene_root.get_world_2d().direct_space_state
	if space == null:
		return false
	var q = PhysicsShapeQueryParameters2D.new()
	var box = RectangleShape2D.new()
	box.size = BLOCK_BOX
	q.shape = box
	q.transform = Transform2D(0.0, scene_root.to_global(spot) + BLOCK_OFFSET)
	q.collision_mask = 12
	if not space.intersect_shape(q, 1).is_empty():
		return true
	q.collision_mask = 48
	q.collide_with_bodies = false
	q.collide_with_areas = true
	return not space.intersect_shape(q, 1).is_empty()

## An interior's walkable floor (its Floor ColorRect, less FLOOR_MARGIN); zero size = no limit
func _floor_bounds(scene_root: Node) -> Rect2:
	var floor_node = scene_root.get_node_or_null("Floor")
	if not (floor_node is Control):
		return Rect2()
	var rect = Rect2(floor_node.global_position, floor_node.size)
	return rect.grow(-FLOOR_MARGIN) if rect.size.x > FLOOR_MARGIN * 2 and rect.size.y > FLOOR_MARGIN * 2 else rect

## Whether a roster NPC belongs in this location right now
func should_be_at(key: String, location_id: String) -> bool:
	var registry = get_node_or_null("/root/WorldRegistry")
	var world_state = get_node_or_null("/root/WorldState")
	if registry == null or not registry.has_npc(key):
		return false
	var npc_id = registry.get_npc_id(key)
	if world_state:
		if not world_state.is_npc_alive(npc_id) or world_state.is_npc_travelling(npc_id):
			return false
		return world_state.get_npc_location(npc_id) == location_id
	return registry.get_npc_home(key) == location_id

func _scene_npcs(scene_root: Node) -> Array:
	var result: Array = []
	for npc in get_tree().get_nodes_in_group("npcs"):
		if "npc_id" in npc and str(npc.npc_id) != "" and (npc == scene_root or scene_root.is_ancestor_of(npc)) and not npc.is_queued_for_deletion():
			result.append(npc)
	return result

func _show(npc: Node, location_id: String) -> void:
	if "current_location" in npc:
		npc.current_location = location_id
	if npc.get("is_alive") == false:
		return  # dead NPCs stay as BaseNPC left them
	if "visible" in npc:
		npc.visible = true
	npc.process_mode = Node.PROCESS_MODE_INHERIT

func _hide(npc: Node) -> void:
	if "visible" in npc:
		npc.visible = false
	npc.process_mode = Node.PROCESS_MODE_DISABLED

func _instance(key: String, scene_path: String) -> Node:
	if instancer.is_valid():
		return instancer.call(key, scene_path)
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_warning("[NpcSpawner] No scene for %s (%s); skipping" % [key, scene_path if scene_path != "" else "none in world.json"])
		return null
	var packed = load(scene_path)
	if not packed is PackedScene:
		push_warning("[NpcSpawner] %s is not a scene; skipping %s" % [scene_path, key])
		return null
	return packed.instantiate()

## A Marker2D named npc_<key> if the scene has one, else beside the default spawn point
func _spawn_position(scene_root: Node, key: String, index: int, taken: Array = []) -> Vector2:
	var marker = scene_root.find_child("npc_" + key, true, false)
	if marker is Node2D:
		var at = marker.position if marker.get_parent() == scene_root else marker.global_position
		taken.append(at)
		return at
	# A line just above the default spawn, as before, when that spot is free; else the nearest free slot
	var spot = _default_spawn(scene_root) + Vector2(0, -64) + SPAWN_OFFSET * (index + 1)
	var bounds = _floor_bounds(scene_root)
	if taken.all(func(t): return t.distance_to(spot) >= MIN_SPACING) and (bounds.size == Vector2.ZERO or bounds.has_point(spot)) \
			and not _blocked(scene_root, spot):
		taken.append(spot)
		return spot
	return _free_spot(scene_root, _default_spawn(scene_root), SPAWN_OFFSET.x * 1.5, index * 45, taken)
