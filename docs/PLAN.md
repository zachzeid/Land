# World Physics & Scene Architecture Plan

## Overview
Establish core game physics systems that all world elements (towns, dungeons, wilderness) adhere to, then apply them to Thornhaven as the first implementation.

---

## Part 1: Core Physics Architecture

### 1.1 Collision Layer System (Global)

Define consistent collision layers used across all scenes:

| Layer | Name | Purpose |
|-------|------|---------|
| 1 | `player` | Player character body |
| 2 | `npc` | NPC character bodies |
| 3 | `world_solid` | Impassable terrain (buildings, walls, cliffs) |
| 4 | `world_obstacle` | Partial obstacles (trees, rocks - block body, not vision) |
| 5 | `interactable` | Interactive zones (doors, NPCs, items) |
| 6 | `trigger` | Scene transitions, events |
| 7 | `projectile` | Arrows, spells (future) |
| 8 | `water` | Swimmable/dangerous areas |

**Collision Matrix:**
- Player collides with: `world_solid`, `world_obstacle`, `npc`
- Player overlaps (Area2D): `interactable`, `trigger`
- NPC collides with: `world_solid`, `world_obstacle`, `player`, `npc`
- Projectile collides with: `world_solid`, `player`, `npc`

### 1.2 World Object Types (Base Classes)

Create reusable components that any scene can use:

**`WorldSolid`** - Impassable structures
- Extends `StaticBody2D`
- Collision layer: `world_solid`
- Used for: building walls, cliff faces, boundary walls
- Has `GeneratableAsset` for AI visuals

**`WorldObstacle`** - Partial blockers
- Extends `StaticBody2D`
- Collision layer: `world_obstacle`
- Has smaller collision than visual (e.g., tree trunk vs canopy)
- Player blocked but can see over/around

**`WorldProp`** - Non-blocking scenery
- Extends `Node2D` (no collision)
- Used for: grass, flowers, puddles, cracks
- Pure visual decoration

**`Interactable`** - Objects player can interact with
- Extends `Area2D`
- Collision layer: `interactable`
- Signals: `interaction_available`, `interacted`
- Base class for doors, chests, wells, signs

**`SceneTrigger`** - Zone transitions
- Extends `Area2D`
- Collision layer: `trigger`
- Properties: `target_scene`, `spawn_point`
- Used for: building doors, cave entrances, town exits

### 1.3 Location System (Global)

**Location Hierarchy:**
```
World
├── Region (e.g., "Western Valley")
│   ├── Area (e.g., "Thornhaven Village")
│   │   ├── Zone (e.g., "Town Square", "Gregor's Shop Interior")
│   │   │   └── NPCs, Objects, Interactables
```

**Location Data Resource:**
- Create `LocationData.gd` resource type
- Properties: `location_id`, `display_name`, `region`, `scene_path`, `spawn_points`
- NPCs reference location by ID, not scene path

### 1.4 Scene Manager (Autoload)

**SceneManager** handles all scene transitions:
```gdscript
# Properties
var current_location: LocationData
var previous_location: LocationData
var spawn_point: String

# Methods
func transition_to(location_id: String, spawn_point: String = "default")
func get_current_location() -> LocationData
func get_npcs_at_location(location_id: String) -> Array
```

**Transition Flow:**
1. Emit `scene_transition_started`
2. Fade out (0.3s)
3. Save volatile state (player position, open dialogs)
4. Load new scene
5. Position player at spawn point
6. Filter NPCs by location
7. Fade in (0.3s)
8. Emit `scene_transition_completed`

### 1.5 NPC Location Binding

**Additions to `base_npc.gd`:**
```gdscript
@export var home_location: String = ""  # Where NPC spawns/lives
var current_location: String = ""        # Where NPC currently is

func is_at_location(location_id: String) -> bool
func move_to_location(location_id: String)  # For schedules
```

**NPC Visibility Rules:**
- NPCs only visible/active when `current_location == SceneManager.current_location.location_id`
- NPCs inside buildings aren't visible from outside
- NPCs can move between locations (for schedules, quests)

---

## Part 2: Scene Structure Standards

