# Quest Infrastructure Design Document

## Overview

This document outlines a **Natural Language Quest System** designed for AI-driven dialogue games. Unlike traditional quest systems with scripted dialogue trees, this system **observes and reacts** to Claude's generated responses, allowing emergent storytelling while maintaining narrative structure.

---

## Design Philosophy

### Core Principle: Quests as Observers, Not Controllers

Traditional RPGs use dialogue trees:
```
Player selects "Tell me about the bandits" → triggers QUEST_BANDITS_STARTED
```

Our approach:
```
Player says anything about bandits → Claude responds naturally →
Quest system detects intent → updates quest state if conditions met
```

### Why This Matters

1. **Preserves AI authenticity** - NPCs respond naturally, not from scripts
2. **Enables emergent gameplay** - Players discover quests through genuine conversation
3. **Supports replayability** - Different conversations lead to different quest paths
4. **Reduces content brittleness** - No "magic words" required to progress

---

## Architecture

### System Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     STORY DIRECTOR                          │
│  (Orchestrates narrative arcs, manages pacing, spawns       │
│   dynamic quests based on world state)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     QUEST MANAGER                           │
│  (Tracks all active/available quests, evaluates conditions, │
│   emits quest events)                                       │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ Quest Instance│    │ Quest Instance│    │ Quest Instance│
│ (gregor_truth)│    │ (find_ledger) │    │ (help_mira)   │
└───────────────┘    └───────────────┘    └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   INTENT DETECTOR                           │
│  (Analyzes Claude responses, extracts intents, topics,      │
│   relationship implications)                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   CLAUDE RESPONSE                           │
│  (Raw AI output with metadata: interaction_type,            │
│   player_tone, emotional_state, topics_discussed)           │
└─────────────────────────────────────────────────────────────┘
```

---

## Component Specifications

### 1. Quest Resource (`QuestResource`)

Defines quest structure without prescribing dialogue.

```gdscript
class_name QuestResource
extends Resource

@export var quest_id: String
@export var title: String
@export var description: String  # For player journal

# Availability conditions (when quest can be discovered)
@export var required_flags: Array[String] = []
@export var blocked_by_flags: Array[String] = []
@export var min_relationship: Dictionary = {}  # {"npc_id": trust_level}
@export var required_memories: Array[String] = []  # Memory tags that must exist

# Discovery triggers (what makes the quest "start")
@export var discovery_intents: Array[String] = []  # ["ask_about_bandits", "mention_missing_weapons"]
@export var discovery_topics: Array[String] = []   # ["bandits", "weapons", "gregor"]
@export var discovery_npc: String = ""  # Which NPC can reveal this quest

# Objectives (observable conditions, not dialogue choices)
@export var objectives: Array[QuestObjective] = []

# Context hints (injected into NPC prompts when quest is active)
@export var npc_context_hints: Dictionary = {}  # {"gregor_001": "Player is investigating weapons"}

# Completion
@export var completion_flags: Array[String] = []  # Flags to set on completion
@export var unlocks_quests: Array[String] = []    # Quest IDs to make available
```

### 2. Quest Objective (`QuestObjective`)

```gdscript
class_name QuestObjective
extends Resource

@export var objective_id: String
@export var description: String  # "Learn about Gregor's secret dealings"

# Completion conditions (any can trigger completion)
@export var complete_on_flag: String = ""           # World flag set
@export var complete_on_intent: String = ""         # Intent detected in conversation
@export var complete_on_relationship: Dictionary = {} # {"npc_id": threshold}
@export var complete_on_memory_tag: String = ""     # NPC stores memory with this tag
@export var complete_on_location: String = ""       # Player enters area

# Optional: specific NPC must be involved
@export var requires_npc: String = ""

# Is this objective optional?
@export var optional: bool = false
```

### 3. Intent Detector

Analyzes Claude's response metadata to extract quest-relevant intents.

```gdscript
class_name IntentDetector
extends RefCounted

# Called after every NPC response
func analyze_response(response_data: Dictionary) -> Dictionary:
    var intents = {
        "topics": [],           # What was discussed
        "revelations": [],      # Secrets revealed
        "promises": [],         # Commitments made
        "requests": [],         # What NPC asked of player
        "emotional_shift": "",  # trust_gained, trust_lost, neutral
        "relationship_implication": "" # ally, enemy, neutral, romantic
    }

    # Extract from Claude's interaction_type
    match response_data.get("interaction_type", ""):
        "revelation":
            intents.revelations.append(response_data.get("topic", "unknown"))
        "quest_hint":
            intents.topics.append("quest_related")
        "confession":
            intents.revelations.append("confession")

    # Analyze topics_discussed (already in response metadata)
    intents.topics = response_data.get("topics_discussed", [])

    return intents
