extends Node2D
class_name BaseInterior
## BaseInterior - Base class for all interior scenes
## Provides standard sizing, validation, and common functionality

## Standard interior sizes (in pixels)
enum InteriorSize {
	SMALL = 512,      # 512x512 - small rooms, closets
	STANDARD = 1024,  # 1024x1024 - shops, houses
	LARGE = 1536,     # 1536x1536 - taverns, large shops
	HUGE = 2048       # 2048x2048 - castles, warehouses
}

## Interior building types
enum InteriorType {
	SHOP,
	TAVERN,
	BLACKSMITH,
	HOUSE,
	INN,
	TEMPLE,
	CASTLE_ROOM,
	WAREHOUSE,
	CUSTOM
}

## Configuration
@export var interior_type: InteriorType = InteriorType.SHOP
@export var interior_size: InteriorSize = InteriorSize.STANDARD
@export var location_id: String = ""  # Links to WorldKnowledge location
@export var display_name: String = ""

## Required nodes (will be validated)
@export_group("Required Nodes")
@export var floor_node_path: NodePath = "Floor"
@export var walls_node_path: NodePath = "Walls"
@export var spawn_points_path: NodePath = "SpawnPoints"
@export var exit_trigger_path: NodePath = "Exit"

## Theme colors for different building types
const BUILDING_THEMES = {
	InteriorType.SHOP: {
		"floor_color": Color(0.32, 0.25, 0.18, 1),
		"floor_inner_color": Color(0.42, 0.34, 0.26, 1),
		"wall_color": Color(0.38, 0.28, 0.2, 1)
	},
	InteriorType.TAVERN: {
		"floor_color": Color(0.28, 0.22, 0.16, 1),
		"floor_inner_color": Color(0.35, 0.28, 0.2, 1),
		"wall_color": Color(0.4, 0.28, 0.18, 1)
	},
	InteriorType.BLACKSMITH: {
		"floor_color": Color(0.2, 0.18, 0.18, 1),
		"floor_inner_color": Color(0.3, 0.28, 0.28, 1),
		"wall_color": Color(0.35, 0.3, 0.28, 1)
	},
	InteriorType.HOUSE: {
		"floor_color": Color(0.35, 0.3, 0.22, 1),
		"floor_inner_color": Color(0.45, 0.38, 0.28, 1),
		"wall_color": Color(0.4, 0.32, 0.22, 1)
	},
	InteriorType.INN: {
		"floor_color": Color(0.3, 0.24, 0.18, 1),
		"floor_inner_color": Color(0.38, 0.3, 0.22, 1),
		"wall_color": Color(0.42, 0.32, 0.22, 1)
	},
	InteriorType.TEMPLE: {
		"floor_color": Color(0.25, 0.25, 0.28, 1),
		"floor_inner_color": Color(0.35, 0.35, 0.4, 1),
		"wall_color": Color(0.4, 0.38, 0.42, 1)
	},
	InteriorType.CASTLE_ROOM: {
		"floor_color": Color(0.22, 0.22, 0.25, 1),
		"floor_inner_color": Color(0.32, 0.32, 0.38, 1),
		"wall_color": Color(0.38, 0.36, 0.4, 1)
	},
	InteriorType.WAREHOUSE: {
		"floor_color": Color(0.25, 0.22, 0.2, 1),
		"floor_inner_color": Color(0.35, 0.3, 0.28, 1),
		"wall_color": Color(0.3, 0.28, 0.25, 1)
	}
}

## Validation results
var validation_passed: bool = false
var validation_errors: Array[String] = []

func _ready():
	_validate_interior()
	if not validation_passed:
		push_warning("[BaseInterior] Validation failed for %s: %s" % [name, validation_errors])
	else:
		print("[BaseInterior] %s validated successfully (%dx%d)" % [name, interior_size, interior_size])

## Validate interior structure and size
func _validate_interior() -> bool:
	validation_errors.clear()
	validation_passed = true

	# Check required nodes exist
	if not _validate_required_nodes():
		validation_passed = false

	# Validate floor size matches expected interior size
	if not _validate_floor_size():
		validation_passed = false

	# Validate walls match interior size
	if not _validate_walls():
		validation_passed = false

	# Validate spawn points exist
	if not _validate_spawn_points():
		validation_passed = false

	# Validate exit trigger exists
	if not _validate_exit():
		validation_passed = false

	return validation_passed

func _validate_required_nodes() -> bool:
	var valid = true

	if not has_node(floor_node_path):
		validation_errors.append("Missing Floor node at path: %s" % floor_node_path)
		valid = false

	if not has_node(walls_node_path):
		validation_errors.append("Missing Walls node at path: %s" % walls_node_path)
		valid = false

	if not has_node(spawn_points_path):
		validation_errors.append("Missing SpawnPoints node at path: %s" % spawn_points_path)
		valid = false

	return valid

func _validate_floor_size() -> bool:
	if not has_node(floor_node_path):
		return false

	var floor_node = get_node(floor_node_path)
	if not floor_node is ColorRect:
		validation_errors.append("Floor must be a ColorRect node")
		return false

	var expected_half = int(interior_size) / 2
	var floor_rect = floor_node as ColorRect

	# Check floor bounds (-half to +half for 1024x1024)
	var expected_left = -expected_half
	var expected_right = expected_half
	var expected_top = -expected_half
	var expected_bottom = expected_half

	var actual_width = floor_rect.offset_right - floor_rect.offset_left
	var actual_height = floor_rect.offset_bottom - floor_rect.offset_top

	if int(actual_width) != int(interior_size) or int(actual_height) != int(interior_size):
		validation_errors.append("Floor size mismatch: expected %dx%d, got %dx%d" % [
			interior_size, interior_size, actual_width, actual_height
		])
		return false

	# Check floor is centered
	if int(floor_rect.offset_left) != expected_left or int(floor_rect.offset_right) != expected_right:
		validation_errors.append("Floor not centered horizontally: expected %d to %d, got %d to %d" % [
			expected_left, expected_right, floor_rect.offset_left, floor_rect.offset_right
		])
		return false

	return true

