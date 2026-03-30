# Implementation Definition: Land JRPG Tech Demo

> **Date:** 2026-03-29
> **Target:** Tech demo showcasing autonomous NPC agents + emergent narrative + living economy
> **Timeline:** 4-6 weeks
> **Team:** Solo developer + AI assistance
> **Milestone:** Playable demonstration of a living world where NPCs think, act, gossip, trade, and drive emergent stories

---

## What the Tech Demo Proves

A player walks into Thornhaven. NPCs are going about their day — Bjorn opens his forge, Mira serves breakfast at the tavern, Gregor nervously arranges his shop. As the player talks to people, builds trust, and explores, they discover that the village is under bandit extortion, that someone is an informant, and that secrets are everywhere.

But here's what makes it a tech demo: **the world moves without the player.** If they spend two game-days training with Elena, Aldric may have confronted a bandit patrol. Mira may have gossiped about Gregor's nervousness to Bjorn. Gregor may have raised his prices because a supply shipment was raided. The player discovers the aftermath of NPC decisions they didn't witness.

**Three things the demo must make viscerally obvious:**

1. **NPCs are alive.** They move, they think, they gossip, they make decisions. Talk to Mira on Day 1 and Day 5 — she references things that happened while you were away.

2. **Stories emerge.** The player doesn't follow a quest chain. They discover that Elena followed her father to the old mill because Elena's agent loop decided to investigate. A quest emerged from an NPC's autonomous action.

3. **The economy breathes.** Bjorn's iron costs more today because the trade route was raided. Gregor has items he shouldn't have. Prices reflect NPC decisions, not static tables.

---

## Scope: In vs Out

### IN (Must Have for Demo)

| System | Scope | Why |
|--------|-------|-----|
| **NPC Agent Loop** | 7 Tier 0 NPCs with full autonomous behavior | Core demo feature |
| **NPC Movement** | NPCs walk between locations on schedules | Visual proof of autonomy |
| **Gossip System** | InfoPacket propagation between NPCs | Shows information is alive |
| **Claude Escalation** | Complex decisions (secrets, alliances) via Bedrock | Shows AI reasoning |
| **Consequence Graph** | Flag cascades trigger world changes | Enables meaningful NPC actions |
| **Story Threads (4)** | Gregor's Bargain, Elena's Awakening, Mira's Cover, Aldric's Watch | Core narrative |
| **Quest Emergence** | 3-5 quests emerge from thread tension | Shows emergent narrative |
| **Basic Economy** | NPC-owned inventories, dynamic pricing, trading | Shows living economy |
| **Evidence Items** | Ledger, marked weapon — presentable to NPCs | Shows narrative-economy integration |
| **Dialogue Redesign** | Suggested responses, evidence presentation, thinking indicator | Playable conversation |
| **Basic HUD** | Health, interaction prompts, notifications | Minimum viable UI |
| **Python Sidecar** | FastAPI server for Bedrock + ChromaDB | Performance foundation |

### OUT (Deferred Post-Demo)

| System | Why Deferred |
|--------|-------------|
| Combat system | 10-14 weeks alone; demo focuses on social/narrative |
| Full skill system | Requires combat and crafting depth |
| Romance paths | Content-heavy, needs quest system maturity |
| Multiple endings | Requires all systems converging |
| Voice synthesis | Polish layer; framework already exists |
| Multi-settlement | One village is enough for demo |
| Procedural world gen | Manual layout is fine for one village |
| Advanced crafting | Relational crafting needs more NPC content |
| Tier 1-3 NPC agents | Focus on 7 Tier 0 NPCs being excellent |
| Full investigation board | Simplified version sufficient for demo |

---

## Architecture: What Gets Built

### The Critical Path

```
Week 1                Week 2              Week 3              Week 4              Week 5-6
┌──────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ FOUNDATIONS│    │ NPC AGENCY   │    │ INFORMATION  │    │ EMERGENT     │    │ ECONOMY +    │
│           │    │              │    │              │    │ NARRATIVE    │    │ POLISH       │
│ Fix bugs  │───▶│ Schedules    │───▶│ InfoPackets  │───▶│ 4 threads    │───▶│ Items/trade  │
│ Consequence│    │ Goals        │    │ Gossip       │    │ Emergence    │    │ Evidence     │
│ Graph     │    │ Agent loop   │    │ Claude escal.│    │ Quest gen    │    │ UI polish    │
│ Event prop│    │ Movement     │    │ Secrets      │    │ Thread mgr   │    │ Demo flow    │
│ Sidecar   │    │ Navigation   │    │              │    │              │    │              │
└──────────┘    └──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
```

### Week 1: Foundations (Unblock Everything)

