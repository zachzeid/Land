@tool
extends Node
class_name GeneratableAsset
## Attach this to any Node2D to make it generate an AI asset
## The asset will replace ColorRect children with generated textures
##
## Asset loading priority:
## 1. Pre-generated assets (res://assets/generated/) - fastest, offline
## 2. Runtime cache (user://generated_assets/) - previously generated
## 3. Runtime generation (API call) - slowest, requires network

const PregeneratedLoaderScript = preload("res://scripts/generation/pregenerated_loader.gd")

## Unique identifier for caching this asset
@export var asset_id: String = ""

## The prompt describing what to generate
@export_multiline var generation_prompt: String = ""

## Asset type category (for consistent styling)
@export_enum("building", "tree", "prop", "terrain", "character", "foundation", "shadow", "path_endpoint") var asset_type: String = "building"

## Seed for reproducible generation (-1 for random)
@export var generation_seed: int = -1

## Whether to auto-generate on ready if not cached
## Set to false when using AssetPreloader (preloader handles generation)
@export var auto_generate: bool = false

## Add shadow under buildings for visual grounding
@export var add_shadow: bool = true
## Shadow opacity (0-1)
@export_range(0.0, 1.0) var shadow_opacity: float = 0.3
## Shadow offset from building base
@export var shadow_offset: Vector2 = Vector2(0, 8)

## For terrain assets: automatically analyze scene after generation
## Uses Claude Vision to identify walkable paths, buildings, doors, etc.
@export var analyze_after_generation: bool = false

## The generated texture (applied at runtime)
var generated_texture: Texture2D = null
var sprite: Sprite2D = null
var shadow_sprite: Sprite2D = null
var is_loaded: bool = false

signal asset_ready(texture: Texture2D)
signal asset_failed(error: String)

func _ready():
	if Engine.is_editor_hint():
		return

	# Auto-generate ID from node path if not set
	if asset_id.is_empty():
		asset_id = _generate_asset_id()

	# For character assets, try to get appearance_prompt from parent NPC
	if asset_type == "character" and generation_prompt.is_empty():
		_try_get_parent_appearance_prompt()

	print("[GeneratableAsset] Ready: %s (prompt: %s...)" % [asset_id, generation_prompt.substr(0, 30)])

	# Connect to AssetGenerator
	if AssetGenerator:
		AssetGenerator.asset_generated.connect(_on_asset_generated)
		AssetGenerator.asset_failed.connect(_on_asset_failed)

		# Try to load from cache first
		get_tree().create_timer(0.1).timeout.connect(_try_load_cached)

func _generate_asset_id() -> String:
	# Generate a stable ID from the node's path in scene
	var path = get_path()
	return str(path).replace("/", "_").replace(":", "_").to_lower()

## Try to get appearance_prompt from parent NPC (for character assets)
func _try_get_parent_appearance_prompt():
	var parent = get_parent()
	if parent and "appearance_prompt" in parent:
		var parent_prompt = parent.appearance_prompt
		if parent_prompt != "":
			generation_prompt = parent_prompt
			print("[GeneratableAsset] Using parent's appearance_prompt for %s" % asset_id)

func _try_load_cached():
	# Priority 1: Check pre-generated assets (res://assets/generated/)
	if _try_load_pregenerated():
		return

	# Priority 2: Check runtime cache (user://generated_assets/)
	if AssetGenerator and AssetGenerator.asset_cache.has(asset_id):
		var path = AssetGenerator.asset_cache[asset_id]
		# Convert user:// path for file existence check
		var check_path = path
		if path.begins_with("user://"):
			check_path = ProjectSettings.globalize_path(path)

		if FileAccess.file_exists(check_path):
			var texture = _load_texture(path)
			if texture:
				print("[GeneratableAsset] Loaded from runtime cache: %s" % asset_id)
				_apply_texture(texture)
				return

	# Priority 3: Generate at runtime if auto_generate is on
	if auto_generate and not generation_prompt.is_empty():
		print("[GeneratableAsset] Auto-generating (no pre-generated or cached): %s" % asset_id)
		generate()

