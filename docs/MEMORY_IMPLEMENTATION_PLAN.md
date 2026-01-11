# Memory Architecture Implementation Plan

> **Purpose:** Phased implementation of score-based memory selection
> **Created:** December 2024
> **Status:** Ready for implementation

---

## Executive Summary

Transform the current tier-based memory allocation into score-based selection while preserving backwards compatibility. The implementation is divided into 6 phases, each independently deployable and testable.

**Key Insight from Exploration:** The codebase already has rich metadata and ChromaDB distances—we just need to apply intelligent scoring to selection.

---

## Phase Overview

| Phase | Focus | Risk | Effort | Dependencies | Status |
|-------|-------|------|--------|--------------|--------|
| 1 | Scoring Foundation | Low | 2-3 hours | None | ✅ COMPLETE |
| 2 | Bounded Collection | Medium | 2-3 hours | Phase 1 | ✅ COMPLETE |
| 3 | Protected Headers | Low | 1-2 hours | None | ✅ COMPLETE |
| 4 | Dual Representation | Medium | 3-4 hours | Phase 1 | ✅ COMPLETE |
| 5 | Schema Constraints + Delta Clamping | Low | 2-3 hours | None | ✅ COMPLETE |
| 6 | Conflict Resolution | Medium | 2-3 hours | Phase 4 | ✅ COMPLETE |

**Total Estimated Effort:** 12-18 hours across all phases

---

## Phase 1: Scoring Foundation

**Goal:** Add scoring function and apply to memory selection within existing tier structure.

### 1.1 Add Scoring Function to RAGMemory

**File:** `scripts/npcs/rag_memory.gd`

```gdscript
## Calculate memory score for selection priority
## Higher score = more likely to be included in context
func _calculate_memory_score(memory: Dictionary, query_context: String) -> float:
    var meta = memory.get("metadata", {})

    # Tier weight (signal, not guarantee)
    var tier = meta.get("memory_tier", 2)
    var tier_weight = config.tier_weights[tier] if config else [3.0, 2.0, 1.0][tier]

    # Importance (1-10 normalized)
    var importance = meta.get("importance", 5) / 10.0

    # Recency decay with configurable half-life
    var half_life = config.recency_half_life_days if config else 7.0
    var recency_floor = config.recency_floor if config else 0.3
    var age_seconds = Time.get_unix_time_from_system() - meta.get("timestamp", 0)
    var age_days = age_seconds / 86400.0
    var recency = recency_floor + (1.0 - recency_floor) * exp(-age_days * 0.693 / half_life)

    # Semantic relevance (from ChromaDB distance, converted to similarity)
    var relevance_floor = config.relevance_floor if config else 0.3
    var distance = memory.get("distance", 0.5)
    var similarity = 1.0 - clamp(distance, 0.0, 1.0)
    var relevance = relevance_floor + (1.0 - relevance_floor) * similarity

    # Supersession penalty
    var supersession_mult = 1.0
    if meta.get("superseded_by", "") != "":
        supersession_mult = config.superseded_score_multiplier if config else 0.1

    return tier_weight * importance * recency * relevance * supersession_mult
```

**Location:** Add after line ~250 (near existing scoring logic for in-memory fallback)

### 1.2 Apply Scoring in Tier Retrieval

**File:** `scripts/npcs/rag_memory.gd`

Modify `_get_memories_by_tier()` (line 859) and `_get_semantic_memories()` (line 888):

```gdscript
func _get_memories_by_tier(tier: int, limit: int, query_context: String = "") -> Array:
    var memories = await chroma_client.query_memories(
        _get_collection_name(),
        query_context if query_context else "relationship milestone important",
        limit * 2,  # Fetch more, then score-filter
        0,
        {"memory_tier": tier}
    )

    # Score and sort
    for mem in memories:
        mem["score"] = _calculate_memory_score(mem, query_context)
    memories.sort_custom(func(a, b): return a.get("score", 0) > b.get("score", 0))

    return memories.slice(0, limit)
```

### 1.3 Add Config Exports

**File:** `scripts/resources/memory_config.gd`

Add after line 19:

```gdscript
## ============================================================================
## SCORE-BASED SELECTION
## ============================================================================

@export_group("Score-Based Selection")
## Tier weights for scoring (PINNED, IMPORTANT, REGULAR)
@export var tier_weights: Array[float] = [3.0, 2.0, 1.0]
## Half-life for recency decay in days
@export var recency_half_life_days: float = 7.0
## Minimum recency factor (prevents total decay)
@export var recency_floor: float = 0.3
## Minimum relevance factor
@export var relevance_floor: float = 0.3
```

