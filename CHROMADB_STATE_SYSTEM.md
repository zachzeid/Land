# ChromaDB State Persistence System

## Overview
All NPC state (life/death, relationships) is stored in ChromaDB alongside memories. This creates a unified source of truth for NPC data that persists across game sessions.

## What's Stored in ChromaDB

### 1. NPC Life/Death State
```gdscript
# Stored as special "npc_state" memory
{
  "text": "I died. Killed by: player. Cause: sword wound.",
  "event_type": "npc_state",
  "is_alive": false,
  "death_cause": "sword wound",
  "killed_by": "player",
  "death_timestamp": 1764963830.0
}
```

### 2. NPC-to-NPC/Faction Relationships
```gdscript
# Elena's relationship with player after dad (Gregor) dies
{
  "text": "My relationship with player: Trust=-80, Respect=-90, Affection=-100",
  "event_type": "relationship_state",
  "with_entity": "player",
  "trust": -80,
  "respect": -90,
  "affection": -100,
  "fear": 30,
  "familiarity": 50
}
```

### 3. Regular Memories
All conversation history, witnessed events, quests, etc. (already working)

## How It Works

### On Game Start
1. NPC initializes RAG memory
2. Queries ChromaDB for `get_npc_state()`
3. If dead → hide NPC, disable processing
4. If alive → load normally

### On NPC Death
1. Call `npc.die("sword wound", "player")`
2. Stores state in ChromaDB: `rag_memory.store_npc_state(false, death_data)`
3. Hides NPC visually (`visible = false`)
4. Death persists forever in ChromaDB

### Cross-NPC Reactions
```gdscript
# When Gregor dies, update Elena's relationship with player
var elena = get_node("Elena")
await elena.rag_memory.store_relationship("player", {
  "trust": -80,
  "respect": -90,
  "affection": -100,  # She hates you now
  "fear": 30,
  "note": "You killed my father"
})

# Elena will remember this and act hostile when you talk to her
```

## API Reference

### RAGMemory Methods

#### `store_npc_state(is_alive: bool, death_data: Dictionary) -> bool`
Store NPC's alive/dead state
```gdscript
await rag_memory.store_npc_state(false, {
  "cause": "sword wound",
  "killed_by": "player",
  "timestamp": Time.get_unix_time_from_system()
})
```

#### `get_npc_state() -> Dictionary`
Retrieve NPC's current state
```gdscript
var state = await rag_memory.get_npc_state()
if not state.is_alive:
  print("NPC is dead: %s" % state.death_cause)
```

#### `store_relationship(with_entity: String, relationship_data: Dictionary) -> bool`
Store relationship with another NPC/faction
```gdscript
await rag_memory.store_relationship("player", {
  "trust": 50,
  "respect": 70,
  "affection": 30,
  "fear": 0,
  "familiarity": 80
})
```

#### `get_relationship(with_entity: String) -> Dictionary`
Retrieve relationship state
```gdscript
var rel = await rag_memory.get_relationship("player")
print("Trust: %d" % rel.trust)
```

### BaseNPC Methods

#### `die(cause: String, killer: String)`
Kill the NPC permanently
```gdscript
npc.die("sword wound", "player")
npc.die("dragon fire", "ancient_dragon")
npc.die("poison", "assassin_guild")
```

#### `can_interact() -> bool`
Check if NPC is alive
```gdscript
if npc.can_interact():
  npc.start_conversation()
```

## Example Use Cases

### 1. Player Kills Gregor
```gdscript
# Gregor dies
gregor.die("sword wound", "player")

# Elena finds out (you'd need to implement news spreading)
var elena = get_node("Elena")
await elena.rag_memory.store({
  "text": "I heard the player killed my father Gregor. I will never forgive them.",
  "event_type": "witnessed_crime",
  "importance": 10,
  "emotion": "grief_rage"
})

# Update Elena's relationship
await elena.rag_memory.store_relationship("player", {
  "trust": -100,
  "respect": -100,
  "affection": -100,
  "fear": 20,
  "familiarity": 100
})

# Now when you talk to Elena, she'll hate you
```

### 2. Faction War
```gdscript
# Player attacks village guard
guard.die("sword wound", "player")

# All village NPCs update relationship
for npc in village_npcs:
  await npc.rag_memory.store_relationship("player", {
    "trust": -60,
    "respect": -40,
    "affection": -50,
    "fear": 30
  })
  
  await npc.rag_memory.store({
    "text": "The player killed our guard. They are an enemy of the village.",
    "importance": 9,
    "event_type": "faction_conflict"
  })
```

### 3. NPC Revival (Resurrection Spell)
```gdscript
# Restore NPC to life
await npc.rag_memory.store_npc_state(true, {})
npc.is_alive = true
npc.visible = true
npc.process_mode = Node.PROCESS_MODE_INHERIT

# Store memory of resurrection
await npc.rag_memory.store({
  "text": "I was brought back from death. The player saved me.",
  "importance": 10,
  "event_type": "resurrection"
})
```

## Advantages Over WorldState JSON

✅ **Single Source of Truth**: All NPC data in ChromaDB  
✅ **Semantic Queries**: Can search "who did the player kill?"  
✅ **Cross-NPC Awareness**: NPCs can query other NPCs' deaths/relationships  
✅ **Rich Context**: Death is a memory with full context, not just a flag  
✅ **AI Integration**: Claude can reference death events naturally  
✅ **No Sync Issues**: Memories and state always consistent  

## Future Enhancements

- **News Spreading System**: NPCs gossip about deaths/crimes
- **Faction Reputation**: Track relationships at faction level
- **Revenge Quests**: Elena seeks revenge for Gregor's death
- **Memorial Events**: Village holds funeral for dead NPCs
- **Guilt System**: Player haunted by victims' memories
