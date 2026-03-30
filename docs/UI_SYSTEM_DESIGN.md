# UI System Design Document

> **Date:** 2026-03-28
> **Status:** Design Document
> **Depends on:** All existing backend systems (5D Relationships, Autonomous NPC Agents, Emergent Narrative, Combat, Crafting/Inventory/Economics, Skills/Progression, World State, Quest System, Voice Synthesis)

---

## 1. Existing UI Audit

### 1.1 What Exists Today

The project has five UI scripts and four UI scene files. All UI is instantiated inside `game_world.tscn`.

| File | Type | Layer | Purpose | Quality |
|------|------|-------|---------|---------|
| `dialogue_ui.gd` | CanvasLayer | Default | NPC conversation with free-text input | Functional but minimal |
| `quest_journal.gd` | CanvasLayer | 10 | Tab-based quest viewer (Active/Completed/Discovered) | Well-built, solid foundation |
| `quest_notifications.gd` | CanvasLayer | 15 | Toast popups for quest events | Clean, production-ready pattern |
| `debug_console.gd` | Control | N/A | Dev console with command input, NPC tracking, memory inspection | Feature-rich dev tool (~1200+ lines) |
| `debug_interaction_panel.gd` | Control | N/A | 5D relationship testing buttons | Dev tool only |

**UI Scenes** (`scenes/ui/`):
- `debug_console.tscn` — Draggable/resizable debug panel
- `debug_interaction_panel.tscn` — Relationship test buttons
- `quest_journal.tscn` — Full quest journal layout
- `quest_notifications.tscn` — Notification container

### 1.2 What Works

1. **Quest Journal** — Well-structured with tabs, detail panels, objective hints, trust progress bars, and topic/intent/relationship completion tracking. The hint generation system (`_generate_objective_hint`) is thoughtful. This is the most polished UI component.

2. **Quest Notifications** — Clean queue-based toast system with type-colored borders, fade animations, and external API (`show_notification`). Good foundation for all notification types.

3. **Dialogue UI** — Functional core: connects to NPC signals (`dialogue_started`, `dialogue_response_ready`, `dialogue_ended`), pauses game, displays conversation in RichTextLabel with BBCode colors, integrates with VoiceManager. The signal-based architecture is correct.

4. **Debug Console** — Extensive developer tooling with live conversation tracking, memory inspection, relationship monitoring, command history. Good for development but should remain dev-only.

### 1.3 What Is Broken or Missing

**Dialogue System (Critical — the most-used UI in the game):**
- Free-text-only input. No suggested response options. No evidence presentation. No skill check indicators.
- No NPC portrait or expression display.
- No "thinking" indicator while Claude generates a response (input just goes disabled).
- No mood/emotion/relationship indicator for the NPC.
- No dialogue history beyond the current session.
- No way to present evidence items during conversation.
- The panel is a basic VBoxContainer with text field — no visual design.

**Entirely Missing UI Systems:**
- **HUD** — No health bars, stamina, resolve, currency, time-of-day, minimap, or interaction prompts. The player has zero persistent UI.
- **Inventory** — No inventory display despite the item system being fully designed (7 categories, weight-based, quality tiers, evidence items).
- **Equipment** — No equipment slots UI (main hand, off hand, head, chest, legs, feet, accessory).
- **Shop/Trade** — No trading interface despite the emergent economics design (NPC-owned inventories, relationship-based pricing, haggling).
- **Crafting** — No crafting request UI (conversation-based crafting with Bjorn, quality preview).
- **Combat HUD** — No combat overlay despite the full combat design (HP/SP/Resolve bars, tactical pause overlay, non-lethal option indicators, surrender prompts).
- **Skills/Capability Profile** — No character progression viewer despite 30 skills across 4 domains with mentorship and plateaus.
- **Relationship/Social** — No way to view NPC relationships, 5D dimensions, gossip log, or settlement reputation.
- **Map/Navigation** — No world map, local area map, or NPC location markers.
- **Pause Menu** — No save/load/settings/quit menu.
- **Interaction Prompts** — No "Press E to talk" or contextual prompts.

### 1.4 Architectural Observations

**Good patterns to preserve:**
- CanvasLayer-based UI layering (dialogue on default, journal on 10, notifications on 15)
- `process_mode = Node.PROCESS_MODE_ALWAYS` for pause-safe UI
- Signal-based connection to game systems (EventBus, QuestManager, NPC signals)
- Null-safe `has_signal()` checks before connecting

**Patterns to improve:**
- UI is built entirely in code or `.tscn` — no shared theme resource. Each component styles itself independently.
- No centralized UI manager or state machine for tracking which panels are open.
- No input action map for UI (only `open_journal` and `ui_cancel` are defined). Need actions for inventory, map, skills, pause, tactical pause, evidence present, etc.
- Dialogue UI is embedded directly in `game_world.tscn` rather than being a standalone scene. This complicates reuse and testing.

---

## 2. UI Design Principles

### 2.1 Core Philosophy

Land is a social mystery game where relationships are the primary mechanic. The UI must serve this identity.

### 2.2 Six Principles

**1. Diegetic Where Possible**
UI elements that exist in the game world are preferred over abstract menus. The quest journal is the player character's actual notebook. The capability profile is their autobiography. The investigation board is a physical board they maintain. Shop interfaces happen through conversation, not abstract grids.

**2. Minimalist HUD**
Show only what is essential during exploration: a subtle health indicator, interaction prompts, and notifications. All complexity hides behind intentional player actions. The screen should feel like a game world, not a dashboard.

**3. Emergent Information**
The UI reflects what the *player* knows, not what the *system* knows. If the player has not discovered that Gregor is suspicious, the investigation board does not hint at it. NPC relationship descriptions use qualitative language ("Gregor seems guarded around you") rather than exposing raw numbers by default.

**4. Relationship-Forward**
NPC relationships are the core of the game. They must be visible and prominent — in dialogue (subtle emotion indicators), in the social overview (who you know, how they feel), and in gameplay feedback (trust changes, gossip heard).

**5. No Numbers Without Context**
Primary displays use qualitative descriptions. "Elena trusts you deeply" rather than "Trust: 78/100". Numbers are available in detail views for players who want them, but the default experience communicates through language and visual metaphor.

**6. Responsive to the World**
UI chrome subtly reflects game state. Parchment textures darken at night. Combat HUD elements pulse with urgency. The investigation board gains pins and strings as the player discovers connections. Wear and tear on journal pages after long journeys.

### 2.3 Art Direction

**Visual Language:** Hand-drawn parchment and ink. UI panels look like pages from a journal, letters from NPCs, or wooden notice boards. Avoid clean digital interfaces.

**Color Palette:**
- Parchment base: `#F5E6C8` (warm cream)
- Ink text: `#2C1810` (dark brown-black)
- Accent gold: `#D4A843` (quest highlights, important items)
- Trust blue: `#4A7B9D` (relationship positive)
- Danger red: `#8B3A3A` (combat, warnings, low health)
- Nature green: `#4A7B4A` (healing, success, growth)
- Shadow purple: `#5A3D6A` (mystery, the unknown)

**Typography:**
- Headers: Serif/calligraphic font (medieval manuscript feel)
- Body: Clean serif for readability
- Numbers/stats: Monospace or tabular for alignment
- NPC speech: Slightly different font weight per NPC personality (bold for Aldric, italic for Mira, etc.)

**Transitions:**
- Panels slide in from edges (journal from left, inventory from right)
- Fade-in for overlays (tactical pause, map)
- Page-turn animation for journal navigation
- Ink-bleed effect for new entries appearing

---

## 3. UI Architecture Overview

### 3.1 Layer Map