### 1.4 Testing

1. Open debug console, talk to any NPC
2. Run `show_npc <id>` to verify memories are being retrieved
3. Add temporary logging in `_calculate_memory_score()` to verify scores
4. Compare behavior with previous tier-only selection

### 1.5 Rollback Plan

- Keep `retrieve_tiered()` signature unchanged
- Add feature flag: `use_score_based_selection` in MemoryConfig
- If disabled, use original tier-only logic

### ✅ Phase 1 Implementation Complete (Dec 2024)

**Files Modified:**
- `scripts/resources/memory_config.gd` - Added score-based selection config exports
- `scripts/npcs/rag_memory.gd` - Added `_calculate_memory_score()`, updated tier/semantic retrieval

**What's Working:**
- Score formula: `tier_weight × importance × recency × relevance × supersession_mult`
- Configurable via MemoryConfig resource
- Feature flag `use_score_based_selection` for rollback
- Debug logging shows scores in tiered retrieval output

---

## Phase 2: Bounded Candidate Collection

**Goal:** Replace "get all" with three-source bounded fetch.

### 2.1 Add Bounded Retrieval Method

**File:** `scripts/npcs/rag_memory.gd`

```gdscript
## Retrieve memories using bounded collection strategy
## Returns: Array of scored memory candidates
func retrieve_scored(context: String, token_budget: int = 2500) -> Array:
    var all_candidates: Array = []
    var seen_ids: Dictionary = {}

    # Source 1: Protected slot-based memories (always include)
    var protected = await _get_protected_memories()
    for mem in protected:
        seen_ids[mem.get("id", "")] = true
        mem["protected"] = true
        all_candidates.append(mem)

    # Source 2: High-signal recent events (last N days)
    var recency_days = config.high_signal_recency_days if config else 7
    var high_signal_types = ["betrayal", "life_saved", "secret_revealed", "promise_made", "promise_broken"]
    var recent_high_signal = await _get_recent_by_types(high_signal_types, recency_days, 10)
    for mem in recent_high_signal:
        if not seen_ids.has(mem.get("id", "")):
            seen_ids[mem.get("id", "")] = true
            all_candidates.append(mem)

    # Source 3: Top-K semantic search
    var top_k = config.semantic_top_k if config else 15
    var semantic = await chroma_client.query_memories(
        _get_collection_name(),
        context,
        top_k,
        4,  # min_importance
        {}
    )
    for mem in semantic:
        if not seen_ids.has(mem.get("id", "")):
            seen_ids[mem.get("id", "")] = true
            all_candidates.append(mem)

    # Score all non-protected candidates
    for mem in all_candidates:
        if not mem.get("protected", false):
            mem["score"] = _calculate_memory_score(mem, context)

    # Sort by score (protected first, then by score)
    all_candidates.sort_custom(func(a, b):
        if a.get("protected", false) != b.get("protected", false):
            return a.get("protected", false)
        return a.get("score", 0) > b.get("score", 0)
    )

    # Fill token budget
    return _fill_token_budget(all_candidates, token_budget)

func _get_protected_memories() -> Array:
    # Query by slot_type for protected entries
    var protected_types = config.protected_slot_types if config else ["relationship_header", "player_name"]
    var results: Array = []
    for slot_type in protected_types:
        var mem = await chroma_client.query_memories(
            _get_collection_name(),
            "",
            1,
            0,
            {"slot_type": slot_type}
        )
        results.append_array(mem)
    return results

func _get_recent_by_types(event_types: Array, days: int, limit: int) -> Array:
    var cutoff = Time.get_unix_time_from_system() - (days * 86400)
    var results: Array = []
    for event_type in event_types:
        var mems = await chroma_client.query_memories(
            _get_collection_name(),
            "",
            limit,
            0,
            {"event_type": event_type}
        )
        for mem in mems:
            if mem.get("metadata", {}).get("timestamp", 0) >= cutoff:
                results.append(mem)
    return results

func _fill_token_budget(memories: Array, budget: int) -> Array:
    var result: Array = []
    var remaining = budget

    for mem in memories:
        var text = mem.get("document", "")
        var tokens = ceili(text.length() / 3.0)  # Conservative estimate
        if tokens <= remaining:
            result.append(mem)
            remaining -= tokens

    return result
```

### 2.2 Add Config Exports

