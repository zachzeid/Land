class_name AssetManifest
extends RefCounted
## AssetManifest - Defines all pre-generated assets with PixelLab MCP specifications
## Used by Claude to generate assets during development, and by the game to load them

# Preload for sizing calculations
const _GridLayout = preload("res://scripts/world/grid_layout.gd")

## Base path for pre-generated assets
const BASE_PATH := "res://assets/generated"

## ===== BUILDING DEFINITIONS =====
## Buildings are map objects with doors and collision areas

const BUILDINGS := {
	"gregor_shop": {
		"description": "low top-down view medieval merchant shop, slight 3/4 angle showing front facade and shingled roof, timber-frame building with dark wood beams and cream plaster walls, visible wooden door at ground level, small display window, hanging shop sign bracket, cozy trading post, pixel art style, warm earthy colors",
		"footprint": "shop",
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	},
	"tavern": {
		"description": "low top-down view medieval tavern, slight 3/4 angle showing front facade and multiple roof sections, large stone foundation with timber upper floor, visible main entrance door with warm light glow, two chimneys with smoke wisps, welcoming inn atmosphere, pixel art style, warm earthy colors",
		"footprint": "tavern",
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	},
	"blacksmith": {
		"description": "low top-down view medieval blacksmith forge, slight 3/4 angle showing open-front workshop and dark roof, large stone chimney with orange glow, anvil and forge visible under awning, weapon rack on side wall, industrial working atmosphere, pixel art style, warm earthy colors with orange fire accents",
		"footprint": "blacksmith",
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	},
	"village_house_1": {
		"description": "low top-down view small cottage, slight 3/4 angle showing front facade and thatched straw roof, simple wooden walls, visible door at center, single shuttered window, small chimney, cozy peasant home, pixel art style, warm earthy colors",
		"footprint": "house_small",
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	},
	"village_house_2": {
		"description": "low top-down view medium cottage, slight 3/4 angle showing front facade and shingled roof, timber-frame walls with plaster, visible door with small porch, two windows, chimney with light smoke, pixel art style, warm earthy colors",
		"footprint": "house_small",
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	},
	"village_gate": {
		"description": "low top-down view wooden village entrance gate, slight 3/4 angle showing archway depth, two sturdy wooden posts with crossbeam, hanging welcome sign bracket, torch sconces on posts, rustic but welcoming design, pixel art style, warm earthy colors",
		"footprint": "gate",
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
	},
}

## ===== PROP DEFINITIONS =====
## Props are smaller map objects for decoration

const PROPS := {
	"barrel": {
		"description": "low top-down view wooden barrel, slight 3/4 angle showing top and side, medieval style, metal bands, slightly weathered wood grain, pixel art",
		"footprint": "barrel",  # 2x2 grid cells
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
	},
	"crate": {
		"description": "low top-down view wooden crate, slight 3/4 angle showing top and sides, medieval storage box, nailed planks visible, pixel art",
		"footprint": "crate",  # 2x2 grid cells
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
	},
	"well": {
		"description": "low top-down view stone well, slight 3/4 angle showing depth, circular stone wall, wooden roof frame with bucket and rope, medieval village style, pixel art",
		"footprint": "well",  # 3x3 grid cells
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	},
	"bench": {
		"description": "low top-down view wooden bench, slight 3/4 angle, simple medieval design, sturdy plank seat with legs visible, pixel art",
		"footprint": "bench",  # 2x2 grid cells
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
	},
	"cart": {
		"description": "low top-down view wooden cart, slight 3/4 angle showing wheels and cargo bed, two spoked wheels, open top for goods, medieval merchant style, pixel art",
		"footprint": "cart",  # 3x3 grid cells
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
	},
	"lamppost": {
		"description": "low top-down view medieval street lamp, slight 3/4 angle showing full height, wrought iron post, glass lantern with warm glow, pixel art",
		"footprint": "lamppost",  # 2x2 grid cells
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
	},
	"tree_oak_1": {
		"description": "low top-down view oak tree, slight 3/4 angle, thick gnarled trunk visible at base, full rounded green canopy with depth, natural forest tree, pixel art",
		"footprint": "tree",
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	},
	"tree_pine_1": {
		"description": "low top-down view pine tree, slight 3/4 angle, straight trunk visible, triangular layered dark green canopy, conifer forest style, pixel art",
		"footprint": "tree",
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	},
	"tree_willow_1": {
		"description": "low top-down view weeping willow tree, slight 3/4 angle, graceful trunk visible, drooping cascading branches, soft green foliage, pixel art",
		"footprint": "tree",
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	},
	"tree_birch_1": {
		"description": "low top-down view birch tree, slight 3/4 angle, distinctive white bark trunk visible, yellow-green leaf canopy, slender elegant form, pixel art",
		"footprint": "tree",
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	},
	"tree_maple_1": {
		"description": "low top-down view autumn maple tree, slight 3/4 angle, sturdy trunk visible, vibrant red-orange foliage, seasonal fall colors, pixel art",
		"footprint": "tree",
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	},
	"tree_apple_1": {
		"description": "low top-down view apple tree, slight 3/4 angle, fruit-bearing branches visible, green canopy dotted with red apples, orchard style, pixel art",
		"footprint": "tree",
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "medium shading",
		"outline": "single color outline",
	},
}

