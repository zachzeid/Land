# Land - AI-Driven Open-World JRPG

An open-world JRPG inspired by Fable where player choices dynamically shape the world. Built with Godot 4, featuring AI-powered NPCs with persistent memory and dynamic dialogue via Claude.

## Quick Start

1. **Install dependencies:**
   ```bash
   # Install ChromaDB for NPC memory
   pip install chromadb
   
   # Start ChromaDB server
   chroma run --host localhost --port 8000
   ```

2. **Configure API keys:**
   ```bash
   # Copy example env file
   cp .env.example .env
   
   # Edit .env and add your Claude API key
   ```

3. **Open in Godot:**
   ```bash
   godot project.godot
   ```

## Architecture

See `.github/copilot-instructions.md` for comprehensive architecture documentation, development workflows, and AI integration patterns.

## Project Structure

- `scenes/` - Godot scene files
- `scripts/` - GDScript code organized by feature
  - `world_state/` - Event bus, world state, consequence tracking
  - `npcs/` - NPC AI, memory, behavior
  - `dialogue/` - Claude integration, dialogue management
  - `memory/` - ChromaDB integration for RAG
- `resources/` - Godot resources (NPC profiles, quests)

## Core Systems

- **Event-Driven World State** - Player actions flow through EventBus singleton
- **AI-Powered NPCs** - Each NPC is an independent Claude AI agent with unique personality
- **RAG Memory System** - ChromaDB stores and retrieves NPC experiences semantically
- **Consequence Graph** - Tracks causal chains of player choices → world changes

## Development

- **Hot Reload** - Save GDScript files while running to see changes instantly
- **Debug Tools** - Use Debug menu for AI state visualization, world state timeline
- **Testing** - Run scenarios via `scripts/debug/ai_scenario_tester.gd`

## License

MIT
