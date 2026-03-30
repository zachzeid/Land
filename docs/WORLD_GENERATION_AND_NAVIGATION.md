# World Generation, Asset Placement, and NPC Navigation

> **Date:** 2026-03-29
> **Status:** Design Document
> **Depends on:** AUTONOMOUS_NPC_AGENTS.md, NPC_EXISTENCE_AND_INFLUENCE_SYSTEM.md

---

## The Problem

Three interconnected problems block autonomous NPCs:

1. **World construction is manual** — Every building, tree, and barrel in `game_world.tscn` is hand-placed (978 lines of scene file). No validation, no overlap detection.
2. **No navigation mesh** — NPCs literally cannot move. There's zero movement code in `base_npc.gd`, even though pathfinding infrastructure (WaypointGraph with A*, NavigationRegion generation) exists but is never connected.
3. **Terrain doesn't render** — TileMapLayer is configured but empty. TerrainPainter code exists but tiles don't appear.

The irony: powerful systems for all three problems exist in the codebase — `GridLayout`, `WaypointGraph`, `TerrainPainter`, navigation polygon generation — but none of them are wired into the actual game world.

---

## Current State: What Exists vs What's Connected

| System | Code Exists | Connected to game_world | Working |
|--------|------------|------------------------|---------|
| GridLayout (placement + validation) | Yes (457 lines) | **No** | Untested |
| WaypointGraph (A* pathfinding) | Yes (457 lines) | **No** | Code works, unused |
| TerrainPainter (tilemap painting) | Yes (143 lines) | Yes (node in scene) | **Broken** (tiles not rendering) |
| NavigationRegion generation | Yes (in GridLayout) | **No** | Untested |
| Collision layers (8 defined) | Yes | Yes | Working |
| WorldSolid/WorldObstacle classes | Yes | Yes | Working |
| Asset generation pipeline | Yes (15 files) | Partial | Recraft works, tilesets incomplete |
| NPC movement code | **No** | N/A | N/A |

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    WORLD CONSTRUCTION PIPELINE               │
│                                                              │
│  ZoneSpec (data)                                             │
│    ├── Required buildings + positions                        │
│    ├── Terrain type + paths                                  │
│    ├── Prop placement rules                                  │
│    └── NPC spawn locations                                   │
│              │                                               │
│              ▼                                               │
│  ConstraintValidator                                         │
│    ├── Grid occupancy check (no overlap)                     │
│    ├── Road adjacency validation                             │
│    ├── Spacing rules (min distance between objects)          │
│    └── Footprint bounds checking                             │
│              │                                               │
│              ▼                                               │
│  Scene Construction                                          │
│    ├── TileMapLayer (terrain painted by TerrainPainter)      │
│    │     └── Navigation polygons per tile (walkable areas)   │
│    ├── Buildings (Sprite2D + StaticBody2D + WorldSolid)      │
│    │     └── Collision from footprint rectangle              │
│    ├── Props (Sprite2D + optional StaticBody2D)              │
│    │     └── Collision from alpha channel or rectangle       │
│    ├── NavigationRegion2D (baked from tilemap + obstacles)   │
│    │     └── Walkable mesh with holes for buildings          │
│    └── Semantic Waypoints (doors, POIs, spawn points)        │
│              │                                               │
│              ▼                                               │
│  NPC Navigation                                              │
│    ├── NavigationAgent2D per NPC (Godot native pathfinding)  │
│    ├── ORCA avoidance (NPCs don't collide with each other)   │
│    ├── Destination selection from waypoints (AI decision)     │
│    ├── Steering behaviors (arrive, wander, flee)             │
│    └── Cross-scene movement via door waypoints               │
└─────────────────────────────────────────────────────────────┘
```

---

## 1. Terrain and Ground Layer

### Current Problem
TileMapLayer node exists in game_world.tscn with TerrainPainter configured to auto-paint, but no tiles render. Likely a tileset metadata mismatch or tile coordinate issue.

### Target Design

**TileMapLayer is the foundation of everything.** It defines:
- What the ground looks like (grass, dirt, cobblestone)
- Where NPCs can walk (via navigation polygons on walkable tiles)
- The base for the navigation mesh

**Tile types:**

| Tile | Walkable | Navigation Polygon | Visual |
|------|----------|-------------------|--------|
| Grass | Yes | Full tile | Green terrain |
| Dirt path | Yes | Full tile | Brown path |
| Cobblestone | Yes | Full tile | Gray stone |
| Water | No | None | Blue (blocks movement) |
| Void/edge | No | None | Nothing (world boundary) |

**How it works with NavigationRegion2D:**
1. Each walkable tile in the TileSet has a navigation polygon covering the full tile
2. NavigationRegion2D is configured to bake from the TileMapLayer's navigation data
3. Building/obstacle StaticBody2D nodes automatically carve holes in the navigation mesh
4. Result: a walkable mesh that routes around all static obstacles

### Integration with TerrainPainter

TerrainPainter already paints terrain from layout data. The fix is:
1. Ensure the TileSet resource (`terrain_tileset.tres`) has valid tile definitions with navigation polygons
2. Verify terrain IDs (0=grass, 1=dirt, 2=cobblestone) match the TileSet's source IDs
3. Verify the coordinate conversion (`grid_to_tile()`) produces valid tile positions

---

## 2. Asset Placement with Collision Avoidance

### Grid Occupancy System

Since the world is a 32x32 grid with 32px cells, maintain a simple occupancy map:

```
OccupancyGrid:
  cells: Array[Array[bool]]  # 32x32, true = occupied

  func can_place(grid_pos: Vector2i, footprint: Vector2i) -> bool:
      for x in range(footprint.x):
          for y in range(footprint.y):
              if cells[grid_pos.x + x][grid_pos.y + y]:
                  return false  # Overlap!
      return true

  func place(grid_pos: Vector2i, footprint: Vector2i):
      for x in range(footprint.x):
          for y in range(footprint.y):
              cells[grid_pos.x + x][grid_pos.y + y] = true
```

**Placement order matters:** Buildings first (largest footprints), then trees, then props. This ensures large objects get placed before small ones fill gaps.

### Collision Shape Generation

**For buildings (rectangular):** Keep the current approach. `WorldSolid` with `RectangleShape2D` at footprint * 0.9 is clean and performant.

**For organic shapes (trees, rocks, irregular props):** Auto-generate from the sprite's alpha channel:

```
Approach: Bitmap.create_from_image_alpha() → opaque_to_polygons()

1. Load the AI-generated PNG
2. Create BitMap from alpha channel (threshold 0.1)
3. Convert to polygons with simplification (epsilon 1.0-2.0)
4. Use as CollisionPolygon2D vertices
```

This means when a new AI asset is generated, its collision shape is derived automatically — no manual setup needed.

**For trees specifically:** Keep the current design where the collision is trunk-only (32x32) while the visual canopy is much larger (128x128). Players and NPCs walk "under" the canopy. This is a deliberate design choice, not a bug.

### Placement Validation Rules

Extend `GridLayout.validate_placement()` beyond bounds checking:

| Rule | Check | Current Status |
|------|-------|---------------|
| Bounds | Position within safe margin | Exists |
| Overlap | Footprint doesn't cover occupied cells | **Missing** |
| Road adjacency | Buildings within 2 cells of a path | **Missing** |
| Minimum spacing | Props at least 1 cell apart | **Missing** |
| Door clearance | 2 cells free in front of each door | **Missing** |
| Path connectivity | All buildings reachable via paths | **Missing** |

---

## 3. NPC Navigation Architecture

### Replace WaypointGraph Pathfinding with NavigationServer2D

The custom WaypointGraph A* should be replaced with Godot's native system:

| Aspect | WaypointGraph (current) | NavigationServer2D (target) |
|--------|------------------------|---------------------------|
| Pathfinding | Custom A* over waypoints | Built-in, threaded, optimized |
| Obstacle avoidance | None | ORCA algorithm (native) |
| Dynamic obstacles | Not supported | NavigationObstacle2D |
| Movement quality | Grid-locked (waypoint to waypoint) | Free-form smooth paths |
| Setup | Manual waypoint placement | Auto-baked from tilemap + obstacles |
| Multi-NPC support | Each NPC runs own A* | Server handles all agents efficiently |

**Keep WaypointGraph for semantics only:** The DOOR, POI, SPAWN, PATROL waypoint types are valuable for NPC AI decision-making. The NPC agent loop says "go to tavern_door" and NavigationAgent2D finds the actual path.

### NPC Movement Implementation

Add to `base_npc.gd`:

```
New child node: NavigationAgent2D
  - radius: 16 (half NPC sprite width)
  - neighbor_distance: 200
  - max_neighbors: 10
  - max_speed: 100 pixels/sec
  - avoidance_enabled: true

Movement flow:
1. Agent loop selects destination (waypoint position)
2. Set NavigationAgent2D.target_position = destination
3. Each _physics_process:
   a. Get next_path_position from NavigationAgent2D
   b. Calculate direction and velocity
   c. Apply steering behaviors (arrive, wander)
   d. Call move_and_slide()
   e. Update animation based on velocity direction
```

### Steering Behaviors

Raw pathfinding produces robotic movement. Add naturalism:

| Behavior | When Used | Effect |
|----------|-----------|--------|
| **Path follow** | Moving to destination | Smooth along navigation path with lookahead |
| **Arrive** | Near destination | Decelerate smoothly instead of stopping abruptly |
| **Wander** | Idle at location | Small random heading changes, "looking around" |
| **Separation** | Near other NPCs | Soft personal space (on top of ORCA hard avoidance) |
| **Flee** | Threat detected | Move away from danger source |

### Cross-Scene Navigation

When an NPC needs to move between scenes (exterior → tavern interior):

1. NPC AI decides: "I need to go to the tavern"
2. Agent loop finds nearest DOOR waypoint for tavern
3. NavigationAgent2D pathfinds to the door position
4. NPC reaches door → triggers transition logic:
   - If player is in the same scene: NPC fades out, appears in target scene
   - If player is NOT present: Skip animation, update logical position instantly
5. In target scene: NPC spawns at the corresponding spawn point
6. NavigationAgent2D pathfinds to final destination within interior

**Off-screen NPCs skip physics entirely.** Track their logical position ("at tavern, sitting at bar") and teleport them to the correct physical position when the player enters their scene.

### Performance Budget: 50 NPCs Navigating

| Component | Cost per NPC/frame | 50 NPCs Total | Budget Impact |
|-----------|-------------------|----------------|---------------|
| NavigationAgent2D query | ~0.01ms | ~0.5ms | Negligible |
| ORCA avoidance | ~0.005ms | ~0.25ms | Negligible |
| move_and_slide() | ~0.02ms | ~1.0ms | Small |
| Sprite rendering | ~0.001ms | ~0.05ms | Negligible |
| Agent loop (GDScript) | ~0.05ms | ~2.5ms | Moderate |
| **Total** | | **~4.3ms** | **26% of 16ms frame budget** |

Plenty of headroom. AI inference calls (Bedrock) are async HTTP and don't touch the frame budget.

---

## 4. Z-Ordering and Depth Sorting

### Current Scheme (Keep)

| Z-Index | Layer | Contents |
|---------|-------|----------|
| -20 | Terrain | TileMapLayer (grass, dirt, stone) |
| -10 | Foundations | Building foundation sprites |
| -5 | Shadows | Ground shadow sprites |
| 0 | Props | Barrels, crates, benches |
| 10 | Buildings | Building sprites |
| 20 | Characters | Player, NPCs |
| 30 | Canopy | Tree tops (walk under) |
| 100+ | UI | Dialogue, menus |

### Enable Y-Sort for Depth Illusion

Set `y_sort_enabled = true` on container nodes for the Characters and Buildings layers. This makes objects with higher Y positions render on top, creating proper top-down depth (player walks behind buildings, in front of foundations).

---

## 5. AI-Generated Asset Integration

### From PNG to Game-Ready Object Pipeline

```
1. GENERATE → PixelLab/Recraft via Bedrock sidecar
                ↓
2. POST-PROCESS → Trim transparent borders
                → Quantize to shared 32-color palette (style consistency)
                → Verify pixel density matches PIXELLAB_SCALE
                ↓
3. COLLISION → Buildings: rectangular from footprint
            → Organic: Bitmap.create_from_image_alpha() → opaque_to_polygons()
            → Trees: trunk-only rectangle (32x32)
                ↓
4. SCENE NODE → Sprite2D + StaticBody2D + CollisionShape/Polygon
             → Z-index set by asset type
             → Navigation obstacle registered
                ↓
5. CACHE → Store in res://assets/generated/[type]/[id].png
         → Cache collision data alongside texture
         → asset_cache.json updated
```

### Style Consistency Across AI Assets

| Technique | Impact | Implementation |
|-----------|--------|---------------|
| **Shared color palette** | Highest | Post-process all PNGs to 32-color palette |
| **Consistent prompts** | High | WorldSettings already handles this |
| **Same pixel density** | High | PIXELLAB_SCALE=2 enforced |
| **Outline normalization** | Medium | "single color outline" in PixelLab params |
| **Shadow direction** | Medium | All assets: shadow bottom-right |
| **Reference image anchoring** | Medium | Pass same style reference to PixelLab |

---

## 6. World Construction: Manual → Data-Driven → Procedural

### Phase 1: Data-Driven (Connect What Exists)

The `THORNHAVEN_LAYOUT` dictionary in GridLayout.gd IS the data-driven layout — it's just not connected. Wire it up:

1. `GridLayout.apply_layout_to_scene(game_world, THORNHAVEN_LAYOUT)` at scene load
2. This creates: collision bodies, entry points, navigation polygon, waypoint graph
3. TerrainPainter reads the same layout to paint terrain
4. Replace the 978-line manual scene with a ~50-line data-driven one

**The scene file becomes:**
```
GameWorld (Node2D)
├── TileMapLayer (auto-painted)
├── NavigationRegion2D (auto-baked)
├── Buildings (auto-placed from layout)
├── Props (auto-placed from layout)
├── NPCs (spawned at layout positions)
├── Player (spawned at default spawn point)
└── UI (CanvasLayer)
```

### Phase 2: Constraint-Validated Layouts

Add validation to ensure layouts are valid before applying:

```
ZoneSpec → ConstraintValidator → ValidatedLayout → apply_layout_to_scene()
```

Constraints: no overlap, road adjacency, door clearance, path connectivity.

This enables: authors define WHAT should be in a zone, the validator ensures WHERE is valid.

### Phase 3: Procedural Generation (Future)

When the game needs new zones beyond hand-authored ones:

1. **Constraint solver** takes a ZoneSpec (required buildings, terrain, size) and produces a valid layout
2. **WFC** fills background detail (ambient houses, tree lines, fences) around constraint-placed structures
3. **Asset generation** creates textures for new buildings/props via Bedrock + PixelLab
4. **Navigation** auto-bakes from the generated layout

---

## 7. NPC Autonomous Movement Integration

### How It All Connects

```
NPC Agent Loop (from AUTONOMOUS_NPC_AGENTS.md)
  │
  ├── PERCEIVE: Query WorldKnowledge for locations, WaypointGraph for nearby POIs
  │
  ├── EVALUATE: Score goals (e.g., "go open shop" priority: 80)
  │
  ├── SELECT: Choose action → move_to("gregor_shop_door")
  │
  ├── EXECUTE:
  │   ├── Look up waypoint position for "gregor_shop_door"
  │   ├── Set NavigationAgent2D.target_position = door_position
  │   ├── _physics_process runs movement:
  │   │   ├── Get next_path_position from NavigationAgent2D
  │   │   ├── Apply steering (arrive behavior near destination)
  │   │   ├── ORCA avoidance adjusts velocity (other NPCs)
  │   │   ├── move_and_slide()
  │   │   └── Update walk animation direction
  │   ├── Reach door → scene transition logic
  │   └── Appear inside shop at spawn point
  │
  └── REFLECT: Store "arrived at shop" in RAG memory
```

### Movement States

```
IDLE ──── NPC at destination, wander behavior active
  │
  ├── Goal selected → MOVING
  │                     │
  │                     ├── Reached destination → IDLE
  │                     ├── Blocked (timeout) → REROUTING
  │                     └── Interrupted (event) → REACTING
  │
  ├── Player approaches → CONVERSING (movement paused)
  │
  └── Threat detected → FLEEING (flee steering behavior)
```

---

## 8. Implementation Priority

### Immediate (Week 1): Fix What's Broken

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 1 | Debug tilemap rendering (TerrainPainter + TileSet) | 2-3 hrs | Ground becomes visible |
| 2 | Add NavigationRegion2D to game_world.tscn | 1-2 hrs | Walkable mesh exists |
| 3 | Add NavigationAgent2D to base NPC scene | 1 hr | NPCs CAN move (infrastructure) |
| 4 | Add basic movement code to base_npc.gd | 3-4 hrs | NPCs DO move |

### Short-term (Week 2-3): Connect Systems

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 5 | Wire GridLayout.apply_layout_to_scene() to game_world | 1 day | Data-driven world |
| 6 | Add grid occupancy validation | 0.5 day | No asset overlap |
| 7 | Add alpha-channel collision generation for organic shapes | 0.5 day | Auto collision |
| 8 | Add y_sort_enabled for depth sorting | 1 hr | Visual depth |
| 9 | Add steering behaviors (arrive, wander) | 1 day | Natural NPC movement |
| 10 | Add ORCA avoidance configuration | 2 hrs | NPCs don't overlap |

### Medium-term (Week 4-5): Full Autonomous Movement

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 11 | Semantic waypoints (keep from WaypointGraph) | 0.5 day | NPC destination selection |
| 12 | Cross-scene NPC movement (door transitions) | 1-2 days | NPCs enter/exit buildings |
| 13 | NPC animation state machine (idle, walk, talk) | 1-2 days | Visual movement feedback |
| 14 | Off-screen NPC position tracking | 0.5 day | Logical vs physical position |
| 15 | Movement integration with agent loop | 1 day | AI-driven navigation |

### Long-term (Week 6+): Generation & Procedural

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 16 | Constraint validator for layouts | 2 days | Valid generated layouts |
| 17 | New zone generation from ZoneSpec | 3-5 days | Expandable world |
| 18 | Auto-generate + place assets for new zones | 2-3 days | AI-built environments |
| 19 | WFC for background detail filling | 3-5 days | Rich procedural detail |

---

## Design Decisions Needing Your Input

1. **Grid-locked vs free-form NPC movement?** NavigationServer2D supports smooth free-form paths (recommended for natural-feeling agents). AStarGrid2D gives grid-locked movement (simpler but robotic). Which fits the game's feel?

2. **Data-driven scene replacement?** Should game_world.tscn be rebuilt from the THORNHAVEN_LAYOUT dictionary (clean, maintainable) or keep the manual 978-line scene file (known-working, more control)?

3. **Collision fidelity for AI assets?** Rectangular approximation (fast, simple) vs alpha-channel polygons (accurate, more complex)? Could use rectangles for buildings and alpha for organic shapes as a hybrid.

4. **Terrain visual style?** The tilemap system uses Godot's autotiling. Should terrain tiles be AI-generated (PixelLab) or hand-drawn? Current tileset assets exist but may not render correctly.