| Layer | Name | Contents | Pauses Game? |
|-------|------|----------|-------------|
| 0 | World | Interaction prompts (floating above NPCs/objects) | No |
| 1 | HUD | Health, stamina, minimap, quest tracker, time, currency | No |
| 5 | Dialogue | Conversation panel, NPC portrait, response options | Yes |
| 10 | Menus | Inventory, journal, skills, map, social, shop | Yes |
| 12 | Investigation | Investigation board overlay | Yes |
| 15 | Notifications | Toast messages, feedback popups | No |
| 18 | Combat HUD | Combat-specific overlays, tactical pause | Tactical pause only |
| 20 | System | Pause menu, save/load, settings | Yes |
| 25 | Debug | Console, interaction panel (dev builds only) | No |

### 3.2 UI Manager (New — Central Controller)

A new autoload `UIManager` coordinates all UI panels, preventing conflicts (e.g., opening inventory while in dialogue) and providing a single point of control.

```
UIManager (extends Node):
  # State tracking
  active_panels: Array[StringName]    # Stack of open panels
  current_mode: UIMode                # EXPLORATION, DIALOGUE, COMBAT, MENU, TACTICAL_PAUSE

  # Panel registry
  panels: Dictionary                  # {panel_name: panel_node}

  # Signals
  signal panel_opened(panel_name: StringName)
  signal panel_closed(panel_name: StringName)
  signal mode_changed(old_mode: UIMode, new_mode: UIMode)

  # Methods
  func open_panel(name: StringName) -> bool    # Returns false if blocked
  func close_panel(name: StringName)
  func close_all_panels()
  func is_panel_open(name: StringName) -> bool
  func can_open_panel(name: StringName) -> bool  # Checks mode conflicts
```

**Mode Rules:**
- `EXPLORATION` — HUD visible, all menus accessible
- `DIALOGUE` — HUD visible, menus blocked, dialogue panel active
- `COMBAT` — Combat HUD active, some menus blocked, tactical pause available
- `MENU` — Game paused, one menu panel active at a time
- `TACTICAL_PAUSE` — Combat paused, tactical overlay active

### 3.3 Input Action Map

New input actions needed (in addition to existing `open_journal`, `ui_cancel`):

| Action | Default Key | Context |
|--------|-------------|---------|
| `open_inventory` | I | Exploration |
| `open_journal` | J | Exploration (exists) |
| `open_investigation` | N | Exploration |
| `open_skills` | K | Exploration |
| `open_map` | M | Exploration |
| `open_social` | R | Exploration |
| `pause_menu` | Escape | Always |
| `interact` | E | Near interactable |
| `tactical_pause` | Space | Combat |
| `present_evidence` | P | Dialogue |
| `quick_slot_1-4` | 1-4 | Combat/Exploration |
| `toggle_minimap` | Tab | Exploration |

---

## 4. Dialogue System Redesign

The dialogue UI is the most important interface in Land. Every major game system surfaces through conversation: quests, crafting requests, evidence presentation, shopping, relationship building, skill mentorship, and narrative discovery.

### 4.1 Layout

```
┌─────────────────────────────────────────────────────────┐
│ [NPC Portrait]  NPC Name            [Mood Indicator]    │
│ [Expression]    Role/Title          [Relationship Bar]  │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Dialogue History (scrollable RichTextLabel)            │
│                                                         │
│  NPC: "I've been worried about the shipments lately.    │
│  Gregor says everything is fine, but..."                │
│                                                         │
│  You: "What do you mean? What's wrong with the          │
│  shipments?"                                            │
│                                                         │
│  NPC: "Never mind. I shouldn't have said anything."     │
│  [Thinking...] ← Claude generation indicator            │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ Suggested Responses:                                    │
│  [1] "Elena, you can trust me. What have you seen?"     │
│      [Persuasion — Moderate] [Trust: Sufficient]        │
│  [2] "If something's wrong, people could get hurt."     │
│      [Appeal to conscience]                             │
│  [3] "I already know about Gregor. You don't have       │
│       to protect him."  [Requires: ledger_found]        │
│  [4] [Present Evidence: Gregor's Ledger]                │
│  [5] [Type your own response...]                        │
├─────────────────────────────────────────────────────────┤
│ [Voice: Playing ▶]  [End Conversation]                  │
└─────────────────────────────────────────────────────────┘
```

### 4.2 Component Breakdown

**NPC Portrait Area (Top Left)**
- 128x128 portrait showing NPC face/bust
- Expression changes based on emotional state (happy, worried, angry, afraid, neutral, suspicious)
- Portraits can be generated via the asset pipeline or hand-drawn
- Subtle animation: breathing idle, expression transitions

**NPC Info (Top Right of Portrait)**
- Name and role/title ("Elena — Merchant's Daughter")
- Mood indicator: small icon or colored dot showing current emotional state
- Relationship bar: thin horizontal bar showing general disposition (cold/warm/close), NOT exact numbers
- Skill check indicator: appears when persuasion/deception/intimidation are relevant (lock icon for gated options)

**Dialogue History (Center)**
- Scrollable `RichTextLabel` with BBCode formatting (preserving existing pattern)
- NPC text in warm color, player text in cool color
- System notes in muted gray italic ("Elena seems troubled by your question")
- Emotional annotations inline: text color/style shifts when NPC emotional state changes
- "Thinking..." animated indicator with dots while Claude generates response
- Voice playback indicator (waveform or speaker icon) when TTS is active

**Response Options Panel (Bottom)**
- Claude generates 3-4 contextual response suggestions based on:
  - Current conversation context
  - Player's known information (story flags)
  - Available skills (persuasion, deception, intimidation, insight)
  - Evidence in player's inventory
  - Relationship state
- Each option shows:
  - The response text (truncated with full text on hover)
  - Skill tag if relevant: `[Persuasion — Moderate]`, `[Deception — Difficult]`
  - Requirement tag if gated: `[Requires: ledger_found]`, `[Trust: Insufficient]`
- Evidence presentation option appears when player has relevant evidence items
- "Type your own response" option always available (preserves current free-text system)
- Keyboard shortcuts: 1-5 to select options

**Voice and Controls (Bottom Bar)**
- Voice playback status and controls (play/stop, from existing VoiceManager integration)
- "End Conversation" button (preserving existing functionality)

### 4.3 Response Generation Architecture

The suggested responses are generated by a secondary Claude call that runs in parallel with (or slightly after) the NPC's response. This call receives:

```
Context for response generation:
  - Last 3-5 dialogue exchanges
  - Player's known story flags
  - Player's relationship state with this NPC
  - Player's social skills (persuasion, deception, insight levels)
  - Evidence items in player inventory that are relevant (matching evidence_tags)
  - Current quest objectives involving this NPC
  - NPC's current emotional state

Output format:
  - 3-4 response options, each with:
    - response_text: String
    - tone: String (friendly/confrontational/diplomatic/deceptive/etc.)
    - skill_check: Optional {skill: String, difficulty: String}
    - requires_flag: Optional String
    - requires_evidence: Optional String (item_id)
```

The player can always bypass suggestions and type freely. Free-text input is never removed — it is the soul of the AI-driven dialogue system. Suggestions are a convenience and a discovery mechanism, showing players what is possible.

### 4.4 Evidence Presentation Flow

When the player presses the evidence presentation key (P) during dialogue:

1. A slide-out panel appears showing evidence items in inventory
2. Items are filtered to those with `presentable_to` including the current NPC
3. Each item shows its name, brief description, and relevance hint
4. Selecting an item injects the evidence context into the NPC's Claude prompt (as designed in CRAFTING_INVENTORY_AND_EMERGENT_ECONOMICS.md Section 1.4)
5. The NPC responds authentically based on personality, secrets, and relationship
6. The panel closes and the response appears in dialogue history

### 4.5 Thinking/Loading States