```

### 4. Quest Manager

Central coordinator for all quest activity.

```gdscript
class_name QuestManager
extends Node

signal quest_discovered(quest_id: String)
signal quest_objective_completed(quest_id: String, objective_id: String)
signal quest_completed(quest_id: String, outcome: String)
signal quest_failed(quest_id: String, reason: String)

var available_quests: Dictionary = {}   # quest_id -> QuestResource (can be started)
var active_quests: Dictionary = {}      # quest_id -> QuestInstance (in progress)
var completed_quests: Dictionary = {}   # quest_id -> outcome
var failed_quests: Dictionary = {}      # quest_id -> reason

var intent_detector: IntentDetector

func _ready():
    intent_detector = IntentDetector.new()
    _load_quest_definitions()
    _connect_to_game_events()

func _connect_to_game_events():
    # Listen to every NPC response
    EventBus.npc_response_generated.connect(_on_npc_response)
    EventBus.world_flag_changed.connect(_on_flag_changed)
    EventBus.npc_relationship_changed.connect(_on_relationship_changed)
    EventBus.npc_memory_stored.connect(_on_memory_stored)
    EventBus.player_entered_area.connect(_on_area_entered)

func _on_npc_response(npc_id: String, response_data: Dictionary):
    var intents = intent_detector.analyze_response(response_data)

    # Check if any available quest should be discovered
    for quest_id in available_quests:
        var quest = available_quests[quest_id]
        if _should_discover_quest(quest, npc_id, intents):
            _discover_quest(quest_id)

    # Check if any active quest objectives are completed
    for quest_id in active_quests:
        _check_objectives(quest_id, npc_id, intents)
```

### 5. Story Director

High-level narrative orchestration.

```gdscript
class_name StoryDirector
extends Node

# Story arcs with their quests
var story_arcs: Dictionary = {
    "gregor_conspiracy": {
        "quests": ["discover_ledger", "trace_weapons", "confront_gregor"],
        "required_for_ending": true
    },
    "mira_resistance": {
        "quests": ["earn_mira_trust", "meet_resistance", "choose_side"],
        "required_for_ending": false
    }
}

# Dynamic quest generation based on world state
func evaluate_narrative_opportunities():
    var world_state = WorldState.get_snapshot()

    # Example: If player has high trust with Gregor but hasn't found ledger,
    # Gregor might "accidentally" reveal information
    if world_state.get_relationship("gregor_001") > 70:
        if not world_state.get_flag(StoryFlags.LEDGER_FOUND):
            _inject_quest_opportunity("gregor_001", "hint_at_ledger")

func _inject_quest_opportunity(npc_id: String, opportunity_type: String):
    # Add temporary context to NPC's next conversation
    var npc = _get_npc(npc_id)
    if npc:
        npc.add_temporary_context(
            "You're feeling guilty about your secrets. " +
            "If the player seems trustworthy, you might let something slip."
        )
```

---

## Quest Types

### 1. Authored Quests (Hand-crafted)

Core story quests with defined structure but flexible triggers.

```gdscript
# Example: gregor_conspiracy.tres
var gregor_quest = QuestResource.new()
gregor_quest.quest_id = "gregor_conspiracy"
gregor_quest.title = "The Merchant's Secret"
gregor_quest.description = "Something isn't right about Gregor's business dealings."

gregor_quest.discovery_intents = ["ask_about_business", "mention_bandits", "question_wealth"]
gregor_quest.discovery_topics = ["bandits", "weapons", "money", "business"]
gregor_quest.discovery_npc = "gregor_001"

gregor_quest.objectives = [
    # Objective 1: Learn about weapons
    QuestObjective.new({
        "objective_id": "discover_weapons",
        "description": "Learn about the mysterious weapon shipments",
        "complete_on_flag": StoryFlags.WEAPONS_TRACED_TO_BJORN,
        "complete_on_intent": "revelation_weapons"
    }),
    # Objective 2: Find evidence
    QuestObjective.new({
        "objective_id": "find_evidence",
        "description": "Find proof of Gregor's involvement",
        "complete_on_flag": StoryFlags.LEDGER_FOUND
    }),
    # Objective 3: Confront or expose
    QuestObjective.new({
        "objective_id": "resolve",
        "description": "Decide what to do with the truth",
        "complete_on_flag": StoryFlags.GREGOR_CONFRONTED
    })
]