**File:** `scripts/resources/memory_config.gd`

```gdscript
@export_group("Bounded Collection")
## Days to look back for high-signal events
@export var high_signal_recency_days: int = 7
## High-signal event types to fetch directly
@export var high_signal_event_types: Array[String] = [
    "betrayal", "life_saved", "secret_revealed", "promise_made", "promise_broken"
]
## Top-K for semantic search
@export var semantic_top_k: int = 15
```

### 2.3 Integration

Update `base_npc.gd` to use `retrieve_scored()` instead of `retrieve_tiered()`:

```gdscript
# In respond_to_player(), around line 430
var memories = await rag_memory.retrieve_scored(player_input, 2500)
# Then format for context...
```

### 2.4 Testing

1. Verify all three sources contribute candidates
2. Check that protected memories always appear
3. Confirm token budget is respected
4. Compare response quality with previous approach

### ✅ Phase 2 Implementation Complete (Dec 2024)

**Files Modified:**
- `scripts/resources/memory_config.gd` - Added bounded collection config exports
- `scripts/npcs/rag_memory.gd` - Added `retrieve_scored()`, `_get_protected_memories()`, `_get_recent_by_types()`, `_get_semantic_top_k()`, `_fill_token_budget()`

**What's Working:**
- Three-source bounded collection: protected → high-signal recent → semantic top-K
- Configurable via MemoryConfig (high_signal_event_types, semantic_top_k, etc.)
- Token budget enforcement with protected memory override
- Feature flag `use_bounded_collection` for rollback
- Debug logging shows source contributions

**Integration Note:** `retrieve_scored()` can now be called directly. Integration with `base_npc.gd` is optional - the tiered retrieval still works.

---

## Phase 3: Protected Relationship Headers

**Goal:** Replace narrative protection with compact state headers.

### 3.1 Add Header Generation

**File:** `scripts/npcs/rag_memory.gd`

```gdscript
## Generate compact relationship header for protected injection
func generate_relationship_header() -> Dictionary:
    var rel = _get_relationship_state()
    var days_known = 0

    # Calculate days since first meeting
    var first_meeting = await _get_memory_by_type("first_meeting")
    if first_meeting:
        var first_ts = first_meeting.get("metadata", {}).get("timestamp", 0)
        days_known = int((Time.get_unix_time_from_system() - first_ts) / 86400.0)

    var header_text = "[Met=%s, Days=%d, Trust=%d, Affection=%d, Fear=%d, Status=%s]" % [
        "yes" if days_known > 0 else "no",
        days_known,
        rel.get("trust", 50),
        rel.get("affection", 0),
        rel.get("fear", 0),
        _get_status_label(rel)
    ]

    return {
        "id": "%s_relationship_header" % npc_id,
        "document": header_text,
        "metadata": {
            "slot_type": "relationship_header",
            "timestamp": Time.get_unix_time_from_system(),
            "npc_id": npc_id
        }
    }

func _get_status_label(rel: Dictionary) -> String:
    var trust = rel.get("trust", 50)
    var affection = rel.get("affection", 0)

    if trust < 20:
        return "hostile" if affection < 0 else "distrustful"
    elif trust < 40:
        return "wary"
    elif trust < 60:
        return "neutral"
    elif trust < 80:
        return "friendly"
    else:
        return "trusted_ally" if affection > 50 else "respected"
```

### 3.2 Update Protected Memory Handling

Modify `_get_protected_memories()` to generate header on-the-fly:

```gdscript
func _get_protected_memories() -> Array:
    var results: Array = []

    # Always include relationship header (generated, not stored)
    results.append(generate_relationship_header())

    # Include player name if known
    var player_name_mem = await _get_memory_by_slot("player_name")
    if player_name_mem:
        results.append(player_name_mem)

    # Include NPC death status if relevant
    var death_status = await _get_memory_by_slot("npc_death_status")
    if death_status:
        results.append(death_status)

    return results
```

### 3.3 Testing

1. Verify header appears in every context
2. Check header updates as relationship changes
3. Confirm `first_meeting` narrative is now in scored pool, not protected

### ✅ Phase 3 Implementation Complete (Dec 2024)

**Files Modified:**
- `scripts/npcs/rag_memory.gd` - Added `generate_relationship_header()`, `_get_status_label()`, `_get_memory_by_event_type()`, `_get_memory_by_slot()`, `set_relationship_state()`