### 2.1 Exterior Scene Template
```
[SceneName] (Node2D)
├── Environment (Node2D)
│   ├── Ground (TileMap or large ColorRect)
│   ├── TerrainFeatures (WorldSolid/WorldObstacle)
│   └── Decorations (WorldProp)
├── Structures (Node2D)
│   ├── Building1 (WorldSolid + Interactable door)
│   ├── Building2 (WorldSolid + Interactable door)
│   └── ...
├── Obstacles (Node2D)
│   ├── Tree1 (WorldObstacle)
│   ├── Rock1 (WorldObstacle)
│   └── ...
├── Boundaries (Node2D)
│   └── SceneBoundary (WorldSolid - invisible walls)
├── Transitions (Node2D)
│   ├── ToBuilding1 (SceneTrigger)
│   ├── ToWorldMap (SceneTrigger)
│   └── ...
├── SpawnPoints (Node2D)
│   ├── default (Marker2D)
│   ├── from_building1 (Marker2D)
│   └── ...
├── NPCs (Node2D)
│   └── [NPCs with home_location matching this scene]
├── Player (CharacterBody2D) - instantiated by SceneManager
└── UI (CanvasLayer)
```

### 2.2 Interior Scene Template
```
[InteriorName] (Node2D)
├── Room (Node2D)
│   ├── Floor (visual)
│   ├── Walls (WorldSolid - collision around edges)
│   └── Furniture (WorldObstacle for tables, WorldProp for rugs)
├── Interactables (Node2D)
│   ├── Counter (Interactable)
│   ├── Chest (Interactable)
│   └── ...
├── Exit (SceneTrigger) - back to exterior
├── SpawnPoints (Node2D)
│   └── from_exterior (Marker2D)
├── NPCs (Node2D)
│   └── [NPCs with home_location matching this interior]
└── UI (CanvasLayer)
```

---

## Part 3: Apply to Thornhaven

### 3.1 Create Location Data
- `thornhaven_town_square` - Main exterior
- `thornhaven_gregor_shop` - Shop interior
- `thornhaven_tavern` - Tavern interior
- `thornhaven_blacksmith` - Smithy interior

### 3.2 Refactor game_world.tscn
1. Add collision to all buildings (WorldSolid)
2. Add collision to trees (WorldObstacle - trunk only)
3. Add town boundary (invisible WorldSolid walls)
4. Add SceneTrigger at each building door
5. Add SpawnPoints for each entry/exit
6. Set Elena's `home_location = "thornhaven_town_square"`

### 3.3 Create Interior Scenes
1. `gregor_shop_interior.tscn`
   - Small shop room with counter, shelves
   - Gregor NPC (`home_location = "thornhaven_gregor_shop"`)
   - Exit trigger back to town square

2. `tavern_interior.tscn`
   - Bar area, tables, fireplace
   - Future: bartender NPC, patrons
   - Exit trigger back to town square

3. `blacksmith_interior.tscn`
   - Forge, anvil, weapon racks
   - Future: blacksmith NPC
   - Exit trigger back to town square

---

## Part 4: Implementation Order

### Phase 1: Core Systems (No scene changes yet)
1. Create collision layer constants in project settings
2. Create `WorldSolid`, `WorldObstacle`, `WorldProp` base scripts
3. Create `Interactable` base class
4. Create `SceneTrigger` component
5. Create `LocationData` resource type
6. Create `SceneManager` autoload
7. Add location properties to `base_npc.gd`

### Phase 2: Apply to Thornhaven Exterior
8. Add collisions to buildings in game_world.tscn
9. Add collisions to trees
10. Add town boundary walls
11. Add spawn points
12. Create LocationData for town square
13. Test: player blocked by buildings/trees

### Phase 3: First Interior (Gregor's Shop)
14. Create `gregor_shop_interior.tscn`
15. Move Gregor NPC to interior scene
16. Add door triggers (exterior → interior)
17. Add exit trigger (interior → exterior)
18. Test: full enter/exit/talk flow

### Phase 4: Remaining Interiors
19. Create tavern interior
20. Create blacksmith interior
21. Connect all transitions
22. Add GeneratableAssets for interior props

---

## File Structure

```
scripts/
├── world/
│   ├── world_solid.gd         # Impassable collision
│   ├── world_obstacle.gd      # Partial collision
│   ├── world_prop.gd          # No collision
│   ├── interactable.gd        # Base interaction
│   ├── scene_trigger.gd       # Scene transitions
│   ├── scene_manager.gd       # Transition controller
│   └── location_data.gd       # Location resource

scenes/
├── game_world.tscn            # Thornhaven exterior (refactored)
├── interiors/
│   ├── gregor_shop_interior.tscn
│   ├── tavern_interior.tscn
│   └── blacksmith_interior.tscn

resources/
└── locations/
    ├── thornhaven_town_square.tres
    ├── thornhaven_gregor_shop.tres
    ├── thornhaven_tavern.tres
    └── thornhaven_blacksmith.tres
```

