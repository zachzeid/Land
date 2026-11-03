# World Build Plan: Five Storylines, Seven Souls

> **Document Purpose:** Assignments for the parallel world build. Read with `docs/WORLD_SCHEMA.md`.

## Canon you must not contradict

`docs/STORY_NARRATIVE.md` is canon. Key facts: Thornhaven is extorted by the Iron Hollow bandits.
Gregor secretly supplies them (weapons via Bjorn's forge) in exchange for Elena's safety. Elena's
mother died of an illness five years ago, and the gold Gregor earns was meant to save Elena from the
same illness. **Mira is "The Boss"** of the bandits behind a grieving-widow mask; her "husband"
Marcus was eliminated when he became a liability. Varn is her enforcer and killed Marcus. Bjorn is
honourable and oblivious. Aldric commands the peacekeepers; Elder Mathias leads a timid council.

## The five storylines

Each storyline **must declare and actually set** its two exported flags (other storylines depend on
them), and should reference **at least two** other storylines' exports through `crossovers`.

| file | prefix | premise | centre NPCs | exports (declare + set) |
|------|--------|---------|-------------|-------------------------|
| `iron_hand.json` | `ih_` | Who feeds the bandits? The ledger, the mill meetings, confronting and exposing Gregor, and what Gregor does when cornered: flee, confess, or bargain. | gregor, varn, aldric, elena | `ih_supply_line_cut`, `ih_gregor_fled` |
| `elenas_fever.json` | `fev_` | Elena carries her mother's illness. The fevers are returning. A cure exists (a rare herb past the forest path, a healer who wants payment, or the bandits' stolen medicine) and Elena wants to choose her own life. | elena, gregor, mathias, mira | `fev_cure_found`, `fev_elena_left_home` |
| `hollow_crown.json` | `hc_` | Succession inside Iron Hollow. Varn chafes under a Boss he has never seen unmasked to the village; Mira tests her lieutenant's loyalty. The player can become a pawn, a kingmaker, or a target. | mira, varn, gregor, bjorn | `hc_varn_ascendant`, `hc_varn_dead` |
| `council_of_ash.json` | `cou_` | Thornhaven's politics. Mathias's council wants to keep paying; Aldric wants to fight. Martial law, a secret bargain with the bandits, or a village rising. | mathias, aldric, bjorn, mira | `cou_martial_law`, `cou_council_bargains` |
| `smiths_oath.json` | `oath_` | Bjorn's honour code meets the truth that his blades arm the bandits. Sabotaged steel, an armed resistance, or a smith who walks away from his forge. | bjorn, gregor, aldric, varn | `oath_blades_sabotaged`, `oath_resistance_armed` |

Every storyline should give **every one of the seven NPCs at least one hook somewhere**, not just the
centre NPCs, so that bystanders can act too (Mira sabotaging the council, Elena reacting to the forge,
and so on).

## Targets per storyline

- 5-8 beats spanning Acts I-III, with at least two distinct routes to resolution.
- 2+ hooks per beat on average; at least half the beats carry hooks for NPCs with opposing wants.
- 2-4 endings, each requiring a distinct combination of flags.
- Reference base flags in `scripts/world_state/story_flags.gd` heavily, so that this storyline
  reacts to the others and to the main story.
- `python3 tools/validate_world.py --storyline <id>` exits 0.

## Ownership (agents share one working tree, so stay inside your files)

| owner | files |
|-------|-------|
| souls agent | `souls/**` |
| framework agent | `scripts/storyline/**`, `scripts/debug/test_storyline_director.gd`, `scripts/debug/fixtures/**`, plus integration edits to `project.godot`, `story_flags.gd`, `event_propagator.gd`, `world_state.gd`, `context_builder.gd`, `base_npc.gd`, `debug_console.gd`, `config.gd` |
| storyline agent N | `resources/storylines/<its file>.json` only |
| lead (main session) | `docs/WORLD_SCHEMA.md`, `docs/WORLD_BUILD_PLAN.md`, `tools/validate_world.py`, git |

Nobody commits or runs git write commands; the lead commits.

---

# Phase 2: The Wider World