**What's Working:**
- Compact relationship headers generated on-the-fly: `[Met=yes, Days=X, Trust=X, Affection=X, Fear=X, Respect=X, Status=X]`
- Status labels: terrified, hostile, distrustful, wary, cautious, neutral, acquaintance, friendly, close_friend, devoted, trusted_ally
- `_get_protected_memories()` now generates headers dynamically instead of querying stored data
- `set_relationship_state()` allows NPC to inject current relationship values

**Integration Note:** NPCs should call `set_relationship_state()` before retrieval to ensure headers reflect current relationship values.

---

## Phase 4: Dual Representation Storage

**Goal:** Store short + full forms for each memory.

### 4.1 Add Summary Generation

**File:** `scripts/npcs/rag_memory.gd`

```gdscript
## Generate short summary from full memory text
## Target: 50-80 characters
func _summarize_to_short(full_text: String, event_type: String) -> String:
    # For simple cases, truncate intelligently
    if full_text.length() <= 80:
        return full_text

    # Find first sentence
    var first_period = full_text.find(".")
    if first_period > 0 and first_period < 80:
        return full_text.substr(0, first_period + 1)

    # Truncate at word boundary
    var truncated = full_text.substr(0, 75)
    var last_space = truncated.rfind(" ")
    if last_space > 40:
        return truncated.substr(0, last_space) + "..."

    return truncated + "..."
```

### 4.2 Modify Storage Path

**File:** `scripts/npcs/rag_memory.gd` - `store()` function (line ~149)

```gdscript
func store(memory_text: String, importance: int = 5, memory_data: Dictionary = {}) -> void:
    # ... existing validation ...

    # Generate dual representations
    var short_text = _summarize_to_short(memory_text, memory_data.get("event_type", ""))

    var document = {
        "document_short": short_text,
        "document_full": memory_text,
        "document": short_text,  # Default to short for backwards compat
        "metadata": {
            # ... existing metadata ...
        }
    }

    # Store with both forms
    await chroma_client.add_memory(_get_collection_name(), document)
```

### 4.3 Relevance-Based Form Selection

Update `_fill_token_budget()`:

```gdscript
const HIGH_RELEVANCE_THRESHOLD = 0.85

func _fill_token_budget(memories: Array, budget: int) -> Array:
    var result: Array = []
    var remaining = budget

    for mem in memories:
        var similarity = 1.0 - mem.get("distance", 0.5)

        # Use full form only for highly relevant memories
        var text: String
        if similarity >= HIGH_RELEVANCE_THRESHOLD:
            text = mem.get("document_full", mem.get("document", ""))
        else:
            text = mem.get("document_short", mem.get("document", ""))

        var tokens = ceili(text.length() / 3.0)
        if tokens <= remaining:
            mem["rendered_text"] = text
            result.append(mem)
            remaining -= tokens

    return result
```

### 4.4 Migration

Existing memories won't have dual forms. Handle gracefully:

```gdscript
var short = mem.get("document_short", mem.get("document", ""))
var full = mem.get("document_full", mem.get("document", short))
```

### ✅ Phase 4 Implementation Complete (Dec 2024)

**Files Modified:**
- `scripts/resources/memory_config.gd` - Added dual representation config exports
- `scripts/npcs/rag_memory.gd` - Added `_summarize_to_short()`, `_use_dual_representation()`, `_get_high_relevance_threshold()`, updated `store()` and `_fill_token_budget()`

**What's Working:**
- Dual form storage: both `document_short` (50-80 chars) and `document_full` saved
- Intelligent summarization respecting sentence boundaries
- Relevance-based form selection: full form only when similarity >= 0.85 (configurable)
- `_rendered_text` field added to memories for downstream use
- Feature flag `use_dual_representation` for rollback
- Form selection logging shows full/short counts per retrieval

**Migration Note:** Existing memories without dual forms gracefully fall back to using `document` field for both short and full.

---

## Phase 5: Schema Constraints + Delta Clamping

**Goal:** Constrain Claude's interaction types and clamp relationship deltas.

### 5.1 Add Validation Layer

**File:** `scripts/npcs/rag_memory.gd`

```gdscript
const VALID_INTERACTION_TYPES = [
    "casual_conversation", "quest_related", "gift_given",
    "emotional_support", "romantic_gesture", "threat_made",
    "secret_shared", "betrayal", "life_saved", "romance_confession"
]

func _validate_interaction_type(claude_type: String) -> String:
    if claude_type in VALID_INTERACTION_TYPES:
        return claude_type

    push_warning("[RAGMemory] Invalid interaction_type: '%s', defaulting to casual_conversation" % claude_type)

    if OS.is_debug_build():
        for valid in VALID_INTERACTION_TYPES:
            if claude_type.similarity(valid) > 0.8:
                push_warning("[RAGMemory]   (Would have mapped to: %s)" % valid)

    return "casual_conversation"
```

