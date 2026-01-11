class_name GridLayout
extends RefCounted
## GridLayout - Utility for grid-based world layout
## Converts between grid coordinates and pixel positions
## All placements are validated against PlayableArea bounds

# Preload dependencies to ensure they're available at parse time
const _PlayableArea = preload("res://scripts/world/playable_area.gd")
const _WaypointGraph = preload("res://scripts/world/waypoint_graph.gd")

# Core constants (must be defined here, not referenced from other classes at parse time)
const GRID_SIZE: int = 32  # pixels per grid cell
const WORLD_SIZE: int = 1024  # total world size in pixels
const GRID_CELLS: int = 32  # WORLD_SIZE / GRID_SIZE

# Margins for bounds validation
const EDGE_MARGIN: int = 32  # 1 grid cell buffer
const SAFE_MARGIN: int = 64  # 2 grid cells recommended
const PIXELLAB_SCALE: int = 2  # Generate at half size, scale 2x

# Validation mode - when true, reject out-of-bounds placements
static var validate_bounds: bool = true

## Convert grid coordinates (0-31, 0-31) to pixel position
## Grid (0,0) is top-left, (16,16) is center/origin
static func grid_to_pixels(grid_x: int, grid_y: int) -> Vector2:
	var pixel_x = (grid_x - GRID_CELLS / 2) * GRID_SIZE + GRID_SIZE / 2
	var pixel_y = (grid_y - GRID_CELLS / 2) * GRID_SIZE + GRID_SIZE / 2
	return Vector2(pixel_x, pixel_y)

## Convert pixel position to nearest grid cell
static func pixels_to_grid(pos: Vector2) -> Vector2i:
	var grid_x = int(round(pos.x / GRID_SIZE)) + GRID_CELLS / 2
	var grid_y = int(round(pos.y / GRID_SIZE)) + GRID_CELLS / 2
	return Vector2i(clamp(grid_x, 0, GRID_CELLS - 1), clamp(grid_y, 0, GRID_CELLS - 1))

## Snap a pixel position to the nearest grid point
static func snap_to_grid(pos: Vector2) -> Vector2:
	var grid = pixels_to_grid(pos)
	return grid_to_pixels(grid.x, grid.y)

## Get pixel position for a building with given grid footprint
## Footprint is width x height in grid cells
## Position is the top-left grid cell of the building
static func building_position(grid_x: int, grid_y: int, footprint_w: int, footprint_h: int) -> Vector2:
	# Center the building within its footprint
	var center_x = grid_x + footprint_w / 2.0
	var center_y = grid_y + footprint_h / 2.0
	return Vector2(
		(center_x - GRID_CELLS / 2) * GRID_SIZE,
		(center_y - GRID_CELLS / 2) * GRID_SIZE
	)

## Standard asset footprints (in grid cells)
const FOOTPRINTS = {
	# Props
	"barrel": Vector2i(2, 2),
	"crate": Vector2i(2, 2),
	"bench": Vector2i(2, 2),
	"lamppost": Vector2i(2, 2),
	"well": Vector2i(3, 3),
	"cart": Vector2i(3, 3),

	# Trees
	"tree": Vector2i(4, 4),

	# Buildings
	"house_small": Vector2i(5, 4),
	"house_medium": Vector2i(5, 5),
	"shop": Vector2i(6, 5),
	"tavern": Vector2i(7, 6),
	"blacksmith": Vector2i(5, 5),
	"gate": Vector2i(4, 4),
}

## Door offsets relative to building footprint (in grid cells from top-left)
## Format: Vector2(x_offset, y_offset) where door is placed
const DOOR_OFFSETS = {
	"house_small": Vector2(2.5, 4),    # Bottom center
	"house_medium": Vector2(2.5, 5),   # Bottom center
	"shop": Vector2(3, 5),             # Bottom center
	"tavern": Vector2(3.5, 6),         # Bottom center
	"blacksmith": Vector2(2.5, 5),     # Bottom center
	"gate": Vector2(2, 4),             # Bottom center (passthrough)
}

