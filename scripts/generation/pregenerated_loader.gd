class_name PregeneratedLoader
extends RefCounted
## PregeneratedLoader - Loads pre-generated assets from res://assets/generated/
## Assets are generated using PixelLab MCP tools during development

const AssetManifestScript = preload("res://scripts/generation/asset_manifest.gd")

## Base path for pre-generated assets
const BASE_PATH := "res://assets/generated"

## ===== BUILDING LOADING =====

## Load a pre-generated building texture
static func load_building(building_id: String) -> Texture2D:
	var path = "%s/buildings/%s.png" % [BASE_PATH, building_id]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## Check if a building has been pre-generated
static func has_building(building_id: String) -> bool:
	var path = "%s/buildings/%s.png" % [BASE_PATH, building_id]
	return ResourceLoader.exists(path)

## ===== PROP LOADING =====

## Load a pre-generated prop texture
static func load_prop(prop_id: String) -> Texture2D:
	var path = "%s/props/%s.png" % [BASE_PATH, prop_id]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## Check if a prop has been pre-generated
static func has_prop(prop_id: String) -> bool:
	var path = "%s/props/%s.png" % [BASE_PATH, prop_id]
	return ResourceLoader.exists(path)

## ===== CHARACTER LOADING =====

## Load pre-generated character SpriteFrames
static func load_character(character_id: String) -> SpriteFrames:
	var path = "%s/characters/%s/sprite_frames.tres" % [BASE_PATH, character_id]
	if ResourceLoader.exists(path):
		return load(path) as SpriteFrames
	return null

## Check if a character has been pre-generated
static func has_character(character_id: String) -> bool:
	var path = "%s/characters/%s/sprite_frames.tres" % [BASE_PATH, character_id]
	return ResourceLoader.exists(path)

## Load a specific character rotation image
static func load_character_rotation(character_id: String, direction: String) -> Texture2D:
	var path = "%s/characters/%s/rotations/%s.png" % [BASE_PATH, character_id, direction]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## ===== FOUNDATION LOADING =====

## Load a pre-generated foundation texture
static func load_foundation(foundation_id: String) -> Texture2D:
	var path = "%s/foundations/%s.png" % [BASE_PATH, foundation_id]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## Check if a foundation has been pre-generated
static func has_foundation(foundation_id: String) -> bool:
	var path = "%s/foundations/%s.png" % [BASE_PATH, foundation_id]
	return ResourceLoader.exists(path)

## ===== SHADOW LOADING =====

## Load a pre-generated shadow texture
static func load_shadow(shadow_id: String) -> Texture2D:
	var path = "%s/shadows/%s.png" % [BASE_PATH, shadow_id]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## Check if a shadow has been pre-generated
static func has_shadow(shadow_id: String) -> bool:
	var path = "%s/shadows/%s.png" % [BASE_PATH, shadow_id]
	return ResourceLoader.exists(path)

## ===== PATH ENDPOINT LOADING =====

## Load a pre-generated path endpoint texture
static func load_path_endpoint(endpoint_id: String) -> Texture2D:
	var path = "%s/path_endpoints/%s.png" % [BASE_PATH, endpoint_id]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## Check if a path endpoint has been pre-generated
static func has_path_endpoint(endpoint_id: String) -> bool:
	var path = "%s/path_endpoints/%s.png" % [BASE_PATH, endpoint_id]
	return ResourceLoader.exists(path)

## ===== TILESET LOADING =====

## Load a pre-generated tileset image
static func load_tileset_image(tileset_id: String) -> Texture2D:
	var path = "%s/tilesets/%s/tileset.png" % [BASE_PATH, tileset_id]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## Load tileset metadata (tile mappings, etc.)
static func load_tileset_metadata(tileset_id: String) -> Dictionary:
	var path = "%s/tilesets/%s/metadata.json" % [BASE_PATH, tileset_id]
	if not FileAccess.file_exists(path):
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}

	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}

	return json.data

## Check if a tileset has been pre-generated
static func has_tileset(tileset_id: String) -> bool:
	var path = "%s/tilesets/%s/tileset.png" % [BASE_PATH, tileset_id]
	return ResourceLoader.exists(path)

## ===== GENERIC LOADING =====

## Load any pre-generated asset by type and ID
static func load_asset(asset_type: String, asset_id: String) -> Resource:
	match asset_type:
		"building":
			return load_building(asset_id)
		"prop":
			return load_prop(asset_id)
		"character":
			return load_character(asset_id)
		"tileset":
			return load_tileset_image(asset_id)
		"foundation":
			return load_foundation(asset_id)
		"shadow":
			return load_shadow(asset_id)
		"path_endpoint":
			return load_path_endpoint(asset_id)
		_:
			var path = "%s/misc/%s.png" % [BASE_PATH, asset_id]
			if ResourceLoader.exists(path):
				return load(path)
			return null

