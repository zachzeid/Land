# Land JRPG - Systems Discovery Report

> **Date:** 2026-03-28
> **Scope:** Full codebase audit (180+ scripts, 26 scenes, 28 docs)
> **Method:** 7 parallel deep audits covering all system areas
> **Intent:** Define, refine, and expand existing game systems

---

## Executive Summary

Land is an **ambitious AI-driven JRPG** with a mature core (Phases 1-6 complete) and well-architected systems. The project has **strong foundations** in NPC AI, memory, dialogue, and physics — but significant gaps in **consequence propagation, behavior evolution, and system integration** prevent the emergent storytelling the design envisions.

### Health Scores by System

| System | Completeness | Quality | Risk | Priority |
|--------|-------------|---------|------|----------|
| NPC AI (5D Relationships) | 95% | 9/10 | LOW | Stable |
| Memory/RAG (ChromaDB) | 90% | 8/10 | MEDIUM | Needs consolidation |
| Dialogue (Claude API) | 100% | 8/10 | LOW | Stable |
| Personality Framework | 100% | 9/10 | LOW | Stable |
| World Physics/Scenes | 85% | 8/10 | MEDIUM | Has bugs |
| Quest System | 85% | 7/10 | MEDIUM | Functional |
| World State/EventBus | 60% | 6/10 | HIGH | Missing consequence graph |
| Cross-NPC Awareness | 50% | 5/10 | HIGH | Death-only awareness |
| Secret/Romance Mechanics | 40% | 5/10 | HIGH | Incomplete paths |
| Behavior Evolution | 20% | 3/10 | HIGH | Documented, not built |
| Asset Generation | 70% | 7/10 | MEDIUM | Untested backends |
| UI (Dialogue/Quests) | 65% | 6/10 | MEDIUM | Scaffolded, not wired |
| Voice Synthesis | 80% | 8/10 | LOW | Framework complete |
| Documentation | 40% accuracy | 4/10 | HIGH | Aspirational fraud |

**Overall Project Health: 72/100** — Strong core, needs integration hardening and missing system implementation.

---

## Critical Findings (Must Fix)

### 1. Player Collision Mask Bug
- **Location:** `scenes/player/player.tscn` line 11
- **Issue:** `collision_mask = 14` (layers 2,3,4) should be `28` (layers 3,4,5)
- **Impact:** Player may not overlap with Interactable zones (doors, triggers)
- **Fix:** 5-minute change

### 2. Consequence Graph Not Implemented
- **Location:** `scripts/world_state/` — missing entirely
- **Issue:** Player actions set flags but nothing cascades. No "if X then Y" rule engine.
- **Impact:** World feels static. Gregor exposed doesn't trigger investigation. NPC deaths don't fail quests.
- **Priority:** P0 — This is the architectural gap preventing emergent storytelling

### 3. NPC Event Propagation Missing
- **Location:** EventBus has `npc_witnessed_event` signal but it's **never emitted or listened to**
- **Issue:** NPCs don't learn about world events. No gossip system. Elena doesn't know her father confessed.
- **Impact:** NPCs feel isolated from each other and the world
- **Priority:** P0 — Core to the game's narrative promise

### 4. Personality Sensitivity Modifiers Not Applied
- **Location:** `scripts/npcs/base_npc.gd` line ~561
- **Issue:** `trust_sensitivity`, `affection_sensitivity` etc. defined in NPCPersonality but never multiplied into relationship changes
- **Impact:** All NPCs respond identically to relationship changes regardless of personality
- **Fix:** Call `personality.apply_personality_modifiers(clamped_deltas)` before applying

### 5. Memory Consolidation Not Implemented
- **Location:** `scripts/npcs/rag_memory.gd` line ~1840
- **Issue:** Config and method stub exist but consolidation never runs. Database grows unbounded.
- **Impact:** After 20-50 hours, ChromaDB queries slow down. Each NPC accumulates 7,300+ memories/year.
- **Priority:** P1 — Ticking time bomb for performance

### 6. Documentation Accuracy: 40%
- **Issue:** Multiple docs describe functions that don't exist (`analyze_personality_evolution()`, `store_npc_state()` as described). DYNAMIC_TRAIT_EVOLUTION.md is 800+ lines describing non-existent code.
- **Impact:** New developers will be misled about what actually works
- **Fix:** Add `[IMPLEMENTED]` / `[ASPIRATIONAL]` tags to every doc

