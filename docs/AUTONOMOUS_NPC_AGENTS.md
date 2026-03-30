# Autonomous NPC Agents - Deep Dive Research

> **Date:** 2026-03-29
> **Focus:** Autonomous AI-powered NPCs that influence story and world
> **Sources:** Codebase analysis + Stanford Generative Agents + industry patterns

---

## Vision

Transform Land's NPCs from **reactive dialogue partners** (respond when player talks) into **autonomous agents** that have goals, make decisions, share information, and shape the narrative — even when the player isn't watching.

---

## Architecture: Universal AI Agency with Tiered Models

### Core Principle

**Every NPC is an autonomous AI agent.** This is the game's identity, not a feature reserved for the main cast. The baker thinks. The off-screen mayor reasons. The bandit faction strategizes. Tiers control the *model*, *frequency*, and *prompt depth* — never whether an NPC gets to reason.

### Infrastructure: AWS Bedrock

All Claude inference runs through **AWS Bedrock**, not direct Anthropic API calls.

**Why Bedrock:**
- **IAM authentication** — no API keys in `.env` for Claude; use AWS credentials/roles
- **Model selection via model ID** — switch Sonnet/Haiku per request, same SDK
- **Batch Inference** — submit Tier 2-3 game-day decisions as a batch job (up to 50% cheaper)
- **Provisioned Throughput** — option for fixed-cost, unlimited calls at high volume (ideal for scaling to 100+ agents)
- **CloudWatch metrics** — monitor cost, latency, and token usage per tier automatically
- **Cross-region inference** — higher rate limits for burst scenarios (all 7 Tier 0 NPCs thinking simultaneously)
- **Guardrails** — Bedrock Guardrails can enforce NPC behavior boundaries at the API level (prevent NPCs from generating inappropriate content)

**Bedrock Model IDs:**
- Tier 0: `anthropic.claude-sonnet-4-6-20250929-v1:0` (or latest Sonnet)
- Tier 1-3: `anthropic.claude-haiku-4-5-20251001-v1:0` (or latest Haiku)

**Integration pattern:**
```
Godot (GDScript) → Python sidecar (FastAPI) → boto3 bedrock-runtime → Claude models
                                              └→ Batch jobs for Tier 2-3 game-day ticks
```

The Python sidecar replaces the current `chroma_cli.py` subprocess pattern with a persistent local server that holds both the ChromaDB client AND the Bedrock client, eliminating per-call subprocess overhead.

### Why Tiered Models?

| Tier | Model | Think Frequency | Cost/Hour (Bedrock on-demand) |
|------|-------|----------------|-------------------------------|
| Tier 0 (Story NPCs, 7-12) | Sonnet via Bedrock | Every 30-60s | ~$0.50-1.05 |
| Tier 1 (Ambient NPCs, 10-25) | Haiku via Bedrock | Every 2-5 min | ~$0.07-0.17 |
| Tier 2 (Off-Screen NPCs, 20-50) | Haiku via Bedrock Batch | Every game-day | ~$0.005-0.02 |
| Tier 3 (Factions, 5-15) | Haiku via Bedrock Batch | Every game-day | ~$0.002-0.004 |
| **Total (42-102 agents)** | | | **$0.58-1.25/hr** |

With prompt caching + Bedrock Batch + Provisioned Throughput: **~$0.35-0.80/hr optimized.**

The difference between this and a rules-only approach: every entity in the world makes decisions that feel *reasoned*, not *random*. The baker mentions something because Haiku decided it was relevant. The bandit faction adapts because Haiku weighed the situation. This is what makes the game's world feel alive.

### The Agent Loop (runs every 30-60 game-seconds per NPC)