---

## Design Principles

1. **Consistency**: Same physics rules everywhere - a tree in Thornhaven blocks like a tree in a forest
2. **Composability**: Mix and match components (WorldSolid + GeneratableAsset + Interactable)
3. **Data-Driven**: Locations and NPC bindings in resources, not hardcoded
4. **Separation**: Physics (collision) separate from visuals (assets) separate from behavior (interactions)

---

## Part 5: World Layout & Visual Standards

### 5.1 Playable Area Bounds

**Standard Zone Size: 1024x1024 pixels**

All exterior zones should fit within a 1024x1024 playable area:
- Origin at center (0,0)
- Bounds: -512 to +512 on both axes
- Camera viewport shows ~640x360 at 1.5x zoom (1920x1080 / 3)

**Why 1024x1024:**
- Clean power-of-2 for texture alignment
- Manageable asset count (~20-40 objects per zone)
- Fits Recraft's native generation sizes (1024x1024)
- Allows consistent asset scaling across zones

**Interior zones can be smaller:**
- Small rooms: 256x256 (shops, bedrooms)
- Medium rooms: 384x384 (tavern main hall)
- Large rooms: 512x512 (castle throne room)

### 5.2 Asset Size Grid

Standardized asset sizes for consistent visual density:

| Category | Grid Units | Pixel Size | Examples |
|----------|------------|------------|----------|
| **Tiny** | 1x1 | 32x32 | Flowers, rocks, debris |
| **Small** | 2x2 | 64x64 | Barrels, crates, signs, lamps |
| **Medium** | 3x3 | 96x96 | Well, cart, bench, small trees |
| **Large** | 4x4 | 128x128 | Trees, large props |
| **Building-S** | 4x4 | 128x128 | Small house, shed |
| **Building-M** | 5x4 | 160x128 | Shop, standard house |
| **Building-L** | 6x5 | 192x160 | Tavern, blacksmith |
| **Character** | 1x1.5 | 32x48 | Player, NPCs |

**Grid unit = 32 pixels** (matches player width)

### 5.3 Recraft Prompt Guidelines

**Recraft API Settings:**
- Style: `digital_illustration` (best for game assets)
- Size: `1024x1024` (square, scale down in-game)
- Substyle options: `pixel_art`, `hand_drawn`, `2d_art_poster`

#### Global Style Prefix (applied to ALL assets):
```
"2D isometric game sprite, 3/4 top-down view at 30-degree angle, medieval fantasy RPG style,
painterly hand-drawn look, warm earth tones, soft diffused lighting, transparent background,
centered composition, clean edges suitable for game use, consistent isometric perspective"
```

#### Zone Theme Descriptors:

**Thornhaven Village:**
```
"rustic medieval village aesthetic, weathered wooden textures,
thatched straw roofs, cobblestone and dirt paths,
cozy lived-in feel, autumn color palette"
```

**Forest/Wilderness:**
```
"enchanted forest atmosphere, dappled sunlight through leaves,
moss-covered surfaces, ancient towering trees,
mysterious and serene, green and brown earth tones"
```

**Dungeon/Cave:**
```
"dark underground dungeon, rough hewn stone walls,
flickering torchlight, damp mossy surfaces,
ominous shadows, gray and orange firelit palette"
```

---

### 5.4 Asset-Specific Prompt Templates

#### Buildings

**Structure:** `[isometric view] + [size] + [type] + [details] + [style notes]`

**Small House:**
```
"isometric 2D game building, 3/4 view showing front and right side,
small single-story cottage, wooden plank walls with visible grain,
steep thatched roof angled for isometric view,
single wooden door on front face, one shuttered window on side,
chimney with light smoke, flower box under window,
rustic medieval village style, warm browns and golden thatch"
```

**Shop/Store:**
```
"isometric 2D game building, 3/4 view showing front and right side,
medieval merchant shop, two-story timber-frame construction,
plastered white walls with dark wood beams,
shingled roof at isometric angle with small dormer window,
large front window display, hanging wooden sign bracket (no text),
worn stone doorstep, busy village commerce feel, cream and dark brown colors"
```

