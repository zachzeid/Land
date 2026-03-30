# Emergent Narrative System

> **Date:** 2026-03-29
> **Core Principle:** The world has stories. NPCs drive them. The player discovers and shapes them. Quests are how the player engages with what's already happening.

---

## Philosophy

There is no "main quest." There is a world where 7+ NPCs pursue their own goals, and those goals collide with each other. The conspiracy isn't a scripted narrative — it's the consequence of Gregor choosing to protect Elena at any cost, Mira choosing to rule from the shadows, Aldric choosing to resist, and Mathias choosing to wait. The player walks into a system already in motion.

**Quests don't drive the narrative. NPC goals drive the narrative. Quests are the player's interface to what's already happening.**

---

## 1. Story Threads (Not Quest Chains)

A **story thread** is an ongoing narrative tension driven by one or more NPCs pursuing conflicting goals. Threads exist whether or not the player engages with them. They advance through NPC autonomous actions (agent loop ticks). The player can discover, accelerate, redirect, or resolve threads.

### Thread Definition

```
StoryThread:
  id: String                    # "gregors_deal"
  name: String                  # "The Merchant's Bargain"
  driving_npcs: Array[String]   # NPCs whose goals fuel this thread
  tension: float                # 0.0-1.0 (how close to crisis)
  state: String                 # "simmering" | "escalating" | "crisis" | "resolved"
  key_flags: Array[String]      # Flags that track this thread's progress
  discovery_difficulty: float   # How hard for the player to stumble onto this
  intersects_with: Array[String]  # Other thread IDs this connects to
```

### The Living Threads of Thornhaven

