# Future Work & Backlog

> **Document Purpose:** Track all planned features, improvements, and technical debt not yet addressed.
> **Last Updated:** December 2024
> **Status:** Living Document

---

## Table of Contents

1. [Priority Legend](#priority-legend)
2. [Story & Narrative](#story--narrative)
3. [NPCs & Characters](#npcs--characters)
4. [Locations & World](#locations--world)
5. [Systems & Mechanics](#systems--mechanics)
6. [Technical Debt](#technical-debt)
7. [Asset Generation](#asset-generation)
8. [Testing & QA](#testing--qa)

---

## Priority Legend

| Priority | Description | Timeline |
|----------|-------------|----------|
| **P0 - Critical** | Blocks core gameplay | Immediate |
| **P1 - High** | Required for story completion | Near-term |
| **P2 - Medium** | Enhances experience | Mid-term |
| **P3 - Low** | Nice to have | When time permits |
| **P4 - Backlog** | Future consideration | No timeline |

---

## Story & Narrative

### P1 - High Priority

#### Mira "Boss" Persona Implementation
- **Description:** Create separate personality/behavior for Mira's reveal as Iron Hollow's leader
- **Dependencies:** Romance system completion, Act III implementation
- **Files Affected:** New `mira_boss.tres`, dialogue system updates
- **Notes:**
  - Must handle three reveal paths: romance confession, cruel reveal, bandit join
  - Mira's cover persona (`mira_tavern_keeper.tres`) should NOT change
  - Need transition logic between personas
- **Reference:** [STORY_NARRATIVE.md - Bandit Leader section](./STORY_NARRATIVE.md)

#### Act III Confrontation System
- **Description:** Implement bandit camp assault/infiltration/negotiation paths
- **Dependencies:** Iron Hollow location (DONE), combat system
- **Components:**
  - [ ] Assault path with peacekeeper allies
  - [ ] Infiltration path (stealth or bandit trust)
  - [ ] Negotiation path (leverage Gregor's secret)
  - [ ] Takeover path (join and lead bandits)

#### Ending System
- **Description:** Implement multiple endings based on player choices
- **Endings to implement:**
  - [ ] Liberation (bandits destroyed, Gregor exposed)
  - [ ] Quiet Peace (bandits destroyed, secret kept)
  - [ ] The Deal (negotiated peace)
  - [ ] Iron Crown (player leads bandits)
  - [ ] Puppet Master (player controls via blackmail)
  - [ ] Ashes (failure ending)

### P2 - Medium Priority

#### Quest Flag System
- **Description:** Track story progression flags
- **Flags needed:**
  ```
  informant_known, gregor_suspected, gregor_evidence,
  gregor_confronted, gregor_exposed, elena_knows,
  bandits_contacted, bandits_joined, bandits_destroyed,
  current_act
  ```

#### Evidence Collection System
- **Description:** Track evidence player has gathered
- **Evidence items:**
  - [ ] Gregor's suspicious ledger
  - [ ] Bjorn's marked weapon found on bandit
  - [ ] Witness testimony (Mira)
  - [ ] Direct observation of Gregor meeting Varn

---

## NPCs & Characters

### P1 - High Priority

#### Phase 5: NPC-to-NPC Relationship Events
- **Description:** Implement event-based relationship changes between NPCs
- **Components:**
  - [ ] `betrayal_discovered` event type
  - [ ] `secret_revealed` event type
  - [ ] `confrontation` event type
  - [ ] Event propagation system
- **Reference:** [NPC_SPECIFICATIONS.md - Phase 5](./NPC_SPECIFICATIONS.md)

### P2 - Medium Priority

#### Generic Villagers
- **Description:** Atmosphere NPCs for village life
- **NPCs to create:**
  - [ ] Farmer Thomas - Sells produce, complains about bandit taxes
  - [ ] Widow Henna - Lost son to bandits, wants revenge
  - [ ] Young Peter - Teenage boy who idolizes adventurers
- **Notes:** Can use simplified personality system

#### Generic Bandits
- **Description:** Combat encounter enemies
- **Types to create:**
  - [ ] Bandit Grunt - Basic melee enemy
  - [ ] Bandit Archer - Ranged enemy
  - [ ] Bandit Brute - Heavy/tank enemy
- **Notes:** May not need full dialogue system

#### Peacekeeper NPCs
- **Description:** Aldric's volunteer corps members
- **Count:** 5-6 named peacekeepers
- **Notes:** Support combat, can be armed by Bjorn

### P3 - Low Priority

#### NPC Schedules
- **Description:** NPCs move between locations based on time
- **Example:** Elena at shop during day, home at night
- **Dependencies:** Day/night cycle system

#### NPC Idle Behaviors
- **Description:** NPCs perform contextual actions when not in dialogue
- **Examples:** Bjorn hammering, Mira wiping bar, Gregor counting coins

---

## Locations & World

### P1 - High Priority

#### Forest Path Scene
- **Description:** Route between Thornhaven and Iron Hollow
- **Features:**
  - [ ] Ambush encounter possibility
  - [ ] Evidence of bandit activity (tracks, camps)
  - [ ] Multiple path choices (safe vs. fast)
- **File:** `scenes/exterior/forest_path.tscn`

#### Scene Transition System
- **Description:** Connect all locations properly
- **Connections needed:**
  - [ ] Town Square ↔ Forest Path
  - [ ] Forest Path ↔ Iron Hollow
  - [ ] Town Square ↔ All interiors
- **Notes:** Some connections exist, need verification

### P2 - Medium Priority

#### Council Hall Interior
- **Description:** Meeting place for village elders
- **Purpose:** Political decisions, rallying support
- **File:** `scenes/interiors/council_hall.tscn`

#### Old Mill Location
- **Description:** Secret meeting spot for Gregor and Varn
- **Purpose:** Evidence gathering, confrontation site
- **File:** `scenes/exterior/old_mill.tscn`

### P3 - Low Priority

#### Village Houses (Interiors)
- **Description:** Generic villager homes
- **Notes:** Only if generic villagers implemented

#### Bandit Patrol Routes
- **Description:** Random encounter areas outside town
- **Notes:** Requires combat system

---

## Systems & Mechanics

### P1 - High Priority

#### Combat System
- **Description:** Player vs. enemy combat
- **Components:**
  - [ ] Basic attack/defense
  - [ ] Health system
  - [ ] Death/defeat handling
  - [ ] NPC combat AI
- **Notes:** Scope TBD - simple or complex?

#### Romance System Completion
- **Description:** Full romance path implementation
- **Available romances:** Elena, Mira, Bjorn
- **Components:**
  - [ ] Romance state tracking
  - [ ] Romance-specific dialogue branches
  - [ ] Romance endings
  - [ ] Mira romance → Boss reveal path

### P2 - Medium Priority

#### Inventory System
- **Description:** Player can collect and use items
- **Item types:**
  - [ ] Evidence items
  - [ ] Weapons/equipment
  - [ ] Consumables
  - [ ] Quest items

#### Economy System
- **Description:** Gold, buying, selling
- **Components:**
  - [ ] Player gold tracking
  - [ ] Shop interfaces
  - [ ] Price variation based on reputation

#### Reputation System
- **Description:** Track player's standing with factions
- **Factions:**
  - [ ] Village (general populace)
  - [ ] Council (political)
  - [ ] Peacekeepers (law enforcement)
  - [ ] Bandits (criminal)

### P3 - Low Priority

#### Day/Night Cycle
- **Description:** Time passes, affects NPC availability
- **Notes:** Significant scope, may not be needed

#### Weather System
- **Description:** Visual variety, possible gameplay effects
- **Notes:** Polish feature, low priority

---

## Technical Debt

### P1 - High Priority

#### Consolidate Scene Files
- **Issue:** Both `thornhaven_square.tscn` and `game_world.tscn` exist
- **Action:** Determine which is canonical, remove/repurpose other
- **Notes:** `game_world.tscn` appears more complete

#### Memory System Error Handling
- **Issue:** RAG/ChromaDB failures could crash game
- **Action:** Add graceful fallbacks
- **Notes:** NPCs should work (degraded) without memory

### P2 - Medium Priority

#### NPC Script Cleanup
- **Issue:** Some scripts may have redundant code after personality refactor
- **Action:** Audit all NPC scripts for dead code

#### Asset Generation Pipeline
- **Issue:** Manual generation process, no caching strategy
- **Action:** Document pipeline, add generation tracking

### P3 - Low Priority

#### Performance Profiling
- **Issue:** Unknown performance with many NPCs
- **Action:** Profile with full NPC set, optimize if needed

#### Save System Verification
- **Issue:** Untested with full NPC state
- **Action:** Verify save/load preserves all NPC data

---

## Asset Generation

### P1 - High Priority

#### Generate Missing NPC Sprites
- **NPCs needing sprites:**
  - [ ] Varn (bandit lieutenant)
  - [ ] Captain Aldric (peacekeeper)
  - [ ] Elder Mathias (council head)
- **Notes:** Use PixelLab MCP tools with appearance_prompt from scripts

### P2 - Medium Priority

#### Iron Hollow Camp Assets
- **Assets needed:**
  - [ ] Command tent building
  - [ ] Barracks tents
  - [ ] Campfire prop
  - [ ] Weapon racks
  - [ ] Loot barrels/crates

#### Character Animations
- **Animations needed per character:**
  - [ ] Idle
  - [ ] Walking (8 directions)
  - [ ] Talking gesture
- **Notes:** Use PixelLab animate_character tool

### P3 - Low Priority

#### Environmental Props
- **Props for atmosphere:**
  - [ ] Market stalls
  - [ ] Wanted posters
  - [ ] Village decorations

---

## Testing & QA

### P1 - High Priority

#### Execute Phase 4 Tests
- **Reference:** [TESTING.md](./TESTING.md)
- **Tests:**
  - [ ] TC-001: Gregor Confession Path
  - [ ] TC-002: Elena Reaction
  - [ ] TC-003: Mira Information
  - [ ] TC-004: Bjorn Weapons
  - [ ] TC-005: Cross-NPC Awareness

#### Debug Command Implementation
- **Commands needed:**
  - [ ] `set_trust <npc_id> <value>`
  - [ ] `set_affection <npc_id> <value>`
  - [ ] `show_npc_state <npc_id>`
  - [ ] `trigger_event <event_type>`

### P2 - Medium Priority

#### Automated Test Suite
- **Description:** GDScript unit tests for core systems
- **Coverage areas:**
  - [ ] NPC personality loading
  - [ ] Memory system operations
  - [ ] Trust/affection calculations
  - [ ] Event propagation

#### Playtesting Sessions
- **Description:** Full playthrough testing
- **Paths to test:**
  - [ ] Hero path (expose Gregor, defeat bandits)
  - [ ] Pragmatist path (negotiate)
  - [ ] Dark path (join bandits)
  - [ ] Romance paths (Elena, Mira, Bjorn)

---

## Completed Items (Archive)

### December 2024

- [x] Phase 1: Update existing NPC personalities (Gregor, Elena)
- [x] Phase 2: Create missing personality files (Mira, Bjorn)
- [x] Phase 3: Create new NPCs (Varn, Aldric, Mathias)
- [x] Position NPCs in game world
- [x] Create Iron Hollow location
- [x] Document Mira as The Boss twist
- [x] Update Varn's secrets about The Boss

---

## Notes & Decisions Log

### Design Decisions

| Date | Decision | Rationale |
|------|----------|-----------|
| Dec 2024 | Event-based NPC relationships | Avoids O(n²) complexity, reduces hallucination |
| Dec 2024 | Mira is The Boss | Subverts widow trope, explains her knowledge |
| Dec 2024 | Personality in .tres files | Separates data from code, easier iteration |

### Open Questions

1. **Combat Scope:** Simple or complex combat system?
2. **Time System:** Day/night cycle needed?
3. **Multiple Playthroughs:** New Game+ features?
4. **Voice/Audio:** Any NPC audio planned?

---

*This document should be updated as work is completed or new items are identified.*