```
1. PERCEIVE ─── Gather beliefs about the world
   ├── WorldState: flags, quests, factions
   ├── WorldKnowledge: locations, establishments, NPCs
   ├── RAGMemory: recent events, stored info
   ├── Nearby NPCs: who's here, their state
   └── Information buffer: new gossip to process

2. EVALUATE ─── Score each goal by urgency
   ├── Persistent goals (from NPCPersonality.goals)
   ├── Reactive goals (from recent events)
   ├── Social goals (from relationships + info received)
   └── Each goal: utility score + preconditions + deadline

3. SELECT ─── Pick highest-utility valid action
   ├── Simple actions → execute immediately (rules)
   └── Complex actions → escalate to Claude

4. EXECUTE ─── Perform the action
   ├── Emit EventBus signals
   ├── Update WorldState/WorldKnowledge
   ├── Store in RAGMemory + WorldEvents
   └── Notify affected NPCs

5. REFLECT ─── Update internal state (periodic, not every tick)
   ├── Store outcome in memory
   ├── Adjust goal priorities
   └── Generate higher-order observations (reflections)
```

### Bedrock Call Routing

All LLM calls go through a Python sidecar (FastAPI) that manages the Bedrock client:

```
Godot (GDScript)
  │
  ├─ HTTP POST localhost:8080/think    → Sidecar → bedrock-runtime InvokeModel (Sonnet or Haiku)
  ├─ HTTP POST localhost:8080/dialogue → Sidecar → bedrock-runtime InvokeModel (Sonnet)
  ├─ HTTP POST localhost:8080/batch    → Sidecar → bedrock-runtime CreateModelInvocationJob (Haiku batch)
  └─ HTTP POST localhost:8080/memory   → Sidecar → ChromaDB PersistentClient
```

The sidecar replaces `chroma_cli.py` (subprocess per call) with a persistent server holding both ChromaDB and Bedrock clients. Auth is via AWS IAM credentials (no API keys in game config).

### Claude Escalation Criteria

Send to Sonnet (via Bedrock) ONLY when:
- Decision involves **secret-sharing** (should I tell X about Y?)
- Decision involves **betrayal/alliance** (which side do I choose?)
- NPC has **conflicting goals** (protect Elena vs. maintain business)
- **Novel situation** with no rule coverage
- Must **generate natural language** (composing a message, deciding gossip content)

### Claude Decision Prompt (Short, ~800 tokens)

```
You are [NPC Name]. Choose ONE action.

PERSONALITY: [2-3 sentences]
GOALS: [current goal list with priorities]
SITUATION: [what triggered this decision]
RELATIONSHIPS: [relevant NPCs + trust levels]
AVAILABLE ACTIONS:
1. share_secret("ledger_exists", target="aldric") - Risk: Gregor exposed
2. stay_silent() - Risk: bandits continue unchecked
3. hint_vaguely(target="aldric") - Moderate risk, preserves deniability

JSON: {"action": "action_id", "reason": "brief", "details": {}}
```

---

## NPC Action Space

| Action | WorldState Impact | EventBus Signal | Claude? |
|--------|------------------|-----------------|---------|
| `move_to(location)` | Updates npc_locations | `npc_moved` | No |
| `follow_schedule()` | Updates npc_locations | `npc_moved` | No |
| `set_flag(flag, value)` | Sets world flag | `world_flag_changed` | No |
| `spread_info(packet, target)` | Adds to target's memory | `npc_communicated` | No* |
| `share_secret(secret, target)` | Adds to target's memory | `npc_communicated` | **Yes** |
| `initiate_quest(quest_id)` | Sets prerequisite flags | `quest_discovered` | No |
| `block_quest(quest_id)` | Clears prerequisite flags | `world_flag_changed` | No |
| `form_alliance(npc_id)` | Updates social graph | `npc_alliance_formed` | Sometimes |
| `betray_alliance(npc_id)` | Updates social graph + trust | `npc_alliance_broken` | **Yes** |
| `confront_npc(npc_id, topic)` | Triggers NPC-NPC exchange | `npc_confrontation` | **Yes** |
| `create_event(description)` | Registers in WorldEvents | `world_event` | Sometimes |
| `adjust_prices(item, mult)` | Updates economy state | `economy_changed` | No |
| `wait() / continue_routine()` | Nothing | None | No |

*Spreading common gossip is rule-based. Deciding WHAT to share or whether to reveal sensitive info requires Claude.

---

## Cross-NPC Communication Protocol

### Information Model (InfoPacket)

```
{
  "id": String,               # Unique identifier
  "content": String,           # What the information is
  "source_npc": String,        # Who originated it
  "category": String,          # "fact" | "rumor" | "secret" | "gossip" | "warning"
  "confidence": float,         # 0.0-1.0 (degrades with each retelling)
  "timestamp": float,          # When created
  "spread_count": int,         # How many times passed along
  "restricted_to": Array,      # NPC IDs allowed to know (empty = public)
}
```

