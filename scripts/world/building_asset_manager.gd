extends Node
class_name BuildingAssetManager
## Discovers and manages all GeneratableAsset nodes in the scene
## Provides batch operations for generation and status tracking

@export var auto_generate_missing: bool = false

var generatable_assets: Array = []  # Array of GeneratableAsset nodes

signal all_assets_loaded
signal generation_progress(completed: int, total: int)

func _ready():
	# Discover all GeneratableAsset nodes after scene is ready
	call_deferred("_discover_assets")

func _unhandled_key_input(event: InputEvent):
	if not event.pressed:
		return

	match event.keycode:
		KEY_F10:
			print("[BuildingAssetManager] F10 pressed - generating missing assets")
			print_status()
			generate_missing()
			get_viewport().set_input_as_handled()
		KEY_F11:
			print("[BuildingAssetManager] F11 pressed - showing status")
			print_status()
			get_viewport().set_input_as_handled()
		KEY_F12:
			print("[BuildingAssetManager] F12 pressed - regenerating all assets")
			regenerate_all()
			get_viewport().set_input_as_handled()

func _discover_assets():
	generatable_assets.clear()
	_find_generatable_assets(get_tree().root)
	print("[BuildingAssetManager] Discovered %d generatable assets" % generatable_assets.size())

	if auto_generate_missing:
		generate_missing()

func _find_generatable_assets(node: Node):
	for child in node.get_children():
		if child.has_method("generate") and child.has_method("regenerate"):
			# Duck-typing check for GeneratableAsset
			if "asset_id" in child and "generation_prompt" in child:
				generatable_assets.append(child)
		_find_generatable_assets(child)

## Generate all assets that aren't cached
func generate_missing():
	var missing = get_missing_assets()
	print("[BuildingAssetManager] Generating %d missing assets..." % missing.size())

	for asset in missing:
		asset.generate()

## Generate ALL assets (regenerate even cached ones)
func regenerate_all():
	print("[BuildingAssetManager] Regenerating all %d assets..." % generatable_assets.size())

	for asset in generatable_assets:
		asset.regenerate()

## Get list of assets that aren't in cache
func get_missing_assets() -> Array:
	var missing: Array = []

	for asset in generatable_assets:
		if not asset.is_loaded and not AssetGenerator.asset_cache.has(asset.asset_id):
			missing.append(asset)

	return missing

## Get status summary
func get_status() -> Dictionary:
	var total = generatable_assets.size()
	var loaded = 0
	var cached = 0

	for asset in generatable_assets:
		if asset.is_loaded:
			loaded += 1
		if AssetGenerator.asset_cache.has(asset.asset_id):
			cached += 1

	return {
		"total": total,
		"loaded": loaded,
		"cached": cached,
		"missing": total - cached
	}

## Show all placeholders (hide textures)
func show_all_placeholders():
	for asset in generatable_assets:
		asset.show_placeholders()

## Show all textures (hide placeholders)
func show_all_textures():
	for asset in generatable_assets:
		asset.show_texture()

## Print status to console
func print_status():
	var status = get_status()
	print("[BuildingAssetManager] Status:")
	print("  Total assets: %d" % status.total)
	print("  Loaded: %d" % status.loaded)
	print("  Cached: %d" % status.cached)
	print("  Missing: %d" % status.missing)

	for asset in generatable_assets:
		var state = "loaded" if asset.is_loaded else ("cached" if AssetGenerator.asset_cache.has(asset.asset_id) else "missing")
		var prompt_preview = asset.generation_prompt.substr(0, 40) if asset.generation_prompt.length() > 40 else asset.generation_prompt
		print("  - %s [%s]: %s..." % [asset.asset_id, state, prompt_preview])