While Claude generates the NPC response:
- Player input is disabled (preserving current behavior)
- An animated "thinking" indicator appears: three dots pulsing, or a quill-writing animation
- The NPC portrait shows a "contemplative" expression
- After 3 seconds without response, show "Still thinking..." with a subtle parchment-aging animation
- After 8 seconds, show a "Taking a moment to consider..." message (prevents player thinking the UI is frozen)
- If the request fails, show an in-character fallback: "NPC seems distracted" and re-enable input

---

## 5. Investigation Board (Replacing Traditional Quest Log)

### 5.1 Concept

The quest journal is replaced by an **Investigation Board** — a visual pinboard metaphor where the player tracks their understanding of the world. This is not a checklist of objectives. It is a living document of what the player knows, suspects, and has connected.

The existing `quest_journal.gd` is preserved as the underlying data source but the presentation layer is completely redesigned.

### 5.2 Layout

```
┌──────────────────────────────────────────────────────────────┐
│  MY INVESTIGATION                               [Close: Esc] │
├──────────┬───────────────────────────────────────────────────┤
│          │                                                   │
│ THREADS  │            BOARD (2D pannable canvas)             │
│          │                                                   │
│ ● The    │    ┌─────────┐         ┌─────────┐               │
│   Merchant│    │ Gregor  │─ ─ ─ ─ │ Ledger  │               │
│   's Deal │    │ [photo] │  "sells │ [item]  │               │
│          │    │ Nervous  │  weapons│ Found in│               │
│ ● The    │    │ lately   │  to..." │ his shop│               │
│   Failing │    └────┬────┘         └─────────┘               │
│   Watch  │         │                                         │
│          │    ┌────┴────┐                                    │
│ ○ Rumors │    │ Elena   │                                    │
│   Heard  │    │ [photo] │                                    │
│          │    │ Suspects │                                    │
│ EVIDENCE │    │ father  │                                    │
│          │    └─────────┘                                    │
│ ◆ Ledger │                                                   │
│ ◆ Marked │                                                   │
│   Weapon │                                                   │
│          │                                                   │
├──────────┼───────────────────────────────────────────────────┤
│          │ SELECTED: Gregor — General Merchant               │
│ GOALS    │ "Sells weapons and goods. Seems prosperous while  │
│          │  the village suffers. Found a suspicious ledger    │
│ ▸ Learn  │  in his shop with entries that don't add up."     │
│   about  │                                                   │
│   Gregor │ Known connections: Elena (daughter), Bjorn         │
│ ▸ Find   │   (supplier), Varn (???)                          │
│   proof  │ Evidence: Gregor's Ledger, Bjorn's Marked Weapon  │
│   for    │                                                   │
│   Aldric │ Related goals: Learn about Gregor's nighttime     │
│          │   activities, Find proof for Aldric                │
└──────────┴───────────────────────────────────────────────────┘
```

### 5.3 Board Elements

**NPC Cards**
- Small cards pinned to the board for NPCs the player has met
- Show portrait thumbnail, name, and a one-line player-authored note (or auto-generated from interactions)
- Cards can be dragged and repositioned by the player
- Color-coded border: blue (ally), gray (neutral), red (hostile/suspicious), gold (quest-relevant)

**Evidence Pins**
- Evidence items appear as pinned documents/objects on the board
- Show item icon, name, brief description
- Highlighted with gold border if recently discovered

**Connection Strings**
- Lines drawn between cards/pins that the player has connected
- Connections form automatically when the player discovers relationships (e.g., finding the ledger connects Gregor to "bandit deal")
- Player can also manually draw connections (right-click drag between two elements)
- Dotted lines for suspected connections, solid for confirmed
- Labels on connections summarize the relationship ("sells weapons to", "daughter of", "witnessed by")

**Thread Markers**
- Active story threads appear as colored thread labels on the left sidebar
- Clicking a thread highlights all related cards, evidence, and connections on the board
- Thread state uses qualitative language: "Simmering", "Something's building", "Crisis imminent"
- The player does NOT see thread tension numbers — they see narrative descriptions

**Goals (Replacing Quest Objectives)**
- Natural language goals, not checklist items:
  - "Learn more about Gregor's nighttime activities" (not "Talk to Gregor (0/1)")
  - "Find proof that Aldric can take to the council" (not "Collect 3 evidence items")
  - "Earn Elena's trust" (not "Reach Trust 55 with Elena")
- Goals emerge from quest data but are rephrased through the narrative lens
- Completed goals fade to a muted color but remain visible as a record

### 5.4 Rumor Log

A sub-panel of the investigation board tracking rumors heard through NPC gossip:

- Each rumor shows: what was said, who said it, when, and confidence level
- Confidence levels: "Gossip" (unverified), "Consistent" (heard from multiple sources), "Confirmed" (player-verified)
- Rumors can be promoted to board connections when confirmed
- Example: "Heard from Mira: 'Gregor's been meeting someone outside the village at night.' (Gossip — 2 days ago)"

### 5.5 Migration from Current Quest Journal

The existing `quest_journal.gd` data structures (quest tabs, objectives, completion tracking) become the data backend. The investigation board is a new presentation layer that reads from `QuestManager` but displays information through the board metaphor. The current journal can remain accessible as a "simple view" toggle for players who prefer a traditional list.

---

## 6. Capability Profile (Replacing Traditional Character Sheet)

### 6.1 Concept

There is no character sheet with stats. The player views their **Capability Profile** — a biography-style journal page that reads like a story of who they have become.

### 6.2 Layout

```
┌──────────────────────────────────────────────────────────────┐
│  MY JOURNAL — CAPABILITIES                      [Close: Esc] │
├──────────┬───────────────────────────────────────────────────┤
│          │                                                   │
│ DOMAINS  │  COMBAT                                           │
│          │                                                   │
│ ⚔ Combat │  Swordsmanship ████████░░ "Competent"             │
│ 🗣 Social│    Learned from: Elena (basic forms)              │
│ 🔨 Craft │    Techniques: Riposte, Feint                     │
│ 🌿 Surv. │    Next: "Earn Aldric's respect to learn          │
│          │           advanced counter-strike"                 │
│ RENOWN   │    ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄                        │
│          │  Blocking ██████░░░░ "Practiced"                   │
│ VITALS   │    Self-taught through combat                     │
│          │    Techniques: Shield Bash                        │
│ MENTORS  │    Plateau: "Need a teacher to improve further"   │
│          │    ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄                        │
│          │  Tactics ███░░░░░░░ "Novice"                      │
│          │    No formal training                             │
│          │    "Aldric could teach you military tactics        │
│          │     if you earn his trust"                         │
│          │                                                   │
│          │  ─── RECENT GROWTH ───                            │
│          │  ▲ Swordsmanship +3 (sparring with Elena)         │
│          │  ▲ Blocking +1 (bandit encounter at the mill)     │
│          │                                                   │
├──────────┼───────────────────────────────────────────────────┤
│          │  SYNERGIES                                        │
│          │  Swordsmanship + Parrying → "Riposte Mastery"     │
│          │    (Both above 40: +15% counter-attack damage)    │
└──────────┴───────────────────────────────────────────────────┘
```

### 6.3 Sections

**Domain Tabs (Left Sidebar)**
- Combat, Social, Craft, Survival — the four skill domains from the design doc
- Each domain shows skills with qualitative progress bars
- Proficiency labels replace numbers: Untrained (0-10), Novice (11-25), Practiced (26-40), Competent (41-55), Skilled (56-70), Expert (71-85), Master (86-100)

**Skill Detail (Main Panel)**
- For each skill:
  - Progress bar with qualitative label (numbers shown in small text on hover/toggle)
  - Mentor attribution: "Learned from Elena", "Self-taught", "Read in ancient text"
  - Known techniques listed with brief descriptions
  - Plateau indicator: if the player has hit a plateau, show what is needed to break through
  - Next milestone: what the player could learn next and from whom (only if discovered)

