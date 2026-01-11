class_name PlayableArea
extends RefCounted
## PlayableArea - Defines and validates the playable world bounds
## All asset placements, navigation, and collision data must fall within these bounds

# World dimensions
const WORLD_SIZE: int = 1024  # Total playable area in pixels
const WORLD_HALF: int = WORLD_SIZE / 2  # 512 - center offset

# Grid configuration
const GRID_SIZE: int = 32  # Pixels per grid cell
const GRID_CELLS: int = WORLD_SIZE / GRID_SIZE  # 32 cells

# Margins - buffer zone from world edges where nothing should be placed
const EDGE_MARGIN: int = 32  # 1 grid cell buffer from edges
const SAFE_MARGIN: int = 64  # 2 grid cells - recommended minimum distance from edge

# PixelLab asset scaling
# Generate assets at smaller sizes, scale up in-game for crisp pixel art
const PIXELLAB_SCALE: int = 2  # Generate at 1/2 size, scale 2x in-game
const PIXELLAB_MAX_SIZE: int = 128  # Maximum PixelLab canvas size we'll use

# Bounds in world coordinates (centered at origin)
const BOUNDS: Rect2 = Rect2(
	Vector2(-WORLD_HALF, -WORLD_HALF),
	Vector2(WORLD_SIZE, WORLD_SIZE)
)

# Safe bounds with margin applied
static func get_safe_bounds() -> Rect2:
	return Rect2(
		Vector2(-WORLD_HALF + SAFE_MARGIN, -WORLD_HALF + SAFE_MARGIN),
		Vector2(WORLD_SIZE - SAFE_MARGIN * 2, WORLD_SIZE - SAFE_MARGIN * 2)
	)

# Inner bounds with minimum margin
static func get_inner_bounds() -> Rect2:
	return Rect2(
		Vector2(-WORLD_HALF + EDGE_MARGIN, -WORLD_HALF + EDGE_MARGIN),
		Vector2(WORLD_SIZE - EDGE_MARGIN * 2, WORLD_SIZE - EDGE_MARGIN * 2)
	)

## ===== VALIDATION METHODS =====

## Check if a point is within playable bounds
static func is_point_valid(pos: Vector2, use_safe_margin: bool = false) -> bool:
	var bounds = get_safe_bounds() if use_safe_margin else get_inner_bounds()
	return bounds.has_point(pos)

## Check if a rectangle fits entirely within playable bounds
static func is_rect_valid(rect: Rect2, use_safe_margin: bool = false) -> bool:
	var bounds = get_safe_bounds() if use_safe_margin else get_inner_bounds()
	return bounds.encloses(rect)

## Check if a placement (center + size) is valid
static func is_placement_valid(center: Vector2, size: Vector2, use_safe_margin: bool = false) -> bool:
	var rect = Rect2(center - size / 2, size)
	return is_rect_valid(rect, use_safe_margin)

## Validate grid coordinates (0-31 range)
static func is_grid_valid(grid_x: int, grid_y: int) -> bool:
	return grid_x >= 0 and grid_x < GRID_CELLS and grid_y >= 0 and grid_y < GRID_CELLS

## Validate grid placement with footprint
static func is_grid_placement_valid(grid_x: int, grid_y: int, footprint: Vector2i, use_safe_margin: bool = false) -> bool:
	# Check all cells of the footprint are within bounds
	var margin_cells = (SAFE_MARGIN if use_safe_margin else EDGE_MARGIN) / GRID_SIZE
	var min_cell = margin_cells
	var max_cell = GRID_CELLS - margin_cells

	if grid_x < min_cell or grid_y < min_cell:
		return false
	if grid_x + footprint.x > max_cell or grid_y + footprint.y > max_cell:
		return false
	return true

## Clamp a position to be within bounds
static func clamp_position(pos: Vector2, use_safe_margin: bool = false) -> Vector2:
	var bounds = get_safe_bounds() if use_safe_margin else get_inner_bounds()
	return Vector2(
		clamp(pos.x, bounds.position.x, bounds.position.x + bounds.size.x),
		clamp(pos.y, bounds.position.y, bounds.position.y + bounds.size.y)
	)

## Clamp a rectangle to fit within bounds (adjusts position, not size)
static func clamp_rect(rect: Rect2, use_safe_margin: bool = false) -> Rect2:
	var bounds = get_safe_bounds() if use_safe_margin else get_inner_bounds()
	var new_pos = Vector2(
		clamp(rect.position.x, bounds.position.x, bounds.position.x + bounds.size.x - rect.size.x),
		clamp(rect.position.y, bounds.position.y, bounds.position.y + bounds.size.y - rect.size.y)
	)
	return Rect2(new_pos, rect.size)

## ===== PIXELLAB ASSET SIZING =====

## Get the size to request from PixelLab for a given display size
## PixelLab generates at smaller resolution, we scale up in-game
static func get_pixellab_size(display_size: Vector2) -> Vector2i:
	var gen_size = display_size / PIXELLAB_SCALE
	# Clamp to PixelLab limits and ensure even numbers
	var width = clampi(int(gen_size.x), 16, PIXELLAB_MAX_SIZE)
	var height = clampi(int(gen_size.y), 16, PIXELLAB_MAX_SIZE)
	# Round to nearest even number for better pixel art
	width = (width / 2) * 2
	height = (height / 2) * 2
	return Vector2i(width, height)

