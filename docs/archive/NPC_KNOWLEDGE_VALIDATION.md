# NPC Knowledge Validation & Anti-Hallucination System

This document describes the systems that ensure NPCs maintain consistent, accurate knowledge about the game world and prevent AI hallucinations (inventing non-existent places, names, or facts).

## Overview

The system uses **three layers of protection**:

1. **Prompt Injection** - WorldKnowledge injects canonical facts into every NPC's context
2. **Response Sanitization** - Fixes hallucinated names before displaying to player
3. **Memory Validation** - Prevents invalid memories from being persisted

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          NPC CONVERSATION FLOW                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Player Input                                                               │
│       ↓                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ LAYER 1: PROMPT INJECTION                                           │   │
│  │ WorldKnowledge.get_world_facts_for_npc() injects:                   │   │
│  │   - Canonical establishment names                                    │   │
│  │   - NPC roster                                                       │   │
│  │   - Geographic knowledge boundaries                                  │   │
│  │   - Explicit warnings against hallucination                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       ↓                                                                     │
│  Claude API generates response                                              │
│       ↓                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ LAYER 2: RESPONSE SANITIZATION                                      │   │
│  │ _sanitize_response_hallucinations() fixes:                          │   │
│  │   - "Weary Wanderer" → "The Rusty Nail"                             │   │
│  │   - "Golden Goose" → "The Rusty Nail"                               │   │
│  │   - "Village smithy" → "Bjorn's Forge"                              │   │
│  │   - (30+ common hallucination patterns)                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       ↓                                                                     │
│  Response displayed to player (sanitized)                                   │
│       ↓                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ LAYER 3: MEMORY VALIDATION                                          │   │
│  │ WorldEvents.validate_memory() blocks:                               │   │
│  │   - Forbidden establishment names                                    │   │
│  │   - Unknown quoted names                                             │   │
│  │   - Location inconsistencies                                         │   │
│  │   - Returns {valid: bool, issues: [], sanitized: String}            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       ↓                                                                     │
│  Memory stored (only if valid) OR rejected                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `scripts/world_state/world_knowledge.gd` | Canonical world facts, geographic scoping |
| `scripts/world_state/world_events.gd` | Memory validation, shared player facts, event log |
| `scripts/npcs/base_npc.gd` | Response sanitization, debug methods |
| `scripts/npcs/rag_memory.gd` | Memory storage with validation integration |
| `scripts/dialogue/context_builder.gd` | Injects world facts into Claude prompts |
| `scripts/debug/interaction_debug_overlay.gd` | F3/F4/F5 debug hotkeys for memory inspection |
| `scripts/debug/memory_dump_cli.gd` | CLI tool for headless memory dumps |

## Geographic Knowledge Scoping

NPCs have **tiered knowledge** based on their home location:

```gdscript
enum KnowledgeScope {
    INTIMATE,   # Own home/workplace - knows every detail
    LOCAL,      # Same village - establishments, neighbors, gossip
    REGIONAL,   # Same region - vague rumors only
    DISTANT,    # Different region - "I've only heard stories..."
    UNKNOWN     # Never heard of it - "I don't know that place"
}
```

### Location Hierarchy

Defined in `WorldKnowledge.location_hierarchy`:

```gdscript
var location_hierarchy = {
    "thornhaven": {
        "parent": null,
        "contains": ["market_square", "thornhaven_gregor_shop", ...],
        "region": "northern_trade_region"
    },
    "kings_castle": {
        "parent": null,
        "contains": ["throne_room", "royal_quarters", "dungeon"],
        "region": "capital_region"
    }
}
```

### NPC Location Assignment

```gdscript
var npc_locations = {
    "gregor_merchant_001": "thornhaven_gregor_shop",
    "elena_daughter_001": "thornhaven_gregor_shop",
    "mira_tavern_keeper_001": "thornhaven_tavern",
    "bjorn_blacksmith_001": "thornhaven_blacksmith"
}
```

### Example: Elena's Knowledge

- **INTIMATE**: Gregor's shop (her home)
- **LOCAL**: The Rusty Nail, Bjorn's Forge, Market Square
- **DISTANT**: King's Castle (would say "I've never been there")
- **UNKNOWN**: Random made-up places

## World Facts Structure

All canonical world facts are stored in `WorldKnowledge.world_facts`:

