class_name AssetPlacement
extends RefCounted
## AssetPlacement - Coordinates asset generation and placement within playable bounds
## Generates specs for PixelLab MCP tools with correct sizing and validates placements

# Preload dependencies
const _GridLayout = preload("res://scripts/world/grid_layout.gd")

# Local constants to avoid parse-time class resolution issues
const GRID_SIZE: int = 32
const PIXELLAB_SCALE: int = 2

## Asset types that can be generated
enum AssetType {
	MAP_OBJECT,      # Props, decorations (barrel, crate, well, etc.)
	BUILDING,        # Structures with doors (shop, tavern, house)
	CHARACTER,       # NPCs and player sprites
	TILE,            # Individual tiles
	TILESET,         # Complete tilesets (topdown or sidescroller)
}

## A placement request with all generation and positioning info
class PlacementRequest:
	var id: String
	var asset_type: AssetType
	var description: String
	var grid_position: Vector2i
	var footprint: Vector2i
	var pixel_position: Vector2
	var display_size: Vector2
	var pixellab_size: Vector2i
	var scale: Vector2
	var metadata: Dictionary
	var valid: bool = true
	var validation_issues: Array[String] = []

	func _init(p_id: String, p_type: AssetType, p_desc: String):
		id = p_id
		asset_type = p_type
		description = p_desc
		metadata = {}

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"asset_type": AssetType.keys()[asset_type],
			"description": description,
			"grid_position": {"x": grid_position.x, "y": grid_position.y},
			"footprint": {"x": footprint.x, "y": footprint.y},
			"pixel_position": {"x": pixel_position.x, "y": pixel_position.y},
			"display_size": {"x": display_size.x, "y": display_size.y},
			"pixellab_size": {"x": pixellab_size.x, "y": pixellab_size.y},
			"scale": {"x": scale.x, "y": scale.y},
			"valid": valid,
			"validation_issues": validation_issues,
			"metadata": metadata,
		}


## ===== PLACEMENT REQUEST CREATION =====

## Create a placement request for a map object (props, decorations)
static func create_map_object_request(
	id: String,
	description: String,
	grid_x: int,
	grid_y: int,
	footprint_type: String = ""
) -> PlacementRequest:
	var request = PlacementRequest.new(id, AssetType.MAP_OBJECT, description)

	# Get footprint from type or default
	request.footprint = _GridLayout.FOOTPRINTS.get(footprint_type, Vector2i(2, 2))

	# Validate and set positions
	var validation = _GridLayout.validate_placement(grid_x, grid_y, request.footprint)
	request.valid = validation.valid
	request.validation_issues = Array(validation.issues, TYPE_STRING, "", null)

	# Use clamped position if invalid
	request.grid_position = validation.clamped_position if not validation.valid else Vector2i(grid_x, grid_y)

	# Calculate pixel position and sizes
	request.pixel_position = _GridLayout.building_position(
		request.grid_position.x,
		request.grid_position.y,
		request.footprint.x,
		request.footprint.y
	)
	request.display_size = Vector2(request.footprint.x * GRID_SIZE, request.footprint.y * GRID_SIZE)
	request.pixellab_size = _GridLayout.get_pixellab_size_for_footprint(request.footprint)
	request.scale = _GridLayout.get_pixellab_scale()

	request.metadata["footprint_type"] = footprint_type
	request.metadata["view"] = "high top-down"

	return request

## Create a placement request for a building
static func create_building_request(
	id: String,
	description: String,
	grid_x: int,
	grid_y: int,
	building_type: String
) -> PlacementRequest:
	var request = PlacementRequest.new(id, AssetType.BUILDING, description)

	request.footprint = _GridLayout.FOOTPRINTS.get(building_type, Vector2i(5, 4))

	var validation = _GridLayout.validate_placement(grid_x, grid_y, request.footprint)
	request.valid = validation.valid
	request.validation_issues = Array(validation.issues, TYPE_STRING, "", null)
	request.grid_position = validation.clamped_position if not validation.valid else Vector2i(grid_x, grid_y)

	request.pixel_position = _GridLayout.building_position(
		request.grid_position.x,
		request.grid_position.y,
		request.footprint.x,
		request.footprint.y
	)
	request.display_size = Vector2(request.footprint.x * GRID_SIZE, request.footprint.y * GRID_SIZE)
	request.pixellab_size = _GridLayout.get_pixellab_size_for_footprint(request.footprint)
	request.scale = _GridLayout.get_pixellab_scale()

	# Calculate door position
	var door_offset = _GridLayout.DOOR_OFFSETS.get(building_type, Vector2(2, 4))
	request.metadata["building_type"] = building_type
	request.metadata["door_offset"] = {"x": door_offset.x, "y": door_offset.y}
	request.metadata["door_position"] = _GridLayout.get_door_position(id, {"buildings": {id: {"grid": request.grid_position, "footprint": building_type}}})
	request.metadata["view"] = "high top-down"

	return request

## Create a character placement request
static func create_character_request(
	id: String,
	description: String,
	spawn_waypoint_id: String = ""
) -> PlacementRequest:
	var request = PlacementRequest.new(id, AssetType.CHARACTER, description)

	# Characters use fixed 48px canvas (standard for PixelLab MCP)
	request.footprint = Vector2i(2, 2)  # ~64x64 display
	request.display_size = Vector2(48 * PIXELLAB_SCALE, 48 * PIXELLAB_SCALE)
	request.pixellab_size = Vector2i(48, 48)  # PixelLab character default
	request.scale = _GridLayout.get_pixellab_scale()

	request.metadata["spawn_waypoint"] = spawn_waypoint_id
	request.metadata["n_directions"] = 8
	request.metadata["view"] = "low top-down"

	return request