**Renown Section**
- Shows how the world perceives the player
- Breakdown by category: Combat, Investigation, Crafting, Social, Infamy
- Per-settlement reputation: "Well-regarded in Thornhaven", "Unknown in Millhaven"
- Uses qualitative descriptions, not numbers

**Vitals Section**
- Health, Stamina, Resolve shown as bars with qualitative descriptions
- "Hearty" (high HP), "Tireless" (high Stamina), "Unshakeable" (high Resolve)
- Growth tracking: "Your resolve has grown since standing up to Varn"

**Mentor Relationships**
- List of NPCs who have taught the player
- What each mentor can still teach (if anything)
- Trust requirement for next teaching: "Bjorn could teach advanced smithing if you earn his deep trust"

**Recent Growth Log**
- Last 10-15 skill gains with context
- "Swordsmanship +3 (sparring with Elena at dawn)"
- "Persuasion +5 (convinced Mathias to hear your evidence)"
- This is the player's growth story told through gameplay events

**Synergies**
- Active skill synergies displayed with their effects
- Potential synergies hinted at: "Your swordsmanship and dodging are both improving. Keep developing both for a bonus."

---

## 7. Always-Visible HUD

### 7.1 Design: Minimal and Contextual

The HUD shows very little by default. Elements appear and fade based on relevance.

### 7.2 Layout

```
┌──────────────────────────────────────────────────────────────┐
│ [❤ ████░░]  [⚡ ██████]  [◆ ████░░]          [☀ Noon]  [🗺] │
│  Health      Stamina      Resolve           Time    Minimap │
│                                                              │
│                                                              │
│                                                       ┌────┐ │
│                                                       │    │ │
│                                                       │mini│ │
│                                                       │map │ │
│                                                       │    │ │
│                                                       └────┘ │
│                                                              │
│                           [!] Toast notifications (top-right)│
│                                                              │
│                                                              │
│                                                              │
│                        [E] Talk to Elena                     │
│                                                              │
│ [▸ Find proof for Aldric]           [💰 47 silver]          │
│  Active quest tracker                Currency                │
└──────────────────────────────────────────────────────────────┘
```

### 7.3 Components

**Health/Stamina/Resolve Bars (Top Left)**
- Thin horizontal bars, minimally styled
- Health fades in/out based on context: always visible in combat, fades during safe exploration
- Stamina visible during combat and exertion, hidden when full and idle
- Resolve visible during social confrontations and combat, hidden otherwise
- Color shifts: health bar yellows at 50%, reds at 25%. Stamina pulses when depleted.
- No numbers on HUD — numbers only in the capability profile

**Time of Day (Top Right)**
- Small icon + text: sun/moon icon with label (Dawn, Morning, Noon, Afternoon, Evening, Night)
- Subtly affects HUD chrome color temperature (warmer at dusk, cooler at night)

**Minimap (Top Right Corner)**
- Small circular or square minimap showing immediate area
- Dots for: NPCs (color-coded by disposition), buildings, quest-relevant locations
- Toggle on/off with Tab
- Respects fog of war — only shows explored areas
- Optional compass rose for orientation

**Toast Notification Area (Upper Right)**
- Preserves existing `quest_notifications.gd` system
- Extended to handle all notification types (see Section 12)
- Stacks up to 3 notifications, queues the rest

**Interaction Prompt (Center Bottom)**
- Appears when player is near an interactable object or NPC
- Shows contextual prompt: "Press E to talk to Elena", "Press E to open chest", "Press E to examine"
- Includes NPC name and a one-word mood hint: "Elena (worried)", "Bjorn (busy)"

**Active Quest Tracker (Bottom Left)**
- Shows 1-2 lines of the current active goal
- Natural language: "Find proof for Aldric" not "Objective: Collect evidence (1/3)"
- Subtle — does not distract from the game world
- Click to open full investigation board

**Currency Display (Bottom Right)**
- Simple coin icon + amount
- Only visible when relevant (near shops, after transactions)
- Fades after 5 seconds of no economic activity

### 7.4 Contextual Visibility Rules

| Element | Visible When | Fades When |
|---------|-------------|------------|
| Health bar | In combat, after taking damage, HP < 80% | Full HP + safe area for 5 seconds |
| Stamina bar | In combat, during exertion, SP < 90% | Full SP + idle for 3 seconds |
| Resolve bar | In social confrontation, combat, Resolve changed | Not in confrontation for 5 seconds |
| Minimap | Always (toggleable) | Player toggles off |
| Time | Always | Never (but minimal footprint) |
| Quest tracker | Always | Never (but single line) |
| Currency | Near shop, after transaction | 5 seconds after last economic event |
| Interaction prompt | Near interactable | Move away from interactable |

---

## 8. Combat HUD

### 8.1 Active Combat Overlay

During combat, the HUD transforms to show combat-relevant information without obscuring the battlefield.

```
┌──────────────────────────────────────────────────────────────┐
│ PLAYER               ALLIES                    TARGET        │
│ ❤ ████████░░         Aldric ❤████░             Bandit Scout  │
│ ⚡ ██████░░░░         Elena  ❤██████            ❤ ██████░░░  │
│ ◆ ████████░░                                   [Hostile]     │
│                                                 Surrender: 30%│
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                    ← Game World →                            │
│                                                              │
│                    [-12 HP]  ← Floating damage               │
│                                                              │
│                                                              │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│ [1] Health Potion x3  [2] Throwing Knife x5                 │
│                                        [SPACE] Tactical Pause │
│ Combo: ██░░ (2/4)          [E] "Surrender!" (Intimidation)  │
└──────────────────────────────────────────────────────────────┘
```

### 8.2 Components

**Player Stats (Top Left)**
- Health, Stamina, Resolve bars — always visible during combat
- Larger and more prominent than exploration HUD

**Ally Status (Top Center)**
- Compact health bars for allied NPCs in combat
- Shows name and health only — minimal footprint
- Flashes when an ally is in danger

**Target Info (Top Right)**
- Current target's name, health bar, and stance
- Behavioral state: `[Hostile]`, `[Defensive]`, `[Fleeing]`, `[Surrendered]`
- Surrender probability estimate (based on player's Insight skill + NPC's Resolve)
- Only visible when player has a locked target

**Floating Combat Text**
- Damage numbers float up from targets: `-12`, `BLOCKED`, `PARRIED`, `DODGED`
- Status effects: `STAGGERED`, `INTIMIDATED`, `DISARMED`
- Non-lethal indicators: `KNOCKED OUT`, `SURRENDERED`
- Color-coded: red for damage dealt, white for damage taken, green for healing, gold for critical

**Quick Slots (Bottom Left)**
- 4 consumable quick-use slots (health potions, throwing weapons, etc.)
- Keyboard shortcuts 1-4
- Shows item icon and remaining count

**Combo Indicator (Bottom Center)**
- Shows current combo chain progress (e.g., 2/4 hits in a light attack chain)
- Technique readiness indicators for unlocked combat techniques

