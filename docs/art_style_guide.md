# Thornhaven Art Style Guide

## Visual Style
- **Genre**: Top-down 2D RPG (low top-down perspective with slight angle)
- **Pixel Scale**: 16px tiles, assets scaled 2x in-game
- **Color Palette**: Earthy, muted tones - greens, browns, grays
- **Time Period**: Medieval fantasy village

## CRITICAL: Unified View Angle

**ALL assets MUST use `view: "low top-down"`**

This provides:
- Slight angle showing building facades (not just roofs)
- Depth and visual interest
- Consistent perspective across all game elements

Do NOT mix "high top-down" and "low top-down" - this causes visual inconsistency.

## PixelLab Generation Parameters

### Tilesets
```
view: "low top-down"
tile_size: 16x16
detail: "medium detail"
shading: "basic shading"
transition_size: 0.25
tile_strength: 1.5          # Good pattern consistency
tileset_adherence: 300      # Balanced structure
tileset_adherence_freedom: 200  # Some flexibility for natural look
text_guidance_scale: 12     # Strong but not rigid prompt following
```

**Tileset Chaining (REQUIRED):**
Generate tilesets in order, passing base_tile_id from previous:
1. Base grass tileset → save grass_base_tile_id
2. Grass-to-dirt → use grass_base_tile_id as upper_base_tile_id
3. Grass-to-stone → use grass_base_tile_id as upper_base_tile_id
4. Dirt-to-stone → use dirt_base_tile_id as lower, stone as upper

### Buildings
```
view: "low top-down"
detail: "medium detail"
shading: "medium shading"
outline: "single color outline"
```

**Building prompts must include:**
- "low top-down view showing front facade and roof"
- "visible door at ground level"
- "slight 3/4 angle"

### Props
```
view: "low top-down"
detail: "medium detail"
shading: "basic shading"
outline: "single color outline"
```

### Building Integration Assets
Every building needs companion assets:
1. **Foundation tile** - ground pad matching terrain (dirt/stone)
2. **Ground shadow** - soft shadow sprite placed under building
3. **Path endpoint** - connects pathway to building door

## Terrain Types
1. **Grass** (base terrain)
   - "lush green grass, natural meadow, muted green tones, low top-down view"

2. **Dirt** (paths)
   - "brown packed dirt, worn earth path, muted brown tones, low top-down view"

3. **Stone** (town square, foundations)
   - "gray flagstone, flat stone slabs, muted gray tones, medieval plaza, low top-down view"

## Tileset Chaining Order
Generate in this EXACT order, saving base_tile_ids:
1. **Base Grass** → save `grass_base_tile_id`
2. **Grass-to-Dirt** → uses `grass_base_tile_id` as upper, save `dirt_base_tile_id`
3. **Grass-to-Stone** → uses `grass_base_tile_id` as upper, save `stone_base_tile_id`
4. **Dirt-to-Stone** → uses saved IDs for seamless plaza/path transitions

## Building Style
- Timber-frame construction
- Thatched or shingled roofs
- Warm wood tones with white/cream walls
- **Visible front facade with door** (low top-down requirement)
- Slight 3/4 angle showing depth

## Prop Style
- Weathered wood
- Iron/metal accents
- Functional medieval items
- Consistent shadow direction (bottom-right)
- **Low top-down perspective** matching buildings

## Building Integration System

### Foundation Tiles
Each building type needs a matching foundation:
- **Shop/House foundation**: 5x4 grid, stone or dirt base
- **Tavern foundation**: 6x5 grid, cobblestone base
- **Blacksmith foundation**: 5x4 grid, stone with scorched areas

### Ground Shadows
Semi-transparent shadow sprites:
- Placed on layer BELOW building
- Offset bottom-right from building center
- Soft edges, 30% opacity black

### Path Endpoints
Transition tiles that connect paths to buildings:
- Match door location of each building
- Blend from path material to foundation material
- 2x2 tile size minimum

## Pathway Network Rules
1. All buildings must connect to the main path network
2. Paths should form logical routes (not random)
3. Minimum path width: 2 tiles (allows NPC passing)
4. Path intersections use appropriate transition tiles
