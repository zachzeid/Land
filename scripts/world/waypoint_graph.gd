class_name WaypointGraph
extends RefCounted
## WaypointGraph - Node-based graph for NPC pathing and procedural spawning
## Defines key positions (doors, intersections, spawn points) and connections between them

# Constants (duplicated to avoid circular dependencies)
const GRID_SIZE: int = 32
const GRID_CELLS: int = 32
const SAFE_MARGIN: int = 64
const WORLD_HALF: int = 512

## Helper: Convert grid to pixel coordinates
static func _grid_to_pixels(grid_x: int, grid_y: int) -> Vector2:
	return Vector2(
		(grid_x - GRID_CELLS / 2) * GRID_SIZE + GRID_SIZE / 2,
		(grid_y - GRID_CELLS / 2) * GRID_SIZE + GRID_SIZE / 2
	)

## Helper: Check if point is within safe bounds
static func _is_point_valid(pos: Vector2) -> bool:
	var min_bound = -WORLD_HALF + SAFE_MARGIN
	var max_bound = WORLD_HALF - SAFE_MARGIN
	return pos.x >= min_bound and pos.x <= max_bound and pos.y >= min_bound and pos.y <= max_bound

## Helper: Clamp position to safe bounds
static func _clamp_position(pos: Vector2) -> Vector2:
	var min_bound = -WORLD_HALF + SAFE_MARGIN
	var max_bound = WORLD_HALF - SAFE_MARGIN
	return Vector2(clamp(pos.x, min_bound, max_bound), clamp(pos.y, min_bound, max_bound))

## Waypoint types
enum WaypointType {
	DOOR,         # Building entrance/exit
	INTERSECTION, # Path crossing point
	SPAWN,        # Valid NPC spawn location
	PATROL,       # Patrol route point
	POI,          # Point of interest (bench, well, etc.)
}

## A single waypoint node in the graph
class Waypoint:
	var id: String
	var position: Vector2
	var grid_position: Vector2i
	var type: WaypointType
	var connections: Array[String]  # IDs of connected waypoints
	var metadata: Dictionary  # Additional data (building_id, etc.)

	func _init(p_id: String, p_pos: Vector2, p_type: WaypointType) -> void:
		id = p_id
		position = p_pos
		grid_position = _pixels_to_grid(p_pos)
		type = p_type
		connections = []
		metadata = {}

	static func _pixels_to_grid(pos: Vector2) -> Vector2i:
		# Use literals - inner classes can't reference outer class at parse time
		var grid_x = int(round(pos.x / 32)) + 16
		var grid_y = int(round(pos.y / 32)) + 16
		return Vector2i(clampi(grid_x, 0, 31), clampi(grid_y, 0, 31))

	func connect_to(other_id: String) -> void:
		if other_id not in connections:
			connections.append(other_id)

	func disconnect_from(other_id: String) -> void:
		connections.erase(other_id)

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"position": {"x": position.x, "y": position.y},
			"grid": {"x": grid_position.x, "y": grid_position.y},
			"type": WaypointType.keys()[type],
			"connections": connections.duplicate(),
			"metadata": metadata.duplicate(),
		}

	static func from_dict(data: Dictionary) -> Waypoint:
		var pos = Vector2(data.position.x, data.position.y)
		var type_idx = WaypointType.keys().find(data.type)
		var wp = Waypoint.new(data.id, pos, type_idx if type_idx >= 0 else WaypointType.SPAWN)
		wp.connections = Array(data.connections, TYPE_STRING, "", null)
		wp.metadata = data.get("metadata", {})
		return wp


## The waypoint graph
var waypoints: Dictionary = {}  # id -> Waypoint

## ===== GRAPH CONSTRUCTION =====

