# Quest Journal UI Design

## Overview

A player-facing UI for viewing quest progress, objectives, and story context. Accessed via hotkey, styled to match the game's JRPG aesthetic.

---

## Access & Controls

| Action | Key | Description |
|--------|-----|-------------|
| Open/Close Journal | `J` | Toggle quest journal visibility |
| Navigate tabs | `Tab` / Click | Switch between Active/Completed/Available |
| Select quest | `Up/Down` / Click | Highlight quest in list |
| Close | `Escape` / `J` | Close journal |

**Note**: Journal should pause game or be accessible during normal gameplay (not during dialogue).

---

## Layout Structure

```
┌─────────────────────────────────────────────────────────────────┐
│  📜 Quest Journal                                          [X]  │
├─────────────────────────────────────────────────────────────────┤
│  [Active (2)]  [Completed (0)]  [Discovered (1)]                │
├──────────────────────┬──────────────────────────────────────────┤
│                      │                                          │
│  ▸ Whispers of       │  WHISPERS OF CONSPIRACY                  │
│    Conspiracy ★      │  ─────────────────────                   │
│                      │                                          │
│  ▸ Elena's           │  The merchant Gregor seems to know       │
│    Whereabouts       │  something about secret dealings in      │
│                      │  town. Perhaps gaining his trust will    │
│                      │  reveal more.                            │
│                      │                                          │
│                      │  OBJECTIVES                               │
│                      │  ──────────                               │
│                      │  ☑ Earn Gregor's trust                   │
│                      │  ☐ Learn about the mysterious ledger     │
│                      │  ☐ Uncover the conspiracy                │
│                      │                                          │
│                      │  HINTS                                    │
│                      │  ─────                                    │
│                      │  • Gregor responds well to respectful    │
│                      │    conversation                          │
│                      │  • Trust level: 45/60 needed             │
│                      │                                          │
└──────────────────────┴──────────────────────────────────────────┘
```

---

## Tab Definitions

### Active Quests
- Quests currently in progress (`QuestState.ACTIVE`)
- Sorted by priority (main quests first, then by priority value)
- Shows completion percentage based on objectives done

### Completed Quests
- Quests that have been finished (`QuestState.COMPLETED`)
- Shows the ending achieved (e.g., "Full Truth", "Partial Truth")
- Grayed out or different styling to indicate completion

### Discovered Quests
- Quests that are available but not yet started (`QuestState.AVAILABLE`)
- Brief teaser description
- Player knows about them but hasn't committed

---

## Quest Detail Panel

### Header
- **Title**: Quest name in large text
- **Type Badge**: `[MAIN]` or `[SIDE]` indicator
- **Story Arc**: Subtle text showing arc name (e.g., "Main Conspiracy")

### Description
- Full quest description from `QuestResource.description`
- Wrapped text, scrollable if long