## Get recommended pixel size for an asset type (display size in-game)
static func get_asset_size(asset_type: String) -> Vector2:
	var footprint = FOOTPRINTS.get(asset_type, Vector2i(2, 2))
	return Vector2(footprint.x * GRID_SIZE, footprint.y * GRID_SIZE)


## ===== PIXELLAB ASSET SIZING =====
## PixelLab generates at smaller sizes for crisp pixel art when scaled up

## Get the size to request from PixelLab for an asset type
## Returns Vector2i suitable for PixelLab's width/height parameters
static func get_pixellab_size(asset_type: String) -> Vector2i:
	var footprint = FOOTPRINTS.get(asset_type, Vector2i(2, 2))
	return _get_pixellab_size_for_footprint(footprint)

## Get PixelLab size from a custom footprint
static func get_pixellab_size_for_footprint(footprint: Vector2i) -> Vector2i:
	return _get_pixellab_size_for_footprint(footprint)

## Internal helper for PixelLab sizing
static func _get_pixellab_size_for_footprint(footprint: Vector2i) -> Vector2i:
	var display_size = Vector2(footprint.x * GRID_SIZE, footprint.y * GRID_SIZE)
	var gen_size = display_size / PIXELLAB_SCALE
	var width = clampi(int(gen_size.x), 16, 128)
	var height = clampi(int(gen_size.y), 16, 128)
	return Vector2i((width / 2) * 2, (height / 2) * 2)  # Round to even

## Get the scale to apply to PixelLab-generated assets
static func get_pixellab_scale() -> Vector2:
	return Vector2(PIXELLAB_SCALE, PIXELLAB_SCALE)

## Get a complete PixelLab generation spec for an asset type
## Returns a dictionary with all parameters needed for PixelLab generation
static func get_pixellab_spec(asset_type: String, description: String = "") -> Dictionary:
	var footprint = FOOTPRINTS.get(asset_type, Vector2i(2, 2))
	var gen_size = _get_pixellab_size_for_footprint(footprint)
	var display_size = get_asset_size(asset_type)

	return {
		"asset_type": asset_type,
		"description": description,
		"footprint": footprint,
		"pixellab_width": gen_size.x,
		"pixellab_height": gen_size.y,
		"display_width": int(display_size.x),
		"display_height": int(display_size.y),
		"scale": PIXELLAB_SCALE,
	}


## ===== VALIDATION =====

## Check if a grid placement is valid within safe bounds
static func _is_grid_placement_valid(grid_x: int, grid_y: int, footprint: Vector2i) -> bool:
	var margin_cells = SAFE_MARGIN / GRID_SIZE
	var min_cell = margin_cells
	var max_cell = GRID_CELLS - margin_cells

	if grid_x < min_cell or grid_y < min_cell:
		return false
	if grid_x + footprint.x > max_cell or grid_y + footprint.y > max_cell:
		return false
	return true

## Validate a grid placement before adding to layout
static func validate_placement(grid_x: int, grid_y: int, footprint: Vector2i) -> Dictionary:
	var result = {
		"valid": true,
		"issues": [],
		"clamped_position": Vector2i(grid_x, grid_y),
	}

	if not validate_bounds:
		return result

	# Check grid bounds
	if not _is_grid_placement_valid(grid_x, grid_y, footprint):
		result.valid = false
		result.issues.append("Placement at (%d, %d) with footprint %s exceeds safe bounds" % [
			grid_x, grid_y, footprint
		])

		# Calculate clamped position
		var margin_cells = SAFE_MARGIN / GRID_SIZE
		var clamped_x = clampi(grid_x, margin_cells, GRID_CELLS - margin_cells - footprint.x)
		var clamped_y = clampi(grid_y, margin_cells, GRID_CELLS - margin_cells - footprint.y)
		result.clamped_position = Vector2i(clamped_x, clamped_y)

	return result