## Try to load from pre-generated assets (res://assets/generated/)
func _try_load_pregenerated() -> bool:
	# Determine the asset type for loading
	var load_type = asset_type
	if load_type == "tree":
		load_type = "prop"  # Trees are stored as props

	# Try to load using PregeneratedLoader
	if PregeneratedLoaderScript.has_asset(load_type, asset_id):
		var resource = PregeneratedLoaderScript.load_asset(load_type, asset_id)
		if resource is Texture2D:
			print("[GeneratableAsset] Loaded pre-generated: %s" % asset_id)
			_apply_texture(resource)
			return true

	# Also try loading by the base asset_id without suffix
	# e.g., "barrel_1" -> "barrel", "lamppost_3" -> "lamppost"
	var base_id = asset_id.rstrip("0123456789").rstrip("_")
	if base_id != asset_id and base_id != "" and PregeneratedLoaderScript.has_asset(load_type, base_id):
		var resource = PregeneratedLoaderScript.load_asset(load_type, base_id)
		if resource is Texture2D:
			print("[GeneratableAsset] Loaded pre-generated (base): %s -> %s" % [asset_id, base_id])
			_apply_texture(resource)
			return true

	return false

func _load_texture(path: String) -> Texture2D:
	var image = Image.new()
	# Convert user:// path to absolute path for loading
	var abs_path = path
	if path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)
	var err = image.load(abs_path)
	if err != OK:
		print("[GeneratableAsset] Failed to load texture from: %s" % abs_path)
		return null
	return ImageTexture.create_from_image(image)

## Manually trigger generation
func generate():
	if generation_prompt.is_empty():
		push_warning("[GeneratableAsset] No prompt set for %s" % name)
		return

	if not AssetGenerator:
		push_warning("[GeneratableAsset] AssetGenerator not available")
		return

	var bounds = _calculate_bounds()
	var options = {
		"width": int(bounds.size.x) if bounds.size.x > 0 else 128,
		"height": int(bounds.size.y) if bounds.size.y > 0 else 128,
		"seed": generation_seed if generation_seed >= 0 else -1
	}

	print("[GeneratableAsset] Generating: %s" % asset_id)
	AssetGenerator.generate_asset(asset_id, generation_prompt, options)

func _calculate_bounds() -> Rect2:
	var parent = get_parent()
	if not parent:
		return Rect2(0, 0, 128, 128)

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
		return Rect2(0, 0, 128, 128)

	return Rect2(min_pos, max_pos - min_pos)

## Create an elliptical shadow sprite to ground buildings on flat terrain
func _create_shadow_sprite(parent: Node, bounds: Rect2, asset_scale: float, sprite_pos: Vector2):
	if shadow_sprite == null:
		shadow_sprite = Sprite2D.new()
		shadow_sprite.name = "ShadowSprite"
		shadow_sprite.z_index = -1  # Render behind everything
		parent.add_child(shadow_sprite)
		parent.move_child(shadow_sprite, 0)  # First child

	# Create elliptical shadow texture
	var shadow_width = int(bounds.size.x * 0.8)
	var shadow_height = int(bounds.size.y * 0.3)  # Flattened ellipse
	shadow_sprite.texture = _create_ellipse_texture(shadow_width, shadow_height)

	# Position shadow at bottom of building with offset
	shadow_sprite.position = sprite_pos + shadow_offset + Vector2(0, bounds.size.y * 0.35)
	shadow_sprite.modulate.a = shadow_opacity
	shadow_sprite.visible = true

