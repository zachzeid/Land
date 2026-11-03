# Player systems: build brief for the agents

Read `docs/PLAYER_SYSTEMS.md` (the spec) first, then this. You build one slice. Ten agents build in
parallel, each in its own git worktree; the lead merges them in order. Rules that keep that safe:

## Hard rules
1. **Work only in your worktree** (the path in your prompt). Never edit, run tests in, or run git in
   `/Users/zzeid/github/Land` itself: tests there write to its real `./chroma`. Your worktree has no
   `.env`: do not create one. Never make network calls to Anthropic, ElevenLabs or PixelLab.
2. **Edit only the files you own** (table below), plus new files under the paths you own. If you
   need a change in someone else's file, do not make it: write it down in your final report as a
   "request to <owner>" with the exact change.
3. **Deeds go through `PlayerEvents.record(kind, summary, about, opts)`.** Never write NPC memories,
   relationships or reputation directly. Physical deeds pass
   `opts.witnesses = Witnesses.in_sight(scene_root, position, {stealth})`
   (`res://scripts/world/witnesses.gd`). Kinds available: the old ones plus `feat`, `crafted`, `fled`,
   `fire`, `trespass`, `solved`, `fell`.
4. **NPC choices go through the soul**: `StorylineDirector.decide_situation(npc_key, hook, title)`
   returns a decision (choice, option, effects) under the soul's Agency and Lines; apply effects with
   `apply_situation_effects(npc_key, decision)`. Options can carry `harms: [key]`, `aids: key` and
   `crowd: true`, and Lines refuse them.
5. **Children**: the player can harm them, at the heaviest reputation cost; NPCs, creatures and
   crowds never target them (`WorldRegistry.is_minor(key)`).
6. **Canon**: late-medieval, low magic, no spells; no forbidden concepts (world.json
   `forbidden_concepts`) in any name or text. Coin is copper, silver, gold, crowns (100 each).
7. **Content is JSON** under `resources/`. Validate it in your own `tools/validators/<system>.py`
   (see `tools/validators/README.md`); `python3 tools/validate_world.py` must report 0 errors.
8. **Save**: your autoload's `save()` / `load_from_dict()` (WorldState already calls them).
9. **Tests**: a headless suite `scripts/debug/test_<system>.gd` in the style of `test_calendar.gd`
   (`extends SceneTree`, two `await process_frame`, `_check`, a final "✅ ALL TESTS PASSED" /
   "❌ N CHECK(S) FAILED" line, `quit(0|1)`). Fakes, not network. Before handing back, run every
   `scripts/debug/test_*.gd` in your worktree (`perl -e 'alarm 200; exec @ARGV' godot --headless
   --path <worktree> -s res://scripts/debug/test_<x>.gd`) and `idle_world_sim.gd`; all must pass
   (`test_api_call` skips by design). A fresh worktree needs `godot --headless --path <worktree>
   --import` first.
10. **Style**: GDScript with tabs, `##` doc comments, terse comments that say why. Match the files
    around you.