func _validate_walls() -> bool:
	if not has_node(walls_node_path):
		return false

	var walls_node = get_node(walls_node_path)
	var required_walls = ["North", "South", "East", "West"]
	var valid = true

	for wall_name in required_walls:
		if not walls_node.has_node(wall_name):
			validation_errors.append("Missing wall: %s" % wall_name)
			valid = false

	return valid

func _validate_spawn_points() -> bool:
	if not has_node(spawn_points_path):
		return false

	var spawn_node = get_node(spawn_points_path)

	# Must have at least a default spawn point
	if not spawn_node.has_node("default") and not spawn_node.has_node("from_exterior"):
		validation_errors.append("Missing default or from_exterior spawn point")
		return false

	return true

func _validate_exit() -> bool:
	if not has_node(exit_trigger_path):
		validation_errors.append("Missing Exit trigger at path: %s" % exit_trigger_path)
		return false

	var exit_node = get_node(exit_trigger_path)
	if not exit_node is Area2D:
		validation_errors.append("Exit must be an Area2D node")
		return false

	return true

## Get the expected size in pixels
func get_size_pixels() -> int:
	return int(interior_size)

## Get the half-size (for centered layouts)
func get_half_size() -> int:
	return int(interior_size) / 2

## Get theme colors for this interior type
func get_theme_colors() -> Dictionary:
	if BUILDING_THEMES.has(interior_type):
		return BUILDING_THEMES[interior_type]
	return BUILDING_THEMES[InteriorType.SHOP]  # Default

## Apply theme colors to floor and walls
func apply_theme():
	var colors = get_theme_colors()

	# Apply to floor
	if has_node(floor_node_path):
		var floor_node = get_node(floor_node_path) as ColorRect
		if floor_node:
			floor_node.color = colors.floor_color
			# Apply inner floor if exists
			for child in floor_node.get_children():
				if child is ColorRect:
					child.color = colors.floor_inner_color
					break

	# Apply to walls
	if has_node(walls_node_path):
		var walls_node = get_node(walls_node_path)
		for wall in walls_node.get_children():
			var visual = wall.get_node_or_null("Visual")
			if visual and visual is ColorRect:
				visual.color = colors.wall_color

## Get spawn point position by name
func get_spawn_position(spawn_name: String = "default") -> Vector2:
	if not has_node(spawn_points_path):
		return Vector2.ZERO

	var spawn_node = get_node(spawn_points_path)

	# Try exact match
	if spawn_node.has_node(spawn_name):
		return spawn_node.get_node(spawn_name).global_position

	# Try default
	if spawn_node.has_node("default"):
		return spawn_node.get_node("default").global_position

	# Try first child
	if spawn_node.get_child_count() > 0:
		return spawn_node.get_child(0).global_position

	return Vector2.ZERO

## Get all spawn point names
func get_spawn_point_names() -> Array[String]:
	var names: Array[String] = []

	if has_node(spawn_points_path):
		var spawn_node = get_node(spawn_points_path)
		for child in spawn_node.get_children():
			names.append(child.name)

	return names

## Static validation for external use (e.g., SceneManager)
static func validate_interior_scene(scene_root: Node) -> Dictionary:
	var result = {
		"valid": true,
		"errors": [],
		"size": 0,
		"type": ""
	}

	# Check if scene has Floor node
	var floor_node = scene_root.get_node_or_null("Floor")
	if not floor_node or not floor_node is ColorRect:
		result.valid = false
		result.errors.append("Missing or invalid Floor node")
		return result

	# Check floor size
	var floor_rect = floor_node as ColorRect
	var width = floor_rect.offset_right - floor_rect.offset_left
	var height = floor_rect.offset_bottom - floor_rect.offset_top

	result.size = int(width)

	# Validate standard sizes
	var valid_sizes = [512, 1024, 1536, 2048]
	if int(width) != int(height):
		result.valid = false
		result.errors.append("Interior must be square: got %dx%d" % [width, height])
	elif int(width) not in valid_sizes:
		result.valid = false
		result.errors.append("Interior size must be 512, 1024, 1536, or 2048. Got: %d" % width)

	# Check walls
	var walls_node = scene_root.get_node_or_null("Walls")
	if not walls_node:
		result.valid = false
		result.errors.append("Missing Walls node")
	else:
		for wall_name in ["North", "South", "East", "West"]:
			if not walls_node.has_node(wall_name):
				result.valid = false
				result.errors.append("Missing wall: %s" % wall_name)

	# Check spawn points
	var spawn_node = scene_root.get_node_or_null("SpawnPoints")
	if not spawn_node:
		result.valid = false
		result.errors.append("Missing SpawnPoints node")
	elif spawn_node.get_child_count() == 0:
		result.valid = false
		result.errors.append("SpawnPoints has no children")

	# Determine type from scene name
	var scene_name = scene_root.name.to_lower()
	if "tavern" in scene_name:
		result.type = "tavern"
	elif "blacksmith" in scene_name or "forge" in scene_name:
		result.type = "blacksmith"
	elif "shop" in scene_name or "store" in scene_name:
		result.type = "shop"
	elif "house" in scene_name or "home" in scene_name:
		result.type = "house"
	elif "inn" in scene_name:
		result.type = "inn"
	elif "temple" in scene_name or "church" in scene_name:
		result.type = "temple"
	elif "castle" in scene_name:
		result.type = "castle_room"
	else:
		result.type = "unknown"

	return result
