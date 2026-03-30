# Skills, Leveling, and Character Progression System

> **Date:** 2026-03-28
> **Status:** Design Document (no code yet)
> **Depends on:** COMBAT_SYSTEM_DESIGN.md (combat proficiency, mentor techniques), CRAFTING_INVENTORY_AND_EMERGENT_ECONOMICS.md (crafting skills, quality formula), AUTONOMOUS_NPC_AGENTS.md (agent loop, 5D relationships), EMERGENT_NARRATIVE_SYSTEM.md (story threads, quest emergence), NPC_EXISTENCE_AND_INFLUENCE_SYSTEM.md (NPC tiers, ripple engine)

---

## 1. Progression Philosophy

### 1.1 Core Principle: The World Is Your Teacher

The player does not open a skill menu at level-up and allocate points. There is no skill tree screen. There is no XP bar. The player grows by **living in the world** -- by swinging a sword until their arm learns the arc, by earning an old soldier's trust until he shares the stance that saved his life, by reading a crumbling book in a ruin, by failing a negotiation and learning what went wrong.

This is not a cosmetic distinction. It is the architectural foundation. Every skill gain traces back to a concrete in-world cause: a mentor, a practice session, a discovery, a survival event. The player's character sheet, if they could see one, would read like a biography.

**Why this matters for Land specifically:**

Land is a mystery/conspiracy game where relationships ARE the core gameplay. If progression is decoupled from the world -- if the player can grind rats to become a master swordsman -- then the NPC mentorship system becomes optional flavor text. By making NPCs the primary source of growth, the game ensures that building relationships is not just narratively rewarding but mechanically necessary. The player who ignores Elena misses her riposte technique. The player who never earns Aldric's trust cannot rally allies. The player who avoids Varn never learns to fight dirty. Your build IS your biography.

### 1.2 Five Sources of Growth

| Source | What It Provides | Examples |
|--------|-----------------|---------|
| **Practice** | Incremental skill improvement through use | Swinging a sword, picking locks, haggling with merchants |
| **Mentorship** | Technique unlocks, plateau-breaking, style specialization | Elena teaches sword forms, Aldric teaches tactics, Mira teaches reading opponents |
| **Discovery** | Knowledge skills, recipe unlocks, lore | Finding a book on herbalism, discovering a hidden inscription, observing an NPC's technique |
| **Experience** | Core stat growth, general resilience, rare "insight" moments | Surviving a bandit ambush, completing a difficult quest, making a moral choice under pressure |
| **Consequence** | Passive modifiers from reputation and world perception | Being known as a skilled fighter intimidates enemies; being known as a liar makes persuasion harder |

### 1.3 Anti-Grind Philosophy

Pure practice hits diminishing returns. The first 30 points of swordsmanship come from swinging a blade. The next 30 require someone who knows what they are doing to correct your form, teach you when to shift your weight, show you combinations you would never discover alone. The final 40 require mastery-level instruction, dangerous real-world application, and possibly esoteric knowledge found only in ruins or ancient texts.

This creates a natural progression curve:

```
Proficiency 0-30:   Practice alone can achieve this. ~10-15 hours of use.
Proficiency 31-60:  Requires at least one mentor OR significant discovery. Practice gains halved.
Proficiency 61-80:  Requires advanced mentor (high trust gate) OR rare discovery. Practice gains quartered.
Proficiency 81-100: Requires mastery conditions: advanced mentor + rare discovery + significant practice. Practice gains at 10%.
```

The mechanical effect: practice-based gains are multiplied by a **plateau modifier** that decreases at each tier boundary. Mentor training resets or raises the plateau ceiling. This means a player who only practices can reach Proficiency 30 comfortably, 45 with enormous effort, and will never reach 60 without mentorship or discovery.

---

## 2. No Levels -- Capability Profile

### 2.1 Why No Traditional Levels

Land does not have a "Level 12 Warrior." Levels imply a linear, accumulative measure of power that contradicts the game's philosophy. A player who spent all their time with Bjorn learning smithing and Mira learning social manipulation is not "higher level" than one who trained with Aldric -- they are differently capable. The game tracks capability, not rank.

### 2.2 What Replaces Levels: Renown

The closest thing to a level is **Renown** -- a measure of how well-known and respected (or feared) the player is across the game world. Renown is not something the player invests in. It is an emergent consequence of their actions, observed by NPCs and spread through the gossip system.

```
Renown:
  value: float              # 0.0 to 100.0
  sources: Dictionary       # {category: contribution}
    # "combat": 25.0       (known for fighting)
    # "investigation": 30.0 (known for uncovering secrets)
    # "crafting": 10.0     (known for making things)
    # "social": 20.0       (known for persuasion/leadership)
    # "infamy": 15.0       (known for ruthlessness/deception)
  per_settlement: Dictionary  # {settlement_id: local_renown}
```

**What Renown does:**
- NPCs react differently to a renowned player (Tier 1 NPCs use it for initial disposition)
- High combat renown intimidates weaker enemies (they may flee or surrender before fighting)
- High social renown makes NPCs more willing to share information
- High investigation renown causes NPCs with secrets to be more guarded
- High infamy causes fearful reactions but also attracts certain quest paths
- Renown spreads via the gossip system -- acts in Thornhaven reach Millhaven in 3-5 game-days

**How Renown grows:**
- Completing significant quests or story events: +3-8
- Winning notable combat encounters (witnessed): +2-5
- Successfully resolving social confrontations: +2-5
- Crafting notable items (e.g., a Masterwork weapon): +1-3
- NPC gossip spreads deeds: +0.5-2 per propagation hop
- Renown decays slowly if the player is inactive for extended periods (-0.5/game-week)

### 2.3 Core Stats and How They Grow

The three core stats from COMBAT_SYSTEM_DESIGN.md (HP, Stamina, Resolve) grow through use and experience, not through point allocation:

| Stat | Base | Maximum | Growth Mechanism |
|------|------|---------|-----------------|
| **Health (HP)** | 100 | ~250 | +1-2 per survived combat encounter. +3-5 from physical training with mentors. +1 per 10 points of any physical skill. Surviving near-death (+5 bonus). |
| **Stamina (SP)** | 100 | ~200 | +1 per sustained physical activity session. +2-3 from training regimens. +1 per 10 points of combat or survival skills. |
| **Resolve** | 30 | 100 | +1-3 from surviving dangerous situations. +2-5 from making difficult moral choices. +1-3 from social skill milestones. Standing ground when outnumbered (+3). Successfully intimidating a strong foe (+2). |

**Resolve deserves special attention.** It is the most narratively meaningful stat. A player who avoids all danger and always takes the easy path will have low Resolve. A player who faces down Varn alone, confronts Gregor with evidence while Elena watches, and tells Aldric the truth about his doomed assault -- that player's Resolve will be high. Resolve reflects the player's willingness to face hard truths and endure consequences.

**Derived attributes** emerge from skills, not from direct investment:

| Derived Attribute | Source |
|------------------|--------|
| **Attack Speed Modifier** | Weapon proficiency (up to +20% at mastery) |
| **Parry Window** | Combat proficiency + mentor techniques (150ms base, up to 300ms) |
| **Stamina Efficiency** | Physical skill average (up to -20% cost at high levels) |
| **Persuasion Success Modifier** | Persuasion skill + target's disposition + evidence quality |
| **Investigation Perception** | Investigation skill (determines what environmental clues are visible) |
| **Crafting Quality Bonus** | Relevant craft skill (feeds into quality_score formula from CRAFTING doc) |
| **Stealth Detection Range** | Stealth skill (determines how close NPCs must be to spot you) |
| **Carry Capacity** | Base 50 stones + 0.2 stones per point of combined physical skills |

---

## 3. Complete Skill Taxonomy

### 3.1 Skill Architecture

Skills are organized into four domains, each containing individual skills rated 0-100. Skills are not hierarchical -- there is no prerequisite tree. However, **synergies** between skills provide bonuses when related skills are both developed (Section 8).

```
PlayerSkills:
  # Each skill: {level: float, practice_xp: float, plateau: int, mentor_unlocks: Array}
  combat: Dictionary
  social: Dictionary
  craft: Dictionary
  survival: Dictionary
```

### 3.2 Combat Skills

| Skill | Description | Practice Source | Plateau Breaks |
|-------|------------|----------------|---------------|
| **Swordsmanship** | Proficiency with bladed weapons (short sword, long sword, dagger) | Landing attacks, parrying, defeating enemies with swords | Elena (30), Aldric (60), Ancient technique scroll (80) |
| **Blunt Weapons** | Proficiency with hammers, maces, staves | Landing attacks with blunt weapons | Bjorn (30, through forge work), Aldric (60) |
| **Ranged Combat** | Proficiency with bows, throwing weapons | Hitting targets, hunting, combat use | Peacekeeper archer NPC (30), practice range (45) |
| **Unarmed** | Fist fighting, grappling, restraint | Brawling, bar fights, non-lethal takedowns | Varn (30, dirty boxing), Aldric (50, military restraint) |
| **Blocking** | Shield and weapon-based defense | Successfully blocking attacks | Aldric (40, shield techniques), practice (ongoing) |
| **Dodging** | Evasion, i-frame timing, positioning | Successfully dodging attacks | Elena (35, reflexive evasion), Varn (50, combat roll) |
| **Parrying** | Timed deflection, riposte opportunities | Successfully parrying attacks | Elena (40, riposte), Aldric (60, counter-strike) |
| **Armor Use** | Efficient movement in heavy armor, reduced penalties | Wearing armor during activity | Aldric (40, military armor training) |
| **Tactics** | Flanking bonus, ally coordination, battlefield awareness | Winning group combats, coordinating with allies | Aldric (50, military tactics), Mira (60, reading the field, post-reveal) |
| **Intimidation (Combat)** | War cries, threatening stance, demoralizing foes | Causing enemies to flee or surrender | Varn (40, fear tactics), High Resolve (passive) |
| **Non-Lethal** | Knockout techniques, disarming, restraint | Defeating enemies without killing | Aldric (35, peacekeeper restraint), Elena (50, disarming riposte) |

### 3.3 Social Skills