### Gossip Propagation Rules

| Factor | Effect |
|--------|--------|
| `trait_extraversion` > 50 | 60% chance to gossip per tick |
| `is_secretive` = true | 10% chance to gossip |
| NPCs in same location | Can exchange info directly |
| Mira (tavern keeper) | Natural gossip hub — talks to everyone |
| Each retelling | `confidence -= 0.15`, `spread_count += 1` |
| After 3+ hops | Content prefixed with "I heard that..." |
| Contradictory info received | Confidence halved on both versions |
| High-importance + multiple sources | Confidence reinforced |
| Age > 5 game-days | Fades from active consideration |

### Secret Sharing Decision Tree

```
NPC considers sharing secret with target_npc:

1. Is secret in unbreakable_secrets? → NEVER share
2. Is secret restricted_to specific NPCs? → Only share with those NPCs
3. Is NPC.is_secretive? → Double the trust threshold
4. Is trust(target_npc) >= secret.unlock_trust? → Eligible
5. Would sharing serve a current goal? → Weight toward sharing
6. Would sharing endanger source NPC? → Weight against sharing
7. AMBIGUOUS? → Escalate to Claude for decision
```

### Social Network Graph

```
Thornhaven Social Network:

    Gregor ──(family, trust:95)── Elena
       │                            │
  (business, trust:80)         (friendly, trust:40)
       │                            │
    Bjorn ──(neighbors, trust:60)── Mira (HUB)
       │                            │
  (wary, trust:30)            (surveillance, trust:20)
       │                            │
    Aldric ──(enemies, trust:5)──── Varn
       │
  (council, trust:70)
       │
    Mathias

Information flows fastest through Mira (tavern = social hub).
Varn is isolated — learns info only through Gregor (informant channel).
Elena learns about her father through player or through Mira.
```

---

## Lessons from Stanford Generative Agents (Smallville)

### What They Got Right (and Land should adopt)

1. **Memory Stream with Retrieval** — Recency + Importance + Relevance scoring. Land already has this via ChromaDB RAG. Well-aligned.

2. **Planning Horizon** — Agents generate daily plans each morning, recursively decomposed into action blocks. Without planning, agents act erratically. Land NPCs need this.

3. **Reflection** — Periodically, agents generate higher-order observations from accumulated memories. Example: multiple arguments → "I don't trust John anymore." This is what Land's DYNAMIC_TRAIT_EVOLUTION.md describes but hasn't implemented. Critical for NPC growth.

4. **Replan on Interruption** — When agents encounter unexpected events, they replan. Land NPCs should replan when world flags change or they receive new information.

### What They Got Wrong (and Land should avoid)

1. **LLM for every decision** — Thousands of dollars per simulation day. Land must use the hybrid approach.

2. **Unbounded memory** — No consolidation. Land already has the config for consolidation (7-day threshold) — just needs implementation.

3. **No gameplay loop** — Agents wandered and chatted without objectives. Land's quest system and mystery narrative provide the missing structure.

4. **No information asymmetry** — All agents had equal access to environmental observations. Land's mystery genre REQUIRES asymmetric knowledge (secrets, gossip confidence, restricted information).

---

## Cost Analysis

### Fully Optimized Cost Stack (AWS Bedrock)

All inference via AWS Bedrock. No direct Anthropic API calls.

| Layer | % of Decisions | Cost | Technique |
|-------|---------------|------|-----------|
| Sonnet (Bedrock on-demand) | ~10% | ~$0.50/hr | T0 dialogue, complex decisions, reflections |
| Haiku (Bedrock on-demand) | ~30% | ~$0.10/hr | T1 decisions/dialogue, T0 simple decisions |
| Haiku (Bedrock Batch) | ~10% | ~$0.02/hr | T2-T3 game-day ticks (batched, 50% cheaper) |
| Agent loop (no LLM) | ~50% | $0.00 | Schedule following, movement, simple gossip relay |
| **Total** | **100%** | **~$0.62/hr** | |

### Bedrock-Specific Optimizations

