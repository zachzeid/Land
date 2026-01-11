# Phase 1: Personality Anchoring System

## Overview

Phase 1 implements a **structured personality system** that ensures NPC character consistency across all Claude interactions. This replaces the unstructured text-blob approach with typed, measurable personality components.

## Implementation Summary

### Files Created/Modified

| File | Purpose |
|------|---------|
| `scripts/resources/npc_personality.gd` | NPCPersonality resource class with structured traits |
| `resources/npc_personalities/gregor_merchant.tres` | Gregor's structured personality |
| `resources/npc_personalities/elena_daughter.tres` | Elena's structured personality |
| `scripts/dialogue/context_builder.gd` | Updated to use structured personalities |
| `scripts/npcs/base_npc.gd` | Updated to load and use personality resources |
| `scripts/debug/personality_kpi_tracker.gd` | KPI measurement system |
| `scripts/debug/test_phase1_personality.gd` | Validation test suite |

---

## Key Features

### 1. Core Identity Anchoring
Every NPC now has immutable identity facts that are **always injected at the top of the context**, never pushed out by conversation history.

```gdscript
identity_anchors = [
    "You are Gregor Stoneheart, age 52, a merchant in Thornhaven",
    "Your daughter Elena is 24 and helps with the shop",
    "You know bandits have an inside informant but are afraid to speak up"
]
```

### 2. Structured Personality Traits
Big Five personality model + character-specific traits:

```gdscript
# Big Five (-100 to 100)
trait_openness = 30
trait_extraversion = 40
trait_agreeableness = 50

# Character traits (boolean)
is_flirtatious = true
is_protective = true
is_secretive = true
```

### 3. Speech Pattern Enforcement
Explicit rules for how NPCs talk:

```gdscript
vocabulary_level = "educated"
speaking_style = "warm"
signature_phrases = ["Fine wares for a fine customer", "Between you and me..."]
forbidden_phrases = ["dude", "awesome", "cool", "whatever"]
```

### 4. Secret & Romance Thresholds
Secrets and romance unlock based on relationship dimensions:

```gdscript
secrets = [{
    "secret": "The bandits have an inside informant...",
    "unlock_trust": 60,
    "unlock_affection": 70
}]

romance_trust_threshold = 50
romance_affection_threshold = 60
romance_familiarity_threshold = 40
```

### 5. Personality-Based Impact Modifiers
Each NPC reacts differently to the same interaction:

```gdscript
affection_sensitivity = 1.3  # Gregor values affection more
fear_sensitivity = 1.2       # Gregor scares easily
forgiveness_tendency = 30    # Moderate forgiveness
```

---

## KPI Definitions & Targets

### KPI 1: Identity Anchor Adherence
**Target: 100%**

Measures whether NPC responses contradict their core identity facts.

- ✅ PASS: Response aligns with all identity anchors
- ❌ FAIL: Response contradicts age, name, relationships, etc.

### KPI 2: Speech Pattern Compliance
**Target: 0% forbidden violations, 20%+ signature phrase usage**

Measures whether NPCs speak in their defined voice.

- ✅ PASS: No forbidden phrases used, signature phrases appear regularly
- ❌ FAIL: "Dude, that's awesome!" from a medieval merchant

### KPI 3: Relationship Threshold Accuracy
**Target: 100%**

Measures whether secrets/romance only appear when thresholds are met.

- ✅ PASS: Secrets revealed only at correct trust/affection levels
- ❌ FAIL: NPC reveals bandit informant to stranger (trust 20)

### KPI 4: Personality Trait Consistency
**Target: 90%+**

Measures whether responses align with personality traits.

- ✅ PASS: Extraverted NPC uses enthusiastic language
- ❌ FAIL: Introverted NPC suddenly becomes life of the party

### KPI 5: World Knowledge Accuracy
**Target: 100%**

Measures whether NPC contradicts WorldKnowledge facts.

- ✅ PASS: Uses correct names, locations, relationships
- ❌ FAIL: Gregor refers to daughter as "Sarah" instead of "Elena"

---

## How to Use

### Loading a Structured Personality

```gdscript
# In your NPC script
extends "res://scripts/npcs/base_npc.gd"

func _ready():
    # Load structured personality resource
    personality_resource = load("res://resources/npc_personalities/gregor_merchant.tres")

    # Initialize with KPI tracking enabled (for testing)
    await initialize(true, true)  # use_chromadb=true, enable_kpi_tracking=true
```