## Generate an elliptical gradient texture for shadows
func _create_ellipse_texture(width: int, height: int) -> ImageTexture:
	# Ensure minimum size
	width = max(width, 16)
	height = max(height, 8)

	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	var center = Vector2(width / 2.0, height / 2.0)
	var radius = Vector2(width / 2.0, height / 2.0)

	for y in range(height):
		for x in range(width):
			var pos = Vector2(x, y)
			var normalized = Vector2(
				(pos.x - center.x) / radius.x,
				(pos.y - center.y) / radius.y
			)
			var dist = normalized.length()

			if dist <= 1.0:
				# Soft gradient from center to edge
				var alpha = (1.0 - dist * dist) * 0.8
				image.set_pixel(x, y, Color(0, 0, 0, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(image)

func _apply_texture(texture: Texture2D):
	generated_texture = texture
	is_loaded = true

	var parent = get_parent()
	if not parent:
		print("[GeneratableAsset] ERROR: No parent for %s" % asset_id)
		return

	var bounds = _calculate_bounds()
	print("[GeneratableAsset] %s bounds: pos=%s size=%s" % [asset_id, bounds.position, bounds.size])

	# Calculate scale to FILL the bounds (may exceed slightly to maintain aspect ratio)
	var tex_size = Vector2(texture.get_width(), texture.get_height())
	var scale_x = bounds.size.x / tex_size.x
	var scale_y = bounds.size.y / tex_size.y
	# Use max instead of min to ensure the asset fills the placeholder area
	var final_scale = max(scale_x, scale_y)

	# Ensure minimum visible scale (assets shouldn't be smaller than 0.5x the texture)
	final_scale = max(final_scale, 0.15)

	# Position at center of bounds (Sprite2D is centered by default)
	var sprite_position = bounds.position + bounds.size / 2.0

	# Create shadow sprite first (so it renders behind the main sprite)
	if add_shadow and asset_type in ["building", "prop", "tree"]:
		_create_shadow_sprite(parent, bounds, final_scale, sprite_position)

	# Create or update main Sprite2D
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "GeneratedSprite"
		# Keep z_index at 0 (same as placeholders) - UI elements have higher z_index
		sprite.z_index = 0
		parent.add_child(sprite)
		# Move sprite to be after shadow but before other children
		if shadow_sprite:
			parent.move_child(sprite, shadow_sprite.get_index() + 1)
		else:
			parent.move_child(sprite, 0)

	sprite.texture = texture
	sprite.scale = Vector2(final_scale, final_scale)
	sprite.position = sprite_position
	sprite.visible = true

	# Hide ColorRect placeholders
	var hidden_count = 0
	for child in parent.get_children():
		if child is ColorRect:
			child.visible = false
			hidden_count += 1

	# For terrain assets, hide ALL ColorRect placeholders in the scene
	# since the terrain image has objects baked in
	if asset_type == "terrain":
		var scene_root = get_tree().current_scene
		if scene_root:
			hidden_count += _hide_all_placeholders(scene_root)

	print("[GeneratableAsset] Applied texture: %s (%dx%d) scaled to %.2f at %s (hid %d placeholders)" % [asset_id, texture.get_width(), texture.get_height(), final_scale, sprite.position, hidden_count])
	asset_ready.emit(texture)

func _on_asset_generated(id: String, texture: Texture2D):
	if id == asset_id:
		_apply_texture(texture)

		# For terrain assets, optionally trigger scene analysis
		if analyze_after_generation and asset_type == "terrain":
			_trigger_scene_analysis()

func _on_asset_failed(id: String, error: String):
	if id == asset_id:
		push_warning("[GeneratableAsset] Failed to generate %s: %s" % [asset_id, error])
		asset_failed.emit(error)

## Show placeholders again (useful for regenerating)
func show_placeholders():
	var parent = get_parent()
	if not parent:
		return

	for child in parent.get_children():
		if child is ColorRect:
			child.visible = true

	if sprite:
		sprite.visible = false
	if shadow_sprite:
		shadow_sprite.visible = false

## Hide placeholders and show texture
func show_texture():
	var parent = get_parent()
	if not parent:
		return

	for child in parent.get_children():
		if child is ColorRect:
			child.visible = false

	if sprite:
		sprite.visible = true
	if shadow_sprite:
		shadow_sprite.visible = true

## Clear and regenerate
func regenerate():
	if AssetGenerator:
		AssetGenerator.asset_cache.erase(asset_id)

	if sprite:
		sprite.queue_free()
		sprite = null

	if shadow_sprite:
		shadow_sprite.queue_free()
		shadow_sprite = null

	show_placeholders()
	is_loaded = false
	generate()

## Trigger scene layout application - uses GridLayout for known scenes, Vision API for others
func _trigger_scene_analysis():
	# Find the scene root
	var scene_root = get_parent()
	if scene_root:
		scene_root = scene_root.get_parent()

	if not scene_root or not scene_root is Node2D:
		print("[GeneratableAsset] Could not find scene root")
		return

	# Check if this is a known scene with a predefined grid layout
	var layout = _get_grid_layout_for_scene()
	if layout != null:
		print("[GeneratableAsset] Using GridLayout for: %s" % asset_id)
		var _waypoint_graph = GridLayout.apply_layout_to_scene(scene_root, layout)
		return

	# Fall back to Vision API for unknown scenes
	print("[GeneratableAsset] No GridLayout found, falling back to Vision API for: %s" % asset_id)
	_trigger_vision_api_analysis()

## Get the appropriate GridLayout for this scene (if one exists)
func _get_grid_layout_for_scene() -> Variant:
	# Check asset_id or scene name against known layouts
	var scene_name = asset_id.to_lower()

	if "thornhaven" in scene_name:
		return GridLayout.THORNHAVEN_LAYOUT

	# Add more layouts here as they're created:
	# if "forest" in scene_name:
	#     return GridLayout.FOREST_LAYOUT

	return null

## Trigger Vision API analysis (fallback for scenes without GridLayout)
func _trigger_vision_api_analysis():
	if not SceneAnalyzer:
		print("[GeneratableAsset] SceneAnalyzer not available")
		return

	if not SceneAnalyzer.is_available():
		print("[GeneratableAsset] SceneAnalyzer: No API key configured")
		return

	# Get the cached image path
	if not AssetGenerator or not AssetGenerator.asset_cache.has(asset_id):
		print("[GeneratableAsset] No cached image for analysis")
		return

	var image_path = AssetGenerator.asset_cache[asset_id]
	print("[GeneratableAsset] Triggering Vision API analysis for: %s" % asset_id)

	# Connect to analysis signals (one-shot)
	if not SceneAnalyzer.analysis_completed.is_connected(_on_scene_analysis_completed):
		SceneAnalyzer.analysis_completed.connect(_on_scene_analysis_completed)
	if not SceneAnalyzer.analysis_failed.is_connected(_on_scene_analysis_failed):
		SceneAnalyzer.analysis_failed.connect(_on_scene_analysis_failed)

	# Start analysis
	SceneAnalyzer.analyze_scene(image_path, generation_prompt)

func _on_scene_analysis_completed(result: Dictionary, image_size: Vector2):
	print("[GeneratableAsset] Scene analysis completed!")
	print("[GeneratableAsset] Found %d buildings, %d obstacles, %d spawn points" % [
		result.get("buildings", []).size(),
		result.get("obstacles", []).size(),
		result.get("spawn_points", []).size()
	])
	print("[GeneratableAsset] Image size: %s" % image_size)

	# Find the scene root (grandparent of this asset node)
	# Structure: SceneRoot > SceneBackground > Asset
	var scene_root = get_parent()
	if scene_root:
		scene_root = scene_root.get_parent()

	if scene_root and scene_root is Node2D:
		# Get the actual scene size from bounds (typically 1024x1024)
		var bounds = _calculate_bounds()
		var scene_size = bounds.size if bounds.size.x > 0 else Vector2(1024, 1024)
		print("[GeneratableAsset] Scene size: %s" % scene_size)

		# Apply analysis results with correct scaling
		# image_size = actual image dimensions (e.g., 256x256)
		# scene_size = scene display size (e.g., 1024x1024)
		SceneAnalyzer.apply_analysis_to_scene(result, scene_root, image_size, scene_size)
		print("[GeneratableAsset] Applied analysis to scene")
	else:
		print("[GeneratableAsset] Could not find scene root to apply analysis")

	# Disconnect signals
	if SceneAnalyzer.analysis_completed.is_connected(_on_scene_analysis_completed):
		SceneAnalyzer.analysis_completed.disconnect(_on_scene_analysis_completed)
	if SceneAnalyzer.analysis_failed.is_connected(_on_scene_analysis_failed):
		SceneAnalyzer.analysis_failed.disconnect(_on_scene_analysis_failed)

func _on_scene_analysis_failed(error: String):
	print("[GeneratableAsset] Scene analysis failed: %s" % error)

	# Disconnect signals
	if SceneAnalyzer.analysis_completed.is_connected(_on_scene_analysis_completed):
		SceneAnalyzer.analysis_completed.disconnect(_on_scene_analysis_completed)
	if SceneAnalyzer.analysis_failed.is_connected(_on_scene_analysis_failed):
		SceneAnalyzer.analysis_failed.disconnect(_on_scene_analysis_failed)

## Recursively hide all ColorRect placeholders in the scene tree
## Used when terrain assets load (terrain has objects baked in)
func _hide_all_placeholders(node: Node) -> int:
	var count = 0

	for child in node.get_children():
		# Hide ColorRect placeholders
		if child is ColorRect:
			child.visible = false
			count += 1

		# Also hide any GeneratableAsset sprites that aren't terrain
		# (terrain bakes these into the image)
		if child is Node:
			var ga = child.get_node_or_null("GeneratableAsset")
			if ga and ga != self and ga.asset_type != "terrain":
				# Hide this asset's sprite if it exists
				if ga.sprite:
					ga.sprite.visible = false
				# Hide its placeholders too
				for grandchild in child.get_children():
					if grandchild is ColorRect:
						grandchild.visible = false
						count += 1

		# Recurse into children
		count += _hide_all_placeholders(child)

	return count