- **Prompt caching:** System prompts structured with static content first → ~90% cache hit rate on personality/world knowledge
- **Bedrock Batch Inference:** T2-T3 game-day decisions submitted as a single batch → up to 50% cheaper
- **Staggered ticks:** NPCs don't all decide simultaneously → smoother performance, avoids Bedrock throttling
- **Provisioned Throughput:** For production, consider fixed-cost throughput units → predictable pricing at scale
- **CloudWatch monitoring:** Per-tier cost tracking, latency dashboards, budget alarms
- **Cross-region inference:** Spread T0 burst calls across regions for higher throughput

### Projected Session Cost (Bedrock)

| Session Length | On-Demand | Optimized (cache + batch) |
|---------------|-----------|--------------------------|
| 1 hour | $0.62 | $0.40 |
| 2 hours | $1.24 | $0.80 |
| 4 hours | $2.48 | $1.60 |

---

## Integration with Existing Codebase

### BaseNPC Extensions

```gdscript
# New properties
var agent_timer: Timer
var current_goals: Array[Dictionary]
var current_plan: Array[Dictionary]
var information_buffer: Array[Dictionary]

# New methods
func _process_agent_tick()         # Agent loop (timer-driven)
func get_current_goals() -> Array  # Scored goal list
func get_available_actions() -> Array
func execute_action(action: Dictionary)
func receive_information(info_packet: Dictionary)
func get_shareable_info(for_npc_id: String) -> Array
```

### NPCPersonality Extensions

```gdscript
# New fields
@export var goals: Array[Dictionary]           # [{goal, priority, conditions}]
@export var daily_schedule: Array[Dictionary]   # [{time, action, location}]
@export var gossip_tendency: float = 0.5        # 0.0-1.0
@export var initiative_level: float = 0.5       # 0.0-1.0
```

### New EventBus Signals

```gdscript
# Agent actions
signal npc_action_taken(npc_id, action_data)
signal npc_moved(npc_id, from_location, to_location)
signal npc_communicated(from_npc, to_npc, info_packet)
signal npc_goal_changed(npc_id, old_goal, new_goal)
signal npc_alliance_formed(npc_a, npc_b)
signal npc_alliance_broken(npc_a, npc_b)
signal npc_confrontation(aggressor, target, topic)

# World simulation
signal time_period_changed(period)  # dawn/morning/noon/evening/night
signal economy_changed(location, change_data)
```

### WorldState Extensions

```gdscript
var npc_locations: Dictionary      # npc_id → location_id
var social_graph: Dictionary       # npc_id → {npc_id: {trust, frequency}}
var information_registry: Dictionary  # info_id → InfoPacket
var economy_state: Dictionary      # location → {item: {price, supply}}
```

### Quest Integration (Uses Existing System)

NPC-initiated quests work through existing QuestManager:
1. NPC agent decides it needs player's help
2. NPC sets `WorldState.set_world_flag("gregor_needs_help", true)`
3. QuestManager's `_on_flag_changed()` makes quest available
4. When player talks to Gregor, memory includes goal context
5. Claude generates dialogue that naturally introduces the quest

No new quest system needed — NPCs just manipulate the flags QuestManager already watches.

---

## Player Discovery of NPC Actions

When the player enters a location or talks to an NPC, they discover what happened:

1. **NPC greetings reference recent actions:**
   "While you were gone, I heard from Mira that bandits hit the northern trade route. I've been locking up early."

2. **Environmental changes:**
   - NPC positions changed (Gregor is at the tavern instead of his shop)
   - Shop states changed (prices higher, some items unavailable)
   - New items or notes appear in the world

3. **WorldEvents log feeds dialogue context:**
   ContextBuilder queries `WorldEvents.get_recent_events(npc_location)` and includes them in the system prompt.

---

## Phased Implementation Plan

### Phase 1: Schedules & Movement (1-2 weeks, $0 Claude cost)

- Add `npc_locations` tracking to WorldState
- Add `daily_schedule` to NPCPersonality
- Build `ScheduleManager` that moves NPCs by time-of-day
- Add `time_period_changed` signal and day/night timer
- Connect the existing `npc_witnessed_event` signal (defined but never used)
- NPCs appear at different locations throughout the day

