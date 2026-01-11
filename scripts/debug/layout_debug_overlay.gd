extends Node2D
class_name LayoutDebugOverlay
## Visual debug overlay for grid layout and asset positioning
## Toggle with F8 key

const GridLayout = preload("res://scripts/world/grid_layout.gd")
const GeneratableAssetScript = preload("res://scripts/world/generatable_asset.gd")

var enabled: bool = false
var show_grid: bool = true
var show_asset_bounds: bool = true
var show_collision_shapes: bool = true
var show_positions: bool = true

## Colors
const COLOR_GRID = Color(1, 1, 1, 0.15)
const COLOR_GRID_MAJOR = Color(1, 1, 0, 0.3)
const COLOR_GRID_CENTER = Color(1, 0, 0, 0.5)
const COLOR_ASSET_BUILDING = Color(0, 0.5, 1, 0.4)
const COLOR_ASSET_TREE = Color(0, 1, 0, 0.4)
const COLOR_ASSET_PROP = Color(1, 0.5, 0, 0.4)
const COLOR_COLLISION = Color(1, 0, 1, 0.3)
const COLOR_TEXT_BG = Color(0, 0, 0, 0.7)
const COLOR_TEXT = Color(1, 1, 1, 1)

func _ready():
	z_index = 1000  # Draw on top of everything
	print("[LayoutDebug] Ready - Press F8 to toggle debug overlay")

func _unhandled_key_input(event: InputEvent):
	if not event.pressed:
		return

	match event.keycode:
		KEY_F8:
			enabled = not enabled
			queue_redraw()
			_print_layout_report()
			print("[LayoutDebug] Overlay %s" % ["DISABLED", "ENABLED"][int(enabled)])
			get_viewport().set_input_as_handled()
		KEY_1:
			if enabled:
				show_grid = not show_grid
				queue_redraw()
				get_viewport().set_input_as_handled()
		KEY_2:
			if enabled:
				show_asset_bounds = not show_asset_bounds
				queue_redraw()
				get_viewport().set_input_as_handled()
		KEY_3:
			if enabled:
				show_collision_shapes = not show_collision_shapes
				queue_redraw()
				get_viewport().set_input_as_handled()
		KEY_4:
			if enabled:
				show_positions = not show_positions
				queue_redraw()
				get_viewport().set_input_as_handled()

func _draw():
	if not enabled:
		return

	if show_grid:
		_draw_grid()

	if show_asset_bounds:
		_draw_asset_bounds()

	if show_collision_shapes:
		_draw_collision_shapes()

	_draw_legend()

func _draw_grid():
	var half_world = GridLayout.WORLD_SIZE / 2
	var grid_size = GridLayout.GRID_SIZE

	# Draw grid lines
	for i in range(GridLayout.GRID_CELLS + 1):
		var offset = (i - GridLayout.GRID_CELLS / 2) * grid_size
		var color = COLOR_GRID

		# Major grid lines every 4 cells
		if i % 4 == 0:
			color = COLOR_GRID_MAJOR

		# Center lines
		if i == GridLayout.GRID_CELLS / 2:
			color = COLOR_GRID_CENTER

		# Vertical line
		draw_line(Vector2(offset, -half_world), Vector2(offset, half_world), color, 1.0)
		# Horizontal line
		draw_line(Vector2(-half_world, offset), Vector2(half_world, offset), color, 1.0)

	# Draw world bounds
	draw_rect(Rect2(-half_world, -half_world, GridLayout.WORLD_SIZE, GridLayout.WORLD_SIZE), Color.RED, false, 2.0)

func _draw_asset_bounds():
	var game_world = get_parent()
	if not game_world:
		return

	for child in game_world.get_children():
		var asset_node = _find_generatable_asset(child)
		if asset_node:
			_draw_single_asset_bounds(child, asset_node)

func _find_generatable_asset(node: Node) -> Node:
	for child in node.get_children():
		if child.get_script() == GeneratableAssetScript:
			return child
	return null

