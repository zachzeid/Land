extends Node
## CreatureSpawner - puts creatures into the scene of the location they live in
## (resources/combat/creatures.json `where`; docs/PLAYER_SYSTEMS.md §3, §10.1)
## After SceneManager finishes a transition, each creature that lives here rolls its chance and count,
## seeded by the world seed, the location and the game day (the same visit on the same day sees the
## same wolves). Creatures stand at the scene's `CreatureSpawns` markers when it has them (any Marker2D
## under a node of that name), else on a ring well away from the default spawn point
## A creature killed here stays dead until it regrows: each death is a cull {creature, at} in game
## minutes, and plan_for leaves one fewer of that creature while `regrow_days` (creatures.json) have
## not passed, so a cleared Darkwood is still clear on re-entry and after a reload (save() rides in
## GenericManager's save, inside WorldState's "generics" block)
## No creature spawns indoors (docs/WORLD_SCHEMA.md "Buildings"): nothing is placed in a building
## location (Creature.is_building), and a spot inside a building's body (a world_solid StaticBody2D)
## or a doorway (Creature.door_zones) is refused, with the refusals in last_report.refused
## GenericManager owns one; tests call plan_for / spawn_into directly

const Creature = preload("res://scripts/combat/creature.gd")
const SCENE_DIR = "res://scenes/creatures"
const MARKERS = "CreatureSpawns"
const RING = 420.0            # pixels from the default spawn when a scene has no markers
const META = "spawned_by_creature_spawner"

@export var enabled: bool = true
var world_seed: int = 7919
var last_report: Dictionary = {}   # {"location", "spawned": [ids], "refused": [{spot, why}]}
var culls: Dictionary = {}         # location -> [{creature, at}] (at: game minute of the death)

func _ready() -> void:
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_signal("scene_transition_completed"):
		scene_manager.scene_transition_completed.connect(_on_scene_ready)

func _on_scene_ready(location_id: String) -> void:
	if not enabled or not is_inside_tree():
		return
	var scene_root = get_tree().current_scene
	if scene_root:
		spawn_into(location_id, scene_root)

## Which creatures appear on this visit: [{creature, n}] (deterministic for location + day), less
## the ones killed here that have not regrown by `now` (game minutes; default the clock)
func plan_for(location_id: String, day: int = -1, now: int = -1) -> Array:
	if day < 0:
		day = _day()
	if now < 0:
		now = _now()
	var rng = RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|%d" % [world_seed, location_id, day]) & 0x7fffffff
	var plan: Array = []
	var defs = Creature.definitions()
	var ids = defs.keys()
	ids.sort()
	for id in ids:
		for entry in defs[id].get("where", []):
			if str(entry.get("location", "")) != location_id:
				continue
			var count: Array = entry.get("count", [1, 1])
			var n = rng.randi_range(int(count[0]), int(count[1]))
			var roll = rng.randf()  # rolled before the cull so the dice stay the same for every visit
			n -= culled(location_id, id, now)
			if roll < float(entry.get("chance", 1.0)) and n > 0:
				plan.append({"creature": id, "n": n})
	return plan

## How many of this creature killed here have not yet regrown by `now`
func culled(location_id: String, creature_id: String, now: int = -1) -> int:
	if now < 0:
		now = _now()
	var regrow = regrow_minutes(creature_id)
	var n = 0
	for c in culls.get(location_id, []):
		if str(c.creature) == creature_id and int(c.at) <= now and now < int(c.at) + regrow:
			n += 1
	return n

## creatures.json `regrow_days` in game minutes (a day when unset)
static func regrow_minutes(creature_id: String) -> int:
	return int(round(float(Creature.definition(creature_id).get("regrow_days", 1.0)) * 1440.0))

## A creature of this location died (anyone's kill): it stays gone until it regrows
func note_cull(location_id: String, creature_id: String, at: int = -1) -> void:
	if location_id == "" or creature_id == "":
		return
	if not culls.has(location_id):
		culls[location_id] = []
	culls[location_id].append({"creature": creature_id, "at": at if at >= 0 else _now()})

## Forget culls that have regrown by `now`
func prune(now: int = -1) -> void:
	if now < 0:
		now = _now()
	for loc in culls.keys():
		culls[loc] = culls[loc].filter(func(c): return now < int(c.at) + regrow_minutes(str(c.creature)))
		if culls[loc].is_empty():
			culls.erase(loc)

