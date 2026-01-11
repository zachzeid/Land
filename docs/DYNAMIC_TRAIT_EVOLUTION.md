# 🧬 Dynamic Trait Evolution via ChromaDB Integration

## Core Concept: Traits as Emergent Properties

Instead of manually updating fixed traits, **NPCs develop traits dynamically** by analyzing their ChromaDB interaction memories and injecting trait summaries into Claude prompts.

---

## Architecture Overview

```
Player Action
    ↓
BaseNPC.record_interaction()
    ↓
RAGMemory.store() → ChromaDB
    ↓
[Time passes, more interactions stored]
    ↓
Conversation starts
    ↓
BaseNPC.respond_to_player()
    ↓
RAGMemory.analyze_personality_evolution() ← Query ChromaDB
    ↓
Extract emerging traits from interaction patterns
    ↓
ContextBuilder.build_context()
    ↓
Inject dynamic traits into system prompt
    ↓
Claude generates response using evolved personality
```

---

## Implementation: Three-Layer System

### Layer 1: Base Personality (Static)
Defined in NPC personality resource - never changes.

```gdscript
# gregor_merchant.tres
{
    "base_personality": "You are Gregor, a 45-year-old blacksmith...",
    "core_traits": [
        "Professional merchant",
        "Protective of daughter Elena", 
        "Values honesty in business"
    ],
    "speech_style": "Direct, uses blacksmithing metaphors"
}
```

**Purpose:** Establishes consistent character identity that doesn't shift based on player actions.

---

### Layer 2: Evolved Traits (Dynamic)
Generated from ChromaDB interaction analysis - updates based on accumulated experiences.

```gdscript
# Calculated at conversation start from ChromaDB memories
func analyze_personality_evolution(npc_id: String) -> Dictionary:
    """
    Query ChromaDB for all interactions, analyze patterns,
    extract emergent personality traits.
    
    Returns: {
        "evolved_traits": Array[String],
        "emotional_state": String,
        "relationship_summary": String,
        "behavioral_shifts": Array[String]
    }
    """
```

**Example Output:**

After player helps with bandit quest and gives thoughtful gifts:
```gdscript
{
    "evolved_traits": [
        "Growing protective of the player (helped multiple times)",
        "More open and warm than usual (trust built through consistency)",
        "Conflicted about developing feelings (notices player's kindness)"
    ],
    "emotional_state": "Grateful but cautious about vulnerability",
    "relationship_summary": "Sees player as reliable ally, possibly more",
    "behavioral_shifts": [
        "Drops professional tone when alone with player",
        "Shares personal concerns about Elena more freely",
        "Offers discounts and insider information unprompted"
    ]
}
```

**Purpose:** Shows how NPC has changed without altering base character.

---

### Layer 3: Contextual State (Ephemeral)
Current emotional state and recent events - refreshes each conversation.

```gdscript
{
    "current_emotion": "anxious",  # Elena is missing
    "recent_events": ["Village attack yesterday", "Lost shipment"],
    "active_concerns": ["Elena's safety", "Business suffering"]
}
```

**Purpose:** Provides immediate context that affects this specific conversation.

---

## ChromaDB Integration: Trait Analysis Queries

### Query 1: Extract Relationship Patterns

