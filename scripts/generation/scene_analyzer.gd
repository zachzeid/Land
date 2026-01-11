extends Node
## SceneAnalyzer - Uses Claude Vision API to analyze generated scenes
## Note: No class_name since this is used as an autoload singleton
## Identifies walkable paths, building locations, door positions, etc.

signal analysis_completed(result: Dictionary, image_size: Vector2)
signal analysis_failed(error: String)

const CLAUDE_API_URL = "https://api.anthropic.com/v1/messages"
const REQUEST_TIMEOUT_MS = 60000

var api_key: String = ""
var pending_request: HTTPRequest = null
var _last_image_size: Vector2 = Vector2(1024, 1024)  # Track actual image size for results

func _ready():
	_load_api_key()

func _load_api_key():
	# Check environment variable
	var env_key = OS.get_environment("ANTHROPIC_API_KEY")
	if env_key != "":
		api_key = env_key
		return

	# Check Config autoload
	if Config and "anthropic_api_key" in Config and Config.anthropic_api_key != "":
		api_key = Config.anthropic_api_key
		return

	# Check local .env file
	var env_path = "res://.env"
	if FileAccess.file_exists(env_path):
		var file = FileAccess.open(env_path, FileAccess.READ)
		while not file.eof_reached():
			var line = file.get_line().strip_edges()
			if line.begins_with("ANTHROPIC_API_KEY="):
				api_key = line.substr(18)
				break
		file.close()

func is_available() -> bool:
	return api_key != ""