## ===== CHARACTER DEFINITIONS =====
## Characters need multiple rotations and animations

const CHARACTERS := {
	"villager_male": {
		"description": "medieval villager man, simple brown tunic, leather belt, brown pants, short brown hair",
		"name": "Villager Male",
		"n_directions": 8,
		"size": 48,
		"view": "low top-down",
		"proportions": '{"type": "preset", "name": "default"}',
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color black outline",
		"animations": ["walk", "idle"],
	},
	"villager_female": {
		"description": "medieval villager woman, simple blue dress, white apron, brown hair in bun",
		"name": "Villager Female",
		"n_directions": 8,
		"size": 48,
		"view": "low top-down",
		"proportions": '{"type": "preset", "name": "default"}',
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color black outline",
		"animations": ["walk", "idle"],
	},
	"merchant": {
		"description": "medieval merchant, wealthy robes, gold trim, round belly, friendly face, merchant cap",
		"name": "Merchant",
		"n_directions": 8,
		"size": 48,
		"view": "low top-down",
		"proportions": '{"type": "preset", "name": "default"}',
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color black outline",
		"animations": ["walk", "idle"],
	},
	"guard": {
		"description": "medieval town guard, chainmail armor, red tabard, helmet, spear",
		"name": "Guard",
		"n_directions": 8,
		"size": 48,
		"view": "low top-down",
		"proportions": '{"type": "preset", "name": "heroic"}',
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color black outline",
		"animations": ["walk", "idle"],
	},
	"player": {
		"description": "young adventurer, green cloak, leather armor, brown boots, sword at hip, determined expression",
		"name": "Player",
		"n_directions": 8,
		"size": 48,
		"view": "low top-down",
		"proportions": '{"type": "preset", "name": "heroic"}',
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color black outline",
		"animations": ["walk", "idle", "running-4-frames"],
	},
}

## ===== TILESET DEFINITIONS =====
## Tilesets for terrain and floors
## IMPORTANT: Generate in order and chain base_tile_ids for consistency

