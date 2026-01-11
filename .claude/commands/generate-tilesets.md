# Generate Terrain Tilesets

Generate all terrain tilesets for the game using PixelLab MCP.

## CRITICAL: Generation Order

Tilesets MUST be generated in chain order to ensure visual consistency.
Each tileset can reference base tile IDs from previous tilesets.

## Tilesets to Generate (IN ORDER)

### 1. Base Grass (chain_order: 1)
- Lower: "lush green grass, natural meadow, muted forest green tones, low top-down view"
- Upper: (same as lower)
- Transition: none (single terrain)
- **SAVES**: grass base tile ID

### 2. Grass to Dirt (chain_order: 2)
- Lower: "brown packed dirt path, worn earth, scattered small pebbles, low top-down view"
- Upper: "lush green grass, natural meadow edge, muted green tones, low top-down view"
- Transition: "grass naturally thinning into dirt, organic ragged edge with sparse grass blades"
- **USES**: grass base tile ID (from step 1)
- **SAVES**: dirt base tile ID

### 3. Grass to Stone (chain_order: 3)
- Lower: "gray flagstone pavement, large flat stone slabs, medieval plaza floor, muted gray tones, low top-down view"
- Upper: "lush green grass, natural meadow edge, muted green tones, low top-down view"
- Transition: "grass meeting stone edge, some grass growing between stone cracks"
- **USES**: grass base tile ID (from step 1)
- **SAVES**: stone base tile ID

### 4. Dirt to Stone (chain_order: 4)
- Lower: "gray flagstone pavement, large flat stone slabs, medieval plaza, low top-down view"
- Upper: "brown packed dirt path, worn earth, low top-down view"
- Transition: "dirt path meeting stone plaza edge, smooth transition"
- **USES**: stone base tile ID (from step 3), dirt base tile ID (from step 2)

## Generation Parameters
```
view: "low top-down"
tile_size: {"width": 16, "height": 16}
detail: "medium detail"
shading: "basic shading"
transition_size: 0.25
```

## Steps to Execute

1. Generate `base_grass` tileset first
   - Call `mcp__pixellab__create_topdown_tileset`
   - Wait for completion, save the **grass base tile ID**

2. Generate `grass_to_dirt` tileset
   - Call with `upper_base_tile_id` = grass base tile ID
   - Wait for completion, save the **dirt base tile ID**

3. Generate `grass_to_stone` tileset
   - Call with `upper_base_tile_id` = grass base tile ID
   - Wait for completion, save the **stone base tile ID**

4. Generate `dirt_to_stone` tileset
   - Call with `lower_base_tile_id` = stone base tile ID
   - Call with `upper_base_tile_id` = dirt base tile ID
   - Wait for completion

5. Download all tilesets to `/Users/zzeid/github/Land/assets/generated/tilesets/`:
   - base_grass/tileset.png + metadata.json
   - grass_to_dirt/tileset.png + metadata.json
   - grass_to_stone/tileset.png + metadata.json
   - dirt_to_stone/tileset.png + metadata.json

6. Run Godot import:
   ```
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/zzeid/github/Land --import
   ```

7. Run tileset converter:
   ```
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/zzeid/github/Land --script scripts/generation/tileset_converter.gd
   ```

## Output
Report:
- All tileset IDs
- Base tile IDs saved at each step
- Download URLs for each tileset
