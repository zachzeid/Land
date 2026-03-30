# Quest System and Story Audit

> **Date:** 2026-03-29
> **Finding:** The quest infrastructure is well-built but completely empty. The story exists in docs but was never translated into quests. These are the same problem.

---

## The Core Problem

```
Story Document (STORY_NARRATIVE.md)     Quest Infrastructure (quest_manager.gd)
├── 3-act structure                     ├── 5 quest states
├── 7 NPCs with 29 secrets             ├── 6 objective types
├── 25 story flags                      ├── Discovery via NPC intent detection
├── 6 endings                           ├── Quest chaining
├── 5+ side quest concepts              ├── NPC context injection
└── Multiple alliance paths             └── Save/load
         │                                        │
         │          NOTHING CONNECTS THEM          │
         └────────────────────────────────────────┘
```

**Current state:** 2 sample quests exist (both broken by NPC ID bugs). Zero .tres quest files. 23 of 25 story flags cannot be set by any quest. All 6 endings have no path to reach them.

---

## What the Quest System CAN Do (Infrastructure)

The infrastructure is genuinely well-designed:

| Feature | Status | Notes |
|---------|--------|-------|
| Quest states (5) | Working | UNAVAILABLE → AVAILABLE → ACTIVE → COMPLETED/FAILED |
| Objective types (6) | Working | flag, intent, relationship, memory_tag, location, topics |
| Discovery via NPC dialogue | Working | IntentDetector analyzes Claude responses |
| Availability gating | Working | required_flags, blocked_by_flags, min_relationship, required_quests |
| Quest chaining | Working | unlocks_quests on completion |
| NPC context hints | Working | Per-NPC hints injected into Claude prompts |
| Multiple endings | Working | possible_endings dictionary per quest |
| Auto-start | Working | Never used |
| Save/load | Working | Full serialization |
| .tres file loading | Working | But res://resources/quests/ directory doesn't exist |

**The system is waiting for content.**

---

## What's Broken

### Critical Bug: NPC ID Mismatch in Sample Quests

The 2 sample quests reference `"gregor_001"` but the actual NPC ID is `"gregor_merchant_001"`. This means:
- Gregor conspiracy quest: discovery conditions never trigger, objectives never complete
- Elena request quest: partially works (uses correct `elena_daughter_001`) but Gregor objectives use wrong ID

**Fix:** 5-minute string replacement in `sample_quests.gd`.

### Missing Quest Content

| What | Count Needed | Count Exists | Gap |
|------|-------------|--------------|-----|
| Main quest chain | 8-10 quests | 0 | Total |
| Side quests | 5-7 quests | 0 (2 broken samples) | Total |
| Romance quests | 6-9 quests (3 paths) | 0 | Total |
| Ending quests | 6 quests | 0 | Total |
| **Total** | **~25-35 quests** | **0 working** | **100%** |

---

## The Story That Exists (in Docs)

STORY_NARRATIVE.md is a solid ~800-line design document. Here's the complete narrative:

### The Conspiracy

**Setup:** Thornhaven is extorted by the Iron Hollow Gang. The village is compliant through fear. The player arrives as an outsider.