const TILESETS := {
	# Step 1: Base grass (generates grass_base_tile_id)
	"base_grass": {
		"type": "topdown",
		"chain_order": 1,
		"lower_description": "lush green grass, natural meadow, muted forest green tones, low top-down view",
		"upper_description": "lush green grass, natural meadow, muted forest green tones, low top-down view",
		"transition_size": 0,
		"tile_size": {"width": 16, "height": 16},
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"saves_base_tile_id": "grass",  # Save this ID after generation
	},
	# Step 2: Grass to dirt path (uses grass base, generates dirt_base_tile_id)
	"grass_to_dirt": {
		"type": "topdown",
		"chain_order": 2,
		"lower_description": "brown packed dirt path, worn earth, scattered small pebbles, low top-down view",
		"upper_description": "lush green grass, natural meadow edge, muted green tones, low top-down view",
		"transition_description": "grass naturally thinning into dirt, organic ragged edge with sparse grass blades",
		"transition_size": 0.25,
		"tile_size": {"width": 16, "height": 16},
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"uses_upper_base_tile_id": "grass",  # Chain from base_grass
		"saves_base_tile_id": "dirt",  # Save dirt ID after generation
	},
	# Step 3: Grass to stone plaza (uses grass base, generates stone_base_tile_id)
	"grass_to_stone": {
		"type": "topdown",
		"chain_order": 3,
		"lower_description": "gray flagstone pavement, large flat stone slabs, medieval plaza floor, muted gray tones, low top-down view",
		"upper_description": "lush green grass, natural meadow edge, muted green tones, low top-down view",
		"transition_description": "grass meeting stone edge, some grass growing between stone cracks",
		"transition_size": 0.25,
		"tile_size": {"width": 16, "height": 16},
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"uses_upper_base_tile_id": "grass",  # Chain from base_grass
		"saves_base_tile_id": "stone",  # Save stone ID after generation
	},
	# Step 4: Dirt to stone (for path-to-plaza transitions)
	"dirt_to_stone": {
		"type": "topdown",
		"chain_order": 4,
		"lower_description": "gray flagstone pavement, large flat stone slabs, medieval plaza, low top-down view",
		"upper_description": "brown packed dirt path, worn earth, low top-down view",
		"transition_description": "dirt path meeting stone plaza edge, smooth transition",
		"transition_size": 0.25,
		"tile_size": {"width": 16, "height": 16},
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"uses_lower_base_tile_id": "stone",  # Chain from grass_to_stone
		"uses_upper_base_tile_id": "dirt",   # Chain from grass_to_dirt
	},
}

## ===== BUILDING INTEGRATION ASSETS =====
## Foundation tiles, shadows, and path endpoints for seamless building placement

const FOUNDATIONS := {
	# Foundations match building footprints and sit UNDER buildings
	"foundation_shop": {
		"description": "low top-down view stone foundation pad, flat cobblestone base for building, worn gray stones, slight 3/4 angle showing thickness, medieval style, pixel art",
		"footprint": "shop",  # Matches shop building footprint
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
		"for_building": "gregor_shop",
	},
	"foundation_tavern": {
		"description": "low top-down view large stone foundation pad, flat cobblestone base for tavern, worn gray stones with slight moss, slight 3/4 angle, medieval style, pixel art",
		"footprint": "tavern",  # Matches tavern building footprint
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
		"for_building": "tavern",
	},
	"foundation_blacksmith": {
		"description": "low top-down view stone foundation pad, flat cobblestone with scorched dark areas near forge, heat-stained stones, slight 3/4 angle, medieval smithy style, pixel art",
		"footprint": "blacksmith",  # Matches blacksmith building footprint
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
		"for_building": "blacksmith",
	},
	"foundation_house": {
		"description": "low top-down view simple dirt and stone foundation pad, packed earth with corner stones, slight 3/4 angle, humble cottage base, pixel art",
		"footprint": "house_small",  # Matches house building footprint
		"view": "low top-down",
		"detail": "low detail",
		"shading": "basic shading",
		"outline": "single color outline",
		"for_building": "village_house_1",
	},
}

const GROUND_SHADOWS := {
	# Semi-transparent shadow sprites placed under buildings
	"shadow_shop": {
		"description": "soft building shadow, dark semi-transparent oval shape, ground shadow for medium building, diffuse edges, cast to bottom-right, pixel art",
		"footprint": "shop",
		"opacity": 0.3,
		"offset": {"x": 8, "y": 8},  # Pixels offset from building center
		"for_building": "gregor_shop",
	},
	"shadow_tavern": {
		"description": "soft building shadow, dark semi-transparent large oval shape, ground shadow for large building, diffuse edges, cast to bottom-right, pixel art",
		"footprint": "tavern",
		"opacity": 0.3,
		"offset": {"x": 12, "y": 12},
		"for_building": "tavern",
	},
	"shadow_blacksmith": {
		"description": "soft building shadow, dark semi-transparent irregular shape for open workshop, ground shadow with gaps for open areas, cast to bottom-right, pixel art",
		"footprint": "blacksmith",
		"opacity": 0.25,
		"offset": {"x": 8, "y": 8},
		"for_building": "blacksmith",
	},
	"shadow_house": {
		"description": "soft building shadow, dark semi-transparent small oval shape, ground shadow for cottage, diffuse edges, cast to bottom-right, pixel art",
		"footprint": "house_small",
		"opacity": 0.3,
		"offset": {"x": 6, "y": 6},
		"for_building": "village_house_1",
	},
	"shadow_tree": {
		"description": "soft tree shadow, dark semi-transparent circular shape with irregular edges, dappled leaf shadow pattern, cast to bottom-right, pixel art",
		"footprint": "tree",
		"opacity": 0.25,
		"offset": {"x": 4, "y": 4},
		"for_prop": "tree_oak_1",
	},
}