#### Thread 1: The Merchant's Bargain
**Driving NPCs:** Gregor, Varn
**Tension source:** Gregor's deal with the bandits — weapons, intelligence, and supplies in exchange for Elena's safety
**What happens autonomously:**
- Gregor meets Varn monthly at the old mill (routine)
- Gregor accumulates gold for Elena's escape (goal: protect Elena)
- If tension rises (player investigation, Aldric's suspicion): Gregor becomes more anxious, makes mistakes
- If unchecked: Gregor eventually flees with Elena, abandoning village
**Player discovery:** Notice Gregor's prosperity while others suffer. Overhear his nervousness. Find the ledger. Follow him to the mill.
**Key flags:** ledger_found, gregor_bandit_meeting_known, gregor_confession_heard, gregor_confronted, gregor_exposed, gregor_redemption_path

#### Thread 2: The Grieving Widow
**Driving NPCs:** Mira, (secretly: her as The Boss)
**Tension source:** Mira knows Gregor is the informant but is "too afraid" to speak. In reality, she orchestrated it all.
**What happens autonomously:**
- Mira runs her failing tavern (cover)
- She drops increasingly desperate hints to anyone who shows strength (testing for recruitable allies or threats)
- She monitors all intelligence flowing through the tavern (gossip hub)
- If tension rises: She either withdraws deeper into cover or begins actively manipulating events
- Her "grief" for Marcus intensifies under pressure (the question: is any of it real?)
**Player discovery:** Notice Mira knows too much. Her "hints" are too precise for someone merely fearful. Varn's behavior around her is deferential, not threatening.
**Key flags:** marcus_death_learned, mira_testimony_given, mira_trusts_player, mira_boss_revealed

#### Thread 3: The Daughter's Awakening
**Driving NPCs:** Elena
**Tension source:** Elena suspects her father but can't face it. She's caught between loyalty and truth.
**What happens autonomously:**
- Elena practices sword fighting in secret (goal: freedom, adventure)
- She follows her father, notices his patterns
- Her suspicions grow with each anomaly she notices
- If another NPC reveals truth to her (gossip, confrontation): devastating crisis
- She may confront Gregor directly if tension reaches critical
**Player discovery:** See her practicing. Hear her ask pointed questions about her father. She confides if trust is high enough.
**Key flags:** elena_knows_about_father, elena_shown_proof, elena_romance_started
**Intersection:** Deeply entangled with Thread 1. Elena's awakening can shatter Gregor's carefully maintained arrangement.

#### Thread 4: The Unwitting Accomplice
**Driving NPCs:** Bjorn
**Tension source:** Bjorn's weapons bear his mark. They're being used against the people he cares about. He doesn't know.
**What happens autonomously:**
- Bjorn fills Gregor's weapon orders, takes pride in his craft
- He occasionally wonders why so many weapons, but trusts Gregor
- If evidence surfaces (marked weapons found after a raid): crisis of identity
- Once he learns truth: transforms from passive craftsman to active resistance
**Player discovery:** Notice the "B" mark on bandit weapons. Ask Bjorn about his orders. Show him proof.
**Key flags:** weapons_traced_to_bjorn, bjorn_truth_revealed, bjorn_allied
**Intersection:** Connects Thread 1 (Gregor's supply chain) to Thread 6 (the resistance). Bjorn is the bridge.

#### Thread 5: The Failing Watch
**Driving NPCs:** Aldric
**Tension source:** Aldric knows the village is compromised. He has weapons, patrol routes, a plan. He lacks proof, authorization, and numbers.
**What happens autonomously:**
- Aldric secretly gathers weapons (cache under old well)
- He maps bandit patrol routes during his "routine patrols"
- He grows increasingly desperate as the village suffers
- If tension peaks without resolution: he may attempt a premature strike (catastrophic)
- He recruits anyone who seems capable
**Player discovery:** Notice his urgency. See him patrolling at unusual hours. He sizes up the player as a potential recruit.
**Key flags:** aldric_has_evidence, aldric_ally, resistance_forming
**Intersection:** Connects to Thread 6 (village politics) and Thread 1 (needs proof about Gregor).

#### Thread 6: The Paralyzed Council
**Driving NPCs:** Mathias
**Tension source:** Mathias leads a council frozen by fear. He suspects Gregor but has no proof. He could authorize action but fears the consequences.
**What happens autonomously:**
- Mathias writes unanswered letters to the capital
- He broods over the village's decline
- He debates endlessly with council members
- If evidence arrives: he can finally act — authorize Aldric, allocate resources
- Without evidence: paralysis deepens until the village dies slowly
**Player discovery:** Attend council meetings. Hear Mathias's frustration. He's desperate for someone to bring him proof.
**Key flags:** mathias_informed, gregor_exposed
**Intersection:** This is the political lock on Thread 5. Mathias's authorization enables everything Aldric wants to do.

#### Thread 7: The Bandit Expansion
**Driving NPCs:** Varn, Iron Hollow Gang (Tier 3 faction)
**Tension source:** The bandits are growing bolder. Varn is ambitious. The current arrangement is stable but Varn wants more.
**What happens autonomously:**
- Bandits maintain extortion schedule
- Varn tests boundaries — more aggressive collection, more territory
- Varn builds support for eventual coup against The Boss
- If village resistance forms: bandits escalate — threats, examples, violence
- Varn is on a collision course with both the village AND his own leadership
**Player discovery:** Encounter bandit patrols. Hear reports of raids. Meet Varn directly.
**Key flags:** varn_confronted, iron_hollow_visited
**Intersection:** This is the external pressure driving ALL other threads. Without it, there's no conspiracy, no fear, no paralysis.

---

## 2. Thread Interaction Map

```
Thread 7: Bandit Expansion
    │ creates external pressure on all threads
    │
    ├───→ Thread 1: Merchant's Bargain (Gregor enables bandits)
    │         │
    │         ├───→ Thread 4: Unwitting Accomplice (Bjorn arms them)
    │         │         │
    │         │         └───→ Thread 5: Failing Watch (Aldric needs proof)
    │         │                   │
    │         │                   └───→ Thread 6: Paralyzed Council (Mathias needs evidence)
    │         │
    │         └───→ Thread 3: Daughter's Awakening (Elena suspects father)
    │
    └───→ Thread 2: Grieving Widow (Mira is actually The Boss)
              │
              └───→ [Hidden connection to Thread 7 — Mira controls it all]
```

**The hidden layer:** Threads 2 and 7 are secretly the same thread. The "Grieving Widow" and "Bandit Expansion" are both driven by Mira. This connection is invisible until the Boss reveal.

---

## 3. Thread Tension and Autonomous Escalation

Each thread has a **tension** value (0.0-1.0) that rises through NPC autonomous actions and world events:

### Tension Triggers (Examples)

| Event | Threads Affected | Tension Change |
|-------|-----------------|----------------|
| Player arrives in Thornhaven | All threads | +0.05 (new variable in system) |
| Player talks to Gregor about bandits | Thread 1 | +0.10 (Gregor gets nervous) |
| Aldric fails patrol, bandits spotted near village | Threads 5, 7 | +0.10 each |
| Player finds ledger | Threads 1, 3, 4, 5, 6 | +0.15-0.20 each |
| Mira drops a hint about Gregor | Threads 1, 2 | +0.10 each |
| Elena follows father to mill | Threads 1, 3 | +0.20 each |
| Varn makes aggressive collection | Thread 7 | +0.10 |
| Player builds trust with Aldric to 60 | Thread 5 | +0.15 |
| Nothing happens for 5 game-days | Threads 5, 6, 7 | +0.05 (frustration/desperation build) |

### Tension Thresholds

| Tension | State | What Happens |
|---------|-------|-------------|
| 0.0-0.3 | **Simmering** | Status quo. NPCs follow routines. Hints are subtle. |
| 0.3-0.6 | **Escalating** | NPCs take more autonomous action. Hints become overt. Mistakes happen. |
| 0.6-0.8 | **Crisis** | NPCs force confrontations. Secrets spill. Alliances form or break. |
| 0.8-1.0 | **Breaking Point** | Thread must resolve. NPCs take drastic action with or without player. |

### What "Breaking Point" Looks Like Per Thread

| Thread | Breaking Point | Autonomous Resolution (No Player) |
|--------|---------------|-----------------------------------|
| 1: Merchant's Bargain | Gregor's secret becomes known | Gregor flees with Elena. Village loses its merchant. |
| 2: Grieving Widow | Mira's cover is threatened | Mira either eliminates the threat or relocates operations. |
| 3: Daughter's Awakening | Elena discovers the truth | Elena confronts Gregor. Emotional devastation. She may flee alone. |
| 4: Unwitting Accomplice | Bjorn sees his marked weapon on a dead villager | Bjorn confronts Gregor. May turn violent. |
| 5: Failing Watch | Aldric's patience breaks | Premature assault on Iron Hollow. Peacekeepers slaughtered. |
| 6: Paralyzed Council | Mathias's health fails or village suffers major loss | Council disbands or makes desperate compromise with bandits. |
| 7: Bandit Expansion | Varn's ambition peaks | Varn challenges The Boss. Internal gang conflict. Village caught in crossfire. |

**The player's role is to intervene before threads reach breaking point — or to deliberately push them there.**

---

## 4. Emergent Quests

Quests aren't authored as fixed sequences. They **emerge** when thread tension crosses thresholds or when the player's actions create conditions.

### Quest Emergence Rules

```
QuestEmergenceRule:
  id: String
  name: String
  conditions: Dictionary      # Thread tensions, flags, relationships required
  quest_template: Dictionary  # Quest definition generated when conditions met
  priority: int
  cooldown: int               # Game-days before this can trigger again
  driven_by: String           # "npc_action" | "player_action" | "world_event" | "tension_threshold"
```

### Example Emergent Quests

**"Something's Not Right"** (Thread 1, tension > 0.2)
- **Triggers when:** Player talks to 3+ NPCs who each hint at "something wrong" in the village
- **Objectives:** Talk to 2 more NPCs about the village's problems (topics: bandits, fear, trade)
- **Completion:** Player gains enough context to start investigating
- **Sets:** Player awareness that investigation is possible

**"The Midnight Meeting"** (Thread 1, tension > 0.4)
- **Triggers when:** Elena's agent loop decides to follow her father AND player has trust > 40 with Elena
- **Objectives:** Elena asks player to help her follow Gregor tonight
- **OR triggers when:** Player independently discovers Gregor's nighttime activity
- **Completion:** Witness Gregor at the old mill
- **Sets:** gregor_bandit_meeting_known

**"The Marked Blade"** (Thread 4, tension > 0.3)
- **Triggers when:** A bandit raid occurs (Thread 7 event) AND Aldric recovers a weapon with Bjorn's mark
- **Objectives:** Aldric shows the weapon to the player. Player must decide: tell Bjorn or investigate quietly.
- **Completion:** Bjorn learns the truth (one way or another)
- **Sets:** weapons_traced_to_bjorn, bjorn_truth_revealed

**"The Captain's Gambit"** (Thread 5, tension > 0.7)
- **Triggers when:** Aldric's desperation exceeds his patience (autonomous escalation)
- **Objectives:** Aldric plans a premature assault. Player can help prepare, convince him to wait, or let it happen.
- **Completion:** Assault succeeds (with player help), is called off (player convinces), or fails catastrophically
- **Sets:** Multiple flags depending on outcome

**"A Letter from the Capital"** (Thread 6, tension > 0.5)
- **Triggers when:** Mathias's letters FINALLY get a response (off-screen event from Tier 2/3 simulation)
- **Objectives:** Help Mathias prepare for the capital's envoy, or intercept the letter for a different faction
- **Completion:** Political dynamics shift
- **Sets:** External political pressure enters the local system

**"Varn's Proposition"** (Thread 7, tension > 0.5)
- **Triggers when:** Player encounters Varn AND demonstrates capability (combat, confidence)
- **Objectives:** Varn offers the player a deal — work for the bandits, good pay, protection
- **Completion:** Player accepts (Iron Crown path opens), refuses (Varn becomes hostile), or strings him along (intelligence gathering)
- **Sets:** Branching based on choice

**"The Empty Tavern"** (Thread 2, tension > 0.6 in Thread 7)
- **Triggers when:** Mira's tavern loses too much business from bandit pressure (economic ripple)
- **Objectives:** Help Mira keep the tavern open OR investigate why she seems so calm about potential closure
- **Completion:** Multiple paths — help her (deepen cover), investigate her (approach the truth), or let it close (ripple effects cascade)
- **Sets:** mira_trusts_player or suspicion flags

---

## 5. Beyond the Conspiracy: Other World Stories

The conspiracy is the loudest thread, but a living world has many stories:

### Thread 8: The Dying Trade Route
**Driving forces:** Iron Hollow Gang (Tier 3), Millhaven merchants (Tier 2), trade economics
**What's happening:** The northern trade route that connects Thornhaven to Millhaven is becoming dangerous. Merchants stop visiting. Prices rise. The village's economy contracts.
**Emergent quests:** Escort a merchant. Clear a bandit checkpoint. Negotiate a trade agreement. Find an alternate route.
**Intersection:** Economic pressure amplifies ALL other threads. Gregor's profits drop. Bjorn has fewer customers. Mira's tavern empties.

### Thread 9: The Old Ruins
**Driving forces:** World history, exploration, independent of conspiracy
**What's happening:** Ancient ruins north of the village hold pre-kingdom artifacts. Scholars from the capital are interested. Bandits may also want what's inside.
**Emergent quests:** Explore the ruins. Discover lore about the kingdom's founding. Find valuable artifacts. Encounter danger.
**Intersection:** Could provide leverage (artifacts as payment), allies (scholars from capital), or a new threat (what's sealed in the ruins).

### Thread 10: The Herbalist's Garden
**Driving forces:** A potential Tier 1→Tier 0 NPC, village health, nature
**What's happening:** The village herbalist (currently Tier 1) notices something wrong with the local plants. Blight spreading from somewhere. May be natural, may be related to the ruins, may be sabotage.
**Emergent quests:** Help investigate the blight. Gather rare ingredients. Discover the cause. The herbalist's growing importance could promote her to Tier 0.
**Intersection:** If the blight is severe enough, it creates a survival crisis independent of bandits. A second major problem forces the player to prioritize.

### Thread 11: The Traveling Performer
**Driving forces:** A Tier 2 NPC who periodically visits, bringing news and entertainment
**What's happening:** A bard/performer circuits between villages. They carry news, rumors, and sometimes messages for people who can't travel. They're also an intelligence asset — everyone talks to the entertainer.
**Emergent quests:** Hear stories from distant places. Commission them to carry a message. Discover they're gathering intelligence for someone. Who?
**Intersection:** The performer is a gossip accelerator — they can carry information between villages faster than normal propagation. They might also be working for Mira.

### Thread 12: The Young Lovers
**Driving forces:** Two Tier 1 NPCs with a forbidden relationship
**What's happening:** The baker's apprentice and a peacekeeper's daughter are meeting secretly. Their families disapprove (one is pro-compliance, one is pro-resistance). It mirrors the larger village tension in miniature.
**Emergent quests:** Help them meet. Mediate between families. Their love story is a microcosm of the village's division.
**Intersection:** Humanizes the background NPCs. Shows the cost of the conspiracy at a personal level.

---

## 6. Quest Emergence Engine

### How Quests Are Created at Runtime

```
Each game-day tick (or on significant events):

1. EVALUATE THREAD TENSIONS
   For each StoryThread:
     Update tension based on recent NPC actions, world events, time passage

2. CHECK EMERGENCE RULES
   For each QuestEmergenceRule:
     If conditions met (tension thresholds, flags, relationships):
       If not on cooldown:
         Generate quest from template
         Register with QuestManager
         Inject context hints into relevant NPCs

3. CHECK NPC-INITIATED QUESTS
   For each Tier 0/1 NPC agent tick that produced an action:
     If action creates a situation the player could engage with:
       Generate quest opportunity
       Example: Elena decides to follow father → quest "The Midnight Meeting" becomes available

4. CHECK WORLD EVENTS
   For each ripple effect that reached LOCAL scope:
     If effect creates a situation the player could engage with:
       Generate quest opportunity
       Example: Merchant caravan attacked → quest "Escort the Merchant" becomes available
```

### Quest Templates (Not Fixed Quests)

Instead of authoring 25 complete quests, author **quest templates** that the emergence engine fills in based on current world state:

```
QuestTemplate:
  id: "investigate_npc_secret"
  name_pattern: "What {npc_name} Is Hiding"
  trigger: Thread tension > threshold AND player has partial knowledge
  objectives_pattern:
    - Build trust with {npc_id} to {threshold}
    - Discuss {topic} with {npc_id}
    - {optional} Verify with {corroborating_npc}
  completion_sets: {relevant_flag}
  context_hint_pattern: "{npc_name} seems nervous when you mention {topic}..."
```

This single template generates different quests for different NPCs:
- "What Gregor Is Hiding" (investigating the deal)
- "What Mira Is Hiding" (investigating her past)
- "What Bjorn Is Hiding" (investigating the weapons)
- "What Aldric Is Hiding" (discovering his secret arsenal)

The template adapts based on which NPC, which secret, and what the player already knows.

---

## 7. The Mira/Boss Duality

### Design Resolution

Mira operates with a **dual-layer personality:**

**Layer 1 (Cover — default):** Grieving widow, fearful tavern keeper, sympathetic figure
- This is what's in her current .tres file
- All Tier 0/1 NPCs see this version
- Claude generates dialogue from this persona

**Layer 2 (Boss — hidden):** Calculating crime lord, manipulative strategist, the real power
- Activated when `mira_boss_revealed` flag is set
- Or: Activated in Mira's autonomous agent decisions (she THINKS as the Boss even while SPEAKING as the widow)
- Her agent loop uses Boss-layer reasoning to make decisions, then wraps them in widow-layer behavior

**How this works in the agent loop:**

```
Mira's Agent Tick:
  1. PERCEIVE (as Boss): Full awareness of operations, Varn's reports, village dynamics
  2. EVALUATE (as Boss): Score goals — maintain cover, control operations, handle threats
  3. SELECT (as Boss): Choose strategic action
  4. EXECUTE (as Widow): If action is public-facing, wrap it in cover behavior
     Example: Boss decides "redirect suspicion away from Gregor"
             Widow executes: "casually mentions to baker that she saw a stranger near the mill"
  5. REFLECT (as Boss): Store outcome with full strategic awareness
```

**Three paths to the reveal:**
1. **Deduction:** Player pieces together inconsistencies (Mira knows too much, Varn defers to her, her "grief" has gaps)
2. **Confrontation:** Player reaches very high trust (T70+) AND presents evidence that doesn't add up — Mira drops the mask
3. **Forced:** Varn's coup attempt (Thread 7 at crisis) forces Mira to reveal herself to maintain control

**After the reveal, all dialogue uses Boss layer.** Previous conversations are recontextualized. Her Claude prompt shifts entirely.

---

## 8. Non-Combat Resolutions

Every thread can resolve without combat (since combat is Phase 7):

| Thread | Combat Resolution | Non-Combat Alternative |
|--------|------------------|----------------------|
| 1: Merchant's Bargain | Assault mill during meeting | Confront with evidence + witnesses. Social pressure. |
| 2: Grieving Widow | Fight Mira's guards | Expose her through gathered testimony. Political leverage. |
| 3: Daughter's Awakening | Elena fights bandits | Elena confronts Gregor. Player mediates or supports. |
| 4: Unwitting Accomplice | Bjorn fights Gregor | Bjorn testifies to council. Crafts weapons for resistance as penance. |
| 5: Failing Watch | Assault Iron Hollow | Aldric uses intelligence + numbers to force surrender. Negotiation. |
| 6: Paralyzed Council | Military coup | Political maneuvering. Evidence presentation. Vote. |
| 7: Bandit Expansion | Open battle | Undermine from within. Cause internal conflict. Cut supply lines (Gregor). |

**Social confrontations** replace combat: scenes where the player presents evidence, makes arguments, and NPCs react based on their personality, trust levels, and the weight of evidence. Claude generates these dynamically.

---

## 9. Evidence Presentation System

Since there's no inventory, evidence works through **knowledge flags + NPC context:**

### How the Player "Shows" Evidence

When a player knows something (flag is true) and talks to an NPC, Claude's context includes:

```
## PLAYER'S KNOWN EVIDENCE
The player has discovered the following (they may choose to share or withhold):
- [ledger_found]: Found a hidden ledger with suspicious financial records in Gregor's shop
- [weapons_traced_to_bjorn]: Knows that bandit weapons bear Bjorn's maker's mark

The player can mention any of this in conversation. React authentically based on your
personality and relationship with the player. If they present evidence that affects you
directly, respond as your character would.
```

The player simply SAYS "I found a ledger in your shop, Gregor" and Claude handles Gregor's reaction based on his personality, trust level, and the flag being true.

**NPC reactions vary by personality:**
- Gregor (confronted with ledger): Denial → panic → confession (trust-dependent)
- Aldric (shown the ledger): Relief → determination → plans next steps
- Elena (told about father): Denial → anger → devastation (relationship-dependent)
- Mathias (given evidence): Careful verification → authorization → action

---

## 10. World Seed Events

To kick-start stories beyond the conspiracy, the world simulation generates **seed events** during the first few game-days:

| Day | Seed Event | Thread(s) | Player Discovery |
|-----|-----------|-----------|-----------------|
| 1 | Merchant caravan arrives (Tier 1 NPC) | 8 | Meet the merchant, hear about dangerous roads |
| 2 | Herbalist notices wilting plants | 10 | See the herbalist examining her garden |
| 3 | Bandit patrol spotted near village | 7, 5 | Aldric warns player, or player witnesses |
| 5 | Traveling performer arrives | 11 | Hear stories and rumors from distant places |
| 7 | Elena caught practicing swords | 3 | Discover her secret, or she confides if trust > 30 |
| 10 | Marked weapon found after bandit encounter | 4, 1 | Aldric shows it to player, or player finds it |
| 14 | Council meeting (public) | 6 | Attend and witness the paralysis firsthand |
| 14+ | Threads escalate naturally | All | Autonomous NPC actions create new situations |

These aren't scripted events — they're high-probability entries in the off-screen event table that ensure the player encounters story hooks in the first two weeks.

---

## 11. Ending Emergence

Endings aren't triggered by completing a quest. They **emerge** when the world reaches a stable state:

### Ending Evaluation (runs when thread tension reaches 0.0 or 1.0 for multiple threads)

```
func evaluate_ending() -> String:
    # Check world state for ending conditions

    if bandits_destroyed AND gregor_exposed:
        return "liberation"

    if bandits_destroyed AND NOT gregor_exposed:
        return "quiet_peace"

    if bandit_deal_negotiated:
        return "the_deal"

    if player_leads_bandits:
        return "iron_crown"

    if player_controls_through_blackmail:
        return "puppet_master"

    if key_npcs_dead >= 3 OR village_population < threshold:
        return "ashes"

    return null  # No ending yet — world still in flux
```

But more importantly, the ending isn't a binary check — it's the **cumulative result of which threads resolved and how:**

| What Happened | Ending |
|--------------|--------|
| Player exposed Gregor, rallied village, destroyed camp | Liberation |
| Player destroyed camp but protected Gregor's secret | Quiet Peace |
| Player negotiated from position of strength (evidence + allies) | The Deal |
| Player joined Varn, helped him overthrow Boss, took control | Iron Crown |
| Player blackmailed Gregor, leveraged evidence against everyone | Puppet Master |
| Player failed to act, NPCs reached breaking points alone | Ashes |

**Mixed endings are possible.** What if the player exposed Gregor but failed to stop Aldric's premature assault? That's a new ending — not one of the original 6 but emergent from the simulation.

---

## 12. Implementation Architecture

### New Components

| Component | Purpose |
|-----------|---------|
| `StoryThread` resource | Defines a thread with NPCs, tension, flags, intersections |
| `ThreadManager` singleton | Tracks thread tensions, evaluates emergence rules |
| `QuestEmergenceEngine` | Generates quests from templates when conditions met |
| `EvidenceContext` module | Injects player knowledge flags into NPC Claude prompts |
| `EndingEvaluator` | Checks world state for stable ending conditions |

### Integration with Existing Systems

- **NPC Agent Loop** → Actions update thread tensions
- **EventBus** → Thread tension changes emit signals
- **WorldState** → Flags track thread progress
- **QuestManager** → Receives generated quests from emergence engine
- **ContextBuilder** → Injects thread state + evidence into NPC prompts
- **RippleEngine** → Thread events create ripples that affect other threads

### Data Flow

```
NPC Agent Tick → Action taken → ThreadManager.update_tension()
                                    │
                    ┌────────────────┼────────────────┐
                    │                │                │
            Thread tension     World flag         Ripple event
            updated            set                created
                    │                │                │
                    └────────────────┼────────────────┘
                                    │
                        QuestEmergenceEngine.evaluate()
                                    │
                            ┌───────┴───────┐
                            │               │
                    Quest generated    No quest (tension
                    and registered     not at threshold)
                            │
                    QuestManager notified
                            │
                    NPC context hints
                    injected for next
                    player conversation
```

---

## 13. Content Needed

### Minimum Viable World (18 Threads, ~30 Emergence Rules)

| Category | Count | Status |
|----------|-------|--------|
| Core conspiracy threads (1-7) | 7 | Designed above |
| World threads (8-12) | 5 | Sketched above, need detail |
| Quest templates (reusable) | 8-10 | Need to author |
| Quest emergence rules | 25-30 | Need to define conditions |
| NPC goal definitions | 7 Tier 0 + 10-15 Tier 1 | Tier 0 complete (from personality files), Tier 1 needed |
| Seed events | 10-15 | Sketched above |
| Ending conditions | 6+ | Defined above, need code specs |
| Mira Boss persona | 1 | Need to design |

### What Exists and Can Be Used

- 7 detailed NPC personalities with goals, fears, secrets ✓
- 25 story flags ✓
- IntentDetector with topic keywords ✓
- QuestManager with full lifecycle ✓
- WorldKnowledge with canonical facts ✓
- EventBus with signal infrastructure ✓

### What Must Be Created

1. **StoryThread definitions** for all 12 threads (data resources)
2. **Thread tension rules** (what increases/decreases each thread's tension)
3. **Quest templates** (8-10 reusable patterns)
4. **Emergence rules** (25-30 condition → quest mappings)
5. **Mira's Boss persona** (dual-layer personality system)
6. **Seed event definitions** (first 2 weeks of world activity)
7. **Ending evaluation logic** (flag combination → ending)
8. **5+ Tier 1 NPC profiles** (ambient village life)
9. **Evidence context injection** in ContextBuilder