**Non-Lethal Options (Bottom Right)**
- Context-sensitive prompts for non-lethal actions:
  - "Press E: Demand Surrender" (when target's Resolve is low enough)
  - "Press E: Spare" (when target has surrendered)
  - "Press Q: Disarm" (when technique is known)
- These prompts are prominent — the game wants players to notice them

### 8.3 Tactical Pause Overlay

When the player presses Space during combat:

```
┌──────────────────────────────────────────────────────────────┐
│                    ═══ TIME FROZEN ═══                        │
│                                                              │
│  PLAYER: HP 78/100  SP 45/100  Resolve 60/100               │
│                                                              │
│  COMBATANTS:                                                 │
│  ● Bandit Scout — HP 34/80 [Hostile, Wavering]               │
│    → Surrender chance: 30% (+20% if intimidated)             │
│  ● Bandit Grunt — HP 60/60 [Hostile, Aggressive]             │
│    → Surrender chance: 5%                                    │
│  ○ Aldric — HP 55/120 [Allied, Holding position]             │
│                                                              │
│  ACTIONS:                                                    │
│  [1] Switch Target    [3] Use Item                           │
│  [2] Command Ally     [4] Demand Surrender                   │
│                       [5] Attempt to Disengage               │
│                                                              │
│  [SPACE] Resume Combat                                       │
└──────────────────────────────────────────────────────────────┘
```

The tactical pause shows full information: exact HP numbers, surrender probabilities, ally commands. This is the "detail view" — the HUD during real-time combat stays minimal. The tactical pause is where the player makes considered decisions.

**Ally Commands:**
- "Focus [target]" — ally prioritizes a specific enemy
- "Fall back" — ally retreats to safe distance
- "Protect me" — ally stays close and intercepts attacks
- "Use ability" — ally uses their best available technique

---

## 9. Inventory and Equipment UI

### 9.1 Layout

```
┌──────────────────────────────────────────────────────────────┐
│  INVENTORY                                      [Close: Esc] │
├──────────┬──────────────────────┬────────────────────────────┤
│          │                      │                            │
│ CATEGORY │  ITEM LIST           │  ITEM DETAIL               │
│          │                      │                            │
│ All      │  ▸ Iron Sword ⚔     │  ┌──────────┐             │
│ Weapons  │    Fine quality      │  │  [Icon]  │  Iron Sword │
│ Armor    │    Equipped (Main)   │  │          │  Fine Quality│
│ Consum.  │                      │  └──────────┘             │
│ Materials│  ▸ Leather Vest 🛡   │                            │
│ Tools    │    Common quality    │  Damage: 15-22             │
│ Evidence │    Equipped (Chest)  │  Durability: 45/60         │
│ Quest    │                      │  Weight: 3.5 stones        │
│          │  ▸ Health Potion x5  │  Value: ~120 silver        │
│          │    Good potency      │                            │
│          │                      │  Crafted by Bjorn          │
│          │  ▸ Gregor's Ledger ◆ │  Maker's mark: "B"        │
│          │    Evidence item     │                            │
│          │                      │  [Equip] [Drop] [Examine] │
│          │                      │                            │
├──────────┴──────────────────────┼────────────────────────────┤
│  Weight: 28.5 / 50.0 stones  ██████████████░░░░░░░  57%     │
│  Gold: 47 silver                                             │
└─────────────────────────────────┴────────────────────────────┘
```

### 9.2 Features

**Category Filters (Left)**
- Filter by item category (matching the 7 categories from the design doc)
- "All" shows everything
- Each category shows item count
- Evidence items have a special diamond marker

**Item List (Center)**
- Sorted by category, then by name
- Shows item name, quality indicator, equipped status
- Stack counts for stackable items
- Evidence items visually distinct (gold border or diamond icon)
- Equipped items marked with slot name

**Item Detail (Right)**
- Full item information matching `ItemData` resource:
  - Icon, name, quality tier
  - Relevant stats (damage for weapons, defense for armor, effect for consumables)
  - Durability bar if applicable
  - Weight and approximate value
  - Crafting origin (who made it, maker's mark)
  - Evidence tags for evidence items
  - Description text
- Action buttons: Equip, Use, Drop, Examine
- For equipment: comparison tooltip showing current equipped vs. inspected item
  - Green/red arrows for stat differences

**Weight/Capacity Bar (Bottom)**
- Visual bar showing current weight vs. max capacity
- Color changes at thresholds: green (normal), yellow (75% — encumbered), red (100% — overburdened)
- Exact numbers displayed

**Equipment View Toggle**
- Button to switch to equipment view showing all 7 slots:
  - Main Hand, Off Hand, Head, Chest, Legs, Feet, Accessory
- Each slot shows equipped item or empty state
- Click a slot to filter inventory list to compatible items

---

## 10. Shop and Trade Interface

### 10.1 Concept: Conversational Commerce

Shopping in Land happens through conversation. The player talks to a merchant NPC, and the shop interface appears as an extension of the dialogue panel — not as a separate screen. This reinforces the principle that NPCs own the economy and prices are opinions.

### 10.2 Layout

```
┌──────────────────────────────────────────────────────────────┐
│ [Gregor Portrait]  Gregor's Shop         [Relationship: Wary]│
├──────────────────────────┬───────────────────────────────────┤
│  GREGOR'S WARES          │  YOUR INVENTORY                   │
│                          │                                   │
│  Rope (Common)      8s   │  Iron Ore x5 (Good)    → 3s each │
│  Lantern (Common)  15s   │  Health Potion x3      → 5s each │
│  Rations x10 (Dry)  2s   │  Leather (Fine)        → 12s     │
│  Travel Pack       25s   │  Bandit's Dagger       → 8s      │
│  ──────────────────────  │                                   │
│  🔒 Iron Dagger    30s   │                                   │
│     "I don't sell         │                                   │
│      weapons to           │                                   │
│      strangers."          │                                   │
│                          │                                   │
├──────────────────────────┴───────────────────────────────────┤
│  SELECTED: Rope (Common)                                     │
│  Gregor's price: 8 silver (fair — standard rate)             │
│  [Haggle: "Could you do 6?"]  [Buy]  [Barter: offer items]  │
├──────────────────────────────────────────────────────────────┤
│  Your gold: 47 silver                Gregor's gold: ~500     │
│  "Gregor seems to charge fair prices. His stock looks normal │
│   but he had more weapons last week."                        │
└──────────────────────────────────────────────────────────────┘
```

### 10.3 Features

**NPC Wares (Left)**
- Shows the NPC's actual inventory (not a generic shop list)
- Prices are the NPC's asking price, modified by relationship, supply/demand, and NPC goals
- Trust-gated items shown with lock icon and NPC's in-character refusal
- Items the NPC is reluctant to sell show a higher price or a note

**Player Inventory (Right)**
- Shows items the player could sell
- Displays the NPC's buy price (what they would pay)
- Buy prices also modified by relationship and NPC needs

**Price Context (Bottom)**
- When an item is selected, shows the NPC's price with a fairness assessment
- Fairness based on player's Appraisal skill: "Fair price", "Overpriced", "Good deal"
- Only visible if Appraisal skill is high enough — low-skill players see just the number

**Haggling**
- "Haggle" button opens a mini-dialogue where the player can propose a price
- Success based on Negotiation skill, relationship, and how far off the request is
- NPC responds in character: "I can do 7, but no lower" or "Don't insult me."
- Failed haggle may raise the price or offend the NPC

**Barter Mode**
- Player can offer items instead of gold
- NPC evaluates the offer based on their needs and the items' value
- "Gregor is interested in your leather — he needs it for travel packs"

**Supply Hints**
- Observational notes about the NPC's stock (if player's Insight is high enough):
  - "Gregor had more weapons last week."
  - "This price seems desperate — Gregor may need gold quickly."
  - "Bjorn doesn't have much iron. The trade route may be disrupted."

---

## 11. Crafting Interface

### 11.1 Concept: Conversation-Based Crafting

The player does not open a crafting menu. They talk to a crafter NPC (primarily Bjorn) and request items through dialogue. The crafting interface is an extension of the dialogue UI.

### 11.2 Flow

1. Player initiates conversation with a crafter NPC
2. Player asks (via dialogue or suggested response): "Can you make me a sword?"
3. NPC evaluates: Do they have materials? Do they trust the player? What quality can they achieve?
4. If possible, a **Crafting Preview Panel** slides out from the dialogue:

```
┌──────────────────────────────────────────────────────────────┐
│  BJORN'S FORGE — Crafting Request                            │
├──────────────────────────────────────────────────────────────┤
│  Requesting: Iron Sword                                      │
│                                                              │
│  Materials Needed:          Available:                        │
│  ● Iron Ingot x2           ✓ Bjorn has 3                    │
│  ● Leather Strip x1        ✓ From your inventory            │
│  ● Coal x1                 ✓ Bjorn has plenty               │
│                                                              │
│  Expected Quality: Fine                                      │
│  (Bjorn's skill: Skilled + Good materials + Basic tools)     │
│  "If you brought me better steel, I could do even better."   │
│                                                              │
│  Cost: 25 silver (materials) + 15 silver (labor)             │
│  Time: Ready by tomorrow morning                             │
│                                                              │
│  [Request Craft]  [Offer Your Materials]  [Never mind]       │
└──────────────────────────────────────────────────────────────┘
```

### 11.3 Features

**Material Selection**
- Shows required materials and sources (NPC's stock, player's inventory, or missing)
- Player can offer their own materials to potentially improve quality
- "Offer Your Materials" opens a filtered inventory view showing compatible materials

**Quality Preview**
- Estimated quality based on the formula from CRAFTING_INVENTORY_AND_EMERGENT_ECONOMICS.md:
  - Crafter skill + material grade + tool quality + relationship trust
- The NPC comments on how to improve quality: "Better steel would make a difference" or "I'll put extra care into this for you"

**Trust-Gated Techniques**
- High-trust crafters use their best techniques, producing higher quality
- If trust is insufficient: "I'll make you a solid sword, but my best work... that I save for friends I trust."
- This is communicated through dialogue, not abstract UI elements

**Crafting Time**
- Crafting is not instant — complex items take in-game hours or days
- The NPC tells the player when to come back
- A notification fires when the item is ready: "Bjorn has finished your sword"

**Recipe Discovery**
- Asking an NPC "What can you make?" reveals their known recipes
- Recipes are filtered by available materials and trust level
- Unknown recipes hinted at: "I know techniques I haven't shown you yet..."

---

## 12. Notification and Feedback Systems

### 12.1 Notification Types

Extending the existing `quest_notifications.gd` system to handle all game feedback:

| Type | Color | Duration | Example |
|------|-------|----------|---------|
| Quest Discovery | Gold | 3s | "New thread: The Merchant's Bargain" |
| Objective Complete | Green | 3s | "Learned about Gregor's shipments" |
| Quest Complete | Bright Green | 4s | "Thread resolved: The Failing Watch" |
| Quest Failed | Red | 4s | "Aldric launched a premature assault" |
| Skill Growth | Teal | 2.5s | "Swordsmanship improved (Practiced)" |
| Relationship Change | Blue/Red | 2.5s | "Elena trusts you more" / "Gregor is suspicious of you" |
| Reputation Change | Purple | 2.5s | "Your renown grows in Thornhaven" |
| Item Acquired | White | 2s | "Obtained: Gregor's Ledger" |
| Evidence Found | Gold | 3s | "Evidence discovered: marked weapon" |
| Crafting Complete | Orange | 3s | "Bjorn has finished your Iron Sword" |
| World Event | Gray | 3s | "The trade route to Millhaven has been raided" |
| Combat Event | Red | 2s | "Bandit fled the battle" / "Enemy surrendered" |
| Discovery | Yellow | 3s | "New area discovered: Iron Hollow" |
| Technique Learned | Teal | 3s | "Learned: Riposte (from Elena)" |
| Gossip Heard | Light Purple | 2.5s | "Overheard a rumor about Gregor" |

### 12.2 Notification Priority

When multiple notifications trigger simultaneously:
1. Quest/thread events (highest)
2. Combat events
3. Relationship changes
4. Skill growth
5. World events
6. Item acquisition (lowest)

Lower-priority notifications queue behind higher-priority ones. Maximum 3 visible at once.

### 12.3 Ambient Feedback (Non-Toast)

Some feedback is communicated without toast notifications:

- **Relationship shifts during dialogue:** NPC portrait expression changes, subtle color shift in the relationship bar
- **Skill practice during combat:** brief flash on the relevant stat in the combat HUD
- **NPC mood in exploration:** interaction prompt includes mood hint ("Elena (worried)")
- **Economic changes:** shop prices shift next time the player visits — no explicit notification
- **Time passing:** sky gradient changes, lighting shifts, NPC schedules change
- **Weather/environment:** visual effects communicate world state directly

### 12.4 Feedback Narrative Style

All notifications use natural language rather than mechanical descriptions:

- "Elena trusts you more" (not "Trust +5 with Elena")
- "Your skill with a blade has grown" (not "Swordsmanship: 34 → 37")
- "Gregor seems warier around you" (not "Gregor suspicion +10")
- "Thornhaven remembers your bravery" (not "Renown (combat) +3 in Thornhaven")

Detail-oriented players can toggle "detailed mode" in settings to see numbers alongside narrative text.

---

## 13. Relationship and Social UI

### 13.1 Layout

```
┌──────────────────────────────────────────────────────────────┐
│  PEOPLE I KNOW                                  [Close: Esc] │
├──────────┬───────────────────────────────────────────────────┤
│          │                                                   │
│ THORNHVN │  [Elena Portrait]  Elena — Merchant's Daughter    │
│          │                                                   │
│ ● Elena  │  Disposition: "Trusts you. Confides her fears."   │
│ ● Gregor │                                                   │
│ ● Bjorn  │  ┌─────────────────────────────────┐             │
│ ● Aldric │  │     Trust: ████████░░ Deep       │             │
│ ● Mira   │  │   Respect: ██████░░░░ Growing    │             │
│ ● Mathias│  │ Affection: █████████░ Strong     │             │
│          │  │      Fear: ░░░░░░░░░░ None       │             │
│ MILLHVN  │  │Familiarity: ████████░░ Close     │             │
│          │  └─────────────────────────────────┘             │
│ (none    │                                                   │
│  known)  │  Shared history:                                  │
│          │  "You've trained together at dawn. She told you   │
│ ──────── │   about her suspicions of her father. You found   │
│ GOSSIP   │   evidence that confirmed her fears."             │
│          │                                                   │
│ REPUTATION│  What she knows about you:                       │
│          │  "Knows you're investigating the bandits. Trusts  │
│          │   you with her father's secret."                  │
│          │                                                   │
│          │  Can teach: Riposte (✓), Disarming Strike (Trust) │
└──────────┴───────────────────────────────────────────────────┘
```

### 13.2 Features

**NPC List (Left Sidebar)**
- Grouped by settlement
- Only shows NPCs the player has met
- Color-coded: blue (friendly), gray (neutral), red (hostile), gold (quest-relevant)
- Small icon indicating relationship tier

**NPC Detail (Main Panel)**
- Portrait and name/role
- Qualitative disposition summary (generated from 5D values)
- 5D relationship visualization:
  - Bars with qualitative labels by default
  - Exact numbers available on hover or toggle (for detail-oriented players)
  - Per the design principle: "No numbers without context"
- Shared history narrative: auto-generated summary of key interactions
- "What they know about you": what the NPC has learned/observed about the player
- Mentorship info: what skills they can teach, trust gates

**Gossip Log (Sidebar Tab)**
- Rumors heard, organized by recency
- Source attribution and confidence level
- Links to investigation board entries

**Reputation (Sidebar Tab)**
- Per-settlement reputation summary
- Renown breakdown by category
- Recent reputation-affecting events

---

## 14. Map and Navigation UI

### 14.1 Local Map

Accessible via M key. Shows the current settlement/area with:

- Building outlines with labels (Gregor's Shop, Bjorn's Forge, Tavern, etc.)
- NPC location markers (for known NPCs — shows last-known position if not currently visible)
- Points of interest (quest-relevant locations highlighted)
- Player position and facing direction
- Fog of war for unexplored areas
- Interior map toggle (when inside a building)

### 14.2 World Map

Unlocks as the player discovers areas:

- Known settlements: Thornhaven, Millhaven, Iron Hollow, others
- Trade routes between settlements (with safety indicators: safe/dangerous/blocked)
- Terrain features: forests, rivers, mountains, ruins
- Fog of war for undiscovered areas
- Travel time estimates between locations
- Quest-relevant markers on discovered locations

### 14.3 Minimap

Always-visible (toggleable) circular minimap in HUD:

- Shows 100-unit radius around player
- Dots for NPCs (colored by disposition), buildings (gray), quest markers (gold)
- North indicator
- Edge indicators for off-screen quest objectives (arrow pointing toward the goal)

---

## 15. Pause Menu

### 15.1 Layout

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│                          LAND                                │
│                                                              │
│                      [Continue]                              │
│                      [Save Game]                             │
│                      [Load Game]                             │
│                      [Settings]                              │
│                      [Quit to Title]                         │
│                                                              │
│  Current location: Thornhaven Square                         │
│  Time: Day 5, Afternoon                                      │
│  Active threads: 3                                           │
└──────────────────────────────────────────────────────────────┘
```

### 15.2 Settings Submenus

**Audio:** Master volume, music, SFX, voice synthesis volume, voice synthesis on/off

**Display:** Resolution, fullscreen/windowed, pixel scaling, UI scale

**Controls:** Rebindable keys, gamepad support, mouse sensitivity

**Gameplay:** Notification detail mode (narrative/numerical), minimap on/off, combat damage numbers on/off, auto-tactical-pause option

**Accessibility:** Text size scaling, colorblind modes, screen reader support for dialogue text, reduced motion option, adjustable UI contrast, dialogue auto-advance speed, extended tooltip display time

---

## 16. Accessibility Considerations

### 16.1 Visual Accessibility

- **Scalable text:** All UI text respects a global text scale setting (75%-200%)
- **Colorblind modes:** Deuteranopia, protanopia, and tritanopia modes that shift all UI colors. Relationship indicators use shape + color, not color alone.
- **High contrast mode:** Option to increase contrast on all UI elements
- **Screen reader support:** All dialogue text, notifications, and menu items carry screen-reader-friendly text descriptions
- **Reduced motion:** Option to disable all animations (fade, slide, page-turn)

### 16.2 Input Accessibility

- **Full keyboard navigation:** Every UI panel is fully navigable with keyboard (arrow keys, Enter, Escape)
- **Gamepad support:** All UI designed with gamepad navigation in mind (d-pad movement, face buttons for confirm/cancel)
- **Rebindable keys:** All input actions can be rebound
- **One-handed mode:** Optional alternate control scheme
- **Adjustable hold times:** For hold-to-interact actions

### 16.3 Cognitive Accessibility

- **Detailed notification mode:** Toggle to show numerical values alongside narrative descriptions
- **Objective clarity toggle:** Option to show traditional checklist objectives alongside natural language goals
- **Quest tracking summary:** Optional "what am I doing?" reminder accessible with a single keypress
- **Dialogue history:** Full history of all past conversations accessible through the investigation board
- **NPC reminder:** When approaching an NPC, optional tooltip showing last conversation summary

---

## 17. Godot 4 Implementation Approach

### 17.1 Node Architecture

```
UIRoot (CanvasLayer)
├── HUD (Control) — Layer 1
│   ├── HealthBar (TextureProgressBar)
│   ├── StaminaBar (TextureProgressBar)
│   ├── ResolveBar (TextureProgressBar)
│   ├── TimeDisplay (HBoxContainer)
│   ├── Minimap (SubViewportContainer)
│   │   └── MinimapViewport (SubViewport)
│   │       └── MinimapCamera (Camera2D)
│   ├── QuestTracker (Label)
│   ├── CurrencyDisplay (HBoxContainer)
│   └── InteractionPrompt (CenterContainer)
│
├── DialogueLayer (CanvasLayer) — Layer 5
│   ├── DialoguePanel (PanelContainer)
│   │   ├── NPCInfoBar (HBoxContainer)
│   │   │   ├── Portrait (TextureRect)
│   │   │   ├── NameAndMood (VBoxContainer)
│   │   │   └── RelationshipBar (ProgressBar)
│   │   ├── DialogueHistory (RichTextLabel)
│   │   ├── ResponseOptions (VBoxContainer)
│   │   │   └── ResponseButton (x4-5, dynamic)
│   │   └── ControlBar (HBoxContainer)
│   └── EvidencePanel (PanelContainer) — slide-out
│
├── MenuLayer (CanvasLayer) — Layer 10
│   ├── InventoryPanel (PanelContainer)
│   ├── InvestigationBoard (Control) — custom 2D canvas
│   ├── CapabilityProfile (PanelContainer)
│   ├── MapPanel (PanelContainer)
│   ├── SocialPanel (PanelContainer)
│   └── ShopPanel (PanelContainer)
│
├── NotificationLayer (CanvasLayer) — Layer 15
│   └── NotificationContainer (VBoxContainer)
│
├── CombatLayer (CanvasLayer) — Layer 18
│   ├── CombatHUD (Control)
│   └── TacticalPauseOverlay (Control)
│
├── SystemLayer (CanvasLayer) — Layer 20
│   ├── PauseMenu (PanelContainer)
│   └── SettingsPanel (PanelContainer)
│
└── DebugLayer (CanvasLayer) — Layer 25 [debug builds only]
    ├── DebugConsole (existing)
    └── DebugInteractionPanel (existing)
```

### 17.2 Theme System

Create a shared `Theme` resource (`res://assets/themes/land_theme.tres`) applied to the UIRoot:

- Base `StyleBoxFlat` overrides for `PanelContainer`, `Button`, `Label`, `RichTextLabel`, `ProgressBar`, `LineEdit`
- Parchment-colored backgrounds with subtle border styling
- Consistent margins, padding, and font sizes
- Color constants defined as theme overrides for easy palette changes
- Separate theme variations for: combat (darker, more urgent), dialogue (warm, intimate), menus (journal-like)

### 17.3 Signal Integration

All UI components connect to existing systems via signals:

| UI Component | Connects To | Signals Used |
|-------------|-------------|--------------|
| HUD health bars | Player node | `health_changed`, `stamina_changed`, `resolve_changed` |
| Dialogue UI | NPC nodes, DialogueManager | `dialogue_started`, `dialogue_response_ready`, `dialogue_ended` |
| Quest tracker | QuestManager | `quest_available`, `quest_objective_completed` |
| Notifications | EventBus | `npc_relationship_changed`, `quest_started`, `quest_completed` |
| Minimap | NPC group, WorldState | Polls position each frame |
| Combat HUD | CombatManager (new) | `combat_started`, `combat_ended`, `damage_dealt`, `enemy_surrendered` |
| Shop UI | NPC inventory, PlayerInventory | `item_purchased`, `item_sold`, `haggle_result` |
| Investigation board | QuestManager, StoryThreadManager | `thread_tension_changed`, `evidence_discovered` |

### 17.4 Scene Organization

```
scenes/ui/
├── hud/
│   ├── hud.tscn
│   ├── health_bar.tscn
│   ├── minimap.tscn
│   ├── quest_tracker.tscn
│   └── interaction_prompt.tscn
├── dialogue/
│   ├── dialogue_panel.tscn
│   ├── response_option.tscn
│   └── evidence_panel.tscn
├── menus/
│   ├── inventory_panel.tscn
│   ├── equipment_view.tscn
│   ├── investigation_board.tscn
│   ├── capability_profile.tscn
│   ├── map_panel.tscn
│   ├── social_panel.tscn
│   └── shop_panel.tscn
├── combat/
│   ├── combat_hud.tscn
│   └── tactical_pause.tscn
├── notifications/
│   ├── quest_notifications.tscn (existing)
│   └── notification_toast.tscn
├── system/
│   ├── pause_menu.tscn
│   └── settings_panel.tscn
├── debug/ (existing)
│   ├── debug_console.tscn
│   └── debug_interaction_panel.tscn
└── shared/
    ├── npc_portrait.tscn
    └── item_tooltip.tscn
```

### 17.5 Performance Considerations

- **Investigation board:** Uses a custom `Control` with `_draw()` for connection lines rather than individual node instances. NPC cards are pooled and recycled.
- **Minimap:** Uses a `SubViewport` with a separate camera at reduced resolution (128x128 or 256x256) rendering a simplified version of the world.
- **Dialogue history:** Clears old entries beyond a threshold (keep last 50 lines in the visual display, archive to a data array for the full log).
- **Notifications:** Maximum 3 visible at once. Queue system prevents instantiation storms.
- **Response suggestions:** Generated asynchronously. UI shows "Generating options..." while the Claude call completes. Player can always type freely without waiting.

---

## 18. Integration with All Existing Systems

### 18.1 System-to-UI Mapping

| Backend System | UI Surfaces |
|---------------|-------------|
| **5D Relationship System** | Dialogue (mood, relationship bar), Social panel (5D visualization), Notifications (relationship changes) |
| **Autonomous NPC Agents** | Dialogue (NPC responses via Claude), Investigation board (NPC cards), Minimap (NPC positions) |
| **Emergent Narrative** | Investigation board (story threads), Notifications (thread events), Quest tracker (natural language goals) |
| **Combat System** | Combat HUD, Tactical pause overlay, Floating damage text, Non-lethal prompts |
| **Crafting/Inventory/Economics** | Inventory panel, Equipment view, Shop interface, Crafting preview, Currency display |
| **Skills/Progression** | Capability profile, Skill check indicators in dialogue, Technique indicators in combat |
| **Quest System** | Investigation board (replaces journal), Quest tracker in HUD, Notifications |
| **Voice Synthesis** | Dialogue UI (playback indicator), Settings (voice on/off and volume) |
| **Gossip/Rumor System** | Social panel (gossip log), Investigation board (rumor entries), Notifications |
| **World State** | Time display, Minimap, Map panel, HUD contextual changes |
| **EventBus** | All notifications, all UI state updates |

### 18.2 New Signals Needed on Existing Systems

The following signals should be added to existing backend systems to support UI:

```
# Player node (for HUD)
signal health_changed(current: float, max: float)
signal stamina_changed(current: float, max: float)
signal resolve_changed(current: float, max: float)
signal inventory_changed()
signal gold_changed(amount: int)
signal equipment_changed(slot: String, item: ItemData)

# WorldState (for HUD/Map)
signal time_of_day_changed(period: String)  # "dawn", "morning", etc.
signal area_discovered(area_id: String)

# DialogueManager (for dialogue UI)
signal response_options_generated(options: Array)
signal skill_check_available(skill: String, difficulty: String)
signal evidence_presentable(item_ids: Array)

# NPC nodes (for social/dialogue UI)
signal mood_changed(npc_id: String, mood: String)
signal gossip_heard(npc_id: String, rumor: Dictionary)

# CombatManager (new, for combat HUD)
signal combat_started(combatants: Array)
signal combat_ended(result: String)
signal target_changed(target: Node)
signal damage_dealt(source: Node, target: Node, amount: int, type: String)
signal surrender_offered(npc: Node)
signal ally_status_changed(ally: Node)
```

---

## 19. Implementation Priority

### Phase 1: Core HUD and Dialogue Redesign (Highest Priority)
**Why first:** These are the UI systems the player sees constantly. Without them, the game is unplayable.

1. **UIManager autoload** — Central controller for panel states and input routing
2. **HUD** — Health/stamina bars (placeholder data), interaction prompts, time display, currency
3. **Dialogue system redesign** — NPC portrait, thinking indicator, response options panel, evidence presentation button
4. **Notification system expansion** — Extend existing `quest_notifications.gd` to handle all notification types
5. **Theme resource** — Shared visual theme for parchment/ink aesthetic

### Phase 2: Investigation Board and Inventory
**Why second:** These unlock the narrative and economic gameplay loops.

6. **Investigation board** — Thread display, NPC cards, evidence pins, connection strings, natural language goals
7. **Inventory panel** — Item list, detail view, equipment slots, weight tracking
8. **Evidence presentation flow** — Full integration of evidence items into dialogue

### Phase 3: Social and Skills UI
**Why third:** These make the relationship and progression systems visible.

9. **Capability profile** — Skill domains, proficiency bars, mentor tracking, growth log
10. **Social/relationship panel** — NPC list, 5D visualization, gossip log, reputation

### Phase 4: Combat HUD
**Why fourth:** Combat system is Phase 7 in the dev plan — UI waits for the backend.

11. **Combat HUD** — Player/enemy/ally bars, floating damage, combo indicator
12. **Tactical pause overlay** — Full battlefield assessment, ally commands, non-lethal options
13. **Non-lethal action prompts** — Surrender, spare, intimidate indicators

### Phase 5: Shop, Crafting, and Map
**Why fifth:** These depend on the inventory and economic systems being implemented.

14. **Shop/trade interface** — NPC wares, player sellback, haggling, barter mode
15. **Crafting preview panel** — Material selection, quality preview, trust-gated techniques
16. **Map panel** — Local map, world map, fog of war
17. **Minimap** — SubViewport implementation, NPC markers

### Phase 6: Polish and Accessibility
**Why last:** Refinement layer on top of functional systems.

18. **Pause menu** — Save/load, settings, accessibility options
19. **Accessibility features** — Text scaling, colorblind modes, screen reader support
20. **Visual polish** — Animations, transitions, parchment textures, ink effects
21. **Contextual HUD visibility** — Fade rules, combat/exploration mode transitions

---

## 20. Open Questions and Risks

### Open Design Questions

1. **Response generation cost:** Each dialogue turn may require two Claude calls (NPC response + player suggestions). Need to evaluate latency and cost. Mitigation: generate suggestions asynchronously, make them optional.

2. **Investigation board complexity:** A free-form pinboard is complex to implement and may overwhelm some players. Mitigation: provide a "simple view" toggle that shows the traditional quest list (from existing journal).

3. **Portrait generation:** NPC portraits need to exist. Options: hand-drawn, AI-generated via asset pipeline, or simple geometric/silhouette style. Decision affects art pipeline timeline.

4. **Minimap rendering:** A SubViewport approach requires maintaining a simplified render of the world. May need a separate tilemap or icon-only representation for performance.

5. **Gamepad-first or keyboard-first?** The dialogue response options work naturally with both, but the investigation board (drag, connect, pan) is more natural with mouse/keyboard. Need to design a good gamepad alternative (cursor simulation or list-based navigation).

### Technical Risks

1. **Claude response latency for suggestions:** If response generation takes 2-4 seconds, the suggestions may arrive too late. Mitigation: show suggestions progressively as they generate, or pre-generate based on conversation context before the NPC finishes speaking.

2. **UI state complexity:** With 10+ panels, mode transitions, and contextual visibility rules, the UIManager needs careful state machine design to prevent conflicts and edge cases.

3. **Save/load with UI state:** The investigation board (player-positioned cards, manual connections) needs to be serialized. This adds to save file complexity.

---

*This document covers the complete UI architecture for Land. Implementation should follow the priority phases, starting with the UIManager autoload and HUD, then the dialogue redesign, and building outward from there. Every UI decision serves the core design identity: Land is a social mystery game where relationships matter more than combat, and the UI should reflect what the player knows, not what the system tracks.*
