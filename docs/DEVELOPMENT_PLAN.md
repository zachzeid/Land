# Development Plan

> **Document Purpose:** Authoritative roadmap for Land development
> **Last Updated:** December 2024

---

## Completed Phases

### Phase 1-5: Foundation (Complete)

| Phase | Focus | Status |
|-------|-------|--------|
| 1 | NPC Personality Framework | ✅ Complete |
| 2 | Create Missing Personalities | ✅ Complete |
| 3 | New NPCs (Varn, Aldric, Mathias) | ✅ Complete |
| 4 | World Positioning | ✅ Complete |
| 5 | Iron Hollow Location | ✅ Complete |

### Phase 6: Story Testability (Complete)

| Component | Status | Key Files |
|-----------|--------|-----------|
| WorldState Enhancements | ✅ Done | `get_flags()`, `get_active_quests()` |
| Story Flags | ✅ Done | `story_flags.gd` (25 flags) |
| Debug Command System | ✅ Done | `debug_console.gd` (12 commands) |
| Quest System | ✅ Done | QuestManager, QuestResource, QuestObjective |
| Quest Journal UI | ✅ Done | `quest_journal.gd`, tabbed interface |
| Quest Notifications | ✅ Done | `quest_notifications.gd` |
| Quest Context Injection | ✅ Done | NPCs hint toward objectives |
| Intent Detection | ✅ Done | `intent_detector.gd` |

**Debug Commands Available:**
- `list_npcs` / `show_npc <id>` - View NPCs and their state
- `set_trust/respect/affection/fear/familiarity <id> <value>` - Modify relationships
- `set_flag <name> <0|1>` / `list_flags` - Manage story flags
- `reset_npc <id>` / `clear` / `help` - Utility commands

---

## Current Phase: 6.5 - Story Polish

### Remaining Items (Deferred from Phase 6)

| Task | Priority | Notes |
|------|----------|-------|
| Evidence Discovery Triggers | P1 | Area2D triggers for ledger, weapons |
| NPC Event Propagation | P1 | NPCs auto-learn from world events |
| Sample Quest Content | P2 | Create main quest chain |

---

## Future Phases

### Phase 7: Combat System

| Component | Priority | Notes |
|-----------|----------|-------|
| Basic Attack/Defense | P0 | Core combat mechanics |
| Health System | P0 | Player and NPC health |
| Death/Defeat Handling | P0 | Game over, respawn |
| NPC Combat AI | P1 | Enemy behavior |
| NPC Combat Participation | P2 | Allies join fights based on relationship |

### Phase 8: Inventory & Trading

| Component | Priority | Notes |
|-----------|----------|-------|
| Item Management | P0 | Basic inventory system |
| Evidence Items | P0 | Ledger, marked weapons |
| Shop Interfaces | P1 | Buy/sell with NPCs |
| Gift-Giving | P2 | Affects relationships |

### Phase 9: Romance Specialization

| Component | Priority | Notes |
|-----------|----------|-------|
| Romance State Tracking | P0 | Track romance progress |
| Romance Dialogue Branches | P1 | Dedicated conversation paths |
| Romance Endings | P1 | Unique ending per romance |
| Elena Romance Path | P0 | Primary romance option |
| Mira Romance → Boss Reveal | P1 | Twist integration |
| Bjorn Romance Path | P2 | Optional romance |

### Phase 10: Multiple Endings

| Ending | Trigger Conditions |
|--------|-------------------|
| Liberation | Bandits destroyed, Gregor exposed |
| Quiet Peace | Bandits destroyed, secret kept |
| The Deal | Negotiated peace |
| Iron Crown | Player leads bandits |
| Puppet Master | Player controls via blackmail |
| Ashes | Failure ending |

### Phase 11: Voice Synthesis

| Component | Notes |
|-----------|-------|
| ElevenLabs TTS | Per-NPC voice assignment |
| Audio Caching | Cost optimization |
| Tone Bracket Stripping | Clean speech output |

See [Voice Synthesis Plan](VOICE_SYNTHESIS_PLAN.md) for details.

---

## Backlog (No Timeline)

### NPCs & Characters

| Task | Priority | Notes |
|------|----------|-------|
| Generic Villagers | P3 | Farmer Thomas, Widow Henna, Young Peter |
| Generic Bandits | P3 | Grunt, Archer, Brute types |
| Peacekeeper NPCs | P3 | 5-6 named peacekeepers |
| NPC Schedules | P4 | Time-based movement |
| NPC Idle Behaviors | P4 | Contextual animations |

### Locations

| Task | Priority | Notes |
|------|----------|-------|
| Forest Path Scene | P2 | Route between Thornhaven and Iron Hollow |
| Council Hall Interior | P3 | Political decisions location |
| Old Mill Location | P3 | Secret meeting spot |
| Village Houses | P4 | Generic villager homes |

### Systems

| Task | Priority | Notes |
|------|----------|-------|
| Economy System | P3 | Gold, prices, reputation effects |
| Reputation System | P3 | Faction standing (Village, Council, Peacekeepers, Bandits) |
| Day/Night Cycle | P4 | NPC schedule dependency |
| Weather System | P4 | Visual polish |

### Technical Debt

| Task | Priority | Notes |
|------|----------|-------|
| Memory System Error Handling | P2 | Graceful ChromaDB fallbacks |
| Save System Verification | P3 | Full NPC state persistence |
| Performance Profiling | P3 | Multiple NPC scaling |

### Asset Generation

| Task | Priority | Notes |
|------|----------|-------|
| Missing NPC Sprites | P2 | Varn, Aldric, Mathias |
| Iron Hollow Camp Assets | P3 | Tents, campfire, weapon racks |
| Character Animations | P3 | Idle, walking, talking |
| Environmental Props | P4 | Market stalls, decorations |

---

## Priority Legend

| Priority | Description | Timeline |
|----------|-------------|----------|
| **P0** | Blocks core gameplay | Current phase |
| **P1** | Required for story completion | Near-term |
| **P2** | Enhances experience | Mid-term |
| **P3** | Nice to have | When time permits |
| **P4** | Future consideration | No timeline |

---

## Design Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| Dec 2024 | Event-based NPC relationships | Avoids O(n²) complexity, reduces hallucination |
| Dec 2024 | Mira is The Boss | Subverts widow trope, explains her knowledge |
| Dec 2024 | Personality in .tres files | Separates data from code, easier iteration |
| Dec 2024 | Quest context injection | NPCs naturally hint at objectives |
| Dec 2024 | Tiered memory (Pinned/Important/Relevant) | Prevents context overflow |

---

## Open Questions

1. **Combat Scope:** Simple or complex combat system?
2. **Time System:** Day/night cycle needed?
3. **Multiple Playthroughs:** New Game+ features?
4. **Voice/Audio:** Proceed with ElevenLabs integration?

---

*This document is the authoritative roadmap. Update as phases complete.*