---

## System-by-System Findings

### A. NPC AI System (17 files, ~4000 lines)

**Status: Production-ready core with incomplete advanced features**

**What Works Well:**
- 5D relationship system (Trust, Respect, Affection, Fear, Familiarity) is well-designed and balanced
- 20+ interaction types with nuanced impact calculations
- Personality resources are fully data-driven (`.tres` files, no code changes needed)
- 7 NPCs implemented with rich personalities, secrets, and speech patterns
- Secret unlocking via dual thresholds (trust AND affection)

**Trade-off Analysis:**
- 5D vs 1D relationship: **5D is correct** — enables "respect but not trust", "love but fear" states critical for the conspiracy narrative
- Static vs evolving traits: **Current static approach is pragmatic** — dimensions capture emotional evolution; Big Five traits remaining fixed is acceptable
- Threshold-based secrets vs story-gated: **Thresholds are player-driven** (good) but lack drama — consider partial reveals at lower thresholds

**Gaps:**
- No secret denial/coercion mechanics — player can't play detective/interrogator
- No romance branching beyond threshold detection
- Unbreakable secrets field exists but no code enforces it
- No diminishing returns on relationship gains (linear to ±100)
- Cross-NPC awareness limited to death state only (no knowledge sharing)
- Behavior evolution designed but not implemented (Big Five traits static forever)

---

### B. Memory/RAG System (ChromaDB + 1850 lines)

**Status: Sophisticated 6-phase implementation, needs operational hardening**

**What Works Well:**
- Tiered retrieval (Pinned → Important → Relevant) with score-based selection
- Dual representation (short 80-char for embedding, full for high-relevance context)
- Data-driven config via MemoryConfig resource
- Memory deduplication and milestone detection
- Hallucination validation via WorldEvents

**Architecture:**
```
GDScript → ChromaClient → chroma_cli.py (subprocess) → ChromaDB PersistentClient → SQLite + HNSW
```

**Trade-off Analysis:**
- CLI subprocess vs HTTP server: **CLI is pragmatic** (~50ms overhead, no server dependency). Keep unless performance becomes issue.
- Score formula balances recency (7-day half-life), relevance, importance, tier weight — **well-designed**
- ChromaDB distances **not used** in scoring — keyword matching replaces semantic similarity. Should trust ChromaDB distances.

**Gaps:**
- Memory consolidation stub exists but never runs (unbounded growth)
- No memory backup/export capability
- `chroma_bridge.py` is dead code (HTTP bridge, never used) — should delete
- `test_chroma_direct.py` tests wrong API (server mode, not PersistentClient) — should delete
- `dialogue_manager.gd` is a 50-line placeholder never used by anything — should delete or expand
- Semantic scoring underutilized (ChromaDB distance ignored, keyword matching used instead)

---

### C. Dialogue System (Claude API, 990 lines)

**Status: Production-ready with good security posture**

**What Works Well:**
- Claude Sonnet 4.5 integration with structured JSON responses
- Prompt injection detection (substring patterns for "ignore previous instructions" etc.)
- Token tracking with cost estimation ($3/MTok input, $15/MTok output)
- Rate limiting (500ms between requests)
- Context builder assembles personality + dimensions + memories + world state + behavioral guidance

**Trade-off Analysis:**
- Full response buffering vs streaming: **Buffering is fine** for turn-based JRPG. Streaming would improve perceived latency but adds complexity.
- 16K char system prompt limit is conservative but safe
- Response format tightly coupled to ContextBuilder — format changes require code edits

**Gaps:**
- Injection detection is case-sensitive and substring-based — easily bypassed
- No response streaming (1-3s wait visible to player)
- No multi-turn context limit — very long conversations exhaust token budget
- No conversation history persistence across sessions (only current session)

---

### D. World State & Events (12 files, ~1500 lines)

**Status: Core tracking functional, consequence propagation missing**

**What Works Well:**
- EventBus with 17 signal types covers all game events
- WorldState tracks factions, relationships, quests, flags with JSON persistence
- WorldEvents validates memories against canonical facts (anti-hallucination)
- WorldKnowledge provides geographic knowledge scoping (NPCs only know local area)
- StoryFlags (25 flags) with NPC-specific context hints

