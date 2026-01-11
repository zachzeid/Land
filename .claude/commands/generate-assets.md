# Generate Game Assets

Generate pre-made assets using PixelLab MCP based on the asset manifest.

## Usage
Specify what to generate: `tilesets`, `buildings`, `props`, `characters`, `foundations`, `shadows`, `path_endpoints`, or `all`

## Asset Manifest Location
`/Users/zzeid/github/Land/scripts/generation/asset_manifest.gd`

## CRITICAL: View Angle Consistency
ALL assets MUST use `view: "low top-down"` for visual consistency.
Do NOT mix high and low top-down views.

## Steps

### For Tilesets (GENERATE IN ORDER):
Tilesets must be generated in chain order to ensure visual consistency.

1. Get tileset order: `AssetManifest.get_tilesets_in_chain_order()`
2. For each tileset in order:
   - Call `mcp__pixellab__create_topdown_tileset`
   - If tileset has `uses_upper_base_tile_id` or `uses_lower_base_tile_id`, pass the saved base_tile_id from previous tileset
   - Poll status until complete
   - If tileset has `saves_base_tile_id`, store the base tile ID for later use
3. Download to `assets/generated/tilesets/`
4. Run converter script

**Chain Order:**
1. base_grass → saves grass base tile ID
2. grass_to_dirt → uses grass ID, saves dirt ID
3. grass_to_stone → uses grass ID, saves stone ID
4. dirt_to_stone → uses dirt and stone IDs

### For Buildings:
1. Read definitions from manifest (all use `view: "low top-down"`)
2. Call `mcp__pixellab__create_map_object` for each
3. Poll status until complete
4. Download to `assets/generated/buildings/`

### For Props:
1. Read definitions from manifest (all use `view: "low top-down"`)
2. Call `mcp__pixellab__create_map_object` for each
3. Poll status until complete
4. Download to `assets/generated/props/`

### For Characters:
1. Read character definitions from manifest
2. Call `mcp__pixellab__create_character` for each
3. Poll status until complete
4. Call `mcp__pixellab__animate_character` for animations
5. Download to `assets/generated/characters/`

### For Foundations (Building Integration):
1. Read foundation definitions from manifest
2. Call `mcp__pixellab__create_map_object` for each
3. These match building footprints - place UNDER buildings
4. Download to `assets/generated/foundations/`

### For Shadows (Building Integration):
1. Read shadow definitions from manifest
2. Call `mcp__pixellab__create_map_object` for each
3. Semi-transparent shadow sprites - place between foundation and building
4. Download to `assets/generated/shadows/`

### For Path Endpoints (Building Integration):
1. Read path endpoint definitions from manifest
2. Call `mcp__pixellab__create_map_object` for each
3. Transition tiles connecting paths to building doors
4. Download to `assets/generated/path_endpoints/`

## Output Directories
```
assets/generated/
├── buildings/        # Building sprites
├── props/            # Prop sprites
├── characters/       # Character sprites + animations
├── tilesets/         # Terrain tilesets
├── foundations/      # Building foundation pads
├── shadows/          # Ground shadow sprites
└── path_endpoints/   # Path-to-door transition tiles
```

## Style Matching (Optional)
For maximum consistency, use style matching when generating new assets:
1. Provide existing map screenshot as `background_image`
2. AI will match colors, shading, and style automatically
