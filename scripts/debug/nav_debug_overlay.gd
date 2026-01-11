extends Node2D
## Navigation debug overlay - Toggle with F8 to visualize walkable areas
## Shows NavigationPolygon outlines, collision shapes, and entry points

var is_visible_overlay: bool = false
var nav_color := Color(0.2, 0.8, 0.2, 0.4)  # Green semi-transparent
var collision_color := Color(0.8, 0.2, 0.2, 0.4)  # Red semi-transparent
var entry_color := Color(0.2, 0.2, 0.8, 0.6)  # Blue
var spawn_color := Color(1.0, 1.0, 0.0, 0.8)  # Yellow

func _ready():
	# Start hidden
	visible = false
	# High z-index to draw on top
	z_index = 100

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
		toggle_overlay()
		get_viewport().set_input_as_handled()

func toggle_overlay():
	is_visible_overlay = not is_visible_overlay
	visible = is_visible_overlay
	if is_visible_overlay:
		print("[NavDebug] Overlay enabled - showing navigation, collisions, entries")
		queue_redraw()
	else:
		print("[NavDebug] Overlay disabled")

func _draw():
	if not is_visible_overlay:
		return

	var scene_root = get_tree().current_scene
	if not scene_root:
		return

	# Draw navigation polygons
	_draw_navigation(scene_root)

	# Draw collision shapes
	_draw_collisions(scene_root)

	# Draw entry points
	_draw_entry_points(scene_root)

	# Draw spawn points
	_draw_spawn_points(scene_root)

func _draw_navigation(root: Node):
	var nav_region = root.get_node_or_null("NavigationRegion2D")
	if not nav_region or not nav_region.navigation_polygon:
		# Draw "No NavPoly" text at center
		draw_string(ThemeDB.fallback_font, Vector2(-60, 0), "No NavigationPolygon", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.RED)
		return

	var nav_poly = nav_region.navigation_polygon
	var vertices = nav_poly.vertices

	# Draw polygons (triangles) - the actual navigation mesh
	for i in range(nav_poly.get_polygon_count()):
		var polygon = nav_poly.get_polygon(i)
		if polygon.size() >= 3:
			var points = PackedVector2Array()
			for idx in polygon:
				if idx < vertices.size():
					points.append(vertices[idx])

			if points.size() >= 3:
				# Draw filled polygon
				var colors = PackedColorArray()
				for _j in range(points.size()):
					colors.append(nav_color)
				draw_polygon(points, colors)

				# Draw polygon border
				var points_closed = points.duplicate()
				points_closed.append(points[0])  # Close the loop
				draw_polyline(points_closed, Color(0.0, 1.0, 0.0, 0.8), 1.5)

	# Also draw outlines if they exist
	for i in range(nav_poly.get_outline_count()):
		var outline = nav_poly.get_outline(i)
		if outline.size() >= 3:
			var outline_closed = outline.duplicate()
			outline_closed.append(outline[0])
			draw_polyline(outline_closed, Color(0.0, 0.8, 0.0, 1.0), 3.0)

	# Draw polygon count
	var count_text = "NavPoly: %d polygons, %d vertices" % [nav_poly.get_polygon_count(), vertices.size()]
	draw_string(ThemeDB.fallback_font, Vector2(-200, -450), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.GREEN)

func _draw_collisions(root: Node):
	var collisions = root.get_node_or_null("Collisions")
	if not collisions:
		return

	for child in collisions.get_children():
		if child is StaticBody2D:
			var shape_node = child.get_node_or_null("CollisionShape2D")
			if shape_node and shape_node.shape:
				var pos = child.global_position - global_position

				if shape_node.shape is RectangleShape2D:
					var rect_shape = shape_node.shape as RectangleShape2D
					var size = rect_shape.size
					var rect = Rect2(pos - size/2, size)
					draw_rect(rect, collision_color, true)
					draw_rect(rect, Color(1.0, 0.3, 0.3, 0.8), false, 2.0)

					# Label
					draw_string(ThemeDB.fallback_font, pos + Vector2(-40, -size.y/2 - 5), child.name.replace("Collision", ""), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)

				elif shape_node.shape is CircleShape2D:
					var circle_shape = shape_node.shape as CircleShape2D
					draw_circle(pos, circle_shape.radius, collision_color)
					draw_arc(pos, circle_shape.radius, 0, TAU, 32, Color(1.0, 0.3, 0.3, 0.8), 2.0)

func _draw_entry_points(root: Node):
	var entries = root.get_node_or_null("EntryPoints")
	if not entries:
		return

	for child in entries.get_children():
		if child is Area2D:
			var pos = child.global_position - global_position

			# Draw door icon (small rectangle with arrow)
			var door_rect = Rect2(pos - Vector2(15, 10), Vector2(30, 20))
			draw_rect(door_rect, entry_color, true)
			draw_rect(door_rect, Color(0.3, 0.3, 1.0, 1.0), false, 2.0)

			# Arrow pointing down (into building)
			var arrow_start = pos + Vector2(0, -15)
			var arrow_end = pos + Vector2(0, -5)
			draw_line(arrow_start, arrow_end, Color.WHITE, 2.0)
			draw_line(arrow_end, arrow_end + Vector2(-5, -5), Color.WHITE, 2.0)
			draw_line(arrow_end, arrow_end + Vector2(5, -5), Color.WHITE, 2.0)

			# Label
			var label = child.name.replace("Entry", "")
			draw_string(ThemeDB.fallback_font, pos + Vector2(-30, 25), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color.CYAN)

func _draw_spawn_points(root: Node):
	var spawns = root.get_node_or_null("SpawnPoints")
	if not spawns:
		return

	for child in spawns.get_children():
		if child is Marker2D:
			var pos = child.global_position - global_position

			# Draw spawn marker (diamond)
			var diamond = PackedVector2Array([
				pos + Vector2(0, -12),
				pos + Vector2(8, 0),
				pos + Vector2(0, 12),
				pos + Vector2(-8, 0)
			])
			draw_polygon(diamond, [spawn_color, spawn_color, spawn_color, spawn_color])
			diamond.append(diamond[0])
			draw_polyline(diamond, Color.YELLOW, 2.0)

			# Label
			draw_string(ThemeDB.fallback_font, pos + Vector2(-30, 20), child.name, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.YELLOW)

func _process(_delta):
	if is_visible_overlay:
		queue_redraw()  # Continuously redraw to follow camera