11. **Commit** in your worktree on your branch with conventional-commit messages ending
    `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. If signing fails, leave the work
    uncommitted and say so; never bypass signing. Kill processes by PID, never `pkill -f`.

## Ownership
| # | Slice | Owns (edit) | New files under |
|---|---|---|---|
| 1 | Skills and level | `scripts/player/player_stats.gd` | `resources/player/`, `scripts/player/teaching.gd`, `tools/validators/skills.py` |
| 2 | Inventory | `scripts/player/inventory.gd` | `resources/items/`, `scripts/world/dropped_pack.gd`, `scenes/world/dropped_pack.tscn`, `resources/emergence/a_pack_by_the_road.json`, `tools/validators/items.py` |
| 3 | Combat core | `scripts/combat/combat.gd`, `scripts/player/player.gd`, `scenes/player/player.tscn` | `resources/combat/weapons.json`, `resources/combat/armour.json`, `scripts/combat/hitbox*.gd`, `tools/validators/combat.py` |
| 4 | Combat world | `scripts/npcs/base_npc.gd`, `scripts/generics/generic_npc.gd`, `scripts/generics/generic_manager.gd` | `scripts/combat/combat_ai.gd`, `scripts/combat/creature.gd`, `scenes/creatures/`, `resources/combat/creatures.json`, `tools/validators/creatures.py` |
| 5 | Crafting and gathering | `scripts/crafting/crafting.gd` | `resources/crafting/{recipes,stations,nodes}.json`, `scripts/crafting/station.gd`, `scripts/crafting/resource_node.gd`, `tools/validators/crafting.py` |
| 6 | Herbcraft and cooking | (none existing) | `scripts/crafting/herbcraft.gd`, `resources/crafting/ingredients.json`, `tools/validators/herbcraft.py` |
| 7 | World physics | `scripts/world/physics/world_physics.gd` | `scripts/world/physics/*.gd` (components), `scenes/world/physics/` |
| 8 | Puzzles | `scripts/puzzles/puzzles.gd`, `resources/world/world.json` (`discovery_flags` only) | `resources/puzzles/`, `scenes/puzzles/`, `scripts/puzzles/*.gd`, `tools/validators/puzzles.py` |
| 9 | Emergent beats | (none existing) | the `resources/emergence/*.json` templates named in spec §7 (not `a_pack_by_the_road`), `scripts/debug/test_player_emergence.gd` |
| 10 | UI and input | `scripts/ui/player_ui.gd` | `scripts/ui/hud.gd`, `scripts/ui/inventory_panel.gd`, `scripts/ui/crafting_panel.gd`, `scripts/ui/skills_page.gd`, `scripts/ui/puzzle_card.gd`, `scripts/ui/difficulty_choice.gd`, `scenes/ui/` (new scenes only) |

Every agent also owns its own `scripts/debug/test_<system>.gd`.

## Contracts (the calls across slices; keep these signatures exactly)
- `PlayerStats`: `use_skill(skill, difficulty_factor, context) -> {gained, level, milestone}`,
  `get_skill(skill) -> float`, `get_level() -> int`, `spend_stamina(amount) -> bool`,
  `damage(amount, damage_type, source) -> {health, staggered, dead}`, `difficulty` ("normal"|"hard"),
  signals `skill_raised(skill, level, milestone)`, `died(info)`. Also: `get_health()`, `get_max_health()`,
  `get_stamina()`, `get_max_stamina()`, `heal(amount)`, `has_perk(id)`.
- `Inventory`: `add(item_id, qty, props) -> bool`, `remove(item_id, qty) -> bool`, `has(item_id, qty) -> bool`,
  `equip(item_id, slot) -> bool`, `get_equipped(slot) -> Dictionary`, signal `changed`. Also:
  `get_items() -> Array`, `get_coin() -> int` (copper), `add_coin(copper)`, `wear(slot, amount)`
  (durability; returns `{broke}`), `drop_all_at(scene_root, position) -> Node` (the pack).
  Item record: `{id, qty, quality (0-100), durability, max_durability, maker, provenance: {from, stolen, owner}}`.
  Item definitions live in `resources/items/*.json`: `{id, name, kind (weapon|armour|tool|material|food|remedy|misc), weight, stack, value (copper), tags, ...}`.
- `Combat`: `attack(attacker, target, action) -> Dictionary`, `can_target(key) -> bool`,
  signals `hit_landed(info)`, `fight_ended(info)`. Also `resolve_hit(attacker, target, weapon, action) -> {damage, type, staggered, killed}`.
  Combat world (4) adds `CombatAI.decide(npc_key, situation) -> String` (fight|yield|flee|call_for_help|talk).
- `Crafting`: `can_craft(recipe_id, station_id) -> {ok, reason}`, `craft(recipe_id, station_id) -> {ok, item, reason}`,
  `cook(ingredients: Array, station_id) -> {ok, item, reason}` (delegates to `Herbcraft.cook`), signal `crafted(item)`.
- `Herbcraft` (`res://scripts/crafting/herbcraft.gd`, `extends RefCounted`, static):
  `cook(ingredient_ids: Array, skill: float) -> {item_id, effects, potency, dubious}`, `ingredient(id) -> Dictionary`.
- `WorldPhysics`: `ignite(node, by) -> bool`, `douse(node) -> bool`, `get_wind() -> Vector2`,
  signals `fire_started(node, by)`, `burned(node, owner_key)`. Components are nodes with
  `script = res://scripts/world/physics/<name>.gd`: `flammable.gd` (export `owner_key`, `burn_seconds`),
  `pressure_plate.gd` (export `weight_needed`, signal `pressed(on)`), `rope.gd` (signal `cut`),
  `lamp.gd`, `basin.gd`, `metal.gd`. Puzzle rooms (8) use exactly these names.
- `Puzzles`: `answer(puzzle_id, answer) -> {ok, flag, reason}`, `get_puzzle(id)`, signal `solved(puzzle_id)`.
- `Witnesses.in_sight(scene_root, at, opts) -> Array` of npc ids (exists).
- `StorylineDirector.decide_situation(npc_key, hook, title)` and `apply_situation_effects(npc_key, decision, source)` (exist).

## Your final report (under 400 words)
What you built, test results (every suite), the commit hashes, any requests to other owners, and
anything you could not finish or decide.
