# NPC Existence and Influence System

> **Date:** 2026-03-28
> **Status:** Design Document (no code yet)
> **Depends on:** AUTONOMOUS_NPC_AGENTS.md (agent loop), existing WorldKnowledge, WorldState, EventBus, NPCPersonality, ContextBuilder

---

## 1. NPC Tier System

The core insight: not every character in the world needs a Claude API call, a personality resource, or even a name. Characters exist on a spectrum from full AI agents down to statistical abstractions. The tier system formalizes this spectrum and defines what each level gets.

### Tier 0: Story NPCs (Full Agency)

**Who:** Gregor, Elena, Mira, Bjorn, Aldric, Mathias, Varn, and any NPC promoted by story events.

**What they get:**
- Full `NPCPersonality` resource (Big Five traits, secrets, speech patterns, values, fears)
- Full 5D relationship tracking (Trust, Respect, Affection, Fear, Familiarity)
- Claude-powered dialogue via `ClaudeClient` + `ContextBuilder`
- RAG memory via ChromaDB (semantic recall of all past interactions)
- Autonomous agent loop (Perceive/Evaluate/Select/Execute/Reflect)
- InfoPacket gossip participation (send and receive)
- Individual entry in `WorldKnowledge.world_facts.npcs`
- Individual entry in `WorldState.npc_states`
- Can hold and reveal secrets with threshold-gated unlocking
- Scene presence: physical CharacterBody2D in the game world when on-screen

**Claude cost:** ~$0.15-0.20/hr across all Tier 0 NPCs (hybrid model from AUTONOMOUS_NPC_AGENTS.md)

**Data structure:**
```
Tier0NPC:
  npc_id: String                    # "gregor_merchant_001"
  personality: NPCPersonality       # Full .tres resource
  relationships: Dictionary         # {player: {trust, respect, ...}, npc_id: {trust, ...}}
  rag_collection: String            # ChromaDB collection name
  current_location: String          # Location ID
  goals: Array[Dictionary]          # [{goal, priority, conditions, deadline}]
  daily_schedule: Array[Dictionary] # [{time, action, location}]
  information_buffer: Array         # Pending InfoPackets to process
  known_secrets: Array[String]      # Secret IDs this NPC knows
  state: String                     # "active" | "departed" | "dead" | "imprisoned" | "exiled"
  departure_data: Dictionary        # If departed: {destination, reason, timestamp, return_conditions}
```

### Tier 1: Named Ambient NPCs (Moderate Agency)

**Who:** Village guards, farmers, the baker, the herbalist, council elders (when not story-critical), traveling merchants who visit regularly.

**What they get:**
- Simplified personality: a `Tier1Profile` resource with name, occupation, 2-3 personality adjectives, 1-2 values, a speaking style tag, and a short backstory sentence
- No secrets (unless promoted), no Big Five traits, no romance paths
- Single-axis relationship with player: Disposition (-100 to 100)
- Haiku-powered dialogue for most interactions, Sonnet escalation for complex/emotional moments
- **Simplified 3-step agent loop** (Perceive → Decide → Act) running every 2-5 minutes via Haiku
- Follow daily schedules, but Haiku can override schedule when situation warrants it
- Autonomously decide: what to gossip about, whether to mention something to the player, whether to change behavior, whether to leave town
- Can receive AND spread InfoPackets — Haiku decides what to share and with whom
- Listed in `WorldKnowledge.world_facts.npcs` with minimal entries
- Can be PROMOTED to Tier 0 if story events make them important

**Claude cost:** Near zero. Occasional escalation might cost $0.01-0.02/hr across all Tier 1 NPCs.

**Data structure:**
```
Tier1Profile:
  npc_id: String                  # "baker_hilda_001"
  display_name: String            # "Hilda"
  occupation: String              # "baker"
  personality_tags: Array[String] # ["cheerful", "gossipy", "superstitious"]
  speaking_style: String          # "warm" | "gruff" | "nervous" | etc.
  backstory_sentence: String      # "Has run the bakery since her mother passed."
  disposition: float              # -100 to 100, single axis
  schedule: Array[Dictionary]     # [{time, location}]
  dialogue_templates: Dictionary  # {greeting: [...], shop: [...], gossip: [...], farewell: [...]}
  heard_rumors: Array[String]     # InfoPacket IDs they've heard
  behavior_flags: Dictionary      # {anxious: false, celebratory: false, mourning: false}
  home_location: String           # "thornhaven"
```

**Template dialogue example:**
```
# greeting templates, selected by disposition + behavior_flags
greeting_positive: [
  "Morning, {player_name}! Fresh bread today.",
  "Ah, good to see you! The usual?",
]
greeting_anxious: [
  "Oh! You startled me. Sorry... been jumpy lately.",
  "Keep your voice down... heard there was trouble on the road.",
]
gossip: [
  "Did you hear? {rumor_content}",   # Pulls from heard_rumors
  "Mira was saying the other day that {rumor_content}",
]
```

**Promotion trigger:** When a Tier 1 NPC becomes central to a quest or the player forms a significant relationship (disposition > 60 with 5+ interactions), the system creates a full `NPCPersonality` resource from their `Tier1Profile` (expanding personality_tags into Big Five traits, generating secrets if the narrative calls for it), migrates their disposition to 5D relationships, and starts a ChromaDB collection.

### Tier 2: Off-Screen Named NPCs (Abstract Agency)

**Who:** The mayor of Millhaven, a merchant guild leader in the capital, a bandit warlord two regions over, a traveling scholar the player might meet later. Characters who exist in the world's lore and take actions, but the player never (or rarely) directly interacts with them.

**What they get:**
- A `Tier2Profile`: name, title/role, location, faction affiliation, 2-3 behavioral tendencies (e.g., "aggressive_expansionist", "cautious_diplomat", "greedy"), current_agenda
- No dialogue system (off-screen), but **Haiku-powered abstract reasoning** once per game-day
- No relationship with player (until player travels to them or they arrive locally)
- **Abstract 2-step agent loop** (Assess → Choose) via Haiku each game-day tick
- Can generate events that propagate inward as rumors reaching Tier 0/1 NPCs
- Referenced in `WorldKnowledge` under a new `regional_npcs` section (vague descriptions matching REGIONAL/DISTANT knowledge scope)
- Can be PROMOTED to Tier 1 (if they arrive locally) or Tier 0 (if they become story-critical)

**Claude cost:** Zero. Entirely rule-based.

