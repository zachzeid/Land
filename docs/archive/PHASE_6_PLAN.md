# Phase 6 Implementation Plan: Story Testability

> **Status:** Planning Complete
> **Scope:** Debug commands, story flags, bug fixes

---

## Analysis Summary

### What Already Exists

| Component | File | Status |
|-----------|------|--------|
| World flags storage | `world_state.gd` | ✅ Has `world_flags` dict, `set_world_flag()`, `get_world_flag()` |
| Flag integration in NPC context | `context_builder.gd` | ✅ Lines 218-224 include flags |
| Story event signals | `event_bus.gd` | ✅ Has `quest_completed`, `npc_relationship_changed` |
| Debug log display | `debug_console.gd` | ✅ Displays logs, missing command input |
| NPC relationship vars | `base_npc.gd` | ✅ Public vars can be set directly |

### What's Missing/Broken

| Issue | Location | Fix Required |
|-------|----------|--------------|
| Missing `get_flags()` method | `world_state.gd` | Add bulk getter |
| Missing `get_active_quests()` method | `world_state.gd` | Add quest tracking |
| Bug: calls non-existent methods | `base_npc.gd:815-818` | Update method calls |
| No command input in debug console | `debug_console.gd` | Add LineEdit + parser |
| No defined story flags | - | Define flag constants |

---

## Implementation Tasks

### Task 1: Fix WorldState Methods (15 min)
**File:** `scripts/world_state/world_state.gd`

Add missing methods that base_npc expects:

```gdscript
# Add quest tracking
var active_quests := {}

func get_flags() -> Dictionary:
    return world_flags.duplicate()

func get_active_quests() -> Array:
    return active_quests.keys()

func start_quest(quest_id: String, data: Dictionary = {}):
    active_quests[quest_id] = data
    EventBus.quest_started.emit(quest_id)

func complete_quest(quest_id: String, outcome: String = "success"):
    if active_quests.has(quest_id):
        active_quests.erase(quest_id)
        EventBus.quest_completed.emit(quest_id, "", outcome)
```

### Task 2: Add Debug Command System (30 min)
**File:** `scripts/ui/debug_console.gd`

Add command input and parser:

```gdscript
# Commands to implement:
# set_trust <npc_id> <value>     - Set trust (0-100)
# set_affection <npc_id> <value> - Set affection (0-100)
# set_flag <flag_name> <0|1>     - Set world flag
# show_npc <npc_id>              - Display NPC state
# trigger_event <event> <npc>    - Trigger story event
# list_npcs                      - List all NPCs in scene
# list_flags                     - Show all world flags
```

UI changes:
- Add LineEdit at bottom of console
- Connect to command parser
- Show command feedback in log

### Task 3: Define Story Flags (10 min)
**File:** `scripts/world_state/story_flags.gd` (new)

Define constants for story progression:

```gdscript
class_name StoryFlags

# Discovery flags
const GREGOR_CONFESSION_HEARD = "gregor_confession_heard"
const LEDGER_FOUND = "ledger_found"
const WEAPONS_TRACED_TO_BJORN = "weapons_traced_to_bjorn"

# Revelation flags
const ELENA_KNOWS_ABOUT_FATHER = "elena_knows_about_father"
const BJORN_KNOWS_ABOUT_WEAPONS = "bjorn_knows_about_weapons"
const MIRA_BOSS_REVEALED = "mira_boss_revealed"

# Relationship flags
const ELENA_ROMANCE_STARTED = "elena_romance_started"
const ALDRIC_ALLY = "aldric_ally"
const VARN_CONFRONTED = "varn_confronted"
```

### Task 4: Update base_npc.gd Bug Fix (5 min)
**File:** `scripts/npcs/base_npc.gd`

Fix lines 815-818 to use correct method names:

```gdscript
# Before (broken):
if ws.has_method("get_flags"):
    world_state["world_flags"] = ws.get_flags()

# After (fixed):
if ws.has_method("get_flags"):
    world_state["world_flags"] = ws.get_flags()
```
(Method will exist after Task 1)

### Task 5: Add EventBus Quest Signal (5 min)
**File:** `scripts/world_state/event_bus.gd`

Add missing signal:

```gdscript
signal quest_started(quest_id: String)
```

---

## File Changes Summary

| File | Change Type | Lines |
|------|-------------|-------|
| `world_state.gd` | Modify | +25 |
| `debug_console.gd` | Modify | +80 |
| `story_flags.gd` | New | ~40 |
| `event_bus.gd` | Modify | +1 |

---

## Testing After Implementation

1. Open game, press backtick (`) to open debug console
2. Type `list_npcs` - should show all NPCs
3. Type `set_trust gregor_001 75` - should update Gregor's trust
4. Talk to Gregor - should reveal secrets appropriate to trust level
5. Type `set_flag ledger_found 1` - should set world flag
6. Type `list_flags` - should show ledger_found = true

---

## Acceptance Criteria

- [ ] Debug console accepts text input
- [ ] `set_trust`/`set_affection` commands work
- [ ] `set_flag` command updates world flags
- [ ] `show_npc` displays current NPC state
- [ ] NPCs react to manipulated relationship values
- [ ] No console errors when using commands