**Day 1-2: Critical Bug Fixes**
- [ ] Fix player collision_mask (14→28) — 5 min
- [ ] Fix NPC ID bug in sample_quests.gd (gregor_001→gregor_merchant_001) — 5 min
- [ ] Create res://resources/quests/ directory — 1 min
- [ ] Create thornhaven_blacksmith.tres location resource — 10 min
- [ ] Apply personality sensitivity modifiers in base_npc.gd — 30 min
- [ ] Add ChromaDB connection timeout (5s) — 1 hr
- [ ] Delete dead code (chroma_bridge.py, test_chroma_direct.py, dialogue_manager.gd) — 15 min

**Day 2-3: Consequence Graph**
- [ ] Create `scripts/world_state/consequence_graph.gd`
- [ ] Design: Rule-based engine (flag change → evaluate rules → execute effects → cascade)
- [ ] Data structure: `{trigger_flag: [{condition, action, targets, delay}]}`
- [ ] Register rules for core story flags (gregor_exposed → investigation starts)
- [ ] Connect to EventBus.world_flag_changed signal
- [ ] Test: Set a flag → verify cascade fires

**Day 3-4: NPC Event Propagation**
- [ ] Wire the existing `npc_witnessed_event` signal (defined but never used)
- [ ] Add listeners in BaseNPC: when event occurs at NPC's location, call `witness_event()`
- [ ] Events propagate to NPCs at same location immediately
- [ ] Events propagate to NPCs at same settlement within 1 game-day
- [ ] Test: Gregor does something → Mira (same village) learns about it next day

**Day 4-5: Python Sidecar**
- [ ] Create FastAPI server replacing chroma_cli.py subprocess pattern
- [ ] Endpoints: `/think` (Bedrock inference), `/memory` (ChromaDB), `/batch` (Tier 2-3)
- [ ] boto3 bedrock-runtime client with Sonnet + Haiku model IDs
- [ ] ChromaDB PersistentClient (persistent connection, no subprocess)
- [ ] Update chroma_client.gd to use HTTP instead of OS.execute()
- [ ] Update claude_client.gd to route through sidecar
- [ ] Test: Full dialogue round-trip through sidecar

### Week 2: NPC Agency (NPCs Come Alive)