## Add a waypoint to the graph
func add_waypoint(id: String, position: Vector2, type: WaypointType, metadata: Dictionary = {}) -> Waypoint:
	# Validate position is within playable area
	if not _is_point_valid(position):
		push_warning("Waypoint '%s' at %s is outside safe playable bounds" % [id, position])
		position = _clamp_position(position)

	var wp = Waypoint.new(id, position, type)
	wp.metadata = metadata
	waypoints[id] = wp
	return wp

## Remove a waypoint and all connections to it
func remove_waypoint(id: String) -> void:
	if not waypoints.has(id):
		return

	# Remove connections from other waypoints
	for other_id in waypoints:
		waypoints[other_id].disconnect_from(id)

	waypoints.erase(id)

## Connect two waypoints bidirectionally
func connect_waypoints(id_a: String, id_b: String) -> void:
	if waypoints.has(id_a) and waypoints.has(id_b):
		waypoints[id_a].connect_to(id_b)
		waypoints[id_b].connect_to(id_a)

## Connect waypoints in a chain (A -> B -> C -> ...)
func connect_chain(ids: Array[String]) -> void:
	for i in range(ids.size() - 1):
		connect_waypoints(ids[i], ids[i + 1])

## Connect one waypoint to multiple others
func connect_to_all(center_id: String, other_ids: Array[String]) -> void:
	for other_id in other_ids:
		connect_waypoints(center_id, other_id)

## ===== GRAPH QUERIES =====

## Get a waypoint by ID
func get_waypoint(id: String) -> Waypoint:
	return waypoints.get(id)

## Get all waypoints of a specific type
func get_waypoints_by_type(type: WaypointType) -> Array[Waypoint]:
	var result: Array[Waypoint] = []
	for wp in waypoints.values():
		if wp.type == type:
			result.append(wp)
	return result

## Get all spawn points
func get_spawn_points() -> Array[Waypoint]:
	return get_waypoints_by_type(WaypointType.SPAWN)

## Get all door waypoints
func get_door_waypoints() -> Array[Waypoint]:
	return get_waypoints_by_type(WaypointType.DOOR)

## Get connected waypoints
func get_connections(id: String) -> Array[Waypoint]:
	var result: Array[Waypoint] = []
	var wp = waypoints.get(id)
	if wp:
		for conn_id in wp.connections:
			if waypoints.has(conn_id):
				result.append(waypoints[conn_id])
	return result

