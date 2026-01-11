extends Node
class_name MockGenerator
## MockGenerator - Test backend that creates colored placeholder images
## Useful for development without API costs

signal generation_started(request_id: String)
signal generation_completed(request_id: String, image_path: String)
signal generation_failed(request_id: String, error: String)

@export var generation_delay: float = 0.5  # Simulate API latency

func is_available() -> bool:
	return true  # Always available

func get_backend_name() -> String:
	return "Mock (Development)"

func generate(request) -> String:
	generation_started.emit(request.id)

	# Create a simple colored image based on prompt hash
	var color = _prompt_to_color(request.prompt)
	var image = _create_placeholder_image(request.width, request.height, color, request.prompt)

	# Simulate async generation
	await get_tree().create_timer(generation_delay).timeout

	# Save the image
	var png_data = image.save_png_to_buffer()
	var filename = "mock_%s.png" % request.id
	var path = _save_image_to_file(png_data, filename)

	if path != "":
		generation_completed.emit(request.id, path)
	else:
		generation_failed.emit(request.id, "Failed to save mock image")

	return request.id

func _prompt_to_color(prompt: String) -> Color:
	# Generate consistent color from prompt
	var hash = prompt.hash()
	var r = (hash & 0xFF) / 255.0
	var g = ((hash >> 8) & 0xFF) / 255.0
	var b = ((hash >> 16) & 0xFF) / 255.0
	return Color(r * 0.6 + 0.2, g * 0.6 + 0.2, b * 0.6 + 0.2)  # Avoid too dark/light

func _create_placeholder_image(width: int, height: int, base_color: Color, prompt: String) -> Image:
	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)

	# Fill with base color
	image.fill(base_color)

	# Add some visual interest - border
	var border_color = base_color.darkened(0.3)
	for x in range(width):
		image.set_pixel(x, 0, border_color)
		image.set_pixel(x, height - 1, border_color)
	for y in range(height):
		image.set_pixel(0, y, border_color)
		image.set_pixel(width - 1, y, border_color)

	# Add inner highlight
	var highlight = base_color.lightened(0.2)
	for x in range(2, width - 2):
		image.set_pixel(x, 2, highlight)
	for y in range(2, height - 2):
		image.set_pixel(2, y, highlight)

	# Add simple pattern based on prompt content
	if "shop" in prompt.to_lower() or "building" in prompt.to_lower():
		_add_building_pattern(image, base_color)
	elif "tree" in prompt.to_lower():
		_add_tree_pattern(image, base_color)
	elif "well" in prompt.to_lower():
		_add_circle_pattern(image, base_color)
	elif "path" in prompt.to_lower() or "road" in prompt.to_lower():
		_add_path_pattern(image, base_color)

	return image

func _add_building_pattern(image: Image, base: Color):
	var w = image.get_width()
	var h = image.get_height()

	# Roof area (top third)
	var roof_color = base.darkened(0.2)
	for y in range(int(h * 0.3)):
		for x in range(w):
			image.set_pixel(x, y, roof_color)

	# Door
	var door_color = base.darkened(0.4)
	var door_x = int(w * 0.4)
	var door_w = int(w * 0.2)
	var door_h = int(h * 0.3)
	for y in range(int(h * 0.7), h - 2):
		for x in range(door_x, door_x + door_w):
			if x < w:
				image.set_pixel(x, y, door_color)

	# Window
	var window_color = Color(0.6, 0.7, 0.9)
	var win_size = int(min(w, h) * 0.15)
	var win_x = int(w * 0.7)
	var win_y = int(h * 0.45)
	for y in range(win_y, win_y + win_size):
		for x in range(win_x, win_x + win_size):
			if x < w and y < h:
				image.set_pixel(x, y, window_color)

func _add_tree_pattern(image: Image, base: Color):
	var w = image.get_width()
	var h = image.get_height()

	# Trunk (bottom center)
	var trunk_color = Color(0.4, 0.25, 0.15)
	var trunk_w = int(w * 0.2)
	var trunk_x = int(w * 0.4)
	for y in range(int(h * 0.6), h - 2):
		for x in range(trunk_x, trunk_x + trunk_w):
			if x < w:
				image.set_pixel(x, y, trunk_color)

	# Canopy (green circle-ish)
	var leaf_color = Color(0.2, 0.5, 0.2)
	var center_x = w / 2
	var center_y = int(h * 0.35)
	var radius = int(min(w, h) * 0.35)
	for y in range(h):
		for x in range(w):
			var dx = x - center_x
			var dy = y - center_y
			if dx * dx + dy * dy < radius * radius:
				image.set_pixel(x, y, leaf_color)

func _add_circle_pattern(image: Image, base: Color):
	var w = image.get_width()
	var h = image.get_height()

	var center_x = w / 2
	var center_y = h / 2
	var outer_r = int(min(w, h) * 0.4)
	var inner_r = int(min(w, h) * 0.25)

	var stone_color = Color(0.4, 0.4, 0.45)
	var water_color = Color(0.2, 0.3, 0.5)

	for y in range(h):
		for x in range(w):
			var dx = x - center_x
			var dy = y - center_y
			var dist_sq = dx * dx + dy * dy
			if dist_sq < outer_r * outer_r:
				if dist_sq < inner_r * inner_r:
					image.set_pixel(x, y, water_color)
				else:
					image.set_pixel(x, y, stone_color)

func _add_path_pattern(image: Image, base: Color):
	var w = image.get_width()
	var h = image.get_height()

	var path_color = Color(0.5, 0.45, 0.35)
	var edge_color = Color(0.4, 0.35, 0.25)

	# Vertical path
	var path_x1 = int(w * 0.3)
	var path_x2 = int(w * 0.7)

	for y in range(h):
		for x in range(path_x1, path_x2):
			if x == path_x1 or x == path_x2 - 1:
				image.set_pixel(x, y, edge_color)
			else:
				image.set_pixel(x, y, path_color)

func _save_image_to_file(image_data: PackedByteArray, filename: String) -> String:
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("generated_assets"):
		dir.make_dir("generated_assets")

	var path = "user://generated_assets/" + filename
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(image_data)
		file.close()
		return path
	return ""