**Data structure:**
```
Tier2Profile:
  npc_id: String                    # "mayor_aldwin_millhaven"
  display_name: String              # "Mayor Aldwin"
  title: String                     # "Mayor of Millhaven"
  location: String                  # "millhaven"
  faction: String                   # "millhaven_council"
  tendencies: Array[String]         # ["cautious_diplomat", "tax_raiser", "anti_bandit"]
  current_agenda: String            # "raise_militia" | "negotiate_with_bandits" | "increase_trade"
  agenda_progress: float            # 0.0 to 1.0
  relationships_abstract: Dictionary # {faction_id: sentiment} e.g., {"iron_hollow": -80, "thornhaven": 40}
  last_action_tick: int             # Game tick of last simulated action
```

### Tier 3: Populations/Factions (Statistical)

**Who:** "The Iron Hollow Gang" (as a collective), "Millhaven traders", "The King's army", "Northern road travelers", "Thornhaven villagers" (the unnamed mass).

**What they get:**
- A `FactionProfile`: name, type, base_location, strength, morale, resources, goals, disposition toward other factions
- No individual members (unless a member is a Tier 2+ NPC)
- **Strategic 1-step agent loop** via Haiku each game-day: evaluate goals, threats, opportunities → choose one strategic action
- Respond to world state changes with AI-reasoned strategic decisions, not just probability tables
- Influence local NPCs through `WorldState` flag changes and InfoPacket generation
- Interface with existing `WorldState.faction_reputations`

**Claude cost:** Zero.

**Data structure:**
```
FactionProfile:
  faction_id: String                # "iron_hollow_gang"
  display_name: String              # "The Iron Hollow Gang"
  type: String                      # "bandit" | "trade_guild" | "military" | "civilian" | "government"
  base_location: String             # "iron_hollow"
  strength: float                   # 0.0-100.0 (military/operational capacity)
  morale: float                     # 0.0-100.0
  resources: float                  # 0.0-100.0 (wealth, supplies)
  goals: Array[String]              # ["control_trade_route", "extort_thornhaven"]
  disposition: Dictionary           # {faction_id: float} toward other factions
  event_weights: Dictionary         # {event_type: weight} for random table
  active_effects: Array[String]     # Currently active modifiers: ["trade_disrupted", "recruiting"]
```

### Tier Summary Table

| Attribute | Tier 0 | Tier 1 | Tier 2 | Tier 3 |
|-----------|--------|--------|--------|--------|
| **Individual identity** | Full | Simplified | Minimal | None (collective) |
| **Dialogue** | Claude + RAG | Templates + rare Claude | None | None |
| **Relationships** | 5D per-NPC | Single axis (disposition) | Abstract (faction-level) | Faction dispositions |
| **Memory** | ChromaDB RAG | heard_rumors list | None | None |
| **Decision-making** | Full agent loop (Sonnet) | Simplified agent loop (Haiku) | Abstract agent loop (Haiku) | Strategic agent (Haiku) |
| **Physical presence** | CharacterBody2D | CharacterBody2D (simpler) | None (off-screen) | None |
| **Secrets** | Yes | No | No | No |
| **Can be promoted** | N/A (already max) | -> Tier 0 | -> Tier 1 or 0 | Members can become Tier 2 |
| **Claude cost** | ~$0.50-1.05/hr (Sonnet) | ~$0.07-0.17/hr (Haiku) | ~$0.01-0.04/hr (Haiku) | ~$0.003-0.008/hr (Haiku) |
| **Estimated count** | 7-12 | 10-25 | 20-50 | 5-15 factions |

---

## 2. Ripple Effect Engine

### Core Concept

Events don't just happen — they propagate. A local event creates consequences that spread outward through space and time, weakening with distance but sometimes amplifying when they hit the right conditions. The Ripple Effect Engine models this propagation.

### Data Structure: RippleEvent

```
RippleEvent:
  id: String                      # Unique ID: "ripple_001_mira_tavern_closed"
  source_event_id: String         # What triggered this ripple (another RippleEvent ID or "player_action_xxx")
  description: String             # Human-readable: "Mira closes The Rusty Nail"
  category: String                # "economic" | "social" | "political" | "military" | "personal"
  origin_location: String         # "thornhaven"
  current_scope: String           # "local" | "regional" | "world" (where it has propagated to so far)
  intensity: float                # 0.0-1.0 (attenuates with distance)
  timestamp_created: int          # Game tick when created
  timestamp_last_propagated: int  # Game tick of last propagation step
  propagation_delay: Dictionary   # {local: 1, regional: 3, world: 7} (game-days)
  effects: Array[RippleEffect]    # What this event causes at each scope level
  child_ripples: Array[String]    # IDs of ripples spawned by this one
  is_active: bool                 # False when fully propagated and resolved
  amplification_tags: Array[String] # Tags that can trigger cascades: ["trade", "fear", "leadership_vacuum"]
```

### Data Structure: RippleEffect

```
RippleEffect:
  scope: String                   # "local" | "regional" | "world"
  effect_type: String             # "flag_change" | "faction_modifier" | "npc_reaction" | "spawn_ripple" | "info_packet"
  target: String                  # Who/what is affected (npc_id, faction_id, flag_name)
  parameters: Dictionary          # Effect-specific data
  delay_days: int                 # Days after parent ripple reaches this scope
  applied: bool                   # Whether this effect has been applied
```

### Propagation Rules

**Timing:**
- LOCAL effects apply after 0-1 game-days
- REGIONAL effects apply after 2-4 game-days
- WORLD effects apply after 5-10 game-days
- Each propagation step, intensity attenuates by 0.2 (configurable per event category)

**Attenuation by category:**
| Category | Local->Regional decay | Regional->World decay |
|----------|----------------------|----------------------|
| economic | 0.15 | 0.25 |
| military | 0.10 | 0.20 |
| political | 0.20 | 0.30 |
| social | 0.30 | 0.50 |
| personal | 0.50 | 0.80 |