### Running the Test Suite

```gdscript
# Add to a scene and run
var test_scene = load("res://scripts/debug/test_phase1_personality.gd").new()
add_child(test_scene)
```

### Viewing KPI Reports

KPI reports are automatically printed when a conversation ends (if tracking is enabled):

```
============================================================
PERSONALITY CONSISTENCY KPI REPORT
NPC: gregor_merchant_001
============================================================

OVERALL HEALTH: GOOD

KPI BREAKDOWN:
----------------------------------------
1. Identity Anchor Adherence
   Rate: 100.0% (Target: 100%)
   Status: PASS

2. Speech Pattern Compliance
   Forbidden Violations: 0.0% (Target: 0%)
   Signature Usage: 25.0% (Target: 20%+)
   Status: PASS
...
```

---

## Success Criteria

Phase 1 is complete when:

| Criteria | Status |
|----------|--------|
| SC-1: NPCPersonality resources load correctly | ✅ |
| SC-2: Core identity block generates properly | ✅ |
| SC-3: Speech patterns are enforced in prompts | ✅ |
| SC-4: Personality modifiers affect impact calculations | ✅ |
| SC-5: Secrets unlock at correct thresholds | ✅ |
| SC-6: Romance unlocks at correct thresholds | ✅ |
| SC-7: ContextBuilder integrates personality correctly | ✅ |
| SC-8: KPI tracker measures all metrics | ✅ |

---

## Next Steps (Phase 2)

Phase 2: Memory Hierarchy will add:

1. **Tiered memory storage** (pinned, important, regular)
2. **Relationship milestone tracking** (first meeting, first gift, etc.)
3. **Memory consolidation** (summarize old memories into facts)
4. **Priority retrieval** (always include pinned memories)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     NPCPersonality.tres                      │
├─────────────────────────────────────────────────────────────┤
│  Core Identity        │  Personality Traits  │  Speech      │
│  - npc_id             │  - Big Five         │  - vocabulary │
│  - display_name       │  - Character traits │  - style     │
│  - identity_anchors   │  - Values/Fears     │  - phrases   │
├─────────────────────────────────────────────────────────────┤
│  Relationship Settings │  Secrets            │  Modifiers   │
│  - thresholds          │  - unlock conditions│  - sensitivity│
│  - orientation         │  - unbreakable      │  - forgiveness│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      ContextBuilder                          │
├─────────────────────────────────────────────────────────────┤
│  1. Core Identity Block      (ALWAYS first, never trimmed)  │
│  2. WorldKnowledge Facts     (Prevents hallucination)       │
│  3. Personality Summary      (Traits in natural language)   │
│  4. Speech Patterns          (Enforcement rules)            │
│  5. Relationship State       (5 dimensions + romance check) │
│  6. Unlocked Secrets         (Based on thresholds)          │
│  7. Memories                 (Categorized by type)          │
│  8. Behavioral Guidance      (Dynamic based on state)       │
│  9. Response Format          (JSON structure)               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Claude API                              │
├─────────────────────────────────────────────────────────────┤
│  Generates response with:                                    │
│  - Consistent character voice                                │
│  - Appropriate secret/romance handling                       │
│  - Relationship dimension analysis                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   KPI Tracker (Optional)                     │
├─────────────────────────────────────────────────────────────┤
│  Validates:                                                  │
│  - Identity adherence                                        │
│  - Speech compliance                                         │
│  - Threshold accuracy                                        │
│  - Trait consistency                                         │
│  - World accuracy                                            │
└─────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

### "Personality resource not loading"
- Ensure the `.tres` file has `script_class="NPCPersonality"`
- Check the script path in the resource file

### "KPI shows forbidden phrase violations"
- Claude is generating modern slang
- Add more forbidden phrases to the personality
- Strengthen the speech pattern section in prompts

### "Secrets revealed too early"
- Check `unlock_trust` and `unlock_affection` values in personality
- Verify relationship dimensions are being passed to context builder

### "NPC personality feels inconsistent"
- Enable KPI tracking to identify specific violations
- Review the identity anchors - are they specific enough?
- Add more signature phrases to reinforce voice