## Get the size to request from PixelLab for a grid footprint
static func get_pixellab_size_for_footprint(footprint: Vector2i) -> Vector2i:
	var display_size = Vector2(footprint.x * GRID_SIZE, footprint.y * GRID_SIZE)
	return get_pixellab_size(display_size)

## Get the scale factor to apply to a PixelLab-generated asset
static func get_asset_scale() -> Vector2:
	return Vector2(PIXELLAB_SCALE, PIXELLAB_SCALE)

## Calculate actual display size from PixelLab generation size
static func get_display_size(pixellab_size: Vector2i) -> Vector2:
	return Vector2(pixellab_size.x * PIXELLAB_SCALE, pixellab_size.y * PIXELLAB_SCALE)

## ===== COORDINATE CONVERSION =====

## Convert grid coordinates to pixel position (world space, centered at origin)
static func grid_to_pixels(grid_x: int, grid_y: int) -> Vector2:
	return Vector2(
		(grid_x - GRID_CELLS / 2) * GRID_SIZE + GRID_SIZE / 2,
		(grid_y - GRID_CELLS / 2) * GRID_SIZE + GRID_SIZE / 2
	)

## Convert pixel position to grid coordinates
static func pixels_to_grid(pos: Vector2) -> Vector2i:
	var grid_x = int(round(pos.x / GRID_SIZE)) + GRID_CELLS / 2
	var grid_y = int(round(pos.y / GRID_SIZE)) + GRID_CELLS / 2
	return Vector2i(
		clampi(grid_x, 0, GRID_CELLS - 1),
		clampi(grid_y, 0, GRID_CELLS - 1)
	)

## ===== VALIDATION REPORTS =====

## Validate an entire layout and return any issues
static func validate_layout(layout: Dictionary) -> Array[String]:
	var issues: Array[String] = []

	# Validate buildings
	if layout.has("buildings"):
		for id in layout.buildings:
			var data = layout.buildings[id]
			var grid_pos = data.grid
			var footprint_name = data.get("footprint", "house_small")
			var footprint = _get_footprint(footprint_name)

			if not is_grid_placement_valid(grid_pos.x, grid_pos.y, footprint, true):
				issues.append("Building '%s' at grid (%d, %d) with footprint %s exceeds safe bounds" % [
					id, grid_pos.x, grid_pos.y, footprint
				])

	# Validate trees
	if layout.has("trees"):
		var tree_footprint = Vector2i(4, 4)
		for i in range(layout.trees.size()):
			var grid_pos = layout.trees[i]
			if not is_grid_placement_valid(grid_pos.x, grid_pos.y, tree_footprint, true):
				issues.append("Tree %d at grid (%d, %d) exceeds safe bounds" % [
					i, grid_pos.x, grid_pos.y
				])

	# Validate props
	if layout.has("props"):
		for id in layout.props:
			var grid_pos = layout.props[id]
			var footprint_name = id.split("_")[0] if "_" in id else id
			var footprint = _get_footprint(footprint_name)

			if not is_grid_placement_valid(grid_pos.x, grid_pos.y, footprint, true):
				issues.append("Prop '%s' at grid (%d, %d) exceeds safe bounds" % [
					id, grid_pos.x, grid_pos.y
				])

	# Validate paths
	if layout.has("paths"):
		for path_id in layout.paths:
			var path = layout.paths[path_id]
			var start = path.start
			var end = path.end

			if not is_grid_valid(start.x, start.y) or not is_grid_valid(end.x, end.y):
				issues.append("Path '%s' has coordinates outside grid bounds" % path_id)

	return issues

## Helper to get footprint from known types
static func _get_footprint(footprint_name: String) -> Vector2i:
	var footprints = {
		"barrel": Vector2i(2, 2),
		"crate": Vector2i(2, 2),
		"bench": Vector2i(2, 2),
		"lamppost": Vector2i(2, 2),
		"well": Vector2i(3, 3),
		"cart": Vector2i(3, 3),
		"tree": Vector2i(4, 4),
		"house_small": Vector2i(5, 4),
		"house_medium": Vector2i(5, 5),
		"shop": Vector2i(6, 5),
		"tavern": Vector2i(7, 6),
		"blacksmith": Vector2i(5, 5),
		"gate": Vector2i(4, 4),
	}
	return footprints.get(footprint_name, Vector2i(2, 2))

## Print bounds info for debugging
static func print_bounds_info() -> void:
	print("=== PLAYABLE AREA BOUNDS ===")
	print("World size: %d x %d pixels" % [WORLD_SIZE, WORLD_SIZE])
	print("Grid: %d x %d cells (%d px each)" % [GRID_CELLS, GRID_CELLS, GRID_SIZE])
	print("Full bounds: %s" % BOUNDS)
	print("Inner bounds (edge margin): %s" % get_inner_bounds())
	print("Safe bounds (safe margin): %s" % get_safe_bounds())
	print("PixelLab scale: %dx (generate at 1/%d size)" % [PIXELLAB_SCALE, PIXELLAB_SCALE])
