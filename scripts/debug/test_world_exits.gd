extends SceneTree

# Exit check across every world.json location: each built location's scene loads, has
# SpawnPoints/default, every SceneTrigger names a built location whose scene has the target spawn
# point, every TravelPoint names its own location, and every travel-point location has a TravelPoint
# and a from_travel spawn. Walking exits should follow a world.json route (reported, not failed,
# for the few doors that predate the route table).
# Scenes are instanced but never added to the tree, so no _ready runs and nothing is generated
# Run: godot --headless --path . -s res://scripts/debug/test_world_exits.gd

const SCENE_TRIGGER = "res://scripts/world/scene_trigger.gd"
const TRAVEL_POINT = "res://scripts/world/travel_point.gd"

var failures: int = 0
var notes: Array = []

func _init():
	await process_frame
	var registry = root.get_node("WorldRegistry")
	var scene_manager = root.get_node("SceneManager")
	print("============================================================")
	print("🧪 WORLD EXITS TEST")
	print("============================================================\n")

	var ids: Array = registry.get_location_ids()
	_check("world.json lists 28 locations (26 places and two puzzle rooms)", ids.size() == 28)
	var scenes: Dictionary = {}   # id -> instanced root
	for id in ids:
		if not registry.is_built(id):
			_check("%s: not built (skipped)" % id, true)
			continue
		var path = registry.get_location_scene(id)
		var ok = path != "" and ResourceLoader.exists(path)
		_check("%s: scene %s exists" % [id, path], ok)
		_check("%s: has LocationData in resources/locations" % id, scene_manager.get_location(id) != null and scene_manager.get_location(id).scene_path == path)
		if ok:
			var packed = load(path)
			var inst = packed.instantiate() if packed is PackedScene else null
			_check("%s: scene instances" % id, inst != null)
			if inst:
				scenes[id] = inst

	for id in scenes:
		var scene: Node = scenes[id]
		_check("%s: has SpawnPoints/default" % id, _spawn(scene, "default", true) != null)
		var travel_points: Array = []
		for node in _all(scene):
			var script = node.get_script()
			if script == null:
				continue
			if script.resource_path == SCENE_TRIGGER:
				var target = str(node.get("target_location"))
				var spawn = str(node.get("target_spawn_point"))
				var target_ok = registry.has_location(target) and registry.is_built(target) and scenes.has(target)
				_check("%s -> %s (%s): target is a built location" % [id, target, node.name], target_ok)
				if target_ok:
					var marker = _spawn(scenes[target], spawn, true)
					var loose = _spawn(scenes[target], spawn, false) if marker == null else marker
					_check("%s -> %s: spawn point '%s' resolves" % [id, target, spawn], loose != null)
					if marker == null and loose != null:
						notes.append("%s -> %s: '%s' is a Marker2D outside SpawnPoints (SceneManager's fallback finds it)" % [id, target, spawn])
					if registry.get_route_minutes(id, target) < 0:
						notes.append("%s -> %s: walking exit with no world.json route (no walk time)" % [id, target])
			elif script.resource_path == TRAVEL_POINT:
				travel_points.append(node)
				_check("%s: TravelPoint %s has from_location = %s" % [id, node.name, id], str(node.get("from_location")) == id)
		if registry.is_travel_point(id):
			_check("%s: travel point location has a TravelPoint" % id, not travel_points.is_empty())
			_check("%s: has a from_travel spawn" % id, _spawn(scene, "from_travel", true) != null)
		elif not travel_points.is_empty():
			_check("%s: TravelPoint only where world.json says travel_point" % id, false)

	for scene in scenes.values():
		scene.free()
	if not notes.is_empty():
		print("\nNotes:")
		for note in notes:
			print("  - " + note)
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

## SpawnPoints/<name> (strict), else any Marker2D of that name (SceneManager's fallback)
func _spawn(scene: Node, spawn_name: String, strict: bool) -> Node:
	var points = scene.find_child("SpawnPoints", true, false)
	if points:
		var marker = points.find_child(spawn_name, false, false)
		if marker is Marker2D:
			return marker
	if strict:
		return null
	var any = scene.find_child(spawn_name, true, false)
	return any if any is Marker2D else null

func _all(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_all(child))
	return out

func _check(label: String, passed: bool):
	if not passed:
		print("  ✗ " + label)
		failures += 1
	else:
		print("  ✓ " + label)