## Validate an entire layout and return report
static func validate_layout(layout: Dictionary) -> Dictionary:
	var issues: Array[String] = []

	# Validate buildings
	if layout.has("buildings"):
		for id in layout.buildings:
			var data = layout.buildings[id]
			var grid_pos = data.grid
			var footprint = FOOTPRINTS.get(data.get("footprint", "house_small"), Vector2i(5, 4))
			if not _is_grid_placement_valid(grid_pos.x, grid_pos.y, footprint):
				issues.append("Building '%s' at grid (%d, %d) exceeds safe bounds" % [id, grid_pos.x, grid_pos.y])

	# Validate trees
	if layout.has("trees"):
		var tree_footprint = Vector2i(4, 4)
		for i in range(layout.trees.size()):
			var grid_pos = layout.trees[i]
			if not _is_grid_placement_valid(grid_pos.x, grid_pos.y, tree_footprint):
				issues.append("Tree %d at grid (%d, %d) exceeds safe bounds" % [i, grid_pos.x, grid_pos.y])

	# Validate props
	if layout.has("props"):
		for id in layout.props:
			var grid_pos = layout.props[id]
			var footprint_name = id.split("_")[0] if "_" in id else id
			var footprint = FOOTPRINTS.get(footprint_name, Vector2i(2, 2))
			if not _is_grid_placement_valid(grid_pos.x, grid_pos.y, footprint):
				issues.append("Prop '%s' at grid (%d, %d) exceeds safe bounds" % [id, grid_pos.x, grid_pos.y])

	return {
		"valid": issues.is_empty(),
		"issue_count": issues.size(),
		"issues": issues,
	}


## ===== THORNHAVEN LAYOUT =====
## All positions in grid coordinates (0-31)
## Buildings store top-left corner of their footprint

const THORNHAVEN_LAYOUT = {
	"buildings": {
		# Buildings positioned around central square with clear paths to roads
		"gregor_shop": {"grid": Vector2i(5, 7), "footprint": "shop"},       # West side
		"tavern": {"grid": Vector2i(20, 7), "footprint": "tavern"},         # East side
		"blacksmith": {"grid": Vector2i(5, 19), "footprint": "blacksmith"}, # SW
		"house1": {"grid": Vector2i(22, 19), "footprint": "house_small"},   # SE
		"village_gate": {"grid": Vector2i(14, 25), "footprint": "gate"},    # South entrance
	},
	"trees": [
		# Reduced to corner trees only
		Vector2i(2, 3),   # NW
		Vector2i(27, 3),  # NE
		Vector2i(2, 26),  # SW
		Vector2i(27, 26), # SE
	],
	"props": {
		# Minimal central props
		"well": Vector2i(15, 14),   # Center of square
	},
	"paths": {
		# Main N-S road (wide)
		"main_vertical": {"start": Vector2i(14, 4), "end": Vector2i(17, 28)},
		# Main E-W road (wide)
		"main_horizontal": {"start": Vector2i(4, 14), "end": Vector2i(27, 17)},
		# Town square (cobblestone)
		"square": {"start": Vector2i(11, 11), "end": Vector2i(20, 20)},
	}
}

## Generate pixel positions from layout
static func get_thornhaven_positions() -> Dictionary:
	var result = {
		"buildings": {},
		"trees": [],
		"props": {},
	}

	# Buildings
	for id in THORNHAVEN_LAYOUT.buildings:
		var data = THORNHAVEN_LAYOUT.buildings[id]
		var footprint = FOOTPRINTS.get(data.footprint, Vector2i(4, 4))
		result.buildings[id] = building_position(data.grid.x, data.grid.y, footprint.x, footprint.y)

	# Trees
	for grid_pos in THORNHAVEN_LAYOUT.trees:
		var footprint = FOOTPRINTS.tree
		result.trees.append(building_position(grid_pos.x, grid_pos.y, footprint.x, footprint.y))

	# Props
	for id in THORNHAVEN_LAYOUT.props:
		var grid_pos = THORNHAVEN_LAYOUT.props[id]
		var footprint_name = id.split("_")[0] if "_" in id else id
		var footprint = FOOTPRINTS.get(footprint_name, Vector2i(2, 2))
		result.props[id] = building_position(grid_pos.x, grid_pos.y, footprint.x, footprint.y)

	return result