**Critical Gap: Consequence Graph**
```
Current: Quest completion → sets flags → ??? (nothing cascades)
Needed:  Quest completion → sets flags → ConsequenceGraph evaluates rules → triggers new quests, NPC reactions, world changes
```

**Unconnected Signals (defined but never used):**
- `npc_witnessed_event` — never emitted or listened to
- `player_action` — never emitted; WorldState handler is empty
- `item_interacted` — never emitted
- `faction_reputation_changed` — never emitted; faction system tracked but unused

**Trade-off Analysis:**
- EventBus pub-sub vs direct calls: **EventBus is correct** — clean decoupling
- In-memory dicts + JSON vs database: **JSON is fine** for single-player JRPG
- Natural language quest detection vs explicit choices: **NL detection is the game's differentiator** — but IntentDetector is keyword-based and brittle

**Dual Source of Truth Risk:**
- NPC relationships tracked in BOTH WorldState AND BaseNPC
- Can desync on save/load — need to pick one authority

---

### E. Quest System (7 files, ~1100 lines)

**Status: Clean state machine with natural language detection**

**What Works Well:**
- QuestManager with full lifecycle (UNAVAILABLE → AVAILABLE → ACTIVE → COMPLETED/FAILED)
- IntentDetector analyzes Claude responses for quest-relevant intents
- Quest context injected into NPC prompts (NPCs hint toward objectives)
- Multi-ending support per quest
- 2 sample quests well-designed for conspiracy arc

