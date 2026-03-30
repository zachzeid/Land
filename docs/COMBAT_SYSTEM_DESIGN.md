# Combat System Design Document

> **Date:** 2026-03-29
> **Status:** Design Document (no code yet)
> **Phase:** 7 (per DEVELOPMENT_PLAN.md)
> **Depends on:** BaseNPC, NPCPersonality, WorldState, EventBus, StoryFlags, 5D Relationship System, Autonomous NPC Agents, Emergent Narrative System

---

## 1. Combat Philosophy

### What Combat Means in Land

Combat in Land is **the failure state of diplomacy**. Every fight represents a moment where goals collided so violently that words stopped working. This is not a hack-and-slash game where combat is the primary verb. Combat is one tool among many -- and often not the best one.

**Core principles:**

1. **Every fight could have been avoided.** If combat starts, the player (or NPCs) chose not to pursue an alternative. The game should always communicate that alternatives exist.
2. **Combat has permanent consequences.** NPC death is permanent. Witnessed violence reshapes relationships. Killing changes how the world sees you.
3. **The 5D relationship system is the combat system.** Who fights, how hard they fight, whether they flee or surrender, and what happens after -- all driven by Trust, Respect, Affection, Fear, and Familiarity.
4. **NPCs fight for reasons, not for gameplay.** Varn attacks because you threaten his operation. Aldric fights because duty demands it. Elena fights because someone she loves is in danger. No NPC attacks "because they are an enemy."
5. **Non-lethal options are always present.** Intimidation, disarming, surrender, knockout, and retreat are first-class combat outcomes -- not afterthoughts.

### Inspirations and What to Take from Each

| Game | What to Take | What to Avoid |
|------|-------------|---------------|
| **Fable** | Real-time melee/ranged/magic triangle, open-world combat, moral reputation from violence | Simplistic morality, combat as primary loop |
| **Undertale** | Every enemy can be spared, mercy as a core mechanic, combat as communication | Abstract battle screen, turn-based grid |
| **Ys VIII/IX** | Fast real-time action, dodge/guard timing, party members with AI | Excessive enemy density, combat-first design |
| **Disco Elysium** | Violence as a last resort, skill checks as alternatives, consequences for aggression | No actual combat system (Land needs one) |
| **Dragon Age: Origins** | Companion combat behavior shaped by relationship, tactical pause, AI tactics | Separate combat/exploration modes |
| **Zelda: A Link to the Past** | Top-down 2D combat feel, simple but satisfying melee, environmental interaction | Enemies as obstacles without personality |
| **Persona 5** | Social links affecting combat power, all-out attacks, negotiation with enemies | Separate dungeon/overworld, random encounters |

### The Land Combat Identity

**Real-time with tactical pause.** Combat happens in the open world, in real time, but the player can pause to assess the situation, issue orders to allies, switch targets, or choose non-lethal options. This bridges the Fable-inspired action feel with the thoughtfulness a narrative-driven game demands.

---

## 2. Core Combat Mechanics

### 2.1 Combat Flow

```
TENSION STATE (pre-combat)
    NPC hostility rising, dialogue turning aggressive, threats exchanged
    Player can: de-escalate, intimidate, flee, or provoke
        |
        v
COMBAT INITIATION
    An NPC attacks, or player draws weapon, or world event triggers violence
    All nearby NPCs evaluate: fight, flee, watch, or intervene
        |
        v
ACTIVE COMBAT (real-time)
    Melee/ranged/ability attacks
    Block/dodge/parry defense
    Non-lethal options (intimidate, disarm, yield command)
    Allies act based on relationship + AI
    Tactical pause available at any time
        |
        v
COMBAT RESOLUTION
    Victory: enemies defeated (killed, knocked out, fled, surrendered)
    Defeat: player knocked out (not killed -- see Death section)
    Stalemate: both sides disengage
    Intervention: third party stops the fight
        |
        v
AFTERMATH
    Relationship changes propagate (witnesses, rumors)
    World flags update (NPC deaths, combat events)
    Reputation shifts (village learns what you did)
    Ripple engine processes consequences
```

### 2.2 Attack Types

**Melee Combat (Primary)**
- Light attack: fast, low damage, can chain 3-hit combo
- Heavy attack: slow, high damage, staggers target, breaks guard
- Directional: attacks go in the player's facing direction (up/down/left/right, matching existing `current_direction` in player.gd)

**Ranged Combat (Secondary)**
- Throwing weapons: knives, stones (limited supply, found/bought)
- Bow: slower, higher damage, requires aim time
- No homing -- player must aim in the 4 cardinal/8 directions

**Abilities (Unlockable)**
- Not magic in the traditional sense -- this is a grounded medieval world
- Combat techniques learned from mentors (see Section 9: Skills and Progression)
- Examples: shield bash (stun), feint (breaks guard), war cry (intimidate area), riposte (counter after parry)

### 2.3 Defense

**Block/Guard**
- Hold block button to reduce incoming damage (stamina cost per hit absorbed)
- Timed block (parry) within a window (~200ms) negates damage and staggers attacker
- Shields improve block effectiveness and parry window
- Cannot block while attacking or mid-dodge

**Dodge/Roll**
- Quick directional dodge with invincibility frames (~150ms i-frames)
- Costs stamina
- Creates distance, useful for resetting combat

**Armor**
- Passive damage reduction
- Different armor types: leather (light, fast), chain (medium), plate (heavy, slow)
- Armor affects movement speed slightly (5-15% reduction for heavier armor)

### 2.4 The Tactical Pause

At any time during combat, the player can press a button to pause the action. During pause:

- Time freezes (no attacks land, no movement)
- Player can survey the battlefield: see all combatants, their health, their stance
- Player can issue orders to allies (if present): "Focus this target," "Fall back," "Protect me"
- Player can select non-lethal options: "Demand surrender," "Attempt intimidation"
- Player can use consumable items
- Player can switch active weapon

This is not a menu-based combat system -- the pause is an overlay on the real-time action. Think Dragon Age: Origins on PC, not Final Fantasy's ATB.

---

## 3. Health, Stamina, and Damage System

### 3.1 Player Stats

| Stat | Range | Purpose |
|------|-------|---------|
| **Health (HP)** | 100 base, scales to ~200 | Damage tolerance. At 0, player is knocked out. |
| **Stamina (SP)** | 100 base, scales to ~150 | Fuels attacks, blocks, dodges. Regenerates over time. |
| **Resolve** | 0-100 | Mental fortitude. Affects intimidation resistance, morale in group fights. |

**Stamina regeneration:** 15 SP/second when not attacking or blocking. Reduced to 5 SP/second during active combat actions. Stops regenerating for 1 second after a stamina-depleting action.

**No mana system.** Combat abilities cost stamina. This keeps the system grounded and prevents a "caster vs fighter" split that does not fit the narrative.

### 3.2 NPC Stats

NPCs use the same stat model but with personality-driven values:

| NPC Archetype | HP | SP | Resolve | Notes |
|--------------|-----|-----|---------|-------|
| **Villager** (Tier 1) | 40-60 | 60 | 20-40 | Flees at 50% HP |
| **Peacekeeper** (Tier 1) | 70-90 | 80 | 50-60 | Fights with discipline |
| **Bandit Grunt** (Tier 1) | 60-80 | 70 | 30-50 | Flees if outnumbered |
| **Aldric** (Tier 0) | 120 | 100 | 85 | Military training, does not rout |
| **Varn** (Tier 0) | 110 | 90 | 70 | Skilled fighter, retreats tactically |
| **Elena** (Tier 0) | 70 | 80 | 55 | Untrained but determined |
| **Bjorn** (Tier 0) | 130 | 110 | 60 | Strong but not a trained fighter |
| **Gregor** (Tier 0) | 60 | 60 | 30 | Merchant, not a fighter |
| **Mira** (Tier 0) | 80 | 70 | 90 | Deceptively capable (The Boss) |

