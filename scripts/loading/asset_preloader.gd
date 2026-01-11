extends Node
class_name AssetPreloaderClass
## AssetPreloader - Preloads AI-generated assets before gameplay starts
## Shows loading progress and ensures all assets are ready before scene becomes interactive

signal preload_started(total_assets: int)
signal preload_progress(loaded: int, total: int, current_asset: String)
signal preload_completed(success_count: int, fail_count: int)
signal asset_loaded(asset_id: String)
signal asset_failed(asset_id: String, error: String)

## Loading state
var is_loading: bool = false
var total_assets: int = 0
var loaded_assets: int = 0
var failed_assets: int = 0
var pending_asset_ids: Array[String] = []
var current_loading_asset: String = ""

## Loading UI
var loading_screen: CanvasLayer = null
var progress_bar: ProgressBar = null
var status_label: Label = null
var asset_label: Label = null

## Timeout for individual asset generation (ms)
const ASSET_TIMEOUT_MS = 90000  # 90 seconds per asset

func _ready():
	_create_loading_ui()

	# Connect to AssetGenerator signals
	if AssetGenerator:
		AssetGenerator.asset_generated.connect(_on_asset_generated)
		AssetGenerator.asset_failed.connect(_on_asset_failed)

	# Connect to SceneManager for scene transitions
	if SceneManager:
		SceneManager.scene_transition_started.connect(_on_scene_transition_started)

	print("[AssetPreloader] Initialized")

	# Defer initial scene preload to allow scene tree to be ready
	call_deferred("_preload_initial_scene")

## Preload assets for the initial scene (when game first starts)
func _preload_initial_scene():
	# Wait a couple frames for everything to initialize
	await get_tree().process_frame
	await get_tree().process_frame

	var scene_root = get_tree().current_scene
	if not scene_root:
		print("[AssetPreloader] No initial scene to preload")
		return

	print("[AssetPreloader] Checking initial scene for assets...")

	# Check if any assets need generation
	if are_scene_assets_ready(scene_root):
		print("[AssetPreloader] Initial scene assets all cached")
		# Still trigger cache loads for each asset
		var assets = _find_generatable_assets(scene_root)
		for asset in assets:
			asset._try_load_cached()
		return

	# Preload any missing assets
	preload_scene_assets(scene_root)

func _create_loading_ui():
	# Create loading screen as CanvasLayer (above everything)
	loading_screen = CanvasLayer.new()
	loading_screen.name = "LoadingScreen"
	loading_screen.layer = 99  # Just below fade overlay
	loading_screen.visible = false
	add_child(loading_screen)

	# Background panel
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.1, 0.1, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_screen.add_child(bg)

	# Container for centered content
	var container = VBoxContainer.new()
	container.name = "Container"
	container.set_anchors_preset(Control.PRESET_CENTER)
	container.custom_minimum_size = Vector2(500, 200)
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	loading_screen.add_child(container)

	# Title
	var title = Label.new()
	title.text = "Loading Assets..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	container.add_child(title)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	container.add_child(spacer)

	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.custom_minimum_size = Vector2(400, 30)
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_bar.show_percentage = true
	container.add_child(progress_bar)

	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 15)
	container.add_child(spacer2)

	# Status label
	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "Checking cached assets..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 18)
	container.add_child(status_label)

	# Asset label (current asset being loaded)
	asset_label = Label.new()
	asset_label.name = "AssetLabel"
	asset_label.text = ""
	asset_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	asset_label.add_theme_font_size_override("font_size", 14)
	asset_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	container.add_child(asset_label)

func _on_scene_transition_started(_from: String, to: String):
	print("[AssetPreloader] Scene transition started: -> %s" % to)
	# Preloading is handled after scene loads via preload_scene_assets()

## Preload all GeneratableAsset nodes in a scene
## Call this before showing the scene
func preload_scene_assets(scene_root: Node) -> void:
	if is_loading:
		push_warning("[AssetPreloader] Already loading, ignoring new request")
		return

	# Find all GeneratableAsset nodes
	var assets = _find_generatable_assets(scene_root)
	if assets.is_empty():
		print("[AssetPreloader] No assets to preload")
		preload_completed.emit(0, 0)
		return

	# Check which assets need generation vs already cached
	var assets_to_generate: Array[Node] = []
	var cached_count = 0

	for asset in assets:
		var asset_id = asset.asset_id if asset.asset_id != "" else _generate_asset_id(asset)
		if _is_asset_cached(asset_id):
			cached_count += 1
			# Trigger load from cache
			asset._try_load_cached()
		else:
			assets_to_generate.append(asset)

	print("[AssetPreloader] Found %d assets: %d cached, %d need generation" % [
		assets.size(), cached_count, assets_to_generate.size()
	])

	if assets_to_generate.is_empty():
		print("[AssetPreloader] All assets cached, skipping loading screen")
		preload_completed.emit(cached_count, 0)
		return

	# Start loading
	_start_loading(assets_to_generate)