**Tavern/Inn:**
```
"isometric 2D game building, 3/4 view showing front and right side,
large medieval tavern, two-story stone and timber construction,
wide welcoming entrance on front face,
multiple chimneys with smoke, warm light glowing from windows,
barrel storage visible on side wall, wooden sign post,
inviting and well-maintained, amber and gray stone colors"
```

**Blacksmith:**
```
"isometric 2D game building, 3/4 view showing front and right side,
medieval blacksmith forge, open-air covered workspace,
prominent stone chimney with heavy smoke,
anvil visible under awning, weapon racks on exterior wall,
coal and metal storage, water barrel nearby,
industrial working atmosphere, dark iron and red brick colors"
```

#### Trees & Nature

**Oak Tree:**
```
"isometric 2D game tree, 3/4 view from above,
single large oak tree, thick gnarled trunk visible at base,
full rounded canopy with depth, individual leaf clusters visible,
natural asymmetric shape, casting shadow to bottom-right,
trunk clearly separated from foliage at bottom,
forest green canopy with yellow-green highlights"
```

**Pine/Evergreen:**
```
"isometric 2D game tree, 3/4 view from above,
tall conifer pine tree, straight narrow trunk visible,
triangular layered branches with depth,
dark green needles, pointed top silhouette,
clear trunk base visible at bottom"
```

**Bush/Shrub:**
```
"isometric 2D game prop, 3/4 view from above,
round flowering bush, dense leafy growth with volume,
small colorful flowers scattered, low to ground,
soft natural edges, shadow to bottom-right,
garden decoration style, green with pink/white flower accents"
```

#### Props & Objects

**Barrel:**
```
"isometric 2D game prop, 3/4 view from above,
wooden storage barrel, vertical wood planks with metal bands,
slightly weathered with stains, showing top and side,
shadow to bottom-right, medieval village storage item,
brown wood with iron gray bands"
```

**Crate/Box:**
```
"isometric 2D game prop, 3/4 view from above,
wooden shipping crate, rough planks nailed together,
showing top and two visible sides, rope handles,
stamped or branded marking (no text),
trade goods container style, pale unfinished wood color"
```

**Well:**
```
"isometric 2D game prop, 3/4 view from above,
medieval stone village well, circular stone wall construction,
wooden roof structure with depth, rope and bucket mechanism,
cobblestone base platform visible, shadow to bottom-right,
central village gathering point, gray stone with wood brown roof"
```

**Market Cart:**
```
"isometric 2D game prop, 3/4 view from above,
wooden merchant cart, two large spoked wheels at isometric angle,
open cargo area visible from above, pull handles at front,
weathered from travel, shadow to bottom-right,
trade caravan style, warm brown aged wood"
```

**Street Lamp:**
```
"isometric 2D game prop, 3/4 view from above,
medieval iron street lamp, tall wrought iron post,
ornate hanging lantern with warm candle glow effect,
decorative scrollwork, shadow cast to bottom-right,
village night lighting, black iron with amber glass"
```

**Bench:**
```
"isometric 2D game prop, 3/4 view from above,
simple wooden bench, thick plank seat at isometric angle,
sturdy leg supports visible, slightly worn from use,
shadow to bottom-right, village square seating,
plain functional design, weathered gray-brown wood"
```

#### Characters

**Villager NPC:**
```
"isometric 2D game character, 3/4 view facing camera,
medieval village peasant, [gender], [age descriptor],
simple cloth tunic and trousers, leather belt and boots,
carrying [item optional], neutral standing pose at isometric angle,
friendly approachable expression, full body visible,
earth tone clothing, [hair color] hair, shadow to bottom-right"
```

**Merchant NPC:**
```
"isometric 2D game character, 3/4 view facing camera,
medieval shopkeeper, middle-aged [gender],
prosperous but not wealthy appearance,
leather apron over nicer clothes, coin purse at belt,
hands ready to gesture, welcoming business smile,
standing pose at isometric angle, full body visible,
practical merchant attire, shadow to bottom-right"
```

**Guard/Soldier:**
```
"isometric 2D game character, 3/4 view facing camera,
medieval village guard, adult [gender],
leather and chain armor, spear or sword at side,
protective but not aggressive stance at isometric angle,
alert watchful expression, town watch uniform look,
standing at attention, full body visible,
iron gray and leather brown armor, shadow to bottom-right"
```

#### Interior Elements

