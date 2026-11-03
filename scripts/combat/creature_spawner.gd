extends Node
## CreatureSpawner - puts creatures into the scene of the location they live in
## (resources/combat/creatures.json `where`; docs/PLAYER_SYSTEMS.md §3, §10.1)
## After SceneManager finishes a transition, each creature that lives here rolls its chance and count,
## seeded by the world seed, the location and the game day (the same visit on the same day sees the
## same wolves). Creatures stand at the scene's `CreatureSpawns` markers when it has them (any Marker2D
## under a node of that name), else on a ring well away from the default spawn point
## GenericManager owns one; tests call plan_for / spawn_into directly

const Creature = preload("res://scripts/combat/creature.gd")
const SCENE_DIR = "res://scenes/creatures"
const MARKERS = "CreatureSpawns"
const RING = 420.0            # pixels from the default spawn when a scene has no markers
const META = "spawned_by_creature_spawner"

@export var enabled: bool = true
var world_seed: int = 7919
var last_report: Dictionary = {}   # {"location", "spawned": [names]}

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

## Which creatures appear on this visit: [{creature, n}] (deterministic for location + day)
func plan_for(location_id: String, day: int = -1) -> Array:
	if day < 0:
		day = _day()
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
			if rng.randf() < float(entry.get("chance", 1.0)) and n > 0:
				plan.append({"creature": id, "n": n})
	return plan

## Instance the plan into a scene. Returns the creature nodes added
func spawn_into(location_id: String, scene_root: Node, day: int = -1) -> Array:
	var added: Array = []
	for node in scene_root.get_tree().get_nodes_in_group("creatures"):
		if node.has_meta(META) and scene_root.is_ancestor_of(node):
			node.queue_free()  # a scene revisited: the plan replaces what was there
	var spots = _spots(scene_root)
	var i = 0
	for row in plan_for(location_id, day):
		for k in int(row.n):
			var c = instance(str(row.creature))
			if c == null:
				continue
			c.set_meta(META, true)
			c.drop_seed = hash("%s|%s|%d" % [location_id, row.creature, k]) & 0x7fffffff
			c.position = spots[i % spots.size()] + Vector2(24 * k, 18 * k)
			scene_root.add_child(c)
			c.home = c.position
			added.append(c)
			i += 1
	last_report = {"location": location_id, "spawned": added.map(func(c): return str(c.creature_id))}
	return added

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
				spots.append(m.position)
	if spots.is_empty():
		var center = Vector2.ZERO
		var marker = scene_root.find_child("SpawnPoints", true, false)
		var default = marker.get_node_or_null("default") if marker else null
		if default is Node2D:
			center = default.position
		for a in 6:
			spots.append(center + Vector2.RIGHT.rotated(TAU * a / 6.0) * RING)
	return spots

func _day() -> int:
	var world_state = get_node_or_null("/root/WorldState")
	return int(world_state.get_game_minutes() / 1440) if world_state and world_state.has_method("get_game_minutes") else 0
