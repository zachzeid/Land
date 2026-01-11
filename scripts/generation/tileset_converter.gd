@tool
extends SceneTree
## PixelLab to Godot Tileset Converter
## Converts PixelLab metadata JSON + PNG to Godot terrain TileSet
## Usage: godot --headless --script scripts/generation/tileset_converter.gd

func _init():
	print("=== PixelLab to Godot Tileset Converter ===")

	var tilesets_dir = "res://assets/generated/tilesets"
	var output_path = "res://assets/generated/tilesets/terrain_tileset.tres"

	# Find all metadata/image pairs
	var pairs = []
	var dir = DirAccess.open(tilesets_dir)
	if not dir:
		print("ERROR: Could not open %s" % tilesets_dir)
		quit(1)
		return

	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if file.ends_with("_metadata.json"):
			var base = file.replace("_metadata.json", "")
			var png_file = base + "_image.png"
			if dir.file_exists(png_file):
				pairs.append({"name": base, "json": tilesets_dir + "/" + file, "png": tilesets_dir + "/" + png_file})
		file = dir.get_next()
	dir.list_dir_end()

	if pairs.is_empty():
		print("ERROR: No tileset pairs found in %s" % tilesets_dir)
		print("Expected files: *_metadata.json and *_image.png")
		quit(1)
		return

	print("Found %d tileset pairs:" % pairs.size())
	for pair in pairs:
		print("  - %s" % pair.name)

	# Load and process tilesets
	var all_tiles = []
	var terrains = {}
	var tile_size = 16

	for pair in pairs:
		var result = load_tileset(pair.json, pair.png, terrains)
		if result:
			all_tiles.append_array(result.tiles)
			tile_size = result.tile_size

	if all_tiles.is_empty():
		print("ERROR: No tiles loaded")
		quit(1)
		return

	# Create combined atlas
	var atlas = create_atlas(all_tiles, tile_size)
	var atlas_path = tilesets_dir + "/terrain_atlas.png"
	atlas.save_png(ProjectSettings.globalize_path(atlas_path))
	print("Saved atlas: %s" % atlas_path)

	# Create TileSet resource
	create_tileset_resource(all_tiles, terrains, atlas, tile_size, output_path)

	print("\n=== Conversion Complete ===")
	print("TileSet: %s" % output_path)
	print("Terrains: %s" % ", ".join(terrains.values()))
	print("\nUsage in Godot:")
	print("  1. Add TileMapLayer node to your scene")
	print("  2. Assign %s as tile_set" % output_path)
	print("  3. Select TileMapLayer > TileMap tab > Terrains")
	print("  4. Use Rect Tool (R) to paint terrain")

	quit(0)


