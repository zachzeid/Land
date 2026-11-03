extends Node
## SceneManager - Handles scene transitions and location management
## Autoload singleton for global access

# Preload BaseInterior for static validation method
const BaseInteriorClass = preload("res://scripts/world/base_interior.gd")
const NpcSpawnerScript = preload("res://scripts/world/npc_spawner.gd")
const OpeningSequenceScript = preload("res://scripts/world/opening_sequence.gd")

## Signals
signal scene_transition_started(from_location: String, to_location: String)
signal scene_transition_completed(location: String)
signal scene_loaded(location: Resource)

## Currently loaded location (LocationData resource)
var current_location: Resource = null
var previous_location: Resource = null
var current_spawn_point: String = "default"

## Registry of all locations (location_id -> LocationData)
var locations: Dictionary = {}

## Player reference (persists across scenes)
var player_scene: PackedScene = null
var player_instance: Node = null

## Fade overlay for transitions
var fade_overlay: ColorRect = null
var fade_tween: Tween = null

## Default fade duration
const DEFAULT_FADE_DURATION = 0.3

## Puts world.json NPCs into the scene that matches where they are
var npc_spawner: Node = null
## The Tithe Night's opening (the drawing in the chapel); GameWorld asks it to play on a new game
var opening: Node = null

func _ready():
	# Load player scene
	player_scene = load("res://scenes/player/player.tscn")

	# Create fade overlay
	_create_fade_overlay()

	# Load all location resources
	_load_locations()

	npc_spawner = NpcSpawnerScript.new()
	npc_spawner.name = "NpcSpawner"
	add_child(npc_spawner)
	opening = OpeningSequenceScript.new()
	opening.name = "OpeningSequence"
	add_child(opening)
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		# NPCs leaving or arriving change who belongs in the current scene
		bus.npc_travel_started.connect(func(_id, _from, _to, _arrive): refresh_npcs())
		bus.npc_arrived.connect(func(_id, _location): refresh_npcs())
	call_deferred("_adopt_initial_scene")

	print("[SceneManager] Initialized with %d locations" % locations.size())

func _create_fade_overlay():
	# Create a CanvasLayer for the fade effect (above everything)
	var canvas = CanvasLayer.new()
	canvas.name = "FadeCanvas"
	canvas.layer = 100  # Above all other UI
	add_child(canvas)

	fade_overlay = ColorRect.new()
	fade_overlay.name = "FadeOverlay"
	fade_overlay.color = Color.BLACK
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_overlay.modulate.a = 0.0

	# Cover entire screen
	fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(fade_overlay)

func _load_locations():
	# Scan for LocationData resources
	var dir = DirAccess.open("res://resources/locations")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				var path = "res://resources/locations/" + file_name
				var location = load(path)
				if location and location.location_id != "":
					locations[location.location_id] = location
					print("[SceneManager] Loaded location: %s" % location.location_id)
			file_name = dir.get_next()
		dir.list_dir_end()

## Register a location at runtime
func register_location(location: Resource):
	if location.location_id != "":
		locations[location.location_id] = location

## Get location data by ID
func get_location(location_id: String) -> Resource:
	return locations.get(location_id, null)

## Transition to a new location
## walk_time = false: no route minutes pass (the opening places the player without walking)
func transition_to(location_id: String, spawn_point: String = "default", fade_duration: float = DEFAULT_FADE_DURATION, walk_time: bool = true):
	var target_location = get_location(location_id)
	if target_location == null:
		push_error("[SceneManager] Unknown location: %s" % location_id)
		return

	var from_id = current_location.location_id if current_location else "none"
	scene_transition_started.emit(from_id, location_id)

	# Store spawn point for use after scene loads
	current_spawn_point = spawn_point
	previous_location = current_location

	# Walking to a neighbour along a world.json route takes that route's minutes of game time
	# (long journeys go through TravelMap, which advances the clock itself)
	if walk_time:
		_advance_time_for_walk(from_id, location_id)

	# Fade out
	await _fade_out(fade_duration)

	# Load new scene
	_load_scene(target_location)

	# Wait a frame for scene to initialize
	await get_tree().process_frame

	# Preload assets before showing the scene
	await _preload_scene_assets()

	# Position player at spawn point
	_position_player_at_spawn(spawn_point)

	# Roster NPCs: spawn / show / hide by where they are; others by their own location
	_reconcile_npcs(location_id)

	# Update current location
	current_location = target_location

	# Fade in
	await _fade_in(fade_duration)

	scene_transition_completed.emit(location_id)
	scene_loaded.emit(target_location)

## Preload AI-generated assets before scene becomes visible
func _preload_scene_assets():
	if not AssetPreloader:
		return

	var scene_root = get_tree().current_scene
	if not scene_root:
		return

	# Check if any assets need generation
	if AssetPreloader.are_scene_assets_ready(scene_root):
		print("[SceneManager] All assets cached, skipping preload")
		return

	print("[SceneManager] Preloading scene assets...")

	# Start preloading and wait for completion
	AssetPreloader.preload_scene_assets(scene_root)

	# Wait for preload to complete
	if AssetPreloader.is_loading:
		await AssetPreloader.preload_completed

	print("[SceneManager] Asset preload complete")

func _fade_out(duration: float):
	if fade_tween:
		fade_tween.kill()

	fade_tween = create_tween()
	fade_tween.tween_property(fade_overlay, "modulate:a", 1.0, duration)
	await fade_tween.finished

func _fade_in(duration: float):
	if fade_tween:
		fade_tween.kill()

	fade_tween = create_tween()
	fade_tween.tween_property(fade_overlay, "modulate:a", 0.0, duration)
	await fade_tween.finished