**Day 1-2: Movement Foundation**
- [ ] Add NavigationRegion2D to game_world.tscn (baked from terrain + obstacle outlines)
- [ ] Add NavigationAgent2D as child of BaseNPC scene
- [ ] Implement `_physics_process` movement in base_npc.gd (get path, follow, move_and_slide)
- [ ] Add basic animation state (idle, walking) with direction
- [ ] Add steering behaviors: arrive (decelerate near target), wander (idle variation)
- [ ] Enable ORCA avoidance (NPCs don't overlap)
- [ ] Test: NPC walks from point A to point B without hitting buildings

**Day 2-3: Schedules**
- [ ] Add `daily_schedule: Array[Dictionary]` to NPCPersonality
- [ ] Define schedules for all 7 NPCs (e.g., Gregor: morning→shop, noon→square, evening→shop, night→home)
- [ ] Create `ScheduleManager` or timer in BaseNPC that checks schedule each time period
- [ ] Add `time_period_changed` signal (dawn/morning/noon/evening/night)
- [ ] Add day/night timer (configurable game-day length)
- [ ] NPCs move to scheduled locations when time changes
- [ ] Test: Fast-forward time → NPCs relocate

**Day 3-4: Goal System**
- [ ] Add `goals: Array[Dictionary]` to NPCPersonality for all 7 NPCs
- [ ] Define 2-3 goals per NPC (from personality audit: Gregor wants to protect Elena, Aldric wants to investigate, etc.)
- [ ] Create `NPCAgentLoop` node/script attached to BaseNPC
- [ ] Implement 5-step loop: Perceive → Evaluate Goals → Select Action → Execute → Reflect
- [ ] Define action space: move_to, set_flag, wait, continue_routine
- [ ] Agent tick timer: every 30-60 seconds
- [ ] Rule-based action selection (no Claude yet — that's Week 3)
- [ ] Test: NPC autonomously decides to move to a location based on goal

**Day 5: Integration**
- [ ] NPC actions stored in WorldEvents canonical log
- [ ] NPC actions stored in RAGMemory as memories
- [ ] NPC actions emit EventBus signals
- [ ] Actions affect story thread tensions (ThreadManager — placeholder for Week 4)
- [ ] Test: NPC takes action → appears in their memory → they reference it in dialogue

### Week 3: Information Flow (The Village Gossips)

**Day 1-2: InfoPacket System**
- [ ] Define InfoPacket data structure (content, source, category, confidence, spread_count)
- [ ] Add `information_buffer: Array` to BaseNPC
- [ ] Add `receive_information(packet)` and `get_shareable_info(for_npc)` to BaseNPC
- [ ] Add `npc_communicated` signal to EventBus
- [ ] Gossip rules: extraversion-based spread probability, confidence decay per hop
- [ ] NPCs at same location exchange info during agent ticks
- [ ] Test: Tell Mira something → she tells Bjorn → Bjorn mentions it to player

**Day 3-4: Claude Escalation (AWS Bedrock)**
- [ ] Define escalation criteria: secret-sharing, alliance/betrayal, novel situations
- [ ] Create short structured decision prompt (~800 tokens for Sonnet, ~500 for Haiku)
- [ ] Route through Python sidecar → Bedrock InvokeModel
- [ ] Validate response: action must be in allowed action space
- [ ] Fallback: if Claude returns invalid action, use rule-based default
- [ ] Test: NPC faces complex decision (should Mira share what she knows?) → Claude decides

**Day 5: Secret Mechanics**
- [ ] Connect secret unlocking to agent loop (NPC checks: should I share this secret with this NPC?)
- [ ] 3-5 critical secrets wired to gossip system (Gregor's deal, Mira's knowledge, Bjorn's weapons)
- [ ] Secret confidence tracking (how sure is the NPC of this information?)
- [ ] Test: Build trust with Mira → she reveals secret → gossip may spread it

### Week 4: Emergent Narrative (Stories Come Alive)

**Day 1-2: Story Threads**
- [ ] Create `StoryThread` resource/data class
- [ ] Create `ThreadManager` singleton
- [ ] Define 4 core threads with tension values, driving NPCs, key flags:
  1. The Merchant's Bargain (Gregor/Varn)
  2. The Daughter's Awakening (Elena)
  3. The Grieving Widow (Mira)
  4. The Failing Watch (Aldric)
- [ ] Tension update rules: NPC actions, world events, time passage → tension changes
- [ ] Thread states: simmering → escalating → crisis → breaking point
- [ ] Test: Play for 10 game-days → observe thread tensions rising

**Day 3-4: Quest Emergence**
- [ ] Create 3-5 quest templates (reusable patterns):
  1. "Investigate NPC" — build trust, discuss topic, verify with corroboration
  2. "Present Evidence" — find item, choose who to show it to
  3. "Witness Event" — be at location when NPC does something
  4. "NPC Request" — NPC asks player for help (triggered by NPC goal)
  5. "Crisis Response" — thread reaches crisis, player must act
- [ ] Create `QuestEmergenceEngine` that evaluates templates against thread state
- [ ] Define 8-10 emergence rules (thread tension threshold → quest generated)
- [ ] Generated quests registered with existing QuestManager
- [ ] NPC context hints injected via existing ContextBuilder
- [ ] Test: Thread tension rises → quest appears → player can discover it through NPC dialogue

**Day 5: Mira Boss Duality**
- [ ] Implement dual-layer personality system
- [ ] Layer 1 (Cover): current mira_tavern_keeper.tres — default
- [ ] Layer 2 (Boss): new data block added to personality — activated when mira_boss_revealed flag set
- [ ] Agent loop uses Boss reasoning for decisions, Widow behavior for public actions
- [ ] Claude prompt switches personality layer based on flag state
- [ ] Test: Before reveal → Mira acts scared. Set flag → Mira's dialogue shifts to calculating

### Week 5-6: Economy + Demo Polish

**Day 1-3: Basic Economy**
- [ ] Create `ItemData` resource class (7 categories, quality tiers, weight)
- [ ] Create `PlayerInventory` (weight-based, category-filtered)
- [ ] Create `NPCInventory` (real items — Bjorn has iron because shipment arrived)
- [ ] Create 20-30 core items (weapons, materials, consumables, 3 evidence items)
- [ ] Create `EconomyManager` singleton (simplified: single settlement)
- [ ] Price formula: base_value × supply_modifier × relationship_discount × NPC_personality_markup
- [ ] Basic trade UI: conversational (NPC lists items, player selects, prices shown)
- [ ] Evidence items: ledger, marked weapon, Mira's testimony — presentable via dialogue
- [ ] Test: Buy from Bjorn → check price reflects relationship. Raid disrupts supply → prices change.

**Day 4-5: UI Polish**
- [ ] Basic HUD: health indicator, interaction prompts ("Press E to talk"), time-of-day, notifications
- [ ] Dialogue redesign: NPC portrait area, scrollable history, "thinking..." indicator, evidence presentation button
- [ ] Simplified investigation board: list of known threads, evidence collected, NPC relationships (not full pinboard — simplified for demo)
- [ ] Quest notifications: use existing toast system, wire to QuestEmergenceEngine
- [ ] Relationship feedback: "Bjorn trusts you more" type notifications on changes

**Day 6-7: Demo Flow & Testing**
- [ ] Define a "golden path" demo scenario: Player arrives → meets NPCs → discovers clues → witnesses NPC autonomous action → presents evidence → story thread escalates
- [ ] Ensure 10-15 minutes of compelling gameplay
- [ ] Test autonomous NPC behavior over 20+ game-days (accelerated time)
- [ ] Verify gossip propagation produces interesting dynamics
- [ ] Verify economy responds to NPC actions
- [ ] Fix edge cases, polish dialogue context injection

---

## Key Architectural Decisions (Resolved)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| ConsequenceGraph design | Rule-based engine | Simplest, most debuggable, 2-3 day implementation |
| Relationship authority | WorldState owns, BaseNPC caches | Prevents dual-source desync |
| NPC movement | Free-form via NavigationServer2D | Natural-feeling autonomous movement |
| World construction | Data-driven from THORNHAVEN_LAYOUT | Enables future procedural generation |
| IntentDetector | Keep keyword-based + Claude for ambiguous | Cost-effective for demo |
| Mira Boss duality | Flag-triggered personality layer switch | Clean separation, one Claude prompt swap |
| Python sidecar | FastAPI with Bedrock + ChromaDB | Eliminates subprocess overhead, enables batching |
| AI inference | AWS Bedrock (Sonnet for T0, Haiku for T1+) | IAM auth, batch API, CloudWatch monitoring |

---

## Cost Budget (Demo Period)

| Component | Model | Calls/Hour | Cost/Hour |
|-----------|-------|-----------|-----------|
| NPC dialogue (player-initiated) | Sonnet | 10-20 | ~$0.10-0.21 |
| NPC agent decisions (autonomous) | Sonnet (escalated) | 5-10 | ~$0.02-0.05 |
| NPC agent decisions (routine) | Rules | 60-120 | $0.00 |
| Gossip/secret decisions | Haiku | 5-10 | ~$0.005-0.01 |
| **Total** | | | **~$0.14-0.27/hr** |

Optimized with prompt caching: **~$0.10-0.20/hr**

A full demo playtest session (2 hours): **$0.20-0.40**

---

## Success Criteria

The demo succeeds if a player can:

1. **Observe NPC autonomy:** See NPCs in different locations at different times. Return to the tavern and find Mira talking about something that happened while the player was away.

2. **Discover emergent quests:** Without being told to investigate Gregor, learn about the conspiracy through NPC gossip, overheard conversations, and building trust. A quest appears because Elena decided to follow her father, not because the player triggered a scripted event.

3. **Experience economic consequences:** Buy something from Bjorn. Come back later, and the price has changed because a trade shipment was raided. Notice that Gregor has unusual items. The economy tells a story.

4. **Present evidence and see authentic reactions:** Find the ledger. Show it to different NPCs. Each reacts according to their personality, trust level, and relationship — Claude generates unique responses, not scripted dialogue.

5. **Feel like the world is bigger than them:** The sense that things are happening beyond their view. NPCs have lives. Information flows. The village isn't waiting for the player to act — it's living.

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Bedrock integration takes longer than expected | Medium | Delays Week 1 | Can fall back to direct Anthropic API initially |
| NPC agent loop creates degenerate behavior | Medium | Breaks demo | Action validation + budget limits per tick |
| Claude costs exceed budget | Low | Financial | Hard cap on calls/hour, Haiku for non-critical |
| Gossip system creates nonsensical rumors | Medium | Breaks immersion | Confidence threshold: NPCs only act on info > 0.5 confidence |
| 4-week timeline is too aggressive | High | Demo incomplete | Prioritize: NPC agency (W1-2) is the minimum demo even without economy |
| NavigationAgent2D pathfinding issues | Low | NPCs get stuck | Fallback to waypoint-based movement |

---

## Minimum Viable Demo (If Timeline Compresses to 3 Weeks)

If only 3 weeks, cut to:

| Week | Focus | What You Lose |
|------|-------|--------------|
| 1 | Foundations + NPC movement | Nothing — still critical path |
| 2 | Agent loop + gossip + Claude escalation | Merge Weeks 2-3, less testing |
| 3 | 2 story threads + basic economy + polish | Fewer threads, simpler economy |

**Still shows:** NPCs thinking, moving, gossiping, and making decisions. Player discovers emergent quests. Basic trading with dynamic prices. That's enough for a compelling tech demo.
