extends Node
class_name AssetGeneratorManager
## AssetGeneratorManager - Manages AI image generation for game assets
## Handles backend selection, caching, and placeholder replacement

const MockGeneratorScript = preload("res://scripts/generation/mock_generator.gd")
const PixelLabGeneratorScript = preload("res://scripts/generation/pixellab_generator.gd")
const LocalSDGeneratorScript = preload("res://scripts/generation/local_sd_generator.gd")
const WorldSettingsScript = preload("res://scripts/world/world_settings.gd")

## Generation request structure
class GenerationRequest:
	var id: String
	var prompt: String
	var negative_prompt: String = ""
	var width: int = 512
	var height: int = 512
	var style_preset: String = ""
	var seed: int = -1

	func _init(p_prompt: String = ""):
		id = str(Time.get_ticks_usec()) + "_" + str(randi())
		prompt = p_prompt

signal asset_generated(asset_id: String, texture: Texture2D)
signal asset_failed(asset_id: String, error: String)
signal batch_completed(batch_id: String, results: Dictionary)

## Available backends
var backends: Dictionary = {}
var active_backend = null  # ImageGenerator subclass

## Asset cache (asset_id -> texture path)
var asset_cache: Dictionary = {}
var cache_file_path: String = "user://asset_cache.json"

## Pending generations
var pending: Dictionary = {}  # request_id -> {asset_id, callback}

## Style configuration for consistent generation
@export var default_style: String = "digital_illustration"
@export var default_width: int = 128
@export var default_height: int = 128

## World settings for prompt building (loaded per-zone)
var world_settings: Resource = null  # WorldSettings resource
const DEFAULT_WORLD_SETTINGS_PATH = "res://resources/world_settings/thornhaven.tres"

## Fallback style if no world settings loaded
const FALLBACK_STYLE = "medieval fantasy village, hand-painted style, warm earthy colors, "

func _ready():
	_setup_backends()
	_load_cache()
	_load_default_world_settings()

func _load_default_world_settings():
	if ResourceLoader.exists(DEFAULT_WORLD_SETTINGS_PATH):
		world_settings = load(DEFAULT_WORLD_SETTINGS_PATH)
		if world_settings:
			print("[AssetGen] Loaded world settings: %s" % DEFAULT_WORLD_SETTINGS_PATH)
		else:
			push_warning("[AssetGen] Failed to load world settings")
	else:
		push_warning("[AssetGen] World settings not found: %s" % DEFAULT_WORLD_SETTINGS_PATH)

## Set world settings for current zone
func set_world_settings(settings: Resource) -> void:
	world_settings = settings
	print("[AssetGen] World settings updated")

## Load world settings from path
func load_world_settings(path: String) -> bool:
	if ResourceLoader.exists(path):
		var settings = load(path)
		if settings:
			world_settings = settings
			print("[AssetGen] Loaded world settings: %s" % path)
			return true
	push_warning("[AssetGen] Failed to load world settings: %s" % path)
	return false

## Build complete prompt using world settings
func _build_full_prompt(base_prompt: String, options: Dictionary = {}) -> String:
	if world_settings and world_settings.has_method("build_prompt"):
		var asset_type = options.get("asset_type", "prop")
		var size = options.get("size", 2)  # MEDIUM = 2
		return world_settings.build_prompt(asset_type, base_prompt, size)
	else:
		return FALLBACK_STYLE + base_prompt

## Build prompt for specific asset type with custom type name
func build_typed_prompt(asset_type: String, type_name: String, details: String, size: int = 2) -> String:
	if world_settings and world_settings.has_method("build_prompt_custom"):
		return world_settings.build_prompt_custom(asset_type, type_name, details, size)
	else:
		return FALLBACK_STYLE + details

func _unhandled_key_input(event: InputEvent):
	if not event.pressed:
		return

	match event.keycode:
		KEY_F9:
			print("[AssetGen] F9 pressed - testing generation")
			test_generate()
			get_viewport().set_input_as_handled()
		# F10, F11, F12 are now handled by BuildingAssetManager for data-driven asset generation