## ===== BATCH OPERATIONS =====

## Create placement requests for all assets in a layout
static func create_requests_from_layout(layout: Dictionary) -> Array[PlacementRequest]:
	var requests: Array[PlacementRequest] = []

	# Buildings
	if layout.has("buildings"):
		for id in layout.buildings:
			var data = layout.buildings[id]
			var building_type = data.get("footprint", "house_small")
			var desc = data.get("description", "medieval %s building" % building_type.replace("_", " "))
			var request = create_building_request(id, desc, data.grid.x, data.grid.y, building_type)
			requests.append(request)

	# Props
	if layout.has("props"):
		for id in layout.props:
			var grid_pos = layout.props[id]
			var footprint_type = id.split("_")[0] if "_" in id else id
			var desc = layout.get("prop_descriptions", {}).get(id, "medieval %s" % footprint_type)
			var request = create_map_object_request(id, desc, grid_pos.x, grid_pos.y, footprint_type)
			requests.append(request)

	# Trees
	if layout.has("trees"):
		for i in range(layout.trees.size()):
			var grid_pos = layout.trees[i]
			var request = create_map_object_request(
				"tree_%d" % i,
				"large oak tree with green foliage",
				grid_pos.x,
				grid_pos.y,
				"tree"
			)
			requests.append(request)

	return requests

## Filter requests to only valid placements
static func get_valid_requests(requests: Array[PlacementRequest]) -> Array[PlacementRequest]:
	var valid: Array[PlacementRequest] = []
	for req in requests:
		if req.valid:
			valid.append(req)
	return valid

## Get all validation issues from requests
static func get_all_issues(requests: Array[PlacementRequest]) -> Array[String]:
	var issues: Array[String] = []
	for req in requests:
		for issue in req.validation_issues:
			issues.append("[%s] %s" % [req.id, issue])
	return issues


## ===== PIXELLAB MCP SPEC GENERATION =====
## These generate the parameters to use with PixelLab MCP tools

## Generate spec for mcp__pixellab__create_map_object
static func get_mcp_map_object_spec(request: PlacementRequest) -> Dictionary:
	return {
		"description": request.description,
		"width": request.pixellab_size.x,
		"height": request.pixellab_size.y,
		"view": request.metadata.get("view", "high top-down"),
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	}

## Generate spec for mcp__pixellab__create_character
static func get_mcp_character_spec(request: PlacementRequest) -> Dictionary:
	return {
		"description": request.description,
		"name": request.id,
		"size": request.pixellab_size.x,  # Characters use square canvas
		"n_directions": request.metadata.get("n_directions", 8),
		"view": request.metadata.get("view", "low top-down"),
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color black outline",
	}

## Generate spec for mcp__pixellab__create_topdown_tileset
static func get_mcp_tileset_spec(lower_desc: String, upper_desc: String, transition_desc: String = "") -> Dictionary:
	return {
		"lower_description": lower_desc,
		"upper_description": upper_desc,
		"transition_description": transition_desc if transition_desc != "" else null,
		"transition_size": 0.5 if transition_desc != "" else 0,
		"tile_size": {"width": 16, "height": 16},  # Generate small, scale up
		"view": "high top-down",
		"detail": "medium detail",
		"shading": "basic shading",
	}


## ===== PLACEMENT APPLICATION =====

## Apply a generated asset to scene at the specified position
static func apply_asset_to_scene(
	scene_root: Node2D,
	request: PlacementRequest,
	texture: Texture2D
) -> Sprite2D:
	if not request.valid:
		push_warning("Applying invalid placement: %s" % request.id)

	var sprite = Sprite2D.new()
	sprite.name = request.id
	sprite.texture = texture
	sprite.position = request.pixel_position
	sprite.scale = request.scale

	# Set appropriate z-index based on type
	match request.asset_type:
		AssetType.BUILDING:
			sprite.z_index = 0
		AssetType.MAP_OBJECT:
			sprite.z_index = 1
		AssetType.CHARACTER:
			sprite.z_index = 10

	scene_root.add_child(sprite)
	sprite.owner = scene_root

	return sprite


## ===== DEBUG =====

## Print all requests with their specs
static func print_requests(requests: Array[PlacementRequest]) -> void:
	print("=== ASSET PLACEMENT REQUESTS ===")
	print("Total: %d requests" % requests.size())

	var valid_count = 0
	for req in requests:
		if req.valid:
			valid_count += 1

	print("Valid: %d, Invalid: %d" % [valid_count, requests.size() - valid_count])
	print("")

	for req in requests:
		var status = "OK" if req.valid else "INVALID"
		print("[%s] %s (%s)" % [status, req.id, AssetType.keys()[req.asset_type]])
		print("  Description: %s" % req.description.left(60))
		print("  Grid: (%d, %d), Footprint: %dx%d" % [req.grid_position.x, req.grid_position.y, req.footprint.x, req.footprint.y])
		print("  Pixel: %s, Display: %s" % [req.pixel_position, req.display_size])
		print("  PixelLab size: %dx%d, Scale: %s" % [req.pixellab_size.x, req.pixellab_size.y, req.scale])
		if not req.valid:
			for issue in req.validation_issues:
				print("  ! %s" % issue)
		print("")
