# NPC System Testing Guide

> **Document Purpose:** Test cases and procedures for validating NPC behavior, dialogue, and story progression.
> **Last Updated:** December 2024
> **Status:** Phase 4 Testing

---

## Table of Contents

1. [Testing Overview](#testing-overview)
2. [Test Environment Setup](#test-environment-setup)
3. [Phase 4 Test Cases](#phase-4-test-cases)
4. [Test Execution Checklist](#test-execution-checklist)
5. [Known Issues & Edge Cases](#known-issues--edge-cases)
6. [Regression Tests](#regression-tests)

---

## Testing Overview

### What We're Testing

| Category | Description |
|----------|-------------|
| **Dialogue Flow** | NPCs respond appropriately based on personality |
| **Trust Progression** | Secrets unlock at correct thresholds |
| **Cross-NPC Awareness** | Information shared with one NPC affects others |
| **Story Consistency** | NPCs maintain consistent knowledge and behavior |
| **Memory Persistence** | RAG memory system stores and retrieves correctly |

### Testing Approach

1. **Manual Dialogue Testing** - Interact with NPCs, verify responses
2. **Threshold Testing** - Manipulate trust/affection values, verify secret unlocks
3. **Event Propagation Testing** - Trigger events, verify cross-NPC updates
4. **Edge Case Testing** - Test boundary conditions and error handling

---

## Test Environment Setup

### Prerequisites

```gdscript
# Enable debug console in-game with backtick (`) key
# Use debug commands to manipulate NPC state
```

### Debug Commands (Implemented)

Toggle console with backtick (`) key.

| Command | Description |
|---------|-------------|
| `help` | Show all available commands |
| `list_npcs` / `npcs` | List all NPCs in current scene |
| `show_npc <id>` / `npc <id>` | Display NPC state and secret unlock status |
| `set_trust <npc_id> <value>` | Set trust value (0-100) |
| `set_respect <npc_id> <value>` | Set respect value (0-100) |
| `set_affection <npc_id> <value>` | Set affection value (0-100) |
| `set_fear <npc_id> <value>` | Set fear value (0-100) |
| `set_familiarity <npc_id> <value>` | Set familiarity value (0-100) |
| `reset_npc <npc_id>` | Reset NPC to initial state |
| `set_flag <name> <0\|1>` | Set world flag (e.g., `set_flag ledger_found 1`) |
| `list_flags` / `flags` | Show all world flags |
| `clear` | Clear console output |

**NPC ID Matching:** Commands accept full NPC IDs (e.g., `gregor_001`), partial names (e.g., `gregor`), or display names (e.g., `Gregor`).

### Test Locations

| Location | Scene | NPCs Present |
|----------|-------|--------------|
| Town Square | `game_world.tscn` | Elena, Aldric, Mathias |
| Gregor's Shop | `gregor_shop_interior.tscn` | Gregor |
| Tavern | `tavern_interior.tscn` | Mira |
| Blacksmith | `blacksmith_interior.tscn` | Bjorn |
| Iron Hollow | `iron_hollow.tscn` | Varn |

---

## Phase 4 Test Cases

### TC-001: Gregor Confession Path

**Objective:** Verify Gregor reveals secrets at appropriate trust levels and responds correctly when confronted with evidence.

#### Test Steps

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Talk to Gregor with trust < 50 | Friendly but guarded, no secrets revealed |
| 2 | Increase trust to 50-59 | Hints at "complicated business arrangements" |
| 3 | Increase trust to 60-69 | May reveal secret about saving gold for Elena |
| 4 | Increase trust to 70-79 | May reveal weapons go to bandits via his orders |
| 5 | Increase trust to 80+ | May confess about bandit deal if cornered |
| 6 | Confront with evidence (ledger) | Breaks down, offers deal or begs for understanding |
| 7 | Threaten to expose | Desperate behavior, may threaten back or bargain |

#### Secret Unlock Verification

| Secret | Trust Threshold | Affection Threshold |
|--------|-----------------|---------------------|
| "Made a deal with bandits" | 50 | 40 |
| "Weapons go to bandits via Bjorn" | 60 | 50 |
| "Saved gold for Elena to escape" | 65 | 55 |
| "Meets Varn monthly at old mill" | 70 | 60 |
| "Full confession" | 85 | 75 |

#### Pass Criteria
- [ ] Secrets unlock at correct thresholds
- [ ] Gregor's tone shifts from confident to nervous as trust increases
- [ ] Confession behavior matches personality (defensive → breakdown)
- [ ] References Elena's safety as justification

---

### TC-002: Elena Reaction to Father's Secret

**Objective:** Verify Elena's denial behavior and reaction when learning the truth about Gregor.

#### Test Steps

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Talk to Elena with trust < 50 | Friendly, curious about outside world |
| 2 | Ask about her father | Defensive, changes subject |
| 3 | Increase trust to 55+ | Shares she saw father meeting hooded figure |
| 4 | Increase trust to 65+ | Mentions father's savings, questions why |
| 5 | Increase trust to 80+ | Admits suspicion about father and bandits |
| 6 | Tell Elena her father is the informant (low trust) | Denial, anger at player, may become hostile |
| 7 | Tell Elena her father is the informant (high trust) | Devastation, "I knew... I always knew..." |

#### Reaction Matrix

| Player Trust | Evidence Provided | Elena's Reaction |
|--------------|-------------------|------------------|
| < 40 | None | Angry, refuses to believe |
| < 40 | With proof | Angry at player for "destroying her world" |
| 40-60 | None | Conflicted, denial mixed with doubt |
| 40-60 | With proof | Devastated, needs time to process |
| 60+ | None | Sad acceptance, suspected already |
| 60+ | With proof | Leans on player for support |

#### Pass Criteria
- [ ] Elena shows denial behavior until trust is high
- [ ] Reaction severity matches relationship level
- [ ] Doesn't immediately forgive or condemn father
- [ ] Romance path complicates reaction appropriately

---

### TC-003: Mira Sharing Information Progression

**Objective:** Verify Mira reveals information about Gregor at appropriate trust levels.

#### Test Steps

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Talk to Mira with trust < 30 | Polite but closed, quick service |
| 2 | Increase trust to 30-49 | Shares gossip, mentions husband obliquely |
| 3 | Increase trust to 50-69 | Hints at "seeing things", tests player's discretion |
| 4 | Increase trust to 70+ | Will share what she knows if promised protection |
| 5 | Ask about Gregor (low trust) | "He's a merchant. Good customer. Why?" |
| 6 | Ask about Gregor (medium trust) | "His shop does well... better than the rest of us." |
| 7 | Ask about Gregor (high trust) | "I've seen things. But I can't... not unless..." |
| 8 | Ask about Gregor (very high trust) | Names him as the informant |

#### Secret Unlock Verification

| Secret | Trust Threshold | Affection Threshold |
|--------|-----------------|---------------------|
| Husband's true death (execution) | 40 | 35 |
| Saw Gregor meeting bandits | 60 | 50 |
| Knows Varn killed Marcus | 75 | 60 |
| Thought about poisoning Gregor | 85 | 70 |

#### Pass Criteria
- [ ] Information reveals follow trust progression
- [ ] Mira's fear is evident (nervous glances, whispers)
- [ ] Requires protection promise before naming Gregor
- [ ] References husband's death appropriately

---

### TC-004: Bjorn Learning About Weapons

**Objective:** Verify Bjorn's reaction when discovering his weapons arm bandits.

#### Test Steps

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Talk to Bjorn about his craft | Proud, detailed discussion |
| 2 | Ask about weapon orders | Mentions Gregor orders many, doesn't question |
| 3 | Point out weapons disappear faster than they should sell | Thoughtful, "Hmm. You're right..." |
| 4 | Increase trust to 50+ | Reveals he marks weapons with 'B' on tang |
| 5 | Show proof weapons go to bandits | Devastated, guilty, angry at Gregor |
| 6 | Ask him to help resistance | Agrees to arm peacekeepers |
| 7 | Ask him to confront Gregor | May agree if trust is high |

#### Redemption Path Verification

| Action | Bjorn's Response |
|--------|------------------|
| Player reveals truth | Horror, guilt, needs moment to process |
| Player asks for help | "What can I do to make this right?" |
| Player asks him to arm peacekeepers | Agrees - wants to atone |
| Player asks him to stop supplying Gregor | Immediately agrees |

#### Pass Criteria
- [ ] Bjorn is genuinely oblivious before reveal
- [ ] Reaction shows horror at unknowing complicity
- [ ] Offers to help make amends
- [ ] Doesn't immediately blame Gregor without processing

---

### TC-005: Cross-NPC Awareness (Gossip System)

**Objective:** Verify that information revealed to one NPC affects others appropriately.

#### Test Scenarios

##### Scenario A: Player Tells Bjorn About Gregor

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Tell Bjorn that Gregor supplies bandits | Bjorn stores memory event |
| 2 | Talk to Bjorn again about Gregor | References the betrayal |
| 3 | Visit Gregor (if Bjorn confronted him) | Gregor may know he's been exposed |

##### Scenario B: Player Tells Aldric About Gregor

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Provide Aldric with proof of Gregor's guilt | Aldric stores evidence memory |
| 2 | Ask Aldric about next steps | Discusses arrest/confrontation plans |
| 3 | Visit Elder Mathias | If Aldric reported, Mathias may know |

##### Scenario C: Elena Learns Truth

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Tell Elena about her father | Elena stores traumatic memory |
| 2 | Visit Gregor | If Elena confronted him, his behavior changes |
| 3 | Talk to Elena again | References the revelation, ongoing processing |

#### Memory Event Types to Verify

| Event Type | Trigger | NPCs Affected |
|------------|---------|---------------|
| `betrayal_discovered` | Bjorn learns about weapons | Bjorn |
| `secret_revealed` | Player shares information | Target NPC |
| `confrontation` | NPC confronts another | Both NPCs involved |
| `accusation` | Player accuses NPC | Accused NPC |

#### Pass Criteria
- [ ] Memory events store correctly in RAG system
- [ ] NPCs reference stored memories in subsequent conversations
- [ ] Information propagation follows logical paths
- [ ] NPCs don't know things they shouldn't

---

## Test Execution Checklist

### Pre-Test Setup

- [ ] Game launches without errors
- [ ] All NPCs load in correct locations
- [ ] Debug console accessible
- [ ] Save system working (for state restoration)

### Phase 4 Test Execution

| Test Case | Tester | Date | Pass/Fail | Notes |
|-----------|--------|------|-----------|-------|
| TC-001: Gregor Confession | | | | |
| TC-002: Elena Reaction | | | | |
| TC-003: Mira Information | | | | |
| TC-004: Bjorn Weapons | | | | |
| TC-005: Cross-NPC Awareness | | | | |

### Post-Test Verification

- [ ] No console errors during testing
- [ ] Memory usage stable
- [ ] No NPC state corruption
- [ ] Save/load preserves NPC state

---

## Known Issues & Edge Cases

### Edge Cases to Test

| Case | Description | Expected Handling |
|------|-------------|-------------------|
| Rapid trust changes | Trust goes from 0 to 100 instantly | Secrets unlock, no crash |
| Multiple secrets same threshold | Two secrets at same unlock level | Both reveal appropriately |
| NPC killed mid-conversation | NPC dies during dialogue | Conversation ends gracefully |
| Negative trust | Trust drops below 0 | Clamped to 0, hostile behavior |
| Missing memory system | RAG unavailable | Graceful fallback, no crash |

### Known Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| LLM context window | Long conversations may lose early context | Summarization in RAG |
| Hallucination risk | NPCs may invent facts | Strong personality anchors |
| Response latency | API calls take time | Loading indicators |

---

## Regression Tests

### After Any NPC Change

- [ ] NPC loads without errors
- [ ] Basic dialogue works
- [ ] Personality traits reflected in responses
- [ ] Secrets don't reveal prematurely
- [ ] Memory system integration works

### After Story Changes

- [ ] Timeline consistency maintained
- [ ] Cross-references still valid
- [ ] No contradictory information in personalities

---

## Test Data Templates

### Trust Level Quick Reference

```
0-29:   Stranger - Minimal information, guarded
30-49:  Acquaintance - Basic personal details
50-69:  Friend - Hints at secrets, tests discretion
70-84:  Trusted - Major secrets, asks for help
85-100: Confidant - Full disclosure, deep connection
```

### Event Memory Template

```gdscript
{
    "text": "[Description of what happened]",
    "event_type": "[betrayal_discovered|secret_revealed|confrontation|accusation]",
    "about_npc": "[npc_id if relevant]",
    "importance": [1-10],
    "emotion": "[horror|anger|sadness|relief|etc]",
    "timestamp": [unix_timestamp]
}
```

---

*This document should be updated as tests are executed and new test cases are identified.*