func load_tileset(json_path: String, png_path: String, terrains: Dictionary) -> Variant:
	print("\nLoading %s..." % json_path)

	# Read JSON
	var abs_json = ProjectSettings.globalize_path(json_path)
	if not FileAccess.file_exists(abs_json):
		print("  ERROR: JSON not found")
		return null

	var file = FileAccess.open(abs_json, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		print("  ERROR: Invalid JSON")
		return null
	file.close()

	var data = json.data

	# Load PNG
	var abs_png = ProjectSettings.globalize_path(png_path)
	if not FileAccess.file_exists(abs_png):
		print("  ERROR: PNG not found")
		return null

	var sprite_sheet = Image.new()
	if sprite_sheet.load(abs_png) != OK:
		print("  ERROR: Failed to load PNG")
		return null

	# Get terrain names
	var lower_name = data.metadata.terrain_prompts.lower
	var upper_name = data.metadata.terrain_prompts.upper

	# Add terrains
	var lower_id = get_terrain_id(terrains, lower_name)
	var upper_id = get_terrain_id(terrains, upper_name)

	# Get tile size
	var ts = data.tileset_data.tile_size
	var tile_size = ts.width

	# Extract tiles
	var tiles = []
	for tile_data in data.tileset_data.tiles:
		var bbox = tile_data.bounding_box
		var corners = tile_data.corners

		# Extract tile image
		var tile_img = Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
		tile_img.blit_rect(sprite_sheet, Rect2i(bbox.x, bbox.y, bbox.width, bbox.height), Vector2i.ZERO)

		# Map corners to terrain IDs
		var corner_ids = [
			upper_id if corners.NW == "upper" else lower_id,  # Top-left
			upper_id if corners.NE == "upper" else lower_id,  # Top-right
			upper_id if corners.SW == "upper" else lower_id,  # Bottom-left
			upper_id if corners.SE == "upper" else lower_id,  # Bottom-right
		]

		tiles.append({
			"image": tile_img,
			"corners": corner_ids,
		})

	print("  Loaded %d tiles (terrains: %s, %s)" % [tiles.size(), lower_name, upper_name])
	return {"tiles": tiles, "tile_size": tile_size}


func normalize_terrain_name(name: String) -> String:
	# Normalize terrain names to base types for consistent IDs
	var lower = name.to_lower()
	if "grass" in lower:
		return "grass"
	if "dirt" in lower or "earth" in lower or "path" in lower and not "cobble" in lower and not "stone" in lower:
		return "dirt"
	if "cobble" in lower or "stone" in lower:
		return "cobblestone"
	if "water" in lower or "ocean" in lower:
		return "water"
	if "sand" in lower:
		return "sand"
	# Fallback to original name
	return name


func get_terrain_id(terrains: Dictionary, name: String) -> int:
	var normalized = normalize_terrain_name(name)
	for id in terrains:
		if terrains[id] == normalized:
			return id
	var id = terrains.size()
	terrains[id] = normalized
	return id


func create_atlas(tiles: Array, tile_size: int) -> Image:
	var cols = 8
	var rows = ceili(float(tiles.size()) / cols)
	var atlas = Image.create(cols * tile_size, rows * tile_size, false, Image.FORMAT_RGBA8)

	for i in range(tiles.size()):
		var x = (i % cols) * tile_size
		var y = (i / cols) * tile_size
		atlas.blit_rect(tiles[i].image, Rect2i(0, 0, tile_size, tile_size), Vector2i(x, y))

	return atlas


func create_tileset_resource(tiles: Array, terrains: Dictionary, atlas: Image, tile_size: int, output_path: String):
	# Build tile definitions for .tres
	var cols = 8
	var tile_defs = []

	for i in range(tiles.size()):
		var x = i % cols
		var y = i / cols
		var corners = tiles[i].corners

		# Determine the primary terrain for this tile (most common corner value)
		var corner_counts = {}
		for c in corners:
			corner_counts[c] = corner_counts.get(c, 0) + 1
		var primary_terrain = corners[0]
		var max_count = 0
		for terrain_id in corner_counts:
			if corner_counts[terrain_id] > max_count:
				max_count = corner_counts[terrain_id]
				primary_terrain = terrain_id

		tile_defs.append("%d:%d/0 = 0" % [x, y])
		tile_defs.append("%d:%d/0/terrain_set = 0" % [x, y])
		tile_defs.append("%d:%d/0/terrain = %d" % [x, y, primary_terrain])
		tile_defs.append("%d:%d/0/terrains_peering_bit/top_left_corner = %d" % [x, y, corners[0]])
		tile_defs.append("%d:%d/0/terrains_peering_bit/top_right_corner = %d" % [x, y, corners[1]])
		tile_defs.append("%d:%d/0/terrains_peering_bit/bottom_left_corner = %d" % [x, y, corners[2]])
		tile_defs.append("%d:%d/0/terrains_peering_bit/bottom_right_corner = %d" % [x, y, corners[3]])

	# Build terrain definitions
	var terrain_defs = []
	var colors = [
		Color(0.3, 0.6, 0.2),  # Green for grass
		Color(0.5, 0.35, 0.2), # Brown for dirt
		Color(0.4, 0.4, 0.45), # Gray for stone
	]

	for id in terrains:
		var name = terrains[id]
		var color = colors[id % colors.size()]
		terrain_defs.append('terrain_set_0/terrain_%d/name = "%s"' % [id, name])
		terrain_defs.append('terrain_set_0/terrain_%d/color = Color(%f, %f, %f, 1)' % [id, color.r, color.g, color.b])

	# Write .tres file - reference external PNG instead of embedding image data
	var atlas_res_path = "res://assets/generated/tilesets/terrain_atlas.png"

	# Try to read the UID from the .import file
	var atlas_uid = ""
	var import_path = ProjectSettings.globalize_path(atlas_res_path + ".import")
	if FileAccess.file_exists(import_path):
		var import_file = FileAccess.open(import_path, FileAccess.READ)
		var import_text = import_file.get_as_text()
		import_file.close()
		var uid_regex = RegEx.new()
		uid_regex.compile('uid="(uid://[^"]+)"')
		var match = uid_regex.search(import_text)
		if match:
			atlas_uid = match.get_string(1)
			print("Found atlas UID: %s" % atlas_uid)

	var tres = '[gd_resource type="TileSet" load_steps=3 format=3]\n\n'
	if atlas_uid != "":
		tres += '[ext_resource type="Texture2D" uid="%s" path="%s" id="1_atlas"]\n\n' % [atlas_uid, atlas_res_path]
	else:
		tres += '[ext_resource type="Texture2D" path="%s" id="1_atlas"]\n\n' % atlas_res_path
	tres += '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_1"]\n'
	tres += 'texture = ExtResource("1_atlas")\n'
	tres += 'texture_region_size = Vector2i(%d, %d)\n' % [tile_size, tile_size]
	tres += "\n".join(tile_defs) + '\n\n'
	tres += '[resource]\n'
	tres += 'tile_size = Vector2i(%d, %d)\n' % [tile_size, tile_size]
	tres += 'terrain_set_0/mode = 1\n'  # Match Corners mode (Wang tiles)
	tres += "\n".join(terrain_defs) + '\n'
	tres += 'sources/0 = SubResource("TileSetAtlasSource_1")\n'

	var abs_path = ProjectSettings.globalize_path(output_path)
	var out_file = FileAccess.open(abs_path, FileAccess.WRITE)
	out_file.store_string(tres)
	out_file.close()

	print("Created TileSet with %d tiles, %d terrains" % [tiles.size(), terrains.size()])