## Instance the plan into a scene. Returns the creature nodes added
func spawn_into(location_id: String, scene_root: Node, day: int = -1) -> Array:
	var added: Array = []
	for node in scene_root.get_tree().get_nodes_in_group("creatures"):
		if node.has_meta(META) and scene_root.is_ancestor_of(node):
			node.queue_free()  # a scene revisited: the plan replaces what was there
	var refused: Array = []
	if Creature.is_building(location_id):
		refused.append({"spot": null, "why": "building location"})
		last_report = {"location": location_id, "spawned": [], "refused": refused}
		return added  # a built place is never theirs, whatever creatures.json says
	var blocked = Blocked.new(scene_root)
	var spots = _spots(scene_root).filter(func(p):
		var why = blocked.why(p)
		if why != "":
			refused.append({"spot": p, "why": why})
			push_warning("[CreatureSpawner] %s: spot %s refused (%s)" % [location_id, p, why])
		return why == "")
	var i = 0
	for row in plan_for(location_id, day) if not spots.is_empty() else []:
		for k in int(row.n):
			var c = instance(str(row.creature))
			if c == null:
				continue
			c.set_meta(META, true)
			c.drop_seed = hash("%s|%s|%d" % [location_id, row.creature, k]) & 0x7fffffff
			var spot: Vector2 = spots[i % spots.size()]
			var fanned = spot + Vector2(24 * k, 18 * k)
			c.position = fanned if blocked.why(fanned) == "" else spot  # a pack never fans into a wall or door
			c.zone_root = scene_root
			scene_root.add_child(c)
			c.home = c.position
			if c.has_signal("died"):
				c.died.connect(func(_info): note_cull(location_id, str(row.creature)))
			added.append(c)
			i += 1
	last_report = {"location": location_id, "spawned": added.map(func(c): return str(c.creature_id)), "refused": refused}
	return added

## Why a spot (scene_root's space) is no place for a creature: "building" (inside a world_solid body:
## a building, wall or river), "doorway" (Creature.door_zones), or "" when it is open ground
class Blocked:
	var root: Node
	var to_root: Transform2D
	var solids: Array = []    # Rect2s in global space (root space when out of the tree)
	var doors: Array = []

	func _init(scene_root: Node) -> void:
		root = scene_root
		to_root = Creature.xform(scene_root, scene_root)
		doors = Creature.door_zones(scene_root)
		for body in scene_root.find_children("*", "StaticBody2D", true, false):
			# world_solid.gd sets its layer in _ready, so a scene not yet in the tree is read by its script
			var script = body.get_script()
			if body.collision_layer & SOLID_MASK or (script and script.resource_path.ends_with("world_solid.gd")):
				for cs in body.get_children():
					if cs is CollisionShape2D and cs.shape and not cs.disabled:
						solids.append(Creature.xform(cs, scene_root) * cs.shape.get_rect())

	## spot: scene_root-local, as markers are read
	func why(spot: Vector2) -> String:
		var p = to_root * spot
		for r in solids:
			if r.has_point(p):
				return "building"
		for z in doors:
			if z.rect.has_point(p):
				return "doorway"
		return ""

## A creature body: its scene under scenes/creatures/<id>.tscn, else a bare body
static func instance(id: String) -> Node:
	if Creature.definition(id).is_empty():
		return null
	var path = "%s/%s.tscn" % [SCENE_DIR, id]
	var c: Node = load(path).instantiate() if ResourceLoader.exists(path) else Creature.new()
	c.setup(id)
	return c

func _spots(scene_root: Node) -> Array:
	var spots: Array = []
	var holder = scene_root.find_child(MARKERS, true, false)
	if holder:
		for m in holder.get_children():
			if m is Marker2D:
				spots.append(holder.position + m.position)
	if spots.is_empty():
		var center = Vector2.ZERO
		var marker = scene_root.find_child("SpawnPoints", true, false)
		var default = marker.get_node_or_null("default") if marker else null
		if default is Node2D:
			center = default.position
		for a in 6:
			spots.append(_inside_walls(scene_root, center, center + Vector2.RIGHT.rotated(TAU * a / 6.0) * RING))
	return spots

const SOLID_MASK = 4      # 2d_physics layer 3, world_solid (walls, buildings)
const WALL_MARGIN = 48.0

## A ring spot past a wall comes back inside it (the first windowed run had a wolf beyond the forest
## path's east wall, where no blade could reach it). Scene markers (CreatureSpawns) are used as placed
func _inside_walls(scene_root: Node, center: Vector2, spot: Vector2) -> Vector2:
	if scene_root == null or not scene_root.is_inside_tree() or scene_root.get_viewport() == null:
		return spot
	var space = scene_root.get_viewport().get_world_2d().direct_space_state
	var origin = scene_root.global_position
	var query = PhysicsRayQueryParameters2D.create(origin + center, origin + spot, SOLID_MASK)
	query.collide_with_areas = false
	var hit = space.intersect_ray(query)
	if hit.is_empty():
		return spot
	var dir = (spot - center).normalized()
	var back = (hit.position - origin) - dir * WALL_MARGIN
	return back if (back - center).dot(dir) > 0.0 else center + dir * WALL_MARGIN

func _day() -> int:
	return int(_now() / 1440)

func _now() -> int:
	var world_state = get_node_or_null("/root/WorldState") if is_inside_tree() else null
	return int(world_state.get_game_minutes()) if world_state and world_state.has_method("get_game_minutes") else 0

# =============================================================================
# SAVE / LOAD (GenericManager carries it inside WorldState's "generics" block)
# =============================================================================

func save() -> Dictionary:
	prune()
	return {"version": 1, "culls": culls.duplicate(true)}

func load_from_dict(data: Dictionary) -> void:
	culls.clear()
	var saved = data.get("culls", {})
	if not saved is Dictionary:
		return
	for loc in saved:
		var rows: Array = []
		for c in saved[loc] if saved[loc] is Array else []:
			if c is Dictionary and str(c.get("creature", "")) != "":
				rows.append({"creature": str(c.creature), "at": int(c.get("at", 0))})
		if not rows.is_empty():
			culls[str(loc)] = rows
