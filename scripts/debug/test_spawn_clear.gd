extends SceneTree

# Tests that the NpcSpawner never puts someone without a marker inside a building or a doorway:
# the line above the default spawn and the rings round it skip spots a wall (layer 3), a prop
# (layer 4) or a door/travel area (layers 5-6) covers
# Fakes only: a hand-built scene, no API calls, no save
# Run: godot --headless --path . -s res://scripts/debug/test_spawn_clear.gd

const Spawner = preload("res://scripts/world/npc_spawner.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	await _test_spawn_skips_bodies()
	print("")
	if failures == 0:
		print("✅ ALL TESTS PASSED")
	else:
		print("❌ %d CHECK(S) FAILED" % failures)
	quit(0 if failures == 0 else 1)

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ✓ " + what)
	else:
		print("  ✗ " + what)
		failures += 1

func _box(parent: Node, at: Vector2, size: Vector2, area: bool, layer: int) -> void:
	var body: CollisionObject2D = Area2D.new() if area else StaticBody2D.new()
	body.collision_layer = layer
	body.position = at
	var shape = CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = size
	body.add_child(shape)
	parent.add_child(body)

func _test_spawn_skips_bodies() -> void:
	print("\n== spots inside a wall, a prop or a doorway are skipped")
	var scene = Node2D.new()
	scene.name = "SpawnClearScene"
	root.add_child(scene)
	var points = Node2D.new()
	points.name = "SpawnPoints"
	scene.add_child(points)
	var default = Marker2D.new()
	default.name = "default"
	points.add_child(default)
	# a house over the first line spots above the spawn, a cart beside it, a door to the right
	_box(scene, Vector2(80, -88), Vector2(200, 80), false, 4)
	_box(scene, Vector2(-120, -40), Vector2(60, 60), false, 8)
	_box(scene, Vector2(150, 0), Vector2(60, 80), true, 32)
	await physics_frame
	await physics_frame
	var spawner = Spawner.new()
	root.add_child(spawner)
	var taken: Array = [Vector2.ZERO]
	var spots: Array = []
	for i in 6:
		spots.append(spawner._spawn_position(scene, "nobody_%d" % i, i, taken))
	var blocked = spots.filter(func(p): return spawner._blocked(scene, p))
	_check(spawner._blocked(scene, Vector2(56, -64)), "the house covers the old first spot (the check sees bodies)")
	_check(spawner._blocked(scene, Vector2(150, 24)), "the doorway area is seen")
	_check(blocked.is_empty(), "no one placed in a body or doorway (%s)" % [blocked])
	_check(spots.all(func(p): return spots.count(p) == 1), "six different spots")
	spawner.queue_free()
	scene.queue_free()
