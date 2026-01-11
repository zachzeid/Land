# 🎮 AI-Agent NPC Growth Demo: Gregor's Romance Arc

## From Cautious Merchant to Romantic Partner

This document demonstrates how the AI-agent growth system transforms NPC personality through player actions.

---

## 📖 THE STORY

### 🎬 ACT 1: First Meeting
**Relationship: 0/100**

Player enters Gregor's shop for the first time.

**Gregor's State:**
- No memories of player
- Professional, cautious demeanor
- Focused on business

**Gregor says:** *"Welcome to my shop. What can I help you find today?"*

---

### 🎬 ACT 2: The Bandit Problem
**Action: Player accepts quest**

Player: *"I can help you with those bandits."*

**System executes:**
```gdscript
gregor.record_player_action(
    "quest_accepted",
    "Player agreed to help deal with bandits raiding supply wagons",
    9,  # High importance
    "hopeful"
)
```

**Effect:**
- ✅ Memory stored: Quest acceptance
- ✅ Relationship: 0 → **5** (+5 for quest_accepted)
- ✅ Emotion: Hopeful
- ✅ AI receives: "How You've Changed: Player agreed to help with bandits"

**Gregor's new tone:** *"Thank you! I'll feel safer with you handling this."*

---

### 🎬 ACT 3: Victory!
**Action: Player completes quest**

Player returns: *"The bandits are in jail. Your wagons are safe."*

**System executes:**
```gdscript
gregor.record_player_action(
    "quest_completed",
    "Player defeated bandits and got them arrested. Supply wagons are safe!",
    10,
    "grateful"
)
```

**Effect:**
- ✅ Memory stored: Quest completion
- ✅ Relationship: 5 → **20** (+15 for quest_completed)
- ✅ Emotion: Deeply grateful
- ✅ AI sees in prompt:
  ```
  ## How You've Changed Through Your Experiences
  - Player agreed to help with bandits raiding supply wagons
  - Player defeated bandits and got them arrested. Supply wagons are safe!
  ```

**Gregor's evolved response:** *"You're a hero! The village owes you everything."*

---

### 🎬 ACT 4: Gratitude Gift
**Action: Gregor gives healing potion**

```gdscript
gregor.record_player_action(
    "item_given",
    "Gave player premium healing potion as thanks for bandit quest",
    7,
    "warm"
)
```

**Effect:**
- ✅ Relationship: 20 → **30** (+10 for item_given)
- ✅ Gregor now at "Positive" relationship tier
- ✅ Flirtation threshold approaching (>30 for subtle hints)

**Gregor:** *"Please, take this. After what you did... it's the least I can offer."*

---

### 🎬 ACT 5: Growing Closer
**Action: Player helps reorganize shop**

Multiple helpful interactions build trust:

```gdscript
gregor.record_player_action(
    "helped",
    "Player helped reorganize inventory. I enjoyed their company. They're... attractive.",
    8,
    "interested"
)
```

**Effect:**
- ✅ Relationship: 30 → **38** (+8 for personal help)
- ✅ CROSSED THRESHOLD: >30 = Subtle flirtation unlocked!
- ✅ AI prompt now includes romantic interest

**Gregor's personality shift:**
```
Your current opinion: Positive (38/100)

How You've Changed:
- Player defeated bandits (quest completed)
- Player helped with inventory, enjoyed their company, finds them attractive

Instructions:
- Drop subtle flirtatious hints if relationship is positive (>30) ✓
```

**Gregor:** *"You have a good eye for... organization. Among other things."* 😏

---

### 🎬 ACT 6-7: Building Deep Trust
**Multiple helpful actions:**

```gdscript
// Better trade deals
gregor.record_player_action("helped", "Player negotiated better prices", 7)
// Relationship: 38 → 45

// Shared secret about bandit informant  
gregor.record_player_action("helped", "Told player about informant. Deep trust.", 9)
// Relationship: 45 → 54
```

**Effect:**
- ✅ Relationship: 45 → **54**
- ✅ "Friendly" tier (50+)
- ✅ Open flirtation threshold unlocked (>50)

**Gregor's evolved behavior:**
- References past help naturally
- More physically comfortable (closer proximity)
- Openly flirtatious comments
- Talks about personal life, not just business

**Gregor:** *"You know, the tavern has excellent wine. Ever been to their... private rooms?"*

---

### 🎬 ACT 8: Chemistry Intensifies

```gdscript
gregor.record_player_action(
    "helped",
    "Talked late into evening. Player is charming, brave, kind. Flirted openly.",
    8,
    "attracted"
)
```

**Effect:**
- ✅ Relationship: 54 → **62**
- ✅ CRITICAL THRESHOLD CROSSED: **>60 = Romance available!**