### 3.3 Damage Calculation

```
Base Damage = Weapon Damage + Strength Modifier
Reduced Damage = Base Damage - Armor Reduction
Final Damage = Reduced Damage * Circumstance Modifiers

Circumstance Modifiers:
  - Flanking: x1.25 (attacking from behind)
  - Staggered target: x1.5
  - Critical hit (timed attack): x1.75
  - Parried attacker: x2.0 (riposte)
  - Weakened (low resolve): x1.15
```

**Weapon damage ranges:**

| Weapon Type | Light Attack | Heavy Attack | Speed |
|------------|-------------|-------------|-------|
| Fists | 5-8 | 10-15 | Very Fast |
| Dagger | 8-12 | 15-20 | Fast |
| Short Sword | 12-18 | 22-30 | Medium |
| Long Sword | 15-22 | 28-38 | Medium-Slow |
| War Hammer | 18-25 | 35-48 | Slow |
| Staff | 8-12 | 18-25 | Medium |
| Bow (per arrow) | 15-25 | N/A | Slow (draw time) |
| Throwing Knife | 10-15 | N/A | Fast |

**Armor reduction:**

| Armor Type | Damage Reduction | Movement Penalty | Stamina Penalty |
|-----------|-----------------|-----------------|-----------------|
| None | 0 | 0% | 0% |
| Leather | 3-5 | 0% | 0% |
| Studded Leather | 5-8 | 5% | 5% |
| Chainmail | 8-12 | 10% | 10% |
| Plate | 12-18 | 15% | 15% |

### 3.4 Death and Defeat

**Player Defeat (HP reaches 0):**
- Player is knocked unconscious, not killed
- Screen fades to black
- Player wakes up: at the tavern (if Mira is alive and friendly), at their camp, or in a cell (if captured by bandits/peacekeepers)
- Time passes (half a game-day) -- NPC autonomous actions continue while player is out
- Consequences: items may be stolen, allies may have been hurt, the situation may have worsened
- No game-over screen, no reload -- the story continues from failure

**NPC Defeat:**
- **Knocked out (non-lethal):** NPC at 0 HP from fists, blunt weapons, or if attacker chose non-lethal. NPC recovers after combat. Relationship impact: moderate fear increase, some trust/respect loss.
- **Killed (lethal):** NPC at 0 HP from bladed weapons or if attacker intended lethal force. **Permanent death.** NPC is removed from the world. Massive relationship ripple. Quest implications. Story threads affected.
- **Surrendered:** NPC yielded before reaching 0 HP (see Section 6). NPC is alive and compliant. Relationship impact varies by circumstance.
- **Fled:** NPC ran away before being defeated. NPC relocates. May return later with reinforcements or different attitude.

**NPC Permadeath:**
Every Tier 0 NPC can die permanently. This is non-negotiable -- it is what makes combat meaningful in Land. The existing `WorldState.register_npc_death()` and `BaseNPC.is_alive` system already supports this. When a Tier 0 NPC dies:

1. `WorldState.register_npc_death()` is called with cause and killer
2. `EventBus.world_event` emits with death details
3. All NPCs who knew the dead NPC process grief/reaction via their agent loop
4. Story threads involving the dead NPC are evaluated (may resolve, fail, or transform)
5. Quests requiring the dead NPC fail or redirect
6. The NPC's physical node is removed from the scene tree
7. Future dialogue references the dead NPC in past tense

---

## 4. NPC Combat AI and Autonomous Combat Decisions

### 4.1 The Decision to Fight

NPCs do not fight because a designer placed them as enemies. They fight because their autonomous agent loop determined that violence serves their current goal better than alternatives.

**Combat Decision Flow (integrated into the Agent Loop from AUTONOMOUS_NPC_AGENTS.md):**

```
NPC Agent Tick → PERCEIVE threat
    |
    v
EVALUATE: Should I fight?
    |
    ├── Check goal alignment: Does fighting serve my goals?
    ├── Check relationship: What is my Trust/Fear toward the target?
    ├── Check capability: Can I win? (HP, weapons, allies nearby)
    ├── Check personality: Am I brave (low neuroticism)? Am I aggressive (low agreeableness)?
    ├── Check context: Is this public? Are there witnesses? Will this damage my reputation?
    |
    v
DECIDE:
    ├── FIGHT: Goal demands it, capability sufficient, personality supports it
    ├── FLEE: Outmatched, or Fear > willingness to fight
    ├── THREATEN: Test opponent's resolve before committing
    ├── CALL FOR HELP: Allies nearby, send for reinforcements
    ├── SUBMIT: Too afraid, too weak, or goal not worth dying for
    └── NEGOTIATE: Try to resolve without violence (Claude-escalated decision)
```

**Claude escalation for combat decisions:**

Complex combat decisions (Should Gregor fight back or surrender? Should Aldric intervene in a fight between the player and Varn? Should Elena pick up a sword to defend her father?) are escalated to Claude via the same system described in AUTONOMOUS_NPC_AGENTS.md:

```
You are [NPC Name]. A violent confrontation is happening. Choose ONE response.

PERSONALITY: [2-3 sentences]
GOALS: [current goals]
RELATIONSHIPS: {target: {trust, respect, fear}, player: {trust, respect, fear}, nearby_npcs: [...]}
SITUATION: [who is fighting whom, why, current HP states, witnesses]
YOUR COMBAT CAPABILITY: [weapon, HP, allies]

AVAILABLE RESPONSES:
1. fight(target="player") - Engage in combat
2. flee(destination="gregor_shop") - Run to safety
3. surrender() - Yield to the aggressor
4. intervene(side="player") - Join the fight on the player's side
5. intervene(side="varn") - Join the fight on Varn's side
6. call_for_help(target="aldric") - Summon allies
7. threaten(target="player", demand="leave") - Intimidate without attacking
8. protect(target="elena") - Shield a specific NPC

JSON: {"action": "action_id", "reason": "brief", "details": {}}
```

### 4.2 The 5D Relationship System in Combat

Each relationship dimension directly affects combat behavior:

**Trust (How much they believe in you)**
| Trust Level | Combat Effect |
|------------|--------------|
| 80-100 (Deep trust) | Will fight alongside you without hesitation. Shares combat resources. Takes hits for you. |
| 50-79 (Trusting) | Will join your side if asked. Follows combat orders. |
| 20-49 (Cautious) | May help if odds are good. Hesitates on risky orders. |
| -20 to 19 (Neutral) | Stays out of your fights. Watches. |
| -50 to -21 (Distrustful) | Refuses to help. May report your violence to others. |
| -100 to -51 (Hostile) | May attack you if provoked. Actively works against you. |

**Respect (How much they admire you)**
| Respect Level | Combat Effect |
|--------------|--------------|
| High (60+) | Fights with honor. Offers fair duels. Acknowledges defeat gracefully. More likely to surrender than fight to the death. |
| Neutral (0-59) | Standard combat behavior. |
| Low (-60 or below) | Fights dirty. Ambushes. Calls for unfair advantage. No mercy. |

**Affection (How much they like you)**
| Affection Level | Combat Effect |
|----------------|--------------|
| High (60+) | Will not initiate combat against you. Hesitates in combat. Pleads for alternatives. If forced to fight, pulls punches. |
| Moderate (20-59) | Normal combat. May express regret. |
| Low (-60 or below) | Fights with emotional intensity. Harder to surrender/yield. Personal vendetta. |