func _find_generatable_assets(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	_find_assets_recursive(root, result)
	return result

func _find_assets_recursive(node: Node, result: Array[Node]):
	if node is GeneratableAsset:
		result.append(node)

	for child in node.get_children():
		_find_assets_recursive(child, result)

func _generate_asset_id(asset: Node) -> String:
	var path = asset.get_path()
	return str(path).replace("/", "_").replace(":", "_").to_lower()

func _is_asset_cached(asset_id: String) -> bool:
	# Priority 1: Check pre-generated assets (res://assets/generated/)
	if _has_pregenerated_asset(asset_id):
		return true

	# Priority 2: Check runtime cache (user://generated_assets/)
	if not AssetGenerator:
		return false

	if not AssetGenerator.asset_cache.has(asset_id):
		return false

	var path = AssetGenerator.asset_cache[asset_id]
	var check_path = path
	if path.begins_with("user://"):
		check_path = ProjectSettings.globalize_path(path)

	return FileAccess.file_exists(check_path)

## Check if a pre-generated asset exists for the given ID
func _has_pregenerated_asset(asset_id: String) -> bool:
	const PregeneratedLoader = preload("res://scripts/generation/pregenerated_loader.gd")

	# Check buildings
	if PregeneratedLoader.has_building(asset_id):
		return true

	# Check props (including trees)
	if PregeneratedLoader.has_prop(asset_id):
		return true

	# Check with base ID (strip trailing numbers and underscore: barrel_1 -> barrel)
	var base_id = asset_id.rstrip("0123456789").rstrip("_")
	if base_id != asset_id and base_id != "":
		if PregeneratedLoader.has_building(base_id):
			return true
		if PregeneratedLoader.has_prop(base_id):
			return true

	return false

func _start_loading(assets: Array[Node]):
	is_loading = true
	total_assets = assets.size()
	loaded_assets = 0
	failed_assets = 0
	pending_asset_ids.clear()

	# Show loading screen
	loading_screen.visible = true
	_update_progress()

	preload_started.emit(total_assets)

	# Queue all assets for generation
	for asset in assets:
		var asset_id = asset.asset_id if asset.asset_id != "" else _generate_asset_id(asset)
		pending_asset_ids.append(asset_id)

		# Disable auto_generate since we're handling it
		asset.auto_generate = false

		# Trigger generation
		print("[AssetPreloader] Queuing: %s" % asset_id)
		current_loading_asset = asset_id
		_update_progress()
		asset.generate()

	status_label.text = "Generating %d assets..." % total_assets

func _on_asset_generated(asset_id: String, _texture: Texture2D):
	if not is_loading:
		return

	if asset_id in pending_asset_ids:
		pending_asset_ids.erase(asset_id)
		loaded_assets += 1

		print("[AssetPreloader] Loaded: %s (%d/%d)" % [asset_id, loaded_assets, total_assets])

		asset_loaded.emit(asset_id)
		preload_progress.emit(loaded_assets + failed_assets, total_assets, asset_id)
		_update_progress()

		_check_completion()

func _on_asset_failed(asset_id: String, error: String):
	if not is_loading:
		return

	if asset_id in pending_asset_ids:
		pending_asset_ids.erase(asset_id)
		failed_assets += 1

		print("[AssetPreloader] Failed: %s - %s (%d/%d)" % [asset_id, error, loaded_assets + failed_assets, total_assets])

		asset_failed.emit(asset_id, error)
		preload_progress.emit(loaded_assets + failed_assets, total_assets, asset_id)
		_update_progress()

		_check_completion()

func _update_progress():
	var completed = loaded_assets + failed_assets
	var percent = (float(completed) / float(total_assets)) * 100.0 if total_assets > 0 else 0

	progress_bar.value = percent

	if current_loading_asset != "":
		asset_label.text = current_loading_asset

	if failed_assets > 0:
		status_label.text = "Loaded: %d  |  Failed: %d  |  Remaining: %d" % [
			loaded_assets, failed_assets, pending_asset_ids.size()
		]
	else:
		status_label.text = "Loaded: %d  |  Remaining: %d" % [
			loaded_assets, pending_asset_ids.size()
		]

func _check_completion():
	if pending_asset_ids.is_empty():
		_complete_loading()

func _complete_loading():
	is_loading = false

	print("[AssetPreloader] ========== Preload Complete ==========")
	print("[AssetPreloader] Success: %d  |  Failed: %d" % [loaded_assets, failed_assets])

	# Update UI
	status_label.text = "Complete! Loaded %d assets" % loaded_assets
	if failed_assets > 0:
		status_label.text += " (%d failed)" % failed_assets

	progress_bar.value = 100

	# Short delay before hiding loading screen
	await get_tree().create_timer(0.5).timeout

	loading_screen.visible = false
	preload_completed.emit(loaded_assets, failed_assets)

## Check if all scene assets are ready (cached)
func are_scene_assets_ready(scene_root: Node) -> bool:
	var assets = _find_generatable_assets(scene_root)
	for asset in assets:
		var asset_id = asset.asset_id if asset.asset_id != "" else _generate_asset_id(asset)
		if not _is_asset_cached(asset_id):
			return false
	return true

## Get loading status as dictionary
func get_status() -> Dictionary:
	return {
		"is_loading": is_loading,
		"total": total_assets,
		"loaded": loaded_assets,
		"failed": failed_assets,
		"pending": pending_asset_ids.size()
	}

## Force show loading screen (for manual control)
func show_loading_screen():
	loading_screen.visible = true

## Force hide loading screen
func hide_loading_screen():
	loading_screen.visible = false
