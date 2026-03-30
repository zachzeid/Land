extends Node
class_name ScheduleManager
## ScheduleManager - Moves NPCs to scheduled locations when time period changes
##
## Listens to GameClock.time_period_changed and instructs NPCs to relocate.
## Each NPC's schedule is defined in their NPCPersonality resource.
## NPCs without schedules stay at their home_location.

## Reference to the game clock (set in _ready via autoload)
var game_clock: Node = null

## Cached NPC references {npc_id: BaseNPC node}
var _tracked_npcs: Dictionary = {}

## Location positions for navigation targets
## Maps location_id → world position (Vector2)
## Populated from SceneManager or manually configured
var location_positions: Dictionary = {}

func _ready():
	# Connect to GameClock (must be registered as autoload)
	game_clock = get_node_or_null("/root/GameClock")
	if game_clock:
		game_clock.time_period_changed.connect(_on_time_period_changed)
		print("[ScheduleManager] Connected to GameClock")
	else:
		push_warning("[ScheduleManager] GameClock not found — schedules disabled")

	# Discover NPCs after scene is ready
	await get_tree().process_frame
	_discover_npcs()
	_populate_location_positions()

func _discover_npcs():
	var npc_nodes = get_tree().get_nodes_in_group("npcs")
	for npc in npc_nodes:
		if npc.has_method("move_to_position") and npc.get("npc_id"):
			_tracked_npcs[npc.npc_id] = npc
	print("[ScheduleManager] Tracking %d NPCs" % _tracked_npcs.size())

func _populate_location_positions():
	# Try to get positions from spawn points in the current scene
	var spawn_points = get_tree().get_nodes_in_group("spawn_points")
	for sp in spawn_points:
		if sp is Marker2D:
			location_positions[sp.name] = sp.global_position

	# Also check SceneManager for location data
	var scene_mgr = get_node_or_null("/root/SceneManager")
	if scene_mgr and scene_mgr.has_method("get_location"):
		# SceneManager may provide spawn point positions
		pass

	# Fallback: define key positions manually for Thornhaven
	# These are approximate positions from game_world.tscn layout
	if location_positions.is_empty():
		location_positions = {
			"thornhaven_town_square": Vector2(0, 0),
			"thornhaven_gregor_shop": Vector2(-240, -304),
			"thornhaven_tavern": Vector2(240, -304),
			"thornhaven_blacksmith": Vector2(-336, 16),
			"thornhaven_well": Vector2(0, 16),
			"thornhaven_gate": Vector2(0, 432),
			"thornhaven_market": Vector2(0, -100),
			# Interior locations — NPCs teleport there via scene transition
			"gregor_shop_interior": Vector2(-240, -280),
			"tavern_interior": Vector2(240, -280),
			"blacksmith_interior": Vector2(-336, 40),
		}
	print("[ScheduleManager] %d location positions registered" % location_positions.size())

## Called when time period changes
func _on_time_period_changed(new_period: String, _old_period: String):
	print("[ScheduleManager] Time changed to '%s' — updating NPC locations" % new_period)

	for npc_id in _tracked_npcs:
		var npc = _tracked_npcs[npc_id]
		if not is_instance_valid(npc) or not npc.is_alive:
			continue
		if npc.is_in_conversation:
			continue  # Don't interrupt conversations

		var target_location = _get_scheduled_location(npc, new_period)
		if target_location == "":
			continue  # No schedule entry for this period

		# Check if NPC needs to move
		if npc.current_location == target_location:
			continue  # Already there

		# Get world position for target location
		var target_pos = location_positions.get(target_location, Vector2.ZERO)
		if target_pos == Vector2.ZERO and target_location != "":
			push_warning("[ScheduleManager] No position for location: %s" % target_location)
			continue

		# Command NPC to move
		npc.current_location = target_location
		npc.move_to_position(target_pos)
		print("[ScheduleManager] %s moving to %s" % [npc.npc_name, target_location])

## Get where an NPC should be at a given time period
func _get_scheduled_location(npc: Node, period: String) -> String:
	# Check if NPC has a personality resource with schedule
	if npc.personality_resource and npc.personality_resource.get("daily_schedule"):
		var schedule = npc.personality_resource.daily_schedule
		for entry in schedule:
			if entry.get("time_period", "") == period:
				return entry.get("location", "")

	# Fallback: NPCs go home during night, wander during day
	if period == "night":
		return npc.home_location
	return ""

## Register a new NPC for tracking (called when NPCs are created dynamically)
func register_npc(npc: Node):
	if npc.get("npc_id"):
		_tracked_npcs[npc.npc_id] = npc

## Add or update a location position
func set_location_position(location_id: String, position: Vector2):
	location_positions[location_id] = position