const PATH_ENDPOINTS := {
	# Transition tiles connecting paths to building entrances
	"path_to_shop_door": {
		"description": "low top-down view path endpoint, dirt path widening into stone doorstep, slight 3/4 angle, worn welcome mat area, connects to building entrance, pixel art",
		"size": {"width": 32, "height": 32},  # 2x2 tiles
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
		"connects_to": "gregor_shop",
		"path_type": "dirt",
	},
	"path_to_tavern_door": {
		"description": "low top-down view path endpoint, dirt path widening into cobblestone entrance area, slight 3/4 angle, welcoming tavern doorstep, connects to large building entrance, pixel art",
		"size": {"width": 48, "height": 32},  # 3x2 tiles
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
		"connects_to": "tavern",
		"path_type": "dirt",
	},
	"path_to_blacksmith": {
		"description": "low top-down view path endpoint, dirt path meeting stone work area, slight 3/4 angle, coal dust stained ground, connects to smithy entrance, pixel art",
		"size": {"width": 32, "height": 32},  # 2x2 tiles
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
		"connects_to": "blacksmith",
		"path_type": "dirt",
	},
	"plaza_to_shop_door": {
		"description": "low top-down view path endpoint, stone plaza meeting shop doorstep, slight 3/4 angle, seamless stone transition, connects to building entrance, pixel art",
		"size": {"width": 32, "height": 32},  # 2x2 tiles
		"view": "low top-down",
		"detail": "medium detail",
		"shading": "basic shading",
		"outline": "single color outline",
		"connects_to": "gregor_shop",
		"path_type": "stone",
	},
}

## ===== HELPER METHODS =====

## Get the PixelLab MCP parameters for a building
static func get_building_params(building_id: String) -> Dictionary:
	if not BUILDINGS.has(building_id):
		return {}

	var def = BUILDINGS[building_id]
	var footprint = _GridLayout.FOOTPRINTS.get(def.footprint, Vector2i(5, 4))
	var pixellab_size = _GridLayout.get_pixellab_size_for_footprint(footprint)

	return {
		"description": def.description,
		"width": pixellab_size.x,
		"height": pixellab_size.y,
		"view": def.get("view", "low top-down"),
		"detail": def.get("detail", "medium detail"),
		"shading": def.get("shading", "medium shading"),
		"outline": def.get("outline", "single color outline"),
	}

## Get the PixelLab MCP parameters for a prop
static func get_prop_params(prop_id: String) -> Dictionary:
	if not PROPS.has(prop_id):
		return {}

	var def = PROPS[prop_id]
	var footprint = _GridLayout.FOOTPRINTS.get(def.footprint, Vector2i(2, 2))
	var pixellab_size = _GridLayout.get_pixellab_size_for_footprint(footprint)

	return {
		"description": def.description,
		"width": pixellab_size.x,
		"height": pixellab_size.y,
		"view": def.get("view", "low top-down"),
		"detail": def.get("detail", "medium detail"),
		"shading": def.get("shading", "basic shading"),
		"outline": def.get("outline", "single color outline"),
	}

## Get the PixelLab MCP parameters for a character
static func get_character_params(character_id: String) -> Dictionary:
	if not CHARACTERS.has(character_id):
		return {}

	var def = CHARACTERS[character_id]
	return {
		"description": def.description,
		"name": def.get("name", character_id),
		"n_directions": def.get("n_directions", 8),
		"size": def.get("size", 48),
		"view": def.get("view", "low top-down"),
		"proportions": def.get("proportions", '{"type": "preset", "name": "default"}'),
		"detail": def.get("detail", "medium detail"),
		"shading": def.get("shading", "basic shading"),
		"outline": def.get("outline", "single color black outline"),
	}

## Get the list of animations for a character
static func get_character_animations(character_id: String) -> Array:
	if not CHARACTERS.has(character_id):
		return ["walk", "idle"]
	return CHARACTERS[character_id].get("animations", ["walk", "idle"])