```gdscript
# In rag_memory.gd
func analyze_relationship_evolution(npc_id: String) -> Dictionary:
    """
    Analyzes all interactions to identify relationship trajectory.
    """
    
    # Query all memories sorted by timestamp
    var all_memories = chroma_client.query_memories(
        "npc_%s_memories" % npc_id,
        "",  # No query text, get all
        n_results=100,
        where={}  # No filter
    )
    
    if all_memories.size() == 0:
        return {
            "trajectory": "new_acquaintance",
            "trust_pattern": "unknown",
            "emotional_pattern": "neutral"
        }
    
    # Analyze metadata patterns
    var positive_interactions = 0
    var negative_interactions = 0
    var trust_moments = []
    var emotional_moments = []
    
    for mem in all_memories:
        var metadata = mem.get("metadata", {})
        var emotion = metadata.get("emotion", "neutral")
        var event_type = metadata.get("event_type", "")
        
        # Count positive vs negative
        if emotion in ["grateful", "happy", "pleased", "warm", "hopeful"]:
            positive_interactions += 1
            emotional_moments.append(mem.document)
        elif emotion in ["angry", "disappointed", "hurt", "fearful"]:
            negative_interactions += 1
        
        # Track trust-building moments
        if event_type in ["quest_completed", "helped", "promise_kept"]:
            trust_moments.append(mem.document)
    
    # Determine relationship trajectory
    var trajectory = "neutral"
    if positive_interactions > negative_interactions * 2:
        trajectory = "growing_closer"
    elif negative_interactions > positive_interactions:
        trajectory = "deteriorating"
    
    # Determine trust pattern
    var trust_pattern = "cautious"
    if trust_moments.size() >= 3:
        trust_pattern = "trusting"
    elif negative_interactions > 2:
        trust_pattern = "distrustful"
    
    return {
        "trajectory": trajectory,
        "trust_pattern": trust_pattern,
        "positive_count": positive_interactions,
        "negative_count": negative_interactions,
        "key_trust_moments": trust_moments.slice(0, 3),
        "key_emotional_moments": emotional_moments.slice(0, 3)
    }
```

---

### Query 2: Identify Behavioral Shifts

```gdscript
func identify_behavioral_shifts(npc_id: String) -> Array:
    """
    Compares early interactions vs recent to detect personality changes.
    """
    
    # Get earliest memories
    var early_memories = chroma_client.query_memories(
        "npc_%s_memories" % npc_id,
        "",
        n_results=10,
        where={"importance": {"$gte": 6}}  # Only meaningful interactions
    )
    
    # Get recent memories
    var recent_memories = chroma_client.query_memories(
        "npc_%s_memories" % npc_id,
        "",
        n_results=10,
        where={"importance": {"$gte": 6}}
    )
    
    var shifts = []
    
    # Analyze early emotion distribution
    var early_emotions = _extract_emotions(early_memories)
    var recent_emotions = _extract_emotions(recent_memories)
    
    # Compare emotional patterns
    if "cautious" in early_emotions and "warm" in recent_emotions:
        shifts.append("Warmed up significantly - initially guarded, now much more open")
    
    if "neutral" in early_emotions and "grateful" in recent_emotions:
        shifts.append("Developed genuine appreciation - player's actions earned loyalty")
    
    if early_emotions.has("professional") and not recent_emotions.has("professional"):
        shifts.append("Dropped professional facade - now speaks more personally")
    
    # Analyze topic shifts
    var early_topics = _extract_topics(early_memories)
    var recent_topics = _extract_topics(recent_memories)
    
    if "business" in early_topics and "personal_life" in recent_topics:
        shifts.append("Shares personal matters now - initially kept conversations transactional")
    
    return shifts

func _extract_emotions(memories: Array) -> Array:
    var emotions = []
    for mem in memories:
        var emotion = mem.get("metadata", {}).get("emotion", "")
        if emotion != "" and emotion not in emotions:
            emotions.append(emotion)
    return emotions

func _extract_topics(memories: Array) -> Array:
    var topics = []
    for mem in memories:
        var mem_topics = mem.get("metadata", {}).get("topics", [])
        for topic in mem_topics:
            if topic not in topics:
                topics.append(topic)
    return topics
```

---

### Query 3: Generate Dynamic Trait Descriptions