**Gaps:**
- IntentDetector is keyword-based — "sword" triggers "weapons" topic even in "I don't have a sword"
- No compound objective conditions (can't require "flag X AND relationship > 50")
- No time-based conditions or urgency mechanics
- Quest failure paths defined but never triggered
- `required_memories` field in QuestResource never enforced
- Only 2 sample quests — limited test coverage

---

### F. World Physics & Scenes (38+ files, 26 scenes)

**Status: 96% of PLAN.md implemented, with bugs**

**What Works Well:**
- All 8 collision layers defined and functional
- 4 base world classes (WorldSolid, WorldObstacle, WorldProp, Interactable) complete
- SceneManager autoload with fade transitions, spawn points, NPC filtering
- 3 complete interior scenes (Gregor's shop, tavern, blacksmith)
- Location resources with data-driven configuration

**Bugs Found:**
1. Player collision_mask = 14 (wrong) should be 28 — may break door interactions
2. `thornhaven_blacksmith.tres` location resource missing from filesystem
3. Trees are visual only — no WorldObstacle collision (walk through trees)
4. No boundary walls at map edges (player can walk off screen)
5. NPC `home_location` not explicitly set in scene files

**Plan vs Reality: 25/26 tasks complete (96%)**

---

### G. Asset Generation (33 files, multi-backend pipeline)

**Status: Functional with untested backends**

**Architecture:**
- 3 backends: Recraft (production-ready code, disabled), PixelLab (active, complex), LocalSD (scaffolding)
- Mock generator for development testing
- WorldSettings resource for consistent prompt construction
- Three-tier loading: pre-generated → runtime cache → API generation
- Asset caching via JSON dictionary

**Assets on Disk:**
- 7 buildings, 25+ props, 5 characters with full rotations/animations, path endpoints, shadows
- Tilesets: directory structure only (no actual PNGs)

**Gaps:**
- Recraft backend disabled/untested despite being production-ready code
- Tileset pipeline incomplete (no real tilesets, converter untested)
- Character animation pipeline untested end-to-end
- Backend selection has race condition (`call_deferred` may lose first request)
- No generation cancellation — API calls continue after game closes
- 31 debug/test files with no CI framework

---

### H. UI Systems (10 files)

**Status: Dialogue works, quest UI scaffolded but unwired**

**Working:**
- DialogueUI with game pause, NPC name, text display, player input
- Voice integration (ElevenLabs streaming + HTTP with tone modulation)
- Debug console with draggable window, command history
- 3 debug overlays (interaction, layout, navigation)

**Scaffolded but Not Wired:**
- QuestJournal (3 tabs, detail panel) — needs QuestManager signals
- QuestNotifications (toast system with animations) — needs QuestManager signals

**Missing:**
- No branching dialogue display (player choices not shown)
- No HUD elements (health, inventory, minimap)
- No quest tracker on main screen

---

### I. Voice Synthesis (4 files)

**Status: Framework complete, needs integration testing**

**What Works:**
- ElevenLabs streaming client (WebSocket) and HTTP fallback
- 16+ tone modifiers (warmly, angrily, nervously, etc.)
- Per-NPC voice mapping (young_female, middle_aged_male, gruff_male, etc.)
- Audio caching by text hash

---

### J. Documentation Health

**28 docs audited. Key findings:**

| Status | Count | Examples |
|--------|-------|---------|
| Accurate | 8 | IMPLEMENTATION_COMPLETE, PHASE1_PERSONALITY_ANCHORING, TESTING |
| Partially Accurate | 6 | PROJECT_OVERVIEW, DEVELOPMENT_PLAN, STORY_NARRATIVE |
| Aspirational (claims complete, isn't) | 8 | DYNAMIC_TRAIT_EVOLUTION, CHROMADB_STATE_SYSTEM, pathway_planning |
| Outdated | 3 | NEXT_STEPS, DEMO_AGENT_GROWTH |
| Archived (correctly) | 3 | PHASE_6_PLAN, FUTURE_WORK |

**Top 5 Doc-Reality Mismatches:**
1. `DYNAMIC_TRAIT_EVOLUTION.md` — 800 lines describing non-existent functions
2. `PLAN.md` — Physics architecture 96% done but claims like "SceneManager autoload" already existed
3. `CHROMADB_STATE_SYSTEM.md` — NPC death/resurrection API described but `store_npc_state()` works differently than documented
4. `pathway_planning.md` — Path network system not implemented (~10% of design exists)
5. `IMPLEMENTATION_COMPLETE.md` — Claims "production ready" but missing methods from own spec

---

## Cross-System Integration Health

### Signal Flow (What's Connected)

```
BaseNPC.respond_to_player() → npc_response_generated → QuestManager (quest discovery) ✅
BaseNPC._apply_relationship_delta() → npc_relationship_changed → QuestManager (objective completion) ✅
WorldState.set_world_flag() → world_flag_changed → StoryItem (visibility) ✅
WorldState.set_world_flag() → world_flag_changed → QuestManager (availability) ✅
```

### Signal Flow (What's Broken/Missing)

```
player_action → WorldState._on_player_action() → EMPTY HANDLER ❌
npc_witnessed_event → NEVER EMITTED, NEVER LISTENED ❌
item_interacted → NEVER EMITTED ❌
faction_reputation_changed → NEVER EMITTED ❌
NPC death → NO EventBus event → other NPCs don't know ❌
Quest completion → flags set → NO consequence cascade ❌
```

### Integration Health Score: 6.4/10
- Decoupling via EventBus: 8/10
- Error handling: 5/10 (many silent failures)
- Data consistency: 6/10 (dual relationship tracking, no locks)
- Resource loading: 5/10 (hardcoded paths, no validation)

---

## Priority Matrix: What to Fix First

### Tier 1: Critical (Fix Before Any New Features)

| # | Item | System | Effort | Impact |
|---|------|--------|--------|--------|
| 1 | Fix player collision_mask (14→28) | Physics | 5 min | Doors may not work |
| 2 | Create thornhaven_blacksmith.tres | Physics | 10 min | Missing location resource |
| 3 | Apply personality sensitivity modifiers | NPC AI | 30 min | All NPCs feel same |
| 4 | Add ChromaDB connection timeout (5s) | Memory | 1 hr | Game hangs if ChromaDB down |
| 5 | Delete dead code (chroma_bridge.py, test_chroma_direct.py, dialogue_manager.gd) | Cleanup | 15 min | Reduces confusion |

### Tier 2: High Priority (This Sprint)

| # | Item | System | Effort | Impact |
|---|------|--------|--------|--------|
| 6 | Implement ConsequenceGraph | World State | 2-3 days | Enables cascading world reactions |
| 7 | Implement NPC event propagation | World State | 1-2 days | NPCs learn about world events |
| 8 | Add memory consolidation | Memory | 1 day | Prevents performance degradation |
| 9 | Add boundary walls to game_world | Physics | 30 min | Player can't walk off map |
| 10 | Add tree collision shapes | Physics | 30 min | Trees block movement |
| 11 | Add doc status tags ([IMPLEMENTED]/[ASPIRATIONAL]) | Docs | 2 hrs | Prevents confusion |

### Tier 3: Important (Next Sprint)

| # | Item | System | Effort | Impact |
|---|------|--------|--------|--------|
| 12 | Secret denial/coercion mechanics | NPC AI | 2 days | Enables detective gameplay |
| 13 | Romance dialogue branching | NPC AI | 1-2 days | Enables romance playthroughs |
| 14 | Unify relationship tracking (pick one authority) | Integration | 1 day | Prevents state desync |
| 15 | Strengthen IntentDetector (semantic, not just keywords) | Quests | 2 days | Reduces false positives |
| 16 | Verify Recraft backend integration | Assets | 1 day | Backup generation path |
| 17 | Complete tileset pipeline | Assets | 2 days | Enables terrain system |
| 18 | Wire QuestManager to Journal/Notifications | UI | 1 day | Quest UI becomes functional |

### Tier 4: Nice to Have (Backlog)

| # | Item | System | Effort | Impact |
|---|------|--------|--------|--------|
| 19 | Response streaming (show Claude output incrementally) | Dialogue | 1 day | Better UX feel |
| 20 | NPC schedule system (time-based location changes) | World | 2 days | NPCs feel alive |
| 21 | Village gossip/rumor propagation | NPC AI | 3 days | Village feels connected |
| 22 | Branching dialogue UI (player choices) | UI | 2 days | RPG staple |
| 23 | Soft personality trait drift | NPC AI | 2 days | NPCs show growth |
| 24 | Content-addressed asset cache | Assets | 1 day | Better cache management |
| 25 | Test framework + CI integration | Debug | 2 days | Regression detection |

---

## Architecture Risks for Phase 7+

### Phase 7 (Combat) Dependencies
- Needs: Health system, damage calculation, NPC combat AI
- Existing support: Collision layers 7 (projectile) reserved, NPC relationship → combat participation possible via 5D system
- Risk: No combat code exists. Fresh architecture needed. Must integrate with EventBus + relationship system.

### Phase 8 (Inventory/Trading) Dependencies
- Needs: Item management, shop interfaces, evidence items
- Existing support: StoryItem exists for evidence discovery, gift_given interaction type tracked
- Risk: No inventory system. Must integrate with quest objectives + NPC dialogue context.

### Phase 9 (Romance) Dependencies
- Needs: Romance state tracking, dedicated dialogue paths, endings
- Existing support: Romance thresholds in NPCPersonality, `is_romance_unlocked()` method, affection tracking
- Risk: No romance branching UI. System detects readiness but has no dialogue paths.

### Phase 10 (Multiple Endings) Dependencies
- Needs: Ending triggers, cutscene system, state aggregation
- Existing support: 25 story flags, quest completion_flags, possible_endings in QuestResource
- Risk: **Consequence graph (Tier 2 #6) is prerequisite** — endings require cascading flag evaluation.

### Phase 11 (Voice Synthesis) Dependencies
- Needs: ElevenLabs integration, per-NPC voice assignment, cost optimization
- Existing support: VoiceManager complete, streaming + HTTP clients, tone modulation, per-NPC mapping
- Risk: Lowest risk. Framework is 80% complete. Just needs integration testing.

---

## Debate-Worthy Decision Points

These are decisions that would benefit from multiple perspectives before committing:

1. **ConsequenceGraph Design:** Rule-based engine vs. event-sourcing vs. Petri net? This is the most impactful architectural decision remaining.

2. **Relationship Authority:** Should BaseNPC or WorldState own relationship dimensions? Current dual tracking will cause bugs.

3. **IntentDetector Strategy:** Keep keyword-based (fast, deterministic) or switch to LLM-based (accurate, expensive)? Or hybrid?

4. **Combat Architecture:** Turn-based (JRPG traditional) vs. real-time (Fable-like)? How does the 5D relationship system influence combat?

5. **Memory Consolidation Strategy:** Summarize old memories (lossy but compact) vs. archive to cold storage (lossless but complex)?