gregor_quest.npc_context_hints = {
    "gregor_001": "The player is suspicious of your business. Be careful what you reveal.",
    "elena_001": "Your father has been acting strange. You've noticed discrepancies.",
    "bjorn_001": "You've been filling large weapon orders but never see the buyers."
}
```

### 2. Dynamic Quests (Generated)

Created by Story Director based on game state.

```gdscript
func _generate_dynamic_quest(trigger: Dictionary) -> QuestResource:
    var quest = QuestResource.new()

    match trigger.type:
        "relationship_opportunity":
            # Player has high relationship with NPC who has secrets
            quest.quest_id = "dynamic_%s_secret" % trigger.npc_id
            quest.title = "%s's Request" % trigger.npc_name
            quest.description = "Someone trusts you enough to ask for help."
            quest.discovery_npc = trigger.npc_id
            quest.min_relationship = {trigger.npc_id: 60}

        "world_event_reaction":
            # Something happened that NPCs should react to
            quest.quest_id = "dynamic_react_%s" % trigger.event_id
            quest.title = "Aftermath"
            quest.description = "The village is buzzing about recent events."

    return quest
```

### 3. Ambient Quests (Emergent)

Not defined quests, but tracked player progress.

```gdscript
# The system recognizes patterns and creates quest-like tracking
func _detect_emergent_quest(player_actions: Array):
    # Player has talked to 3 NPCs about the same topic
    var topic_counts = {}
    for action in player_actions:
        if action.type == "conversation":
            for topic in action.topics:
                topic_counts[topic] = topic_counts.get(topic, 0) + 1

    for topic in topic_counts:
        if topic_counts[topic] >= 3:
            # Player is investigating this topic
            _create_investigation_tracker(topic)
```

---

## NPC Motivation Integration

### How NPC Personalities Drive Quests

NPCs don't exist to give quests—they have motivations that naturally create quest opportunities.

```gdscript
# In NPC personality resource
@export var core_motivation: String = "protect_daughter"
@export var secret_shame: String = "dealing_with_bandits"
@export var fear: String = "being_exposed"
@export var desire: String = "enough_gold_for_elena"

# These create natural quest hooks:
# - Player gains trust → NPC shares motivation → player wants to help
# - Player discovers shame → quest to confront or help cover up
# - Player threatens fear → NPC becomes antagonist or makes deals
```

### Context Injection Based on Quest State

```gdscript
# In context_builder.gd
func build_npc_context(npc: BaseNPC) -> String:
    var context = _build_base_context(npc)

    # Add quest-relevant hints
    var active_quests = QuestManager.get_active_quests_for_npc(npc.npc_id)
    for quest in active_quests:
        if quest.npc_context_hints.has(npc.npc_id):
            context += "\n\n[NARRATIVE CONTEXT]\n"
            context += quest.npc_context_hints[npc.npc_id]

    return context
```

---

## Testing Strategy

### Debug Console Commands

```
# Quest inspection
list_quests              - Show all quests (available/active/completed)
quest_info <quest_id>    - Detailed quest state
quest_start <quest_id>   - Force start a quest
quest_complete <quest_id> [outcome] - Force complete
quest_reset <quest_id>   - Reset quest to available

# Objective manipulation
objective_complete <quest_id> <objective_id>
objective_reset <quest_id> <objective_id>

# Intent simulation
simulate_intent <npc_id> <intent_type> [data]
# Example: simulate_intent gregor_001 revelation weapons_source

# Story Director
story_state              - Show narrative arc progress
story_inject <npc_id> <context> - Add temporary NPC context
```

### Automated Test Scenarios

```gdscript
# test_quest_discovery.gd
func test_gregor_quest_discovery():
    # Setup: Player has talked to Gregor before
    WorldState.set_relationship("gregor_001", 30)

    # Simulate conversation about bandits
    var mock_response = {
        "interaction_type": "information",
        "topics_discussed": ["bandits", "trade"],
        "player_tone": "curious"
    }

    EventBus.npc_response_generated.emit("gregor_001", mock_response)

    # Assert quest becomes active
    assert(QuestManager.is_quest_active("gregor_conspiracy"))