func _load_scene(location: Resource):
	var new_scene = location.get_scene()
	if new_scene == null:
		push_error("[SceneManager] Failed to load scene for %s" % location.location_id)
		return

	# Get current scene root
	var root = get_tree().root
	var current_scene = get_tree().current_scene

	# Remove old player instance if it exists in the scene
	if player_instance and is_instance_valid(player_instance):
		player_instance.get_parent().remove_child(player_instance)

	# Remove current scene
	if current_scene:
		current_scene.queue_free()

	# Instance new scene
	var new_scene_instance = new_scene.instantiate()
	root.add_child(new_scene_instance)
	get_tree().current_scene = new_scene_instance

	# Validate interior scenes
	_validate_interior_scene(new_scene_instance, location)

	# Add player to new scene if not already there
	_ensure_player_in_scene(new_scene_instance)

## Validate interior scene structure and size
func _validate_interior_scene(scene_root: Node, location: Resource):
	# Check if this is an interior scene (has Floor node)
	var floor_node = scene_root.get_node_or_null("Floor")
	if not floor_node:
		return  # Not an interior, skip validation

	# Use BaseInterior static validation if available
	var validation = BaseInteriorClass.validate_interior_scene(scene_root)

	if validation.valid:
		print("[SceneManager] Interior validated: %s (%dx%d, type: %s)" % [
			location.location_id, validation.size, validation.size, validation.type
		])
	else:
		push_warning("[SceneManager] Interior validation failed for %s:" % location.location_id)
		for error in validation.errors:
			push_warning("  - %s" % error)
		print("[SceneManager] Interior %s has issues: %s" % [location.location_id, validation.errors])

func _ensure_player_in_scene(scene_root: Node):
	# Check if scene already has a player
	var existing_player = scene_root.find_child("Player", true, false)
	if existing_player:
		player_instance = existing_player
		return

	# Create new player instance if needed
	if player_instance == null or not is_instance_valid(player_instance):
		player_instance = player_scene.instantiate()

	# Add to scene
	scene_root.add_child(player_instance)

func _position_player_at_spawn(spawn_point_name: String):
	if player_instance == null:
		return

	# Find spawn point marker in scene
	var spawn_points = get_tree().current_scene.find_child("SpawnPoints", true, false)
	if spawn_points:
		var spawn_marker = spawn_points.find_child(spawn_point_name, false, false)
		if spawn_marker and spawn_marker is Marker2D:
			player_instance.global_position = spawn_marker.global_position
			print("[SceneManager] Player spawned at %s: %s" % [spawn_point_name, spawn_marker.global_position])
			return

	# Fallback: find any Marker2D with matching name
	var marker = get_tree().current_scene.find_child(spawn_point_name, true, false)
	if marker and marker is Marker2D:
		player_instance.global_position = marker.global_position
		return

	# Last resort: use default position
	push_warning("[SceneManager] Spawn point '%s' not found, using origin" % spawn_point_name)
	player_instance.global_position = Vector2.ZERO

## Advance the clock by the direct route's minutes (no route: no time, e.g. a debug jump)
func _advance_time_for_walk(from_id: String, to_id: String) -> int:
	var registry = get_node_or_null("/root/WorldRegistry")
	var world_state = get_node_or_null("/root/WorldState")
	if registry == null or world_state == null or from_id == to_id:
		return 0
	var minutes = registry.get_route_minutes(from_id, to_id)
	if minutes > 0:
		world_state.advance_time(minutes, "walk:%s->%s" % [from_id, to_id])
	return maxi(minutes, 0)

## Re-check who belongs in the current scene (NPCs set off or arrived)
func refresh_npcs() -> void:
	var location_id = get_current_location_id()
	if location_id != "" and is_inside_tree() and get_tree().current_scene:
		_reconcile_npcs(location_id)

func _reconcile_npcs(location_id: String) -> void:
	var scene_root = get_tree().current_scene
	if npc_spawner and scene_root:
		npc_spawner.reconcile(location_id, scene_root)
	_filter_npcs_for_location(location_id)

## The main scene was loaded by the engine, not by transition_to: learn which location it is
func _adopt_initial_scene() -> void:
	var scene_root = get_tree().current_scene
	if current_location != null or scene_root == null or scene_root.scene_file_path == "":
		return
	for id in locations:
		if locations[id].scene_path == scene_root.scene_file_path:
			current_location = locations[id]
			break
	if current_location == null:
		var registry = get_node_or_null("/root/WorldRegistry")
		var id = registry.get_location_for_scene(scene_root.scene_file_path) if registry else ""
		if id != "" and locations.has(id):
			current_location = locations[id]
	if current_location:
		print("[SceneManager] Initial scene is %s" % current_location.location_id)
		_reconcile_npcs(current_location.location_id)

## NPCs off the world.json roster (dynamic NPCs) show only where their own location says
func _filter_npcs_for_location(location_id: String):
	var registry = get_node_or_null("/root/WorldRegistry")
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if registry and "npc_id" in npc and registry.get_npc_key(str(npc.npc_id)) != "":
			continue  # roster NPCs belong to the spawner
		if "current_location" in npc:
			var npc_location = npc.current_location if npc.current_location != "" else npc.get("home_location")
			if npc_location == location_id:
				npc.visible = true
				npc.process_mode = Node.PROCESS_MODE_INHERIT
			else:
				npc.visible = false
				npc.process_mode = Node.PROCESS_MODE_DISABLED

## Get all NPCs that belong to a specific location
func get_npcs_at_location(location_id: String) -> Array:
	var result = []
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if "home_location" in npc and npc.home_location == location_id:
			result.append(npc)
	return result

## Get current location ID
func get_current_location_id() -> String:
	if current_location:
		return current_location.location_id
	return ""
