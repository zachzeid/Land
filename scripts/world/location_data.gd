extends Resource
class_name LocationData
## LocationData - Data resource defining a game location
## Used by SceneManager to handle scene transitions and NPC placement

## Unique identifier for this location
@export var location_id: String = ""

## Display name shown to player
@export var display_name: String = ""

## Region this location belongs to (for world map organization)
@export var region: String = ""

## Area within the region (e.g., "Thornhaven Village")
@export var area: String = ""

## Path to the scene file for this location
@export_file("*.tscn") var scene_path: String = ""

## Whether this is an interior (affects lighting, ambient sounds, etc.)
@export var is_interior: bool = false

## Spawn points available in this location
## Key: spawn point name, Value: description
@export var spawn_points: Dictionary = {"default": "Default spawn point"}

## NPCs that call this location home
## Populated at runtime by SceneManager
var resident_npcs: Array = []

## Get the scene for this location
func get_scene() -> PackedScene:
	if scene_path == "":
		return null
	return load(scene_path) as PackedScene

## Check if a spawn point exists
func has_spawn_point(point_name: String) -> bool:
	return spawn_points.has(point_name)