```

### Playtesting Checklist

- [ ] Can discover main quest through natural conversation (no magic words)
- [ ] Quest doesn't trigger if preconditions not met
- [ ] NPC context hints affect dialogue appropriately
- [ ] Objectives complete from multiple valid approaches
- [ ] Story Director creates opportunities when player is stuck
- [ ] Dynamic quests feel natural, not artificial
- [ ] Debug console can manipulate all quest states

---

## Required Game Systems

### Already Implemented

| System | Location | Status |
|--------|----------|--------|
| World Flags | `world_state.gd` | Working |
| Story Flags | `story_flags.gd` | Defined |
| Event Bus | `event_bus.gd` | Partial (needs signals) |
| NPC Relationships | `base_npc.gd` | Working |
| Memory System | `rag_memory.gd` | Working |
| Context Builder | `context_builder.gd` | Working |
| Debug Console | `debug_console.gd` | Working |

### Needs Implementation

| System | Priority | Complexity |
|--------|----------|------------|
| Quest Resource | High | Low |
| Quest Objective Resource | High | Low |
| Quest Manager | High | Medium |
| Intent Detector | High | Medium |
| Story Director | Medium | High |
| Quest Debug Commands | High | Low |
| Player Journal UI | Low | Medium |

### New EventBus Signals Needed

```gdscript
# In event_bus.gd - add these signals
signal npc_response_generated(npc_id: String, response_data: Dictionary)
signal world_flag_changed(flag_name: String, old_value, new_value)
signal player_entered_area(area_id: String)
signal quest_discovered(quest_id: String)
signal quest_objective_completed(quest_id: String, objective_id: String)
signal quest_completed(quest_id: String, outcome: String)
```

---

## Implementation Phases

### Phase 1: Foundation (Current Priority)
1. Create `QuestResource` and `QuestObjective` resources
2. Create `QuestManager` with basic state tracking
3. Add quest debug commands to console
4. Add missing EventBus signals

### Phase 2: Detection
1. Create `IntentDetector` class
2. Connect to NPC response flow
3. Implement quest discovery logic
4. Implement objective completion detection

### Phase 3: Integration
1. Modify `context_builder.gd` to inject quest hints
2. Create authored quest definitions for main story
3. Test with debug console manipulation

### Phase 4: Story Director
1. Implement `StoryDirector` for narrative pacing
2. Add dynamic quest generation
3. Create opportunity injection system

### Phase 5: Polish
1. Player journal UI
2. Quest notification system
3. Save/load quest state

---

## Example: Complete Quest Flow

### "The Merchant's Secret" Quest

**Discovery:**
```
Player: "Gregor, I've noticed a lot of weapons passing through lately."
Claude (as Gregor): "Ah, yes, well, trade has been... good. Nothing unusual."
                   (interaction_type: "deflection", topics: ["weapons", "trade"])

Intent Detector: Topics include "weapons" + Gregor is discovery_npc
Quest Manager: Preconditions met (none required), discovering quest
→ Quest "gregor_conspiracy" becomes ACTIVE
```

**Objective 1 Progress:**
```
Player talks to Bjorn about weapons
Claude (as Bjorn): "Strange orders lately. Large quantities, always cash,
                   never see who picks them up."
                   (interaction_type: "information", topics: ["weapons", "mystery"])

Quest Manager: Checks if this completes any objectives
→ Not yet - need flag WEAPONS_TRACED_TO_BJORN

Player: "Do the orders come from anyone in town?"
Claude (as Bjorn): "Now that you mention it... Gregor's been the middleman."
                   (interaction_type: "revelation", revelation_type: "connection")

→ World flag WEAPONS_TRACED_TO_BJORN set
→ Objective "discover_weapons" COMPLETE
```

**Context Injection:**
```
Next conversation with Elena, context includes:
"Your father has been acting strange. You've noticed discrepancies."

Claude (as Elena, unprompted): "Have you noticed my father seems worried lately?
                                He's been working late, counting things..."
```

**Completion:**
```
Player confronts Gregor with evidence
Claude (as Gregor): "I... I had no choice. It was for Elena. All of it."
                    (interaction_type: "confession", topics: ["guilt", "elena"])

→ World flag GREGOR_CONFRONTED set
→ Objective "resolve" COMPLETE
→ Quest "gregor_conspiracy" COMPLETE (outcome: "confronted")
```

---

## Open Questions

1. **Should failed quests be recoverable?**
   - Proposed: Yes, but with consequences (changed NPC attitudes, new obstacles)

2. **How much should quests affect NPC memory?**
   - Proposed: Quest events become pinned memories, ensuring consistency

3. **Can players complete quests in unintended ways?**
   - Proposed: Yes, embrace emergent solutions. Define multiple valid completion states.

4. **How visible should quest tracking be?**
   - Proposed: Minimal UI. Player journal shows "things you've learned" not "objectives"

---

## Next Steps

1. Review this document with stakeholders
2. Finalize Phase 1 implementation scope
3. Create quest definition template
4. Implement basic QuestManager
5. Add debug commands for testing