func _setup_backends():
	print("[AssetGen] Setting up backends...")

	# Mock generator (always available, for testing)
	var mock = MockGeneratorScript.new()
	mock.name = "MockGenerator"
	add_child(mock)
	backends["mock"] = mock
	mock.generation_completed.connect(_on_generation_completed)
	mock.generation_failed.connect(_on_generation_failed)
	print("[AssetGen] Mock generator added")

	# PixelLab (cloud - pixel art focused)
	var pixellab = PixelLabGeneratorScript.new()
	pixellab.name = "PixelLabGenerator"
	add_child(pixellab)
	backends["pixellab"] = pixellab
	pixellab.generation_completed.connect(_on_generation_completed)
	pixellab.generation_failed.connect(_on_generation_failed)
	# Note: is_available() check happens in _select_best_backend after _ready runs

	# Local SD (when available)
	var local_sd = LocalSDGeneratorScript.new()
	local_sd.name = "LocalSDGenerator"
	add_child(local_sd)
	backends["local"] = local_sd
	local_sd.generation_completed.connect(_on_generation_completed)
	local_sd.generation_failed.connect(_on_generation_failed)

	# Defer backend selection to allow child _ready() functions to run first
	call_deferred("_select_best_backend")
	call_deferred("_print_init_status")

func _print_init_status():
	print("[AssetGen] PixelLab available: %s" % backends["pixellab"].is_available())
	print("[AssetGen] Local SD available: %s" % backends["local"].is_available())
	print("[AssetGen] Initialized. Active backend: %s" % (active_backend.get_backend_name() if active_backend else "None"))

func _select_best_backend():
	# Prefer local if available (free, faster iteration)
	if backends["local"].is_available():
		active_backend = backends["local"]
		return

	# Fall back to PixelLab (cloud - pixel art focused)
	if backends["pixellab"].is_available():
		active_backend = backends["pixellab"]
		return

	# Fall back to mock (always available, for development)
	active_backend = backends["mock"]
	push_warning("[AssetGen] Using mock backend - no real generation available")

## Set preferred backend explicitly
func set_backend(backend_name: String) -> bool:
	if backends.has(backend_name) and backends[backend_name].is_available():
		active_backend = backends[backend_name]
		print("[AssetGen] Switched to: %s" % active_backend.get_backend_name())
		return true
	return false

## Generate a single asset
func generate_asset(asset_id: String, prompt: String, options: Dictionary = {}) -> bool:
	if active_backend == null:
		asset_failed.emit(asset_id, "No backend available")
		return false

	# Check cache first
	if asset_cache.has(asset_id):
		var cached_path = asset_cache[asset_id]
		var abs_cached_path = cached_path
		if cached_path.begins_with("user://"):
			abs_cached_path = ProjectSettings.globalize_path(cached_path)

		if FileAccess.file_exists(abs_cached_path):
			var texture = _load_generated_texture(cached_path)
			if texture:
				print("[AssetGen] Loaded from cache: %s" % asset_id)
				asset_generated.emit(asset_id, texture)
				return true

	# Build request with world settings or fallback
	var full_prompt = _build_full_prompt(prompt, options)
	var request = GenerationRequest.new(full_prompt)
	request.style_preset = options.get("style", default_style)
	request.width = options.get("width", default_width)
	request.height = options.get("height", default_height)
	request.negative_prompt = options.get("negative", "blurry, low quality, modern, sci-fi")
	request.seed = options.get("seed", -1)

	# Track pending request
	var req_id = active_backend.generate(request)
	if req_id != "":
		pending[req_id] = {"asset_id": asset_id, "options": options}
		return true

	return false

## Generate building asset with standard options
func generate_building(building_id: String, building_type: String, seed: int = -1) -> bool:
	var prompts = {
		"shop": "small wooden shop building with shingled roof, front door, display window",
		"tavern": "two-story tavern with chimney, wooden sign hanging outside",
		"blacksmith": "stone smithy with forge chimney, anvil visible, dark interior",
		"house": "small cottage with thatched roof, single door, small windows",
		"well": "stone well with wooden bucket and rope, circular stone base",
		"gate": "wooden village gate with stone posts, arched entrance",
		"tree": "large oak tree with thick trunk and full canopy",
	}

	var prompt = prompts.get(building_type, "medieval building")
	return generate_asset(building_id, prompt, {"seed": seed, "width": 128, "height": 128})

## Generate a batch of consistent assets
func generate_batch(batch_id: String, assets: Array[Dictionary], base_seed: int = -1) -> bool:
	if active_backend == null:
		return false

	var seed = base_seed if base_seed >= 0 else randi()
	var batch_pending = []

	for i in range(assets.size()):
		var asset = assets[i]
		var options = asset.get("options", {}).duplicate()
		options["seed"] = seed + i  # Related seeds for consistency

		if generate_asset(asset.id, asset.prompt, options):
			batch_pending.append(asset.id)

	# Track batch
	if batch_pending.size() > 0:
		pending["batch_" + batch_id] = {"ids": batch_pending, "results": {}}
		return true

	return false