## Find nearest waypoint to a position
func find_nearest(position: Vector2, type_filter: WaypointType = -1) -> Waypoint:
	var nearest: Waypoint = null
	var nearest_dist: float = INF

	for wp in waypoints.values():
		if type_filter >= 0 and wp.type != type_filter:
			continue
		var dist = position.distance_squared_to(wp.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = wp

	return nearest

## Find all waypoints within a radius
func find_within_radius(position: Vector2, radius: float, type_filter: WaypointType = -1) -> Array[Waypoint]:
	var result: Array[Waypoint] = []
	var radius_sq = radius * radius

	for wp in waypoints.values():
		if type_filter >= 0 and wp.type != type_filter:
			continue
		if position.distance_squared_to(wp.position) <= radius_sq:
			result.append(wp)

	return result

## ===== PATHFINDING =====

## Find shortest path between two waypoints using A*
func find_path(from_id: String, to_id: String) -> Array[Waypoint]:
	var result: Array[Waypoint] = []

	if not waypoints.has(from_id) or not waypoints.has(to_id):
		return result

	var start = waypoints[from_id]
	var goal = waypoints[to_id]

	# A* implementation
	var open_set: Array[String] = [from_id]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {from_id: 0.0}
	var f_score: Dictionary = {from_id: start.position.distance_to(goal.position)}

	while not open_set.is_empty():
		# Find node with lowest f_score
		var current_id = open_set[0]
		var lowest_f = f_score.get(current_id, INF)
		for id in open_set:
			var f = f_score.get(id, INF)
			if f < lowest_f:
				lowest_f = f
				current_id = id

		if current_id == to_id:
			# Reconstruct path
			var path_ids: Array[String] = [current_id]
			while came_from.has(current_id):
				current_id = came_from[current_id]
				path_ids.push_front(current_id)

			for id in path_ids:
				result.append(waypoints[id])
			return result

		open_set.erase(current_id)
		var current = waypoints[current_id]

		for neighbor_id in current.connections:
			if not waypoints.has(neighbor_id):
				continue

			var neighbor = waypoints[neighbor_id]
			var tentative_g = g_score.get(current_id, INF) + current.position.distance_to(neighbor.position)

			if tentative_g < g_score.get(neighbor_id, INF):
				came_from[neighbor_id] = current_id
				g_score[neighbor_id] = tentative_g
				f_score[neighbor_id] = tentative_g + neighbor.position.distance_to(goal.position)

				if neighbor_id not in open_set:
					open_set.append(neighbor_id)

	return result  # No path found

## ===== LAYOUT GENERATION =====

## Generate waypoint graph from a grid layout
static func from_layout(layout: Dictionary) -> RefCounted:
	var script = load("res://scripts/world/waypoint_graph.gd")
	var graph = script.new()

	# Add door waypoints for buildings
	if layout.has("buildings"):
		for building_id in layout.buildings:
			var data = layout.buildings[building_id]
			var door_pos = _get_door_position(data.grid, data.footprint)

			if _is_point_valid(door_pos):
				var wp = graph.add_waypoint(
					building_id + "_door",
					door_pos,
					WaypointType.DOOR,
					{"building_id": building_id, "footprint": data.footprint}
				)

	# Add POI waypoints for interactive props
	if layout.has("props"):
		for prop_id in layout.props:
			var grid_pos = layout.props[prop_id]
			var footprint_name = prop_id.split("_")[0] if "_" in prop_id else prop_id

			# Only add waypoints for interactive props
			if footprint_name in ["well", "bench", "cart"]:
				var pos = _grid_to_pixels(grid_pos.x, grid_pos.y)
				if _is_point_valid(pos):
					graph.add_waypoint(
						prop_id + "_poi",
						pos,
						WaypointType.POI,
						{"prop_id": prop_id, "type": footprint_name}
					)

	# Generate intersection waypoints from paths
	if layout.has("paths"):
		var intersections = _find_path_intersections(layout.paths)
		for i in range(intersections.size()):
			var pos = intersections[i]
			if _is_point_valid(pos):
				graph.add_waypoint(
					"intersection_%d" % i,
					pos,
					WaypointType.INTERSECTION
				)

	# Generate spawn points along paths
	var spawn_points = _generate_spawn_points(layout, graph)
	for i in range(spawn_points.size()):
		var pos = spawn_points[i]
		graph.add_waypoint(
			"spawn_%d" % i,
			pos,
			WaypointType.SPAWN
		)

	# Auto-connect nearby waypoints
	graph._auto_connect()

	return graph

## Calculate door position from grid and footprint
static func _get_door_position(grid_pos: Vector2i, footprint_name: String) -> Vector2:
	var door_offsets = {
		"house_small": Vector2(2.5, 4),
		"house_medium": Vector2(2.5, 5),
		"shop": Vector2(3, 5),
		"tavern": Vector2(3.5, 6),
		"blacksmith": Vector2(2.5, 5),
		"gate": Vector2(2, 4),
	}

	var offset = door_offsets.get(footprint_name, Vector2(2, 4))
	var door_grid_x = grid_pos.x + offset.x
	var door_grid_y = grid_pos.y + offset.y

	return Vector2(
		(door_grid_x - GRID_CELLS / 2) * GRID_SIZE,
		(door_grid_y - GRID_CELLS / 2) * GRID_SIZE
	)

## Find intersections in path definitions
static func _find_path_intersections(paths: Dictionary) -> Array[Vector2]:
	var intersections: Array[Vector2] = []

	# Convert paths to rects
	var rects: Array[Rect2] = []
	for path_id in paths:
		var path = paths[path_id]
		var start = path.start
		var end = path.end
		var rect = Rect2(
			_grid_to_pixels(start.x, start.y) - Vector2(GRID_SIZE/2, GRID_SIZE/2),
			Vector2((end.x - start.x + 1) * GRID_SIZE, (end.y - start.y + 1) * GRID_SIZE)
		)
		rects.append(rect)

	# Find intersections between rects
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				var intersection = rects[i].intersection(rects[j])
				intersections.append(intersection.get_center())

	return intersections

## Generate spawn points along walkable paths
static func _generate_spawn_points(layout: Dictionary, graph: WaypointGraph) -> Array[Vector2]:
	var spawn_points: Array[Vector2] = []

	if not layout.has("paths"):
		return spawn_points

	# Place spawn points at regular intervals along paths
	var spawn_spacing = GRID_SIZE * 4  # Every 4 grid cells

	for path_id in layout.paths:
		var path = layout.paths[path_id]
		var start_pixel = _grid_to_pixels(path.start.x, path.start.y)
		var end_pixel = _grid_to_pixels(path.end.x, path.end.y)

		var direction = (end_pixel - start_pixel).normalized()
		var length = start_pixel.distance_to(end_pixel)
		var num_points = int(length / spawn_spacing)

		for i in range(num_points):
			var pos = start_pixel + direction * (spawn_spacing * (i + 0.5))

			# Check not too close to existing waypoints
			var too_close = false
			for wp in graph.waypoints.values():
				if pos.distance_to(wp.position) < GRID_SIZE * 2:
					too_close = true
					break

			if not too_close and _is_point_valid(pos):
				spawn_points.append(pos)

	return spawn_points

## Auto-connect waypoints within reasonable distance
func _auto_connect() -> void:
	var connection_radius = GRID_SIZE * 6  # Connect within 6 grid cells

	var wp_list = waypoints.values()
	for i in range(wp_list.size()):
		for j in range(i + 1, wp_list.size()):
			var wp_a = wp_list[i]
			var wp_b = wp_list[j]

			var dist = wp_a.position.distance_to(wp_b.position)
			if dist <= connection_radius:
				# Connect door to nearest intersections/spawns
				# Connect intersections to each other
				# Connect spawns to nearest intersection
				var should_connect = false

				if wp_a.type == WaypointType.DOOR or wp_b.type == WaypointType.DOOR:
					should_connect = true
				elif wp_a.type == WaypointType.INTERSECTION and wp_b.type == WaypointType.INTERSECTION:
					should_connect = true
				elif wp_a.type == WaypointType.SPAWN or wp_b.type == WaypointType.SPAWN:
					should_connect = dist <= GRID_SIZE * 3

				if should_connect:
					connect_waypoints(wp_a.id, wp_b.id)

## ===== SERIALIZATION =====

## Convert graph to dictionary for saving
func to_dict() -> Dictionary:
	var result = {}
	for id in waypoints:
		result[id] = waypoints[id].to_dict()
	return result

## Load graph from dictionary
static func from_dict(data: Dictionary) -> RefCounted:
	var script = load("res://scripts/world/waypoint_graph.gd")
	var graph = script.new()
	for id in data:
		var wp = Waypoint.from_dict(data[id])
		graph.waypoints[id] = wp
	return graph

## ===== DEBUG =====

## Print graph structure
func print_graph() -> void:
	print("=== WAYPOINT GRAPH ===")
	print("Total waypoints: %d" % waypoints.size())

	for type in WaypointType.values():
		var count = get_waypoints_by_type(type).size()
		if count > 0:
			print("  %s: %d" % [WaypointType.keys()[type], count])

	print("\nConnections:")
	for wp in waypoints.values():
		if wp.connections.size() > 0:
			print("  %s -> %s" % [wp.id, ", ".join(wp.connections)])