### 5.2 Add Delta Clamping

**File:** `scripts/npcs/base_npc.gd` - in `_apply_relationship_changes()` or similar

```gdscript
const MAX_TRUST_CHANGE = 15
const MAX_AFFECTION_CHANGE = 10
const MAX_FEAR_CHANGE = 10
const MAX_RESPECT_CHANGE = 10

func _clamp_relationship_deltas(analysis: Dictionary) -> Dictionary:
    return {
        "trust_change": clamp(analysis.get("trust_change", 0), -MAX_TRUST_CHANGE, MAX_TRUST_CHANGE),
        "affection_change": clamp(analysis.get("affection_change", 0), -MAX_AFFECTION_CHANGE, MAX_AFFECTION_CHANGE),
        "fear_change": clamp(analysis.get("fear_change", 0), -MAX_FEAR_CHANGE, MAX_FEAR_CHANGE),
        "respect_change": clamp(analysis.get("respect_change", 0), -MAX_RESPECT_CHANGE, MAX_RESPECT_CHANGE)
    }
```

### 5.3 Update Prompt

**File:** `scripts/dialogue/context_builder.gd` - system prompt section

Add to the analysis instructions:

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

### ✅ Phase 5 Implementation Complete (Dec 2024)

**Files Modified:**
- `scripts/resources/memory_config.gd` - Added schema constraints config (valid_interaction_types, delta clamp limits) and helper methods
- `scripts/npcs/rag_memory.gd` - Added `validate_interaction_type()` and `clamp_relationship_deltas()` wrapper functions
- `scripts/npcs/base_npc.gd` - Added `_clamp_relationship_deltas()` helper, integrated validation and clamping in response handling
- `scripts/dialogue/context_builder.gd` - Updated `_build_response_format_section()` with constrained interaction types list

**What's Working:**
- Interaction type validation: invalid types from Claude default to "casual_conversation"
- Delta clamping: trust ±15, affection ±10, fear ±10, respect ±10, familiarity ±5
- Fuzzy matching in debug builds logs near-matches to catch prompt drift
- Context prompt now includes explicit list of allowed interaction types with descriptions
- All config values exposed in MemoryConfig resource for data-driven tuning

**Integration Note:** Validation and clamping happen automatically in `base_npc.gd` when processing Claude's analysis response. No additional integration needed.

---

## Phase 6: Conflict Resolution

**Goal:** Implement slot updates and supersession chains.

### 6.1 Add Conflict Detection

**File:** `scripts/npcs/rag_memory.gd`

```gdscript
const SLOT_TYPES = [
    "player_name", "player_allegiance", "npc_belief_about_player", "current_quest_for_npc"
]

const SUPERSESSION_PAIRS = {
    "promise_made": "promise_broken",
    "trust_gained": "trust_lost",
    "alliance_formed": "alliance_broken",
    "secret_kept": "secret_revealed"
}

func store_with_conflict_check(memory_text: String, importance: int, memory_data: Dictionary) -> void:
    var event_type = memory_data.get("event_type", "")
    var slot_type = memory_data.get("slot_type", "")

    # Handle slot-based updates (complete replacement)
    if slot_type in SLOT_TYPES:
        await _store_slot_update(slot_type, memory_text, importance, memory_data)
        return

    # Handle supersession chains
    if event_type in SUPERSESSION_PAIRS.values():
        var opposite = _find_supersession_key(event_type)
        if opposite:
            await _mark_superseded(opposite)

    # Store normally
    await store(memory_text, importance, memory_data)

func _store_slot_update(slot_type: String, text: String, importance: int, data: Dictionary) -> void:
    var existing = await _get_memory_by_slot(slot_type)
    if existing:
        await chroma_client.delete_memory(_get_collection_name(), existing.get("id", ""))
    await store(text, importance, data)

func _mark_superseded(event_type: String) -> void:
    var old_memories = await chroma_client.query_memories(
        _get_collection_name(),
        "",
        10,
        0,
        {"event_type": event_type}
    )
    for mem in old_memories:
        var meta = mem.get("metadata", {})
        meta["superseded_by"] = "pending"  # Will be updated with new ID
        meta["superseded_at"] = Time.get_unix_time_from_system()
        await chroma_client.update_memory(_get_collection_name(), mem.get("id", ""), meta)

func _find_supersession_key(value: String) -> String:
    for key in SUPERSESSION_PAIRS:
        if SUPERSESSION_PAIRS[key] == value:
            return key
    return ""
```

