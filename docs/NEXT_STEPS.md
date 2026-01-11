# Next Steps - Land JRPG Project

## 🎮 Project Successfully Initialized!

Your Godot 4 project structure is ready with all core architectural components.

## ✅ What's Been Set Up

1. **Godot 4.5.1** - Installed and ready
2. **Project Structure** - All directories created following architecture guidelines
3. **Core Autoload Singletons**:
   - `EventBus` - Central event system
   - `WorldState` - Global state management
   - `DialogueManager` - Conversation orchestration
   - `Config` - API key and settings management
4. **Configuration Files**:
   - `project.godot` - Godot project configuration
   - `.env` - API keys (needs your Claude key)
   - `.gitignore` - Protects secrets and generated files

## 🚀 Immediate Next Steps

### 1. Add Your Claude API Key
```bash
# Edit .env file and replace placeholder:
code .env  # or use any text editor

# Add your actual Claude API key:
CLAUDE_API_KEY=sk-ant-api03-xxxxx
```

### 2. Install and Start ChromaDB
```bash
# Install ChromaDB
pip install chromadb

# Start the server (keep this running in a terminal)
chroma run --host localhost --port 8000
```

### 3. Open Project in Godot
```bash
# From project directory
godot project.godot

# Or use Godot's project manager to import this folder
```

## 📋 Implementation Roadmap

Based on `.github/copilot-instructions.md`, here's the suggested build order:

### Phase 1: Core AI Integration (Start Here)
1. **ClaudeClient** (`scripts/dialogue/claude_client.gd`)
   - HTTP requests to Claude API
   - Error handling and retry logic
   - Token usage tracking

2. **ChromaClient** (`scripts/memory/chroma_client.gd`)
   - HTTP communication with ChromaDB
   - Memory storage/retrieval interface

3. **RAGMemory** (`scripts/npcs/rag_memory.gd`)
   - Wrapper for ChromaDB operations
   - Memory importance scoring
   - Semantic retrieval logic

### Phase 2: NPC Foundation
4. **BaseNPC** (`scripts/npcs/base_npc.gd`)
   - System prompt loading
   - RAG memory integration
   - Conversation state management

5. **ContextBuilder** (`scripts/dialogue/context_builder.gd`)
   - Assemble system prompt + RAG + world state
   - Format for Claude API

6. **First NPC Personality Resource**
   - Create `resources/npc_profiles/test_npc.tres`
   - Write detailed system prompt (use guide in copilot-instructions)

### Phase 3: World Systems
7. **ConsequenceGraph** (`scripts/world_state/consequence_graph.gd`)
   - Track player action → world change chains
   - Delayed consequence scheduling

8. **FactionReputation** (`scripts/world_state/faction_reputation.gd`)
   - Relationship matrices
   - Reputation threshold triggers

### Phase 4: Testing & Debug Tools
9. **AI Scenario Tester** (`scripts/debug/ai_scenario_tester.gd`)
10. **NPC Memory Inspector** (`scripts/debug/npc_debugger.gd`)

## 🧪 Testing Your Setup

Once you have Claude API key and ChromaDB running:

1. Open Godot project
2. Create a simple test scene with player and NPC
3. Test conversation flow: Player input → Context builder → Claude → Response
4. Verify memory storage in ChromaDB

## 📚 Key Documentation

- **Architecture**: `.github/copilot-instructions.md` (comprehensive guide for AI agents)
- **README**: `README.md` (quick start and overview)
- **System Prompts**: See "Writing Effective NPC System Prompts" section in copilot-instructions.md

## 💡 Development Tips

1. **Use Hot Reload**: Save GDScript files while game is running to see changes instantly
2. **Start Small**: Build one NPC with simple conversation before expanding
3. **Test Memory**: Use ChromaDB's web UI to inspect stored memories
4. **Monitor Costs**: Claude API usage is pay-per-token, test with short conversations first
5. **Ask AI Agents**: Your copilot-instructions.md is designed to guide AI coding assistants - leverage them!

## 🐛 Troubleshooting

**Godot won't open project?**
- Check that `project.godot` exists
- Ensure Godot version is 4.x

**ChromaDB connection fails?**
- Verify ChromaDB is running: `curl http://localhost:8000/api/v1/heartbeat`
- Check CHROMA_URL in `.env` matches server address

**Claude API errors?**
- Verify API key in `.env` is correct
- Check network connectivity
- Review Claude API rate limits

## 🎯 Your First Goal

Create a single working NPC conversation:
1. Implement ClaudeClient
2. Implement basic RAGMemory
3. Create BaseNPC script
4. Design one test NPC personality
5. Build simple scene to chat with NPC
6. Verify conversation works and memories are stored

Once this works, you have the foundation to build the entire dynamic world system!

---

**Need help?** Reference `.github/copilot-instructions.md` - it's designed to guide both you and AI coding assistants through this architecture.
