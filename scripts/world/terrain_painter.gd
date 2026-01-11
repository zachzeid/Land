extends Node
## TerrainPainter - Programmatically paints terrain based on layout
## Attach to a node that has a TileMapLayer sibling named "TerrainLayer"

const GridLayout = preload("res://scripts/world/grid_layout.gd")

## Terrain IDs (from the tileset)
## 0 = grass, 1 = dirt, 2 = cobblestone
const TERRAIN_GRASS := 0
const TERRAIN_DIRT := 1
const TERRAIN_COBBLESTONE := 2

@export var auto_paint_on_ready := true

func _ready():
	if auto_paint_on_ready:
		call_deferred("paint_terrain")

func paint_terrain():
	var tile_map = get_parent().get_node_or_null("TerrainLayer")
	if not tile_map:
		push_warning("[TerrainPainter] No TerrainLayer found")
		return

	print("[TerrainPainter] Painting terrain...")

	# Verify tileset is assigned
	if not tile_map.tile_set:
		push_error("[TerrainPainter] No TileSet assigned!")
		return

	# Clear existing tiles
	tile_map.clear()

	var layout = GridLayout.THORNHAVEN_LAYOUT

	# Paint grass everywhere first (full map area)
	paint_area(tile_map, Vector2i(-32, -32), Vector2i(31, 31), TERRAIN_GRASS)

	# Paint town square with cobblestone (larger central area)
	paint_area(tile_map, Vector2i(-10, -10), Vector2i(8, 8), TERRAIN_COBBLESTONE)

	# Paint main north-south road (wider, through center)
	paint_area(tile_map, Vector2i(-4, -32), Vector2i(2, 31), TERRAIN_DIRT)

	# Paint main east-west road (wider, through center)
	paint_area(tile_map, Vector2i(-32, -4), Vector2i(31, 2), TERRAIN_DIRT)

	# Paint connections to buildings BEFORE paths to ensure visibility
	paint_building_connections(tile_map, layout)

	print("[TerrainPainter] Terrain painted! %d tiles placed" % tile_map.get_used_cells().size())


func paint_area(tile_map: TileMapLayer, from: Vector2i, to: Vector2i, terrain_id: int):
	var cells: Array[Vector2i] = []
	for x in range(from.x, to.x + 1):
		for y in range(from.y, to.y + 1):
			cells.append(Vector2i(x, y))

	if cells.size() > 0:
		# TileMapLayer API: set_cells_terrain_connect(cells, terrain_set, terrain)
		tile_map.set_cells_terrain_connect(cells, 0, terrain_id)


func paint_path_from_grid(tile_map: TileMapLayer, start_grid: Vector2i, end_grid: Vector2i, terrain_id: int):
	# Convert grid coordinates to tile coordinates
	# Grid is 32x32 with origin at center (16,16)
	# Tiles are 16x16 pixels, world is 1024x1024
	# Tile coords: -32 to 31 (64 tiles)
	var start_tile = grid_to_tile(start_grid)
	var end_tile = grid_to_tile(end_grid)

	paint_area(tile_map, start_tile, end_tile, terrain_id)


func grid_to_tile(grid_pos: Vector2i) -> Vector2i:
	# Grid (0-31) to tile coords (-32 to 31)
	# Each grid cell = 32 pixels = 2 tiles (16px tiles)
	var tile_x = (grid_pos.x - 16) * 2
	var tile_y = (grid_pos.y - 16) * 2
	return Vector2i(tile_x, tile_y)


func paint_building_connections(tile_map: TileMapLayer, layout: Dictionary):
	# Paint dirt paths from main roads to building entrances
	if not layout.has("buildings"):
		return

	# Main road tile coordinates (matching paint_terrain)
	var ns_road_x_min = -4
	var ns_road_x_max = 2
	var ew_road_y_min = -4
	var ew_road_y_max = 2

	for building_id in layout.buildings:
		var data = layout.buildings[building_id]
		var grid_pos = data.grid
		var footprint_name = data.footprint
		var footprint = GridLayout.FOOTPRINTS.get(footprint_name, Vector2i(4, 4))
		var door_offset = GridLayout.DOOR_OFFSETS.get(footprint_name, Vector2(2, 4))

		# Door position in grid (where entrance is)
		var door_grid = Vector2i(
			int(grid_pos.x + door_offset.x),
			int(grid_pos.y + door_offset.y)
		)

		# Convert to tile coordinates
		var door_tile = grid_to_tile(door_grid)

		# Building footprint in tiles (for painting under building)
		var building_tile = grid_to_tile(grid_pos)
		var footprint_tiles = Vector2i(footprint.x * 2, footprint.y * 2)

		# Paint entrance area at the door (extends slightly into building footprint)
		var entrance_from = door_tile - Vector2i(2, 2)
		var entrance_to = door_tile + Vector2i(2, 3)
		paint_area(tile_map, entrance_from, entrance_to, TERRAIN_DIRT)

		# Determine which road is closer and connect to it
		var dist_to_ns_road = abs(door_tile.x)
		var dist_to_ew_road = abs(door_tile.y)

		if dist_to_ns_road < dist_to_ew_road:
			# Connect horizontally to N-S road
			var target_x = ns_road_x_max if door_tile.x > 0 else ns_road_x_min
			var start_x = mini(door_tile.x - 2, target_x)
			var end_x = maxi(door_tile.x + 2, target_x)
			paint_area(tile_map,
				Vector2i(start_x, door_tile.y - 2),
				Vector2i(end_x, door_tile.y + 3),
				TERRAIN_DIRT)
		else:
			# Connect vertically to E-W road
			var target_y = ew_road_y_max if door_tile.y > 0 else ew_road_y_min
			var start_y = mini(door_tile.y - 2, target_y)
			var end_y = maxi(door_tile.y + 3, target_y)
			paint_area(tile_map,
				Vector2i(door_tile.x - 2, start_y),
				Vector2i(door_tile.x + 2, end_y),
				TERRAIN_DIRT)