## Print layout as debug info
static func print_layout():
	var positions = get_thornhaven_positions()
	print("=== THORNHAVEN GRID LAYOUT ===")
	print("Buildings:")
	for id in positions.buildings:
		print("  %s: %s" % [id, positions.buildings[id]])
	print("Trees:")
	for i in range(positions.trees.size()):
		print("  tree_%d: %s" % [i + 1, positions.trees[i]])
	print("Props:")
	for id in positions.props:
		print("  %s: %s" % [id, positions.props[id]])


## ===== COLLISION & NAVIGATION GENERATION =====

## Get door position in pixel coordinates for a building
static func get_door_position(building_id: String, layout: Dictionary) -> Vector2:
	if not layout.buildings.has(building_id):
		return Vector2.ZERO

	var data = layout.buildings[building_id]
	var grid_pos = data.grid
	var footprint_name = data.footprint
	var door_offset = DOOR_OFFSETS.get(footprint_name, Vector2(2, 4))

	# Calculate door position in grid coordinates, then convert to pixels
	var door_grid_x = grid_pos.x + door_offset.x
	var door_grid_y = grid_pos.y + door_offset.y

	return Vector2(
		(door_grid_x - GRID_CELLS / 2) * GRID_SIZE,
		(door_grid_y - GRID_CELLS / 2) * GRID_SIZE
	)

## Generate collision data for all elements in a layout
## Returns dictionary with buildings, props, trees arrays ready for scene application
static func generate_collision_data(layout: Dictionary) -> Dictionary:
	var result = {
		"buildings": [],
		"obstacles": [],
		"entry_points": [],
	}

	# Buildings - use full footprint for collision
	for id in layout.buildings:
		var data = layout.buildings[id]
		var grid_pos = data.grid
		var footprint = FOOTPRINTS.get(data.footprint, Vector2i(4, 4))
		var center_pos = building_position(grid_pos.x, grid_pos.y, footprint.x, footprint.y)
		var size = Vector2(footprint.x * GRID_SIZE, footprint.y * GRID_SIZE)

		# Shrink collision slightly (90%) so roofs don't block movement
		var collision_size = size * 0.9

		result.buildings.append({
			"id": id,
			"name": id.to_pascal_case(),
			"position": center_pos,
			"size": collision_size,
			"footprint": data.footprint,
		})

		# Add door/entry point
		var door_pos = get_door_position(id, layout)
		result.entry_points.append({
			"id": id + "_entry",
			"name": id.to_pascal_case() + "Entry",
			"position": door_pos,
			"target_scene": data.get("interior_scene", ""),
		})

	# Trees
	var tree_idx = 0
	for grid_pos in layout.get("trees", []):
		var footprint = FOOTPRINTS.tree
		var center_pos = building_position(grid_pos.x, grid_pos.y, footprint.x, footprint.y)
		# Trees have smaller collision than visual (trunk only)
		var collision_size = Vector2(GRID_SIZE * 1.5, GRID_SIZE * 1.5)

		result.obstacles.append({
			"id": "tree_%d" % tree_idx,
			"name": "Tree%d" % tree_idx,
			"position": center_pos,
			"size": collision_size,
			"type": "tree",
		})
		tree_idx += 1

	# Props
	for id in layout.get("props", {}):
		var grid_pos = layout.props[id]
		var footprint_name = id.split("_")[0] if "_" in id else id
		var footprint = FOOTPRINTS.get(footprint_name, Vector2i(2, 2))
		var center_pos = building_position(grid_pos.x, grid_pos.y, footprint.x, footprint.y)
		var size = Vector2(footprint.x * GRID_SIZE, footprint.y * GRID_SIZE)

		result.obstacles.append({
			"id": id,
			"name": id.to_pascal_case(),
			"position": center_pos,
			"size": size * 0.8,  # Slightly smaller collision
			"type": footprint_name,
		})

	return result