### 6.2 Add Config Exports

**File:** `scripts/resources/memory_config.gd`

```gdscript
@export_group("Conflict Resolution")
## Score multiplier for superseded memories
@export var superseded_score_multiplier: float = 0.1
## Slot types (complete replacement)
@export var slot_types: Array[String] = [
    "player_name", "player_allegiance", "npc_belief_about_player"
]
## Supersession pairs (history preserved)
@export var supersession_pairs: Dictionary = {
    "promise_made": "promise_broken",
    "trust_gained": "trust_lost",
    "alliance_formed": "alliance_broken"
}
```

### ✅ Phase 6 Implementation Complete (Dec 2024)

**Files Modified:**
- `scripts/resources/memory_config.gd` - Added conflict resolution config (slot_types, supersession_pairs) and helper methods
- `scripts/npcs/rag_memory.gd` - Added `store_with_conflict_check()`, `_store_slot_update()`, `_mark_superseded()`, `_delete_memory()`, `_update_memory_metadata()`, `_get_memories_by_event_type()`

**What's Working:**
- Slot-based updates: memories with slot_types like `player_name` replace old values completely
- Supersession chains: when `promise_broken` is stored, `promise_made` memories get 0.1x score penalty
- Both in-memory and ChromaDB storage supported
- Configurable via MemoryConfig resource (slot_types array, supersession_pairs dictionary)
- `superseded_score_multiplier` (0.1) already integrated with Phase 1 scoring formula

**Two Conflict Resolution Mechanisms:**
| Mechanism | Use Case | Behavior |
|-----------|----------|----------|
| Slot Update | Identity facts (player_name, allegiance) | Old value deleted, new value stored |
| Supersession | Narrative transitions (promise_made → promise_broken) | Old memory preserved with 90% score penalty |

**Integration Note:** Use `store_with_conflict_check()` instead of `store()` when the memory might conflict with existing data. The function automatically detects slot types and supersession triggers.

---

## Testing Strategy

### Unit Tests (per phase)

```gdscript
# test_memory_scoring.gd
func test_score_calculation():
    var memory = {
        "metadata": {
            "memory_tier": 0,  # PINNED
            "importance": 10,
            "timestamp": Time.get_unix_time_from_system() - 86400  # 1 day ago
        },
        "distance": 0.2  # High similarity
    }
    var score = rag_memory._calculate_memory_score(memory, "test context")
    assert(score > 2.0, "PINNED high-importance recent memory should score > 2.0")

func test_protected_always_included():
    var memories = await rag_memory.retrieve_scored("any context", 100)  # Tiny budget
    var has_header = memories.any(func(m): return m.get("metadata", {}).get("slot_type") == "relationship_header")
    assert(has_header, "Relationship header should always be included")

func test_dual_form_selection():
    # High relevance -> full form
    # Low relevance -> short form
    pass
```

### Integration Tests

1. **Conversation flow:** Verify NPC responses are coherent with scored memories
2. **Long session:** Play for 20+ interactions, verify no context overflow
3. **Edge cases:** New NPC (no memories), old NPC (100+ memories)

---

## Rollback Strategy

Each phase has independent rollback:

| Phase | Rollback Method |
|-------|-----------------|
| 1 | Set `use_score_based_selection = false` in config |
| 2 | Revert to `retrieve_tiered()` in base_npc.gd |
| 3 | Remove header generation, restore first_meeting protection |
| 4 | Ignore `document_short`/`document_full`, use `document` |
| 5 | Remove validation, remove delta clamps |
| 6 | Disable conflict check, use `store()` directly |

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Context overflow errors | 0 | Error logs |
| Memory retrieval latency | < 500ms | Timing logs |
| Relevant memory inclusion | > 80% | Manual testing |
| Token budget adherence | 100% | Assert in code |
| Score distribution | Normal curve | Histogram analysis |

---

## Next Steps

1. **Review this plan** with stakeholders
2. **Start Phase 1** (Scoring Foundation) - lowest risk, highest impact
3. **Test thoroughly** before proceeding to Phase 2
4. **Document learnings** as implementation progresses

---

*This plan should be updated as implementation proceeds. Mark phases complete as they're finished.*