Read `docs/WORLD_BIBLE.md` and `resources/world/world.json` first. Schema sections 5-7 (registry,
free-form conversation, player flags) are new.

| owner | files |
|-------|-------|
| engine agent | `scripts/storyline/**`, `scripts/world_state/**`, `scripts/dialogue/**`, `scripts/npcs/base_npc.gd`, `scripts/npcs/rag_memory.gd`, `scripts/memory/**`, `scripts/core/config.gd`, `scripts/ui/debug_console.gd`, `scripts/world/world_registry.gd`, `scripts/world/scene_manager.gd`, new `scripts/world/npc_spawner.gd`, `scripts/debug/test_*.gd` (new tests), `chroma_cli.py` |
| cast agent | `souls/**`, new `resources/npc_personalities/<new>.tres`, new `scripts/npcs/<new>.gd`, new `scenes/npcs/<new>.tscn` |
| valley locations agent | `scenes/exterior/{village_gate,old_mill,forest_path}.tscn`, `scenes/interiors/{council_hall,thornhaven_chapel,healer_hut}.tscn`, exits added to `scenes/exterior/{thornhaven_square,iron_hollow}.tscn`, `resources/locations/` for those + `iron_hollow_camp.tres` |
| capitol locations agent | `scenes/capitol/**`, `resources/locations/capitol_*.tres`, `resources/locations/ashdown_manor.tres` |
| march & travel agent | `scenes/exterior/{ferrisford,greystone_mines,fort_ashguard}.tscn`, `scenes/interiors/{kingsroad_waystation,brackenmoor_abbey}.tscn`, their `resources/locations/*.tres`, `scripts/world/travel_map.gd`, new `scenes/ui/travel_map.tscn` + its scripts |
| storyline agents | their two `resources/storylines/<id>.json` files each |
| lead | `resources/world/world.json`, `docs/WORLD_*`, `tools/`, `project.godot`, `export_presets.cfg`, `scripts/world/travel_point.gd`, git |

Shared conventions:
- **Spawn points:** a scene reached from location X has a Marker2D named `from_<X>` under
  `SpawnPoints`, plus `default`.
- **Walking exits:** a `SceneTrigger` (`scripts/world/scene_trigger.gd`) with
  `target_location` = the neighbour id and `target_spawn_point` = `from_<this id>`. One exit per
  `routes` edge within the same region where both ends are built.
- **Long roads:** every location with `"travel_point": true` has a `TravelPoint`
  (`scripts/world/travel_point.gd`) with `from_location` set. It calls `TravelMap.open()`.
- **NPCs:** don't bake new NPCs into scenes. The engine's NPC spawner instances `world.json` NPCs
  into whichever scene matches their current location. Existing scenes keep their baked NPCs; the
  spawner reconciles them.
- **Time:** `WorldState.advance_time(minutes, reason)` (engine) moves the game clock. Travel calls
  it. Walking exits advance time by the route's minutes through SceneManager.

---

# Phase 3: Lives (personal arcs, generics, promotion/demotion)

Spec: `docs/WORLD_SCHEMA.md` §8-9. Config: `world.json` `relationship_decay` and `tiers`.

| owner | files |
|-------|-------|
| arcs engine agent | `scripts/storyline/**` (soul.gd Life parsing, Director personal turns + soul registration API), new `scripts/debug/test_personal_arcs.gd`, `scripts/debug/fixtures/life/**` |
| generics engine agent | new `scripts/generics/**`, `scripts/world_state/**` (world_state, event_propagator, world_events, world_knowledge, dynamic_npc_registry), `scripts/generation/dynamic_npc_generator.gd`, `scripts/dialogue/**`, `scripts/npcs/base_npc.gd`, `scripts/npcs/rag_memory.gd`, `scripts/world/npc_spawner.gd`, new `scenes/npcs/generic_npc.tscn` + script, new `scripts/debug/test_generics.gd`, `scripts/debug/fixtures/generics/**` |
| life writers (2) | the `## Life` section of their souls in `souls/**`, and `souls/WANTS.md` (life index section only) |
| archetypes writer | `resources/generics/**` |
| shared, append-only | `scripts/ui/debug_console.gd`: add commands in your own clearly delimited block; re-read before every edit |
| lead | world.json, docs, tools, project.godot, git |