func _draw_single_asset_bounds(parent: Node, asset: Node):
	if not parent is Node2D:
		return

	var pos = parent.global_position
	var bounds = _calculate_visual_bounds(parent)

	# Select color based on asset type (use duck typing)
	var color = COLOR_ASSET_PROP
	var asset_type_val = asset.get("asset_type") if asset.get("asset_type") else "prop"
	match asset_type_val:
		"building":
			color = COLOR_ASSET_BUILDING
		"tree":
			color = COLOR_ASSET_TREE
		"prop":
			color = COLOR_ASSET_PROP

	# Draw bounding box (adjusted for parent position)
	var rect = Rect2(pos + bounds.position, bounds.size)
	draw_rect(rect, color, false, 2.0)
	draw_rect(rect, Color(color.r, color.g, color.b, 0.1), true)

	# Draw center point
	draw_circle(pos, 4, Color.WHITE)

	# Draw position label
	if show_positions:
		var asset_id_val = asset.get("asset_id") if asset.get("asset_id") else "unknown"
		var grid_pos = _pixel_to_grid(pos)
		var label = "%s\npos: (%.0f, %.0f)\nsize: %.0fx%.0f\ngrid: (%d, %d)" % [
			asset_id_val,
			pos.x, pos.y,
			bounds.size.x, bounds.size.y,
			grid_pos.x, grid_pos.y
		]
		_draw_label(pos + Vector2(bounds.size.x/2 + 5, -bounds.size.y/2), label, color)

func _calculate_visual_bounds(parent: Node) -> Rect2:
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)

	for child in parent.get_children():
		if child is ColorRect:
			var rect_min = Vector2(child.offset_left, child.offset_top)
			var rect_max = Vector2(child.offset_right, child.offset_bottom)
			min_pos.x = min(min_pos.x, rect_min.x)
			min_pos.y = min(min_pos.y, rect_min.y)
			max_pos.x = max(max_pos.x, rect_max.x)
			max_pos.y = max(max_pos.y, rect_max.y)

	if min_pos.x == INF:
		return Rect2(-64, -64, 128, 128)

	return Rect2(min_pos, max_pos - min_pos)

func _draw_collision_shapes():
	var game_world = get_parent()
	if not game_world:
		return

	for child in game_world.get_children():
		if child is StaticBody2D or child is Area2D:
			_draw_collision_for_body(child)

func _draw_collision_for_body(body: Node2D):
	for child in body.get_children():
		if child is CollisionShape2D and child.shape:
			var shape_pos = body.global_position + child.position

			if child.shape is RectangleShape2D:
				var rect_shape = child.shape as RectangleShape2D
				var half_size = rect_shape.size / 2
				var rect = Rect2(shape_pos - half_size, rect_shape.size)
				draw_rect(rect, COLOR_COLLISION, false, 2.0)
				draw_rect(rect, Color(COLOR_COLLISION.r, COLOR_COLLISION.g, COLOR_COLLISION.b, 0.1), true)
			elif child.shape is CircleShape2D:
				var circle_shape = child.shape as CircleShape2D
				draw_arc(shape_pos, circle_shape.radius, 0, TAU, 32, COLOR_COLLISION, 2.0)

func _draw_label(pos: Vector2, text: String, color: Color):
	var font = ThemeDB.fallback_font
	var font_size = 10
	var lines = text.split("\n")
	var line_height = 12
	var max_width = 0

	for line in lines:
		var line_size = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		max_width = max(max_width, line_size.x)

	var bg_rect = Rect2(pos.x - 2, pos.y - 2, max_width + 4, lines.size() * line_height + 4)
	draw_rect(bg_rect, COLOR_TEXT_BG, true)
	draw_rect(bg_rect, color, false, 1.0)

	for i in range(lines.size()):
		draw_string(font, pos + Vector2(0, i * line_height + 10), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_TEXT)