**Furniture - Table:**
```
"isometric 2D game furniture, 3/4 view from above,
medieval wooden dining table, heavy oak construction,
rectangular shape at isometric angle, thick sturdy legs visible,
plank surface with visible grain, shadow to bottom-right,
tavern or home furniture style, dark stained wood"
```

**Furniture - Chair:**
```
"isometric 2D game furniture, 3/4 view from above,
simple medieval wooden chair, straight back design,
woven seat optional, legs visible at isometric angle,
practical peasant furniture, shadow to bottom-right,
matches table style, medium brown wood"
```

**Fireplace:**
```
"isometric 2D game prop, 3/4 view from above,
stone fireplace hearth, rough cut stone construction,
active fire with warm glow, showing depth and dimension,
iron grate and tools nearby, mantle shelf visible,
cozy interior focal point, gray stone with orange fire"
```

**Counter/Bar:**
```
"isometric 2D game furniture, 3/4 view from above,
medieval tavern bar counter, long wooden serving surface,
polished from use, showing top and front at isometric angle,
storage shelves visible behind, mugs and bottles displayed,
busy tavern atmosphere, dark polished wood"
```

---

### 5.5 Prompt Construction Best Practices

**DO include:**
- Consistent isometric angle ("3/4 view from above", "isometric 2D")
- Size/scale hints ("small", "large", "single", "full")
- Material descriptions ("wooden", "stone", "iron")
- Color guidance ("warm browns", "gray stone", "amber glow")
- Context ("village", "tavern", "forest")
- "transparent background" for sprites
- "game sprite" or "game asset" to signal intended use
- Shadow direction ("shadow to bottom-right") for consistency
- "full body visible" for characters

**DON'T include:**
- Text or letters (Recraft struggles with text)
- Specific UI elements
- Multiple objects in one prompt (generate separately)
- Ambiguous terms without context
- Photo-realistic requests (use painterly/illustrated style)
- Mixed perspective angles (keep all isometric)

**Consistency Tips:**
- Use identical isometric angle (30-degree) for ALL assets in a zone
- Match shadow direction across all assets (bottom-right)
- Reference specific color hex codes in a style guide
- Generate similar items together to maintain style coherence
- Use same style substyle setting for entire zone
- Buildings show front + right side consistently
- Characters face toward camera at isometric angle

---

### 5.6 Visual Density Guidelines

**Exterior Zone Composition (1024x1024):**
- 3-6 buildings (clustered, not grid-aligned)
- 8-15 trees/large obstacles (organic placement)
- 10-20 small props (scattered near buildings/paths)
- 2-4 interactables (well, signs, chests)
- Clear pathways between areas (min 64px wide)

**Visual Layering (Z-index):**
| Z-Index | Layer | Contents |
|---------|-------|----------|
| -10 | Ground | Terrain, paths, grass |
| 0 | Props | Low obstacles, decorations |
| 10 | Characters | Player, NPCs |
| 20 | Buildings | Structures (player walks behind lower portion) |
| 30 | Canopy | Tree tops, awnings (player walks under) |
| 100+ | UI | Dialogs, menus |

### 5.7 Color Palette Reference

**Thornhaven Village Palette:**
```
Ground:     #384F2E (dark forest green)
Paths:      #7A6B57 (dusty brown)
Square:     #6B6152 (warm stone tan)
Wood:       #5C4A3D (weathered brown)
Roofs:      #8B7355 (thatch tan) / #4A4A4A (slate gray)
Foliage:    #4A7A3A (leaf green)
Accents:    #C4A35A (warm gold) / #8B4513 (rust)
```

### 5.8 Implementation: WorldSettings Resource

Create a `WorldSettings` resource to centralize visual configuration:

```gdscript
# scripts/world/world_settings.gd
class_name WorldSettings
extends Resource

@export var zone_size: Vector2 = Vector2(1024, 1024)
@export var grid_unit: int = 32
@export var global_style_prefix: String
@export var zone_style: String
@export_multiline var building_prompt_template: String
@export_multiline var tree_prompt_template: String
@export_multiline var prop_prompt_template: String
@export_multiline var character_prompt_template: String
@export var color_palette: Dictionary

func build_prompt(asset_type: String, details: String) -> String:
    var template = _get_template(asset_type)
    return global_style_prefix + ", " + zone_style + ", " + template.replace("{details}", details)
```

**Usage:** Each zone loads its WorldSettings resource, and GeneratableAsset nodes use it to construct consistent prompts automatically.
