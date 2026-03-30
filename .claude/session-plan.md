# Session Plan

**Created:** 2026-03-28
**Intent Contract:** See .claude/session-intent.md

## What You'll End Up With

A comprehensive systems audit and strategic expansion plan for Land's game architecture — covering all existing systems (NPC AI, memory, quests, world state, dialogue, physics), identifying gaps and refinement opportunities, and providing a prioritized roadmap for Phases 7-11 that fits the existing architecture.

## How We'll Get There

### Phase Weights
- **Discover: 45%** — Deep audit of all existing systems, cross-referencing code with docs, identifying undocumented state and gaps
- **Define: 20%** — Synthesize findings into clear problem statements, prioritize systems needing refinement vs expansion, establish constraints
- **Develop: 20%** — Draft concrete implementation strategies for each system area, with architecture proposals for upcoming phases
- **Deliver: 15%** — Validate plan against existing design principles, ensure internal consistency, produce shareable deliverable

### Detailed Phase Breakdown

#### DISCOVER (45%) — Systems Audit
Research and catalog the current state of every major system:

1. **NPC AI System** — Audit `scripts/npcs/` (17 files): base_npc, personality framework, behavior trees, relationship 5D model, secret unlocking, cross-NPC awareness
2. **Memory/RAG System** — Audit `scripts/memory/` + `chroma_bridge.py` + `chroma_cli.py`: storage tiers, ChromaDB integration, fallback modes, memory importance scoring
3. **Dialogue System** — Audit `scripts/dialogue/` (8 files): Claude client, context builder, intent detection, conversation state management
4. **World State System** — Audit `scripts/world_state/` (12 files): EventBus, WorldState, consequence graph, story flags, faction reputation
5. **Quest System** — Audit `scripts/quests/` (7 files): QuestManager, QuestResource, objectives, journal UI, notifications, context injection
6. **World/Physics** — Audit `scripts/world/` (38 files): collision layers, world objects, scene management, location system, interactables
7. **UI System** — Audit `scripts/ui/` (10 files): dialogue UI, quest journal, notifications, debug tools
8. **Scene Architecture** — Audit `scenes/`: game_world, interiors, NPC scenes, test scenes
9. **Asset Generation** — Audit `scripts/generation/` (33 files): Recraft integration, tileset generation, asset pipeline
10. **Cross-system Integration** — Map how systems communicate (EventBus signals, shared state, resource dependencies)

#### DEFINE (20%) — Problem Synthesis
- Gap analysis: what's documented but unimplemented?
- Refinement targets: what works but could be improved?
- Expansion requirements: what Phase 7-11 features need from existing systems?
- Architecture risks: where are the coupling points or scaling concerns?
- Priority matrix: effort vs impact for each identified item

#### DEVELOP (20%) — Strategy Drafting
- Per-system improvement proposals with code-level specifics
- Phase 7 (Combat) architecture that integrates with NPC AI + relationships
- Phase 8 (Inventory) architecture that connects to quests + evidence items
- Cross-cutting concerns: save/load, performance, testing strategy
- Dependency graph: what must be done before what?

#### DELIVER (15%) — Validation & Output
- Cross-reference against existing PLAN.md and DEVELOPMENT_PLAN.md
- Verify consistency with design principles (composability, data-driven, separation of concerns)
- Produce final strategic document
- Identify debate-worthy decision points for team alignment

### Execution Commands
To execute this plan, run:
```
/octo:embrace "Define, refine, and expand Land's game systems"
```

Or execute phases individually:
- `/octo:discover` — Systems audit (recommended first)
- `/octo:define` — Problem synthesis
- `/octo:develop` — Strategy drafting
- `/octo:deliver` — Validation & output

## Provider Requirements
🔴 Codex CLI: Available ✓
🟡 Gemini CLI: Available ✓
🟤 Copilot CLI: Available ✓
🟣 Perplexity: Not configured ✗
🔵 Claude: Available ✓

## Debate Checkpoints

🔸 **After Define phase:** "Are the identified gaps and priorities correct? What are we missing?"
   Triggers: 1-round adversarial debate on completeness and prioritization

🔸 **After Develop phase:** "Is the proposed Phase 7 (Combat) architecture the right approach?"
   Triggers: 1-round adversarial debate on architectural risks and alternatives

## Success Criteria
- [ ] Team alignment — clear, shareable understanding of system state and next steps
- [ ] Working solution — actionable implementation plan for system refinements
- [ ] Production-ready — plan accounts for testing, validation, and quality gates

## Next Steps
1. Review this plan
2. Adjust if needed (re-run /octo:plan)
3. Execute with /octo:embrace when ready