## Generate navigation polygon from path definitions
## Returns PackedVector2Array of vertices forming the walkable area
static func generate_navigation_polygon(layout: Dictionary) -> PackedVector2Array:
	var vertices = PackedVector2Array()

	if not layout.has("paths"):
		return vertices

	# For now, use the largest path region (square) as the main walkable area
	# More sophisticated merging could be added later
	var paths = layout.paths

	# Collect all path rectangles
	var rects: Array[Rect2] = []
	for path_id in paths:
		var path = paths[path_id]
		var start_grid = path.start
		var end_grid = path.end

		# Convert grid to pixels
		var start_pixel = Vector2(
			(start_grid.x - GRID_CELLS / 2) * GRID_SIZE,
			(start_grid.y - GRID_CELLS / 2) * GRID_SIZE
		)
		var end_pixel = Vector2(
			(end_grid.x - GRID_CELLS / 2 + 1) * GRID_SIZE,
			(end_grid.y - GRID_CELLS / 2 + 1) * GRID_SIZE
		)

		rects.append(Rect2(start_pixel, end_pixel - start_pixel))

	if rects.is_empty():
		return vertices

	# Merge overlapping rectangles into a single polygon
	# Start with the largest rect and expand
	var merged = _merge_rectangles_to_polygon(rects)
	return merged

## Merge rectangles into a simplified polygon (convex hull approach)
static func _merge_rectangles_to_polygon(rects: Array[Rect2]) -> PackedVector2Array:
	# Collect all corner points
	var all_points: Array[Vector2] = []
	for rect in rects:
		all_points.append(rect.position)
		all_points.append(Vector2(rect.position.x + rect.size.x, rect.position.y))
		all_points.append(rect.position + rect.size)
		all_points.append(Vector2(rect.position.x, rect.position.y + rect.size.y))

	# Find bounding box of all rects (simplified approach)
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)
	for rect in rects:
		min_pos.x = min(min_pos.x, rect.position.x)
		min_pos.y = min(min_pos.y, rect.position.y)
		max_pos.x = max(max_pos.x, rect.position.x + rect.size.x)
		max_pos.y = max(max_pos.y, rect.position.y + rect.size.y)

	# Return simple rectangle for now (can be enhanced for complex shapes)
	var vertices = PackedVector2Array()
	vertices.append(min_pos)
	vertices.append(Vector2(max_pos.x, min_pos.y))
	vertices.append(max_pos)
	vertices.append(Vector2(min_pos.x, max_pos.y))

	return vertices

## Apply layout to a scene - creates collision bodies, entry points, and navigation
## Returns a WaypointGraph if generate_waypoints is true (as Variant to avoid class load order issues)
static func apply_layout_to_scene(scene_root: Node2D, layout: Dictionary, generate_waypoints: bool = true) -> Variant:
	print("[GridLayout] Applying layout to scene...")

	# Validate layout first
	if validate_bounds:
		var validation = validate_layout(layout)
		if not validation.valid:
			push_warning("[GridLayout] Layout has %d validation issues:" % validation.issue_count)
			for issue in validation.issues:
				push_warning("  - %s" % issue)

	var collision_data = generate_collision_data(layout)

	# Create or get Collisions node
	var collisions = scene_root.get_node_or_null("Collisions")
	if not collisions:
		collisions = Node2D.new()
		collisions.name = "Collisions"
		scene_root.add_child(collisions)
		collisions.owner = scene_root

	# Create or get EntryPoints node
	var entry_points = scene_root.get_node_or_null("EntryPoints")
	if not entry_points:
		entry_points = Node2D.new()
		entry_points.name = "EntryPoints"
		scene_root.add_child(entry_points)
		entry_points.owner = scene_root

	# Apply building collisions (layer 3 = world_solid)
	for building in collision_data.buildings:
		_create_or_update_collision(
			collisions, scene_root,
			building.name + "Collision",
			building.position,
			building.size,
			1 << 2  # Layer 3: world_solid
		)
		print("[GridLayout]   Building: %s at %s" % [building.name, building.position])

	# Apply obstacle collisions (layer 4 = world_obstacle)
	for obstacle in collision_data.obstacles:
		_create_or_update_collision(
			collisions, scene_root,
			obstacle.name + "Collision",
			obstacle.position,
			obstacle.size,
			1 << 3  # Layer 4: world_obstacle
		)
		print("[GridLayout]   Obstacle: %s at %s" % [obstacle.name, obstacle.position])

	# Apply entry points
	for entry in collision_data.entry_points:
		_create_or_update_entry_point(
			entry_points, scene_root,
			entry.name,
			entry.position,
			entry.get("target_scene", "")
		)
		print("[GridLayout]   Entry: %s at %s" % [entry.name, entry.position])

	# Apply navigation polygon
	_apply_navigation_from_layout(scene_root, layout)

	# Generate waypoint graph for NPC pathing
	var waypoint_graph = null
	if generate_waypoints:
		waypoint_graph = _WaypointGraph.from_layout(layout)
		print("[GridLayout] Generated waypoint graph with %d waypoints" % waypoint_graph.waypoints.size())

	print("[GridLayout] Layout applied successfully!")
	return waypoint_graph