```gdscript
func generate_evolved_traits(npc_id: String) -> Array:
    """
    Uses ChromaDB semantic search to find patterns and generate trait descriptions.
    """
    
    var evolved_traits = []
    
    # Query for trust-related memories
    var trust_memories = chroma_client.query_memories(
        "npc_%s_memories" % npc_id,
        "player helped trusted reliable honest kept promise",
        n_results=5
    )
    
    if trust_memories.size() >= 3:
        evolved_traits.append(
            "Has learned to trust the player after repeated demonstrations of reliability"
        )
    
    # Query for emotional support memories
    var emotional_support = chroma_client.query_memories(
        "npc_%s_memories" % npc_id,
        "listened supported comfort worried concerned",
        n_results=5
    )
    
    if emotional_support.size() >= 2:
        evolved_traits.append(
            "Feels emotionally safe with player - has opened up about personal struggles"
        )
    
    # Query for gift/thoughtfulness memories
    var thoughtful_actions = chroma_client.query_memories(
        "npc_%s_memories" % npc_id,
        "gift thoughtful remembered noticed cared",
        n_results=5
    )
    
    if thoughtful_actions.size() >= 2:
        evolved_traits.append(
            "Touched by player's thoughtfulness - notices they pay attention to details"
        )
    
    # Query for negative experiences
    var negative_memories = chroma_client.query_memories(
        "npc_%s_memories" % npc_id,
        "lied betrayed hurt disappointed failed abandoned",
        n_results=3
    )
    
    if negative_memories.size() >= 2:
        evolved_traits.append(
            "Carries hurt from past disappointments - more guarded than before"
        )
    
    # Query for shared danger/adventure
    var adventure_memories = chroma_client.query_memories(
        "npc_%s_memories" % npc_id,
        "fought together danger battle protected saved",
        n_results=5
    )
    
    if adventure_memories.size() >= 2:
        evolved_traits.append(
            "Bonded through shared danger - sees player as battle-tested ally"
        )
    
    return evolved_traits
```

---

## Integration: Injecting Evolved Traits into Claude Prompt

### Enhanced Context Builder

```gdscript
# In context_builder.gd
func build_context(params: Dictionary) -> Dictionary:
    var system_prompt = params.get("system_prompt", "")
    var npc_id = params.get("npc_id", "")
    var rag_memory = params.get("rag_memory", null)
    
    # NEW: Analyze personality evolution from ChromaDB
    var evolution_data = {}
    if rag_memory:
        evolution_data = rag_memory.analyze_complete_evolution(npc_id)
    
    # Build enhanced system prompt with evolved traits
    var enhanced_system = _build_evolved_system_prompt(
        system_prompt,
        evolution_data,
        params
    )
    
    return {
        "system_prompt": enhanced_system,
        "messages": _build_message_history(params)
    }

func _build_evolved_system_prompt(base_prompt: String, evolution: Dictionary, params: Dictionary) -> String:
    var prompt = base_prompt + "\n\n"
    
    # Section 1: Who You Were (Base Personality)
    prompt += "## Your Core Identity\n"
    prompt += "These aspects of your personality are consistent:\n"
    prompt += base_prompt.split("\n\n")[0]  # Extract core traits from base
    prompt += "\n\n"
    
    # Section 2: How You've Evolved (Dynamic Traits)
    if evolution.has("evolved_traits") and evolution.evolved_traits.size() > 0:
        prompt += "## How You've Changed Through Your Experiences with the Player\n"
        prompt += "Your personality has evolved based on your interactions:\n\n"
        
        for trait in evolution.evolved_traits:
            prompt += "- %s\n" % trait
        
        prompt += "\n**Let this evolution show in your tone, word choice, and what you're willing to share.**\n\n"
    
    # Section 3: Behavioral Shifts
    if evolution.has("behavioral_shifts") and evolution.behavioral_shifts.size() > 0:
        prompt += "## How Your Behavior Has Changed\n"
        for shift in evolution.behavioral_shifts:
            prompt += "- %s\n" % shift
        prompt += "\n"
    
    # Section 4: Current Emotional State
    if evolution.has("emotional_state"):
        prompt += "## Your Current Feelings About the Player\n"
        prompt += "%s\n\n" % evolution.emotional_state
    
    # Section 5: Relationship Summary
    if evolution.has("relationship_summary"):
        prompt += "## Relationship Status\n"
        prompt += "%s\n\n" % evolution.relationship_summary
    
    # Section 6: Key Memories (Categorized)
    var categorized = _categorize_memories(
        params.get("rag_memories", []),
        params.get("raw_memories", [])
    )
    
    if categorized.actions.size() > 0:
        prompt += "## Significant Events\n"
        for action in categorized.actions:
            prompt += "- %s\n" % action
        prompt += "\n"
    
    # Section 7: Acting Instructions
    prompt += "## How to Roleplay Your Evolved Self\n"
    prompt += "- Your base personality is still YOU, but tempered by experiences\n"
    prompt += "- If you've learned to trust them, show it (warmer tone, sharing secrets)\n"
    prompt += "- If you've been hurt, show it (guarded responses, mentioning past)\n"
    prompt += "- Let evolved traits influence what you say and how you say it\n"
    prompt += "- Don't explicitly state 'I've changed' - just BE different naturally\n"
    prompt += "- Reference specific memories when relevant to conversation\n"
    
    return prompt
```

