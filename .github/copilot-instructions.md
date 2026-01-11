# Land - AI-Driven Open-World JRPG

An open-world JRPG (inspired by Fable) where player choices dynamically affect the world and NPCs. Built with Godot 4, featuring AI-powered NPCs that remember interactions and respond to player decisions.

## Tech Stack

- **Engine**: Godot 4.x with GDScript
- **AI/Dialogue**: Claude API (Anthropic) for dynamic NPC conversations - each NPC is an independent AI agent
- **Memory/RAG**: ChromaDB (local vector database) for NPC memory storage and semantic retrieval
- **Save System**: Godot's built-in ConfigFile/JSON serialization for world state persistence
- **Architecture**: Event-driven world state with persistent consequence tracking

## Project Structure

```
/
├── scenes/          # Godot scene files (.tscn)
├── scripts/         # GDScript files
│   ├── world_state/ # Event bus, consequence graph, faction system
│   ├── npcs/        # NPC AI, memory, personality, behavior
│   ├── dialogue/    # Dialogue manager, LLM integration, context builder
│   ├── memory/      # ChromaDB client, RAG retrieval logic
│   └── events/      # Player action events, world event handlers
├── resources/       # Godot resources (.tres) - NPC profiles, quest data
├── addons/          # Third-party Godot plugins
└── chroma_data/     # ChromaDB persistent storage (gitignored)
```

## Core Architecture

### World State System
- **EventBus** (`scripts/world_state/event_bus.gd`): Central singleton for all game events. Player actions emit signals consumed by world state managers.
- **ConsequenceGraph** (`scripts/world_state/consequence_graph.gd`): Tracks causal chains of player actions → world changes. Supports delayed consequences and probability branches.
- **FactionReputation** (`scripts/world_state/faction_reputation.gd`): Manages relationship matrices between player and factions/NPCs. Changes trigger narrative events at thresholds.

Example event emission pattern:
```gdscript
EventBus.emit_signal("player_action", {
    "type": "dialogue_choice",
    "npc_id": npc.id,
    "choice": selected_option,
    "timestamp": Time.get_unix_time_from_system()
})
```

### NPC AI Architecture
**Each NPC is an independent AI agent** with Claude-powered decision-making:

1. **System Prompt (Personality)**: Defines character traits, motivations, fears, speech patterns - stored in `resources/npc_profiles/*.tres`
2. **RAG Memory System**: Vector database of NPC's experiences, player interactions, witnessed events - retrieved contextually for each conversation
3. **Perception Layer**: Real-time awareness of nearby entities, current world state, active events
4. **Dialogue Generation**: System prompt + RAG context + current situation → Claude API → character-consistent response

NPC scripts inherit from `BaseNPC` (`scripts/npcs/base_npc.gd`) which provides:
- System prompt loading from personality resource
- RAG memory storage/retrieval interface
- Claude API integration with context assembly
- Conversation state management

### Choice & Consequence Pipeline
1. Player performs action → Event emitted to EventBus
2. ConsequenceGraph evaluates action against world state rules
3. Immediate effects applied (reputation change, NPC reactions)
4. Delayed consequences scheduled (quest triggers, world changes)
5. NPC memories updated with player action + context

### How World Events Become NPC Memories

**Player Action Example:**
```gdscript
# Player helps NPC with quest
EventBus.emit_signal("player_action", {
    "type": "quest_completed",
    "quest_id": "find_lost_sword",
    "npc_id": "aldric_blacksmith",
    "outcome": "success"
})

# This generates memory for Aldric:
npc.rag_memory.store({
    "document": "The player found my stolen sword in the bandit camp. They risked their life to help me. I'm grateful and impressed by their courage.",
    "metadata": {
        "event_type": "quest_completed",
        "importance": 8,
        "emotion": "grateful",
        "timestamp": Time.get_unix_time_from_system()
    }
})
```

**NPC Witnessing Event:**
```gdscript
# Player steals from shop while NPC watches
if npc.can_see(player) and player.is_stealing:
    npc.rag_memory.store({
        "document": "I saw the player stealing from the merchant's stall. They looked around nervously before pocketing the item. I don't trust thieves.",
        "metadata": {
            "event_type": "witnessed_crime",
            "importance": 9,
            "emotion": "disapproval",
            "participants": ["player"],
            "location": current_scene
        }
    })
```

**Conversation Memory:**
```gdscript
# After dialogue turn completes
npc.rag_memory.store({
    "document": "Player asked about the rebellion. I deflected - I don't trust them enough yet to discuss politics. They seemed curious but didn't press.",
    "metadata": {
        "event_type": "conversation",
        "importance": 6,
        "emotion": "cautious",
        "topics": ["rebellion", "politics"]
    }
})
```