## Create or update a collision body
static func _create_or_update_collision(parent: Node2D, owner: Node, collision_name: String, pos: Vector2, size: Vector2, layer: int) -> void:
	var existing = parent.get_node_or_null(collision_name)
	if existing:
		existing.position = pos
		var shape = existing.get_node_or_null("CollisionShape2D")
		if shape and shape.shape is RectangleShape2D:
			shape.shape.size = size
	else:
		var body = StaticBody2D.new()
		body.name = collision_name
		body.position = pos
		body.collision_layer = layer
		body.collision_mask = (1 << 0) | (1 << 1)  # Player + NPC
		parent.add_child(body)
		body.owner = owner

		var shape = CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var rect = RectangleShape2D.new()
		rect.size = size
		shape.shape = rect
		body.add_child(shape)
		shape.owner = owner

## Create or update an entry point (Area2D for door detection)
static func _create_or_update_entry_point(parent: Node2D, owner: Node, entry_name: String, pos: Vector2, target_scene: String) -> void:
	var existing = parent.get_node_or_null(entry_name)
	if existing:
		existing.position = pos
	else:
		var area = Area2D.new()
		area.name = entry_name
		area.position = pos
		area.collision_layer = 1 << 4  # Layer 5: interactable
		area.collision_mask = 1 << 0   # Detects player
		parent.add_child(area)
		area.owner = owner

		var shape = CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var rect = RectangleShape2D.new()
		rect.size = Vector2(64, 32)  # Standard door size
		shape.shape = rect
		area.add_child(shape)
		shape.owner = owner

		# Store target scene as metadata
		if target_scene != "":
			area.set_meta("target_scene", target_scene)

## Apply navigation polygon from layout paths
static func _apply_navigation_from_layout(scene_root: Node2D, layout: Dictionary) -> void:
	var nav_region = scene_root.get_node_or_null("NavigationRegion2D")
	if not nav_region:
		nav_region = NavigationRegion2D.new()
		nav_region.name = "NavigationRegion2D"
		scene_root.add_child(nav_region)
		nav_region.owner = scene_root

	var vertices = generate_navigation_polygon(layout)
	if vertices.is_empty():
		print("[GridLayout] No walkable regions defined in layout")
		return

	# Create navigation polygon with vertices and polygon indices directly
	# This avoids the deprecated make_polygons_from_outlines()
	var nav_poly = NavigationPolygon.new()
	nav_poly.vertices = vertices

	# Create polygon indices (simple quad: 0,1,2,3 for 4 vertices)
	# For a rectangle, we need two triangles
	if vertices.size() == 4:
		nav_poly.add_polygon(PackedInt32Array([0, 1, 2]))
		nav_poly.add_polygon(PackedInt32Array([0, 2, 3]))
	else:
		# For more complex shapes, create a fan from first vertex
		for i in range(1, vertices.size() - 1):
			nav_poly.add_polygon(PackedInt32Array([0, i, i + 1]))

	nav_region.navigation_polygon = nav_poly
	print("[GridLayout] Navigation polygon created with %d vertices" % vertices.size())