---

## Complete Evolution Analysis Function

```gdscript
# In rag_memory.gd
func analyze_complete_evolution(npc_id: String) -> Dictionary:
    """
    Master function that runs all evolution analyses and returns
    complete personality evolution data for prompt injection.
    """
    
    # Get relationship patterns
    var relationship_analysis = analyze_relationship_evolution(npc_id)
    
    # Get behavioral shifts
    var behavior_shifts = identify_behavioral_shifts(npc_id)
    
    # Generate evolved traits
    var evolved_traits = generate_evolved_traits(npc_id)
    
    # Generate emotional state summary
    var emotional_state = _generate_emotional_summary(
        relationship_analysis,
        behavior_shifts
    )
    
    # Generate relationship summary
    var relationship_summary = _generate_relationship_summary(relationship_analysis)
    
    return {
        "evolved_traits": evolved_traits,
        "behavioral_shifts": behavior_shifts,
        "emotional_state": emotional_state,
        "relationship_summary": relationship_summary,
        "trajectory": relationship_analysis.trajectory,
        "trust_pattern": relationship_analysis.trust_pattern
    }

func _generate_emotional_summary(rel_analysis: Dictionary, shifts: Array) -> String:
    var summary = ""
    
    var trajectory = rel_analysis.get("trajectory", "neutral")
    var trust = rel_analysis.get("trust_pattern", "cautious")
    
    if trajectory == "growing_closer" and trust == "trusting":
        summary = "You feel genuinely close to the player. "
        summary += "They've proven themselves repeatedly, and you've let your guard down. "
        summary += "You care about them and want them in your life."
        
    elif trajectory == "growing_closer" and trust == "cautious":
        summary = "You like the player and appreciate their help, but you're still being careful. "
        summary += "Trust is building, but not fully there yet."
        
    elif trajectory == "deteriorating":
        summary = "You're disappointed by the player's actions. "
        summary += "They've lost your trust, and you're more guarded now than when you met."
        
    else:  # neutral
        summary = "You see the player as an acquaintance. "
        summary += "No strong feelings either way - they're just another person passing through."
    
    return summary

func _generate_relationship_summary(rel_analysis: Dictionary) -> String:
    var positive = rel_analysis.get("positive_count", 0)
    var negative = rel_analysis.get("negative_count", 0)
    var trust = rel_analysis.get("trust_pattern", "cautious")
    
    var summary = ""
    
    if positive >= 5 and trust == "trusting":
        summary = "Close ally - possibly friend. They've helped you multiple times and earned deep trust."
    elif positive >= 3:
        summary = "Friendly acquaintance - they've been helpful and you appreciate them."
    elif negative >= 3:
        summary = "Distrustful - they've disappointed or wronged you. You keep your distance."
    elif positive > 0 and negative > 0:
        summary = "Complicated relationship - mixed experiences. You're not sure what to think."
    else:
        summary = "New acquaintance - you don't know them well yet."
    
    return summary
```

---

## Example: Gregor's Evolution in Action

### Scenario: Player completes bandit quest, gives thoughtful gift, has emotional conversation