## Replace ColorRect placeholders with generated sprites
func replace_placeholder(node: ColorRect, asset_id: String, prompt: String) -> void:
	# Check if we have cached texture
	if asset_cache.has(asset_id):
		var texture = _load_generated_texture(asset_cache[asset_id])
		if texture:
			_apply_texture_to_placeholder(node, texture)
			return

	# Generate new asset
	var options = {
		"width": int(node.size.x) if node.size.x > 0 else default_width,
		"height": int(node.size.y) if node.size.y > 0 else default_height,
	}

	# Store node reference for callback
	node.set_meta("pending_asset_id", asset_id)

	if generate_asset(asset_id, prompt, options):
		# Connect one-shot callback
		var callback = func(id: String, tex: Texture2D):
			if node.get_meta("pending_asset_id", "") == id:
				_apply_texture_to_placeholder(node, tex)
		asset_generated.connect(callback, CONNECT_ONE_SHOT)

func _apply_texture_to_placeholder(placeholder: ColorRect, texture: Texture2D) -> void:
	# Create TextureRect as sibling
	var tex_rect = TextureRect.new()
	tex_rect.texture = texture
	tex_rect.position = placeholder.position
	tex_rect.size = placeholder.size
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var parent = placeholder.get_parent()
	parent.add_child(tex_rect)

	# Hide placeholder (don't remove in case we need fallback)
	placeholder.visible = false

func _on_generation_completed(request_id: String, image_path: String):
	if not pending.has(request_id):
		return

	var info = pending[request_id]
	var asset_id = info.asset_id

	# Update cache
	asset_cache[asset_id] = image_path
	_save_cache()

	# Load and emit texture
	var texture = _load_generated_texture(image_path)
	if texture:
		asset_generated.emit(asset_id, texture)
		print("[AssetGen] Generated: %s -> %s" % [asset_id, image_path])
	else:
		asset_failed.emit(asset_id, "Failed to load generated image")

	pending.erase(request_id)

func _on_generation_failed(request_id: String, error: String):
	if not pending.has(request_id):
		return

	var asset_id = pending[request_id].asset_id
	asset_failed.emit(asset_id, error)
	push_warning("[AssetGen] Generation failed for %s: %s" % [asset_id, error])
	pending.erase(request_id)

## Load texture from generated file
func _load_generated_texture(path: String) -> Texture2D:
	var abs_path = path
	if path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)

	if not FileAccess.file_exists(abs_path):
		print("[AssetGen] Texture file not found: %s" % abs_path)
		return null

	var image = Image.new()
	var err = image.load(abs_path)
	if err != OK:
		print("[AssetGen] Failed to load image: %s" % abs_path)
		return null

	return ImageTexture.create_from_image(image)

## Cache management
func _load_cache():
	var abs_cache_path = ProjectSettings.globalize_path(cache_file_path)
	if FileAccess.file_exists(abs_cache_path):
		var file = FileAccess.open(abs_cache_path, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			asset_cache = json.data
		file.close()
	print("[AssetGen] Loaded %d cached assets" % asset_cache.size())
	for key in asset_cache.keys():
		print("[AssetGen]   - %s: %s" % [key, asset_cache[key]])

func _save_cache():
	var file = FileAccess.open(cache_file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(asset_cache))
	file.close()

func clear_cache():
	asset_cache.clear()
	_save_cache()

## Get current backend info
func get_backend_info() -> Dictionary:
	if active_backend == null:
		return {"name": "None", "available": false}
	return {
		"name": active_backend.get_backend_name(),
		"available": active_backend.is_available()
	}

## Test generation - call from debug console or script
func test_generate(prompt: String = "isometric 2D game building, medieval shop, 3/4 view") -> void:
	print("[AssetGen] Testing generation with: %s" % prompt)

	if active_backend == null:
		print("[AssetGen] ERROR: No backend available!")
		return

	print("[AssetGen] Backend: %s" % active_backend.get_backend_name())

	var test_id = "test_" + str(Time.get_ticks_msec())

	# Connect temporary listener
	var on_complete = func(id: String, tex: Texture2D):
		if id == test_id:
			print("[AssetGen] TEST SUCCESS! Generated texture: %dx%d" % [tex.get_width(), tex.get_height()])

	var on_fail = func(id: String, error: String):
		if id == test_id:
			print("[AssetGen] TEST FAILED: %s" % error)

	asset_generated.connect(on_complete, CONNECT_ONE_SHOT)
	asset_failed.connect(on_fail, CONNECT_ONE_SHOT)

	generate_asset(test_id, prompt)

## DEPRECATED: Use BuildingAssetManager.generate_missing() instead
## Building assets are now defined via GeneratableAsset nodes in the scene tree
