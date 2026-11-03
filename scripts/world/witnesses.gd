extends RefCounted
## Witnesses - who saw a physical deed (docs/PLAYER_SYSTEMS.md §1.2, §8)
## A deed done in a scene is seen by the NPC bodies with line of sight to it: within range, with no
## wall between (collision layer 3 "world_solid"; props on "world_obstacle" do not hide a standing
## person). Range shrinks at night and with the doer's stealth; lit lamps and fires light the spot
## (WorldPhysics.sight_factor), and a watcher standing in their light sees less of the dark beyond
## (WorldPhysics.glare_factor: lamps reveal and blind). Physical deeds pass the result to
## PlayerEvents.record as opts.witnesses; spoken deeds keep their conversation partner

const CharacterTypes = preload("res://scripts/npcs/character_types.gd")
const SIGHT_MASK = 4             # 2d_physics layer 3, world_solid (walls, buildings)
const DAY_RANGE = 520.0          # pixels
const NIGHT_FACTOR = 0.5         # 21:00-05:00, by the game clock, when the world has no physics
const STEALTH_FACTOR = 0.5       # stealth 100 halves the range

## NPC ids whose bodies see `at`. opts: range, stealth (0-100), exclude (ids), hour (default: the game clock)
static func in_sight(scene_root: Node, at: Vector2, opts: Dictionary = {}) -> Array:
	if scene_root == null or not scene_root.is_inside_tree():
		return []
	var reach = sight_range(opts, at, scene_root)
	var exclude: Array = opts.get("exclude", [])
	var space = scene_root.get_viewport().get_world_2d().direct_space_state if scene_root.get_viewport() else null
	var physics = _physics() if not opts.has("hour") else null
	var light_opts = {"scene_root": scene_root, "outdoors": not _indoors(scene_root)}
	var glare = physics != null and physics.has_method("glare_factor")
	var seen: Array = []
	for npc in scene_root.get_tree().get_nodes_in_group("npcs"):
		if not (npc is Node2D) or not npc.is_visible_in_tree() or not scene_root.is_ancestor_of(npc):
			continue
		var id = str(npc.get("npc_id")) if npc.get("npc_id") != null else ""
		if id == "" or id in exclude or (npc.get("is_alive") == false):
			continue
		var npc_reach = reach * (float(physics.glare_factor(npc.global_position, at, light_opts)) if glare else 1.0)
		if npc.has_method("character_kind"):
			npc_reach *= CharacterTypes.sight_factor(npc.character_kind(), light_opts.outdoors)  # woodwise eyes under the sky
		if npc.global_position.distance_to(at) > npc_reach:
			continue
		if space and _blocked(space, npc.global_position, at):
			continue
		if not id in seen:
			seen.append(id)
	return seen

## Darkness: WorldPhysics.sight_factor at the spot (the hour, weather, lamps, shadows, indoors) when
## the world has physics; a flat night factor otherwise, or when opts.hour pins the hour (tests)
static func sight_range(opts: Dictionary = {}, at = null, scene_root: Node = null) -> float:
	var reach = float(opts.get("range", DAY_RANGE))
	var physics = _physics()
	if physics and physics.has_method("sight_factor") and at is Vector2 and not opts.has("hour"):
		reach *= float(physics.sight_factor(at, {"scene_root": scene_root, "outdoors": not _indoors(scene_root)}))
	else:
		var hour = int(opts.get("hour", _hour()))
		if hour >= 21 or hour < 5:
			reach *= NIGHT_FACTOR
	reach *= 1.0 - STEALTH_FACTOR * clampf(float(opts.get("stealth", 0)), 0.0, 100.0) / 100.0
	return reach

## An interior (a level with a Floor) is dim by day and has no sky
static func _indoors(scene_root: Node) -> bool:
	return scene_root != null and scene_root.get_node_or_null("Floor") != null

static func _blocked(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	var query = PhysicsRayQueryParameters2D.create(from, to, SIGHT_MASK)
	query.collide_with_areas = false
	return not space.intersect_ray(query).is_empty()

static func _physics() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("WorldPhysics") if tree else null

static func _hour() -> int:
	var tree = Engine.get_main_loop() as SceneTree
	var world_state = tree.root.get_node_or_null("WorldState") if tree else null
	return world_state.get_hour() if world_state and world_state.has_method("get_hour") else 12