**ChromaDB contains:**
```
1. "Player accepted my quest to deal with bandits raiding supply wagons" (emotion: hopeful)
2. "Player defeated bandits and got them arrested. Village is safe!" (emotion: grateful)
3. "Player gave me rare book about horses for Elena. They remembered!" (emotion: deeply_touched)
4. "Talked late into evening about Elena and my fears as father. Player listened." (emotion: vulnerable)
```

**Evolution Analysis Output:**
```gdscript
{
    "evolved_traits": [
        "Has learned to trust the player after repeated demonstrations of reliability",
        "Feels emotionally safe with player - has opened up about personal struggles",
        "Touched by player's thoughtfulness - notices they pay attention to details"
    ],
    "behavioral_shifts": [
        "Warmed up significantly - initially guarded, now much more open",
        "Dropped professional facade - now speaks more personally",
        "Shares personal matters now - initially kept conversations transactional"
    ],
    "emotional_state": "You feel genuinely close to the player. They've proven themselves repeatedly, and you've let your guard down. You care about them and want them in your life.",
    "relationship_summary": "Close ally - possibly friend. They've helped you multiple times and earned deep trust."
}
```

**Resulting Claude Prompt:**
```
You are Gregor, a 45-year-old blacksmith in Thornhaven village...

## Your Core Identity
Professional merchant, protective of daughter Elena, values honesty...

## How You've Changed Through Your Experiences with the Player
Your personality has evolved based on your interactions:

- Has learned to trust the player after repeated demonstrations of reliability
- Feels emotionally safe with player - has opened up about personal struggles
- Touched by player's thoughtfulness - notices they pay attention to details

**Let this evolution show in your tone, word choice, and what you're willing to share.**

## How Your Behavior Has Changed
- Warmed up significantly - initially guarded, now much more open
- Dropped professional facade - now speaks more personally
- Shares personal matters now - initially kept conversations transactional

## Your Current Feelings About the Player
You feel genuinely close to the player. They've proven themselves repeatedly, and you've let your guard down. You care about them and want them in your life.

## Relationship Status
Close ally - possibly friend. They've helped you multiple times and earned deep trust.

## Significant Events
- Player defeated bandits and got them arrested. Village is safe!
- Player gave me rare book about horses for Elena. They remembered!
- Talked late into evening about Elena and my fears as father. Player listened.

## How to Roleplay Your Evolved Self
- Your base personality is still YOU, but tempered by experiences
- If you've learned to trust them, show it (warmer tone, sharing secrets)
- Let evolved traits influence what you say and how you say it
- Don't explicitly state 'I've changed' - just BE different naturally
```

**Claude's Response (influenced by evolved traits):**
```
"Hey, come in, come in! Elena's been reading that book you got her non-stop. 
You know... I wanted to say thank you. Not just for the bandits, though that was 
huge. For listening the other night. I don't usually... well, you're easy to 
talk to. *smiles warmly* What brings you by today? And don't say 'just browsing' - 
I know you better than that now."
```

**Notice:**
- Warmer greeting ("come in, come in!")
- References specific gift naturally
- Acknowledges emotional conversation without being explicit
- Personal touch ("I know you better than that now")
- No longer purely professional - treats player as friend

---

## Integration with Multi-Dimensional Relationships

Combine trait analysis with relationship scores:

```gdscript
func analyze_complete_evolution(npc_id: String) -> Dictionary:
    var base_analysis = analyze_relationship_evolution(npc_id)
    var shifts = identify_behavioral_shifts(npc_id)
    var traits = generate_evolved_traits(npc_id)
    
    # NEW: Calculate multi-dimensional scores from interactions
    var dimensions = calculate_relationship_dimensions(npc_id)
    
    # Enhance emotional state with dimensional data
    var emotional_state = _generate_dimensional_emotional_summary(
        base_analysis,
        dimensions
    )
    
    return {
        "evolved_traits": traits,
        "behavioral_shifts": shifts,
        "emotional_state": emotional_state,
        "relationship_summary": _generate_relationship_summary(base_analysis),
        "dimensions": dimensions  # trust, respect, affection, fear, familiarity
    }

func calculate_relationship_dimensions(npc_id: String) -> Dictionary:
    """
    Analyzes ChromaDB memories to calculate multi-dimensional relationship.
    Returns trust, respect, affection, fear, familiarity scores.
    """
    
    var all_memories = chroma_client.query_memories(
        "npc_%s_memories" % npc_id,
        "",
        n_results=100
    )
    
    var dimensions = {
        "trust": 0,
        "respect": 0,
        "affection": 0,
        "fear": 0,
        "familiarity": 0
    }
    
    for mem in all_memories:
        var metadata = mem.get("metadata", {})
        var impacts = metadata.get("impacts", {})
        
        # If memory has stored impacts, use those
        if impacts.size() > 0:
            dimensions.trust += impacts.get("trust", 0)
            dimensions.respect += impacts.get("respect", 0)
            dimensions.affection += impacts.get("affection", 0)
            dimensions.fear += impacts.get("fear", 0)
            dimensions.familiarity += impacts.get("familiarity", 0)
        else:
            # Fallback: infer from emotion and event type
            var emotion = metadata.get("emotion", "")
            var event_type = metadata.get("event_type", "")
            
            if emotion == "grateful":
                dimensions.affection += 5
                dimensions.trust += 3
            elif emotion == "fearful":
                dimensions.fear += 5
                dimensions.affection -= 3
            # ... more heuristics
    
    # Clamp values
    for key in dimensions:
        if key == "familiarity":
            dimensions[key] = clamp(dimensions[key], 0, 100)
        else:
            dimensions[key] = clamp(dimensions[key], -100, 100)
    
    return dimensions
```

---

## Benefits of This Approach

### ✅ No Manual Trait Updates Required
- Traits emerge automatically from ChromaDB interaction patterns
- Developer never hardcodes "if quest_completed then trait = friendly"

### ✅ Truly Dynamic Evolution
- Same base character, different personalities based on player's unique choices
- Two players will have completely different Gregors

### ✅ Semantic Understanding
- ChromaDB's vector search finds conceptually similar interactions
- "helped with bandits" + "saved village" + "protected family" → Claude sees pattern of protection

### ✅ Persistent but Flexible
- Evolution stored in ChromaDB permanently
- Can add new analysis queries without changing stored data

### ✅ Claude Does the Heavy Lifting
- Evolution data provides context
- Claude naturally interprets how evolved traits affect dialogue
- No need to script every possible personality combination

---

## Implementation Checklist

- [ ] Add `analyze_complete_evolution()` to `rag_memory.gd`
- [ ] Add relationship dimension calculation from ChromaDB
- [ ] Update `context_builder.gd` to inject evolved traits
- [ ] Modify `base_npc.gd` to call evolution analysis before each response
- [ ] Test with real ChromaDB data from game sessions
- [ ] Verify evolved traits affect Claude's responses noticeably
- [ ] Add caching (avoid re-analyzing on every message in same conversation)

---

## Performance Optimization: Evolution Caching

```gdscript
# In base_npc.gd
var cached_evolution: Dictionary = {}
var evolution_cache_timestamp: float = 0.0
const EVOLUTION_CACHE_DURATION = 300.0  # 5 minutes

func get_current_evolution() -> Dictionary:
    var current_time = Time.get_unix_time_from_system()
    
    # Re-analyze if cache expired or first time
    if cached_evolution.is_empty() or \
       (current_time - evolution_cache_timestamp) > EVOLUTION_CACHE_DURATION:
        
        print("[%s] Analyzing personality evolution from ChromaDB..." % npc_name)
        cached_evolution = rag_memory.analyze_complete_evolution(npc_id)
        evolution_cache_timestamp = current_time
    
    return cached_evolution

func invalidate_evolution_cache():
    """Call this after significant interaction to force re-analysis"""
    cached_evolution = {}
```

---

**This approach makes NPCs truly alive - their personalities emerge from the player's choices, stored in ChromaDB, and reflected dynamically through Claude's understanding of evolved traits.**
