# Pathway Planning System

## Overview

This document defines how to plan and generate logical pathway networks that connect buildings in Thornhaven and other zones. Proper pathway planning ensures:

1. Buildings are accessible via logical routes
2. Terrain transitions look natural
3. NPCs can navigate sensibly
4. The village feels lived-in and coherent

## Pathway Network Structure

### Node Types

```
PathNetwork
├── MainPath (spine of the village)
│   ├── Intersection nodes
│   └── Endpoint nodes (village entrance/exit)
├── BranchPaths (connect buildings to main)
│   └── Building connection nodes
└── PlazaAreas (open gathering spaces)
    └── Multi-building connections
```

### Connection Rules

1. **Every building MUST connect to the path network**
   - Direct connection via BranchPath
   - Or faces a Plaza that connects to MainPath

2. **Main Path forms the village spine**
   - Connects village entrance to key destinations
   - At least 3 tiles wide for NPC traffic
   - Uses dirt or cobblestone material

3. **Branch Paths connect individual buildings**
   - 2 tiles wide minimum
   - Short and direct (no meandering)
   - Material matches building type (stone for shops, dirt for houses)

4. **Plazas are gathering nodes**
   - Central plaza connects 3+ buildings
   - Uses stone/cobblestone material
   - Contains props (well, benches, lampposts)

## Thornhaven Layout

```
                    [Village Gate]
                         |
                    MainPath (dirt)
                         |
        +----------------+----------------+
        |                |                |
   [House 1]        [Town Plaza]     [House 2]
                    (cobblestone)
                   /     |     \
                  /      |      \
           [Tavern]   [Well]   [Shop]
                         |
                    MainPath (dirt)
                         |
                   [Blacksmith]
                         |
                    [Forest Exit]
```

## Path Generation Workflow

### Step 1: Define Path Network Data

Create a `PathNetworkData` resource for each zone:

```gdscript
# resources/paths/thornhaven_paths.tres
class_name PathNetworkData
extends Resource

@export var nodes: Array[PathNode]  # All path nodes
@export var segments: Array[PathSegment]  # Connections between nodes
@export var building_connections: Dictionary  # building_id -> node_id
```

### Step 2: Node Placement

Place path nodes at key locations:

```gdscript
var nodes = [
    PathNode.new("gate", Vector2(0, -400), "endpoint"),
    PathNode.new("plaza_center", Vector2(0, 0), "plaza"),
    PathNode.new("tavern_door", Vector2(-200, 100), "building"),
    PathNode.new("shop_door", Vector2(200, 100), "building"),
    PathNode.new("smithy_door", Vector2(0, 300), "building"),
    PathNode.new("forest_exit", Vector2(0, 450), "endpoint"),
]
```

### Step 3: Define Segments

Connect nodes with path segments:

```gdscript
var segments = [
    # Main spine
    PathSegment.new("gate", "plaza_center", "dirt", 3),
    PathSegment.new("plaza_center", "smithy_door", "dirt", 3),
    PathSegment.new("smithy_door", "forest_exit", "dirt", 3),

    # Plaza connections (stone)
    PathSegment.new("plaza_center", "tavern_door", "stone", 2),
    PathSegment.new("plaza_center", "shop_door", "stone", 2),
]
```

### Step 4: Generate Tilemap

Use the path network to paint the TileMap:

```gdscript
func paint_paths(tilemap: TileMap, network: PathNetworkData):
    for segment in network.segments:
        var start = network.get_node(segment.start_node).position
        var end = network.get_node(segment.end_node).position
        paint_path_segment(tilemap, start, end, segment.material, segment.width)
```

## Tileset Requirements

### Required Tilesets (in chain order)

1. `base_grass` - Background terrain
2. `grass_to_dirt` - Dirt path edges
3. `grass_to_stone` - Stone plaza edges
4. `dirt_to_stone` - Path-to-plaza transitions

### Transition Tiles

Each tileset provides 16-23 transition tiles for Wang autotiling:
- Corner pieces (4)
- Edge pieces (4)
- Inner corner pieces (4)
- Full tiles (4+)

## Building Integration

### Foundation Placement

1. Place foundation BEFORE building
2. Foundation extends 1 tile beyond building footprint
3. Foundation material matches nearby path material

### Path Endpoint Tiles

Place at building doors:
1. Detect door position on building
2. Place appropriate path_endpoint tile
3. Endpoint blends path material → foundation material

### Shadow Placement

1. Place shadow sprite AFTER foundation, BEFORE building
2. Offset shadow bottom-right from building center
3. Shadow layer = foundation layer + 1

## Layer Order (Z-Index)

| Z-Index | Layer | Contents |
|---------|-------|----------|
| -20 | Terrain | Grass tilemap |
| -15 | Paths | Dirt/stone tilemap |
| -10 | Foundations | Building foundation sprites |
| -5 | Shadows | Ground shadow sprites |
| 0 | Props | Barrels, crates, etc. |
| 10 | Buildings | Building sprites |
| 20 | Characters | Player, NPCs |
| 30 | Canopy | Tree tops (walk under) |

## Example: Adding a New Building

When adding a new building to Thornhaven:

1. **Choose location** - Must be adjacent to existing path or plaza
2. **Add path node** - Create building connection node at door location
3. **Add path segment** - Connect to nearest MainPath or Plaza node
4. **Generate foundation** - Create foundation asset for building type
5. **Generate path endpoint** - Create transition tile for door
6. **Update tilemap** - Paint new path segment
7. **Place assets** - Foundation → Shadow → Building → Props

## NPC Navigation

Path network doubles as navigation hints:

```gdscript
func get_path_to_building(from: Vector2, building_id: String) -> PackedVector2Array:
    var target_node = path_network.building_connections[building_id]
    var nearest_node = path_network.get_nearest_node(from)
    return path_network.find_path(nearest_node, target_node)
```

NPCs prefer walking on paths:
- Higher navigation cost for grass
- Lower cost for dirt paths
- Lowest cost for stone paths/plazas

## Debugging

Enable path debug visualization:

```gdscript
# In game_world.gd
func _ready():
    if OS.is_debug_build():
        $PathNetwork.debug_draw = true
```

This shows:
- Path nodes as circles
- Path segments as lines
- Building connections as arrows