| Skill | Description | Practice Source | Plateau Breaks |
|-------|------------|----------------|---------------|
| **Persuasion** | Convincing NPCs through honest argument, rhetoric, emotional appeal | Successful persuasion attempts in dialogue | Mathias (40, rhetorical technique), Court tutor in Capital (60) |
| **Deception** | Lying convincingly, maintaining cover stories, misdirection | Successful lies in dialogue (detected by NPC Insight) | Mira (40, pre-reveal, by observing her), Varn (50, criminal deception) |
| **Intimidation (Social)** | Threatening, coercing, leveraging fear outside combat | Successfully intimidating NPCs in dialogue | Varn (40), high Fear reputation (passive) |
| **Insight** | Reading NPC emotions, detecting lies, noticing discomfort | Talking to NPCs and paying attention to their tells | Mira (35, tavern keeper's intuition), Elena (50, she learned to read her father) |
| **Negotiation** | Haggling, deal-making, finding mutually acceptable terms | Buying/selling, making deals with NPCs | Gregor (30, merchant technique), Mathias (50, political negotiation) |
| **Leadership** | Rallying NPCs, coordinating groups, inspiring action | Leading NPCs in quests, making decisions that affect groups | Aldric (50, military command), Mathias (60, political authority) |
| **Investigation** | Noticing environmental clues, connecting evidence, deduction | Finding clues, presenting evidence, solving puzzles | Aldric (35, peacekeeper methods), Scholar NPC (50), ruins discoveries (60+) |
| **Etiquette** | Court manners, formal address, understanding social hierarchies | Interacting with nobility, attending formal events | Mathias (30, village politics), Capital court (60) |

### 3.4 Craft Skills

| Skill | Description | Practice Source | Plateau Breaks |
|-------|------------|----------------|---------------|
| **Smithing** | Forging weapons, armor, tools, metal goods | Working at Bjorn's forge, repairing equipment | Bjorn (30, basic technique), Bjorn (60, advanced technique at Trust 70), Guild smith in Millhaven (80) |
| **Herbalism** | Identifying plants, making poultices, basic medicine | Gathering herbs, treating wounds, campfire remedies | Village herbalist (30), rare herb discovery (50), ancient text (70) |
| **Cooking** | Preparing food with stat buffs, preserving ingredients | Cooking at campfire or Mira's kitchen | Mira (30, tavern recipes), specialty ingredients (50) |
| **Alchemy** | Advanced potion-making, poison-crafting, transmutation | Experimentation at alchemy stations | Herbalist (30, basics), Scholar NPC or Capital alchemist (50), ruins discovery (70) |
| **Repair** | Maintaining weapons and armor, restoring damaged items | Repairing own equipment, working with Bjorn | Bjorn (35, weapon maintenance), self-practice (ongoing) |
| **Appraisal** | Identifying item quality, material grade, forgeries, value | Examining items, trading with experienced merchants | Gregor (30, merchant's eye), Bjorn (40, material expertise) |

### 3.5 Survival and Exploration Skills

| Skill | Description | Practice Source | Plateau Breaks |
|-------|------------|----------------|---------------|
| **Stealth** | Moving unseen, avoiding detection, following NPCs | Sneaking past enemies, tailing NPCs, infiltration | Varn (40, bandit stealth), Elena (30, sneaking out to practice swords) |
| **Lockpicking** | Opening locked doors, chests, mechanisms | Attempting locks (success and failure both teach) | Bandit NPC (30), ruins mechanisms (50) |
| **Tracking** | Following trails, reading footprints, finding hidden paths | Following NPCs, hunting, exploring wilderness | Aldric (35, patrol tracking), hunter NPC (50) |
| **Navigation** | Reading the landscape, finding shortcuts, not getting lost | Exploring new areas, traveling between settlements | Traveling merchant NPC (30), cartographer (50) |
| **Foraging** | Finding edible plants, useful materials, water sources | Gathering in wilderness areas | Herbalist (25, plant identification), survival situations (ongoing) |
| **Lore** | Knowledge of history, monsters, factions, ancient secrets | Reading books, talking to scholars, exploring ruins | Mathias (40, village history), Scholar NPC (60, kingdom history), ruins inscriptions (80) |

---

## 4. Learning Mechanics in Detail

### 4.1 Practice-Based Learning

Every skill has a practice XP counter that fills toward the next level. XP gains come from relevant actions. The amount gained depends on three factors: the action's difficulty relative to current skill, whether the action succeeded, and the plateau modifier.

```
practice_xp_gain = base_xp * difficulty_modifier * success_modifier * plateau_modifier

Where:
  base_xp: defined per action type (see tables below)
  difficulty_modifier:
    action_difficulty < skill_level - 20: 0.25 (too easy, minimal learning)
    action_difficulty within 20 of skill_level: 1.0 (appropriate challenge)
    action_difficulty > skill_level + 20: 1.5 (struggling, learning fast)
  success_modifier:
    success: 1.0
    failure: 0.5 (you still learn from failure, just less)
    critical success: 1.5
  plateau_modifier:
    skill_level 0-30: 1.0 (full speed)
    skill_level 31-60 without mentor break: 0.5 (halved)
    skill_level 31-60 with mentor break: 0.8
    skill_level 61-80 without advanced mentor: 0.25 (quartered)
    skill_level 61-80 with advanced mentor: 0.6
    skill_level 81-100 without mastery conditions: 0.1 (near-zero)
    skill_level 81-100 with mastery conditions: 0.4
```

**XP required per level:**

```
xp_for_next_level = 100 + (current_level * 10)

Level 0 -> 1:  100 XP
Level 10 -> 11: 200 XP
Level 30 -> 31: 400 XP (plateau hits here)
Level 50 -> 51: 600 XP
Level 80 -> 81: 900 XP (mastery plateau)
```

**Combat practice XP (base values):**

| Action | Base XP | Condition |
|--------|---------|-----------|
| Light attack landed | 2 | Per hit |
| Heavy attack landed | 4 | Per hit |
| Successful parry | 6 | Per parry |
| Successful dodge | 3 | Per dodge |
| Successful block | 2 | Per block |
| Defeated an enemy (non-lethal) | 15 | Per enemy |
| Defeated an enemy (lethal) | 12 | Per enemy (slightly less -- killing teaches less than restraint) |
| Survived combat encounter | 8 | Once per encounter |
| Used a technique successfully | 5 | Per technique use |

**Social practice XP:**

| Action | Base XP | Condition |
|--------|---------|-----------|
| Successful persuasion check | 8 | Per conversation |
| Failed persuasion (learned why) | 4 | Per conversation |
| Successful deception | 8 | Per lie that stuck |
| Caught in a lie | 3 | Painful but educational |
| Successful intimidation | 6 | Per target intimidated |
| Read an NPC's emotional state correctly | 4 | Per insight check |
| Completed a negotiation | 10 | Per deal |
| Successfully led a group action | 12 | Per event |
| Noticed an investigation clue | 6 | Per clue found |
| Connected two pieces of evidence | 10 | Per connection |

**Craft practice XP:**

| Action | Base XP | Condition |
|--------|---------|-----------|
| Crafted an item (any quality) | 10 | Per item |
| Crafted a Fine+ item | 15 | Per item |
| Crafted a Superior+ item | 25 | Per item |
| Repaired an item | 5 | Per repair |
| Identified a material correctly | 4 | Per identification |
| Gathered herbs/materials | 3 | Per gathering session |
| Cooked a meal | 5 | Per meal |
| Brewed a potion | 8 | Per potion |
| Experimented and discovered a recipe | 20 | Per discovery |

**Survival practice XP:**

| Action | Base XP | Condition |
|--------|---------|-----------|
| Moved undetected past an NPC | 5 | Per NPC avoided |
| Picked a lock | 8 | Per lock (scaled by difficulty) |
| Followed a trail successfully | 6 | Per tracking session |
| Found a hidden path/area | 10 | Per discovery |
| Foraged successfully | 3 | Per gathering session |
| Read a lore book or inscription | 8 | Per text |
| Survived a dangerous wilderness event | 10 | Per event |

### 4.2 Mentor-Based Learning

Mentorship is the primary mechanism for breaking through skill plateaus and unlocking techniques. When an NPC teaches the player, three things happen:

1. **Plateau break:** The player's plateau ceiling for the relevant skill is raised. Example: Elena breaks the Swordsmanship plateau at 30, allowing practice gains to continue at 0.8x modifier up to 60.

2. **Technique unlock:** The NPC teaches a specific named technique that provides a discrete new ability. Example: "Elena's Riposte" -- counter-attack after parry that disarms the opponent.

3. **Skill XP burst:** The teaching session itself grants a significant chunk of practice XP. Example: Training with Aldric for an afternoon grants 50 Tactics XP.

**How mentorship works in-game:**

Mentorship is not a menu selection. It emerges from dialogue and relationship:

1. Player builds trust with an NPC to the required threshold
2. Context conditions are met (story flags, location, time of day)
3. The NPC's Claude agent, seeing the trust level and context in its prompt, naturally offers to teach
4. Or: the player asks the NPC to teach them during dialogue
5. A training scene plays (could be a practice combat, a conversation, a crafting session)
6. Skills update, technique unlocks, memory is stored for both player and NPC

**Training scene format:**

```
TrainingSession:
  mentor_npc_id: String           # Who is teaching
  skill_affected: String          # Which skill improves
  xp_granted: int                 # Practice XP from the session
  plateau_break_level: int        # New plateau ceiling (e.g., 60)
  technique_unlocked: String      # Technique ID, or "" if just XP/plateau
  duration_game_minutes: int      # How long the training takes (in-game time)
  trust_requirement: int          # Minimum trust to trigger
  additional_requirements: Dictionary  # {flag: value, skill_minimum: int, etc.}
  repeatable: bool                # Can this training be done multiple times?
  repeat_xp: int                  # XP per repeat (lower than first time)
  dialogue_context: String        # Context injected into NPC prompt for the scene
```

**Repeated training:** Some training sessions are repeatable (Elena's sword practice, Aldric's drills). Each repeat grants diminishing XP (50% of first session, then 25%, then fixed at 10 XP). This models the realistic diminishing returns of drilling the same exercises.

### 4.3 Discovery-Based Learning

Some knowledge cannot be taught by any living NPC. It must be found in the world.

**Books and scrolls:**
- Found in ruins, libraries, NPC homes (with permission or theft), merchant caravans
- Reading a book grants Lore XP and may unlock specific knowledge flags
- Some books contain recipes (Tier D from CRAFTING doc)
- Some books contain combat technique descriptions (grants practice XP toward a technique that normally requires a mentor, but at reduced efficiency -- learning from a book is slower than learning from a person)

**Observation:**
- Watching an NPC perform a skill can grant small XP gains
- Observing Bjorn at the forge: +2 Smithing XP per observation (once per game-day)
- Watching Elena practice swords: +2 Swordsmanship XP (and a story flag)
- Observing Mira manage the tavern: +1 Insight XP, +1 Negotiation XP
- Observing Aldric train peacekeepers: +2 Tactics XP, +1 Leadership XP

**Experimentation:**
- Combining crafting materials in unexpected ways can discover new recipes (Tier C from CRAFTING doc)
- Trying social approaches that are outside the player's comfort zone grants bonus XP on success
- Exploring areas thoroughly can reveal hidden environmental clues that grant Investigation XP

**Ruins and ancient knowledge:**
- The old ruins north of Thornhaven contain pre-kingdom artifacts and inscriptions
- Ancient texts can break high-level plateaus (80+) for certain skills
- These are one-time discoveries: unique, valuable, and tied to exploration quests
- Example: an ancient combat manual in the ruins can break the Swordsmanship 80 plateau, granting mastery-level practice gains without needing a living master

### 4.4 Experience-Based Growth (Insight Moments)

Certain events grant **Insight** -- a one-time growth burst that reflects the player learning something fundamental about themselves or the world. Insight is not a currency. It is an event that triggers stat growth and sometimes skill growth.

**Insight triggers:**

| Event | Stats/Skills Affected | Growth |
|-------|----------------------|--------|
| First time nearly dying in combat | HP +5, Resolve +3 | Survived to learn |
| First successful non-lethal takedown | Non-Lethal +5, Resolve +2 | Learned restraint |
| Discovering Gregor's secret | Investigation +5, Insight +3 | A major revelation |
| Confronting Gregor with evidence | Resolve +5, Persuasion or Intimidation +3 | Facing a hard truth |
| Elena learning the truth about her father | Resolve +3 (if player was present and handled it well) | Witnessing consequences |
| Successfully de-escalating a combat encounter | Persuasion +5, Resolve +2 | Chose the harder path |
| Being betrayed by an NPC you trusted | Insight +5, Resolve +3, trust recalibrated | Pain teaches |
| Making a moral choice that costs you something | Resolve +3-5 depending on cost | Character-defining moment |
| Surviving the Iron Hollow assault | HP +5, Stamina +5, all combat skills +3 | Baptism of fire |
| Boss reveal (learning Mira's true identity) | Insight +10, Investigation +5 | Everything you thought you knew was wrong |

---

## 5. Mentor System -- Complete NPC Teacher Registry

### 5.1 Overview

Every Tier 0 NPC can teach the player something. What they teach reflects who they are. The player's build is a map of their relationships.

### 5.2 Elena -- The Natural Fighter

Elena practices swordwork in secret, dreaming of adventure. She is untrained but talented, learning fast. Teaching Elena is reciprocal -- you improve together.

| Teaching | Trust Gate | Skill Affected | What Player Gains |
|----------|-----------|---------------|------------------|
| Sword practice partner | 30 | Swordsmanship | +50% practice XP gain for sword attacks (she pushes you to be better) |
| Basic forms | 40 | Swordsmanship | Plateau break at 30. +30 XP burst. |
| Elena's Riposte | 60 | Swordsmanship, Parrying | Technique unlock: counter-attack after parry that disarms opponent. Plateau break at 60. |
| Reading opponents | 50 | Insight | +20 XP burst. Elena teaches you to watch people's eyes before they act. |
| Mutual training (repeatable) | 40+ | Swordsmanship | +15 XP per session (diminishing), Elena's own combat stats improve as ally |

**Narrative note:** Training with Elena is one of the game's most satisfying loops. You watch her go from wild swings to disciplined strikes. Her improvement as an ally is directly tied to time spent training together. If the player never trains with Elena, she remains an untrained but determined ally in combat -- brave but sloppy.

**Reciprocal effect:** The player's Swordsmanship level affects Elena's growth. At player Swordsmanship 50+, Elena gains combat stats faster during training sessions. The player becomes her mentor in return.

### 5.3 Aldric -- The Veteran Soldier

Aldric is a former military officer. His training is disciplined, demanding, and effective. He does not suffer fools, and he does not teach people he does not trust to use their skills responsibly.

| Teaching | Trust Gate | Skill Affected | What Player Gains |
|----------|-----------|---------------|------------------|
| Basic combat drills | 35 | All combat skills | +20 XP to each combat skill. Plateau break at 30 for Blocking, Parrying. |
| Tactical combat | 50 | Tactics | +15% damage when flanking, +10% block efficiency. Plateau break at 50. +40 XP. |
| Shield Wall technique | 60 | Blocking, Tactics | Technique unlock: coordinated shield defense with allies. Requires shield + ally. |
| Commander's Rally | 70 | Leadership, Tactics | Technique unlock: AoE ally buff (+10% damage, 15 seconds). Plateau break at 60 for Leadership. |
| Military restraint | 50 | Non-Lethal | Peacekeeper restraint techniques. +30 XP. Plateau break at 35. |
| Patrol tracking | 40 | Tracking | Aldric teaches wilderness tracking from his patrol experience. +25 XP. Plateau break at 35. |
| Advanced tactics (repeatable) | 60+ | Tactics | Training drills at peacekeeper camp. +10 XP per session. |

**Narrative note:** Training with Aldric happens at the peacekeeper camp and is visible to other NPCs. Being seen training with the peacekeepers improves Respect with law-abiding NPCs and damages Trust with Varn and bandit-aligned NPCs. This is a meaningful social signal.

### 5.4 Varn -- The Ruthless Fighter

Varn teaches through pain and pragmatism. His techniques are effective but dishonorable. Learning from Varn changes how the world sees you.

| Teaching | Trust Gate | Skill Affected | What Player Gains |
|----------|-----------|---------------|------------------|
| Dirty boxing | 30 (bandit path) | Unarmed | Cheap shots, eye gouges, groin strikes. +30 XP. Plateau break at 30. |
| Dirty Fighting | 40 (bandit path) or 60 (neutral) | All melee combat | Technique unlock: attacks from behind deal +20%, can throw dirt to blind. |
| Fear tactics | 40 | Intimidation (Combat + Social) | Technique unlock: war cry that causes morale check. +30 XP. Plateau break at 40. |
| Criminal stealth | 50 | Stealth | How to move unseen, avoid patrols, plan escape routes. +40 XP. Plateau break at 40. |
| Bandit deception | 50 | Deception | How criminals lie convincingly. +30 XP. Plateau break at 50. |
| Poison application | 60 | Alchemy (sub-discipline) | Apply poison to weapons. Morally gray. +20 Alchemy XP. |

**Reputation consequence:** Any NPC who learns the player trained with Varn suffers the following relationship changes:
- Aldric: Respect -15, Trust -10
- Bjorn: Respect -10
- Mathias: Trust -10
- Elena: Concern (no immediate change, but triggers worried dialogue)
- Mira: Secretly pleased (no visible change, but Boss persona notes this)

This information spreads through gossip. If Aldric sees you fight using Varn's techniques (dirty fighting, fear tactics), he recognizes the style: "Where did you learn to fight like that? That is not a soldier's technique."

### 5.5 Bjorn -- The Master Craftsman

Bjorn does not teach combat directly. He teaches craft and material knowledge that indirectly strengthens everything the player does with equipment.

| Teaching | Trust Gate | Skill Affected | What Player Gains |
|----------|-----------|---------------|------------------|
| Basic smithing | 30 | Smithing | Plateau break at 30. +30 XP. Can work the forge with basic competence. |
| Weapon maintenance | 35 | Repair | Technique unlock: weapons degrade 50% slower. +25 XP. Plateau break at 35. |
| Material identification | 40 | Appraisal | Can identify material grade on sight. +20 XP. Plateau break at 40. |
| Advanced smithing | 70 | Smithing | Plateau break at 60. +50 XP. Access to Fine+ quality crafting. |
| Custom weapon forging | 80 | Smithing | Bjorn forges a unique weapon tuned to player's style (+5% proficiency gain with that weapon type). |
| Forge work (repeatable) | 30+ | Smithing, Repair | +8 XP per session. Also builds Affection and Respect with Bjorn. |

**Narrative note:** Working at Bjorn's forge is physical labor. It takes game-time. The player stands at the anvil, hands dirty, learning the craft. Other NPCs who visit see the player working. This builds Bjorn's Respect for the player and makes the custom weapon (Trust 80) feel earned.

### 5.6 Mathias -- The Scholar-Elder

Mathias is old, cautious, and deeply knowledgeable. He teaches through conversation and political maneuvering, not physical action.

| Teaching | Trust Gate | Skill Affected | What Player Gains |
|----------|-----------|---------------|------------------|
| Village politics | 30 | Etiquette | Understanding Thornhaven's power structure. +20 XP. Plateau break at 30. |
| Rhetorical technique | 40 | Persuasion | How to argue effectively before the council. +30 XP. Plateau break at 40. |
| Historical knowledge | 40 | Lore | Village and regional history. +30 XP. Plateau break at 40. |
| Political negotiation | 60 | Negotiation | Advanced deal-making. +40 XP. Plateau break at 50. |
| Leadership philosophy | 60 | Leadership | Theoretical foundations of command. +30 XP. |
| Investigation methods | 50 | Investigation | How a village elder pieces together community secrets. +25 XP. |

### 5.7 Mira -- The Hidden Master

Before the Boss reveal, Mira appears to teach only tavern-keeper skills. After the reveal, her true capabilities become available -- but accepting her training carries heavy narrative weight.

**Pre-reveal:**

| Teaching | Trust Gate | Skill Affected | What Player Gains |
|----------|-----------|---------------|------------------|
| Tavern keeper's intuition | 30 | Insight | Reading customers, noticing lies. +20 XP. Plateau break at 35. |
| Tavern recipes | 40 | Cooking | Specialty food and drink. +25 XP. Plateau break at 30. |
| The rumor network | 50 | Investigation | How information flows through a tavern. +20 XP. |
| Haggling wisdom | 35 | Negotiation | Practical merchant negotiation. +15 XP. |

**Post-reveal (requires `mira_boss_revealed` and player did not immediately turn hostile):**

| Teaching | Trust Gate | Skill Affected | What Player Gains |
|----------|-----------|---------------|------------------|
| Reading opponents | 50 (Boss trust) | Insight, Tactics | Technique unlock: "Boss's Gambit" -- see enemy attack telegraphs 200ms earlier. Plateau break at 60 for Insight. |
| Manipulation tactics | 60 (Boss trust) | Deception, Persuasion | How to control people without them knowing. +40 XP each. Plateau break at 60 for Deception. |
| Network building | 70 (Boss trust) | Leadership | How she built and maintained a criminal empire. +50 XP. Plateau break at 60. |
| Poison craft | 50 (Boss trust) | Alchemy | Advanced poison-making. +30 XP. |

**Narrative note:** Every skill learned from post-reveal Mira is tainted. The player is learning from the conspiracy's architect. NPCs who learn about this training will have strong reactions. But the techniques are genuinely powerful -- this is the game's Faustian bargain for progression.

### 5.8 Gregor -- The Merchant

Gregor teaches mercantile skills. His willingness depends heavily on whether the player is investigating him.

| Teaching | Trust Gate | Skill Affected | What Player Gains |
|----------|-----------|---------------|------------------|
| Merchant's eye | 30 | Appraisal | Quick value assessment of items. +20 XP. Plateau break at 30. |
| Haggling | 40 | Negotiation | Practical price negotiation. +25 XP. Plateau break at 30. |
| Reading desperation | 50 | Insight | Recognizing when someone is hiding something (ironic -- Gregor teaches the skill that can be used against him). +20 XP. |

### 5.9 Settlement-Specific Mentors

Beyond Thornhaven's Tier 0 NPCs, other settlements offer unique learning opportunities through Tier 1 and Tier 2 NPCs:

**Thornhaven (additional):**

| NPC | Tier | Teaching | Skill | Trust/Disposition |
|-----|------|---------|-------|------------------|
| Village Herbalist | Tier 1 | Plant identification, basic potions | Herbalism | Disposition 30+ |
| Peacekeeper Archer | Tier 1 | Bow training | Ranged Combat | Disposition 40+ |
| Baker Hilda | Tier 1 | Bread-making, pastry | Cooking | Disposition 20+ |
| Old Hunter | Tier 1 | Wilderness tracking, animal behavior | Tracking, Foraging | Disposition 30+ |

**Millhaven (future settlement):**

| NPC | Tier | Teaching | Skill | Trust/Disposition |
|-----|------|---------|-------|------------------|
| Guild Smith | Tier 1 | Advanced metalwork | Smithing (plateau 80) | Guild rep + payment |
| Merchant Prince | Tier 2 | High-stakes negotiation | Negotiation (plateau 70) | Reputation + quest |
| Traveling Scholar | Tier 1 | Kingdom history, ancient languages | Lore (plateau 60) | Disposition 40+ |
| Alchemist | Tier 1 | Advanced alchemy | Alchemy (plateau 50) | Disposition 50+ |

**Capital (future settlement):**

| NPC | Tier | Teaching | Skill | Trust/Disposition |
|-----|------|---------|-------|------------------|
| Court Tutor | Tier 1 | Courtly persuasion, etiquette | Persuasion, Etiquette (plateau 60) | Introduction required |
| Royal Armorer | Tier 2 | Masterwork smithing techniques | Smithing (plateau 90) | Reputation + quest |
| Spymaster contact | Tier 2 | Advanced espionage | Stealth, Deception (plateau 70) | Quest chain |
| Historian | Tier 1 | Deep kingdom lore | Lore (plateau 80) | Disposition 40+ |

**Iron Hollow (bandit camp):**

| NPC | Tier | Teaching | Skill | Trust/Disposition |
|-----|------|---------|-------|------------------|
| Bandit Locksmith | Tier 1 | Advanced lockpicking | Lockpicking (plateau 50) | Bandit faction trust |
| Camp Cook | Tier 1 | Wilderness cooking, poison identification | Cooking, Herbalism | Bandit faction trust |
| Bandit Scout | Tier 1 | Wilderness stealth, ambush tactics | Stealth, Tactics | Bandit faction trust |

---

## 6. How Skills Affect Game Systems

### 6.1 Combat Effects

Skills do not just provide passive bonuses. They change what the player can DO in combat situations.

**Weapon proficiency effects (per 20 points):**

| Proficiency | Combat Changes |
|-------------|---------------|
| 0-20 | Basic attacks only. Slow recovery. 2-hit combo max. Obvious telegraphs. |
| 21-40 | 3-hit combo. Slightly faster. Special attacks available. Can use techniques from mentors. |
| 41-60 | Smooth transitions between attacks. Reduced stamina cost (-10%). Techniques are more effective. |
| 61-80 | Fast recovery. Adaptive combos. -15% stamina cost. Can read enemy patterns better. |
| 81-100 | Master tier. 4-hit combo. Maximum speed. -20% stamina cost. All techniques at full power. Can choose lethal vs non-lethal on any hit. |

**Tactics skill effects:**

| Tactics Level | Effect |
|--------------|--------|
| 20+ | Flanking damage bonus (+10%) |
| 40+ | Can issue one ally command during tactical pause |
| 60+ | Flanking bonus (+25%). Two ally commands. Enemies show health bars. |
| 80+ | Three ally commands. Allies coordinate automatically (flanking, focus fire). Enemies show stance/intention. |

**Non-lethal skill effects:**

| Non-Lethal Level | Effect |
|-----------------|--------|
| 20+ | Fists and blunt weapons reliably knock out instead of kill |
| 40+ | Can attempt to disarm with any weapon (skill check) |
| 60+ | Can demand surrender mid-combat (Resolve check against enemy) |
| 80+ | Can end combat by restraining an opponent (grapple system) |

### 6.2 Social Effects

Social skills change what dialogue options are available, how NPCs respond, and what information the player can access.

**How social skill checks work:**

Social interactions are not binary pass/fail dice rolls. The player's skill level determines what approaches are available in conversation (injected as context for the NPC's Claude prompt), and the NPC's AI determines the response based on the approach's appropriateness, the player's relationship, and the NPC's personality.

```
Social Skill Check:
  player_skill_level: int
  npc_disposition: int            # From 5D relationship or single-axis disposition
  context_modifiers: Array        # Evidence presented, witnesses, recent events
  approach_difficulty: int        # How hard this particular ask is

  # Instead of a dice roll, this becomes a context block in the NPC's Claude prompt:
  "[PLAYER CAPABILITY] The player has Persuasion {level} (descriptor). They are attempting
   to convince you to {action}. Based on your personality, goals, and relationship with
   the player, determine how you respond. The player's approach is {skillful/clumsy/average}
   for this kind of request."
```

**What this means in practice:**

- A player with Persuasion 20 trying to convince Mathias to authorize action: Claude sees "clumsy but earnest argument" and Mathias responds with patient refusal and advice on how to build a better case
- A player with Persuasion 60 + strong evidence: Claude sees "well-argued case with evidence" and Mathias is genuinely persuaded
- A player with Intimidation 50 trying to scare Gregor: Claude sees "credible threat" and Gregor's paranoid personality makes him crack

**Skill-gated dialogue approaches:**

| Skill Level | What Becomes Available |
|------------|----------------------|
| Insight 30+ | Player can "read" NPCs -- Claude prompt includes "[The player notices your {emotion}]" |
| Insight 60+ | Player detects lies -- Claude prompt includes "[The player suspects you are not being truthful]" |
| Persuasion 40+ | Eloquent arguments available -- NPC takes player more seriously |
| Deception 40+ | Convincing lies available -- NPC Claude prompt does NOT flag the statement as a lie |
| Intimidation 50+ | Credible threats available -- Fear-susceptible NPCs respond with compliance |
| Leadership 40+ | Can rally groups -- NPCs in earshot make morale checks |
| Investigation 30+ | Environmental clues become visible (highlighted interactable objects) |
| Investigation 60+ | Can connect evidence in dialogue -- "[The player presents a chain of evidence: A leads to B]" |
| Negotiation 40+ | Counter-offers become available -- NPC considers alternatives |
| Etiquette 30+ | Formal address options -- noble/authority NPCs respond with more respect |

### 6.3 Economic Effects

Skills directly affect the economic simulation from CRAFTING_INVENTORY_AND_EMERGENT_ECONOMICS.md:

**Crafting quality bonus:**
The player's craft skill feeds directly into the `quality_score` formula:

```
# From CRAFTING doc, crafter_skill component:
crafter_skill = player_craft_skill / 100.0  # 0.0 to 1.0, weighted at 0.30

# A player with Smithing 70 contributes 0.21 to the quality score
# A player with Smithing 30 contributes 0.09
# Bjorn (effective skill 85) contributes 0.255
# The difference between player-crafted and Bjorn-crafted items decreases as player skill rises
```

**Negotiation and prices:**

```
# Haggle adjustment from CRAFTING doc:
haggle_adjustment = negotiation_skill_check()
  # Negotiation 0-20: -0.0 to -0.05 (tiny discount)
  # Negotiation 21-40: -0.05 to -0.15 (noticeable discount)
  # Negotiation 41-60: -0.10 to -0.25 (significant discount)
  # Negotiation 61-80: -0.15 to -0.30 (major discount, NPC may feel cheated)
  # Negotiation 81-100: -0.20 to -0.35 (master haggler)
```

**Appraisal and market awareness:**

| Appraisal Level | Economic Information Available |
|----------------|------------------------------|
| 0-20 | See item names and vague price ("a few coins", "expensive") |
| 21-40 | See actual prices. Can identify Common vs Fine quality. |
| 41-60 | See quality tier precisely. Notice when prices are above market rate. |
| 61-80 | Identify material grade. Know supply/demand trends. Detect counterfeit goods. |
| 81-100 | Full market awareness. Know NPC markup. Identify Masterwork potential in materials. |

**Crafting as economic participation:**
A player with high Smithing can craft items that compete with Bjorn's output. This affects the local economy:
- Player-crafted weapons enter the supply pool
- If player undercuts Bjorn's prices, it affects his income (and their relationship)
- High-quality player crafts increase Renown (crafting category)
- NPCs may commission the player for specific items (new quest hooks)

### 6.4 Exploration Effects

| Skill | Level | Effect on Exploration |
|-------|-------|---------------------|
| Stealth 20+ | | Can follow NPCs without being noticed (enables tailing missions) |
| Stealth 40+ | | Can infiltrate restricted areas (bandit camp, Gregor's back room) |
| Stealth 60+ | | Can eavesdrop on NPC-NPC conversations (overhear gossip/secrets) |
| Lockpicking 20+ | | Can open simple locks (basic chests) |
| Lockpicking 40+ | | Can open moderate locks (Gregor's hidden stash) |
| Lockpicking 60+ | | Can open complex locks (Aldric's weapon cache, ruins mechanisms) |
| Tracking 20+ | | Footprints visible on trails. Can follow obvious paths. |
| Tracking 40+ | | Can track NPCs to discover their movements. Find hidden locations. |
| Tracking 60+ | | Can track old trails. Determine who passed and when. |
| Navigation 20+ | | Minimap shows more detail. Fewer dead ends in wilderness. |
| Navigation 40+ | | Discover shortcuts between locations. |
| Foraging 20+ | | Find basic herbs and edible plants in wilderness. |
| Foraging 40+ | | Find rare materials. Know where to look for specific items. |
| Lore 20+ | | Ancient inscriptions partially readable. Basic monster knowledge. |
| Lore 40+ | | Historical context for locations. Can identify artifacts. |
| Lore 60+ | | Read ancient texts. Understand political context of factions. |
| Lore 80+ | | Decipher encoded messages. Understand pre-kingdom history. |

### 6.5 Skills Opening Quest Resolution Paths

This is where the system pays off narratively. The same quest situation can be resolved through multiple skill paths:

**Example: "The Midnight Meeting" (follow Gregor to the old mill)**

| Approach | Required Skills | What Happens |
|----------|----------------|-------------|
| Follow stealthily | Stealth 30+ | Observe the meeting undetected. Full evidence. |
| Track his footprints | Tracking 30+ | Follow his trail to the mill after the fact. Partial evidence. |
| Confront him beforehand | Intimidation 40+ OR Persuasion 50+ | He confesses or breaks down. Different evidence. |
| Ask Mira about his movements | Insight 30+ (notice she knows more than she says) | She hints at the location. |
| Pick the lock on his ledger chest | Lockpicking 40+ | Find financial evidence. Different angle entirely. |
| Investigate the weapons | Investigation 30+ + Appraisal 20+ | Trace Bjorn's marks. Indirect route to the truth. |

**Example: "The Captain's Gambit" (Aldric plans premature assault)**

| Approach | Required Skills | What Happens |
|----------|----------------|-------------|
| Fight alongside Aldric | Combat skills 40+ | Join the assault. High risk, direct resolution. |
| Convince Aldric to wait | Persuasion 50+ OR Leadership 40+ | He trusts you enough to delay. Need to provide alternative plan. |
| Negotiate with Varn directly | Negotiation 50+ + Intimidation 40+ | Cut a deal or threaten Varn into retreat. |
| Sabotage bandit defenses first | Stealth 40+ + Tactics 30+ | Weaken Iron Hollow before the assault. |
| Rally additional allies | Leadership 40+ + high Renown | Bring Bjorn, armed villagers, maybe Elena. |
| Present evidence to Mathias first | Investigation 40+ + Persuasion 40+ | Get official backing. Aldric gets reinforcements. |

---

## 7. NPC Perception of Player Skills

### 7.1 How NPCs Detect Player Skills

NPCs do not see a number. They observe behavior and form opinions. The player's skill levels are translated into observable traits that feed into the NPC agent loop:

```
PlayerSkillPerception:
  # Generated from player skill levels, injected into NPC context prompts
  combat_impression: String
    # Skills < 20 avg: "seems untrained in combat"
    # Skills 20-40 avg: "handles themselves adequately in a fight"
    # Skills 40-60 avg: "is a competent fighter"
    # Skills 60-80 avg: "is a skilled warrior -- moves with trained precision"
    # Skills 80+ avg: "is a master combatant -- every movement is economical and lethal"

  social_impression: String
    # Similar descriptors for social capabilities

  craft_impression: String
    # Similar descriptors

  survival_impression: String
    # Similar descriptors

  # Specific observations from witnessed events:
  witnessed_feats: Array[String]
    # "defeated three bandits without killing any"
    # "forged a Fine-quality sword at Bjorn's forge"
    # "talked down a hostile NPC with eloquent argument"
    # "picked the lock on Gregor's chest"
```

### 7.2 Per-NPC Skill Reactions

Each Tier 0 NPC has specific skills they notice and react to:

**Aldric values:** Combat skill (Respect+), Tactics (Respect++), Leadership (Respect+), Non-lethal prowess (Respect+), Dirty fighting (Respect--)
- At player combat avg 50+: "You handle yourself well. Where did you train?"
- At player Tactics 40+: Offers to coordinate on patrol. Treats player as peer.
- At player Dirty Fighting known: "That technique... that is not an honest fighter's art. Where did you learn it?"

**Bjorn values:** Smithing (Respect+), Repair skill (Respect+), Quality appreciation (Affection+), Patience in craft (Trust+)
- At player Smithing 40+: Treats player as fellow craftsman. Offers advanced techniques earlier.
- At player Appraisal 30+: Enjoys discussing material quality. Opens up about his craft.
- At player Smithing 70+: Genuine admiration. "You have the hands for this. Rare, that."

**Mathias values:** Lore (Respect+), Investigation (Trust+), Persuasion (Respect+), Etiquette (Trust+), Violence (Trust-)
- At player Lore 30+: Engages in historical discussions. Shares more context.
- At player Investigation 40+: Takes player seriously as someone who can find the truth.
- At player known violence: Wary. "The village needs justice, not another sword."

**Varn values:** Combat skill (Respect+), Intimidation (Respect+), Stealth (Trust+), Deception (Trust+), Diplomacy/honor (Contempt)
- At player combat avg 50+: Offers his "proposition" earlier.
- At player Intimidation 40+: Treats player as potential rival or asset.
- At player high Persuasion + low Intimidation: "You talk too much. This world runs on steel, not words."

**Elena values:** Swordsmanship (Admiration+), Non-lethal (Respect+), Investigation (Trust+), Teaching ability (Affection+)
- At player Swordsmanship 40+: Asks for training openly. Excited to learn.
- At player Non-lethal focus: Respects the restraint. "You don't have to hurt people to win?"
- At player teaching Elena: Affection increases. This is a bonding mechanism.

**Mira values (pre-reveal):** Insight (Wariness), Investigation (Fear), Social skills (Careful respect), Trust-building (Strategic evaluation)
- At player Insight 40+: Mira's Boss persona (internal) flags the player as perceptive -- dangerous.
- At player Investigation 50+: Mira becomes more careful about her cover. Drops fewer hints.
- At player Deception 40+: Mira (as Boss) recognizes a fellow manipulator. May adjust strategy.

**Gregor values:** Negotiation (Respect+), Discretion (Trust+), Investigation (Fear), Intimidation (Fear)
- At player Investigation 30+: Gregor becomes more nervous in conversation.
- At player Intimidation 40+ used on him: May confess earlier out of terror.
- At player Negotiation 50+: Sees player as someone he could make a deal with.

### 7.3 Skill-Based Reputation Spread

When the player demonstrates a skill publicly, the gossip system picks it up:

```
SkillDemonstrationEvent:
  skill: String                 # "swordsmanship"
  level_displayed: int          # Approximate level shown (not exact -- NPCs estimate)
  context: String               # "defeated three bandits in town square"
  witnesses: Array[String]      # NPC IDs who saw it
  location: String              # Where it happened
  timestamp: int                # When

  # Becomes an InfoPacket:
  info_packet:
    content: "The newcomer is a skilled swordsman -- I saw them handle three bandits with ease."
    category: "gossip"
    confidence: 0.9             # High if witnessed directly
```

This InfoPacket propagates through the gossip system. Within 1-2 game-days, most of Thornhaven knows. Within 3-5 game-days, word reaches Millhaven. The player's skill reputation precedes them.

**Consequences of skill reputation:**
- High combat reputation: Weaker enemies flee. Stronger enemies prepare. Varn takes you seriously.
- High social reputation: NPCs approach you for help. Council considers your opinion. Information flows to you more freely.
- High craft reputation: NPCs commission items. Bjorn respects you. Economic opportunities appear.
- High stealth/deception reputation: Paradoxically, being KNOWN as sneaky makes people watch you more carefully. The game penalizes open displays of covert skills.

---

## 8. Skill Synergies

### 8.1 Design Principle

When two related skills are both developed, they create emergent capabilities greater than either skill alone. Synergies reward diverse builds and create natural playstyle niches.

### 8.2 Synergy Table

| Skill A | Skill B | Synergy | Required Levels | Effect |
|---------|---------|---------|----------------|--------|
| **Investigation** | **Persuasion** | Interrogation | 30+ each | When questioning NPCs, can present evidence mid-conversation for +50% persuasion effectiveness. NPC Claude prompt receives "[The player combines evidence with skilled questioning]" |
| **Investigation** | **Insight** | Profiling | 30+ each | Can "read" an NPC's secrets. NPC Claude prompt includes "[The player is studying you with unsettling precision -- they seem to notice things others don't]" |
| **Smithing** | **Any combat skill** | Weapon Expertise | 30+ each | +10% damage with weapons the player could theoretically forge. Understanding the weapon's construction reveals optimal striking angles. |
| **Smithing** | **Repair** | Field Maintenance | 30+ each | Can repair weapons and armor during tactical pause (limited, consumes materials). Equipment durability degradation reduced by 30%. |
| **Herbalism** | **Cooking** | Medicinal Cuisine | 25+ each | Food provides minor healing over time. Specialty meals grant temporary stat buffs (+5 HP regen, +10 Stamina, etc.). |
| **Herbalism** | **Alchemy** | Advanced Remedies | 30+ each | Potions are more potent (+25% effect magnitude). Can create antidotes for specific poisons. |
| **Stealth** | **Investigation** | Covert Surveillance | 30+ each | Can follow NPCs without being noticed AND gain Investigation XP from observing their behavior. Unlock tailing quests. |
| **Stealth** | **Lockpicking** | Infiltration | 30+ each | Can enter locked buildings at night undetected. Combined skill check instead of separate checks. |
| **Leadership** | **Tactics** | Commander | 40+ each | Allies in combat gain +15% damage and +10% defense (stacks with Commander's Rally). Can issue complex orders (coordinated flanking, organized retreat). |
| **Leadership** | **Persuasion** | Rallying Speech | 40+ each | Can rally groups of NPCs outside combat. Villagers may form militia. Council is more receptive to bold plans. |
| **Intimidation (Social)** | **Intimidation (Combat)** | Terrifying Presence | 40+ each | Combined intimidation aura. Weaker NPCs refuse to engage. Even strong NPCs hesitate. Fear reputation spreads faster. |
| **Deception** | **Insight** | Manipulator | 40+ each | Can detect lies AND tell convincing ones. In dialogue, the player sees NPC deception indicators while their own lies are harder to detect. |
| **Negotiation** | **Appraisal** | Master Trader | 30+ each | Full price transparency. Know exact fair value, NPC markup, and NPC desperation level. Maximum haggle effectiveness. |
| **Tracking** | **Stealth** | Predator | 35+ each | Can follow targets who are themselves trying to be stealthy. Counter-stealth checks at +20%. |
| **Lore** | **Investigation** | Scholar-Detective | 35+ each | Historical context enhances evidence analysis. Can identify the significance of ancient artifacts. Quest clues from ruins are more informative. |
| **Swordsmanship** | **Dodging** | Bladedancer | 40+ each | Can attack immediately out of a dodge (dodge-strike). Reduced recovery time between dodge and attack by 50%. |
| **Blocking** | **Parrying** | Iron Guard | 40+ each | Blocking stamina cost reduced by 25%. Parry window increased by 50ms. Can parry attacks that would normally be unblockable. |
| **Non-Lethal** | **Insight** | Merciful Read | 30+ each | Can see when enemies are close to surrender. Surrender threshold lowered (enemies yield earlier). |
| **Foraging** | **Navigation** | Pathfinder | 30+ each | Discover hidden wilderness paths. Travel between locations takes less game-time. Find rare material locations. |

### 8.3 Synergy Detection

Synergies activate automatically when both skills reach the required level. The player is notified through subtle in-game cues, not popup notifications:

- A journal entry appears: "I am beginning to see how understanding a weapon's forging informs how I fight with it."
- An NPC comments: "You fight like someone who knows their blade from the inside out."
- New options appear in gameplay without explicit announcement.

---

## 9. The "Master of Everything" Problem

### 9.1 The Problem

In skill-by-doing systems (Elder Scrolls, Kingdom Come, Stardew Valley), players tend to eventually master every skill, eliminating meaningful build diversity. In Land, where skills gate narrative content, this problem is even worse -- a completionist player would see every mentor's teachings, every quest path, and every resolution option.

### 9.2 How Land Prevents This

**Time pressure from the narrative:**

The story threads from EMERGENT_NARRATIVE_SYSTEM.md advance autonomously. Tension rises. NPCs reach breaking points. The player cannot spend 100 game-days training with every mentor because by game-day 30, Aldric may have launched his doomed assault, Gregor may have fled, and Elena may have confronted her father alone. The world does not wait for you to finish your training montage.

This is the single most important anti-mastery mechanism. Time spent training is time not spent investigating, building relationships, or preventing catastrophe. The player must choose what to prioritize.

**Relationship exclusivity:**

Some mentor paths are mutually exclusive:
- Training with Varn (Dirty Fighting, Fear Tactics) damages relationships with Aldric and Bjorn
- Training with Mira (post-reveal) is morally compromising -- affects how other NPCs perceive you
- Deep investment in one NPC's teachings means less time for another's
- The gossip system means choices are visible -- you cannot secretly train with Varn and maintain Aldric's respect if anyone sees you

**Plateau mechanics:**

Without mentors, practice gains hit steep diminishing returns at 30. This means the player can be mediocre at many things but can only excel at skills where they invested mentor relationships. Since mentor access requires trust (which requires time and choices), the player naturally specializes.

**Geographic separation:**

Advanced mentors are spread across settlements. The Millhaven Guild Smith, the Capital Court Tutor, the ruins' ancient knowledge -- these require travel, which costs game-time. A player who travels to Millhaven for smithing mastery is not in Thornhaven preventing the narrative from derailing.

**Skill level soft cap through XP scaling:**

```
Effective skill cap by time investment:
  10 game-days focused: ~2-3 skills at 50+, others at 20-30
  20 game-days focused: ~3-4 skills at 60+, others at 25-35
  30 game-days focused: ~4-5 skills at 70+, others at 30-40
  Full game (40-60 game-days): ~2-3 skills at 80+, 4-5 at 50-60, rest at 30-40
```

A player who completes the game will be strong in a handful of skills that reflect their choices, competent in several more, and weak in the rest. This is by design.

### 9.3 New Game Plus Consideration

If a New Game+ mode is implemented, the player could carry over some skill progress (e.g., 50% of levels), allowing them to explore different mentor paths on subsequent playthroughs. This turns the limitation into replayability -- each playthrough reveals different content based on different specializations.

---

## 10. Multi-Settlement Skill Variation

### 10.1 Design Principle

Each settlement has a cultural identity expressed through what can be learned there. Traveling to a new settlement is not just a change of scenery -- it is access to entirely new growth opportunities.

### 10.2 Settlement Specializations

**Thornhaven -- The Village**
- Core offering: Basic combat (Elena, Aldric), smithing (Bjorn), social fundamentals (Mathias, Mira), herbalism (village herbalist)
- Unique: Conspiracy investigation skills (Insight, Investigation, Deception -- learned by engaging with the mystery)
- Limitation: No advanced alchemy, no courtly skills, no academic lore beyond village history
- Atmosphere: Practical, grounded. Skills learned here feel earned through daily life.

**Iron Hollow -- The Bandit Camp**
- Core offering: Dirty fighting (Varn), stealth, lockpicking, intimidation, poison application
- Unique: Criminal network skills -- understanding how an organization operates from the inside
- Limitation: No honorable combat training, no crafting beyond crude weapons, no scholarly knowledge
- Access gate: Requires bandit faction trust (joining Varn's path or infiltrating)
- Atmosphere: Harsh, pragmatic. Skills learned here cost your reputation.

**Millhaven -- The Trade Town (future)**
- Core offering: Advanced smithing (Guild), merchant skills (Negotiation, Appraisal at high levels), formal combat training
- Unique: Guild system access -- structured skill advancement through professional organizations
- Limitation: Guild access requires reputation or payment. Political skills focused on trade, not courtly intrigue.
- Access gate: Travel there (costs game-days), then earn Guild reputation
- Atmosphere: Professional, mercantile. Skills are commodified -- you pay for training.

**The Capital -- The Seat of Power (future)**
- Core offering: Courtly skills (Etiquette, Persuasion at elite levels), academic knowledge (Lore at 80+), political intrigue (Deception at elite levels)
- Unique: Access to royal library (ancient technique scrolls), court connections (quest hooks)
- Limitation: Combat training is ceremonial, not practical. Crafting is for artisans, not adventurers.
- Access gate: Requires introduction (high Renown or NPC connection), travel distance
- Atmosphere: Refined, dangerous in a different way. Skills learned here are about power, not survival.

**The Old Ruins -- The Ancient Place**
- Core offering: Lore (unique plateau-breaking texts), rare crafting recipes, ancient combat techniques
- Unique: One-time discoveries that break mastery plateaus (80+) for specific skills
- Limitation: Dangerous. No living mentors. Knowledge is fragmented and must be pieced together (Investigation checks).
- Access gate: Navigation skill + physical access (may require quest completion)
- Atmosphere: Mysterious, rewarding. Skills gained here feel ancient and powerful.

---

## 11. Integration with Existing Systems

### 11.1 Combat System Integration

From COMBAT_SYSTEM_DESIGN.md, the combat proficiency system is absorbed into this broader skill framework:

| Combat Doc Concept | Skills System Equivalent |
|-------------------|------------------------|
| Weapon proficiency (0-100) | Swordsmanship, Blunt Weapons, Ranged Combat, Unarmed |
| Proficiency thresholds (Novice-Master) | Same thresholds, same effects, plus plateau mechanics |
| Mentor techniques | Now part of full mentor registry (Section 5) |
| Circumstance modifiers (flanking, etc.) | Enhanced by Tactics skill |
| Resolve stat | Grows through experience events (Section 4.4) |
| Non-lethal options | Governed by Non-Lethal skill with explicit level gates |

The combat document's Section 9 (Skills and Progression) is superseded by this document, which expands it to cover all skill domains.

### 11.2 Crafting and Economics Integration

From CRAFTING_INVENTORY_AND_EMERGENT_ECONOMICS.md:

| Crafting Doc Concept | Skills System Equivalent |
|---------------------|------------------------|
| `crafter_skill` in quality formula | Player's relevant craft skill / 100.0 |
| Recipe tiers (Innate/Taught/Discovered/Found) | Practice/Mentor/Discovery learning sources |
| Taught by NPCs at trust thresholds | Mentor system (Section 5) with specific trust gates |
| Haggle adjustment | Negotiation skill check |
| Material identification | Appraisal skill |

**Specific integration point:** The crafting quality formula's `crafter_skill` component now references the player's Smithing, Herbalism, Cooking, or Alchemy skill level (depending on what is being crafted). The `relationship_bonus` component remains separate -- it reflects the NPC's effort, not the player's skill.

When the player crafts alone (campfire crafting):
```
quality_score = (
  material_grade * 0.35 +
  player_craft_skill * 0.40 +  # Higher weight when player is sole crafter
  tool_quality * 0.25 +
  0.0                           # No relationship bonus (solo crafting)
)
```

When the player works with an NPC crafter:
```
quality_score = (
  material_grade * 0.35 +
  max(player_craft_skill, npc_craft_skill) * 0.25 +  # Best of both
  synergy_bonus * 0.10 +       # If player + NPC skills complement each other
  tool_quality * 0.15 +
  relationship_bonus * 0.15
)
```

### 11.3 NPC Agent System Integration

From AUTONOMOUS_NPC_AGENTS.md:

The player's skill levels feed into NPC perception during every agent tick. When an NPC's agent loop runs PERCEIVE, the player's skill impression (Section 7.1) is included in the context:

```
# Added to NPC agent tick context:
"PLAYER ASSESSMENT: {player_combat_impression}. {player_social_impression}.
Recently demonstrated: {recent_skill_demonstrations}.
Known training: {known_mentor_relationships}."
```

This means NPCs autonomously adjust their behavior based on the player's growing capabilities. As the player becomes more skilled:
- Weaker NPCs become more deferential
- Rivals become more cautious
- Mentors become more willing to teach advanced techniques
- Enemies prepare better defenses
- The gossip network spreads the player's reputation

### 11.4 Narrative System Integration

From EMERGENT_NARRATIVE_SYSTEM.md:

Skills open and close quest resolution paths. The Quest Emergence Engine checks player skill levels as part of its conditions:

```
# Extended QuestEmergenceRule:
QuestEmergenceRule:
  conditions:
    thread_tensions: {thread_id: min_tension}
    flags: {flag: required_value}
    relationships: {npc_id: {dimension: min_value}}
    player_skills: {skill_id: min_level}    # NEW: skill gating

# Example:
QuestEmergenceRule:
  id: "covert_investigation"
  conditions:
    thread_tensions: {"gregors_deal": 0.3}
    player_skills: {"stealth": 30, "investigation": 25}
  quest_template:
    name: "Shadow of the Merchant"
    description: "Follow Gregor without being seen and discover where he goes at night."
```

Skills also affect thread tension:
- High Investigation skill + talking to NPCs about the conspiracy: increases Thread 1 tension faster (you ask better questions, notice more)
- High Intimidation used on Gregor: increases Thread 1 tension sharply (he panics)
- High Persuasion used on Aldric: can moderate Thread 5 tension (convince him to be patient)
- High Leadership + rallying villagers: reduces all threat-related tensions (the village feels safer)

### 11.5 Ripple Engine Integration

From NPC_EXISTENCE_AND_INFLUENCE_SYSTEM.md:

Significant skill demonstrations create RippleEvents:

```
RippleEvent:
  description: "The newcomer single-handedly defeated three bandits in the village square using advanced combat techniques."
  category: "social"
  origin_location: "thornhaven"
  intensity: 0.6
  effects:
    - scope: "local"
      effect_type: "npc_reaction"
      target: "all_thornhaven_npcs"
      parameters: {modify_impression: "combat", direction: "positive", magnitude: 15}
    - scope: "regional"
      effect_type: "info_packet"
      target: "millhaven"
      parameters: {content: "A capable fighter has arrived in Thornhaven", confidence: 0.7}
```

---

## 12. Godot 4 Data Structures

### 12.1 PlayerSkillManager (Autoload Singleton)

```gdscript
extends Node
class_name PlayerSkillManager

# Skill data: {skill_id: SkillData}
var skills: Dictionary = {}

# Synergy cache: recalculated when skills change
var active_synergies: Array[Dictionary] = []

# Renown tracking
var renown: Dictionary = {
    "value": 0.0,
    "sources": {},
    "per_settlement": {}
}

# Core stats
var hp_max: int = 100
var stamina_max: int = 100
var resolve: int = 30

# Mentor history
var mentor_sessions: Array[Dictionary] = []  # [{npc_id, skill, timestamp, trust_at_time}]

# Learned techniques
var techniques: Array[String] = []  # Technique IDs

# Discovered recipes (links to CRAFTING system)
var known_recipes: Array[String] = []

# Insight events already triggered (prevent double-granting)
var triggered_insights: Array[String] = []

func get_skill_level(skill_id: String) -> int:
    if skills.has(skill_id):
        return skills[skill_id].level
    return 0

func add_practice_xp(skill_id: String, base_xp: float, difficulty: int = -1, success: bool = true) -> void:
    # Apply difficulty modifier, success modifier, plateau modifier
    # Check for level-up
    # Check for synergy activation
    # Emit signal
    pass

func apply_mentor_training(session: Dictionary) -> void:
    # Raise plateau ceiling
    # Grant XP burst
    # Unlock technique if applicable
    # Record in mentor_sessions
    # Emit signal
    pass

func check_synergies() -> void:
    # Iterate synergy definitions
    # Activate/deactivate based on current skill levels
    # Update active_synergies
    pass

func get_skill_impression(domain: String) -> String:
    # Calculate average skill level for a domain
    # Return human-readable impression string
    pass

func get_player_capability_context() -> Dictionary:
    # Generate context block for NPC Claude prompts
    # Includes skill impressions, known techniques, recent demonstrations
    pass

# Signals
signal skill_level_changed(skill_id: String, new_level: int)
signal technique_unlocked(technique_id: String)
signal synergy_activated(synergy_id: String)
signal plateau_reached(skill_id: String, plateau_level: int)
signal renown_changed(new_value: float, sources: Dictionary)
signal insight_triggered(insight_id: String)
```

### 12.2 SkillData Resource

```gdscript
extends Resource
class_name SkillData

@export var skill_id: String              # "swordsmanship"
@export var display_name: String          # "Swordsmanship"
@export var domain: String                # "combat" | "social" | "craft" | "survival"
@export var description: String           # Flavor description

# Current state
@export var level: int = 0                # 0-100
@export var practice_xp: float = 0.0     # XP toward next level
@export var xp_for_next: float = 100.0   # XP needed for next level

# Plateau tracking
@export var plateau_ceiling: int = 30     # Current ceiling (raised by mentors)
@export var mentor_breaks: Array[Dictionary] = []  # [{npc_id, ceiling_raised_to, timestamp}]

# Practice efficiency
@export var base_plateau_modifier: float = 1.0  # Current modifier based on level vs ceiling
```

### 12.3 TechniqueData Resource

```gdscript
extends Resource
class_name TechniqueData

@export var technique_id: String          # "elenas_riposte"
@export var display_name: String          # "Elena's Riposte"
@export var description: String           # What it does narratively
@export var domain: String                # "combat" | "social" | "craft" | "survival"

# Requirements
@export var skill_requirements: Dictionary = {}  # {skill_id: min_level}
@export var mentor_required: String = ""          # NPC ID, or "" if no mentor needed
@export var mentor_trust_required: int = 0        # Trust level with mentor
@export var flag_requirements: Dictionary = {}     # {flag_name: required_value}

# Effects
@export var passive_effects: Dictionary = {}       # {stat: modifier}
@export var active_ability: bool = false            # Does this give an active combat/social ability?
@export var ability_stamina_cost: int = 0           # Stamina cost if active
@export var ability_cooldown: float = 0.0           # Cooldown in seconds if active
```

### 12.4 SynergyDefinition Resource

```gdscript
extends Resource
class_name SynergyDefinition

@export var synergy_id: String            # "interrogation"
@export var display_name: String          # "Interrogation"
@export var description: String

# Requirements
@export var skill_a: String               # "investigation"
@export var skill_a_min: int              # 30
@export var skill_b: String               # "persuasion"
@export var skill_b_min: int              # 30

# Effects
@export var passive_effects: Dictionary = {}   # {effect_type: value}
@export var context_injection: String = ""      # Text added to NPC Claude prompts when synergy active
@export var unlocks_actions: Array[String] = [] # Action IDs that become available
```

### 12.5 TrainingSession Resource

```gdscript
extends Resource
class_name TrainingSession

@export var session_id: String            # "elena_basic_forms"
@export var mentor_npc_id: String         # "elena_daughter_001"
@export var skill_affected: String        # "swordsmanship"

# Requirements
@export var trust_requirement: int = 40
@export var skill_minimum: int = 0        # Player must be at least this level
@export var flag_requirements: Dictionary = {}
@export var location_required: String = "" # "" = anywhere, or specific location

# Rewards
@export var xp_granted: int = 30
@export var plateau_break_to: int = 30     # Raises ceiling to this level
@export var technique_unlocked: String = "" # Technique ID, or "" if none
@export var stat_bonuses: Dictionary = {}   # {stat: amount} for HP/SP/Resolve

# Repeat
@export var repeatable: bool = true
@export var repeat_xp: int = 15            # XP per subsequent session
@export var repeat_diminish_rate: float = 0.5  # Each repeat gives this fraction of previous
@export var min_repeat_xp: int = 5          # Floor for repeat XP

# Timing
@export var duration_game_minutes: int = 60
@export var cooldown_game_hours: int = 12   # Time before this session can repeat

# Context for NPC dialogue
@export var dialogue_context: String = ""    # Injected into mentor's Claude prompt during session
```

### 12.6 EventBus Signals (New)

```gdscript
# Add to existing EventBus autoload:

# Skill events
signal player_skill_changed(skill_id: String, old_level: int, new_level: int)
signal player_technique_learned(technique_id: String, mentor_npc_id: String)
signal player_synergy_activated(synergy_id: String)
signal player_plateau_reached(skill_id: String, level: int)
signal player_training_started(npc_id: String, skill_id: String)
signal player_training_completed(npc_id: String, skill_id: String, xp_gained: int)

# Renown events
signal player_renown_changed(old_value: float, new_value: float, category: String)
signal player_skill_demonstrated(skill_id: String, level_shown: int, witnesses: Array)

# Insight events
signal player_insight_triggered(insight_id: String, stats_changed: Dictionary)
```

### 12.7 ContextBuilder Extensions

```gdscript
# Additions to existing ContextBuilder for NPC prompts:

func build_player_capability_context() -> String:
    var psm = PlayerSkillManager  # autoload reference
    var ctx = "## PLAYER CAPABILITIES\n"
    ctx += "Combat: %s\n" % psm.get_skill_impression("combat")
    ctx += "Social: %s\n" % psm.get_skill_impression("social")
    ctx += "Craft: %s\n" % psm.get_skill_impression("craft")
    ctx += "Survival: %s\n" % psm.get_skill_impression("survival")

    var techniques = psm.techniques
    if techniques.size() > 0:
        ctx += "Known techniques: %s\n" % ", ".join(techniques)

    var recent = psm.get_recent_demonstrations(3)
    if recent.size() > 0:
        ctx += "Recently demonstrated:\n"
        for demo in recent:
            ctx += "- %s\n" % demo.description

    return ctx

func build_mentor_context(npc_id: String) -> String:
    # If this NPC has training sessions available for the player,
    # and the player meets the requirements, inject teaching opportunity context
    var available = get_available_training(npc_id)
    if available.size() == 0:
        return ""

    var ctx = "## TEACHING OPPORTUNITY\n"
    ctx += "You have skills you could teach the player. Based on your trust level and the current situation, you may naturally offer to train them if the conversation flows that way.\n"
    ctx += "Available to teach:\n"
    for session in available:
        ctx += "- %s (you trust them enough for this)\n" % session.display_name
    return ctx
```

---

## 13. Implementation Priority

### Phase 1: Core Skill Framework (1 week)

**Deliverables:**
- `PlayerSkillManager` autoload singleton with all skill definitions
- `SkillData`, `TechniqueData` resources
- Practice XP system (gain XP from combat actions)
- Plateau modifier system (diminishing returns without mentors)
- EventBus signals for skill changes
- Basic ContextBuilder extension (player capability context in NPC prompts)

**Why first:** This is the foundation everything else depends on. No mentor system, no synergies, no NPC perception -- just "I swung a sword 50 times and my Swordsmanship went from 3 to 5."

**Depends on:** Existing BaseNPC, WorldState, EventBus (all in codebase)

### Phase 2: Mentor System (1-2 weeks)

**Deliverables:**
- `TrainingSession` resource with all Thornhaven NPC training sessions defined
- Training flow: trust check -> dialogue context -> training scene -> skill update
- Plateau break mechanics
- Technique unlock system
- `TechniqueData` resources for all combat techniques from COMBAT_SYSTEM_DESIGN.md Section 9

**Why second:** Mentor training is the game's signature progression mechanic. Once this works, the "learn from the world" philosophy is tangible.

**Depends on:** Phase 1 + existing 5D relationship system + ContextBuilder

### Phase 3: Social and Exploration Skills (1 week)

**Deliverables:**
- Social skill checks integrated into dialogue system (skill level -> NPC Claude prompt context)
- Investigation skill gates (environmental clues visible at skill thresholds)
- Stealth skill affecting NPC detection
- Survival skills affecting exploration (lockpicking, tracking, foraging)

**Why third:** Extends the system beyond combat into the social and exploration pillars. Combat skills work from Phase 1-2; now social and survival skills become functional.

**Depends on:** Phase 1 + existing ClaudeClient and ContextBuilder

### Phase 4: Synergies and NPC Perception (1 week)

**Deliverables:**
- `SynergyDefinition` resources for all synergies
- Synergy detection and activation
- NPC skill perception (player skill impressions in agent loop context)
- Skill demonstration events feeding into gossip system
- Renown system

**Why fourth:** These are enhancement layers. The core system works without them, but they make it sing. NPC perception of player skills is what makes the world feel responsive to growth.

**Depends on:** Phases 1-3 + AUTONOMOUS_NPC_AGENTS.md agent loop + gossip system

### Phase 5: Discovery and Insight (1 week)

**Deliverables:**
- Book/scroll discovery system (reading grants XP and knowledge)
- Observation XP (watching NPCs practice)
- Experimentation system (crafting discovery)
- Insight moments (one-time growth events triggered by narrative milestones)
- Core stat growth from experience events

**Why fifth:** Discovery and insight add depth and surprise to the system. The player has been practicing and training; now the world itself teaches them.

**Depends on:** Phases 1-4 + EMERGENT_NARRATIVE_SYSTEM.md story thread flags

### Phase 6: Multi-Settlement and Advanced Content (2 weeks)

**Deliverables:**
- Millhaven mentor definitions (Guild Smith, Merchant Prince, etc.)
- Capital mentor definitions (Court Tutor, Royal Armorer, etc.)
- Ruins discovery content (ancient texts, mastery plateau breaks)
- Iron Hollow mentor definitions (expanded from Phase 2)
- Settlement-specific skill availability

**Why last:** Requires multiple settlements to exist in the game. This phase is content creation more than system engineering.

**Depends on:** All previous phases + WORLD_GENERATION_AND_NAVIGATION.md settlement implementation

---

## 14. Research Notes and Influences

### Elder Scrolls (Oblivion/Skyrim) -- Skill-by-Doing

**What Land takes:** The core loop of "use it to improve it." Swing a sword, get better at swords. Pick a lock, get better at lockpicking. This is intuitive and eliminates the disconnect between player action and character growth.

**What Land avoids:** Skyrim's system has no diminishing returns and no mentor dependency, leading to the "master of everything" problem. Players exploit the system by repeatedly casting spells on nothing or pickpocketing their own companions. Land's plateau mechanics and time pressure prevent this.

### Kingdom Come: Deliverance -- Mentor Training + Practice

**What Land takes:** The most direct influence. KCD requires you to find trainers to unlock higher skill tiers, and training sessions are interactive scenes. Land adopts this structure wholesale and enhances it with the 5D relationship gating.

**What Land avoids:** KCD's training is transactional (pay gold, get skill). Land's training is relational (earn trust, receive teaching). The gold cost is replaced by the time and moral investment of building a relationship.

### Disco Elysium -- Skills as Personality

**What Land takes:** The idea that skills are not just numbers but aspects of who the player is. High Investigation does not just let you find clues -- it makes NPCs perceive you as observant. High Intimidation does not just scare enemies -- it makes everyone around you more cautious. Skills shape NPC perception, which shapes available interactions, which shapes the story.

**What Land avoids:** Disco Elysium's skills "talk" to the player as internal voices. Land externalizes this -- NPCs respond to your skills, rather than your skills responding to you. The player's inner life is their own.

### Persona -- Social Links Powering Abilities

**What Land takes:** The mechanical link between relationship depth and combat power. In Persona, maxing a Confidant unlocks the ultimate Persona of that arcana. In Land, maxing trust with Aldric unlocks Commander's Rally. The progression system IS the relationship system.

**What Land avoids:** Persona's separation between "social time" and "dungeon time." In Land, training with Aldric (social) directly improves your combat capability (mechanical) in the same world space. There is no mode switch.

### Dark Souls -- Investment with Diminishing Returns

**What Land takes:** The concept that each additional point costs more than the last, creating natural soft caps. Land's XP scaling (`xp_for_next_level = 100 + (current_level * 10)`) ensures the gap between 80 and 81 is much larger than between 10 and 11.

**What Land avoids:** Dark Souls' pure stat investment model (spend souls on numbers). Land never asks the player to choose between +1 STR and +1 DEX. Growth emerges from action, not allocation.

### Fable -- The World Reflects Your Choices

**What Land takes:** The idea that your build is visible. In Fable, heavy melee use makes you muscular. In Land, NPCs comment on your fighting style, your craft skills show in the items you produce, and your social skills change how conversations flow. Your progression is not hidden in a menu -- it is evident in how the world responds to you.

### Stardew Valley -- Skill Leveling Through Practice

**What Land takes:** The satisfying loop of doing an activity and seeing a bar fill. Stardew proves that practice-based leveling is deeply satisfying when the activities themselves are enjoyable. Land ensures that combat, social interaction, crafting, and exploration are all intrinsically engaging.

**What Land avoids:** Stardew's lack of skill depth -- each skill is essentially a single bar with a few perks. Land's skills have mentors, plateaus, techniques, synergies, and NPC perception layers.

---

## Appendix A: Quick Reference -- All Techniques

| Technique | Source | Skill | Trust/Level | Effect |
|-----------|--------|-------|-------------|--------|
| Combo Chain (3-hit) | Practice | Weapon proficiency 25 | -- | Extended combo |
| Power Strike | Practice | Weapon proficiency 30 | -- | Charged heavy attack |
| Shield Bash | Practice | Blocking 35 + shield | -- | 1.5s stun |
| Parry Counter | Practice or Aldric | Parrying 40 | Aldric Trust 50 | Riposte after parry |
| Elena's Riposte | Elena | Swordsmanship 40 | Elena Trust 60 | Counter-disarm |
| War Cry | Practice | Intimidation 45 | -- | AoE morale check |
| Feint | Practice | Weapon proficiency 50 | -- | Opens enemy guard |
| Dirty Fighting | Varn | Melee combat 30 | Varn Trust 40 | +20% backstab, dirt blind |
| Commander's Rally | Aldric | Leadership 40 | Aldric Trust 70 | AoE ally buff |
| Shield Wall | Aldric | Blocking 50 | Aldric Trust 60 | Coordinated shield defense |
| Weapon Maintenance | Bjorn | Repair 30 | Bjorn Trust 35 | 50% slower degradation |
| Combo Chain (4-hit) | Practice | Weapon proficiency 70 | -- | Maximum combo |
| Lethal Precision | Practice | Weapon proficiency 80 | -- | Choose lethal/non-lethal |
| Boss's Gambit | Mira (post-reveal) | Insight 40 | Mira Trust 50 (Boss) | Earlier attack telegraphs |
| Fear Tactics | Varn | Intimidation 30 | Varn Trust 40 | Enhanced war cry |
| Interrogation | Synergy | Investigation 30 + Persuasion 30 | -- | Evidence-enhanced questioning |
| Profiling | Synergy | Investigation 30 + Insight 30 | -- | Read NPC secrets |
| Weapon Expertise | Synergy | Smithing 30 + Combat 30 | -- | +10% damage with forgeable weapons |
| Field Maintenance | Synergy | Smithing 30 + Repair 30 | -- | Tactical pause repair |
| Medicinal Cuisine | Synergy | Herbalism 25 + Cooking 25 | -- | Food heals over time |
| Commander | Synergy | Leadership 40 + Tactics 40 | -- | Enhanced ally combat bonuses |
| Infiltration | Synergy | Stealth 30 + Lockpicking 30 | -- | Combined covert entry |
| Manipulator | Synergy | Deception 40 + Insight 40 | -- | Detect AND tell lies |
| Master Trader | Synergy | Negotiation 30 + Appraisal 30 | -- | Full price transparency |
| Bladedancer | Synergy | Swordsmanship 40 + Dodging 40 | -- | Dodge-strike attack |
| Iron Guard | Synergy | Blocking 40 + Parrying 40 | -- | Enhanced defense |

---

## Appendix B: Skill Level Descriptors

Used in NPC Claude prompts and journal entries:

| Level Range | Descriptor | What NPCs See |
|------------|-----------|---------------|
| 0-10 | Untrained | "Has no idea what they're doing" |
| 11-20 | Novice | "Has the basics but is clearly inexperienced" |
| 21-30 | Apprentice | "Shows some competence, still learning" |
| 31-40 | Competent | "Knows what they're doing" |
| 41-50 | Proficient | "Handles themselves well" |
| 51-60 | Skilled | "Clearly experienced" |
| 61-70 | Expert | "Impressive ability" |
| 71-80 | Master | "Among the best I've seen" |
| 81-90 | Grandmaster | "Exceptional -- world-class" |
| 91-100 | Legendary | "The kind of skill songs are written about" |

---

*This document supersedes COMBAT_SYSTEM_DESIGN.md Section 9 (Skills and Progression) and extends it to cover all skill domains. The combat section's proficiency system, mentor techniques, and progression philosophy are preserved and expanded here.*