func _draw_legend():
	var legend_pos = Vector2(-500, -500)
	var legend = "F8: Toggle | 1: Grid | 2: Bounds | 3: Collision | 4: Labels"
	_draw_label(legend_pos, legend, Color.WHITE)

	# Show current toggles
	var status = "Grid: %s | Bounds: %s | Collision: %s | Labels: %s" % [
		"ON" if show_grid else "OFF",
		"ON" if show_asset_bounds else "OFF",
		"ON" if show_collision_shapes else "OFF",
		"ON" if show_positions else "OFF"
	]
	_draw_label(legend_pos + Vector2(0, 20), status, Color.GRAY)

func _pixel_to_grid(pos: Vector2) -> Vector2i:
	return GridLayout.pixels_to_grid(pos)

## Helper to repeat a string
func _repeat_str(s: String, count: int) -> String:
	var result = ""
	for i in range(count):
		result += s
	return result

func _print_layout_report():
	if not enabled:
		return

	var separator = _repeat_str("=", 60)
	var dash_line = _repeat_str("-", 60)

	print("\n" + separator)
	print("LAYOUT DEBUG REPORT")
	print(separator)
	print("Grid: %dx%d cells, %dpx per cell" % [GridLayout.GRID_CELLS, GridLayout.GRID_CELLS, GridLayout.GRID_SIZE])
	print("World: %dx%d pixels (-%d to +%d)" % [GridLayout.WORLD_SIZE, GridLayout.WORLD_SIZE, GridLayout.WORLD_SIZE/2, GridLayout.WORLD_SIZE/2])
	print(dash_line)

	var game_world = get_parent()
	if not game_world:
		print("ERROR: No parent game world found!")
		return

	var assets_by_type = {"building": [], "tree": [], "prop": []}

	for child in game_world.get_children():
		var asset_node = _find_generatable_asset(child)
		if asset_node and child is Node2D:
			var pos = child.global_position
			var bounds = _calculate_visual_bounds(child)
			var grid_pos = _pixel_to_grid(pos)
			var asset_id_val = asset_node.get("asset_id") if asset_node.get("asset_id") else "unknown"
			var asset_type_val = asset_node.get("asset_type") if asset_node.get("asset_type") else "prop"
			var info = {
				"id": asset_id_val,
				"pos": pos,
				"grid": grid_pos,
				"size": bounds.size,
				"node": child.name
			}
			if assets_by_type.has(asset_type_val):
				assets_by_type[asset_type_val].append(info)

	for type in ["building", "tree", "prop"]:
		if assets_by_type[type].size() > 0:
			print("\n%sS (%d):" % [type.to_upper(), assets_by_type[type].size()])
			for asset in assets_by_type[type]:
				var snap_check = ""
				var expected_pos = GridLayout.grid_to_pixels(asset.grid.x, asset.grid.y)
				var diff = asset.pos - expected_pos
				if diff.length() > 1:
					snap_check = " [NOT SNAPPED! diff=%.1f,%.1f]" % [diff.x, diff.y]
				print("  %-20s pos=(%6.0f,%6.0f) grid=(%2d,%2d) size=%3.0fx%3.0f%s" % [
					asset.id, asset.pos.x, asset.pos.y, asset.grid.x, asset.grid.y, asset.size.x, asset.size.y, snap_check
				])

	# Check for overlaps
	print("\n" + dash_line)
	print("OVERLAP CHECK:")
	var all_assets = []
	for type in assets_by_type:
		all_assets.append_array(assets_by_type[type])

	var overlaps_found = 0
	for i in range(all_assets.size()):
		for j in range(i + 1, all_assets.size()):
			var a = all_assets[i]
			var b = all_assets[j]
			var rect_a = Rect2(a.pos - a.size/2, a.size)
			var rect_b = Rect2(b.pos - b.size/2, b.size)
			if rect_a.intersects(rect_b):
				print("  OVERLAP: %s <-> %s" % [a.id, b.id])
				overlaps_found += 1

	if overlaps_found == 0:
		print("  No overlaps detected")

	print(separator + "\n")