**Result:** NPCs feel alive — they move around, have routines, aren't always standing in one spot.

### Phase 2: Goal System (1-2 weeks, $0 Claude cost)

- Add `goals` array to NPCPersonality
- Build `NPCAgentLoop` node that attaches to BaseNPC
- Implement 5-step loop with rule-based actions only
- Define action space (move, set_flag, wait, continue_routine)
- Store actions in WorldEvents and RAGMemory
- NPC actions appear in subsequent dialogue context

**Result:** NPCs pursue goals and take actions. Gregor hoards supplies when he hears about bandit activity. Aldric patrols more frequently.

### Phase 3: Information Sharing (1-2 weeks, minimal Claude cost)

- Implement InfoPacket model
- Add `npc_communicated` signal to EventBus
- Build gossip propagation (extraversion-based, confidence decay)
- Add `receive_information()` and `get_shareable_info()` to BaseNPC
- NPCs at same location exchange info based on social graph
- Mira as gossip hub — information flows through the tavern

**Result:** Information spreads through the village. Secrets can leak. The mystery becomes dynamic.

### Phase 4: Claude-Escalated Decisions (1-2 weeks, ~$0.20/hr)

- Build Claude escalation system (detect complex decisions)
- Design short structured decision prompt (~800 tokens)
- Secret-sharing decisions (should I tell Aldric about the ledger?)
- Alliance/betrayal decisions
- Novel-situation handling
- Response validation (reject impossible actions)

**Result:** NPCs make surprising, personality-driven decisions about secrets and alliances. The narrative becomes emergent.

### Phase 5: Player Integration (1 week)

- NPC greetings reference autonomous actions
- Quest prerequisites set/unset by NPC actions
- Player finds changed environments, moved NPCs, notes
- NPCs remember and discuss their autonomous actions
- NPC-NPC confrontations the player can witness

**Result:** The player discovers a living world that evolved while they were away.

### Phase 6: Reflection & Growth (1 week)

- Periodic reflection generation (when importance threshold crossed)
- Reflections stored as high-importance memories
- Personality trait drift from accumulated reflections
- Cross-NPC opinion formation ("I've been thinking... I don't trust Gregor anymore")

**Result:** NPCs evolve over time. Long-term play reveals character growth.

---

## Narrative Guardrails

To prevent NPCs from destabilizing the game world:

1. **Action budget:** Max 2 world-mutating actions per NPC per game-day
2. **Flag protection:** Critical story flags can only be set by specific NPCs or the player
3. **Revert mechanism:** If an NPC action would make a main quest uncompletable, block it
4. **Confidence threshold:** NPCs only act on information with confidence > 0.5
5. **Player primacy:** NPC actions create opportunities for the player, never solve the mystery for them

---

## Key Design Decisions (Need Your Input)

1. **Agent tick frequency:** real-time
2. **Gossip hub design:** Any high-traffic area.
3. **Secret leak consequences:** Flag change, NPCs re-plan
4. **NPC-NPC dialogue:** NPCs actually generate dialogue with each other.
5. **Reflection depth:**  Every game-day, as near real-time as possible.

---

## References

- Park et al., "Generative Agents: Interactive Simulacra of Human Behavior" (UIST 2023)
- Yao et al., "ReAct: Synergizing Reasoning and Acting in Language Models" (ICLR 2023)
- Shinn et al., "Reflexion: Language Agents with Verbal Reinforcement Learning" (NeurIPS 2023)
- Rao & Georgeff, "BDI Agents: From Theory to Practice" (ICMAS 1995)
- Inworld AI (https://inworld.ai/)
- NVIDIA ACE (https://developer.nvidia.com/ace)
- LimboAI for Godot 4 (https://github.com/limbonaut/limboai)
- AI Town open-source (https://github.com/a16z-infra/ai-town)
- AWS Bedrock Claude Integration (https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-anthropic-claude-messages.html)
- Bedrock Batch Inference (https://docs.aws.amazon.com/bedrock/latest/userguide/batch-inference.html)
- Bedrock Provisioned Throughput (https://docs.aws.amazon.com/bedrock/latest/userguide/prov-throughput.html)
- Claude Prompt Caching on Bedrock (https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html)