Economic and military events carry further. Personal events (someone's mood, a private quarrel) barely ripple beyond the village.

**Amplification:**
When a ripple arrives at a new scope, the engine checks for amplification conditions:
- If a faction at that scope has a matching vulnerability tag (e.g., ripple tagged "trade_disruption" hits a faction with goal "control_trade_route"), intensity is multiplied by 1.5 and a child ripple is spawned
- If multiple ripples with the same category arrive at the same scope within 3 game-days, they combine: intensity = max(intensities) + 0.1 * sum(other intensities)
- If a ripple's intensity drops below 0.05, it is discarded (too weak to matter)

**Interference:**
- Opposing ripples (e.g., "trade_flourishing" and "trade_disrupted" at the same scope) cancel: both lose intensity equal to the weaker one's intensity
- Reinforcing ripples (same category, same direction) combine as described above

### The Propagation Loop

Runs once per game-day (or per time-period tick if using dawn/morning/noon/evening/night):

```
for each active RippleEvent:
    days_since_last_propagation = current_tick - event.timestamp_last_propagated

    for each unapplied RippleEffect in event.effects:
        if effect.scope matches event's next propagation target:
            if days_since_last_propagation >= effect.delay_days:
                apply_effect(effect)
                effect.applied = true

    # Check if ready to propagate to next scope
    if all effects at current scope are applied:
        next_scope = get_next_scope(event.current_scope)
        if next_scope != null:
            event.intensity *= get_attenuation(event.category, event.current_scope)
            if event.intensity >= 0.05:
                event.current_scope = next_scope
                check_amplification(event, next_scope)
                event.timestamp_last_propagated = current_tick
            else:
                event.is_active = false  # Too weak, stop propagating
        else:
            event.is_active = false  # Reached world scope, done
```

### Effect Application

When `apply_effect` fires, it translates the abstract effect into concrete game changes:

| effect_type | What happens |
|-------------|-------------|
| `flag_change` | `WorldState.set_world_flag(target, parameters.value)` |
| `faction_modifier` | Modifies `FactionProfile` attributes (strength, morale, resources) |
| `npc_reaction` | Adds an entry to a Tier 0/1 NPC's information_buffer or behavior_flags |
| `spawn_ripple` | Creates a new `RippleEvent` (cascade) |
| `info_packet` | Creates an InfoPacket that enters the gossip system |
| `economy_change` | Modifies prices, supply, or availability at a location |
| `npc_state_change` | Changes an NPC's state (e.g., Tier 2 NPC changes agenda) |

---

## 3. NPC Departure and Absence

### Departure States

An NPC can leave the active story in several ways. Each has different mechanical implications:

| State | Physical presence | Memory persists | Can return | Generates off-screen events |
|-------|------------------|----------------|------------|---------------------------|
| **Departed (voluntary)** | Removed from scene | Yes, in all NPCs who knew them | Yes, if conditions met | Yes (letters, rumors) |
| **Exiled** | Removed from scene | Yes | Only if exile is lifted | Rarely (bitter rumors) |
| **Imprisoned** | Moved to prison scene or removed | Yes | If freed | No (isolated) |
| **Dead** | Removed, gravestone possible | Yes, as grief/legacy | No | No |
| **Traveling** | Temporarily removed | Yes | Yes, after travel time | Yes (reports from road) |

### What Happens When an NPC Departs

Using Mira as the example (she closes The Rusty Nail and leaves Thornhaven):

**Step 1: State Change**
```
WorldState.npc_states["mira_tavern_keeper_001"] = {
    "state": "departed",
    "previous_location": "thornhaven_tavern",
    "destination": "millhaven",         # or "unknown"
    "departure_reason": "voluntary",
    "departure_timestamp": current_tick,
    "return_conditions": ["player_sends_letter", "bandit_threat_resolved"],
    "is_alive": true
}
```

**Step 2: Physical Removal**
- Mira's CharacterBody2D is removed from the tavern scene
- The tavern scene changes: empty counter, dust, "CLOSED" sign (environmental storytelling)
- If Mira was Tier 0, her agent loop stops ticking

**Step 3: Role Vacuum**
The departure creates a `RippleEvent` with these effects:
- LOCAL: `flag_change` -> "tavern_closed" = true
- LOCAL: `info_packet` -> "Mira left Thornhaven" spreads to all local NPCs
- LOCAL: `npc_reaction` -> Each NPC who knew Mira processes the departure:
  - Gregor: loses an information source, may feel guilt (she left because of the bandit situation he enabled)
  - Elena: loses a friend/mentor figure
  - Bjorn: loses a customer and social connection
  - Tier 1 NPCs: behavior_flags.mourning = true for close contacts; gossip templates shift to reference Mira's departure
- REGIONAL: `economy_change` -> Thornhaven loses its inn; traveling merchants have nowhere to stay; trade visits decrease
- REGIONAL: `info_packet` -> "The Rusty Nail in Thornhaven closed" reaches off-screen NPCs as rumor
- REGIONAL: `faction_modifier` -> Iron Hollow Gang's "thornhaven_control" score changes (one less person to extort, but also one less information vector)

**Step 4: Vacuum Filling (Delayed)**
After 3-5 game-days, the vacuum triggers secondary effects:
- A Tier 1 NPC (or new Tier 1) might attempt to reopen the tavern or repurpose the building
- If no one fills the role, the "no_tavern" flag persists and continues generating ripples (reduced gossip flow, lower traveler traffic)
- Council elder Mathias might raise this as a concern at the next council meeting

**Step 5: Off-Screen Existence**
If the departed NPC was Tier 0, they transition to Tier 2 while off-screen:
- Their full personality and memory are archived (saved to disk, ChromaDB collection preserved)
- A `Tier2Profile` is created from their personality (tendencies derived from Big Five traits, agenda = departure_reason)
- They participate in off-screen simulation at Tier 2 resolution
- They may generate events: "A letter arrives from Mira in Millhaven" (InfoPacket, category: "personal", source: off-screen)

**Step 6: Potential Return**
If return_conditions are met:
- The Tier 2 profile is retired
- The archived Tier 0 data is restored
- A new memory is added to their ChromaDB collection summarizing their time away (generated via a single Claude call: "Summarize Mira's experience traveling to Millhaven and living there for X days, given her personality and the world events that occurred")
- Their relationships may have shifted (time away reduces familiarity with player by -1/day, but trust/affection persist)
- They re-enter the scene with dialogue that references their absence

### Handling Quests Involving Departed NPCs

When an NPC departs and they are involved in active quests:

| Situation | Resolution |
|-----------|-----------|
| NPC was quest giver | Quest enters "abandoned" state; a different NPC may pick up the thread ("Mira left this note for you before she went...") |
| NPC was quest target | Quest fails or transforms ("Find where Mira went" becomes a new quest) |
| NPC held critical information | Information enters the gossip system as a rumor, or is left behind as a physical note/letter |
| NPC was romance interest | Romance is suspended; player can pursue it if NPC returns; other NPCs comment on the absence |

---

## 4. Off-Screen Simulation Architecture

### World Simulation Layer

A new singleton: `WorldSimulation` (autoload), responsible for simulating everything beyond the player's immediate scene.

**Tick rate:** Once per game-day (or once per time-period change if the game uses dawn/morning/noon/evening/night, which is 4-5 ticks per game-day). Heavier computation (ripple propagation, faction actions) runs once per game-day. Lighter checks (NPC schedule changes, gossip spread) can run per time-period.

### Data Structures

**RegionMap** (held by WorldSimulation):
```
RegionMap:
  regions: Dictionary
    # region_id -> RegionData
    "northern_trade_region":
      name: "Northern Trade Region"
      locations: ["thornhaven", "millhaven", "crossroads_inn"]
      trade_routes: [{from: "thornhaven", to: "millhaven", safety: 0.7, traffic: 0.5}]
      dominant_faction: "millhaven_council"

    "capital_region":
      name: "The Capital Region"
      locations: ["kings_castle", "portwall", "highmarket"]
      trade_routes: [...]
      dominant_faction: "the_crown"
```

**OffScreenEventTable** (rule-based event generation):
```
OffScreenEventTable:
  entries: Array[OffScreenEventRule]

OffScreenEventRule:
  id: String                        # "bandit_raid_trade_route"
  preconditions: Dictionary         # {flags: {bandit_activity_high: true}, faction_min: {iron_hollow: {strength: 30}}}
  probability_per_tick: float       # 0.0-1.0 per game-day
  faction_source: String            # Which faction triggers this
  category: String                  # "military"
  generates_ripple: RippleEvent     # Template for the ripple this creates
  generates_info_packet: Dictionary # Template for gossip this creates
  cooldown_days: int                # Minimum days between occurrences
  last_triggered: int               # Game tick of last trigger
```

### How Off-Screen Events Are Generated

Each game-day tick:

1. **Faction Action Phase:** Each `FactionProfile` evaluates its goals against its state:
   - If `strength > 60` and goal is "expand_territory": roll against probability table for expansion event
   - If `resources < 20` and goal is "survival": generate "faction_weakening" event
   - If `morale < 30`: generate "faction_desertion" event (reduces strength)

2. **Tier 2 NPC Action Phase:** Each `Tier2Profile` evaluates agenda_progress:
   - Progress increments by 0.05-0.15 per tick (modified by faction strength, resources)
   - When agenda_progress reaches 1.0: the agenda completes, generating a RippleEvent
   - Example: Mayor Aldwin's "raise_militia" agenda completes -> RippleEvent: "Millhaven militia formed" with REGIONAL military ripple

3. **Off-Screen Event Table Phase:** Roll against each active rule's probability:
   - Check preconditions against current WorldState flags and faction states
   - If triggered and not on cooldown: instantiate the RippleEvent and InfoPacket templates
   - Apply cooldown

4. **Trade Route Phase:** For each trade route, calculate safety and traffic:
   - Safety = base_safety - (local_bandit_strength * 0.01) + (local_military_strength * 0.005)
   - Traffic = base_traffic * safety * regional_economy_modifier
   - Low traffic generates economic ripples at connected locations

### How Off-Screen Events Become Local Gossip

The bridge between off-screen simulation and local NPC experience is the **InfoPacket injection** system:

1. When a RippleEvent reaches a scope that includes the player's current region, any `info_packet` effects create InfoPackets
2. These InfoPackets are tagged with a `delivery_method`:
   - `"traveler"`: A generic traveler NPC delivers the news (Tier 1 template dialogue: "I just came from Millhaven. Did you hear...?")
   - `"merchant"`: A regular merchant mentions it during trade
   - `"letter"`: A physical letter appears at a location (the tavern, the shop)
   - `"rumor_chain"`: The info enters the highest-extraversion local NPC's gossip buffer and spreads organically
   - `"official_notice"`: Posted on the village notice board (environmental object the player can read)
3. InfoPackets from off-screen have lower initial confidence (0.4-0.6) reflecting their distant, second-hand nature
4. Tier 0 NPCs receive these in their `information_buffer` and process them during their agent tick
5. Tier 1 NPCs add them to `heard_rumors` and may surface them in template dialogue

### How Player Reputation Reaches Off-Screen

Player actions that affect faction reputation propagate outward:
- `WorldState.faction_reputations` changes emit `faction_reputation_changed` on EventBus
- `WorldSimulation` listens for this signal
- Creates a RippleEvent with category "political" or "social" carrying the player's reputation change
- As the ripple propagates, Tier 2 NPCs and Tier 3 factions at each scope adjust their abstract disposition toward the player
- When the player eventually travels to a new region, the local NPCs there already have heard of them (or not, if the ripple attenuated to nothing)

---

## 5. Integration with Existing Systems

### WorldKnowledge Integration

**Current state:** `WorldKnowledge` has `KnowledgeScope` enum (INTIMATE/LOCAL/REGIONAL/DISTANT/UNKNOWN) and `location_hierarchy` with regions.

**New additions:**
- `WorldKnowledge.regional_npcs`: A dictionary of Tier 2 NPCs, structured like `world_facts.npcs` but with less detail. NPCs reference these with REGIONAL or DISTANT scope.
- `WorldKnowledge.factions`: A dictionary of Tier 3 factions, providing canonical names and descriptions for anti-hallucination.
- `WorldKnowledge.get_world_facts_for_npc()` is extended: the "WHAT YOU DON'T KNOW" section now dynamically references off-screen events that have reached LOCAL scope. Instead of hardcoded "You have NEVER been to the King's castle", it checks ripple state: if a ripple from the capital has reached Thornhaven, the NPC knows that rumor.

**Mapping tiers to scopes:**
| NPC Tier | Knowledge Scope they occupy for other NPCs |
|----------|-------------------------------------------|
| Tier 0 (same location) | INTIMATE or LOCAL |
| Tier 0 (different location) | LOCAL |
| Tier 1 (same village) | LOCAL |
| Tier 2 (same region) | REGIONAL |
| Tier 2 (different region) | DISTANT |
| Tier 3 (factions) | REGIONAL or DISTANT depending on faction base |

### EventBus Integration

**New signals needed on EventBus:**
```
signal ripple_created(ripple_id: String, ripple_data: Dictionary)
signal ripple_propagated(ripple_id: String, new_scope: String, intensity: float)
signal ripple_effect_applied(ripple_id: String, effect_type: String, target: String)
signal npc_departed(npc_id: String, departure_data: Dictionary)
signal npc_returned(npc_id: String, return_data: Dictionary)
signal npc_tier_changed(npc_id: String, old_tier: int, new_tier: int)
signal offscreen_event_generated(event_id: String, event_data: Dictionary)
signal faction_action_taken(faction_id: String, action_data: Dictionary)
signal trade_route_status_changed(route_id: String, old_safety: float, new_safety: float)
```

These integrate with the existing `world_event`, `world_flag_changed`, and `faction_reputation_changed` signals. The ripple engine listens to existing signals as triggers and emits new signals as outputs.

### InfoPacket / Gossip Integration

The InfoPacket model from AUTONOMOUS_NPC_AGENTS.md is the bridge:

```
Off-screen event -> RippleEffect (type: info_packet) -> InfoPacket created ->
  -> If delivery_method is "rumor_chain": injected into a Tier 0 NPC's information_buffer
  -> NPC processes it during agent tick -> may spread to other NPCs via gossip rules
  -> Player discovers it by talking to NPCs
```

The confidence decay rules from AUTONOMOUS_NPC_AGENTS.md apply: each retelling drops confidence by 0.15, and after 3+ hops the NPC prefaces with "I heard that..."

Off-screen InfoPackets start with lower confidence (0.4-0.6) and are already prefaced with uncertainty markers ("Word from the capital is that...").

### WorldState Integration

**Extensions to WorldState:**
```
# Existing (keep as-is):
var faction_reputations: Dictionary
var npc_states: Dictionary
var world_flags: Dictionary

# New:
var npc_tiers: Dictionary              # npc_id -> tier (0, 1, 2)
var departed_npcs: Dictionary          # npc_id -> departure_data
var active_ripples: Array[Dictionary]  # Active RippleEvents
var faction_profiles: Dictionary       # faction_id -> FactionProfile data
var tier2_npcs: Dictionary             # npc_id -> Tier2Profile data
var region_states: Dictionary          # region_id -> {economy, safety, politics}
var off_screen_event_log: Array        # Last N off-screen events for debugging/save
```

The existing `save()` and `load_from_dict()` methods on WorldState are extended to include the new dictionaries. The existing `npc_states` dictionary gains the new states ("departed", "exiled", "traveling") alongside the existing "is_alive" tracking.

### ContextBuilder Integration

When building context for a Tier 0 NPC, `ContextBuilder._build_world_state_section()` is extended to include:

1. **Off-screen events that reached this NPC:** Query `WorldSimulation` for InfoPackets in this NPC's buffer that originated from off-screen. Format as "RUMORS FROM BEYOND THORNHAVEN" section.
2. **Departed NPC awareness:** If any NPC this character knew has departed, include a note: "Mira left Thornhaven 5 days ago. You feel [emotion based on relationship]."
3. **Faction pressure:** If faction actions are affecting this NPC's location, summarize: "The Iron Hollow Gang has been more active lately. Trade on the northern route has slowed."

This information goes into the system prompt at SECTION 8 (World State), which has appropriate priority for truncation.

### NPC Tier Transitions

**Promotion (Tier 1 -> Tier 0):**
1. Triggered by: quest involvement, player relationship threshold, or narrative event
2. `EventBus.npc_tier_changed` emitted
3. `Tier1Profile` is expanded into full `NPCPersonality` resource:
   - personality_tags -> Big Five traits (mapped via lookup table: "cheerful" -> extraversion:60, agreeableness:50)
   - disposition -> 5D relationship (disposition maps primarily to Trust, with smaller spread to Affection and Familiarity)
   - backstory_sentence -> expanded core_identity via a single Claude call
   - dialogue_templates discarded in favor of Claude-generated dialogue
4. ChromaDB collection created; heard_rumors migrated as initial memories
5. Agent loop starts ticking for this NPC

**Demotion (Tier 0 -> Tier 2, on departure):**
1. Full personality and RAG memory archived to disk
2. `Tier2Profile` created from personality (Big Five -> tendencies, current goal -> agenda)
3. Agent loop stops; NPC enters off-screen simulation
4. If NPC returns, archived data is restored

**Promotion (Tier 2 -> Tier 1, NPC arrives locally):**
1. `Tier2Profile` expanded into `Tier1Profile`
2. Tendencies -> personality_tags, agenda -> schedule behavior
3. Dialogue templates generated (or hand-authored if important)
4. CharacterBody2D spawned in appropriate scene

---

## 6. Scenario: "Mira Leaves Thornhaven"

### Trigger

The player has been in Thornhaven for 10 game-days. Bandit raids have intensified (a ripple from Iron Hollow Gang's increased strength). Mira's morale has dropped below a threshold due to:
- Tavern income declining (fewer travelers because trade route is dangerous)
- Fear increasing (bandit presence in village)
- No progress on justice for her husband (player hasn't helped enough)

During her agent tick, Mira's goal evaluation scores "leave_thornhaven" higher than "keep_tavern_running" for the first time. This is a complex decision (involves abandoning her livelihood, her social network, and her cover identity as The Boss) -- it escalates to Claude.

Claude decides: Mira leaves. (Or, if Mira is The Boss and is strategically relocating, Claude decides this differently -- the system works the same mechanically.)

### Day 0: Departure

**1. NPC State Change:**
```
WorldState.npc_states["mira_tavern_keeper_001"].state = "departed"
WorldState.npc_states["mira_tavern_keeper_001"].destination = "millhaven"
```

**2. EventBus:**
```
EventBus.npc_departed.emit("mira_tavern_keeper_001", {destination: "millhaven", reason: "voluntary"})
```

**3. RippleEvent Created:**
```
RippleEvent:
  id: "ripple_mira_departure_001"
  description: "Mira Hearthwood closes The Rusty Nail and leaves Thornhaven"
  category: "social" + "economic"  # dual category
  origin: "thornhaven"
  intensity: 0.8  # Major local event
  effects:
    - {scope: "local", type: "flag_change", target: "tavern_closed", params: {value: true}, delay: 0}
    - {scope: "local", type: "flag_change", target: "mira_departed", params: {value: true}, delay: 0}
    - {scope: "local", type: "info_packet", target: "all_local", params: {content: "Mira has closed The Rusty Nail and left for Millhaven", category: "gossip", confidence: 0.95}, delay: 0}
    - {scope: "local", type: "economy_change", target: "thornhaven", params: {lodging: -1.0, food_variety: -0.3, gossip_flow: -0.5}, delay: 1}
    - {scope: "regional", type: "info_packet", target: "regional_npcs", params: {content: "Thornhaven's only tavern has closed", category: "rumor", confidence: 0.6}, delay: 3}
    - {scope: "regional", type: "economy_change", target: "northern_trade_route", params: {thornhaven_stop_value: -0.5}, delay: 3}
    - {scope: "regional", type: "spawn_ripple", target: null, params: {template: "trade_reroute_away_from_thornhaven"}, delay: 5}
  amplification_tags: ["social_hub_lost", "trade_disruption"]
```

**4. Mira Transitions to Tier 2:**
- Full personality archived
- Tier2Profile created: tendencies = ["cautious", "grief_driven", "information_broker"], agenda = "establish_new_life"
- Agent loop stops

**5. Scene Changes:**
- Mira's CharacterBody2D removed from tavern scene
- Tavern interior scene swaps to "closed" variant: empty chairs, dark fireplace, dust, a note on the bar

### Day 0-1: Local Reactions

**6. Tier 0 NPCs process the InfoPacket:**

*Gregor:* During his agent tick, receives "Mira departed" info. His goal system evaluates:
- Loses a key social contact and potential information leak (mixed feelings if he's the informant)
- Tavern closing means less foot traffic near his shop
- Rule-based: anxiety_level += 1, adds "mira_left" to recent_triggers
- Claude escalation: "Gregor is conflicted about Mira leaving. She knew about his late-night meetings. Is he relieved or worried?" Claude decides.
- Gregor's next dialogue with player references it: "Did you hear? Mira left. Packed up in the night. The Rusty Nail just... empty."

*Elena:* Receives info. Processes as loss of a friend figure. Affection for Mira was high.
- Rule-based: current_mood = "sad"
- Next dialogue: "I can't believe Mira's gone. She always had a kind word for me..."

*Bjorn:* Receives info. Processes as practical concern (he ate at the tavern).
- Rule-based: schedule adjusts (no more evening tavern visit)
- Next dialogue: "Tavern's closed. Suppose I'll be cooking for myself now. *grumbles*"

**7. Tier 1 NPCs react:**
- Baker Hilda: behavior_flags.mourning = true for 3 days. Gossip templates shift: "Poor Mira. I wonder what drove her away."
- Guard captain: behavior_flags.anxious = true. Template: "Another one leaving. This village is dying."

### Day 1-3: Gossip Spreads

**8. InfoPacket propagation among local NPCs:**
- Mira's departure gossip spreads to all local NPCs within 1 day (high confidence, major event)
- Each NPC adds their own spin when they spread it (personality-dependent):
  - Gossipy NPC: "I always thought she'd leave eventually. That tavern was losing money hand over fist."
  - Fearful NPC: "If Mira's leaving, maybe we should too. It's not safe here."
- Player can hear different versions depending on who they talk to

### Day 3-5: Regional Ripple

**9. Regional effects activate:**
- InfoPacket "Thornhaven's tavern closed" reaches Tier 2 NPCs in Millhaven
- Mayor Aldwin (Tier 2) adjusts: if his agenda was "increase_trade_with_thornhaven", progress resets
- Trade route safety/value for Thornhaven decreases (no inn for travelers)
- Off-screen event table: "traveling_merchant_skips_thornhaven" probability increases

### Day 5-7: Cascade

**10. Amplification check:**
- The "trade_disruption" tag on Mira's ripple hits the "northern_trade_route" which already has reduced safety (bandit activity). Amplification triggers.
- A child ripple spawns: "Northern trade route becoming unreliable"
  - REGIONAL effect: merchants reroute to southern roads
  - This affects Gregor's supply chain (fewer goods arriving)
  - Gregor's shop prices increase (economy_change effect)

**11. Further cascade:**
- Higher prices in Thornhaven -> villagers (Tier 3 "thornhaven_villagers") morale decreases
- Lower morale -> increased probability of "villager_leaves" events in off-screen table
- If enough villagers leave, population drops, which further reduces trade value
- The pebble-in-a-pond effect is complete: one woman leaving her tavern is slowly strangling the village

### Day 7+: What the Player Experiences

**12. Player discovery points:**
- **Immediate:** Walk into the tavern, find it empty and dark. Environmental storytelling.
- **Day 1:** Talk to any NPC -- they all reference Mira's departure with different emotions
- **Day 3:** Notice that the traveling merchant who visits weekly doesn't show up
- **Day 5:** Gregor mentions his supply costs have gone up. "With Mira gone, fewer traders stop here."
- **Day 7:** A letter arrives from Mira (if player had high trust): an InfoPacket delivered as a physical item. "Dear friend, I've reached Millhaven. It's bigger here, but colder somehow..."
- **Day 10+:** New quest possibility: "Convince Mira to return" or "Find someone to reopen the tavern"
- **Day 14+:** If bandits are still active, they notice the weakened village. Raid frequency increases. This is the spiral the player must break.

### If the Player Prevented Mira's Departure

If the player had built high trust with Mira (Trust > 70) and resolved some of her concerns (helped with tavern, made progress against bandits), her goal evaluation would never score "leave_thornhaven" high enough to trigger. None of this cascade happens. The player's investment in a relationship prevented a systemic collapse -- the ripple that never was.

---

## 7. Cost Model: Every NPC Thinks

### Core Principle

**Autonomous AI agency is the game's core architecture, not a privilege reserved for story NPCs.** Every NPC at every tier gets a thinking budget. Tiers control the *model*, *frequency*, and *prompt depth* — never whether the NPC gets to reason at all.

The baker decides whether to mention what she saw. The off-screen mayor reasons about his militia strategy. The bandit faction weighs whether this is the right moment to raid. Every entity in the world is an AI agent.

### Per-Tier AI Budget

| Tier | Model | Think Frequency | Prompt Budget | Dialogue Model | Agent Loop |
|------|-------|----------------|---------------|----------------|------------|
| **Tier 0** | Sonnet | Every 30-60s | ~2000 tokens | Sonnet (full) | Full (5-step) |
| **Tier 1** | Haiku | Every 2-5 min | ~800 tokens | Haiku (+ Sonnet escalation) | Simplified (3-step) |
| **Tier 2** | Haiku | Every game-day | ~500 tokens | N/A (off-screen) | Abstract (2-step) |
| **Tier 3** | Haiku | Every game-day | ~400 tokens | N/A (collective) | Strategic (1-step) |

### What Each Tier Thinks About

**Tier 0 (Story NPCs) — Full Reasoning:**
- Complex social decisions (secrets, alliances, betrayals)
- Dialogue generation with full personality and memory
- Goal evaluation with multi-factor trade-offs
- Reflections on accumulated experiences
- Reactions to ripple effects with emotional nuance

**Tier 1 (Ambient NPCs) — Situational Reasoning:**
- "Should I mention what I saw last night?" (weighs risk, trust, personality)
- "The player seems trustworthy — should I share this rumor?" (social judgment)
- "Bandits are getting bolder — should I leave town?" (survival reasoning)
- Dialogue that goes beyond templates when the situation calls for it
- Goal evaluation with simpler trade-offs (2-3 factors, not 10)

**Tier 2 (Off-Screen NPCs) — Strategic Reasoning:**
- "My militia is ready — should I move against the bandits now or wait?" (timing)
- "A letter from Thornhaven — should I respond?" (relationship management)
- "Trade routes are shifting — should I adjust my agenda?" (adaptation)
- Generates decisions that create ripple effects reaching the player's world

**Tier 3 (Factions) — Collective Reasoning:**
- "Our strength is high and Thornhaven's defenses are weak — raid or recruit?" (strategic)
- "We lost three members to the player — retaliate or consolidate?" (response)
- "A new trade opportunity emerged — exploit it?" (opportunistic)
- Faction decisions that feel like they were made by someone, not rolled on a table

### Agent Loop by Tier

**Tier 0: Full 5-Step Loop** (Perceive → Evaluate Goals → Select Action → Execute → Reflect)
- Perceive: Full world state, memories, nearby NPCs, information buffer
- Evaluate: All goals scored with personality modifiers
- Select: Complex actions escalate to Sonnet
- Execute: Full EventBus integration
- Reflect: Periodic higher-order observations stored as memories

**Tier 1: Simplified 3-Step Loop** (Perceive → Decide → Act)
- Perceive: Local world state, recent gossip, behavior flags
- Decide: Haiku evaluates 2-3 options with personality context
- Act: Simpler action space (move, gossip, change behavior, alert)
- No separate reflection phase — but decisions accumulate in a simple memory log

**Tier 2: Abstract 2-Step Loop** (Assess → Choose)
- Assess: Haiku receives current agenda, faction state, recent regional events
- Choose: Advance agenda, change agenda, take a specific action, or wait
- One decision per game-day tick, stored as an event in off-screen log

**Tier 3: Strategic 1-Step Loop** (Decide)
- Haiku receives faction state, goals, threats, opportunities
- Returns one strategic action per game-day
- Action becomes a ripple event affecting the world

### Prompt Templates by Tier

**Tier 0 Decision Prompt (~2000 tokens):**
Full personality, current goals, relationship states, recent memories, world context, available actions.

**Tier 1 Decision Prompt (~800 tokens):**
```
You are {name}, {occupation} in {location}. You are {personality_tags}.
SITUATION: {current_situation}
YOU KNOW: {recent_gossip_summary}
YOUR MOOD: {behavior_flags}
CHOOSE ONE:
1. {action_a} — {consequence}
2. {action_b} — {consequence}
3. {action_c} — {consequence}
JSON: {"action": "id", "reason": "brief", "would_mention_to_player": true/false}
```

**Tier 2 Decision Prompt (~500 tokens):**
```
You are {name}, {title}. Tendencies: {tendencies}.
CURRENT AGENDA: {agenda} (progress: {progress}%)
REGIONAL STATE: {relevant_regional_summary}
RECENT EVENTS: {recent_events_affecting_you}
CHOOSE ONE: advance_agenda | change_agenda({new}) | take_action({action}) | wait
JSON: {"choice": "id", "reason": "brief", "generates_event": "description or null"}
```

**Tier 3 Decision Prompt (~400 tokens):**
```
You represent {faction_name} ({type}). Goals: {goals}.
STATE: strength={strength}, morale={morale}, resources={resources}
THREATS: {threats}
OPPORTUNITIES: {opportunities}
CHOOSE ONE strategic action:
1. {option_a}
2. {option_b}
3. {option_c}
4. Hold position
JSON: {"action": "id", "reason": "brief"}
```

### Revised Cost Analysis

**Model pricing (Claude):**
- Sonnet: $3/M input, $15/M output
- Haiku: $0.80/M input, $4/M output

**Per-decision costs:**

| Tier | Model | Input tokens | Output tokens | Cost/decision |
|------|-------|-------------|---------------|---------------|
| T0 decision | Sonnet | ~800 | ~150 | $0.00465 |
| T0 dialogue | Sonnet | ~2000 | ~300 | $0.01050 |
| T1 decision | Haiku | ~800 | ~100 | $0.00104 |
| T1 dialogue | Haiku | ~800 | ~200 | $0.00144 |
| T2 decision | Haiku | ~500 | ~80 | $0.00072 |
| T3 decision | Haiku | ~400 | ~60 | $0.00056 |

**Hourly cost (full world simulation):**

| Tier | NPCs | Decisions/hr | Dialogue/hr | Cost/hr |
|------|------|-------------|-------------|---------|
| T0 | 7-12 | 60-120 (1-2/min each) | 20-50 (player-driven) | $0.49-$1.05 |
| T1 | 10-25 | 60-150 (1 per 2-5 min each) | 5-15 (player-driven) | $0.07-$0.17 |
| T2 | 20-50 | 20-50 (1/game-day each) | 0 | $0.01-$0.04 |
| T3 | 5-15 | 5-15 (1/game-day each) | 0 | $0.003-$0.008 |
| **Total** | **42-102** | **145-335** | **25-65** | **$0.57-$1.27** |

**Per-session cost (2-hour session): $1.14-$2.54**

### Cost Optimization Levers (AWS Bedrock)

Even with every tier thinking, costs are manageable via:

1. **Prompt caching (Bedrock):** Static personality/world content in system prompt cached → ~90% reduction on cached input tokens
2. **Bedrock Batch Inference:** Tier 2-3 game-day decisions submitted as a single batch job → up to 50% cheaper than on-demand
3. **Decision throttling:** Tier 0 NPCs far from player think every 2 min instead of 30s
4. **Shared context batching:** Tier 3 faction decisions bundled: multiple factions' state in one call → fewer calls
5. **Result caching:** If world state hasn't changed since last tick, skip the decision
6. **Provisioned Throughput (optional):** For production at scale, fixed hourly cost regardless of call volume — becomes cheaper than on-demand above ~50 agents
7. **CloudWatch budgets:** Set cost alarms per tier to prevent runaway spending

**Optimized cost: $0.35-$0.80/hr, or $0.70-$1.60 per 2-hour session.**

### Why This Cost Is Worth It

The difference between a $0.16/hr game (rules for most NPCs) and a $0.60/hr game (every NPC thinks):

- The baker who mentions something unprompted because Haiku decided it was relevant
- The off-screen mayor whose militia timing feels strategic, not random
- The bandit faction that adapts to the player's tactics instead of following a script
- Tier 1 NPCs who feel like people, not furniture with dialogue boxes
- A world where EVERY entity has agency — the game's core identity

---

## 8. Data Structures Summary

### New Files Needed

| File | Purpose |
|------|---------|
| `scripts/world_state/world_simulation.gd` | Autoload singleton. Manages off-screen ticks, faction actions, Tier 2 NPC simulation, trade routes. |
| `scripts/world_state/ripple_engine.gd` | Manages RippleEvent lifecycle: creation, propagation, attenuation, amplification, effect application. |
| `scripts/resources/tier1_profile.gd` | Resource class for Tier 1 ambient NPCs. |
| `scripts/resources/tier2_profile.gd` | Resource class for Tier 2 off-screen NPCs. |
| `scripts/resources/faction_profile.gd` | Resource class for Tier 3 factions. |
| `scripts/resources/ripple_event.gd` | Resource/data class for ripple events. |
| `scripts/resources/offscreen_event_rule.gd` | Resource for off-screen event table entries. |
| `scripts/npcs/tier1_npc.gd` | Extends CharacterBody2D. Simplified NPC with template dialogue, schedule, gossip reception. |
| `scripts/world_state/region_map.gd` | Defines regions, locations, trade routes, and their connections. |
| `scripts/world_state/npc_departure_manager.gd` | Handles the departure/return flow: archive, transition, vacuum effects, return restoration. |

### Modified Files

| File | Changes |
|------|---------|
| `scripts/world_state/world_state.gd` | Add npc_tiers, departed_npcs, active_ripples, faction_profiles, tier2_npcs, region_states. Extend save/load. |
| `scripts/world_state/world_knowledge.gd` | Add regional_npcs, factions sections to world_facts. Extend `get_world_facts_for_npc()` to include off-screen rumors that have reached LOCAL scope. |
| `scripts/world_state/event_bus.gd` | Add new signals: ripple_created, ripple_propagated, npc_departed, npc_returned, npc_tier_changed, offscreen_event_generated, faction_action_taken, trade_route_status_changed. |
| `scripts/dialogue/context_builder.gd` | Extend `_build_world_state_section()` to include off-screen rumors, departed NPC awareness, and faction pressure summaries. |
| `scripts/npcs/base_npc.gd` | Add tier tracking, departure/return methods, archive/restore methods. |
| `scripts/resources/npc_personality.gd` | Add `goals` array, `daily_schedule`, `gossip_tendency`, `initiative_level` (as specified in AUTONOMOUS_NPC_AGENTS.md). |
| `project.godot` | Register `WorldSimulation` as autoload. |

---

## 9. Player Experience

### What Does the Player Actually See, Hear, and Discover?

The entire system is invisible to the player. They never see tier numbers, ripple intensities, or faction profiles. What they experience:

**A world that moves without them.**

- They leave Thornhaven for two game-days to explore Iron Hollow. When they return, the tavern is closed. Nobody told them it would happen. They have to piece together what happened by talking to people.

- A merchant they've never met mentions that "trade's been rough on the northern road." The player doesn't know this is because Mira left, which reduced traveler traffic, which made bandits bolder. They just know the world feels different.

- Gregor's prices went up. He doesn't explain why unless the player asks. If they do ask, he says supply chains are tight. He doesn't connect it to Mira -- or maybe he does, if his trust is high enough: "Ever since Mira left, fewer wagons come through. My suppliers charge more."

- A letter arrives from someone they befriended who left. It contains a rumor about something happening in the capital. The player can share this with local NPCs, who react to it, creating new gossip chains.

- The village feels emptier. Two Tier 1 NPCs left (low morale from the cascade). The player notices fewer faces at the market. The guard captain is more anxious. The council is more desperate.

**The player's actions create counter-ripples.**

- If the player destroys the bandit camp, a massive positive ripple propagates: trade route safety increases, merchants return, prices drop, morale rises. NPCs who left may return.

- If the player blackmails Gregor, a negative ripple of paranoia and fear spreads among those who notice Gregor's changed behavior.

- If the player does nothing, the negative ripples compound. Thornhaven slowly dies. This is an ending (the "Ashes" ending from STORY_NARRATIVE.md).

**Discovery is the reward.**

The player is never told "a ripple has propagated." They discover it:
- Through NPC dialogue (the primary channel for Tier 0/1)
- Through environmental changes (closed shops, posted notices, changed NPC locations)
- Through letters and notes (physical items from departed or off-screen NPCs)
- Through price and availability changes at shops
- Through quest state changes (a quest becomes available or fails because of off-screen events)
- Through absence itself (noticing who ISN'T there anymore)

The system's greatest trick: making the player feel that the world is vast and alive, when in reality 90% of it is running on probability tables and simple arithmetic, with Claude providing the human-feeling veneer only at the points where the player is actually looking.

---

## Appendix A: Implementation Priority

Given the existing codebase state, the recommended build order:

1. **FactionProfile + basic WorldSimulation tick** (enables Tier 3, foundation for everything else)
2. **RippleEngine with flag_change and economy_change effects** (the propagation backbone)
3. **NPC departure flow in WorldState + BaseNPC** (Mira can leave)
4. **Tier1Profile + Tier1NPC with template dialogue** (ambient village life)
5. **InfoPacket injection from ripples into Tier 0 NPCs** (off-screen events become dialogue)
6. **Tier2Profile + off-screen event tables** (the wider world exists)
7. **Tier promotion/demotion mechanics** (dynamic world)
8. **RegionMap + trade route simulation** (economic ripples)
9. **ContextBuilder extensions** (Claude knows about all of this)
10. **Environmental scene changes** (visual payoff: closed tavern, empty stalls)

This order front-loads the systems that create the most player-visible impact (faction events, departures, gossip) while deferring the more complex simulation layers.

## Appendix B: Narrative Guardrails for the Ripple System

To prevent the simulation from accidentally ruining the mystery narrative:

1. **Protected NPCs:** Tier 0 story NPCs cannot be killed or permanently removed by off-screen events or ripple effects alone. Only player actions or Claude-escalated Tier 0 decisions can cause story NPC departures/deaths.

2. **Protected Flags:** Critical story flags (gregor_exposed, bandits_destroyed, current_act) cannot be set by ripple effects. They require player action or explicit narrative triggers.

3. **Ripple Budget:** Maximum 3 active ripples per game-day originating from off-screen sources. Prevents cascade overload.

4. **Revert Mechanism:** If a ripple effect would make the main quest line uncompletable (e.g., removing all NPCs who hold critical information), the effect is blocked and logged for debugging.

5. **Player Primacy:** Ripple effects create problems and opportunities. They never solve the mystery. The player must always be the one who puts the pieces together.