**Central Secret:** Gregor (the merchant) orchestrated the arrangement 3 years ago. He provides weapons (via Bjorn's forge), supplies, and intelligence to the bandits. In return, his shop prospers and his daughter Elena is untouchable.

**Major Twist:** Mira (the "grieving widow" tavern keeper) is actually "The Boss" — the mastermind behind Iron Hollow. Her husband Marcus was either killed by Varn or never existed.

### The Investigation Web

Every NPC holds pieces of the puzzle:

```
             ┌── Elena ────── "saw father at old mill"
             │                "suspects father involved"
             │
Gregor ──────┼── Mira ─────── "Gregor meets bandits at mill"
(central     │                 "Varn killed Marcus"
 secret)     │                 [IS ACTUALLY THE BOSS]
             │
             ├── Bjorn ────── "weapon orders suspicious"
             │                "B mark on weapons found at raids"
             │
             ├── Aldric ───── "suspects Gregor"
             │                "has evidence, needs proof"
             │
             └── Mathias ──── "suspected Gregor for a year"
                              "could authorize action"
```

**Player's Investigation Path:** Talk to NPCs → build trust → unlock secrets → piece together the conspiracy → choose what to do with the truth.

### 29 Secrets (The Real Quest Content)

These secrets ARE the story. Each one is a revelation that advances the narrative:

**Gregor (5 secrets, trust 50-85):**
1. Gold saved for Elena to escape (T50/A40)
2. Loneliness since wife died (T55/A50)
3. Weapons go to bandits via Bjorn (T70/A60)
4. Made the deal with bandits (T80/A70)
5. Monthly meetings with Varn at old mill (T85/A75)

**Elena (4 secrets, trust 40-80):**
1. Secret sword practice (T40/A30)
2. Saw father at old mill with hooded figure (T55/A40)
3. Father's suspicious savings (T65/A55)
4. Suspects father involved with bandits (T80/A70)

**Mira (4 secrets, trust 40-85):**
1. Marcus was executed, not robbed (T40/A35)
2. Gregor meets bandits at old mill (T60/A50)
3. Varn killed Marcus (T75/A60)
4. Thought about poisoning Gregor (T85/A70)

**Bjorn (4 secrets, trust 35-70):**
1. Gregor orders too many weapons (T35/A25)
2. Marks weapons with "B" (T50/A40)
3. Father died in debt (T60/A55)
4. Fears learning weapons hurt innocents (T70/A60)

**Varn (4 secrets, trust 60-90):**
1. Aldric is on his list (T60/A50)
2. Wants to take over gang (T80/A70)
3. Killed Marcus slowly (T70/A60)
4. Elena is leverage against Gregor (T90/A80)

**Aldric (4 secrets, trust 50-80):**
1. Suspects Gregor (T50/A40)
2. Secret weapon cache under old well (T65/A55)
3. Self-doubt about leading men (T75/A65)
4. Mapped bandit patrol routes (T80/A70)

**Mathias (4 secrets, trust 45-70):**
1. Unanswered letters to capital (T45/A35)
2. Suspected Gregor for a year (T55/A45)
3. Knew Gregor's honest father (T65/A55)
4. Could authorize action but fears retribution (T70/A60)

### 25 Story Flags

| Category | Flags | Can Be Set By |
|----------|-------|--------------|
| Discovery (5) | ledger_found, weapons_traced_to_bjorn, gregor_bandit_meeting_known, marcus_death_learned, varn_killed_marcus_known | Only ledger_found (StoryItem). Rest: nothing. |
| Confession (4) | gregor_confession_heard, gregor_gold_secret_revealed, mira_testimony_given, bjorn_truth_revealed | Nothing |
| Revelation (5) | elena_knows_about_father, elena_shown_proof, aldric_has_evidence, mathias_informed, bjorn_knows_about_weapons | Nothing |
| Relationship (4) | elena_romance_started, aldric_ally, mira_trusts_player, bjorn_allied | Nothing |
| Confrontation (3) | gregor_confronted, varn_confronted, iron_hollow_visited | Nothing |
| Outcome (4) | gregor_exposed, gregor_redemption_path, mira_boss_revealed, resistance_forming | Nothing |

**23 of 25 flags have no automated trigger.** They can only be set via debug console.

### 6 Endings (No Path to Any)

| Ending | Key Requirements | Quest Chain Needed |
|--------|-----------------|-------------------|
| **Liberation** | Bandits destroyed + Gregor exposed | Evidence → Confront → Rally → Assault |
| **Quiet Peace** | Bandits destroyed + secret kept | Evidence → Rally → Assault (skip exposure) |
| **The Deal** | Negotiate with bandits | Evidence → Leverage → Negotiate |
| **Iron Crown** | Player leads bandits | Contact → Join → Rise → Depose |
| **Puppet Master** | Player controls via blackmail | Evidence → Blackmail → Control |
| **Ashes** | Failure/inaction | Fail key quests or trigger retaliation |

---

## Story Gaps (What Needs Writing Before Quests Can Be Built)

### 1. Mira/Boss Duality (Critical)
Mira's personality .tres is her cover story. There is NO "Boss Mira" persona. Varn's file references the Boss, but Mira's file presents her cover as reality. Until this is resolved:
- The Boss reveal quest cannot function
- The Iron Crown ending has no mechanical support
- Mira's romance arc has a dangling twist with no resolution

**Needs:** A dual-persona system where Mira's behavior shifts after reveal, or a hidden "Boss persona" that Claude accesses when certain flags are set.

### 2. Dark Paths Are Thin
"The Deal" and "Iron Crown" paths have minimal design detail:
- How does the player contact bandits?
- What does joining them involve?
- What quests support these paths?
- How does the player depose the Boss?

**Needs:** Quest-by-quest breakdowns comparable to the Liberation path.

### 3. No Combat Design
The story calls for an assault on Iron Hollow but combat is Phase 7 (unimplemented). Quests ending in combat can't be built.

**Workaround:** Design non-combat resolutions for every quest. The assault could be a series of dialogue/social choices rather than a combat encounter.

### 4. No Inventory/Evidence System
The story relies on "finding evidence" and "showing proof" but there's no inventory (Phase 8). The StoryItem + flag system works for discovery but not for presentation ("show the ledger to Aldric").

**Workaround:** Use conversation + flags. If `ledger_found` is true when talking to Aldric, Claude's context includes "The player has found your ledger" and Aldric can react.

### 5. Act Transition Triggers Undefined
What moves the story from Act I to Act II to Act III? No conditions specified.

**Needs:** Define flag combinations that trigger act transitions (e.g., Act II begins when player learns an informant exists).

### 6. Showing Evidence to NPCs
How does the player present physical evidence? The natural language system means the player could just SAY "I found your ledger" but that feels weak.

**Needs:** An interaction pattern where the player's knowledge (from flags) is reflected in dialogue options or Claude's context.

---

## The Natural Quest Structure (What Secrets Tell Us)

The 29 secrets naturally organize into quest arcs:

### Main Quest Chain: The Conspiracy

```
Act I: Discovery
  Q1: "Welcome to Thornhaven" (auto-start, meet NPCs)
  Q2: "The Bandit Problem" (learn about extortion from any NPC)
  Q3: "Whispers in the Dark" (discover informant exists — from Mira, Aldric, or Mathias)

Act II: Investigation
  Q4: "Hidden Records" (find ledger in Gregor's shop — flag: ledger_found)
  Q5: "The Weapon Trail" (Bjorn's secrets → weapons_traced_to_bjorn)
  Q6: "Mira's Testimony" (Mira's secrets → marcus_death_learned, mira_testimony_given)
  Q7: "The Merchant's Secret" (confront Gregor → gregor_confronted)

Act III: Resolution
  Q8: "Rally the Village" (Aldric + Mathias → resistance_forming)
  Q9: "The Reckoning" (Iron Hollow confrontation → ending-dependent)
  Q10: "Judgment" (Gregor's fate + ending determination)
```

### Side Quests: Character Arcs

```
SQ1: "Elena's Curiosity" (Elena's 4 secrets → elena_knows_about_father)
SQ2: "Bjorn's Burden" (Bjorn's 4 secrets → bjorn_truth_revealed)
SQ3: "Council's Paralysis" (Mathias's secrets → mathias_informed)
SQ4: "Peacekeeper Pride" (Aldric's secrets → aldric_ally)
SQ5: "Behind the Mask" (Mira Boss reveal → mira_boss_revealed)
```

### Romance Quests

```
RQ1: "Gregor Romance" (affection > 60, trust > 50, familiarity > 40)
RQ2: "Elena Romance" (affection > 55, trust > 60, familiarity > 45)
RQ3: "Mira Romance" (affection > 65, trust > 70, familiarity > 50)
     → Complicated by Boss reveal
```

### Total: 18 quests (10 main + 5 side + 3 romance)
This is a playable game.

---

## What the Autonomous NPC System Changes

With autonomous NPCs (from AUTONOMOUS_NPC_AGENTS.md), the quest system transforms:

### NPCs Drive Quests Forward
Instead of waiting for the player to talk to them:
- Gregor's agent loop decides to warn Elena → sets flag → new quest available
- Aldric decides to investigate on his own → discovers evidence → tells player
- Mira decides to close the tavern → ripple effects → new quest emerges

### Quests Emerge from NPC Actions
The autonomous agent system means quests aren't just player-initiated:
- An NPC gossips about Gregor → another NPC confronts him → world state changes → player discovers aftermath
- If player ignores the investigation, Aldric may solve it himself (badly) → different ending path

### The Story Becomes Dynamic
Instead of a fixed quest tree, the story becomes a **living system** where:
- NPCs pursue their own goals (protect daughter, seek justice, maintain cover)
- Player actions create ripples that change NPC priorities
- Quests branch based on what NPCs decided to do autonomously
- Multiple paths to the same ending, or endings the player didn't expect

### Quest System Extensions Needed

| Feature | Why | Priority |
|---------|-----|----------|
| NPC-initiated quests | NPCs set flags that trigger quest availability | High |
| Dynamic objectives | Objectives that change based on NPC autonomous actions | Medium |
| Quest failure from NPC actions | If Aldric dies (NPC combat), his quests fail | Medium |
| Emergent quest generation | New quests from NPC decisions not anticipated by authors | Future |

---

## Recommended Next Steps

### Immediate (Fix What's Broken)
1. Fix NPC ID bug in sample_quests.gd (`gregor_001` → `gregor_merchant_001`)
2. Create `res://resources/quests/` directory
3. Test that the 2 sample quests actually trigger and complete

### Short-term (Build the Story Foundation)
4. Resolve the Mira/Boss duality design
5. Define act transition conditions (flag combinations)
6. Define ending trigger conditions as code-ready specs
7. Design non-combat resolutions for combat-dependent quests

### Medium-term (Build the Quest Chain)
8. Implement the 10 main quest chain as .tres resources
9. Implement the 5 side quests
10. Connect all 25 story flags to quests that set them
11. Implement ending evaluation logic

### Long-term (Dynamic Quests)
12. Connect autonomous NPC actions to quest triggers
13. Add NPC-initiated quest creation
14. Add dynamic quest modification from NPC decisions