**AI Prompt now shows:**
```
Current Relationship: Friendly (62/100)

How You've Changed Through Your Experiences:
- Player completed quest defeating bandits (grateful)
- Player helped with business multiple times (appreciative)
- Shared dangerous secret about informant (trusting)
- Long evening conversation, mutual attraction (interested)

Your personality traits include:
- Would accept romantic advances if trust is high (>60) ✓ CONDITION MET
```

---

### 🎬 ACT 9: The Invitation
**Player makes their move**

Player: *"Gregor... would you like to come back to my room at the tavern? For wine?"*

**Gregor's AI evaluates:**
1. Quest completed? ✅ (Bandits defeated)
2. Relationship score? ✅ (62/100 > 60 threshold)
3. Trust established? ✅ (Shared secrets)
4. Mutual attraction? ✅ (Memories confirm interest)
5. Personality allows? ✅ (System prompt permits romance)

**Gregor responds naturally:**
*"I thought you'd never ask. Let me just... close up the shop."* 💕

```gdscript
gregor.record_player_action(
    "item_received",  // Accepting invitation
    "Player invited me to tavern room. After everything together, I want this.",
    10,
    "excited"
)
```

**Effect:**
- ✅ Relationship: 62 → **72** (+10 for intimate moment)
- ✅ **ROMANCE ACHIEVED**
- ✅ Memory stored: Romantic encounter

---

## 🌅 EPILOGUE: Permanent Evolution

### Gregor's Memory Bank Now Contains:
1. **Quest accepted** - "Player agreed to help with bandits" (importance: 9)
2. **Quest completed** - "Player defeated bandits, village safe" (importance: 10)
3. **Gift given** - "Gave healing potion as thanks" (importance: 7)
4. **Multiple helps** - "Inventory, trades, secrets shared" (importance: 7-9)
5. **Romance accepted** - "Invited to tavern, I wanted them" (importance: 10)

### Future Conversations:
All dialogue will be filtered through these experiences.

**Next morning, player visits shop:**

Player: *"Good morning, Gregor."*

**Gregor's AI receives:**
```
System Prompt: You are Gregor, flirtatious merchant...

Current Relationship: Trusted friend (72/100)

How You've Changed Through Your Experiences:
- Player defeated bandits and saved the village
- Player helped with business and earned deep trust
- Player and I spent the night together at the tavern
- I care deeply about them now

Past Conversations:
- Discussed bandit problems
- Shared secret about informant
- Flirted about wine and tavern rooms
```

**Gregor responds (generated by Claude):**
*"Good morning, love. Last night was... unforgettable. I saved you a special item behind the counter."* 😊

---

## ✨ This is AI-Agent Growth

### Before Quest (Relationship: 0):
*"Welcome to my shop. What do you need?"*

### After Quest (Relationship: 20):
*"Ah, my hero returns! What can I do for you today?"*

### After Building Trust (Relationship: 50):
*"Always a pleasure to see you. You brighten my day, you know."*

### After Romance (Relationship: 72):
*"There's my favorite customer... and so much more. Come here."*

**Same NPC. Same AI. Different personality.**

The only thing that changed: **Action memories stored through gameplay.**

---

## 🎯 How to Achieve This In-Game

### Step-by-Step Guide:

1. **Talk to Gregor** - Start conversation (Relationship: 0)

2. **Accept his quest** - Manually trigger:
   ```gdscript
   gregor.record_player_action("quest_accepted", "...", 9)
   ```
   
3. **(Build quest system later to automate this)**

4. **Complete objectives** - Trigger:
   ```gdscript
   gregor.record_player_action("quest_completed", "...", 10)
   ```

5. **Help with tasks** - Trigger:
   ```gdscript
   gregor.record_player_action("helped", "...", 7-9)
   ```

6. **Build relationship to 60+** through repeated positive actions

7. **Flirt in conversation** - Claude will respond based on memories

8. **Make invitation** - If relationship > 60, he'll accept!

### Action Types & Relationship Changes:
- `quest_accepted`: +5
- `quest_completed`: +15
- `quest_refused`: -5
- `helped`: +5
- `item_given`: +10
- `item_received`: varies

---

## 🔧 Current Implementation Status

✅ **Memory system stores actions with metadata**
✅ **Context builder categorizes memories (actions vs conversations)**
✅ **Claude receives "How You've Changed" section**
✅ **Relationship scores auto-update**
✅ **Gregor's personality allows romance at >60 relationship**
✅ **All memories persist in ChromaDB**

🚧 **Next Steps:**
- Build actual quest system to trigger actions automatically
- Add quest completion detection
- Create more NPCs with different romance thresholds/personalities
- Add combat for quest resolution

---

**The NPC isn't scripted. He evolved.**

Every response is generated fresh by Claude, informed by actual experiences stored in memory. Gregor "grew" from stranger to lover through the accumulation of action memories - just like a real relationship.

This is AI-agent NPC growth. 🚀