Contracts between the two engine agents:
- **Arcs agent provides:**
  - `StorylineDirector.register_soul(key, soul_text, opts) -> bool`, with `opts.tier` ∈ `main|promoted|generic` and `opts.npc_id`. Validates through the Soul parser.
  - `unregister_soul(key)` and `set_soul_tier(key, tier)`.
  - Personal turns go only to `main` and `promoted` souls.
  - Personal flags from any registered soul's Life are known flags.
  - Signals `personal_step_completed(key, arc, step)` and `personal_arc_ended(key, arc, outcome)`.
- **Generics agent provides:** rolled souls for every generic instance (`tier: generic`), promotion and demotion by switching tier, and a generated `## Life` section on promotion. `{id}_` prefixes are replaced with the instance id. It calls only the API above and doesn't edit `scripts/storyline/**`.

---

# Phase 4: The Tithe Night rewrite

Canon: `docs/STORY_NARRATIVE.md` (rewritten). The old version is in `docs/archive/`. The base flag
descriptions in `story_flags.gd` are rewritten to the new canon. The new world.json entries are
Davin, the Pit, `calendar` (the fixed points `tn_day_2..7` and `tn_collection_night`) and seven new
discovery flags.

**Preserve identifiers other files depend on.** Keep every export flag name (`ih_*`, `fev_*`, `hc_*`,
`cou_*`, `oath_*`) and every want id that any storyline cites. Grep `resources/storylines/` before
removing or renaming anything. Add new ids freely.

| owner | files |
|-------|-------|
| world & engine agent | calendar runtime, the opening sequence, `scenes/interiors/the_pit.tscn` + `.tres`, StoryItem text in the Thornhaven scenes, `scripts/**` as needed, tests |
| souls A | `souls/{gregor,elena,mira,bjorn}/SOUL.md` + their `resources/npc_personalities/*.tres` |
| souls B | `souls/{aldric,mathias,varn}/SOUL.md` + their `.tres`, plus new Davin (soul, `.tres`, script, scene), `souls/WANTS.md` |
| storyline agents (next) | the 5 Thornhaven storyline files + new `tithe_night.json` |
| wider alignment (last) | text-only alignment of the 10 wider storylines and `WORLD_BIBLE.md` |

## Phase 4 storyline contract

**Flags that must survive** (declared and genuinely settable in the rewritten file, with a meaning
true to the new canon), because other storylines, souls or archetypes read them:

| file | flags |
|------|-------|
| iron_hand | `ih_gregor_fled`, `ih_supply_line_cut`, `ih_trail_opened` |
| elenas_fever | `fev_cure_found`, `fev_door_stayed_barred`, `fev_elena_left_home`, `fev_fever_seen` |
| hollow_crown | `hc_mira_marked_varn`, `hc_varn_ascendant`, `hc_varn_dead` |
| council_of_ash | `cou_barn_burned`, `cou_council_bargains`, `cou_martial_law`, `cou_patrols_sold`, `cou_rising_broken`, `cou_village_rises` |
| smiths_oath | `oath_blades_sabotaged`, `oath_resistance_armed`, `oath_smith_walked_away` |

**The spine, `tithe_night.json` (prefix `tn_`).** It declares and sets these flags, which the other
five files may consume through `crossovers`:
- Knowledge: `tn_lot_rigged_known`, `tn_elena_swap_known`, `tn_taken_alive_known`
- Plans (player flags): `tn_plan_fight`, `tn_plan_bargain`, `tn_plan_substitute`, `tn_plan_follow_cart`
- Exports: `tn_tithe_broken`, `tn_taken_freed`, `tn_substitute_sent`, `tn_elena_taken`

It also owns the eight canon endings. The neglect ending is `tn_the_cart_rolled`: Collection Night
passes without the player, and it is the only spine ending allowed without a player flag. The
calendar flags (`tn_day_2..7`, `tn_collection_night`) are world fixed points that any file may
gate on.