## Get the PixelLab MCP parameters for a tileset
static func get_tileset_params(tileset_id: String) -> Dictionary:
	if not TILESETS.has(tileset_id):
		return {}

	var def = TILESETS[tileset_id]
	return {
		"lower_description": def.lower_description,
		"upper_description": def.upper_description,
		"transition_description": def.get("transition_description", ""),
		"transition_size": def.get("transition_size", 0),
		"tile_size": def.get("tile_size", {"width": 16, "height": 16}),
		"view": def.get("view", "low top-down"),
		"detail": def.get("detail", "medium detail"),
		"shading": def.get("shading", "basic shading"),
		# Chaining fields for connected tilesets
		"chain_order": def.get("chain_order", 0),
		"uses_lower_base_tile_id": def.get("uses_lower_base_tile_id", ""),
		"uses_upper_base_tile_id": def.get("uses_upper_base_tile_id", ""),
		"saves_base_tile_id": def.get("saves_base_tile_id", ""),
	}

## Get tilesets sorted by chain order for proper generation sequence
static func get_tilesets_in_chain_order() -> Array:
	var tilesets_with_order = []
	for id in TILESETS:
		var def = TILESETS[id]
		tilesets_with_order.append({
			"id": id,
			"order": def.get("chain_order", 99)
		})
	tilesets_with_order.sort_custom(func(a, b): return a.order < b.order)
	return tilesets_with_order.map(func(t): return t.id)

## Get the PixelLab MCP parameters for a foundation
static func get_foundation_params(foundation_id: String) -> Dictionary:
	if not FOUNDATIONS.has(foundation_id):
		return {}

	var def = FOUNDATIONS[foundation_id]
	var footprint = _GridLayout.FOOTPRINTS.get(def.footprint, Vector2i(5, 4))
	var pixellab_size = _GridLayout.get_pixellab_size_for_footprint(footprint)

	return {
		"description": def.description,
		"width": pixellab_size.x,
		"height": pixellab_size.y,
		"view": def.get("view", "low top-down"),
		"detail": def.get("detail", "medium detail"),
		"shading": def.get("shading", "basic shading"),
		"outline": def.get("outline", "single color outline"),
		"for_building": def.get("for_building", ""),
	}

## Get the PixelLab MCP parameters for a ground shadow
static func get_shadow_params(shadow_id: String) -> Dictionary:
	if not GROUND_SHADOWS.has(shadow_id):
		return {}

	var def = GROUND_SHADOWS[shadow_id]
	var footprint = _GridLayout.FOOTPRINTS.get(def.footprint, Vector2i(5, 4))
	var pixellab_size = _GridLayout.get_pixellab_size_for_footprint(footprint)

	return {
		"description": def.description,
		"width": pixellab_size.x,
		"height": pixellab_size.y,
		"opacity": def.get("opacity", 0.3),
		"offset": def.get("offset", {"x": 8, "y": 8}),
		"for_building": def.get("for_building", ""),
		"for_prop": def.get("for_prop", ""),
	}

## Get the PixelLab MCP parameters for a path endpoint
static func get_path_endpoint_params(endpoint_id: String) -> Dictionary:
	if not PATH_ENDPOINTS.has(endpoint_id):
		return {}

	var def = PATH_ENDPOINTS[endpoint_id]
	var size = def.get("size", {"width": 32, "height": 32})

	return {
		"description": def.description,
		"width": size.width,
		"height": size.height,
		"view": def.get("view", "low top-down"),
		"detail": def.get("detail", "medium detail"),
		"shading": def.get("shading", "basic shading"),
		"outline": def.get("outline", "single color outline"),
		"connects_to": def.get("connects_to", ""),
		"path_type": def.get("path_type", "dirt"),
	}

## Get path where a pre-generated asset should be saved/loaded
static func get_asset_path(asset_type: String, asset_id: String) -> String:
	match asset_type:
		"building":
			return "%s/buildings/%s.png" % [BASE_PATH, asset_id]
		"prop":
			return "%s/props/%s.png" % [BASE_PATH, asset_id]
		"character":
			return "%s/characters/%s/sprite_frames.tres" % [BASE_PATH, asset_id]
		"tileset":
			return "%s/tilesets/%s/tileset.png" % [BASE_PATH, asset_id]
		"foundation":
			return "%s/foundations/%s.png" % [BASE_PATH, asset_id]
		"shadow":
			return "%s/shadows/%s.png" % [BASE_PATH, asset_id]
		"path_endpoint":
			return "%s/path_endpoints/%s.png" % [BASE_PATH, asset_id]
		_:
			return "%s/misc/%s.png" % [BASE_PATH, asset_id]