```gdscript
var world_facts = {
    "locations": {
        "thornhaven": {
            "name": "Thornhaven",
            "type": "village",
            "population": 150,
            "description": "A small trading village on the northern trade route"
        }
    },
    "establishments": {
        "tavern": {
            "name": "The Rusty Nail",   # ← CANONICAL NAME
            "type": "tavern",
            "owner": "mira_tavern_keeper_001",
            "goods": ["ale", "mead", "hot meals", "rooms for rent"]
        },
        "blacksmith": {
            "name": "Bjorn's Forge",
            "type": "blacksmith",
            "owner": "bjorn_blacksmith_001"
        },
        "gregor_shop": {
            "name": "Gregor's General Goods",
            "type": "shop",
            "owner": "gregor_merchant_001"
        }
    },
    "npcs": {
        "elena_daughter_001": {
            "name": "Elena",
            "full_name": "Elena Stoneheart",
            "age": 24,
            "occupation": "shop assistant",
            "family": ["gregor_merchant_001"]
        }
        // ... more NPCs
    }
}
```

## Prompt Injection (Layer 1)

When building context for Claude, `context_builder.gd` injects world facts:

```gdscript
# In context_builder.gd
if WorldKnowledge and not personality.npc_id.is_empty():
    prompt += WorldKnowledge.get_world_facts_for_npc(personality.npc_id)
```

This produces a prompt section like:

```markdown
## ⚠️ STRICT WORLD KNOWLEDGE RULES ⚠️

1. **ONLY use names/places listed below** - If not listed, you DON'T KNOW IT
2. **NEVER invent establishment names** - No 'Weary Wanderer', 'Golden Goose', etc.
3. **When uncertain, say so** - 'I've heard rumors...' or 'I don't know'
4. **Your knowledge is LIMITED** - Distant places are only rumors.

---

## YOUR VILLAGE: THORNHAVEN (You know this well)

### ESTABLISHMENTS IN THORNHAVEN (Use ONLY these names!)

⚠️ These are the ONLY establishments in Thornhaven. There are NO others.

- **"Gregor's General Goods"** - the shop
- **"The Rusty Nail"** - the tavern (run by Mira)
- **"Bjorn's Forge"** - the blacksmith (run by Bjorn)

⚠️ Do NOT mention any tavern/shop/smithy other than those listed above!

## WHAT YOU DON'T KNOW (Be honest about this!)

- You have NEVER been to the King's castle or the capital
- Distant places are only RUMORS to you
- If asked about unknown places, say: "I've never been there"

---

⚠️ **FINAL WARNING:** If you mention ANY establishment not listed above,
you are HALLUCINATING.
```

## Response Sanitization (Layer 2)

Even with strong prompts, Claude may hallucinate. `_sanitize_response_hallucinations()` fixes common patterns:

```gdscript
# In base_npc.gd
var hallucination_replacements = {
    # Tavern hallucinations → The Rusty Nail
    "weary wanderer": "The Rusty Nail",
    "the weary wanderer": "The Rusty Nail",
    "golden goose": "The Rusty Nail",
    "dancing dragon": "The Rusty Nail",
    "prancing pony": "The Rusty Nail",
    "village tavern": "The Rusty Nail",
    "local tavern": "The Rusty Nail",
    "local inn": "The Rusty Nail",

    # Blacksmith hallucinations → Bjorn's Forge
    "village smithy": "Bjorn's Forge",
    "local blacksmith": "Bjorn's Forge",

    # Shop hallucinations → Gregor's General Goods
    "general store": "Gregor's General Goods",
    "village shop": "Gregor's General Goods",
}
```

Applied automatically after Claude responds:

```gdscript
# In respond_to_player()
var npc_response = parsed_response.response

# SANITIZE: Fix hallucinations BEFORE display
npc_response = _sanitize_response_hallucinations(npc_response)

dialogue_response_ready.emit(npc_id, npc_response)
```

## Memory Validation (Layer 3)

Before storing any memory, `WorldEvents.validate_memory()` checks for issues:

```gdscript
# In rag_memory.gd store()
if not skip_validation and WorldEvents:
    var validation = WorldEvents.validate_memory(memory_data.text, npc_id)
    if not validation.valid:
        push_warning("[RAGMemory] Memory REJECTED: %s" % validation.issues)
        return false  # Memory NOT stored

    if validation.sanitized != memory_data.text:
        memory_data.text = validation.sanitized  # Auto-correct typos
```

### Validation Checks