**World State Change:**
```gdscript
# Village comes under attack
EventBus.emit_signal("world_event", {
    "type": "faction_attack",
    "location": "thornhaven_village",
    "attacker": "bandit_clan"
})

# All NPCs in village store memory:
for npc in village_npcs:
    npc.rag_memory.store({
        "document": "Bandits attacked the village today. I heard screams and saw smoke. The player %s during the attack." % ("fought bravely" if player_helped else "was nowhere to be found"),
        "metadata": {
            "event_type": "village_attack",
            "importance": 10,
            "emotion": "fearful" if not player_helped else "relieved"
        }
    })
```

**Memory Importance Scoring Guidelines:**
- **1-3**: Trivial (weather comments, casual greetings)
- **4-6**: Notable (normal conversations, minor favors)
- **7-8**: Significant (quest help, witnessed crimes, emotional moments)
- **9-10**: Life-changing (saves NPC's life, betrayals, major reveals)

### Dialogue System
- **DialogueManager** (`scripts/dialogue/dialogue_manager.gd`): Orchestrates conversations, manages turn-taking
- **ClaudeClient** (`scripts/dialogue/claude_client.gd`): Handles Claude API calls with retry logic, rate limiting, context window management
- **RAGMemory** (`scripts/npcs/rag_memory.gd`): Vector-based memory retrieval - queries NPC's experience database for relevant context
- **ContextBuilder** (`scripts/dialogue/context_builder.gd`): Assembles system prompt + RAG results + current state into Claude messages

Claude message format:
```gdscript
var messages = [
    {"role": "system", "content": npc.personality_resource.system_prompt},
    {"role": "user", "content": context_builder.build_context({
        "rag_memories": npc.rag_memory.retrieve_relevant(current_situation, limit=5),
        "relationship": FactionReputation.get_npc_relationship(npc.id),
        "world_state": WorldState.get_relevant_state(npc.id),
        "player_message": player_input
    })}
]
```

## Development Workflows

### Running the Game
```bash
# Launch Godot editor
godot4 --editor project.godot

# Run from command line (for testing)
godot4 --path . scenes/main.tscn
```

### Testing NPC AI
- Use `scripts/debug/ai_scenario_tester.gd` to run NPCs through predefined scenarios
- Debug visualizer: Enable "Show AI State" in Debug menu to see utility scores, active goals
- Conversation replay: `DialogueManager.replay_conversation(npc_id, conversation_id)` for testing dialogue flows

### World State Debugging
- Timeline visualizer: `WorldState.debug_show_timeline()` displays causal event chains
- State inspection: `WorldState.query("faction.reputation > 50")` for complex queries
- Save diff tool: `SaveManager.compare_states(save_a, save_b)` shows changes between snapshots
- RAG memory inspector: `NPCDebugger.show_rag_memories(npc_id)` displays what NPC remembers about player/events

### Hot Reload
Godot supports hot-reload for GDScript. To iterate on dialogue/AI:
1. Modify script while game is running
2. Save file (Ctrl/Cmd+S)
3. Changes apply immediately without restart

## Key Patterns & Conventions

- **Signals over polling**: Use Godot signals for event propagation (not `_process` loops checking state)
- **Resources for data**: NPC personalities, quest templates, dialogue trees → `.tres` files, not hardcoded
- **Autoload singletons**: `EventBus`, `WorldState`, `DialogueManager` are autoloaded (Project Settings → Autoload)
- **Scene composition**: NPCs are scenes with attached behavior scripts, not monolithic scripts
- **API key management**: Store Claude API key in `.env` file (gitignored), load via `scripts/core/config.gd`
- **State serialization**: Use Godot's `ConfigFile` or `JSON.stringify()` for saves - all world state classes implement `save()` and `load()` methods returning/accepting dictionaries
- **NPC agents as independent entities**: Each NPC maintains own Claude conversation thread, RAG memory store, and personality profile

## Claude Integration Best Practices

- **System prompts**: Each NPC's personality lives in system prompt - make them rich and character-specific (voice, motivations, secrets, speech patterns)
- **RAG retrieval**: Query vector DB for top 5-10 relevant memories per turn - balance recency with relevance
- **Context window**: Claude has 200k tokens but keep prompts <3000 tokens for cost/speed - use RAG to surface only relevant history
- **Fallback responses**: Always have template-based dialogue if Claude API fails (network issues, rate limits)
- **Cost tracking**: Log token usage per conversation - Claude pricing is per-token (input + output)
- **Prompt caching**: Use Claude's prompt caching for system prompts to reduce costs on repeated NPC interactions

## RAG Memory Implementation (ChromaDB)

### Architecture
- **ChromaDB server**: Runs locally as HTTP service (`http://localhost:8000`)
- **Collections**: One collection per NPC (e.g., `npc_merchant_001_memories`)
- **Embeddings**: Use Claude's embedding capability or Voyage AI for cost-efficiency
- **Integration**: GDScript HTTPRequest node communicates with ChromaDB REST API

### Memory Storage Format
```gdscript
# When storing a memory in ChromaDB
var memory = {
    "id": generate_unique_id(),  # timestamp + event type
    "document": "Player asked about the stolen sword. I told them I saw suspicious figures near the blacksmith.",
    "metadata": {
        "timestamp": Time.get_unix_time_from_system(),
        "event_type": "conversation",
        "participants": ["player", npc.id],
        "location": current_scene,
        "emotion": "concerned",
        "importance": 7  # 1-10 scale for memory prioritization
    }
}
```

### Memory Retrieval
```gdscript
# Query relevant memories from ChromaDB
func retrieve_relevant_memories(npc_id: String, query: String, limit: int = 5) -> Array:
    var response = await chroma_client.query({
        "collection_name": "npc_%s_memories" % npc_id,
        "query_texts": [query],
        "n_results": limit,
        "where": {"importance": {"$gte": 5}}  # Filter low-importance memories
    })
    return response.documents
```

### ChromaDB Setup
```bash
# Install ChromaDB (Python)
pip install chromadb

# Run ChromaDB server locally
chroma run --host localhost --port 8000

# Or use Docker
docker run -p 8000:8000 chromadb/chroma
```

### GDScript Integration Pattern
- Create `scripts/memory/chroma_client.gd` singleton for HTTP communication
- Use `HTTPRequest` node to make REST API calls to ChromaDB
- Implement async/await pattern for memory retrieval during dialogue
- Cache frequently accessed memories in Godot for performance

## Writing Effective NPC System Prompts

System prompts define NPC personality and should be stored in `resources/npc_profiles/*.tres` files. Each prompt creates a consistent character AI agent.

### Essential Components

**1. Core Identity**
```
You are Aldric, a 45-year-old blacksmith in the village of Thornhaven. You've lived here your entire life and take pride in your craft.
```

**2. Personality Traits (3-5 key traits)**
```
- Gruff but kind-hearted - you act tough but help those in need
- Suspicious of outsiders initially, but warm up if they prove trustworthy
- Deeply loyal to friends and family
- Stubborn about your opinions on metalwork
```

**3. Speech Patterns**
```
You speak in short, direct sentences. You often use blacksmithing metaphors ("That plan needs more tempering" or "You're forging ahead without thinking"). You rarely use flowery language.
```

**4. Motivations & Goals**
```
- Protect your daughter Elena from getting involved with the rebellion
- Maintain your reputation as the best blacksmith in the region
- Discover who's been stealing iron from your workshop
```

**5. Secrets & Knowledge**
```
SECRET (don't reveal easily): You once forged weapons for the rebellion's enemies. You feel guilty about this.
KNOWS: The location of a hidden cache of rare metals in the nearby mine.
DOESN'T KNOW: That Elena is secretly dating a rebel.
```

**6. Relationships**
```
- Elena (daughter): Overprotective, would do anything for her
- Player: Initially wary, opinion changes based on their actions and reputation
- Lord Castor: Dislikes but fears him due to past debts
```

**7. Behavioral Guidelines**
```
- Don't give away your secret about the rebellion unless player has earned deep trust (reputation > 75)
- React negatively if player mentions rebellion around you
- Become more talkative and friendly when discussing blacksmithing techniques
- Reference past conversations - if player helped you before, acknowledge it warmly
```

### Example Complete System Prompt
```
You are Aldric, a 45-year-old blacksmith in Thornhaven village. You are gruff but kind-hearted, suspicious of outsiders initially but loyal to friends. You speak in short, direct sentences and often use blacksmithing metaphors.

Your main goals are protecting your daughter Elena and maintaining your reputation as the region's best blacksmith. Someone has been stealing iron from your workshop, and you're determined to find out who.

SECRET: You once forged weapons for those who fought against the rebellion. You feel deep guilt about this and will only reveal it to someone you truly trust.

You know about a hidden cache of rare metals in the nearby mine, but you don't know that Elena is secretly involved with the rebels.

When interacting with the player:
- Start wary and reserved. Your trust must be earned through actions, not words.
- Warm up significantly when discussing blacksmithing - it's your passion.
- React negatively to mentions of rebellion or politics.
- If the player has helped you before, acknowledge it and show gratitude.
- Never reveal your secret unless you deeply trust them (they've proven themselves multiple times).

Relationships:
- Elena (daughter): You're overprotective and would sacrifice anything for her safety.
- Lord Castor: You dislike him but fear him due to old debts you owe.

Remember past interactions through your memories. Stay consistent with your personality and let your opinion of the player evolve based on their choices and actions toward you and Thornhaven.
```

### Best Practices for System Prompts
- **Be specific**: "Gruff but kind" is better than "complex personality"
- **Include contradictions**: Real characters have internal conflicts
- **Define boundaries**: Clearly state what NPC won't do or reveal easily
- **Reference memory system**: Remind Claude to consider retrieved RAG memories
- **Allow evolution**: Let NPC opinion change based on player actions
- **Use examples**: Show speech patterns with example phrases or metaphors

## File Naming Conventions

- Scripts: `snake_case.gd` (e.g., `npc_memory.gd`)
- Scenes: `PascalCase.tscn` (e.g., `VillageNPC.tscn`)
- Resources: `snake_case.tres` (e.g., `merchant_personality.tres`)
- Constants: `UPPER_SNAKE_CASE` in GDScript

## Getting Started

1. Create core autoload singletons (`event_bus.gd`, `world_state.gd`, `dialogue_manager.gd`)
2. Set up Claude API key configuration in `scripts/core/config.gd` (load from `.env`)
3. Implement `ClaudeClient` (`scripts/dialogue/claude_client.gd`) with basic API calls and error handling
4. Build `RAGMemory` system (`scripts/npcs/rag_memory.gd`) for storing/retrieving NPC experiences
5. Create `BaseNPC` class with system prompt loading, RAG integration, and conversation state
6. Design first NPC personality resource with detailed system prompt (character traits, background, goals)
7. Build test scene with simple player-NPC conversation using Claude API

## Implementation Status

### ✅ Completed Components (5/5 - First Milestone Complete!)

**ClaudeClient** (`scripts/dialogue/claude_client.gd`)
- Full Claude 3.5 Sonnet integration
- Prompt injection detection and mitigation (wraps suspicious input)
- Rate limiting (500ms between requests)
- Token tracking and cost calculation
- Error handling with fallback messages
- Manual API key override for testing: `client.api_key_override = "sk-ant-..."`

**ChromaClient** (`scripts/memory/chroma_client.gd`)
- ChromaDB v2 API integration
- Collection management (create, get, delete)
- Memory storage with metadata (event_type, importance, emotion, timestamp)
- Semantic similarity search (query by meaning, not keywords)
- Importance-based filtering
- Connection health checks
- Requires ChromaDB server: `chroma run --host localhost --port 8000`

**RAGMemory** (`scripts/npcs/rag_memory.gd`)
- High-level NPC memory interface wrapping ChromaClient
- Store memories from NPC's perspective with `store()`
- Retrieve relevant memories semantically with `retrieve_relevant()`
- Helper methods: `store_conversation()`, `store_witnessed_event()`, `store_quest_memory()`
- Importance-based filtering and recent memory access
- Per-NPC collection management

**ContextBuilder** (`scripts/dialogue/context_builder.gd`)
- Assembles complete context for Claude API from NPC state
- System prompt enhancement with RAG memories, relationship status, world state
- Relationship-aware descriptions (Hostile → Trusted friend scale)
- Message history formatting for Claude API
- Token estimation and trimming (~4 chars per token)
- Helper methods: `build_greeting_context()`, `build_reaction_context()`
- All tests passing

**BaseNPC** (`scripts/npcs/base_npc.gd`) ✅ **Just Completed!**
- Foundation class for all AI-driven NPCs
- Integrates all AI components: RAGMemory + ContextBuilder + ClaudeClient
- Personality loading from system prompt (inline or from .tres resource)
- Conversation management: `start_conversation()`, `respond_to_player()`, `end_conversation()`
- Relationship tracking with automatic memory storage on significant changes
- Witness event system for reacting to world events
- Signals: `dialogue_started`, `dialogue_response_ready`, `dialogue_ended`
- All tests passing (component integration verified)

**Config System** (`scripts/core/config.gd`)
- Loads API keys from `.env` file (gitignored)
- Supports quotes in environment variables
- Autoload singleton accessible throughout project

**Test Infrastructure**
- `scripts/debug/quick_test.gd` - Unit tests for ClaudeClient sanitization
- `scripts/debug/test_api_call.gd` - Live Claude API integration test
- `scripts/debug/test_chroma_client.gd` - ChromaDB integration test
- `scripts/debug/test_rag_memory.gd` - RAGMemory wrapper test
- `scripts/debug/test_context_builder.gd` - Context assembly test (all passing)
- `scripts/debug/test_base_npc.gd` - BaseNPC component integration test (all passing)
- Run tests: `godot -s scripts/debug/[test_file].gd`

### 🎯 Completed - Ready for Live Testing!

**All core components implemented and tested:**

1. ✅ **ClaudeClient** - API integration with prompt injection protection
2. ✅ **ChromaClient** - ChromaDB vector database integration  
3. ✅ **RAGMemory** - NPC memory storage/retrieval
4. ✅ **ContextBuilder** - Context assembly for Claude
5. ✅ **BaseNPC** - Foundation class with all AI components integrated
6. ✅ **Test Conversation Scene** - Standalone UI for testing NPC dialogue
7. ✅ **Game World Scene** - Player movement + NPC interaction + dialogue UI

**Created Scenes:**
- `scenes/test_conversation.tscn` - Debug UI for testing NPCs without game context
- `scenes/game_world.tscn` - Playable demo with player movement and NPC interaction
- `scenes/player/player.tscn` - Simple player controller (WASD movement)
- `scenes/npcs/gregor_merchant.tscn` - First AI-driven NPC

**How to Test:**

1. **Start ChromaDB server**: `chroma run --host localhost --port 8000`
2. **Add Claude API credits**: Visit https://console.anthropic.com/settings/plans
3. **Run game world**: Press F6 or open `scenes/game_world.tscn` and click Play
4. **Walk to NPC**: Use arrow keys or WASD to move player near Gregor
5. **Start conversation**: Press E or Enter when "[E] Talk" appears
6. **Chat with Gregor**: Type messages and press Send/Enter

**What Works:**
- ✅ Player can walk around with WASD/arrows
- ✅ Approach Gregor to see interaction prompt
- ✅ Press E to start AI-powered conversation
- ✅ Gregor responds with Claude 3 Haiku (fast, personality-driven)
- ✅ Conversation history maintained during session
- ✅ Dialogue pauses game and shows overlay UI
- ✅ End conversation button returns to gameplay
- ⚠️ RAG memory temporarily disabled (ChromaDB query hangs - needs investigation)

**Known Issues:**
1. ChromaDB semantic memory retrieval hangs on query - temporarily disabled
   - NPCs don't remember conversations between sessions
   - Fix needed: Investigate ChromaDB v2 API query implementation
2. Dialogue started signal emits twice on conversation start (minor)

**Next Development Tasks:**

**Next Development Tasks:**

1. **Implement Quest System**
   - Quest data structure (objectives, rewards, dependencies)
   - QuestManager singleton for tracking active/completed quests
   - Quest triggers from NPC dialogue choices
   - Quest completion detection

2. **Expand World State**
   - Implement ConsequenceGraph for tracking player action chains
   - FactionReputation system for village/bandit relationships
   - World event system (attacks, festivals, NPC schedule changes)
   - Persistent save/load for world state

3. **Enhance NPC AI**
   - Roaming behavior (patrol routes, daily schedules)
   - NPC-to-NPC conversations (gossip system)
   - Dynamic quest generation based on world state
   - More personality profiles and NPC types

4. **Visual Polish**
   - Replace ColorRect placeholders with actual sprites
   - Add animations (walk, idle, talk)
   - Improve dialogue UI styling
   - Add sound effects and music

5. **Combat & Interaction**
   - Basic combat system
   - Inventory and item system
   - Trading with merchants
   - Pickpocketing/stealing mechanics (with consequences!)

6. **Fix ChromaDB RAG Memory**
   - Debug why query_memories hangs
   - Implement timeout/fallback for ChromaDB calls
   - Re-enable persistent NPC memory across sessions

## Development Workflows

### Running Tests
```bash
# Unit tests (sanitization, validation)
godot -s scripts/debug/quick_test.gd

# Claude API test (requires API key in .env)
godot -s scripts/debug/test_api_call.gd

# ChromaDB test (requires running server)
godot -s scripts/debug/test_chroma_client.gd
```

### Starting ChromaDB Server
```bash
# Install (first time only)
pip install chromadb

# Start server (keep running in background)
chroma run --host localhost --port 8000

# Verify connection
curl http://localhost:8000/api/v2/heartbeat
```

### Environment Setup
```bash
# Copy example
cp .env.example .env

# Edit .env and add keys (no quotes needed, but supported)
CLAUDE_API_KEY=sk-ant-api03-...
CHROMA_URL=http://localhost:8000
```
