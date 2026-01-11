# Land - Project Overview

> **An AI-Driven Open-World JRPG with Persistent NPC Memory**
>
> **Engine:** Godot 4.5 | **AI:** Claude Sonnet 4.5 | **Memory:** ChromaDB
>
> **Last Updated:** December 2024

---

## Table of Contents

1. [Vision & Goals](#vision--goals)
2. [Core Features](#core-features)
3. [Technical Architecture](#technical-architecture)
4. [Implementation Details](#implementation-details)
5. [Challenges & Solutions](#challenges--solutions)
6. [Architectural Decisions](#architectural-decisions)
7. [Current State](#current-state)
8. [Future Roadmap](#future-roadmap)

---

## Vision & Goals

### Project Vision

Create an RPG where every NPC is a unique AI agent with persistent memory, evolving relationships, and authentic personality. Players don't follow scripted dialogue trees - they have genuine conversations that shape relationships and unlock story paths organically.

### Design Pillars

| Pillar | Description |
|--------|-------------|
| **Authentic NPCs** | Each character has distinct personality, secrets, fears, and goals |
| **Persistent Memory** | NPCs remember past interactions and reference them naturally |
| **Consequence-Driven** | Player choices propagate through the world and affect NPC relationships |
| **Emergent Story** | Narrative unfolds through relationship building, not quest markers |
| **Dynamic Generation** | Pixel art assets generated via AI to match the world's aesthetic |

### Core Narrative

The village of Thornhaven harbors dark secrets. The player must navigate complex relationships to uncover:
- Who is the village informant working with bandits?
- What happened to Mira's husband Marcus?
- Why does Gregor save gold for his daughter Elena to escape?
- What is the true identity of "The Boss" of Iron Hollow?

---

## Core Features

### 1. AI-Driven NPC System

Every NPC runs an individual Claude AI agent with:

| Component | Purpose |
|-----------|---------|
| **NPCPersonality Resource** | Immutable character traits, secrets, speech patterns |
| **5D Relationship System** | Trust, Respect, Affection, Fear, Familiarity |
| **RAG Memory** | Semantic recall of past interactions via ChromaDB |
| **Secret Unlocking** | Information revealed at relationship thresholds |
| **Cross-NPC Awareness** | NPCs know about each other and share world knowledge |

**Implemented NPCs (7):**
- Gregor (merchant, informant)
- Elena (Gregor's daughter, romance option)
- Mira (tavern keeper, secret: "The Boss")
- Bjorn (blacksmith, unwitting accomplice)
- Aldric (peacekeeper captain)
- Mathias (village elder)
- Varn (bandit lieutenant)

### 2. Memory & Continuity

NPCs remember everything through a tiered memory system backed by ChromaDB vector database.

---

## Memory Architecture (Detailed)

> **Status:** Current implementation documented below, with planned improvements noted.

### Storage Layer

```
┌─────────────────────────────────────────────────────────────────┐
│                      DUAL-MODE STORAGE                           │
├────────────────────────────┬────────────────────────────────────┤
│     ChromaDB (Primary)     │     In-Memory (Fallback)           │
│  • Vector DB via Python CLI│  • Array-based storage             │
│  • Semantic embeddings     │  • Keyword matching                │
│  • Persistent across runs  │  • Lost on session end             │
│  • Collection per NPC      │  • For testing/offline             │
└────────────────────────────┴────────────────────────────────────┘
```

**Key Files:**
- `scripts/npcs/rag_memory.gd` - High-level memory API
- `scripts/memory/chroma_client.gd` - ChromaDB CLI wrapper
- `scripts/resources/memory_config.gd` - Data-driven configuration
- `chroma_cli.py` - Python CLI for ChromaDB operations

### Memory Data Structure

```gdscript
# Each memory stored with:
{
  "id": "npc_aldric_1702500000_conversation",
  "document": "The player told me their name is Theron.",  # NPC's perspective
  "metadata": {
    "event_type": "player_info",       # Category
    "importance": 10,                   # 1-10 scale
    "timestamp": 1702500000,            # Unix time
    "npc_id": "aldric_blacksmith",
    "memory_tier": 0,                   # 0=PINNED, 1=IMPORTANT, 2=REGULAR
    "is_milestone": true,
    "milestone_type": "first_meeting",
    "emotion": "curious",
    "info_type": "player_name"          # For deduplication
  }
}
```

### Current Tiered Retrieval System

```
┌─────────────────────────────────────────────────────────────────┐
│                    RETRIEVAL PIPELINE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Step 1: PINNED MEMORIES (max 5)                                │
│  ├─ Query: metadata_filter = {memory_tier: 0}                   │
│  ├─ Sort by: importance DESC                                    │
│  └─ Always included regardless of context                       │
│                      ↓                                          │
│  Step 2: IMPORTANT MEMORIES (max 3)                             │
│  ├─ Query: metadata_filter = {memory_tier: 1}                   │
│  ├─ Sort by: importance DESC                                    │
│  └─ High priority, not semantic                                 │
│                      ↓                                          │
│  Step 3: RELEVANT MEMORIES (max 5)                              │
│  ├─ Query: semantic similarity to current input                 │
│  ├─ Filter: exclude already-included IDs                        │
│  ├─ Filter: importance >= 4                                     │
│  └─ ChromaDB embedding-based search                             │
│                      ↓                                          │
│  Step 4: BUDGET ENFORCEMENT                                     │
│  ├─ Total character limit: 3000                                 │
│  └─ Truncate individual memories if exceeding                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Tier Classification Logic

```
_detect_memory_tier(event_type, importance, memory_data):

    Priority 1: Explicit milestone marker → PINNED
    Priority 2: Claude interaction_type in pinned list → PINNED
    Priority 3: Event type in pinned_event_types → PINNED
    Priority 4: Claude interaction_type in important list → IMPORTANT
    Priority 5: Event type in important_event_types → IMPORTANT
    Priority 6: Importance score >= 8 → IMPORTANT
    Priority 7: Default → REGULAR
```

**Pinned Event Types:** `betrayal`, `saved_life`, `romance_confession`, `witnessed_kill`, `secret_revealed`, `first_meeting`, `first_gift`, `first_quest`

**Important Event Types:** `quest_completed`, `quest_failed`, `gift_received`, `emotional_support`, `romantic_gesture`

### Current Budgets

| Parameter | Value | Location |
|-----------|-------|----------|
| `max_memory_chars` | 10,000 | memory_config.gd:13 |
| `max_pinned_memories` | 8 | memory_config.gd:15 |
| `max_important_memories` | 5 | memory_config.gd:17 |
| `max_regular_memories` | 8 | memory_config.gd:19 |
| `importance_threshold` | 8 | memory_config.gd:73 |

**Token Budget Rationale:**

> **Important:** Character count is a conservative guardrail, not the main allocator. Actual tokenization varies significantly based on content.

- 10,000 chars ≈ 2,500-3,300 tokens depending on content
- Memory blocks include timestamps, IDs, and tags that increase token density
- Pure prose: ~4 chars/token; structured data: ~3 chars/token
- Leaves ~5,000+ tokens for: personality (~500), system prompt (~1,000), conversation history (~3,000), response (~1,000)
- Total context per request: ~8,000-10,000 tokens (well within Claude's limits)

```gdscript
# Token estimation should use actual string, not char count
func estimate_tokens(text: String) -> int:
    # Conservative: assume 3 chars/token for structured memory content
    # This overestimates slightly, which is safer than underestimating
    return ceili(text.length() / 3.0)

# Character limit as backup guardrail, not primary allocator
func enforce_budget(memories: Array, char_limit: int) -> Array:
    var result = []
    var total_chars = 0
    for mem in memories:
        var text = mem.get("text", "")
        if total_chars + text.length() <= char_limit:
            result.append(mem)
            total_chars += text.length()
    return result
```

### Importance Scoring (Current)

| Source | Importance | Notes |
|--------|------------|-------|
| `store_milestone()` | 10 | Always maximum |
| `store_player_action()` | 8 | Player did something |
| `store_quest_memory()` | 8 | Quest events |
| `store_witnessed_event()` | 7 | Observed events |
| `store_conversation()` | 6 | Normal dialogue |
| Default | 5 | Unspecified |

**Issue:** Importance is static per event type. Claude's `emotional_impact` analysis is not used to adjust importance.

### Memory Features

- **NPC Perspective:** Stored as "The player told me..." not "Player said..."
- **Deduplication:** `player_info` with same `info_type` updates rather than duplicates
- **Validation:** WorldEvents checks for hallucinated NPC names before storage
- **Milestones:** Auto-detected from event type or explicit `is_milestone` flag

---

## Known Issues (Current Implementation)

| Issue | Severity | Description |
|-------|----------|-------------|
| **Context Drift at Scale** | High | "Always inject" semantics guarantee crowding as corpus grows; pinned tier becomes permanent tax on context budget |
| **Truncation not semantic-aware** | High | Budget enforcement truncates mid-sentence; no short/full dual representation |
| **Schema drift in Claude types** | Medium | Claude's `interaction_type` is free-form; may not match enumerated types, causing silent tier detection failures |
| **Importance not deterministic** | Medium | Relies on static event types or subjective `emotional_impact`; should use concrete state changes |
| **No conflict resolution** | Medium | Contradictory memories (promise made vs broken) have no supersession policy |
| **Dummy semantic query** | Medium | Tier queries use `"relationship milestone important"` as query text - irrelevant since filtering by metadata |
| **Milestone/Pinned conflation** | Low | All milestones auto-pin; concepts are redundant |
| **Consolidation unimplemented** | Medium | ChromaDB consolidation not working; memory bloat possible |
| **Blocking CLI calls** | High | Each ChromaDB query spawns Python process (100-300ms) |
| **No recency decay** | Low | Old memories have same weight as new ones |

### The Drift Problem (Detailed)

```
Current Tier Semantics (Problematic at Scale):
┌──────────────┬─────────────────────────────────────────────────────┐
│   Tier       │   Actual Behavior                                   │
├──────────────┼─────────────────────────────────────────────────────┤
│ PINNED       │ "Always inject" → permanent context tax             │
│ MILESTONE    │ "Always pin" → accelerates crowding                 │
│ IMPORTANT    │ "Always inject until caps" → caps hit early         │
└──────────────┴─────────────────────────────────────────────────────┘

After N hours of play:
├─ 5+ first_meetings, gifts, quests → pinned full
├─ 8+ emotional moments → important full
├─ Semantic slot (5) is all that flexes
└─ 3000 chars permanently consumed by stale memories
```

**Core insight:** Tiers work as *classification* but fail as *allocation strategy*. A betrayal from 10 hours ago shouldn't have equal weight to a betrayal from 10 minutes ago.

---

## Planned Architecture: Score-Based Selection

> **Design Principle:** Tier = Classification signal, NOT allocation guarantee

### New Retrieval Model

```
┌─────────────────────────────────────────────────────────────────┐
│         SCORE-BASED SELECTION (Replaces Tier Caps)             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  TIER = Classification signal, NOT allocation guarantee         │
│  ├─ PINNED: High base score, but still competes                │
│  ├─ IMPORTANT: Medium base score                                │
│  └─ REGULAR: Low base score, boosted by relevance               │
│                                                                  │
│  SCORE = tier_weight × importance × recency × relevance         │
│                                                                  │
│  BUDGET = Hard constraint, not tier caps                        │
│  ├─ Fill by score until budget exhausted                        │
│  └─ Old pinned memories CAN be displaced by new important ones  │
│                                                                  │
│  PROTECTED = Tiny set immune to displacement                    │
│  └─ Only: first_meeting, player_name, npc_death (~2-3 max)     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Scoring Formula

```gdscript
func calculate_memory_score(memory: Dictionary, query_context: String) -> float:
    var meta = memory.get("metadata", {})

    # Base weight from tier (signal, not guarantee)
    var tier = meta.get("memory_tier", 2)
    var tier_weight = [3.0, 2.0, 1.0][tier]  # PINNED=3x, IMPORTANT=2x, REGULAR=1x

    # Importance (1-10 normalized)
    var importance = meta.get("importance", 5) / 10.0

    # Recency decay: half-life of 7 days
    var age_seconds = Time.get_unix_time_from_system() - meta.get("timestamp", 0)
    var age_days = age_seconds / 86400.0
    var recency = exp(-age_days * 0.693 / 7.0)  # 0.693 = ln(2)

    # Semantic relevance (0-1, from ChromaDB distance)
    # TUNED: Wider range (0.3-1.0) gives relevance more influence over tier
    var relevance = memory.get("similarity", 0.5)

    # Final score: tier provides advantage, but recency and relevance matter
    # TUNED: (0.3 + 0.7 * relevance) gives ~3.3x swing instead of 2x
    # This allows highly relevant REGULAR memories to compete with stale PINNED
    return tier_weight * importance * (0.3 + 0.7 * recency) * (0.3 + 0.7 * relevance)
```

### Score Component Weights

| Component | Range | Swing | Rationale |
|-----------|-------|-------|-----------|
| `tier_weight` | 1.0-3.0 | 3x | Pinned gets 3x advantage, not guarantee |
| `importance` | 0.1-1.0 | 10x | Normalized from 1-10 scale |
| `recency` | 0.3-1.0 | 3.3x | Floor of 0.3 prevents total decay; 7-day half-life |
| `relevance` | 0.3-1.0 | 3.3x | **Tuned up from 0.5-1.0** to let current topics compete |

**Score Behavior Analysis:**
- Old PINNED (tier=3, importance=10, age=10d, relevance=0.3): `3.0 × 1.0 × 0.37 × 0.51 = 0.57`
- New REGULAR (tier=1, importance=5, age=0d, relevance=0.9): `1.0 × 0.5 × 1.0 × 0.93 = 0.47`
- New REGULAR with high relevance can now nearly match old PINNED
- System prioritizes "what is being talked about now" more than before

### Protected Memories (Immune to Displacement)

Protected memories are compact **relationship state headers**, not narrative memories:

```gdscript
# Protected = compact state blob, not narrative
# Instead of protecting the first_meeting narrative:
#   "We met three days ago at the market when you helped me carry grain..."
# Protect a relationship header:
#   "[Met=yes, Days_known=3, Trust=45, Affection=20, Status=friendly_acquaintance]"

const PROTECTED_SLOT_TYPES = [
    "relationship_header",  # Compact state summary
    "player_name",          # What to call them
    "npc_death_status"      # Whether key NPCs are alive/dead
]

func get_relationship_header(npc_id: String) -> String:
    var rel = get_relationship_state(npc_id)
    return "[Met=%s, Days_known=%d, Trust=%d, Affection=%d, Fear=%d, Status=%s]" % [
        "yes" if rel.has_met else "no",
        rel.days_since_first_meeting,
        rel.trust,
        rel.affection,
        rel.fear,
        rel.get_status_label()  # "stranger", "acquaintance", "friend", "rival", etc.
    ]

func is_protected(memory: Dictionary) -> bool:
    var slot_type = memory.get("metadata", {}).get("slot_type", "")
    return slot_type in PROTECTED_SLOT_TYPES
```

**Why Headers, Not Narratives:**
- Smaller token footprint (~50 chars vs ~200 chars)
- Semantically stable (same format every turn)
- Contains what Claude actually needs for coherence
- The `first_meeting` narrative remains in the scored pool and surfaces when relevant

**Limit:** 2-3 slot-based entries per NPC maximum.

### Selection Algorithm

```
┌─────────────────────────────────────────────────────────────────┐
│                    SELECTION PIPELINE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. BOUNDED CANDIDATE COLLECTION (not "get all")                │
│     ├─ Protected: Direct fetch by slot_type (2-3 max)          │
│     ├─ High-signal recent: Fetch by event_type + recency        │
│     │   (secrets, betrayals, obligations from last 7 days)      │
│     └─ Semantic: Top-K similarity search (K=15)                 │
│                                                                  │
│  2. DEDUPLICATE                                                  │
│     └─ Merge overlapping results from the three sources         │
│                                                                  │
│  3. SCORE CANDIDATES (non-protected only)                       │
│     └─ Apply: tier_weight × importance × recency × relevance    │
│                                                                  │
│  4. SORT BY SCORE (descending)                                  │
│                                                                  │
│  5. FILL TOKEN BUDGET                                           │
│     budget = MAX_TOKENS - protected_tokens - system_overhead    │
│     for memory in sorted_candidates:                            │
│         if memory.tokens <= remaining_budget:                   │
│             include(memory)                                     │
│             remaining_budget -= memory.tokens                   │
│                                                                  │
│  6. OUTPUT: Protected + top-scored within budget                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Why Bounded Collection Matters:**
- "Get all" becomes expensive at 100+ memories per NPC
- Latency pressure leads to over-injection "just in case"
- Bounded fetch ensures optimizer sees high-value candidates without full scan
- Three sources provide good recall: protected (identity), high-signal (recent important events), semantic (contextually relevant)

### Comparison: Current vs. Planned

| Aspect | Current (Tier Caps) | Planned (Score-Based) |
|--------|---------------------|----------------------|
| Pinned allocation | Always inject (5 max) | Compete with 3x score advantage |
| Old milestones | Permanent residents | Can be displaced by newer high-score |
| Recency | None | Exponential decay (7-day half-life) |
| Relevance | Only REGULAR tier | All memories boosted by relevance |
| Budget | Character caps per tier | Single token budget, fill by score |
| Protected set | Entire pinned tier (5) | Tiny set (~2-3 max) |
| Scale behavior | Crowds at corpus growth | Resilient as corpus grows |

### Dual Representation Storage

Each memory stores both a compact summary and full narrative:

```gdscript
{
  "id": "npc_elena_1702500000_saved_life",
  "document_short": "Player saved me from bandits at Old Mill. I owe them my life.",
  "document_full": "When three bandits cornered me behind the Old Mill, the player
                    intervened despite being outnumbered. I was injured in the
                    fight but survived. I feel overwhelming gratitude and told
                    them I owe them a life debt. This changes everything.",
  "metadata": { ... }
}
```

**Benefits:**
- Short form (~50-80 chars) used for budget-constrained context injection
- Full form (~200-400 chars) preserved for consolidation and deep-context scenarios
- No semantic loss from mid-sentence truncation
- Selection algorithm uses short form for token estimation

**Selection with Dual Forms:**
```gdscript
const HIGH_RELEVANCE_THRESHOLD = 0.85  # Use full form only for highly relevant memories

func fill_budget(memories: Array, budget: int) -> Array:
    var result = []
    var remaining = budget

    for mem in memories:
        # Use short form by default for stability
        var text = mem.get("document_short", mem.get("document", ""))
        var tokens = estimate_tokens(text)

        # Use full form ONLY when memory is primary topic (high relevance)
        # This prevents non-deterministic tone shifts based on budget fluctuations
        var relevance = mem.get("similarity", 0.0)
        if relevance >= HIGH_RELEVANCE_THRESHOLD:
            var full_text = mem.get("document_full", text)
            if estimate_tokens(full_text) <= remaining:
                text = full_text
                tokens = estimate_tokens(full_text)

        if tokens <= remaining:
            result.append({"memory": mem, "text": text})
            remaining -= tokens

    return result
```

**Why Relevance-Based, Not Budget-Based:**
- Budget-based ("use full if > 50% remaining") causes non-determinism
- Same memory appears in different detail levels on different turns
- NPC tone shifts unexpectedly when budget happens to be large
- Relevance-based ensures full form only when memory is the conversation topic

### Schema Constraints for Claude Interaction Types

**Problem:** Claude returns free-form `interaction_type` strings that may not match our enumerated types, causing silent tier detection failures.

**Solution:** Constrain Claude's response to a fixed schema via prompt engineering:

```
When analyzing the interaction, classify it as ONE of these exact types:
- "casual_conversation" - Normal friendly chat
- "quest_related" - Discussing quests or objectives
- "gift_given" - Player gave something to NPC
- "emotional_support" - Player provided comfort or help
- "romantic_gesture" - Flirting, compliments, romantic interest
- "threat_made" - Hostility or intimidation
- "secret_shared" - Revealing private information
- "betrayal" - Breaking trust or promise
- "life_saved" - Rescue from danger
- "romance_confession" - Declaration of romantic feelings

Do NOT invent new types. Use "casual_conversation" if unsure.
```

**Validation Layer:**
```gdscript
const VALID_INTERACTION_TYPES = [
    "casual_conversation", "quest_related", "gift_given",
    "emotional_support", "romantic_gesture", "threat_made",
    "secret_shared", "betrayal", "life_saved", "romance_confession"
]

func validate_interaction_type(claude_type: String) -> String:
    if claude_type in VALID_INTERACTION_TYPES:
        return claude_type

    # Log invalid values - don't silently remap in production
    push_warning("[Memory] Invalid interaction_type from Claude: '%s', defaulting to casual_conversation" % claude_type)

    # Fuzzy matching ONLY in debug builds - helps during development
    # In production, invalid types should be logged and investigated
    if OS.is_debug_build():
        for valid in VALID_INTERACTION_TYPES:
            if claude_type.similarity(valid) > 0.8:
                push_warning("[Memory]   (Would have mapped to: %s)" % valid)

    return "casual_conversation"  # Safe default
```

**Why Debug-Only Fuzzy Matching:**
- Similarity-based mapping can map wrong labels in edge cases
- Silent remapping hides prompt drift that should be fixed
- Logging invalid values helps identify when Claude's prompt needs adjustment
- Debug mode shows potential mappings for development convenience

### Concrete State-Based Importance

**Current Problem:** Importance derives from static event types or subjective `emotional_impact`.

**Solution:** Drive importance from observable, deterministic state changes:

| Signal | Importance Boost | Rationale |
|--------|------------------|-----------|
| Relationship delta ≥ 15 | +2 | Major shift in disposition |
| New secret revealed | +3 | Permanent knowledge asymmetry |
| Obligation created | +2 | Future behavior constraint ("I owe you") |
| Quest state change | +2 | Story progression marker |
| NPC injury/death | +4 | Irreversible world state |
| Player name learned | +2 | Identity information |
| Promise made/broken | +2 | Trust-affecting commitment |

```gdscript
func calculate_importance(event_type: String, claude_analysis: Dictionary, state_deltas: Dictionary) -> int:
    var base = EVENT_TYPE_IMPORTANCE.get(event_type, 5)
    var boost = 0

    # Relationship magnitude (concrete, measurable)
    var rel_delta = abs(state_deltas.get("trust_change", 0)) + \
                    abs(state_deltas.get("affection_change", 0)) + \
                    abs(state_deltas.get("fear_change", 0))
    if rel_delta >= 15:
        boost += 2

    # New information (concrete, verifiable)
    if state_deltas.get("secret_revealed", false):
        boost += 3
    if state_deltas.get("player_name_learned", false):
        boost += 2

    # Obligations (concrete, trackable)
    if state_deltas.get("obligation_created", false):
        boost += 2
    if state_deltas.get("promise_made", false) or state_deltas.get("promise_broken", false):
        boost += 2

    # Quest progression (concrete, system-tracked)
    if state_deltas.get("quest_started", false) or state_deltas.get("quest_completed", false):
        boost += 2

    # Irreversible events
    if state_deltas.get("npc_injured", false):
        boost += 3
    if state_deltas.get("npc_died", false):
        boost += 4

    return clamp(base + boost, 1, 10)
```

**Delta Clamping (Critical):**

If Claude can output unclamped relationship deltas, importance saturates and everything gets pinned:

```gdscript
# Hard clamps on Claude-proposed deltas - REQUIRED
const MAX_TRUST_CHANGE = 15
const MAX_AFFECTION_CHANGE = 10
const MAX_FEAR_CHANGE = 10
const MAX_RESPECT_CHANGE = 10

func clamp_claude_deltas(analysis: Dictionary) -> Dictionary:
    return {
        "trust_change": clamp(analysis.get("trust_change", 0), -MAX_TRUST_CHANGE, MAX_TRUST_CHANGE),
        "affection_change": clamp(analysis.get("affection_change", 0), -MAX_AFFECTION_CHANGE, MAX_AFFECTION_CHANGE),
        "fear_change": clamp(analysis.get("fear_change", 0), -MAX_FEAR_CHANGE, MAX_FEAR_CHANGE),
        "respect_change": clamp(analysis.get("respect_change", 0), -MAX_RESPECT_CHANGE, MAX_RESPECT_CHANGE)
    }

# Better approach: derive deltas from event_type rules, use Claude only for qualitative tags
func get_deterministic_deltas(event_type: String, context: Dictionary) -> Dictionary:
    match event_type:
        "gift_given":
            return {"affection_change": 5, "trust_change": 2}
        "betrayal":
            return {"trust_change": -15, "affection_change": -10}
        "life_saved":
            return {"trust_change": 15, "affection_change": 10, "fear_change": -5}
        _:
            return {}  # No automatic deltas for unrecognized types
```

### Conflict Resolution Policy

**Problem:** Memories can contradict (e.g., "player promised to help" vs "player refused to help").

**Two Distinct Mechanisms:**

| Mechanism | Use Case | Example |
|-----------|----------|---------|
| **Slot Update** | Identity facts with single current value | player_name, allegiance, NPC beliefs |
| **Supersession Chain** | Narrative state transitions | promise_made → promise_broken |

```gdscript
# SLOT-BASED FACTS: Only one active value per slot (like player_info dedup)
const SLOT_TYPES = [
    "player_name",           # Only one name at a time
    "player_allegiance",     # Current faction loyalty
    "npc_belief_about_player", # What NPC thinks player is (hero, villain, stranger)
    "current_quest_for_npc"  # Active quest with this NPC
]

func store_slot_update(slot_type: String, new_value: Dictionary) -> void:
    # Slot updates replace old value entirely
    var existing = query_by_slot_type(slot_type)
    if existing:
        delete_memory(existing.id)
    store(new_value)

# SUPERSESSION CHAINS: Narrative transitions that preserve history
const SUPERSESSION_PAIRS = {
    "promise_made": "promise_broken",
    "trust_gained": "trust_lost",
    "alliance_formed": "alliance_broken",
    "secret_kept": "secret_revealed"
}

func store_with_conflict_check(new_memory: Dictionary) -> void:
    var event_type = new_memory.get("event_type", "")
    var slot_type = new_memory.get("metadata", {}).get("slot_type", "")

    # Handle slot-based updates (complete replacement)
    if slot_type in SLOT_TYPES:
        store_slot_update(slot_type, new_memory)
        return

    # Handle supersession chains (preserve history with penalty)
    if event_type in SUPERSESSION_PAIRS.values():
        var opposite = SUPERSESSION_PAIRS.find_key(event_type)
        var old_memories = query_by_event_type(opposite)
        for old in old_memories:
            old.metadata["superseded_by"] = new_memory.id
            old.metadata["superseded_at"] = Time.get_unix_time_from_system()
            update_memory(old)

    store(new_memory)

# Superseded memories get score penalty
func calculate_memory_score(memory: Dictionary, query_context: String) -> float:
    var base_score = _calculate_base_score(memory, query_context)

    if memory.get("metadata", {}).get("superseded_by", "") != "":
        return base_score * 0.1  # 90% penalty, but not deleted

    return base_score
```

**Slot Update vs Supersession:**
| Aspect | Slot Update | Supersession |
|--------|-------------|--------------|
| Old value | Deleted | Preserved with 0.1x score |
| History | Lost | Retained for consolidation |
| Use when | Only current value matters | History matters ("promised then broke") |

---

## Implementation Phases

### Phase 1: Score-Based Selection

Replace `retrieve_tiered()` with `retrieve_scored()`:

```gdscript
func retrieve_scored(context: String, token_budget: int) -> Array:
    # 1. Get all memories with similarity scores
    var all_memories = await get_all_with_similarity(context)

    # 2. Partition protected vs candidates
    var protected = all_memories.filter(func(m): return is_protected(m))
    var candidates = all_memories.filter(func(m): return not is_protected(m))

    # 3. Score and sort candidates
    for mem in candidates:
        mem.score = calculate_memory_score(mem, context)
    candidates.sort_custom(func(a, b): return a.score > b.score)

    # 4. Fill budget
    var result = protected.duplicate()
    var remaining = token_budget - estimate_tokens(protected)

    for mem in candidates:
        var tokens = estimate_tokens([mem])
        if tokens <= remaining:
            result.append(mem)
            remaining -= tokens

    return result
```

### Phase 2: Dual Representation + Schema Constraints

Implement dual-form storage and Claude schema validation:

```gdscript
# At memory creation time, generate both forms
func create_memory(event: Dictionary, claude_response: Dictionary) -> Dictionary:
    var full_text = format_memory_full(event, claude_response)
    var short_text = summarize_to_short(full_text)  # ~60-80 chars

    return {
        "document_short": short_text,
        "document_full": full_text,
        "metadata": {
            "interaction_type": validate_interaction_type(
                claude_response.get("analysis", {}).get("interaction_type", "")
            ),
            # ... other metadata
        }
    }
```

### Phase 3: Concrete State-Based Importance

Replace subjective emotional analysis with observable state changes.

See "Concrete State-Based Importance" section above for full implementation.

Key changes:
- Track `state_deltas` dictionary through interaction pipeline
- Importance driven by relationship magnitude, secrets, obligations, quest state
- Remove dependency on Claude's `emotional_impact` field

### Phase 4: Volume-Based Consolidation

Trigger consolidation on memory count, not age:

```gdscript
const MAX_MEMORIES_BEFORE_CONSOLIDATE = 50
const CONSOLIDATE_TARGET = 20

func check_consolidation_needed() -> bool:
    return get_memory_count() > MAX_MEMORIES_BEFORE_CONSOLIDATE

func consolidate():
    # Get lowest-scored non-protected memories
    var to_consolidate = get_lowest_scored(MAX_MEMORIES_BEFORE_CONSOLIDATE - CONSOLIDATE_TARGET)

    # Group by timeframe (same day) and topic
    var groups = group_by_timeframe_and_topic(to_consolidate)

    # Summarize each group into single memory
    for group in groups:
        var summary = summarize_memories(group)
        store(summary, importance=6, tier=IMPORTANT)
        delete_memories(group)
```

### Phase 5: Connection Pooling

Reduce ChromaDB latency with persistent connection:

```
Current:  Godot → spawn Python → ChromaDB → exit → parse (100-300ms)
Planned:  Godot → HTTP to persistent server → ChromaDB (10-50ms)
```

---

## Configuration (Planned)

```gdscript
# memory_config.gd additions

@export_group("Score-Based Selection")
@export var tier_weights: Array[float] = [3.0, 2.0, 1.0]  # PINNED, IMPORTANT, REGULAR
@export var recency_half_life_days: float = 7.0
@export var recency_floor: float = 0.3  # Never fully decay
@export var relevance_floor: float = 0.3  # TUNED: wider swing (was 0.5)
@export var high_relevance_threshold: float = 0.85  # Use full form above this

@export_group("Protected Memories")
## Protected = compact state headers, not narrative memories
@export var protected_slot_types: Array[String] = ["relationship_header", "player_name", "npc_death_status"]

@export_group("Bounded Collection")
@export var high_signal_recency_days: int = 7  # Fetch high-signal events from last N days
@export var semantic_top_k: int = 15  # Top-K for semantic search

@export_group("Consolidation")
@export var max_memories_before_consolidate: int = 50
@export var consolidate_target: int = 20

@export_group("Schema Constraints")
## Valid interaction types Claude can return - used for validation
@export var valid_interaction_types: Array[String] = [
    "casual_conversation", "quest_related", "gift_given",
    "emotional_support", "romantic_gesture", "threat_made",
    "secret_shared", "betrayal", "life_saved", "romance_confession"
]
## Similarity threshold for fuzzy matching invalid types
@export var interaction_type_similarity_threshold: float = 0.8

@export_group("Importance Signals")
## Relationship delta threshold for importance boost
@export var relationship_delta_threshold: int = 15
## Importance boost values for concrete state changes
@export var importance_boost_secret: int = 3
@export var importance_boost_relationship: int = 2
@export var importance_boost_obligation: int = 2
@export var importance_boost_quest: int = 2
@export var importance_boost_injury: int = 3
@export var importance_boost_death: int = 4

@export_group("Conflict Resolution")
## Score multiplier for superseded memories (0.1 = 90% penalty)
@export var superseded_score_multiplier: float = 0.1
## Slot types that get replaced entirely (no history kept)
@export var slot_types: Array[String] = [
    "player_name", "player_allegiance", "npc_belief_about_player", "current_quest_for_npc"
]
## Supersession pairs: key = original state, value = superseding state (history kept)
@export var supersession_pairs: Dictionary = {
    "promise_made": "promise_broken",
    "trust_gained": "trust_lost",
    "alliance_formed": "alliance_broken",
    "secret_kept": "secret_revealed"
}

@export_group("Delta Clamping")
## Maximum relationship delta Claude can propose per interaction
@export var max_trust_change: int = 15
@export var max_affection_change: int = 10
@export var max_fear_change: int = 10
@export var max_respect_change: int = 10
```

---

## Memory Flow Diagram

```
Player Input
    ↓
[respond_to_player]
    ├─ retrieve_tiered(input_text)
    │   ├─ Get pinned (metadata filter)
    │   ├─ Get important (metadata filter)
    │   └─ Get relevant (semantic search)
    ↓
[context_builder.build_context]
    ├─ Format tiered memories
    ├─ Add to system prompt
    └─ Include conversation history
    ↓
[claude_client.send_message]
    ↓
[Parse Response]
    ├─ Extract dialogue
    ├─ Extract analysis
    └─ Extract learned_about_player
    ↓
[record_interaction]
    ├─ Calculate importance (TODO: use analysis)
    ├─ Detect tier
    ├─ Detect milestone
    ├─ Validate against WorldEvents
    └─ Store to ChromaDB
    ↓
Response to Player
```

### 3. Dialogue Generation

Real-time dialogue via Claude API with structured analysis:

```json
{
  "response": "[warmly] It's good to see you again, friend.",
  "analysis": {
    "player_tone": "friendly",
    "emotional_impact": "positive",
    "trust_change": 2,
    "affection_change": 1,
    "learned_about_player": {
      "name": "Marcus",
      "notable_facts": ["Claims to be a traveling merchant"]
    }
  }
}
```

**Dialogue Features:**
- Tone notation with `[brackets]` for emotional context
- Automatic relationship dimension updates
- Player information extraction and storage
- Greeting recognition based on memory

### 4. World State & Consequences

Player actions ripple through the world:

| System | Purpose |
|--------|---------|
| **EventBus** | Signal-based event propagation |
| **WorldState** | Faction reputation, quest tracking, flags |
| **WorldEvents** | Canonical event log (source of truth) |
| **WorldKnowledge** | Prevents NPC hallucination with verified facts |
| **StoryFlags** | 25 defined flags for narrative progression |

### 5. Asset Generation Pipeline

AI-generated pixel art via multiple backends:

| Backend | Use Case |
|---------|----------|
| **PixelLab.ai** | Primary - Characters, animations, tiles |
| **Recraft** | Style-consistent images with references |
| **Local SD** | Offline fallback |
| **Mock** | Testing without API calls |

---

## Technical Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         GODOT ENGINE                            │
├─────────────────────────────────────────────────────────────────┤
│  AUTOLOAD SINGLETONS (12)                                       │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│  │  EventBus   │ │ WorldState  │ │SceneManager │               │
│  └─────────────┘ └─────────────┘ └─────────────┘               │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│  │WorldKnowledge│ │ WorldEvents │ │   Config    │               │
│  └─────────────┘ └─────────────┘ └─────────────┘               │
├─────────────────────────────────────────────────────────────────┤
│  NPC SYSTEM                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  BaseNPC (CharacterBody2D)                               │   │
│  │  ├── NPCPersonality (Resource)                          │   │
│  │  ├── RAGMemory → ChromaDB                               │   │
│  │  ├── ContextBuilder                                     │   │
│  │  └── ClaudeClient → Claude API                          │   │
│  └─────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  EXTERNAL SERVICES                                              │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐            │
│  │  Claude API  │ │   ChromaDB   │ │  PixelLab    │            │
│  │  (Dialogue)  │ │   (Memory)   │ │  (Assets)    │            │
│  └──────────────┘ └──────────────┘ └──────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
Land/
├── scripts/           (90 files, ~21,000 lines)
│   ├── npcs/          - NPC framework & implementations
│   ├── dialogue/      - Claude integration, context building
│   ├── memory/        - ChromaDB client
│   ├── world_state/   - Event bus, world state, flags
│   ├── generation/    - Asset generation pipeline
│   ├── world/         - Scene management, locations
│   ├── ui/            - Debug console, dialogue UI
│   └── debug/         - Testing tools
├── scenes/            (21 files)
│   ├── npcs/          - Individual NPC scenes
│   ├── interior/      - Building interiors
│   ├── exterior/      - Outdoor locations
│   └── ui/            - UI components
├── resources/         (19 files)
│   ├── npc_personalities/  - Character definitions
│   └── locations/     - Location data
└── docs/              (9 files)
    └── Documentation & planning
```

### Key Patterns

| Pattern | Usage |
|---------|-------|
| **Singleton/Autoload** | Global systems (EventBus, WorldState, etc.) |
| **Composition** | NPCs contain memory, context, client components |
| **Resource-Driven** | Personalities and locations as `.tres` files |
| **Event-Driven** | Decoupled communication via signals |
| **Async/Await** | Non-blocking API and database calls |

---

## Implementation Details

### NPC Conversation Flow

```
1. Player approaches NPC
   └── InteractionArea.body_entered signal

2. Player presses interact key (E)
   └── start_conversation() called

3. Memory retrieval (async)
   └── ChromaDB returns tiered memories

4. Context assembly
   └── ContextBuilder combines:
       - NPCPersonality prompt
       - Tiered memories
       - World state & flags
       - Conversation history

5. Claude API call (async)
   └── Returns JSON with response + analysis

6. Response processing
   ├── Display dialogue with tone brackets
   ├── Update relationship dimensions
   ├── Extract learned player info
   └── Store interaction memory

7. Memory persistence
   └── ChromaDB stores from NPC's perspective
```

### Relationship Dimension System

```gdscript
# 5 Dimensions tracked per NPC
var relationship_trust: int = 30        # -100 to 100
var relationship_respect: int = 30      # -100 to 100
var relationship_affection: int = 30    # -100 to 100
var relationship_fear: int = 0          # -100 to 100
var relationship_familiarity: int = 10  # 0 to 100

# Dimensions affect:
# - Dialogue tone and openness
# - Secret unlocking thresholds
# - Romance availability
# - NPC behavior and reactions
```

### Secret Unlocking

```gdscript
# Example from Gregor's personality
secrets = [{
    "secret": "Made a deal with bandits for protection",
    "unlock_trust": 50,
    "unlock_affection": 40
}, {
    "secret": "Saved gold for Elena to escape the village",
    "unlock_trust": 65,
    "unlock_affection": 55
}]
```

---

## Challenges & Solutions

### Challenge 1: NPC Memory Bloat

**Problem:** Unlimited memory storage causes context overflow and increased costs.

**Solution:** Tiered memory system with limits:
- Pinned: 5 max (relationship-defining)
- Important: 3 max (significant events)
- Relevant: 5 max (semantic search)
- Deduplication by custom_id pattern

### Challenge 2: NPC Hallucination

**Problem:** Claude invents facts about the world or other NPCs.

**Solution:**
- `WorldKnowledge` singleton with canonical facts
- Strong personality anchors in prompts
- Memory validation checking for unknown NPC names
- "NEVER invent" instructions in system prompt

### Challenge 3: Response Latency

**Problem:** Claude API calls take 1-3 seconds, breaking immersion.

**Solution:**
- Async/await for non-blocking calls
- Loading indicator during generation
- Pre-generated greetings for common scenarios
- Rate limiting (500ms between requests)

### Challenge 4: Prompt Injection

**Problem:** Players could manipulate NPCs via crafted input.

**Solution:**
- Input sanitization in ClaudeClient
- "NEVER break character" anchors
- Unbreakable secrets that resist any trust level
- Response validation before display

### Challenge 5: Cross-Platform ChromaDB

**Problem:** ChromaDB is Python-based, Godot uses GDScript.

**Solution:**
- Python CLI wrapper (`chroma_cli.py`)
- `OS.execute()` calls from GDScript
- JSON-based communication
- Async execution to prevent blocking

### Challenge 6: Consistent Art Style

**Problem:** AI-generated assets vary in style.

**Solution:**
- PixelLab.ai with style parameters
- Style reference images for Recraft
- Consistent prompts with "16-bit SNES style"
- Generation seed for reproducibility

---

## Architectural Decisions

### Decision 1: One AI Agent Per NPC

**Choice:** Each NPC has its own Claude context rather than a shared "NPC controller."

**Rationale:**
- Enables distinct personalities without cross-contamination
- Memory isolation prevents NPCs "knowing" what others learned
- Scalable - adding NPCs doesn't affect existing ones
- Easier debugging of individual NPC behavior

**Trade-off:** Higher API costs per conversation, but authentic interactions.

### Decision 2: Resource-Driven Personalities

**Choice:** NPCPersonality as Godot Resource (`.tres`) files.

**Rationale:**
- Designer-friendly editing in Godot inspector
- Version control friendly (text-based)
- Hot-reloadable during development
- Clear separation of data and logic

### Decision 3: Event Bus for Decoupling

**Choice:** Central EventBus singleton for cross-system communication.

**Rationale:**
- Systems don't need direct references to each other
- Easy to add new listeners without modifying emitters
- Enables replay/logging of all game events
- Simplifies testing individual systems

### Decision 4: ChromaDB Over SQLite

**Choice:** Vector database for NPC memory instead of relational.

**Rationale:**
- Semantic search matches "what was the conversation about"
- Better for natural language recall
- Built-in embedding generation
- Scales with memory without query complexity

**Trade-off:** External Python dependency, more complex setup.

### Decision 5: Structured JSON Responses

**Choice:** Claude returns JSON with analysis, not just dialogue text.

**Rationale:**
- Explicit relationship dimension changes
- Player information extraction
- Tone and emotional impact tracking
- Fallback to text parsing if JSON fails

### Decision 6: Tiered Memory Architecture

**Current Choice:** Pinned > Important > Relevant memory tiers with fixed limits (5/3/5).

**Original Rationale:**
- Ensures critical memories always included
- Semantic search for contextual relevance
- Prevents context overflow

**Known Limitations (Context Drift):**
- "Always inject" semantics become permanent tax as corpus grows
- Fixed limits don't adapt to available context budget
- Old pinned memories crowd out newer important events

**Planned Evolution:** Score-based selection where tier provides scoring *advantage* (3x/2x/1x) rather than allocation *guarantee*. Protected set limited to ~2-3 truly critical memories (first_meeting, player_name, npc_death). See Memory Architecture section for full design.

---

## Current State

> **Last Updated:** December 2024

### Completed Systems

| System | Status | Key Files |
|--------|--------|-----------|
| **NPC Personality Framework** | Complete | `base_npc.gd`, 7 `.tres` resources |
| **5D Relationship System** | Complete | Trust, Respect, Affection, Fear, Familiarity |
| **RAG Memory (ChromaDB)** | Complete | `rag_memory.gd`, tiered retrieval |
| **Claude Dialogue Generation** | Complete | JSON responses, tone notation |
| **Scene Management** | Complete | `scene_manager.gd`, transitions |
| **Debug Console** | Complete | 12 commands for testing |
| **Story Flags** | Complete | `story_flags.gd`, 25 defined flags |
| **World Knowledge** | Complete | Canonical facts, hallucination prevention |
| **Asset Generation** | Complete | PixelLab, Recraft, Local SD backends |
| **Quest System** | Complete | See Quest Architecture below |

### Quest Architecture (Phase 6+)

| Component | Status | Description |
|-----------|--------|-------------|
| `QuestManager` | Complete | Singleton tracking active/completed quests |
| `QuestResource` | Complete | Data class for quest definitions |
| `QuestObjective` | Complete | Individual objective tracking |
| `IntentDetector` | Complete | NPC dialogue intent recognition |
| **Quest Journal UI** | Complete | `quest_journal.gd`, tabbed interface |
| **Quest Notifications** | Complete | `quest_notifications.gd`, popup system |
| **Quest Context Injection** | Complete | NPCs hint toward quest objectives |

### In Progress

| System | Status | Next Steps |
|--------|--------|------------|
| Evidence Discovery Triggers | Planned | Area2D triggers for ledger, weapons |
| NPC Event Propagation | Planned | NPCs auto-learn from world events |
| Voice Synthesis | Researched | ElevenLabs integration planned |

### Known Limitations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| API Latency | 1-3s response time | Loading indicators, async |
| Memory Context | ~8k tokens max | Tiered system, summarization |
| Art Consistency | Style variation | Consistent prompts, seeds |
| Offline Play | Requires internet | Local fallbacks where possible |

---

## Future Roadmap

### Phase 7: Combat System

- Turn-based or real-time combat
- NPC combat participation based on relationship
- Combat affects relationship dimensions
- Death consequences and world state updates

### Phase 8: Inventory & Trading

- Item management system
- NPC-specific trade inventories
- Evidence items (ledger, marked weapons)
- Gift-giving affects relationships

### Phase 9: Romance Specialization

- Dedicated romance dialogue paths
- Relationship milestones and events
- Rival romance dynamics
- Romance-specific memories

### Phase 10: Multiple Endings

- Ending determination from flags
- Faction alliance outcomes
- Romance partner outcomes
- Village fate variations

### Phase 11: Voice Synthesis

- ElevenLabs TTS integration
- Per-NPC voice assignment
- Audio caching for cost optimization
- Tone bracket stripping for speech

### Phase 12: Procedural NPCs

- Runtime NPC generation
- Dynamic personality creation
- Procedural backstory integration
- Scalable to larger worlds

### Long-Term Vision

| Feature | Description |
|---------|-------------|
| **Multi-Village World** | Multiple locations with travel system |
| **Faction Warfare** | Large-scale conflicts based on player choices |
| **Legacy System** | Consequences persist across playthroughs |
| **Mod Support** | Custom NPCs, locations, stories |
| **Multiplayer** | Shared world with persistent NPCs |

---

## Development Guidelines

### Adding a New NPC

1. Create personality resource: `resources/npc_personalities/npc_name.tres`
2. Create scene: `scenes/npcs/npc_name.tscn` extending BaseNPC
3. Add to scene with `groups = ["npcs"]`
4. Define secrets with unlock thresholds
5. Add to WorldKnowledge canonical facts

### Testing NPC Behavior

1. Open debug console (backtick key)
2. `set_trust npc_name 75` - Test secret unlocking
3. `show_npc npc_name` - View state and secrets
4. `set_flag flag_name 1` - Test flag-dependent dialogue

### API Cost Management

- Monitor token usage via ClaudeClient logging
- Use `max_tokens: 1024` for responses
- Cache greetings where possible
- Rate limit at 500ms minimum between calls

---

## References

### Active Documentation

| Document | Purpose |
|----------|---------|
| [Story Narrative](STORY_NARRATIVE.md) | Full story, lore, and character details |
| [Development Plan](DEVELOPMENT_PLAN.md) | Roadmap, phases, and backlog |
| [Testing Guide](TESTING.md) | Test cases for NPC behavior |
| [Voice Synthesis Plan](VOICE_SYNTHESIS_PLAN.md) | ElevenLabs integration (future) |

### Archived (Superseded)

| Document | Status | Notes |
|----------|--------|-------|
| `PHASE_6_PLAN.md` | Archived | Merged into DEVELOPMENT_PLAN.md |
| `QUEST_INFRASTRUCTURE.md` | Archived | Quest system now complete, documented above |
| `QUEST_JOURNAL_UI_DESIGN.md` | Archived | UI implemented per design |
| `NPC_SPECIFICATIONS.md` | Archived | Merged into STORY_NARRATIVE.md |
| `FUTURE_WORK.md` | Archived | Merged into DEVELOPMENT_PLAN.md |
| `NPC_KNOWLEDGE_VALIDATION.md` | Archived | Anti-hallucination documented in architecture |

---

*This document should be updated as major features are implemented or architectural decisions change.*