1. **Forbidden Names**: Blocks known hallucination patterns
   ```gdscript
   var forbidden_establishment_names = [
       "weary wanderer", "golden goose", "silver spoon",
       "dancing dragon", "prancing pony", "old inn",
       "village tavern", "local tavern"
   ]
   ```

2. **Unknown Establishments**: Extracts quoted names and validates
   ```gdscript
   var mentioned = _extract_quoted_names(text)
   for name in mentioned:
       if not WorldKnowledge.is_valid_establishment_name(name):
           result.valid = false
   ```

3. **Location Consistency**: NPCs can't claim to visit places they've never been
   ```gdscript
   if "king's castle" in text_lower:
       var scope = WorldKnowledge.get_knowledge_scope_for_location(npc_id, "kings_castle")
       if scope == DISTANT and "i visited" in text_lower:
           result.valid = false  # NPC claiming to visit distant place
   ```

## Shared Player Facts

When an NPC learns the player's name, it's registered globally:

```gdscript
# In base_npc.gd _store_learned_player_info()
if WorldEvents:
    WorldEvents.register_player_info("name", player_name, npc_id)
```

Other NPCs can check if player is known:

```gdscript
# Get player name (returns "stranger" if unknown)
var name = WorldEvents.get_player_name()

# Check if player has introduced themselves to anyone
var is_known = WorldEvents.is_player_known()
```

### Player Facts Stored

```gdscript
var player_facts = {
    "name": null,           # Player's stated name
    "occupation": null,     # What they claim to do
    "origin": null,         # Where they claim to be from
    "notable_facts": [],    # Other things NPCs learned
    "first_seen": 0.0,      # Timestamp of first interaction
    "interactions": []      # List of NPC IDs player talked to
}
```

## Debug & Inspection Tools

### Dump NPC Memories

```gdscript
# Get reference to an NPC
var elena = get_tree().get_nodes_in_group("npcs").filter(
    func(n): return n.npc_id == "elena_daughter_001"
)[0]

# Dump all memories (grouped by tier)
var dump = await elena.debug_dump_memories()
print(dump)
```

Output:
```
=== MEMORY DUMP FOR elena_daughter_001 ===
Collection: npc_elena_daughter_001_memories
Using ChromaDB: true

Total memories: 12

--- PINNED MEMORIES (2) ---
[14:30] (player_info, imp:10) The player told me their name is Marcus.
[14:25] (first_meeting, imp:10) I met the player for the first time...

--- IMPORTANT MEMORIES (3) ---
[14:32] (conversation, imp:8) Player asked about my father's shop...

--- REGULAR MEMORIES (7) ---
[14:35] (conversation, imp:6) Player mentioned the weather...
...
=== END DUMP ===
```

### Print Full NPC State

```gdscript
await elena.debug_print_state()
```

Output:
```
=== NPC STATE: Elena (elena_daughter_001) ===
Location: thornhaven_town_square (home: thornhaven_gregor_shop)
Alive: true

Relationship Dimensions:
  Trust: 15.0
  Respect: 10.0
  Affection: 5.0
  Fear: 0.0
  Familiarity: 25.0

Known NPCs: 2
  - player (stranger, importance: 7)
  - gregor_merchant_001 (family, importance: 10)

Memory Stats:
  Total: 12 (Pinned: 2, Important: 3, Regular: 7)
  By type: {conversation: 8, player_info: 2, first_meeting: 1, ...}

WorldEvents Player Facts:
  Player name: Marcus
  Is known: true
=== END STATE ===
```

### Get Memory Statistics

```gdscript
var stats = await elena.debug_get_memory_stats()
print(stats)
# {total: 12, pinned: 2, important: 3, regular: 7, by_type: {...}}
```

### WorldEvents Debug

```gdscript
# Print all canonical events and player facts
WorldEvents.debug_print_events()
```

### In-Game Debug Hotkeys

The debug overlay (toggle with **F3**) provides quick memory inspection:

| Key | Action |
|-----|--------|
| **F3** | Toggle debug overlay on/off |
| **F4** | Dump ALL NPC memories to console |
| **F5** | Dump NEAREST NPC's memories + relationship state |

Output goes to the Godot console/Output panel.

### CLI Memory Dump Tool

Dump memories from the command line without launching the full game:

```bash
# Show help
godot --headless --script scripts/debug/memory_dump_cli.gd -- --help

# Dump all known NPCs
godot --headless --script scripts/debug/memory_dump_cli.gd -- --all

# Dump specific NPC
godot --headless --script scripts/debug/memory_dump_cli.gd -- --npc elena_daughter_001

# Show stats only (memory counts by tier)
godot --headless --script scripts/debug/memory_dump_cli.gd -- --stats
```

**Example --stats output:**
```
Memory Statistics for all NPCs:

  elena_daughter_001       :  12 total (P:2 I:3 R:7)
  gregor_merchant_001      :   5 total (P:1 I:2 R:2)
  mira_tavern_keeper_001   :   0 total (P:0 I:0 R:0)
  bjorn_blacksmith_001     :   3 total (P:1 I:0 R:2)
--------------------------------------------------
  TOTAL                    :  20 total (P:4 I:5 R:11)
```

**Known NPCs in CLI tool:**
- `elena_daughter_001`
- `gregor_merchant_001`
- `mira_tavern_keeper_001`
- `bjorn_blacksmith_001`

To add more NPCs, edit `KNOWN_NPCS` array in `scripts/debug/memory_dump_cli.gd`.

## Testing the System

### Test 1: Hallucination Sanitization

1. Start a conversation with any NPC
2. Say something that might trigger a tavern reference
3. Watch console for: `[Elena] HALLUCINATION FIXED: Weary Wanderer -> The Rusty Nail`
4. Verify the displayed response uses "The Rusty Nail"

### Test 2: Memory Rejection

1. Manually try to store an invalid memory:
   ```gdscript
   var result = await elena.rag_memory.store({
       "text": "Player told me about the Weary Wanderer tavern",
       "event_type": "conversation",
       "importance": 5
   })
   print(result)  # Should be false (rejected)
   ```

2. Check console for: `[RAGMemory] Memory REJECTED for elena_daughter_001: Contains forbidden name: 'weary wanderer'`

### Test 3: Geographic Knowledge Boundaries

1. Ask Elena about the King's castle
2. She should say something like "I've never been there" or "I've only heard stories"
3. Check console for proper knowledge scope being used

### Test 4: Shared Player Facts

1. Tell Elena your name: "I'm Marcus"
2. Check WorldEvents: `print(WorldEvents.get_player_name())` → "Marcus"
3. Talk to another NPC (e.g., Gregor)
4. They may reference "I heard there's a traveler named Marcus in town"

### Test 5: Memory Inspection

1. Have a few conversations with Elena
2. Run: `print(await elena.debug_dump_memories())`
3. Verify:
   - Player name is in PINNED memories
   - Conversations are properly categorized
   - No hallucinated establishment names appear

## Adding New Locations/Establishments

When adding new world content:

1. **Add to WorldKnowledge.world_facts**:
   ```gdscript
   "establishments": {
       "new_shop": {
           "name": "The New Shop Name",
           "type": "shop",
           "owner": "npc_id",
           "location": "parent_location"
       }
   }
   ```

2. **Add to location_hierarchy** (if new area):
   ```gdscript
   "new_location": {
       "parent": "thornhaven",
       "contains": [],
       "region": "northern_trade_region"
   }
   ```

3. **Update npc_locations** for NPCs in new area:
   ```gdscript
   "new_npc_001": "new_location"
   ```

4. **(Optional) Add hallucination patterns** for common alternatives:
   ```gdscript
   # In base_npc.gd _sanitize_response_hallucinations()
   "generic alternative name": "The New Shop Name"
   ```

## Troubleshooting

### Hallucinations Still Appearing

1. Check if WorldKnowledge is being injected:
   ```gdscript
   print(WorldKnowledge.get_world_facts_for_npc("elena_daughter_001"))
   ```

2. Check if sanitization is running (look for console logs)

3. Add the hallucinated pattern to `hallucination_replacements` dict

### Memories Not Being Stored

1. Check validation result:
   ```gdscript
   var result = WorldEvents.validate_memory("test text", "npc_id")
   print(result)  # {valid: bool, issues: [...], sanitized: "..."}
   ```

2. Check for forbidden patterns in `WorldEvents.forbidden_establishment_names`

### NPC Doesn't Know Player's Name

1. Check if name was learned:
   ```gdscript
   print(WorldEvents.player_facts)
   ```

2. Check NPC's pinned memories:
   ```gdscript
   print(await npc.debug_dump_memories())
   ```

3. Verify the Claude response included `learned_about_player.name` in analysis