## Analyze a generated scene image to identify game elements
## Returns structured data about paths, buildings, doors, etc.
func analyze_scene(image_path: String, scene_description: String = "") -> void:
	if not is_available():
		analysis_failed.emit("Anthropic API key not configured")
		return

	print("[SceneAnalyzer] Starting analysis of: %s" % image_path)

	# Load and encode the image
	var abs_path = image_path
	if image_path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(image_path)

	if not FileAccess.file_exists(abs_path):
		analysis_failed.emit("Image file not found: %s" % abs_path)
		return

	var image = Image.new()
	var err = image.load(abs_path)
	if err != OK:
		analysis_failed.emit("Failed to load image")
		return

	# Get actual image dimensions
	_last_image_size = Vector2(image.get_width(), image.get_height())
	print("[SceneAnalyzer] Actual image size: %dx%d" % [int(_last_image_size.x), int(_last_image_size.y)])

	# Convert to base64 PNG
	var png_data = image.save_png_to_buffer()
	var base64_image = Marshalls.raw_to_base64(png_data)

	# Build the analysis prompt with actual dimensions
	var prompt = _build_analysis_prompt(scene_description, _last_image_size)

	# Create request body
	var body = {
		"model": "claude-sonnet-4-20250514",
		"max_tokens": 4096,
		"messages": [{
			"role": "user",
			"content": [
				{
					"type": "image",
					"source": {
						"type": "base64",
						"media_type": "image/png",
						"data": base64_image
					}
				},
				{
					"type": "text",
					"text": prompt
				}
			]
		}]
	}

	# Send request
	pending_request = HTTPRequest.new()
	pending_request.timeout = REQUEST_TIMEOUT_MS / 1000.0
	add_child(pending_request)

	pending_request.request_completed.connect(_on_request_completed)

	var headers = [
		"x-api-key: " + api_key,
		"anthropic-version: 2023-06-01",
		"Content-Type: application/json"
	]

	var json_body = JSON.stringify(body)
	print("[SceneAnalyzer] Sending to Claude Vision API...")

	err = pending_request.request(CLAUDE_API_URL, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		analysis_failed.emit("HTTP request failed: %d" % err)
		pending_request.queue_free()
		pending_request = null

func _build_analysis_prompt(scene_description: String, image_size: Vector2 = Vector2(1024, 1024)) -> String:
	var center_x = int(image_size.x / 2)
	var center_y = int(image_size.y / 2)
	var prompt = """Analyze this top-down 2D game scene image. The image is %dx%d pixels.

I need you to identify the following elements and provide their approximate pixel coordinates (where 0,0 is the top-left corner of the image, and %d,%d is roughly the center):""" % [int(image_size.x), int(image_size.y), center_x, center_y]

	prompt += """

1. **Walkable Paths**: Identify areas that appear to be walkable paths (cobblestone, dirt roads, plazas). Provide a list of rectangular regions or polygon vertices.

2. **Buildings**: Identify each building visible in the scene. For each building, provide:
   - A descriptive name (e.g., "tavern", "shop", "blacksmith")
   - The bounding box (top-left x,y and width,height)
   - The likely door/entrance position (x,y coordinate where a player would enter)

3. **Props/Obstacles**: Identify any props like wells, barrels, crates, trees that should block player movement. Provide bounding boxes.

4. **Spawn Points**: Suggest good spawn points for the player (typically on paths, near entrances).

"""

	if scene_description != "":
		prompt += "Scene context: %s\n\n" % scene_description

	prompt += """Respond in this exact JSON format:
```json
{
  "walkable_regions": [
    {"type": "rect", "x": 100, "y": 100, "width": 200, "height": 300},
    {"type": "polygon", "points": [[x1,y1], [x2,y2], [x3,y3], ...]}
  ],
  "buildings": [
    {
      "name": "tavern",
      "bounds": {"x": 50, "y": 50, "width": 150, "height": 120},
      "door": {"x": 125, "y": 170}
    }
  ],
  "obstacles": [
    {"name": "well", "bounds": {"x": 480, "y": 480, "width": 64, "height": 64}}
  ],
  "spawn_points": [
    {"name": "default", "x": 512, "y": 600},
    {"name": "from_north", "x": 512, "y": 100}
  ]
}
```

Be precise with coordinates. The image is %dx%d pixels. Provide coordinates relative to the image dimensions.""" % [int(image_size.x), int(image_size.y)]

	return prompt

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if pending_request:
		pending_request.queue_free()
		pending_request = null

	if result != HTTPRequest.RESULT_SUCCESS:
		analysis_failed.emit("Request failed: %d" % result)
		return

	if response_code != 200:
		var error_text = body.get_string_from_utf8()
		print("[SceneAnalyzer] API error: %s" % error_text.left(500))
		analysis_failed.emit("API error %d" % response_code)
		return

	# Parse Claude's response
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		analysis_failed.emit("Failed to parse API response")
		return

	var response_data = json.data
	if not response_data.has("content") or response_data.content.size() == 0:
		analysis_failed.emit("No content in response")
		return

	var text_content = response_data.content[0].text
	print("[SceneAnalyzer] Received analysis response")

	# Extract JSON from the response (it might be wrapped in markdown code blocks)
	var analysis_result = _extract_json_from_response(text_content)
	if analysis_result.is_empty():
		analysis_failed.emit("Failed to parse analysis JSON")
		return

	print("[SceneAnalyzer] Analysis complete!")
	analysis_completed.emit(analysis_result, _last_image_size)

func _extract_json_from_response(text: String) -> Dictionary:
	# Try to find JSON in the response (might be in code blocks)
	var json_start = text.find("{")
	var json_end = text.rfind("}") + 1

	if json_start == -1 or json_end <= json_start:
		return {}

	var json_str = text.substr(json_start, json_end - json_start)

	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK:
		print("[SceneAnalyzer] JSON parse error: %s" % json.get_error_message())
		return {}

	return json.data

## Convert analysis results to Godot scene elements
## This can be used to automatically update collision shapes, navigation, etc.
## Set force_navigation to true to replace existing navigation polygons with Vision API results
func apply_analysis_to_scene(analysis: Dictionary, scene_root: Node2D, image_size: Vector2 = Vector2(1024, 1024), scene_size: Vector2 = Vector2(1024, 1024), force_navigation: bool = false) -> void:
	var scale_factor = scene_size / image_size
	var offset = -scene_size / 2  # Center the scene at origin

	print("[SceneAnalyzer] Applying analysis to scene...")
	print("[SceneAnalyzer]   Scale: %s, Offset: %s" % [scale_factor, offset])

	# Create or update collision shapes for buildings
	if analysis.has("buildings"):
		_apply_building_collisions(analysis.buildings, scene_root, scale_factor, offset)

	# Create or update obstacle collisions
	if analysis.has("obstacles"):
		_apply_obstacle_collisions(analysis.obstacles, scene_root, scale_factor, offset)

	# Create or update spawn points
	if analysis.has("spawn_points"):
		_apply_spawn_points(analysis.spawn_points, scene_root, scale_factor, offset)

	# Create or update navigation polygon from walkable regions
	if analysis.has("walkable_regions"):
		_apply_navigation_polygon(analysis.walkable_regions, scene_root, scale_factor, offset, force_navigation)

func _apply_building_collisions(buildings: Array, scene_root: Node2D, scale: Vector2, offset: Vector2):
	# Find or create Collisions node
	var collisions = scene_root.get_node_or_null("Collisions")
	if not collisions:
		collisions = Node2D.new()
		collisions.name = "Collisions"
		scene_root.add_child(collisions)
		collisions.owner = scene_root

	# Find or create EntryPoints node
	var entry_points = scene_root.get_node_or_null("EntryPoints")
	if not entry_points:
		entry_points = Node2D.new()
		entry_points.name = "EntryPoints"
		scene_root.add_child(entry_points)
		entry_points.owner = scene_root

	for building in buildings:
		var bounds = building.bounds
		var collision_name = building.name.to_pascal_case() + "Collision"

		# Convert coordinates
		var pos = Vector2(bounds.x + bounds.width/2, bounds.y + bounds.height/2) * scale + offset
		var size = Vector2(bounds.width, bounds.height) * scale

		print("[SceneAnalyzer] Building '%s' at %s size %s" % [building.name, pos, size])

		# Check if collision already exists, or create new one
		var collision_body = collisions.get_node_or_null(collision_name)
		if collision_body:
			collision_body.position = pos
			var shape = collision_body.get_node_or_null("CollisionShape2D")
			if shape and shape.shape is RectangleShape2D:
				shape.shape.size = size
		else:
			# Create new collision body
			collision_body = StaticBody2D.new()
			collision_body.name = collision_name
			collision_body.position = pos
			collisions.add_child(collision_body)
			collision_body.owner = scene_root

			var shape = CollisionShape2D.new()
			shape.name = "CollisionShape2D"
			var rect_shape = RectangleShape2D.new()
			rect_shape.size = size
			shape.shape = rect_shape
			collision_body.add_child(shape)
			shape.owner = scene_root
			print("[SceneAnalyzer]   Created new collision for '%s'" % building.name)

		# Apply door position if we have entry points
		if building.has("door"):
			var door_pos = Vector2(building.door.x, building.door.y) * scale + offset
			var entry_name = building.name.to_pascal_case() + "Entry"
			var existing_entry = entry_points.get_node_or_null(entry_name)
			if existing_entry:
				existing_entry.position = door_pos
				print("[SceneAnalyzer]   Updated door at %s" % door_pos)
			else:
				# Create new entry point
				var entry = Area2D.new()
				entry.name = entry_name
				entry.position = door_pos
				entry_points.add_child(entry)
				entry.owner = scene_root

				var entry_shape = CollisionShape2D.new()
				entry_shape.name = "CollisionShape2D"
				var entry_rect = RectangleShape2D.new()
				entry_rect.size = Vector2(60, 30) * scale
				entry_shape.shape = entry_rect
				entry.add_child(entry_shape)
				entry_shape.owner = scene_root
				print("[SceneAnalyzer]   Created door entry at %s" % door_pos)

func _apply_obstacle_collisions(obstacles: Array, scene_root: Node2D, scale: Vector2, offset: Vector2):
	# Find or create Collisions node
	var collisions = scene_root.get_node_or_null("Collisions")
	if not collisions:
		collisions = Node2D.new()
		collisions.name = "Collisions"
		scene_root.add_child(collisions)
		collisions.owner = scene_root

	for obstacle in obstacles:
		var bounds = obstacle.bounds
		var collision_name = obstacle.name.to_pascal_case() + "Collision"

		var pos = Vector2(bounds.x + bounds.width/2, bounds.y + bounds.height/2) * scale + offset
		var size = Vector2(bounds.width, bounds.height) * scale

		print("[SceneAnalyzer] Obstacle '%s' at %s size %s" % [obstacle.name, pos, size])

		var existing = collisions.get_node_or_null(collision_name)
		if existing:
			existing.position = pos
			var shape = existing.get_node_or_null("CollisionShape2D")
			if shape and shape.shape is RectangleShape2D:
				shape.shape.size = size
		else:
			# Create new obstacle collision
			var obstacle_body = StaticBody2D.new()
			obstacle_body.name = collision_name
			obstacle_body.position = pos
			# Set to world_obstacle layer (layer 4)
			obstacle_body.collision_layer = 1 << 3
			obstacle_body.collision_mask = (1 << 0) | (1 << 1)  # Collides with player + NPC
			collisions.add_child(obstacle_body)
			obstacle_body.owner = scene_root

			var shape = CollisionShape2D.new()
			shape.name = "CollisionShape2D"
			var rect_shape = RectangleShape2D.new()
			rect_shape.size = size
			shape.shape = rect_shape
			obstacle_body.add_child(shape)
			shape.owner = scene_root
			print("[SceneAnalyzer]   Created new obstacle collision for '%s'" % obstacle.name)

func _apply_spawn_points(spawn_points: Array, scene_root: Node2D, scale: Vector2, offset: Vector2):
	# Find or create SpawnPoints node
	var spawns = scene_root.get_node_or_null("SpawnPoints")
	if not spawns:
		spawns = Node2D.new()
		spawns.name = "SpawnPoints"
		scene_root.add_child(spawns)
		spawns.owner = scene_root

	for sp in spawn_points:
		var pos = Vector2(sp.x, sp.y) * scale + offset
		var existing = spawns.get_node_or_null(sp.name)
		if existing:
			existing.position = pos
			print("[SceneAnalyzer] Updated spawn '%s' at %s" % [sp.name, pos])
		else:
			# Create new spawn point marker
			var marker = Marker2D.new()
			marker.name = sp.name
			marker.position = pos
			spawns.add_child(marker)
			marker.owner = scene_root
			print("[SceneAnalyzer] Created spawn '%s' at %s" % [sp.name, pos])

func _apply_navigation_polygon(walkable_regions: Array, scene_root: Node2D, scale: Vector2, offset: Vector2, force: bool = false):
	# Find existing NavigationRegion2D
	var nav_region = scene_root.get_node_or_null("NavigationRegion2D")

	# If we already have a valid navigation polygon, only replace if forced
	if nav_region and nav_region.navigation_polygon and nav_region.navigation_polygon.get_polygon_count() > 0:
		if not force:
			print("[SceneAnalyzer] Keeping existing NavigationPolygon (use force_navigation=true to override)")
			return
		else:
			print("[SceneAnalyzer] Replacing existing NavigationPolygon with Vision API results")

	# Create NavigationRegion2D if it doesn't exist
	if not nav_region:
		nav_region = NavigationRegion2D.new()
		nav_region.name = "NavigationRegion2D"
		scene_root.add_child(nav_region)
		nav_region.owner = scene_root

	print("[SceneAnalyzer] Processing %d walkable regions" % walkable_regions.size())

	# Collect all rectangles as Rect2 for merging
	var rects: Array[Rect2] = []

	for region in walkable_regions:
		if region.has("type") and region.type == "rect":
			var x = region.x * scale.x + offset.x
			var y = region.y * scale.y + offset.y
			var w = region.width * scale.x
			var h = region.height * scale.y
			rects.append(Rect2(x, y, w, h))
			print("[SceneAnalyzer]   Rect region at (%d,%d) size %dx%d" % [x, y, w, h])

	if rects.is_empty():
		print("[SceneAnalyzer] No valid walkable regions to create navigation polygon")
		return

	# Create navigation polygon by directly adding vertices and polygons
	# This avoids the outline merging issues
	var nav_poly = NavigationPolygon.new()
	var all_vertices: PackedVector2Array = PackedVector2Array()
	var vertex_offset = 0

	for rect in rects:
		# Add 4 vertices for this rectangle
		var v0 = all_vertices.size()
		all_vertices.append(Vector2(rect.position.x, rect.position.y))
		all_vertices.append(Vector2(rect.position.x + rect.size.x, rect.position.y))
		all_vertices.append(Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y))
		all_vertices.append(Vector2(rect.position.x, rect.position.y + rect.size.y))

		# Add two triangles for this rectangle (counter-clockwise for navigation)
		nav_poly.add_polygon(PackedInt32Array([v0, v0 + 3, v0 + 2]))  # First triangle
		nav_poly.add_polygon(PackedInt32Array([v0, v0 + 2, v0 + 1]))  # Second triangle

	nav_poly.vertices = all_vertices

	if nav_poly.get_polygon_count() > 0:
		nav_region.navigation_polygon = nav_poly
		print("[SceneAnalyzer] Applied navigation polygon with %d polygons from %d rects" % [nav_poly.get_polygon_count(), rects.size()])
	else:
		print("[SceneAnalyzer] WARNING: Failed to create valid navigation mesh from analysis")

## Calculate approximate area of a polygon (for sorting)
func _polygon_area(points: PackedVector2Array) -> float:
	var area = 0.0
	var n = points.size()
	for i in range(n):
		var j = (i + 1) % n
		area += points[i].x * points[j].y
		area -= points[j].x * points[i].y
	return abs(area) / 2.0
