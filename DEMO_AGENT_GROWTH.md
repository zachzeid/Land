# AI-Agent NPC Growth System - Demo Guide

This demonstrates how NPCs "grow" and evolve based on player interactions using action memories.

## How It Works

NPCs now categorize their memories into three types:

1. **Actions** - Quest acceptance/refusal, help given, items exchanged
   - Highest impact on NPC personality evolution
   - Directly affects relationship score
   - Shown as "How You've Changed Through Your Experiences" in Claude prompt

2. **Conversations** - Dialogue exchanges  
   - Medium impact - what was discussed
   - Helps NPC remember context and topics

3. **Events** - Witnessed events, world changes
   - Lower impact - things NPC observed
   - Environmental context

## Recording Player Actions

When player does something significant, call:

```gdscript
# Example: Player accepts quest from Gregor
gregor.record_player_action(
    "quest_accepted",
    "Player agreed to help me retrieve stolen supplies from the bandits",
    9,  # Importance (1-10)
    "hopeful"  # Emotion
)
```

This automatically:
- ✅ Stores memory in ChromaDB with event_type="quest_accepted"
- ✅ Updates relationship score (+5 for quest_accepted)
- ✅ Changes how NPC behaves in future conversations

## Action Types

- `quest_accepted` → +5 relationship, emotion: "hopeful"
- `quest_completed` → +15 relationship, emotion: "grateful"  
- `quest_refused` → -5 relationship, emotion: "disappointed"
- `quest_failed` → -10 relationship, emotion: "frustrated"
- `helped` → +5 relationship, emotion: "grateful"
- `refused_help` → -5 relationship, emotion: "disappointed"
- `item_given` → +10 relationship, emotion: "grateful"
- `item_received` → +0 relationship, emotion: "pleased"

## How NPC Personality Evolves

When Claude receives context, it sees:

```
## How You've Changed Through Your Experiences
Recent significant events that shaped your view of the player:
- Player agreed to help me retrieve stolen supplies from the bandits
- Player successfully completed my quest and returned the supplies
- Player gave me a healing potion when I was wounded

Let these experiences inform your current attitude and responses.

## Current Relationship with Player
Your current opinion of the player: Friendly (65/100)
```

This makes the NPC:
- ✅ Reference past help naturally ("After you helped with those bandits...")
- ✅ Show genuine gratitude or resentment
- ✅ Adjust tone based on relationship
- ✅ Remember failures or refusals

## Testing the System

### 1. Have a normal conversation
```
Player: "Hello Gregor"
Gregor: "Greetings, traveler." (neutral tone)
```

### 2. Accept a quest (simulate for now)
```gdscript
gregor.record_player_action(
    "quest_accepted",
    "Player agreed to deal with the bandits raiding our supply wagons",
    9
)
```

### 3. Talk again - NPC remembers!
```
Player: "How are you?"
Gregor: "Better, now that you've agreed to help! Those bandits have been a plague." 
(hopeful tone, references the action)
```

### 4. Complete quest
```gdscript
gregor.record_player_action(
    "quest_completed",
    "Player defeated the bandits and recovered our supplies. I'm deeply grateful.",
    10,
    "grateful"
)
```

### 5. Talk again - personality has evolved
```
Player: "Need anything else?"
Gregor: "You've already done so much for us! The village is safer because of you. 
If you ever need help, I'm here." (warm, trusting tone)
```

## Current Implementation Status

✅ Memory system stores actions with metadata  
✅ Context builder categorizes memories  
✅ Claude receives structured action history  
✅ Relationship scores update automatically  
✅ NPCs reference past experiences in dialogue  

🚧 **Next Steps:**
- Build actual quest system (not just manual recording)
- Add quest triggers from dialogue
- Create quest completion detection
- Add combat system for quest resolution

## Try It Now!

Run the game and talk to Gregor, then manually record an action:
1. Open game console (if available) or modify `gregor_merchant.gd`
2. Add after a conversation: `record_player_action("helped", "Player gave me advice about the bandits", 7)`
3. Talk to Gregor again and watch him remember it!