### Objectives
- List of objectives with completion status
- `☑` for completed, `☐` for incomplete
- Only show objectives in current order (don't spoil future ones)
- Optional: Show locked objectives as `🔒 ???`

### Progress Hints (Optional Section)
For objectives with measurable progress, show hints:
- **Relationship objectives**: "Trust: 45/60 needed"
- **Topic objectives**: "Ask about: ledger, secrets"
- **Location objectives**: "Travel to: ???" (if location unknown)

**Design Decision**: Should hints be shown?
- **Option A**: Always show hints (easier for players)
- **Option B**: Only show hints if player has partial progress
- **Option C**: Never show hints (more mysterious)

---

## Visual Design

### Color Scheme
Match existing UI (debug console style but more polished):

| Element | Color |
|---------|-------|
| Background | Dark semi-transparent (`#1a1a2e` @ 90% opacity) |
| Header | Gold/amber (`#f0c040`) |
| Active quest | White text |
| Completed quest | Gray text (`#888888`) |
| Main quest indicator | Gold star (`★`) |
| Objective complete | Green check (`#40c040`) |
| Objective incomplete | Gray box (`#666666`) |

### Fonts
- Header: Larger size (18-20px)
- Quest titles: Medium (14-16px)
- Body text: Standard (12-14px)
- Use existing game font if available

### Panel Sizing
- Default: 800x500 pixels
- Centered on screen
- Not resizable (unlike debug console)
- Modal (blocks input to game while open)

---

## Data Flow

```
QuestManager                    QuestJournalUI
     │                               │
     │  get_active_quest_ids()       │
     │<──────────────────────────────│
     │                               │
     │  get_quest(quest_id)          │
     │<──────────────────────────────│
     │                               │
     │  Returns QuestResource        │
     │──────────────────────────────>│
     │                               │
     │                          Display quest
     │                          title, description,
     │                          objectives
```

### Required QuestManager Methods (already exist)
- `get_active_quest_ids()` → Array of active quest IDs
- `get_completed_quest_ids()` → Array of completed quest IDs
- `get_available_quest_ids()` → Array of available quest IDs
- `get_quest(quest_id)` → QuestResource

### Required QuestResource Properties (already exist)
- `title`, `description`, `story_arc`
- `is_main_quest`, `priority`
- `objectives` → Array of QuestObjective
- `possible_endings`, `ending_achieved`

---

## File Structure

```
scenes/ui/
├── quest_journal.tscn      # Main scene
└── quest_journal.gd        # Script

# Add to existing main scene or HUD
```

### Scene Hierarchy
```
QuestJournal (Control)
├── Panel (Panel)
│   ├── Header (HBoxContainer)
│   │   ├── TitleLabel
│   │   └── CloseButton
│   ├── TabContainer (HBoxContainer)
│   │   ├── ActiveTab (Button)
│   │   ├── CompletedTab (Button)
│   │   └── DiscoveredTab (Button)
│   └── ContentSplit (HSplitContainer)
│       ├── QuestList (VBoxContainer + ScrollContainer)
│       │   └── [QuestListItem...] (generated)
│       └── QuestDetail (VBoxContainer + ScrollContainer)
│           ├── QuestTitle
│           ├── QuestDescription
│           ├── ObjectivesHeader
│           └── ObjectivesList
```

---

## Notifications (Future Enhancement)

When quest state changes, show brief notification:

```
┌────────────────────────────┐
│  📜 Quest Updated          │
│  Whispers of Conspiracy    │
│  Objective complete!       │
└────────────────────────────┘
```

- Appears in corner of screen
- Auto-dismisses after 3 seconds
- Clicking opens journal to that quest

**Note**: This is a future enhancement, not part of initial implementation.

---

## Implementation Priority

### Phase 1: Core UI (Initial)
1. Basic panel with tab navigation
2. Quest list population from QuestManager
3. Quest detail display
4. Hotkey to open/close

### Phase 2: Polish
1. Objective progress hints
2. Keyboard navigation
3. Visual polish and animations
4. Sound effects on open/close

### Phase 3: Notifications (Future)
1. Quest state change notifications
2. New quest discovered popup
3. Quest complete celebration

---

## Design Decisions

### 1. Game Pauses When Journal Open ✓
- Journal is modal - pauses game while open
- Player can read without time pressure
- Uses `get_tree().paused = true/false`
- Journal must be in `process_mode = PROCESS_MODE_ALWAYS` to work while paused

### 2. Show Objective Hints ✓
Since the game is heavily dialogue-driven, players need breadcrumbs:
- **Relationship objectives**: "Trust: 45/60 needed" with progress bar
- **Topic objectives**: "Discuss: ledger, conspiracy, secrets"
- **NPC objectives**: "Speak with: Gregor"
- **Location objectives**: "Travel to: Town Square"
- **Flag objectives**: "Requirement not yet met" (vague for mystery)

### 3. UI Layering
Journal should not interfere with other game UI:
- Uses dedicated CanvasLayer (layer 10)
- Other UI (inventory, dialogue) on different layers
- Input handling respects UI stack
- Only one modal UI active at a time

### 4. Journal NOT Accessible During Dialogue
- Hotkey disabled while in conversation
- Prevents breaking flow and immersion

---

## Hint Display Format

```
OBJECTIVES
──────────
☑ Earn Gregor's trust
   └─ Complete: Trust reached 60

☐ Learn about the mysterious ledger
   └─ Discuss with Gregor: "ledger", "records", "books"

☐ Uncover the conspiracy
   └─ Requires: Previous objective
```

For relationship-based objectives:
```
☐ Gain Mira's confidence
   └─ Trust: ████████░░ 42/60
```

---

## Recommendation

Start with **Phase 1**:
- Simple, functional journal
- Tab navigation between Active/Completed/Discovered
- Quest list + detail view with hints
- `J` hotkey to toggle (disabled during dialogue)
- Pause game while open
- CanvasLayer 10 for proper UI stacking