## Check if any pre-generated asset exists
static func has_asset(asset_type: String, asset_id: String) -> bool:
	match asset_type:
		"building":
			return has_building(asset_id)
		"prop":
			return has_prop(asset_id)
		"character":
			return has_character(asset_id)
		"tileset":
			return has_tileset(asset_id)
		"foundation":
			return has_foundation(asset_id)
		"shadow":
			return has_shadow(asset_id)
		"path_endpoint":
			return has_path_endpoint(asset_id)
		_:
			var path = "%s/misc/%s.png" % [BASE_PATH, asset_id]
			return ResourceLoader.exists(path)

## ===== ASSET TYPE DETECTION =====

## Try to determine asset type from ID
static func detect_asset_type(asset_id: String) -> String:
	# Check manifest definitions
	if AssetManifestScript.BUILDINGS.has(asset_id):
		return "building"
	if AssetManifestScript.PROPS.has(asset_id):
		return "prop"
	if AssetManifestScript.CHARACTERS.has(asset_id):
		return "character"
	if AssetManifestScript.TILESETS.has(asset_id):
		return "tileset"

	# Check file existence as fallback
	if has_building(asset_id):
		return "building"
	if has_prop(asset_id):
		return "prop"
	if has_character(asset_id):
		return "character"
	if has_tileset(asset_id):
		return "tileset"

	return "unknown"

## ===== BULK LOADING =====

## Load all pre-generated buildings
static func load_all_buildings() -> Dictionary:
	var result := {}
	for id in AssetManifestScript.BUILDINGS:
		var texture = load_building(id)
		if texture:
			result[id] = texture
	return result

## Load all pre-generated props
static func load_all_props() -> Dictionary:
	var result := {}
	for id in AssetManifestScript.PROPS:
		var texture = load_prop(id)
		if texture:
			result[id] = texture
	return result

## Load all pre-generated characters
static func load_all_characters() -> Dictionary:
	var result := {}
	for id in AssetManifestScript.CHARACTERS:
		var sf = load_character(id)
		if sf:
			result[id] = sf
	return result

## ===== STATUS =====

## Get count of pre-generated vs. missing assets
static func get_status() -> Dictionary:
	var status := {
		"buildings": {"generated": 0, "missing": 0, "missing_ids": []},
		"props": {"generated": 0, "missing": 0, "missing_ids": []},
		"characters": {"generated": 0, "missing": 0, "missing_ids": []},
		"tilesets": {"generated": 0, "missing": 0, "missing_ids": []},
	}

	for id in AssetManifestScript.BUILDINGS:
		if has_building(id):
			status.buildings.generated += 1
		else:
			status.buildings.missing += 1
			status.buildings.missing_ids.append(id)

	for id in AssetManifestScript.PROPS:
		if has_prop(id):
			status.props.generated += 1
		else:
			status.props.missing += 1
			status.props.missing_ids.append(id)

	for id in AssetManifestScript.CHARACTERS:
		if has_character(id):
			status.characters.generated += 1
		else:
			status.characters.missing += 1
			status.characters.missing_ids.append(id)

	for id in AssetManifestScript.TILESETS:
		if has_tileset(id):
			status.tilesets.generated += 1
		else:
			status.tilesets.missing += 1
			status.tilesets.missing_ids.append(id)

	return status

## Print status to console
static func print_status() -> void:
	var status = get_status()
	print("=== PRE-GENERATED ASSETS STATUS ===")
	print("Buildings: %d/%d" % [
		status.buildings.generated,
		status.buildings.generated + status.buildings.missing
	])
	print("Props: %d/%d" % [
		status.props.generated,
		status.props.generated + status.props.missing
	])
	print("Characters: %d/%d" % [
		status.characters.generated,
		status.characters.generated + status.characters.missing
	])
	print("Tilesets: %d/%d" % [
		status.tilesets.generated,
		status.tilesets.generated + status.tilesets.missing
	])

	var total_missing = (
		status.buildings.missing +
		status.props.missing +
		status.characters.missing +
		status.tilesets.missing
	)

	if total_missing > 0:
		print("\nMissing assets:")
		for id in status.buildings.missing_ids:
			print("  - building: %s" % id)
		for id in status.props.missing_ids:
			print("  - prop: %s" % id)
		for id in status.characters.missing_ids:
			print("  - character: %s" % id)
		for id in status.tilesets.missing_ids:
			print("  - tileset: %s" % id)