**Fear (How much they're afraid of you)**
| Fear Level | Combat Effect |
|-----------|--------------|
| High (60+) | Will not attack unless cornered. Surrenders quickly. Flees at first opportunity. Provides information under threat without combat needed. |
| Moderate (30-59) | Fights nervously. Makes mistakes. May freeze. Lower damage output (-15%). |
| Low (0-29) | Fights at full capability. Not intimidated by threats. |

**Familiarity (How well they know you)**
| Familiarity Level | Combat Effect |
|------------------|--------------|
| High (60+) | Predicts your patterns (harder to surprise). Knows your weaknesses. But also: harder to bring themselves to fight you. |
| Low (0-30) | Fights generically. Does not adapt to your tactics. But also: no emotional hesitation. |

### 4.3 NPC Combat Behavior Profiles

Each NPC's combat behavior emerges from their personality traits:

**Aldric (The Soldier):**
- `trait_conscientiousness: 85` -- Fights with discipline and tactics
- `trait_neuroticism: 35` -- Stays calm under pressure
- `is_protective: true` -- Will bodyguard allies
- `intimidation_susceptibility: 15` -- Nearly impossible to intimidate
- Combat style: Defensive, calculated, calls orders to allies. Retreats strategically, never routs.

**Varn (The Enforcer):**
- `trait_agreeableness: 15` -- Shows no mercy
- `trait_extraversion: 60` -- Taunts during combat
- `is_ambitious: true` -- Takes risks for power
- `intimidation_susceptibility: 10` -- Cannot be intimidated (unless massively outmatched)
- Combat style: Aggressive, dirty. Uses terrain. Retreats only to set ambushes.

**Elena (The Awakening Fighter):**
- `trait_openness: 70` -- Adapts quickly, learns from combat
- `is_protective: true` -- Fights fiercely when someone she loves is threatened
- `intimidation_susceptibility: 30` -- Brave but not foolhardy
- Combat style: Untrained but determined. Improves as story progresses (secret sword practice). Wild swings that become disciplined with mentoring.

**Bjorn (The Strong Man):**
- `trait_conscientiousness: 80` -- Methodical, powerful strikes
- `trait_neuroticism: 20` -- Unshakeable in combat
- `intimidation_susceptibility: 25` -- Hard to scare
- Combat style: Slow but devastating. Treats combat like smithing -- each blow deliberate. His hammers and weapons are superior quality.

**Gregor (The Desperate Father):**
- `trait_neuroticism: 45` -- Panics under pressure
- `is_fearful: true` -- Will flee rather than fight
- `intimidation_susceptibility: 50` -- Moderate -- fight-or-flight kicks in
- Combat style: Avoids combat entirely. If cornered, flails desperately. Will use a hidden dagger. The one thing that makes him fight: threatening Elena.

**Mira (The Hidden Boss):**
- Surface: Appears helpless, will not fight. Cries for help, hides.
- Reality (after `mira_boss_revealed`): Calculated, dangerous. Fights with concealed weapons. Has bodyguards. Uses the environment. Her `resolve: 90` means she never panics.

### 4.4 Group Combat AI

**Bandit Group Behavior:**
- Bandits coordinate: flanker, tank, ranged
- Leader (Varn or squad leader) issues orders via `call_for_help` / `coordinate` actions
- If leader falls, group morale drops -- grunts may flee
- Bandits disengage if casualties exceed 40% of group
- Will take hostages if available (nearby civilian NPCs)

**Peacekeeper Group Behavior:**
- Fight in formation if Aldric is present
- Without Aldric: fight bravely but individually (demoralized, per narrative)
- Will defend civilians and pull them from danger
- Never pursue -- hold defensive positions
- Rally if player demonstrates leadership (high respect with Aldric)

**Player + Ally Behavior:**
- Allies with Trust > 50 will join combat automatically
- Allies with Trust 30-50 will join if asked (tactical pause order)
- Player can issue simple orders during tactical pause: Attack, Defend, Retreat
- Allies fight according to their personality (Aldric defends, Bjorn smashes, Elena adapts)
- Ally AI is driven by the same NPC agent loop -- they make real decisions, not scripted patterns

---

## 5. Combat and Narrative Integration

### 5.1 Pre-Combat: The Tension Escalation

Before violence erupts, the narrative system builds tension. This connects directly to the Thread Tension system from EMERGENT_NARRATIVE_SYSTEM.md:

```
Thread tension 0.6-0.8 (Crisis):
    NPCs begin making threats
    Body language changes (weapon-touching verbal tics)
    Dialogue becomes confrontational
    Player has opportunities to de-escalate

Thread tension 0.8-1.0 (Breaking Point):
    NPCs may initiate combat autonomously
    Dialogue options narrow
    Violence becomes likely but not inevitable
    Last chance for intimidation/negotiation
```

**Combat as a thread resolution mechanism:**
- Thread 5 (Failing Watch) at breaking point: Aldric assaults Iron Hollow -- with or without the player
- Thread 7 (Bandit Expansion) at breaking point: Varn raids the village -- combat in the town square
- Thread 1 (Merchant's Bargain) at breaking point: Gregor is cornered -- may fight back desperately

### 5.2 During Combat: Narrative Moments

Combat is not just mechanical -- NPCs speak, emote, and react:

- Varn taunts: "You think you can stop what's coming? I've killed better than you."
- Elena screams if her father is attacked: "NO! Don't hurt him!"
- Aldric issues tactical commands: "Flank right! Don't let them regroup!"
- Gregor pleads if cornered: "Wait -- I can explain everything. Please!"
- Bjorn roars with guilt-fueled rage if fighting bandits with his weapons: "THOSE ARE MY BLADES!"

These are generated by Claude during combat, using the NPC's personality and the combat context. Short bursts (1-2 sentences) injected at key moments:
- Combat start
- NPC health drops below 50%
- An ally falls
- The tide turns (numerical advantage shifts)

### 5.3 Post-Combat: The Aftermath Engine

**Witness System:**
Every NPC within visual range (a configurable radius, ~200 pixels) of a combat event is a witness. Witnesses process what they saw through their agent loop:

```
Witness processing:
  What happened: [player killed Varn] | [player knocked out a peacekeeper] | [bandits attacked]
  Who was involved: [combatants list]
  Who won: [victor]
  How it ended: [death, surrender, flee, knockout]
  Was it justified: [based on witness's values and relationships]
      |
      v
  Relationship impact on witness:
    - Saw player defend the village: Trust +10, Respect +15
    - Saw player kill unarmed NPC: Trust -20, Fear +25, Respect -10
    - Saw player force surrender without killing: Respect +10, Fear +10
    - Saw player lose a fight: Respect -5
```

**Gossip Propagation:**
Combat events become InfoPackets that spread through the gossip system:

```
InfoPacket:
  content: "The outsider killed Varn in the town square"
  category: "fact"
  confidence: 1.0 (witnessed directly)
  spread_count: 0

After 2 hops:
  content: "I heard the outsider struck down the bandit lieutenant"
  confidence: 0.70
  spread_count: 2
```

**Reputation Effects:**

| Combat Action | Reputation Change | Who Cares |
|--------------|------------------|-----------|
| Kill a bandit | +Respect from village, -Trust from bandits | Everyone |
| Kill a villager | -Trust, +Fear from village | Everyone |
| Kill Varn | Major story event. Bandits destabilized. Village relieved but afraid of you. | All Tier 0 NPCs |
| Knock out (non-lethal) | +Respect (merciful), moderate Fear | Witnesses |
| Force surrender | +Respect, +Fear (you're dangerous but fair) | Witnesses + gossip |
| Lose a fight | -Respect from witnesses | Witnesses |
| Flee from fight | -Respect broadly, but some NPCs value pragmatism | Witnesses + gossip |
| Defend a civilian | +Trust, +Respect, +Affection from defended NPC | Witnesses + defended NPC |

### 5.4 Story Flags from Combat

New combat-related story flags to add to `story_flags.gd`:

```
# Combat outcome flags
const VARN_KILLED = "varn_killed"
const VARN_DEFEATED_NONLETHAL = "varn_defeated_nonlethal"
const VARN_SURRENDERED = "varn_surrendered"
const ALDRIC_KILLED = "aldric_killed"
const ELENA_KILLED = "elena_killed"
const GREGOR_KILLED = "gregor_killed"
const BJORN_KILLED = "bjorn_killed"
const MIRA_KILLED = "mira_killed"

# Combat event flags
const IRON_HOLLOW_ASSAULT_SUCCESS = "iron_hollow_assault_success"
const IRON_HOLLOW_ASSAULT_FAILED = "iron_hollow_assault_failed"
const VILLAGE_DEFENDED_FROM_RAID = "village_defended_from_raid"
const VILLAGE_RAID_FAILED = "village_raid_failed"  # player failed to defend

# Combat reputation flags
const PLAYER_KNOWN_KILLER = "player_known_killer"
const PLAYER_KNOWN_MERCIFUL = "player_known_merciful"
const PLAYER_KNOWN_COWARD = "player_known_coward"
const PLAYER_KNOWN_DEFENDER = "player_known_defender"
```

---

## 6. Non-Lethal Options and Narrative Consequences

### 6.1 The Non-Lethal Toolkit

Non-lethal resolution is not a side feature -- it is equally developed as lethal combat:

**Intimidation (pre-combat and during combat):**
- Available when player's Fear rating with target is significant, or player demonstrates overwhelming force
- Calculation: `success = (player_threat_score + target_fear_of_player) > target_resolve`
- `player_threat_score` = weapon quality + visible allies + combat reputation + recent kills witnessed
- Success: Target surrenders, flees, or complies with a demand
- Failure: Target attacks (they were going to anyway, now they're angry)
- Partial success: Target hesitates, giving player initiative

**Surrender Demand (during combat, tactical pause):**
- Available when target HP < 40% OR target morale is broken (allies fled/died)
- Player issues "Yield!" command
- Target evaluates: Can I still win? Is death preferable to surrender? What happens if I yield?
- NPC personality affects response:
  - Varn (`forgiveness_tendency: 5`): Will fight to the death rather than yield to someone he does not respect. Might yield if Respect > 60.
  - Gregor (`is_fearful: true`): Yields quickly under pressure
  - Aldric (`intimidation_susceptibility: 15`): Will never yield to bandits. May yield to an honorable opponent.

**Disarming:**
- Special attack available after a successful parry
- Forces target to drop their weapon
- Disarmed NPC must decide: fight unarmed, flee, or surrender
- Most NPCs surrender when disarmed (unless cornered or fanatical)

**Knockout:**
- Using fists or blunt weapons when target HP reaches 0 causes knockout instead of death
- Player can choose "non-lethal finishing blow" when target is staggered at low HP
- Knocked-out NPCs wake up after combat with 10% HP
- Relationship impact: Fear increases but Trust/Respect loss is much less than killing

**Escape/De-escalation:**
- Player can sheathe weapon during combat to signal non-hostility
- If done while winning (enemy HP < player HP), enemies may accept de-escalation
- If done while losing: enemy may let you go (high affection) or press the advantage (low affection)

### 6.2 Surrender Mechanics

When an NPC surrenders, a brief Claude-generated dialogue scene plays:

```
[Combat pauses]
[Surrendered NPC raises hands / drops weapon]

NPC (generated by Claude based on personality + situation):
"Alright! Alright, I yield. I'm not dying for a few gold coins."

Player options:
1. "Tell me everything." (Interrogation -- NPC reveals information based on what they know)
2. "Drop your weapons and leave." (Mercy -- NPC flees, may return reformed or vengeful)
3. "You're coming with me." (Capture -- NPC becomes prisoner, can be brought to Aldric/council)
4. [Attack anyway] (Executing a surrendered enemy -- massive reputation/relationship consequences)
```

**What surrendered NPCs reveal:**
- Bandit grunts: patrol routes, camp layout, number of fighters
- Varn (if ever surrenders): information about operations, Gregor's involvement (will not reveal Mira as Boss -- unbreakable secret)
- Gregor (surrenders easily): confesses his arrangement, pleads for Elena's safety

**Executing a surrendered enemy:**
- Witnesses: Trust -30, Fear +40, Respect -20 from all witnesses
- Gossip spreads: "The outsider murdered a man who surrendered"
- Aldric (if alive): loses all trust in player. Will not ally with someone who executes prisoners.
- Sets `player_known_killer` flag

### 6.3 Non-Lethal Endgame Options

The narrative's climactic confrontations should all support non-lethal resolution:

**Iron Hollow Assault:**
- Full military assault (lethal, Aldric's plan)
- Infiltration and sabotage (disable without killing)
- Siege and negotiation (surround camp, demand surrender)
- Internal coup (turn Varn's ambition against The Boss)

**Confronting Gregor:**
- Evidence + witnesses at council (political, no violence)
- Private confrontation (threaten but do not harm)
- Redemption path (Gregor turns state's evidence)

**Confronting Mira/The Boss:**
- Expose her publicly (social, no violence)
- Private blackmail (leverage without combat)
- Varn's coup forces her hand (violence between bandits, player can stay out)

---

## 7. NPC-vs-NPC Combat

### 7.1 Autonomous NPC Combat

NPCs can and will fight each other based on their agent loop decisions. This is one of Land's most distinctive features.

**When NPC-vs-NPC combat happens:**

| Thread | Combat Event | Trigger |
|--------|-------------|---------|
| Thread 5 + 7 | Aldric's peacekeepers vs. bandit raiding party | Thread 5 tension > 0.8 (premature assault) or Thread 7 tension > 0.8 (bandits raid village) |
| Thread 1 + 4 | Bjorn confronts Gregor physically | Bjorn learns truth about weapons AND `trait_agreeableness: 55` is overridden by horror |
| Thread 7 | Varn's coup against The Boss | Varn's ambition peaks, Thread 7 tension > 0.9 |
| Thread 3 | Elena defends her father against attackers | Anyone attacks Gregor while Elena is present |
| General | Bandits attack a merchant caravan | Seed event from off-screen simulation |

### 7.2 On-Screen NPC-vs-NPC Combat (Player Can Intervene)

When the player is present during NPC-vs-NPC combat:

1. Combat initiates normally -- NPCs enter combat state
2. Player receives visual/audio notification: combat sounds, NPC shouts
3. Player has choices:
   - **Intervene on one side:** Run into combat, attack one side. Allied NPCs recognize your allegiance.
   - **Intervene as mediator:** Enter combat zone, sheathe weapon, attempt to de-escalate (risky)
   - **Watch:** Stand back and observe. Witnesses note your inaction.
   - **Leave:** Walk away. You were not involved. But: did you abandon someone who needed you?

**Player intervention affects:**
- Relationships with both sides (joining Aldric against bandits: +Trust from Aldric, -Trust from Varn)
- Witnesses remember which side you chose
- Combat outcome may depend on player's involvement (Aldric's premature assault may fail without player, succeed with player)

### 7.3 Off-Screen NPC-vs-NPC Combat (Tier 2-3)

Not all combat needs to be simulated blow-by-blow. When the player is not present:

**Statistical Resolution:**

```
func resolve_offscreen_combat(side_a: Dictionary, side_b: Dictionary) -> Dictionary:
    # side = {npcs: [...], morale: float, equipment_quality: float, tactical_advantage: float}

    score_a = side_a.fighters * side_a.equipment_quality * side_a.morale * side_a.tactical_advantage
    score_b = side_b.fighters * side_b.equipment_quality * side_b.morale * side_b.tactical_advantage

    # Add randomness
    score_a *= randf_range(0.7, 1.3)
    score_b *= randf_range(0.7, 1.3)

    winner = "side_a" if score_a > score_b else "side_b"
    margin = abs(score_a - score_b) / max(score_a, score_b)

    casualties_winner = int(winner_count * randf_range(0.05, 0.15) * (1.0 - margin))
    casualties_loser = int(loser_count * randf_range(0.20, 0.50) * (1.0 + margin))

    return {winner, casualties_winner, casualties_loser, named_npc_fates}
```

**Named NPC survival in off-screen combat:**
- Tier 0 NPCs have a survival bonus (they are important characters)
- Survival chance: `base_survival * (hp_factor * resolve_factor)`
- Aldric in a lost battle: 70% survival (military training, knows when to retreat)
- Elena in a battle: 85% survival (people protect her, she has instincts)
- If a Tier 0 NPC dies off-screen, the player discovers the aftermath (body, grieving NPCs, empty shop)

**Off-screen combat results become world events:**

```
InfoPacket:
  content: "The peacekeepers fought a bandit raiding party at the north road. Two peacekeepers were wounded. The bandits were driven off but one escaped."
  category: "fact"
  confidence: 0.9
```

The player learns about these events through NPC dialogue, environmental changes, and gossip.

---

## 8. Weapons, Armor, and Equipment System

### 8.1 Weapon Types

| Type | Subtypes | Damage Profile | Special |
|------|----------|---------------|---------|
| **Blades** | Dagger, Short Sword, Long Sword | Slashing/piercing, balanced | Lethal by default |
| **Blunt** | Club, Mace, War Hammer | Crushing, high stagger | Non-lethal by default (knockout) |
| **Polearms** | Spear, Halberd | Reach advantage, thrust | Keeps enemies at distance |
| **Ranged** | Short Bow, Throwing Knives | Projectile damage | Requires ammunition |
| **Improvised** | Bottle, Chair, Pitchfork | Low damage, breaks | Available in environment |
| **Shield** | Buckler, Round Shield, Tower Shield | Defensive, shield bash | Pairs with one-handed weapons |

### 8.2 Equipment Slots

```
Player Equipment:
  Main Hand: weapon (sword, mace, etc.)
  Off Hand: shield, second weapon, or empty (two-handed weapons use both slots)
  Armor: body armor (leather, chain, plate)
  Accessory: one accessory slot (ring, amulet, cloak)
```

Simple and restrained -- this is not a loot-driven game. Equipment matters but does not dominate.

### 8.3 Bjorn's Weapons: The Maker's Mark

Bjorn's weapons are central to the narrative. Every weapon he forges carries a small "B" on the tang.

**Mechanical significance:**
- Bjorn-forged weapons have +10% damage and +5% parry window (superior craftsmanship)
- They are visually distinct (subtle sprite difference or tooltip)
- When the player finds a "B"-marked weapon on a dead bandit, it becomes evidence (`weapons_traced_to_bjorn` flag)
- Bjorn can identify any weapon he made: "That's my work. Where did you get that?"

**Narrative significance:**
- Showing Bjorn a marked weapon found on a bandit triggers his crisis of conscience
- After his revelation, Bjorn forges weapons for the resistance at no cost -- these are his best work
- Bjorn's weapons found at Iron Hollow prove the Gregor supply chain
- The player's own weapons can be Bjorn-forged (bought or gifted), giving them a personal connection to the smith

### 8.4 Weapon Quality Tiers

| Quality | Damage Modifier | Source | Notes |
|---------|----------------|--------|-------|
| **Improvised** | x0.6 | Found in world | Breaks after ~10 hits |
| **Poor** | x0.8 | Bandit drops, old weapons | Functional but worn |
| **Standard** | x1.0 | Shops, standard loot | Baseline |
| **Fine** | x1.1 | Bjorn's regular work | Bjorn-made, reliable |
| **Superior** | x1.25 | Bjorn's best work (post-revelation) | Made with purpose and fury |
| **Legendary** | x1.4 | Bjorn's masterwork (one weapon, end-game) | A blade forged to end the bandit threat |

### 8.5 Equipment Acquisition

- **Purchase:** Buy from Gregor's shop (irony: his weapons arm you AND the bandits) or traveling merchants
- **Loot:** Dropped by defeated enemies. Bandit weapons are Poor-Standard quality.
- **Gift:** NPCs with high Trust/Affection may gift equipment. Bjorn gifts a Fine weapon at Trust 50+.
- **Craft Request:** Ask Bjorn to forge something specific (requires materials + payment or high relationship)
- **Found:** Hidden in the world. Aldric's weapon cache under the old well. Elena's practice sword.

---

## 9. Skills and Progression

### 9.1 Progression Philosophy

The player does not gain arbitrary XP from killing enemies. Progression is **practice-based and mentor-based** -- you get better at what you do, and you learn from the people around you.

### 9.2 Practice-Based Improvement

```
Combat Proficiency System:
  Each weapon type has a proficiency level (0-100)
  Proficiency increases through USE:
    - Light attack landed: +0.5 proficiency
    - Heavy attack landed: +1.0 proficiency
    - Successful parry: +1.5 proficiency
    - Successful dodge: +0.5 proficiency (general combat skill)
    - Defeated an enemy: +3.0 proficiency

  Proficiency thresholds:
    0-20: Novice (basic attacks only, slow, telegraphed)
    21-40: Apprentice (combo chains unlock, slightly faster)
    41-60: Competent (special attacks available, good timing)
    61-80: Skilled (advanced techniques, fast recovery)
    81-100: Master (all techniques available, maximum efficiency)
```

**What proficiency affects:**
- Attack speed (higher proficiency = 10-20% faster at max)
- Combo length (novice: 2-hit, skilled: 3-hit, master: 4-hit)
- Parry window (novice: 150ms, master: 250ms)
- Stamina efficiency (master uses 15% less stamina per action)
- Unlocks specific techniques at thresholds

### 9.3 Mentor-Based Learning

This is where the relationship system directly enhances combat. NPCs can teach the player techniques based on their own combat knowledge and the player's relationship with them.

**Elena (Secret Sword Practice)**
- Requirement: Trust > 40, discover her practicing (story flag or stumble upon her)
- Teaches: Basic sword forms (accelerates sword proficiency gain by 50%)
- At Trust > 60: Teaches a unique technique -- "Elena's Riposte" (counter-attack that knocks enemy weapon aside)
- Narrative hook: Teaching Elena in return improves her combat capability as an ally

**Aldric (Military Training)**
- Requirement: Trust > 50, `aldric_ally` flag
- Teaches: Tactical Combat (+15% damage when flanking, +10% block efficiency)
- At Trust > 70: Teaches "Commander's Rally" (boost allies' damage by 10% for 15 seconds, area shout)
- At Trust > 80: Teaches "Shield Wall" (if allies with shields present, coordinated defense)
- Narrative hook: Training with Aldric happens at the peacekeeper camp. Other NPCs see you training. Reputation effect.

**Varn (Brutal Fighting)**
- Requirement: Joined bandits path OR Trust > 60 through bandit alliance
- Teaches: Dirty Fighting (+20% damage from behind, can throw dirt to blind)
- Teaches: Intimidation Technique (boosts intimidation success rate)
- Narrative hook: Learning from Varn teaches you effective but dishonorable tactics. NPCs who value honor (Aldric, Bjorn) lose Respect for you if they find out.

**Bjorn (Weapon Mastery)**
- Requirement: Trust > 50, help him in the forge
- Does not teach combat directly, but:
- Teaches weapon maintenance: Bjorn-quality weapons last longer, can repair equipment
- At Trust > 70: Forges a custom weapon tuned to your fighting style (+5% proficiency gain)
- Narrative hook: Working the forge builds Affection and Respect. Physical labor as bonding.

**Mira (after Boss reveal)**
- Requirement: `mira_boss_revealed`, player did not immediately turn hostile
- Teaches: "The Boss's Gambit" -- read opponent's intention before they attack (brief telegraph indicator)
- Teaches: Poison application to weapons (morally gray -- lethal, dishonorable)
- Narrative hook: Accepting training from the villain. What does that say about you?

### 9.4 Skill Tree (Technique Unlocks)

Not a traditional branching tree. Instead, a flat list of techniques unlocked by proficiency thresholds and mentor training:

| Technique | Requirement | Effect |
|-----------|------------|--------|
| Combo Chain (3-hit) | Proficiency 25 in weapon type | Extended basic combo |
| Power Strike | Proficiency 30 | Charged heavy attack, extra stagger |
| Parry Counter | Proficiency 40 + Aldric OR practice | Riposte after successful parry |
| Elena's Riposte | Elena mentor + Trust 60 | Counter that disarms |
| Dirty Fighting | Varn mentor OR proficiency 50 | Attacks from behind deal +20% |
| Commander's Rally | Aldric mentor + Trust 70 | AoE ally buff |
| Shield Bash | Proficiency 35 + shield equipped | Stun enemy for 1.5s |
| War Cry | Proficiency 45 | AoE intimidation check on all enemies |
| Feint | Proficiency 50 | Fake attack that opens enemy guard |
| Combo Chain (4-hit) | Proficiency 70 in weapon type | Maximum combo length |
| Weapon Maintenance | Bjorn mentor + Trust 50 | Weapons degrade 50% slower |
| Lethal Precision | Proficiency 80 | Choose lethal vs non-lethal on any weapon |
| Boss's Gambit | Mira mentor (post-reveal) | See enemy attack telegraphs earlier |

---

## 10. Off-Screen Combat Resolution (Tier 2-3)

### 10.1 Purpose

The world is larger than what the player sees. Bandits patrol. Peacekeepers defend. Caravans are attacked. Factions clash. These events happen as part of the off-screen simulation described in AUTONOMOUS_NPC_AGENTS.md and should produce meaningful results that the player encounters.

### 10.2 Resolution System

Off-screen combat is resolved during game-day ticks (Tier 2-3 batch processing via Haiku on Bedrock):

```
OffscreenCombatEvent:
  id: String
  location: String               # Where it happens
  side_a: {
    faction: String,             # "peacekeepers", "bandits", "merchants"
    strength: int,               # Number of fighters
    equipment: float,            # 0.0-1.0 quality
    morale: float,               # 0.0-1.0
    leadership: String,          # NPC ID of leader (or "none")
    tactics: float               # 0.0-1.0 tactical skill
  }
  side_b: { same structure }
  context: String                # Why this fight happened
  player_can_encounter: bool     # True if player could stumble into this
```

**Resolution formula:**

```
combat_power(side) = strength * equipment * morale * (1.0 + tactics * 0.3)
                     * leadership_bonus  # 1.2 if Tier 0 NPC leads, 1.0 otherwise

roll_a = combat_power(side_a) * randf_range(0.7, 1.3)
roll_b = combat_power(side_b) * randf_range(0.7, 1.3)

outcome:
  decisive_victory: winner_roll > loser_roll * 1.5  (loser routed, high casualties)
  victory: winner_roll > loser_roll                 (loser retreats, moderate casualties)
  stalemate: rolls within 10% of each other         (both sides retreat, low casualties)
```

### 10.3 Consequences Feed Into the World

Off-screen combat results:
1. Update faction strength (`bandits_strength -= casualties`)
2. May kill or wound named NPCs (with survival bonuses for Tier 0)
3. Generate WorldEvents that enter the gossip system
4. Update thread tensions (successful bandit raid: Thread 7 tension +0.1)
5. Create environmental evidence (player finds aftermath: blood, abandoned weapons, damaged buildings)
6. May trigger emergent quests ("The North Road Ambush" -- help wounded merchants)

---

## 11. Godot 4 Implementation Approach

### 11.1 Architecture Overview

```
CombatSystem (Autoload Singleton)
  |
  ├── CombatManager
  |     ├── Tracks active combats (multiple can be simultaneous)
  |     ├── Manages combat state (pre-combat, active, resolution)
  |     ├── Handles tactical pause
  |     └── Routes combat events to EventBus
  |
  ├── DamageCalculator
  |     ├── Pure calculation functions
  |     ├── Weapon stats, armor reduction, modifiers
  |     └── Critical hit / parry resolution
  |
  ├── CombatAI
  |     ├── NPC combat decision-making
  |     ├── Group coordination
  |     ├── Flee/surrender evaluation
  |     └── Claude escalation for complex decisions
  |
  └── OffscreenCombatResolver
        ├── Statistical combat resolution
        ├── Named NPC fate determination
        └── Result → WorldEvent conversion
```

### 11.2 Hitbox/Hurtbox System

Using Godot's Area2D system for combat detection:

```
CharacterBody2D (Player or NPC)
  |
  ├── CollisionShape2D         # Physics collision (movement)
  |
  ├── Hitbox (Area2D)          # Deals damage (active during attacks)
  |   └── CollisionShape2D     # Shape varies by weapon type
  |       - Sword: Rectangle extending from character
  |       - Hammer: Wider rectangle, shorter reach
  |       - Bow: Projectile spawned separately
  |
  ├── Hurtbox (Area2D)         # Receives damage (always active)
  |   └── CollisionShape2D     # Slightly smaller than physics collision
  |
  └── DetectionRange (Area2D)  # Awareness radius for combat AI
      └── CollisionShape2D     # Circle, ~200px radius
```

**Collision layers:**

| Layer | Name | Purpose |
|-------|------|---------|
| 1 | Player | Player physics |
| 2 | NPCs | NPC physics |
| 3 | Walls | Environment collision |
| 4 | Player Hitbox | Player's attack area |
| 5 | NPC Hitbox | NPC attack areas |
| 6 | Player Hurtbox | Player's damageable area |
| 7 | NPC Hurtbox | NPC damageable areas |
| 8 | Detection | Combat awareness triggers |

**Hit detection flow:**

```
1. Player presses attack → Attack animation plays
2. At attack frame, Hitbox Area2D is enabled (collision shape active)
3. Hitbox.area_entered signal fires if overlapping with any Hurtbox
4. DamageCalculator processes the hit
5. Damage applied to target
6. Hit reaction animation plays on target
7. Hitbox disabled at end of attack frame
```

### 11.3 Combat State Machine

Both the player and NPCs use an AnimationTree-driven state machine for combat:

```
States:
  IDLE          → Can move, can attack, can block
  ATTACKING     → In attack animation, hitbox active, cannot move
  BLOCKING      → Reduced damage, cannot attack, can move slowly
  DODGING       → Invincible, moving in dodge direction, cannot attack
  STAGGERED     → Hit by heavy attack or guard broken, cannot act for ~0.5s
  KNOCKED_DOWN  → On the ground after heavy hit, must recover (~1.5s)
  DEFEATED      → HP at 0, combat over for this entity
  FLEEING       → Running away, reduced defense, increased speed
  SURRENDERED   → Combat over, dialogue state

Transitions:
  IDLE → ATTACKING:   Attack input + stamina available
  IDLE → BLOCKING:    Block input held
  IDLE → DODGING:     Dodge input + stamina available
  ANY → STAGGERED:    Hit by heavy attack while not blocking, or guard broken
  ANY → KNOCKED_DOWN: Hit while staggered
  ANY → DEFEATED:     HP reaches 0
  ANY → FLEEING:      NPC decision (fear/morale check)
  ANY → SURRENDERED:  NPC decision (yield evaluation)
```

### 11.4 Animation-Driven Combat

Combat timing is driven by AnimatedSprite2D frame callbacks:

```gdscript
# In the attack animation, specific frames trigger events:
# Frame 3: "wind_up" - telegraph visible to player
# Frame 5: "hit_active" - hitbox enabled, damage can occur
# Frame 7: "hit_end" - hitbox disabled
# Frame 9: "recovery" - can cancel into next action

func _on_animation_frame_changed():
    var frame = animated_sprite.frame
    match current_attack_state:
        "light_attack":
            if frame == 5: enable_hitbox()
            if frame == 7: disable_hitbox()
            if frame == 9: can_chain_next_attack = true
```

### 11.5 Key Godot Nodes and Resources

**New scripts to create:**

| Script | Type | Purpose |
|--------|------|---------|
| `scripts/combat/combat_manager.gd` | Autoload | Central combat coordination |
| `scripts/combat/damage_calculator.gd` | RefCounted | Pure damage math |
| `scripts/combat/combat_ai.gd` | Node | NPC combat decision-making |
| `scripts/combat/hitbox.gd` | Area2D | Damage-dealing collision |
| `scripts/combat/hurtbox.gd` | Area2D | Damage-receiving collision |
| `scripts/combat/combat_state_machine.gd` | Node | State machine for combat entities |
| `scripts/combat/offscreen_combat.gd` | RefCounted | Off-screen resolution |
| `scripts/combat/weapon_resource.gd` | Resource | Weapon stats definition |
| `scripts/combat/armor_resource.gd` | Resource | Armor stats definition |
| `scripts/combat/combat_proficiency.gd` | Resource | Player proficiency tracking |
| `scripts/combat/tactical_pause_ui.gd` | Control | Tactical pause overlay |

**New resources:**

| Resource | Purpose |
|----------|---------|
| `resources/weapons/*.tres` | Individual weapon definitions |
| `resources/armor/*.tres` | Individual armor definitions |
| `resources/combat_profiles/*.tres` | NPC combat behavior profiles |

**New EventBus signals:**

```gdscript
# Combat signals (add to event_bus.gd)
signal combat_initiated(attacker_id: String, defender_id: String, context: Dictionary)
signal combat_ended(combat_id: String, result: Dictionary)
signal npc_defeated(npc_id: String, defeated_by: String, method: String)  # method: "killed", "knockout", "surrendered", "fled"
signal npc_surrendered(npc_id: String, to_whom: String)
signal combat_witnessed(witness_id: String, combat_data: Dictionary)
signal intimidation_attempted(source_id: String, target_id: String, success: bool)
signal player_defeated(defeated_by: String, location: String)
signal combat_reputation_changed(player_reputation: Dictionary)
```

---

## 12. Integration with Story Threads, Ripple Engine, and Quest Emergence

### 12.1 Combat as Thread Resolution

Combat events directly affect thread tensions from EMERGENT_NARRATIVE_SYSTEM.md:

| Combat Event | Thread(s) Affected | Tension Change |
|-------------|-------------------|----------------|
| Player defeats bandit patrol | Thread 7 (Bandit Expansion) | -0.10 |
| Bandits raid village | Thread 7 | +0.15 |
| Aldric's premature assault fails | Thread 5 (Failing Watch) | +0.30 (catastrophic) |
| Aldric's assault succeeds (with player) | Thread 5, 7 | Thread 5 resolved, Thread 7 -0.30 |
| Varn killed | Thread 7 | -0.20 (bandits weakened) but Thread 2 +0.15 (Mira must adapt) |
| Gregor killed in combat | Thread 1, 3 | Both reach crisis immediately |
| Player defends village from raid | Thread 5, 6 | +0.15 each (resistance grows, council may act) |
| Bjorn fights Gregor | Thread 1, 4 | Both escalate dramatically |

### 12.2 Combat-Emergent Quests

New quest emergence rules triggered by combat events:

**"The Captain's Gambit"** (Thread 5, tension > 0.7)
- Aldric plans a premature assault on Iron Hollow
- Player can: join and help (combat), convince him to wait (diplomacy), or let it happen (consequences)
- If player joins: combat encounter at Iron Hollow with peacekeeper allies
- If player does not join and assault fails: `aldric_killed` possibility, village demoralized

**"Blood on the Square"** (Thread 7, tension > 0.8)
- Bandits raid Thornhaven town square
- Player must defend or hide
- NPC allies join based on Trust: Aldric (Trust > 30), Bjorn (Trust > 40 + `bjorn_allied`), Elena (Trust > 50 + she has a weapon)
- Outcome: shapes whether village rallies or submits

**"The Duel"** (Thread 7, player Respect > 60 with Varn)
- Varn respects the player enough to offer single combat
- Formal duel: no allies, no flee, fight to yield or death
- If player wins: Varn yields information, or dies
- If player loses: Varn takes something (weapon, information) but does not kill (honor between fighters)

**"Father's Shield"** (Thread 1 + 3, combat near Gregor while Elena present)
- Elena intervenes in combat involving her father
- She is under-equipped and under-trained (unless player mentored her)
- Player must protect her while managing the actual threat
- Outcome: shapes Elena's arc (does she become a fighter or does trauma push her away from violence?)

### 12.3 Ripple Engine Integration

Combat events generate ripples that propagate through the existing ripple system:

```
Combat Ripple Template:
  event: "npc_killed"
  source: combat_event
  ripples:
    IMMEDIATE (0 game-hours):
      - Witnesses update relationships (fear, trust, respect)
      - Nearby NPCs react (flee, approach, freeze)
      - Combat participants enter post-combat state

    SHORT_TERM (1-6 game-hours):
      - Gossip packets generated and begin spreading
      - Allied faction responds (bandits seek revenge, peacekeepers honor fallen)
      - Related NPCs enter grief/anger/relief states

    MEDIUM_TERM (1-3 game-days):
      - Faction strength updates (one fewer bandit, one fewer peacekeeper)
      - Power vacuum effects (Varn's death destabilizes Iron Hollow)
      - Quest implications resolve (quests requiring dead NPC fail/redirect)
      - Thread tensions update

    LONG_TERM (3+ game-days):
      - Village reputation stabilizes (player is known as killer/defender/coward)
      - New equilibrium: NPCs adjust their plans around the new reality
      - Possible ending condition evaluation
```

---

## 13. Implementation Priority (Phased Plan)

### Phase 7A: Core Combat Foundation (2-3 weeks)

**Goal:** Player can attack and be attacked. Basic hit detection works. Damage is dealt.

| Task | Priority | Notes |
|------|----------|-------|
| Hitbox/Hurtbox Area2D setup on player | P0 | Extend `player.tscn` |
| Hitbox/Hurtbox Area2D setup on BaseNPC | P0 | Extend base NPC scene |
| CombatStateMachine (player) | P0 | IDLE/ATTACKING/BLOCKING/STAGGERED/DEFEATED |
| Basic light/heavy attack | P0 | Direction-based, frame-driven |
| Basic blocking | P0 | Hold to block, stamina drain |
| DamageCalculator (simple) | P0 | Weapon damage - armor = final |
| Health system on player | P0 | HP bar, damage, defeat |
| Health system on NPCs | P0 | HP tracking, defeat state |
| Player defeat handling | P0 | Knockout, fade to black, wake up |
| NPC death handling | P0 | Integrate with existing `register_npc_death()` |
| Attack animations (placeholder) | P0 | Directional attack sprites |
| CombatManager singleton | P0 | Track active combats, route events |

**New EventBus signals:** `combat_initiated`, `combat_ended`, `npc_defeated`, `player_defeated`

### Phase 7B: NPC Combat AI (2 weeks)

**Goal:** NPCs can fight the player and each other with personality-driven behavior.

| Task | Priority | Notes |
|------|----------|-------|
| CombatAI node for NPCs | P0 | Decision-making: fight/flee/surrender |
| NPC attack behavior | P0 | Basic AI: approach, attack, retreat |
| NPC flee behavior | P1 | When HP low or fear high |
| NPC surrender behavior | P1 | When HP low and resolve broken |
| Group combat coordination | P1 | Flanking, leader commands |
| Relationship-driven combat entry | P1 | Trust/Fear thresholds for ally/enemy |
| Combat awareness (DetectionRange) | P1 | NPCs notice nearby combat |
| Integration with NPC agent loop | P1 | Combat as an agent action |

### Phase 7C: Non-Lethal System (1-2 weeks)

**Goal:** Every fight has alternatives. Intimidation, surrender, knockout all work.

| Task | Priority | Notes |
|------|----------|-------|
| Intimidation system | P0 | Pre-combat and during combat |
| Surrender demand mechanic | P0 | Tactical pause option |
| Knockout vs kill distinction | P0 | Blunt = KO, blade = kill |
| Surrender dialogue (Claude) | P1 | Brief generated scene post-surrender |
| Disarm mechanic | P1 | After parry, special input |
| De-escalation (sheathe weapon) | P2 | Signal non-hostility |
| Non-lethal finishing blow | P1 | Choose mercy at low HP |

### Phase 7D: Tactical Pause and Allies (1-2 weeks)

**Goal:** Player can pause combat, survey the field, issue ally orders.

| Task | Priority | Notes |
|------|----------|-------|
| Tactical pause (freeze time) | P0 | Overlay UI |
| Battlefield survey (show NPC HP, stance) | P1 | Information display |
| Ally order system | P1 | Attack/Defend/Retreat commands |
| Ally join combat (Trust-gated) | P1 | NPCs join automatically or on request |
| Item use during pause | P2 | Consumables |

### Phase 7E: Weapons, Equipment, Progression (1-2 weeks)

**Goal:** Weapon/armor resources work. Proficiency tracks. Mentors teach.

| Task | Priority | Notes |
|------|----------|-------|
| WeaponResource and ArmorResource | P0 | Data definitions |
| Equipment slots on player | P0 | Main hand, off hand, armor, accessory |
| Weapon quality tiers | P1 | Bjorn marks, quality modifiers |
| Combat proficiency tracking | P1 | Practice-based improvement |
| Mentor system (learn from NPCs) | P2 | Relationship-gated technique unlocks |
| Bjorn weapon evidence (marked blades) | P1 | Narrative integration |

### Phase 7F: Narrative Integration (1-2 weeks)

**Goal:** Combat has story consequences. Witnesses react. Reputation propagates.

| Task | Priority | Notes |
|------|----------|-------|
| Witness system | P0 | NPCs in range process combat events |
| Post-combat relationship changes | P0 | Trust/Fear/Respect updates |
| Combat gossip generation | P1 | InfoPackets from combat events |
| Combat story flags | P1 | Death flags, reputation flags |
| Thread tension updates from combat | P1 | Connect to ThreadManager |
| Combat-emergent quest triggers | P2 | Quest emergence from combat events |
| Off-screen combat resolution | P2 | Statistical system for Tier 2-3 |

### Phase 7G: Polish and Tuning (1 week)

| Task | Priority | Notes |
|------|----------|-------|
| Damage number tuning | P1 | Balance pass on all values |
| AI behavior tuning | P1 | NPCs feel smart, not cheap |
| Combat animations (final) | P1 | Replace placeholders with real sprites |
| Screen shake, hit flash, particles | P2 | Juice and feel |
| Combat sound effects | P2 | Hit sounds, block sounds, combat music |
| Dodge i-frame tuning | P1 | Feels fair and responsive |

### Total Estimated Timeline: 10-14 weeks

**Dependencies on other systems:**
- Phase 7A-7C can start immediately (only requires existing player/NPC/WorldState)
- Phase 7D requires ally NPCs with Trust tracking (already exists)
- Phase 7E requires inventory system (Phase 8) for full implementation, but weapon/armor resources can be created independently
- Phase 7F requires the Autonomous NPC Agent system (Phase from AUTONOMOUS_NPC_AGENTS.md) for full gossip propagation, but witness system can work with direct relationship updates initially

---

## Appendix A: Combat Balance Reference

### Time-to-Kill Targets

| Matchup | Target TTK | Notes |
|---------|-----------|-------|
| Player vs. bandit grunt (1v1) | 8-15 seconds | Should feel achievable but not trivial |
| Player vs. Varn (1v1) | 20-40 seconds | A real challenge, multiple exchanges |
| Player + allies vs. bandit group (4v4) | 30-60 seconds | Chaotic, dynamic, tactical |
| Bandit ambush (1v3) | Player should flee or use terrain | Overwhelming odds = not a fair fight |
| Aldric's assault (with player, 8v15) | 3-5 minutes | The climactic battle, should feel epic |

### Difficulty Through Narrative, Not Numbers

Combat difficulty in Land comes from **context**, not from inflated HP:
- Fighting Varn alone is hard because he is skilled and aggressive
- Fighting Varn when you have Aldric, Bjorn, and three peacekeepers is manageable
- Fighting Varn after he has taken a hostage is hard in a different way -- you cannot just swing freely
- The hardest "combat" in the game might be the one you choose NOT to fight

---

## Appendix B: Open Questions

1. **Dodge roll or dodge step?** Roll is more dramatic but may look odd in top-down 2D. A quick sidestep with i-frames may feel more appropriate.

2. **Combat camera.** Should the camera zoom in during combat? Pull out to show more of the battlefield? Current player camera is static -- may need a combat-aware camera system.

3. **Lock-on targeting.** Should the player lock onto a specific enemy (Zelda-style Z-targeting)? Or free aim in the cardinal direction? Lock-on is more accessible; free aim is more action-oriented.

4. **Friendly fire.** Can the player accidentally hit allies? This would add tactical depth but frustration. Recommend: friendly fire is OFF for player attacks, ON for NPC-vs-NPC (NPCs can hurt each other in a melee).

5. **Healing during combat.** Consumable healing items? Slow natural regeneration? The game does not have a potion system yet (Phase 8: Inventory). For now, assume no mid-combat healing. Post-combat recovery at the tavern or herbalist.

6. **Combat music.** Transition from exploration music to combat music? Context-dependent combat themes? (Bandit raid: aggressive. Duel with Varn: tense. Defending Elena: desperate.)

---

*This document should be updated as implementation progresses and design decisions are tested in-game.*