## Check if a pre-generated asset exists
static func has_pregenerated(asset_type: String, asset_id: String) -> bool:
	var path = get_asset_path(asset_type, asset_id)
	return ResourceLoader.exists(path)

## Get all asset IDs that need generation
static func get_missing_assets() -> Dictionary:
	var missing = {
		"buildings": [],
		"props": [],
		"characters": [],
		"tilesets": [],
		"foundations": [],
		"shadows": [],
		"path_endpoints": [],
	}

	for id in BUILDINGS:
		if not has_pregenerated("building", id):
			missing.buildings.append(id)

	for id in PROPS:
		if not has_pregenerated("prop", id):
			missing.props.append(id)

	for id in CHARACTERS:
		if not has_pregenerated("character", id):
			missing.characters.append(id)

	for id in TILESETS:
		if not has_pregenerated("tileset", id):
			missing.tilesets.append(id)

	for id in FOUNDATIONS:
		if not has_pregenerated("foundation", id):
			missing.foundations.append(id)

	for id in GROUND_SHADOWS:
		if not has_pregenerated("shadow", id):
			missing.shadows.append(id)

	for id in PATH_ENDPOINTS:
		if not has_pregenerated("path_endpoint", id):
			missing.path_endpoints.append(id)

	return missing

## Print generation status
static func print_status() -> void:
	print("=== ASSET MANIFEST STATUS ===")

	var total = 0
	var generated = 0

	print("\nBuildings:")
	for id in BUILDINGS:
		total += 1
		var exists = has_pregenerated("building", id)
		if exists:
			generated += 1
		print("  [%s] %s" % ["OK" if exists else "MISSING", id])

	print("\nProps:")
	for id in PROPS:
		total += 1
		var exists = has_pregenerated("prop", id)
		if exists:
			generated += 1
		print("  [%s] %s" % ["OK" if exists else "MISSING", id])

	print("\nCharacters:")
	for id in CHARACTERS:
		total += 1
		var exists = has_pregenerated("character", id)
		if exists:
			generated += 1
		print("  [%s] %s" % ["OK" if exists else "MISSING", id])

	print("\nTilesets (chain order):")
	for id in get_tilesets_in_chain_order():
		total += 1
		var exists = has_pregenerated("tileset", id)
		if exists:
			generated += 1
		var def = TILESETS[id]
		var chain_info = "order:%d" % def.get("chain_order", 0)
		if def.has("uses_upper_base_tile_id"):
			chain_info += " uses:%s" % def.uses_upper_base_tile_id
		if def.has("saves_base_tile_id"):
			chain_info += " saves:%s" % def.saves_base_tile_id
		print("  [%s] %s (%s)" % ["OK" if exists else "MISSING", id, chain_info])

	print("\nFoundations:")
	for id in FOUNDATIONS:
		total += 1
		var exists = has_pregenerated("foundation", id)
		if exists:
			generated += 1
		print("  [%s] %s (for: %s)" % ["OK" if exists else "MISSING", id, FOUNDATIONS[id].for_building])

	print("\nGround Shadows:")
	for id in GROUND_SHADOWS:
		total += 1
		var exists = has_pregenerated("shadow", id)
		if exists:
			generated += 1
		var target = GROUND_SHADOWS[id].get("for_building", GROUND_SHADOWS[id].get("for_prop", ""))
		print("  [%s] %s (for: %s)" % ["OK" if exists else "MISSING", id, target])

	print("\nPath Endpoints:")
	for id in PATH_ENDPOINTS:
		total += 1
		var exists = has_pregenerated("path_endpoint", id)
		if exists:
			generated += 1
		print("  [%s] %s (%s -> %s)" % ["OK" if exists else "MISSING", id, PATH_ENDPOINTS[id].path_type, PATH_ENDPOINTS[id].connects_to])

	print("\nTotal: %d/%d generated" % [generated, total])
