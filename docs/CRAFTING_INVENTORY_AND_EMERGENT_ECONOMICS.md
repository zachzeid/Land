# Crafting, Inventory, and Emergent Economics System

> **Date:** 2026-03-28
> **Status:** Design Document (no code yet)
> **Depends on:** AUTONOMOUS_NPC_AGENTS.md (agent loop), NPC_EXISTENCE_AND_INFLUENCE_SYSTEM.md (ripple engine, tiers), EMERGENT_NARRATIVE_SYSTEM.md (story threads), existing WorldState, WorldKnowledge, EventBus, NPCPersonality

---

## Design Philosophy

Economics in Land is not a spreadsheet. It is the **material consequence of NPC decisions**. When Gregor diverts weapons to bandits, Bjorn's visible stock drops. When bandits raid the trade route, grain prices rise in Thornhaven. When Mira closes the tavern, traveling merchants stop visiting. None of these require a hand-authored price table. They emerge from the same agent loop that drives the narrative.

The player experiences economics the way a person arriving in a real village would: through the prices NPCs charge, the goods available on shelves, the complaints of farmers, and the whispered deals in back alleys. The underlying simulation is invisible. What the player sees is a world that responds coherently to disruption.

**Three governing principles:**

1. **NPCs own the economy.** Every item in the world belongs to an NPC or a location. There is no abstract "shop inventory" that refills magically. Bjorn has iron because a shipment arrived from Millhaven. If the shipment was raided, he does not have iron.

2. **Prices are opinions, not facts.** An NPC's asking price reflects their inventory, their desperation, their relationship with the buyer, and their goals. Gregor charges more when he is saving gold for Elena's escape. Bjorn charges less to someone who helped him learn the truth about his weapons.

3. **Crafting is relational.** The player does not open a menu and combine items. They go to Bjorn's forge and ask him to make something. The quality depends on Bjorn's skill, the materials available, and whether Bjorn trusts the player enough to use his best techniques.

---

## 1. Item System Architecture

### 1.1 Item Categories

Items fall into seven functional categories. An item's category determines which systems interact with it.

| Category | Examples | Stackable | Has Quality | Has Durability | Can Present as Evidence |
|----------|---------|-----------|-------------|----------------|------------------------|
| **Materials** | Iron ore, leather, herbs, timber, grain | Yes (99) | Yes (grade) | No | No |
| **Weapons** | Sword, dagger, bow, club | No | Yes (tier) | Yes | Yes (if marked) |
| **Armor** | Leather vest, chain shirt, shield | No | Yes (tier) | Yes | No |
| **Consumables** | Health potion, bread, ale, antidote | Yes (20) | Yes (potency) | No (but expiry) | No |
| **Tools** | Pickaxe, lockpick, fishing rod, rope | No | Yes (tier) | Yes | No |
| **Evidence** | Ledger, marked weapon, letter, seal | No | No | No | Yes |
| **Quest Items** | Key to old mill, Mira's locket, seal ring | No | No | No | Sometimes |

### 1.2 Item Data Structure

Items are represented as Godot `Resource` instances. This allows them to be saved, loaded, inspected in the editor, and referenced cleanly by both GDScript and the save system.

```
ItemData (extends Resource):
  class_name: ItemData

  # Identity
  item_id: String              # "iron_ore", "bjorn_longsword_001"
  display_name: String         # "Iron Ore", "Bjorn's Longsword"
  description: String          # Flavor text
  category: ItemCategory       # Enum: MATERIAL, WEAPON, ARMOR, CONSUMABLE, TOOL, EVIDENCE, QUEST
  icon_path: String            # Path to sprite (generated or hand-placed)

  # Physical properties
  weight: float                # In "stones" (abstract unit). 1 stone ~ 5 lbs.
  base_value: int              # Base price in silver coins. NOT the sale price; just a reference anchor.

  # Stacking
  is_stackable: bool           # Materials and consumables
  max_stack_size: int          # 99 for materials, 20 for consumables, 1 for everything else

  # Quality (for materials, weapons, armor, consumables, tools)
  quality: ItemQuality         # Enum: CRUDE, COMMON, FINE, SUPERIOR, MASTERWORK

  # Durability (for weapons, armor, tools)
  max_durability: int          # 0 = no durability tracking
  current_durability: int      #

  # Consumable properties
  effect_type: String          # "heal", "buff_strength", "cure_poison", "none"
  effect_magnitude: int        # How much (heal 30, buff +5, etc.)
  expiry_days: int             # 0 = never expires. Bread might be 3, potions 30.
  created_on_day: int          # Game-day when crafted/obtained

  # Weapon/Armor properties
  damage_bonus: int            # For weapons
  defense_bonus: int           # For armor
  equipment_slot: String       # "main_hand", "off_hand", "head", "chest", "legs", "feet", "accessory"

  # Crafting origin
  crafted_by: String           # NPC ID of crafter, or "" if found/bought
  maker_mark: String           # Visual identifier (Bjorn's "B" mark)

  # Evidence properties
  evidence_tags: Array[String] # ["bandit_deal", "gregor_involvement", "weapons_supply"]
  presentable_to: Array[String] # NPC IDs who would react to this evidence: ["aldric", "mathias", "bjorn"]

  # Tags for AI context
  tags: Array[String]          # ["metal", "weapon", "bjorn_crafted", "bandit_marked"]
```

### 1.3 Item Quality System

Quality is not cosmetic. It directly affects gameplay: weapon damage, armor protection, consumable potency, tool effectiveness, and sale price.

| Quality | Damage/Defense Mult | Durability Mult | Value Mult | How Obtained |
|---------|-------------------|-----------------|------------|-------------|
| **Crude** | 0.7x | 0.5x | 0.4x | Failed craft, scavenged, lowest materials |
| **Common** | 1.0x | 1.0x | 1.0x | Standard craft, most shop goods |
| **Fine** | 1.2x | 1.3x | 2.0x | Good materials + skilled crafter |
| **Superior** | 1.5x | 1.6x | 4.0x | Excellent materials + high-skill crafter + good tools |
| **Masterwork** | 1.8x | 2.0x | 8.0x | Best materials + master crafter + master tools + crafter trust |

Quality is determined at creation time by a formula (Section 3.4). It never changes after creation.

### 1.4 Evidence Items (Deep Integration with Narrative)

Evidence items are the bridge between the inventory system and the narrative system. They are the physical proof that threads require.

**The Ledger** (`gregor_ledger`)
- `evidence_tags`: ["bandit_deal", "gregor_involvement", "weapons_supply", "financial_records"]
- `presentable_to`: ["aldric_peacekeeper_001", "elder_mathias_001", "bjorn_blacksmith_001", "elena_daughter_001"]
- Presenting to Aldric: Sets `gregor_exposed` flag, advances Thread 5 (Failing Watch), provides the evidence Mathias needs (Thread 6)
- Presenting to Elena: Devastating. Advances Thread 3, potentially shatters Thread 1.
- Presenting to Bjorn: Reveals his unwitting complicity. Advances Thread 4.
- Presenting to Gregor: Confrontation. His Claude prompt receives the evidence context. Response depends on relationship state.

**Bjorn's Marked Weapon** (`bjorn_marked_weapon`)
- Found on a dead bandit or recovered from a raid
- `evidence_tags`: ["weapons_supply", "bjorn_crafted", "bandit_possession"]
- `maker_mark`: "B" (Bjorn's signature)
- `presentable_to`: ["bjorn_blacksmith_001", "aldric_peacekeeper_001"]
- Presenting to Bjorn: "That's... that's my mark. Where did you find this?"

**Evidence Presentation Mechanic:**
When the player presents an evidence item to an NPC during dialogue, the system injects the evidence context into the NPC's Claude prompt:

```
[EVIDENCE PRESENTED]
The player is showing you: {item.display_name}
Description: {item.description}
Evidence tags: {item.evidence_tags}
Your known relationship to this evidence: {npc-specific context}
React authentically based on your personality, secrets, and relationship with the player.
```

The NPC's Claude agent then generates a response that reflects their personality, their knowledge, and the implications of the evidence. This is not a scripted reaction -- it is an emergent one shaped by all the context the NPC has accumulated.

---

## 2. Inventory System

### 2.1 Player Inventory

The player uses a **weight-based** inventory with a soft cap and hard cap. Weight-based (not slot-based) because it creates meaningful choices about what to carry without the artificiality of "your backpack has exactly 20 slots."

```
PlayerInventory:
  items: Array[InventorySlot]     # All carried items
  max_weight: float               # Default: 50.0 stones
  current_weight: float           # Calculated from items
  gold: int                       # Currency carried

  # Weight thresholds
  ENCUMBERED_THRESHOLD: 0.75      # At 75% capacity: movement speed -20%
  OVERBURDENED_THRESHOLD: 1.0     # At 100%: cannot run, movement speed -50%
  ABSOLUTE_MAX: 1.2               # At 120%: cannot pick up more items

InventorySlot:
  item: ItemData                  # The item resource
  quantity: int                   # For stackable items, else 1
```

**Weight values (reference):**
- Materials: 0.5-2.0 stones (ore is heavy, herbs are light)
- Weapons: 2.0-6.0 stones (dagger light, greatsword heavy)
- Armor: 3.0-10.0 stones (leather light, plate heavy)
- Consumables: 0.1-0.5 stones
- Tools: 1.0-3.0 stones
- Evidence: 0.1-0.5 stones (paper is light)
- Quest items: 0.0 stones (quest items never encumber)

### 2.2 NPC Inventories

Every NPC that sells, crafts, or trades has an inventory. NPC inventories are the economic simulation's ground truth. There is no abstract "stock level" -- there are actual items.

```
NPCInventory:
  npc_id: String
  items: Array[InventorySlot]
  gold: int                         # How much currency the NPC has to buy with
  daily_expenses: int               # Gold spent per game-day on operating costs
  restock_sources: Array[String]    # Where this NPC gets new goods (trade routes, crafting, farming)

  # Price modifiers (calculated, not stored permanently)
  # See Section 4 for the pricing formula
```

**Key NPC inventories at game start:**

**Gregor (General Goods):**
- Stock: rope, lanterns, rations, cloth, basic tools, travel supplies, some weapons (diverted from Bjorn)
- Gold: 500 (high -- profits from bandit arrangement)
- Restock: Millhaven trade route (threatened by bandits), Bjorn's forge, local farmers
- Secret inventory: weapons cached for next bandit delivery (hidden, not displayed in shop UI unless player discovers them)

**Bjorn (Blacksmith):**
- Stock: swords (2-3), shields (1-2), tools, nails, horseshoes, repair services
- Gold: 150 (modest -- honest work)
- Restock: Iron ore from Millhaven trade route, charcoal from local woodcutter
- Note: Bjorn crafts new items when he has materials. His stock is the output of his work, not a refilling table.

**Mira (Tavern):**
- Stock: ale, mead, bread, stew, rooms (service, not item), information (not sold, but traded)
- Gold: 80 (tavern is struggling)
- Restock: Local farmers (grain, vegetables), Millhaven trade route (wine, spices)

### 2.3 Container Inventories

Locations can have container inventories: chests, barrels, crates, hidden caches.

```
ContainerInventory:
  container_id: String            # "gregor_shop_hidden_chest", "aldric_weapon_cache"
  location: String                # Location ID
  items: Array[InventorySlot]
  is_locked: bool
  lock_difficulty: int            # 0-100 for lockpicking
  requires_key: String            # Item ID of required key, or ""
  owner_npc: String               # NPC ID who "owns" this (stealing has consequences)
  discovery_flag: String          # WorldState flag set when player finds this
```

**Narrative containers:**
- Gregor's hidden chest: Contains the ledger, extra gold, a letter to Elena. Locked. Discovery flag: `gregor_hidden_stash_found`.
- Aldric's weapon cache: Under the old well. Contains weapons Aldric has been stockpiling. Discovery flag: `aldric_cache_found`.
- Bandit weapon crate at Iron Hollow: Contains weapons with Bjorn's maker mark. Discovery flag: `bandit_weapons_examined`.

---

## 3. Crafting System

### 3.1 Design Principle: Crafting is Social

The player does not craft in isolation. Crafting happens at NPC-owned stations, and the NPC's skill, willingness, and relationship with the player determine what can be made and how well.

This is not a limitation -- it is a narrative device. Bjorn teaching the player better techniques is a relationship milestone. The player seeking out the herbalist for rare potions is a quest hook. Having to go to a bandit camp for illegal weapons is a moral choice.

**Exception:** The player can perform basic campfire crafting alone (simple potions, cooking, basic repairs). Anything requiring a forge, alchemy station, or specialized tools requires an NPC or station.

### 3.2 Crafting Stations

| Station | Location | Owner NPC | What Can Be Made | Access Requirements |
|---------|----------|-----------|-----------------|---------------------|
| **Bjorn's Forge** | Thornhaven Blacksmith | Bjorn | Weapons, armor, tools, metal goods | Bjorn must be present and willing |
| **Herbalist's Garden** | Thornhaven (Tier 1 NPC) | Herbalist | Potions, salves, antidotes, poisons | Herbalist must trust player |
| **Player's Campfire** | Any wilderness/camp | Player | Cooked food, simple potions, basic repairs | Always available |
| **Mira's Kitchen** | The Rusty Nail | Mira | Better food, specialty drinks | Mira must be present |
| **Iron Hollow Forge** | Bandit Camp | Bandit smith | Crude weapons, traps, poison-tipped bolts | Bandit faction trust required |
| **Millhaven Workshop** | Millhaven (future) | Guild craftsman | Fine goods, specialty items | Guild reputation or payment |

### 3.3 Recipe System

Recipes are not static unlock lists. They exist along a spectrum:

**Tier A -- Innate Knowledge:**
The player knows basic survival crafting from the start.
- Campfire cooking (raw meat + fire = cooked meat)
- Basic bandage (cloth + herbs)
- Torch (stick + cloth + oil)
- Simple trap (rope + stick + weight)

**Tier B -- Taught by NPCs:**
NPCs teach recipes as a natural consequence of relationship building. This is handled through the dialogue system, not a separate recipe UI.

- Bjorn teaches weapon smithing at trust >= 40 ("Here, let me show you how to work the metal properly")
- Bjorn teaches superior techniques at trust >= 70 ("I've never shown anyone this technique... my old commander taught me during the Border Wars")
- The herbalist teaches potion brewing at disposition >= 30
- Mira teaches specialty cooking at trust >= 50
- A bandit might teach trap-making or poison application

When an NPC teaches a recipe, it is stored in the player's known recipes and a memory is created for both the player's journal and the NPC's RAG memory.

**Tier C -- Discovered through Experimentation:**
Some recipes can be discovered by combining materials at a station. The system has a hidden recipe table, and when the player uses materials that match an undiscovered recipe, they succeed and learn it.

**Tier D -- Found in the World:**
Written recipes in books, scrolls, or notes found in exploration (the old ruins, a dead traveler's pack, a scholar's research).

```
Recipe:
  recipe_id: String                # "iron_longsword"
  display_name: String             # "Iron Longsword"
  result_item_id: String           # "longsword"
  result_category: ItemCategory    # WEAPON

  # Requirements
  materials: Array[Dictionary]     # [{item_id: "iron_ore", quantity: 3}, {item_id: "leather_strip", quantity: 1}]
  station_required: String         # "forge", "alchemy_station", "campfire", "kitchen"
  minimum_skill: int               # 0-100, crafter's skill must meet this
  tools_required: Array[String]    # ["hammer", "tongs"] -- must be at the station

  # Discovery
  discovery_method: String         # "innate", "taught", "experimented", "found"
  taught_by: String                # NPC ID if taught
  taught_at_trust: int             # Trust threshold if taught

  # Result modifiers
  base_quality: ItemQuality        # COMMON -- modified by crafter skill + materials
  craft_time_minutes: int          # In-game minutes to complete
```

### 3.4 Quality Determination

When an item is crafted, quality is calculated from four factors:

```
quality_score = (
  material_grade * 0.35 +       # Average quality of input materials (0.0-1.0)
  crafter_skill * 0.30 +        # NPC or player crafting skill (0.0-1.0)
  tool_quality * 0.20 +         # Quality of tools at the station (0.0-1.0)
  relationship_bonus * 0.15     # NPC trust/effort bonus (0.0-1.0)
)

Quality thresholds:
  0.0 - 0.25 -> CRUDE
  0.25 - 0.50 -> COMMON
  0.50 - 0.70 -> FINE
  0.70 - 0.85 -> SUPERIOR
  0.85 - 1.00 -> MASTERWORK
```

**The relationship_bonus matters.** When Bjorn trusts the player (trust >= 60), he puts in extra effort. He uses better techniques. He takes his time. This is reflected in the quality calculation and is visible to the player: "Bjorn works with unusual care, applying techniques you've never seen him use for other customers."

At trust < 20, Bjorn does competent but uninspired work (relationship_bonus = 0.2).
At trust 20-50, standard effort (relationship_bonus = 0.4-0.6).
At trust 50-80, genuine care (relationship_bonus = 0.7-0.85).
At trust > 80, he teaches the player as he works, and the result reflects his best (relationship_bonus = 0.9-1.0).

### 3.5 Crafting Flow (Player Experience)

1. Player approaches Bjorn's forge while Bjorn is present
2. Player initiates dialogue: "Can you make me a sword?"
3. Bjorn's Claude agent responds based on:
   - Does he have the materials? (Checked against his NPCInventory)
   - Does he trust the player? (Checked against relationship_trust)
   - Does the player have something to trade/pay? (Checked against player inventory/gold)
   - Is there a reason he would refuse? (e.g., he just learned the truth about his weapons -- too upset to work)
4. If agreeable, the crafting transaction occurs:
   - Materials are consumed from Bjorn's inventory (or the player provides them)
   - Gold changes hands
   - A crafting event fires through EventBus
   - The result item is created with quality determined by the formula
   - Time passes (in-game minutes)
5. Bjorn presents the result with dialogue reflecting the quality and his feelings

This flow means crafting is a **conversation**, not a menu. The player asks an NPC to make something. The NPC decides whether and how well to do it.

---

## 4. Emergent Economic Simulation

### 4.1 Core Architecture: The Economic State

A new autoload singleton: `EconomyManager`. This system runs alongside `WorldSimulation` and maintains the economic state of every settlement.

```
EconomyManager (Autoload Singleton):

  # Per-settlement economic state
  settlement_economies: Dictionary
    # settlement_id -> SettlementEconomy

  # Active trade routes
  trade_routes: Array[TradeRoute]

  # Price history (for player to notice trends)
  price_history: Dictionary
    # item_id -> Array[{day, settlement, price}]

  # Economic event log
  economic_events: Array[Dictionary]
```

```
SettlementEconomy:
  settlement_id: String           # "thornhaven"

  # Supply tracking (per commodity)
  supply: Dictionary              # {commodity_id: float} -- 0.0 to 200.0 (100 = normal)
  demand: Dictionary              # {commodity_id: float} -- 0.0 to 200.0 (100 = normal)

  # Aggregate indicators
  prosperity: float               # 0.0-100.0 -- general economic health
  trade_volume: float             # 0.0-100.0 -- how much trading is happening
  tax_rate: float                 # 0.0-0.5 -- set by local authority (nobility/council)

  # Wage levels (affects what peasants/workers earn)
  average_daily_wage: int         # In silver coins

  # Active modifiers
  modifiers: Array[EconomicModifier]
```

```
EconomicModifier:
  modifier_id: String             # "trade_route_disrupted"
  source: String                  # "iron_hollow_gang" or "drought" or "festival"
  affects: Dictionary             # {commodity_id: {supply_delta: -30, demand_delta: +10}}
  duration_days: int              # -1 = permanent until resolved
  remaining_days: int             #
  intensity: float                # 0.0-1.0
```

### 4.2 Commodity System

The economy does not track every individual item. It tracks **commodities** -- abstract categories that items belong to. Individual items derive their prices from commodity values.

| Commodity | Example Items | Base Supply Sources | Base Demand Sources |
|-----------|--------------|--------------------|--------------------|
| `grain` | Wheat, barley, flour, bread | Local farms, Millhaven imports | Bakery, tavern, general population |
| `iron` | Iron ore, iron ingots | Millhaven mines via trade route | Blacksmith, tool repair |
| `timber` | Logs, planks, firewood | Local forest | Construction, heating, crafting |
| `leather` | Raw hides, tanned leather | Local hunters, livestock | Armor, clothing, equipment |
| `herbs` | Medicinal herbs, cooking herbs | Herbalist's garden, wild gathering | Healing, cooking, alchemy |
| `weapons` | Swords, bows, shields | Blacksmith (Bjorn) | Peacekeepers, travelers, bandits (secretly) |
| `food` | Meat, vegetables, preserved goods | Farms, hunting, trade route | Everyone |
| `ale` | Ale, mead, wine | Tavern (Mira), Millhaven imports | Tavern customers, celebrations |
| `luxury` | Spices, silk, jewelry, rare books | Capital, distant trade | Nobility, wealthy merchants |
| `tools` | Hammers, axes, plows, nails | Blacksmith | Farmers, tradespeople, general |

### 4.3 The Pricing Formula

When a player (or NPC) wants to buy an item from another NPC, the price is calculated dynamically:

```
sale_price = base_value
  * supply_demand_modifier        # From settlement economy
  * seller_markup                 # NPC's profit margin (personality-driven)
  * relationship_modifier         # Discount/markup based on trust
  * scarcity_modifier            # Extra markup if seller's own stock is low
  * desperation_modifier          # If seller urgently needs gold, prices drop
  * tax_modifier                  # Local tax rate
  * (1.0 + haggle_adjustment)    # Result of haggling, if attempted

Where:
  supply_demand_modifier = demand[commodity] / max(supply[commodity], 10.0)
    # If demand = 150 and supply = 50: modifier = 3.0 (prices triple)
    # If demand = 80 and supply = 120: modifier = 0.67 (prices drop)
    # Clamped to range [0.3, 5.0] to prevent extremes

  seller_markup:
    # Gregor: 1.3 (he's profit-oriented, saving for Elena)
    # Bjorn: 1.1 (fair, honest)
    # Black market: 1.5-2.0 (risk premium)
    # Desperate seller: 0.8-0.9

  relationship_modifier:
    # trust < -50: 1.5 (hostile markup)
    # trust -50 to 0: 1.2 (suspicious markup)
    # trust 0 to 30: 1.0 (standard)
    # trust 30 to 60: 0.9 (friendly discount)
    # trust > 60: 0.8 (trusted friend discount)
    # trust > 80: 0.7 (family price)

  scarcity_modifier:
    # If seller has <3 of this item: 1.3
    # If seller has 1 of this item: 1.6
    # If this is seller's last one: 2.0 (or refuses to sell)

  desperation_modifier:
    # If seller's gold < daily_expenses * 3: 0.85
    # If seller's gold < daily_expenses: 0.7
    # Otherwise: 1.0

  tax_modifier:
    # 1.0 + settlement.tax_rate
    # Black market transactions skip tax
```

**Buy prices** (what an NPC will pay the player) use the same formula but inverted: the NPC applies a buy discount (typically 0.4-0.6 of sale price) because they need profit margin.

### 4.4 How Supply and Demand Change

Supply and demand are not static. They change every game-day tick based on:

**Supply changes:**
```
Each game-day:
  For each commodity in each settlement:

    # Production
    supply += local_production(commodity)
      # e.g., Thornhaven produces grain (farms), timber (forest), herbs (herbalist)
      # Production is an attribute of the settlement, modified by season and events

    # Trade route imports
    for route in connected_trade_routes:
      if route.is_active and route.safety > 0.3:
        supply += route.import_volume(commodity) * route.safety

    # NPC crafting output
    for npc in settlement.crafting_npcs:
      supply += npc.daily_output(commodity)
      # Bjorn produces ~2 weapons/day and ~5 tools/day when he has materials

    # Consumption
    supply -= local_consumption(commodity)
      # Population eats food, burns firewood, wears out tools
      # consumption = population * per_capita_rate * season_modifier

    # Theft/raiding
    supply -= raid_losses(commodity)
      # If bandits raided, supply drops sharply

    # Decay
    supply *= decay_rate(commodity)
      # Perishables (food, herbs) decay faster than durables (iron, weapons)
      # food: 0.95/day, herbs: 0.97/day, iron: 0.999/day

    # Clamp
    supply = clamp(supply, 0.0, 200.0)
```

**Demand changes:**
```
Each game-day:
  For each commodity in each settlement:

    # Base demand from population
    demand = base_demand(commodity, settlement.population)

    # Event-driven demand spikes
    if "military_buildup" in settlement.active_events:
      demand["weapons"] += 50
      demand["iron"] += 30

    if "festival" in settlement.active_events:
      demand["food"] += 40
      demand["ale"] += 60
      demand["luxury"] += 20

    if "disease_outbreak" in settlement.active_events:
      demand["herbs"] += 80

    # NPC goal-driven demand
    for npc in settlement.npcs:
      demand += npc.get_demand_contributions()
      # Gregor's demand for weapons is high (bandit supply orders)
      # Aldric's demand for weapons is rising (stockpiling for resistance)

    # Seasonal demand
    demand *= seasonal_modifier(commodity, current_season)
      # Winter: food demand +30%, firewood demand +50%
      # Harvest: grain supply +100%, labor demand +40%
```

### 4.5 Trade Routes

Trade routes are the arteries of the economy. When they are disrupted, settlements starve.

```
TradeRoute:
  route_id: String               # "thornhaven_millhaven_north"
  endpoints: Array[String]       # ["thornhaven", "millhaven"]

  # State
  safety: float                  # 0.0-1.0 (1.0 = perfectly safe)
  traffic: float                 # 0.0-1.0 (1.0 = maximum trade volume)
  travel_time_days: int          # Normal travel time between endpoints

  # What flows along this route
  commodities: Dictionary        # {commodity_id: volume_per_day}
  # e.g., {"iron": 5, "grain": 10, "luxury": 2, "ale": 3}

  # Threats
  threats: Array[Dictionary]     # [{source: "iron_hollow_gang", severity: 0.6, type: "bandit_raids"}]

  # Modifiers
  is_blocked: bool               # Completely impassable
  blockage_reason: String        # "bridge_destroyed", "army_siege", "winter_snow"
```

**Thornhaven-Millhaven North Route (at game start):**
- safety: 0.5 (bandits are active but not fully blocking)
- traffic: 0.6 (some merchants still brave it)
- commodities: {"iron": 5, "grain": 8, "luxury": 1, "ale": 2, "tools": 3}
- threats: [{source: "iron_hollow_gang", severity: 0.5, type: "bandit_raids"}]

**How trade route safety changes:**
- Bandit faction strength increases: safety decreases
- Peacekeeper patrols increase: safety increases
- Player escorts a merchant caravan: temporary safety boost
- Major bandit defeat: safety jumps significantly
- Bridge destroyed: route blocked entirely

**Economic impact of route disruption:**
When the Thornhaven-Millhaven route safety drops from 0.5 to 0.2:
- Iron supply to Thornhaven drops by 60%. Bjorn cannot get enough ore. Weapon production halves.
- Grain imports drop. Food prices rise 30-50%.
- Luxury goods vanish. No new wine for Mira's tavern.
- This creates a RippleEvent with category "economic" that propagates to affect NPC behavior.

### 4.6 Multi-Settlement Economics

Each settlement is a node in the economic graph. Trade routes are edges. The simulation runs per-settlement with trade flows connecting them.

**Thornhaven** (village, population ~150):
- Produces: grain (moderate), timber (good), herbs (small)
- Needs: iron (no mines), luxury goods, specialty tools
- Economy type: Subsistence + light trade
- Economic health: Declining (bandit pressure)

**Millhaven** (town, population ~800):
- Produces: iron (mines nearby), tools (guild workshops), ale (breweries)
- Needs: grain (urban population), timber, leather
- Economy type: Industrial + trade hub
- Economic health: Stable but concerned about trade route safety

**Capital City** (city, population ~5000+, Tier 2/3 simulation):
- Produces: luxury goods, military supplies, governance
- Needs: raw materials from everywhere
- Economy type: Imperial hub
- Sets monetary policy, tax rates for the region

**Iron Hollow** (bandit camp, population ~30-50):
- Produces: nothing legitimate
- Needs: weapons, food, supplies (obtained through theft and Gregor's deal)
- Economy type: Parasitic
- Has a black market for stolen goods

**Economic flow at game start:**
```
Millhaven ─── iron, tools, ale ──→ Thornhaven ─── grain, timber ──→ Millhaven
    │                                    ↑
    │                                    │ (diverted)
    └── (some goods never arrive) ──→ Iron Hollow (bandits steal from route)
                                         ↑
                                    Gregor ── weapons, intel, supplies ──→ Iron Hollow
```

---

## 5. NPC Economic Behavior by Tier and Class

### 5.1 Tier 0: Full Economic Reasoning (Story NPCs)

Tier 0 NPCs make economic decisions through their Claude agent loop. Their `EVALUATE` phase receives economic context:

**Injected into Tier 0 NPC prompts (economic section):**
```
## ECONOMIC SITUATION
Your current gold: {gold}
Your current inventory: {summary of stock}
Items running low: {items below threshold}
Items overstocked: {items above threshold}
Recent price trends: {commodity changes this week}
Trade route status: {safety of routes you depend on}
Your daily expenses: {expenses}
Days of operating capital remaining: {gold / daily_expenses}

## YOUR ECONOMIC GOALS
{From NPC personality and current agenda}
```

**Gregor's economic behavior:**
- Prices goods to maximize profit (seller_markup: 1.3)
- Maintains a hidden reserve of weapons for bandit delivery
- When trade route is disrupted, he adjusts prices upward (he knows why it is disrupted but blames "the times")
- Saves aggressively for Elena's escape fund (gold target: 1000)
- If player buys frequently and at good prices, Gregor's Claude agent may offer discounts (relationship building + profit motive)
- If confronted about prices: "These are dangerous times. Costs go up for everyone."

**Bjorn's economic behavior:**
- Prices fairly (seller_markup: 1.1)
- Crafts what he has materials for; when iron is scarce, he makes more wooden-handled tools
- At high trust, he saves his best work for the player
- After learning the truth about his weapons: may refuse to sell weapons entirely until the situation is resolved, or channel his anger into arming the resistance
- His Claude agent reasons about this: "I need to make a living, but I can't stomach the thought that my swords might end up in bandit hands again"

**Mira's economic behavior:**
- Prices to keep the tavern running (barely profitable)
- As The Boss, she actually controls far more wealth than she shows
- She uses the tavern's declining state as cover: "Business has been terrible since the road became dangerous"
- If pushed on prices: she will lower them slightly for someone she is cultivating as an asset
- Her hidden economic power is a discoverable secret

### 5.2 Tier 1: Rule-Based Economic Behavior (Ambient NPCs)

Tier 1 NPCs follow simpler economic rules processed by their Haiku agent loop:

```
Tier1EconomicBehavior:
  npc_id: String
  occupation_type: String          # "baker", "farmer", "guard", "herbalist"

  # Pricing rules
  pricing_strategy: String         # "fixed_margin", "market_rate", "desperation"
  base_margin: float               # 1.1 for fair, 1.3 for greedy, 0.9 for desperate

  # Stock behavior
  restock_day: String              # "daily", "weekly", "when_supply_arrives"
  crafts_own_goods: bool           # Baker bakes, herbalist grows

  # Reactions to economic events
  price_sensitivity: float         # How quickly they adjust prices to supply changes
  hoarding_threshold: float        # At what supply level they stop selling (keep for self)

  # Dialogue triggers
  complain_threshold: float        # Prosperity level below which they complain about economy
  celebrate_threshold: float       # Prosperity level above which they mention good times
```

**Baker Hilda (Tier 1 example):**
- Buys grain from market. Bakes bread. Sells bread.
- When grain supply drops: bread price rises. She mentions it: "Grain's getting dear with the roads so dangerous. Price has to go up, I'm afraid."
- When grain supply is critically low: she stops selling and hoards for her family. "Sorry, love, got to feed my own before I can sell."
- Her Haiku agent decides these responses based on the economic context injected into her prompt.

### 5.3 Tier 2: Abstract Economic Actions (Off-Screen NPCs)

Tier 2 NPCs take one economic action per game-day as part of their abstract agent loop:

```
Tier2EconomicAction:
  npc_id: String                   # "mayor_aldwin_millhaven"
  action: String                   # "adjust_tariffs", "fund_militia", "subsidize_trade", "hoard_resources"
  target: String                   # What the action affects
  magnitude: float                 # How significant
```

**Mayor Aldwin of Millhaven (Tier 2):**
- If trade route safety < 0.3: agenda shifts to "fund_militia" (increases iron demand in Millhaven, decreases exports to Thornhaven)
- If Thornhaven merchants petition for help: may reduce tariffs to encourage trade flow
- These decisions propagate as RippleEvents with economic effects

### 5.4 Tier 3: Macro-Economic Effects (Factions)

Factions affect economics through their strategic actions:

**Iron Hollow Gang:**
- `active_effects: ["trade_disrupted"]` directly reduces trade route safety
- When strength > 60: more aggressive raids, further supply disruption
- When strength < 30: raids decrease, trade route recovers
- Stolen goods enter the black market (supply of cheap weapons/tools at Iron Hollow)

**Millhaven Merchant Guild (potential Tier 3 faction):**
- Controls iron pricing regionally
- If they decide to embargo Thornhaven (political pressure): iron supply drops to zero
- Guild decisions are one-step strategic choices by Haiku each game-day

### 5.5 Social Class and Economic Role

| Social Class | Economic Role | Price Sensitivity | Economic Power |
|-------------|--------------|-------------------|---------------|
| **Nobility** | Set taxes, control land, fund projects | Low (wealthy) | High (policy) |
| **Merchants** | Buy/sell, establish routes, accumulate | Medium (profit-driven) | Medium-High (capital) |
| **Tradespeople** | Craft goods, provide services | Medium (need customers) | Medium (skills) |
| **Peasants** | Farm, labor, buy essentials | Very High (survival) | Low (subsistence) |
| **Bandits** | Steal, extort, fence goods | Low (take what they want) | Variable (strength-based) |
| **Peacekeepers** | Funded by taxes, buy equipment | N/A (salaried) | Low (budget-constrained) |

**How social class intersects with the simulation:**

Peasant NPCs (Tier 1) are the canaries in the coal mine. When food prices rise 30%, the player notices because peasants start complaining, eating less, and looking desperate. This is not scripted -- it is the Tier 1 Haiku agent reacting to injected economic context.

Nobility (if present, Tier 2) responds to economic pressure by raising taxes or funding responses. These decisions cascade through the system.

Merchants adjust prices and seek new trade opportunities. When one route is blocked, a merchant might propose a new one (quest hook).

---

## 6. Shop and Trade Interface

### 6.1 Conversation-First Trading

The player does not open a "shop menu" by pressing E near a merchant. Trading begins through dialogue.

**Flow:**
1. Player talks to Gregor: "What do you have for sale?"
2. Gregor's Claude agent responds with available goods, personalized by relationship: "Ah, good to see you! I've got some fine rope, a couple of lanterns, and -- between us -- a rather nice dagger I acquired recently. What catches your eye?"
3. The trade UI opens alongside the dialogue, showing Gregor's available inventory with prices.
4. Player can browse, buy, sell, and continue talking.
5. Gregor comments on purchases: "Planning a trip? That's a lot of rope." (His Claude agent generates contextual responses.)

### 6.2 Trade UI Layout

```
┌─────────────────────────────────────────────────────────┐
│  [NPC Portrait]  Gregor's General Goods                 │
│  "What can I interest you in today?"                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────── FOR SALE ────────┐  ┌──── YOUR GOODS ─────┐ │
│  │ Iron Dagger      45s [1] │  │ Wolf Pelt      12s   │ │
│  │ Rope (50ft)      8s  [3] │  │ Iron Ore       20s   │ │
│  │ Lantern          15s [2] │  │ Healing Herb   5s    │ │
│  │ Travel Rations   5s  [8] │  │ Bread          2s    │ │
│  │ Healing Potion   25s [1] │  │                      │ │
│  │                          │  │                      │ │
│  └──────────────────────────┘  └──────────────────────┘ │
│                                                         │
│  Your Gold: 120s          Gregor's Gold: 487s           │
│  [Buy Selected]  [Sell Selected]  [Haggle]  [Close]     │
│                                                         │
│  ─── Dialogue ──────────────────────────────────────    │
│  Gregor: "That dagger? Fine steel. Won't find better    │
│  this side of Millhaven. 45 silver, fair price."        │
│  [Response options generated by Claude]                  │
└─────────────────────────────────────────────────────────┘
```

**Key design notes:**
- Prices are **dynamic** -- they reflect the pricing formula in real time
- Stock is **real** -- what Gregor has is what he has. If he sold his last rope yesterday, it is not there.
- The `[quantity]` shows how many are available
- "YOUR GOODS" shows what the NPC is willing to buy (not everything -- a tavern keeper does not want iron ore)

### 6.3 Haggling System

Haggling is not a minigame. It is a dialogue-driven negotiation powered by the NPC's Claude agent.

**Mechanic:**
When the player clicks [Haggle] or says "Can you do better on the price?", the NPC's Claude agent receives:

```
[HAGGLE REQUEST]
The player wants to buy: {item} at listed price: {price}
Your minimum acceptable price: {floor_price}
Your relationship with player: Trust {trust}, Respect {respect}
Your current financial state: {gold, expenses, urgency}
Their haggling history: {have they haggled before? did they buy at full price last time?}

Respond in character. You may:
- Lower the price if relationship is good or you're desperate for the sale
- Hold firm if you think the price is fair
- Counter-offer with a bundle deal
- Refuse if they're being unreasonable
- Get offended if they lowball you
```

The `floor_price` is calculated:
```
floor_price = base_value * supply_demand_modifier * (1.0 + tax_modifier) * minimum_margin
Where minimum_margin:
  Gregor: 0.9 (will go to cost for a good customer)
  Bjorn: 1.0 (won't sell below cost)
  Black market: 1.2 (always a premium)
```

**Haggling outcomes:**
- NPC might lower price 5-20% for a trusted customer
- NPC might offer a bundle: "Tell you what, buy the dagger AND the rope, I'll knock 10 silver off"
- NPC might get annoyed if player haggles too aggressively (trust -2)
- Some NPCs never haggle (Bjorn: "My prices are fair. Take it or leave it.")

### 6.4 Barter System

Not every transaction requires gold. NPCs can accept trade of goods they need.

**Mechanic:**
If the player offers an item instead of gold, the NPC evaluates:
- Do I need this item? (Check NPC demand/restock needs)
- What is it worth to me? (May differ from market value -- Bjorn values iron ore more than its market price)
- Is the trade fair? (NPC's Claude agent evaluates)

**Example:** Player to Bjorn: "I don't have enough gold, but I found some iron ore in the hills. Would you take it for the sword?"
Bjorn's agent: Checks his iron supply (low, trade route disrupted). Iron ore is worth 20s on the market but worth 30s to him right now. He agrees, maybe even offers a bonus: "Good ore! Tell you what, bring me more and I'll forge you something special."

### 6.5 Black Market

The Iron Hollow bandit camp has an informal market. Stolen goods, illegal items, and information trade here.

**Access requirements:**
- Must be able to reach Iron Hollow (the route must be known)
- Must not be actively hostile with bandit faction (reputation > -30)
- OR must be escorted by Varn (through quest progression)

**Black market characteristics:**
- Prices: Higher for weapons and tools (risk premium). Lower for stolen goods (fencing).
- Inventory: Stolen merchant goods, weapons (including Bjorn's), contraband
- No tax applied
- Purchases here may carry risk: if Aldric sees you with stolen goods, reputation with peacekeepers drops
- Some items only available here (poison, lockpicks, bandit intelligence)

### 6.6 Trust-Gated Inventory

NPCs do not show everything to everyone. Trust unlocks access to better goods:

| Trust Level | Gregor | Bjorn | Mira | Black Market |
|------------|--------|-------|------|-------------|
| < 0 | Refuses service | Basic tools only | Watered ale | Entrance denied |
| 0-20 | Basic goods | Common weapons, tools | Food, ale | Basic stolen goods |
| 20-50 | Full standard stock | Full stock, common quality | Full menu, rumors | Full stolen inventory |
| 50-70 | Hints at "special items" | Fine quality available | Good wine, real information | Special orders available |
| > 70 | Secret stash access | Superior/Masterwork, teaches crafting | Specialty drinks, deep intel | Direct deals with leadership |

---

## 7. Integration with Existing Systems

### 7.1 Integration with Ripple Effect Engine

Economic events generate RippleEvents. The existing ripple engine (NPC_EXISTENCE_AND_INFLUENCE_SYSTEM.md Section 2) already supports `economy_change` as an effect type. This design makes that concrete.

**Economic RippleEvent examples:**

```
# When trade route safety drops below 0.3
RippleEvent:
  id: "ripple_trade_route_critical"
  category: "economic"
  origin_location: "thornhaven"
  intensity: 0.7
  effects:
    - scope: "local"
      effect_type: "economy_change"
      target: "thornhaven"
      parameters: {supply_modifier: {iron: -40, grain: -20, luxury: -80}}
    - scope: "local"
      effect_type: "info_packet"
      target: "all_local_npcs"
      parameters: {content: "No merchants on the north road for a week now. Prices are climbing."}
    - scope: "regional"
      effect_type: "economy_change"
      target: "millhaven"
      parameters: {demand_modifier: {grain: -10}, trade_volume: -20}

# When Gregor is exposed and arrested
RippleEvent:
  id: "ripple_gregor_arrested_economic"
  category: "economic"
  origin_location: "thornhaven"
  intensity: 0.8
  effects:
    - scope: "local"
      effect_type: "economy_change"
      target: "thornhaven"
      parameters: {supply_modifier: {general_goods: -60}, note: "main shop closed"}
    - scope: "local"
      effect_type: "npc_reaction"
      target: "all_merchants"
      parameters: {behavior: "price_gouge_or_fill_vacuum"}
    - scope: "regional"
      effect_type: "info_packet"
      parameters: {content: "Thornhaven's merchant was arrested. The village has no general store now."}
```

### 7.2 Integration with NPC Agent Loop

The agent loop (AUTONOMOUS_NPC_AGENTS.md Section: Agent Loop) gains economic awareness:

**PERCEIVE phase additions:**
- Current prices at the NPC's settlement
- NPC's own inventory and gold
- Trade route status
- Recent economic events

**EVALUATE phase additions:**
- "Am I running low on operating capital?" (survival goal)
- "Are there economic opportunities?" (profit goal)
- "Should I adjust my prices?" (adaptation)
- "Do I need to find a new supplier?" (strategic)

**EXECUTE phase additions:**
- `economic_action`: buy, sell, adjust_price, hoard, seek_trade, close_shop
- These actions update the NPCInventory and fire EventBus signals

**REFLECT phase additions:**
- "The trade route disruption is hurting me. I need to find alternatives."
- "The player bought a lot of weapons. Why? Are they preparing for something?"

### 7.3 Integration with Story Threads

Economic pressure amplifies narrative tension. This is not a separate system -- it is a natural consequence of the simulation feeding into the same thread tension calculations from EMERGENT_NARRATIVE_SYSTEM.md.

**Thread 1 (Merchant's Bargain) + Economics:**
- Gregor's wealth is visible evidence. His shop is stocked when others suffer.
- If the player tracks Gregor's purchasing patterns (he buys weapons in bulk), they can detect the conspiracy economically.
- Exposing Gregor creates a supply vacuum (his shop closes). This is a real economic consequence that ripples through the village.

**Thread 4 (Unwitting Accomplice) + Economics:**
- Bjorn's weapon orders from Gregor are trackable. The player can notice: "Gregor orders 10 swords a month but only sells 2."
- If iron supply drops, Bjorn has to choose: fill Gregor's order or make tools for the village.
- This economic pressure forces character-revealing decisions.

**Thread 7 (Bandit Expansion) + Economics:**
- Bandit raids directly reduce trade route safety.
- The economic consequences (price spikes, shortages) create urgency that the player feels.
- This is not abstract -- the player pays 3x for bread and hears peasants complain.

**Thread 8 (Dying Trade Route) + Economics:**
- This thread IS the economic system. The trade route's health is the thread's tension.
- Emergent quests trigger from economic thresholds: "Escort a merchant" when route safety < 0.4, "Find alternate route" when route is blocked.

### 7.4 Integration with EventBus

New signals added to EventBus:

```gdscript
# Economic signals
signal price_changed(settlement_id: String, commodity_id: String, old_price: float, new_price: float)
signal supply_changed(settlement_id: String, commodity_id: String, old_supply: float, new_supply: float)
signal trade_route_status_changed(route_id: String, old_safety: float, new_safety: float)
signal npc_trade_completed(buyer_id: String, seller_id: String, item_id: String, price: int)
signal shop_opened(npc_id: String, location: String)
signal shop_closed(npc_id: String, location: String, reason: String)
signal economic_crisis(settlement_id: String, crisis_type: String, severity: float)
signal item_crafted(crafter_id: String, item_id: String, quality: String)
signal inventory_changed(entity_id: String, item_id: String, delta: int)
```

### 7.5 Integration with WorldKnowledge

WorldKnowledge.world_facts.establishments gains economic data:

```gdscript
"gregor_shop": {
    "name": "Gregor's General Goods",
    "type": "shop",
    "owner": "gregor_merchant_001",
    "location": "market_square",
    "description": "A well-stocked general store selling tools, supplies, and everyday items",
    "goods": ["tools", "rope", "lanterns", "basic supplies"],
    "reputation": "reliable and fairly priced",
    # NEW economic fields:
    "economic_role": "general_merchant",
    "commodities_sold": ["tools", "food", "general_goods"],
    "commodities_bought": ["weapons", "materials", "crafted_goods"],
    "price_reputation": "fair",  # "cheap", "fair", "expensive", "gouging"
    "is_open": true
}
```

### 7.6 Integration with Evidence System

The existing `StoryItem` class (scripts/world/story_item.gd) handles one-time evidence discovery. The economics system extends this with **tradeable evidence** -- items that exist in inventories and can be shown to NPCs during dialogue.

When the player has an evidence item and talks to an NPC listed in `presentable_to`, the dialogue UI adds a `[Show Evidence]` option. Selecting it triggers the evidence presentation flow (Section 1.4).

---

## 8. Economic Actions Drive Narrative (Concrete Examples)

### Example 1: The Grain Shortage

**Setup:** Bandits raid a grain shipment (Tier 3 faction action).
**Immediate:** Thornhaven grain supply drops 40%. EconomyManager fires supply_changed signal.
**Day 1:** Baker Hilda (Tier 1) receives economic context: grain supply critical. Her Haiku agent decides to raise bread prices 50% and limit sales. She complains to customers.
**Day 2:** Peasant NPCs (Tier 1) react: they can barely afford bread. Behavior flags shift to `anxious`. Their dialogue templates activate hunger/complaint variants.
**Day 3:** Gregor (Tier 0) notices the shortage. His Claude agent reasons: "I have some grain reserves I was holding for the bandit shipment. If I sell them now, I profit and look generous. But the bandits expect their cut." He decides based on his goals (protect Elena vs. maintain arrangement).
**Day 4:** Mira (Tier 0) sees her tavern food costs spike. She can absorb it (she has hidden wealth) but plays it up: "I may have to close the kitchen. Can't afford grain at these prices." (Cover story. She is testing who responds and how.)
**Day 5:** If the player has not intervened, Mathias (Tier 0) raises the issue at a council meeting. This creates a quest emergence condition.
**Player involvement:** The player can escort a grain shipment, negotiate with Millhaven for emergency supplies, confront the bandits, or even discover Gregor's hidden grain cache.

### Example 2: Bjorn's Dilemma

**Setup:** Iron supply drops (trade route disrupted). Gregor places his monthly weapon order.
**The tension:** Bjorn has enough iron for either Gregor's weapon order OR the tools the village needs, not both.
**Bjorn's Tier 0 reasoning:** His Claude agent receives: "You have 15 units of iron. Gregor wants 8 swords (requires 12 iron). The village needs tools and repairs (requires 10 iron). You cannot fill both orders."
**Possible outcomes (Claude decides):**
- If Bjorn trusts Gregor (default): he fills Gregor's order first, village goes without. "Gregor's a steady customer. The village will have to wait."
- If Bjorn has learned the truth: he refuses Gregor's order entirely. "Not one more blade for that traitor." This disrupts the bandit supply chain (Gregor cannot fulfill his deal).
- If the player brings Bjorn iron ore: Bjorn can fill both orders. Relationship boost. "You're a lifesaver. This iron is good quality too."
**Narrative consequence:** If Bjorn refuses Gregor, Gregor panics. His Claude agent reasons about alternatives. He might try to buy weapons from Millhaven, approach another smith, or accelerate his plan to flee with Elena.

### Example 3: The Price of Exposure

**Setup:** Gregor is exposed and arrested/flees.
**Immediate economic shock:**
- Gregor's General Goods closes. Supply of general goods in Thornhaven drops to near zero.
- Gregor's gold (which was flowing to Thornhaven's economy through purchases) stops.
- The weapons pipeline to bandits is severed.
**Day 1-3:** Village enters supply crisis. No general store. Prices spike on all remaining goods.
**Day 3-5:** Ripple reaches Iron Hollow. Bandits receive no weapons. Their `resources` attribute drops. Their Tier 3 strategic action may be "raid_supply_directly" (more aggressive) or "negotiate_alternate_source" (seek new informant).
**Day 5-10:** A Tier 1 NPC may attempt to fill the vacuum -- maybe a farmer starts selling goods from his home, or a Millhaven merchant sees an opportunity. This is either rule-generated (Tier 1 economic behavior) or Claude-reasoned (if a Tier 0 NPC takes interest).
**Player opportunity:** The player could set up a supply line, recruit a new merchant, or negotiate with Millhaven for aid. These are emergent quests driven by economic conditions.

### Example 4: Black Market Discovery

**Setup:** Player explores Iron Hollow and discovers the black market.
**What they find:** Goods at unusual prices. Some items clearly stolen (merchant stamps, village markings). Weapons with Bjorn's maker mark.
**Economic intelligence:** The player now understands the economic flow of the conspiracy. They can trace supply chains backward.
**Player choice:**
- Buy from the black market (pragmatic but morally grey; funds bandits)
- Report to Aldric (provides evidence for resistance)
- Use it as leverage with Gregor ("I saw your goods at Iron Hollow")
- Trade with bandits to build faction trust (Iron Crown path)

---

## 9. Currency and Monetary System

### 9.1 Currency

The primary currency is the **silver coin** (abbreviated "s" in UI, referred to as "silver" or "coin" in dialogue).

| Denomination | Value | Physical Form | Usage |
|-------------|-------|---------------|-------|
| Copper bit | 0.1s | Small copper coin | Peasant transactions, tips |
| Silver coin | 1s | Standard silver coin | Most transactions |
| Gold mark | 10s | Stamped gold coin | Large purchases, savings |
| Crown note | 100s | Paper note from Capital | Large-scale trade, rare |

Most NPC dialogue refers to silver coins. Gregor's secret stash might be described as "a pouch of gold marks" (significant wealth). The Capital uses crown notes (paper currency) which Thornhaven villagers may distrust.

### 9.2 Barter Economy

In disrupted conditions (trade route blocked, no merchant), Thornhaven may revert to barter. NPCs accept goods directly instead of currency. This is not a separate system -- it is what happens when the currency-based pricing formula fails because no one has enough coin.

The player experiences this through dialogue: "Gold's no use when there's nothing to buy. Got any grain? I'll trade you firewood."

---

## 10. Implementation Plan (Phased)

### Phase A: Foundation Items and Inventory (Priority: P0)

**Goal:** Items exist, player can carry them, NPCs have inventories.

**Deliverables:**
1. `ItemData` Resource class (`scripts/resources/item_data.gd`)
2. `PlayerInventory` system (`scripts/inventory/player_inventory.gd`)
3. `NPCInventory` component added to BaseNPC (`scripts/inventory/npc_inventory.gd`)
4. `ContainerInventory` for world containers (`scripts/inventory/container_inventory.gd`)
5. Basic inventory UI (list view, weight display, item inspection)
6. Item pickup/drop mechanics
7. Initial item definitions: 20-30 core items (basic weapons, materials, evidence items, consumables)
8. Evidence items: Ledger, marked weapon, key story items

**Integration points:**
- EventBus signals for inventory changes
- WorldState save/load includes inventories
- StoryItem (existing) can grant items on discovery

**Estimated effort:** 2-3 weeks

### Phase B: Basic Trading (Priority: P0)

**Goal:** Player can buy from and sell to NPCs with dynamic prices.

**Deliverables:**
1. `EconomyManager` singleton (simplified: single settlement, static supply/demand)
2. Pricing formula implementation (base_value * modifiers)
3. Trade UI (buy/sell interface alongside dialogue)
4. NPC purchase/sale logic in BaseNPC
5. Relationship-based price modifiers
6. Trust-gated inventory (NPCs show/hide items based on trust)
7. Gold tracking for player and NPCs

**Integration points:**
- NPC Claude prompts include inventory context
- Trade transactions fire EventBus signals
- WorldEvents logs commerce events

**Estimated effort:** 2-3 weeks

### Phase C: Evidence Presentation (Priority: P1)

**Goal:** Player can show evidence items to NPCs and get emergent reactions.

**Deliverables:**
1. Evidence presentation mechanic in dialogue UI
2. Evidence context injection into NPC Claude prompts
3. NPC reaction handling (flag setting, relationship changes, quest advancement)
4. 5-8 evidence items with full `presentable_to` and `evidence_tags`

**Integration points:**
- Quest system (presenting evidence can complete quest objectives)
- Story threads (evidence presentation changes thread tension)
- WorldState flags (evidence triggers narrative flags)

**Estimated effort:** 1-2 weeks

### Phase D: Crafting System (Priority: P1)

**Goal:** Player can request crafting from NPCs, quality system works.

**Deliverables:**
1. `Recipe` Resource class (`scripts/crafting/recipe.gd`)
2. `CraftingManager` system (`scripts/crafting/crafting_manager.gd`)
3. Crafting station interaction (approach Bjorn's forge, initiate crafting via dialogue)
4. Quality determination formula
5. Recipe discovery (innate + NPC-taught)
6. 15-20 recipes (weapons, tools, consumables, basic armor)
7. Campfire crafting (player-solo basics)
8. Material consumption and item creation

**Integration points:**
- NPC trust gates which recipes are teachable
- NPC inventories provide/consume materials
- Crafting events integrate with NPC memory (Bjorn remembers what he made for you)

**Estimated effort:** 2-3 weeks

### Phase E: Dynamic Economy (Priority: P2)

**Goal:** Supply and demand fluctuate based on world events. Prices respond to simulation.

**Deliverables:**
1. Full `EconomyManager` with per-settlement economies
2. Commodity system (supply/demand tracking)
3. Trade routes with safety/traffic simulation
4. Economic modifiers from events (bandit raids, festivals, seasons)
5. NPC economic behavior rules (Tier 1) and prompt injection (Tier 0)
6. Price history tracking
7. Economic RippleEvent generation

**Integration points:**
- Ripple engine `economy_change` effect type fully implemented
- NPC agent loop includes economic PERCEIVE/EVALUATE data
- Trade route safety connected to faction strength

**Estimated effort:** 3-4 weeks

### Phase F: Multi-Settlement and Advanced Features (Priority: P3)

**Goal:** Multiple settlements with interconnected economies. Black market. Haggling.

**Deliverables:**
1. Millhaven settlement economy (even if off-screen)
2. Capital settlement economy (abstract, Tier 2/3)
3. Iron Hollow black market
4. Inter-settlement trade flow simulation
5. Haggling system (Claude-powered negotiation)
6. Barter system
7. NPC-to-NPC trading (autonomous)
8. Economic crisis events (famine, embargo, trade war)
9. Durability and item degradation
10. Seasonal economic cycles

**Integration points:**
- Tier 2 NPC economic actions
- Tier 3 faction economic effects
- Off-screen simulation (WorldSimulation)
- Multiple settlement travel (when implemented)

**Estimated effort:** 4-6 weeks

---

## Appendix A: Godot 4 Implementation Notes

### Resource Architecture

All item and recipe definitions are Godot `Resource` types (.tres files), consistent with the existing pattern used for `NPCPersonality`, `LocationData`, and `MemoryConfig`. This means:
- Items can be created and edited in the Godot Inspector
- Items serialize cleanly for save/load via `ResourceSaver`/`ResourceLoader`
- Items can be referenced by path or preloaded

### Autoload Singletons

The following new autoloads will be registered in `project.godot`:

```
EconomyManager="*res://scripts/economy/economy_manager.gd"
PlayerInventory="*res://scripts/inventory/player_inventory.gd"
CraftingManager="*res://scripts/crafting/crafting_manager.gd"
```

### File Structure

```
scripts/
  economy/
    economy_manager.gd          # Autoload: settlement economies, trade routes, pricing
    settlement_economy.gd       # Per-settlement economic state
    trade_route.gd              # Trade route data and simulation
    commodity.gd                # Commodity definitions
    price_calculator.gd         # Pricing formula implementation
  inventory/
    player_inventory.gd         # Autoload: player inventory management
    npc_inventory.gd            # Component: NPC inventory (attached to BaseNPC)
    container_inventory.gd      # World container inventories
    inventory_slot.gd           # Single inventory slot (item + quantity)
  crafting/
    crafting_manager.gd         # Autoload: recipe registry, crafting execution
    recipe.gd                   # Recipe Resource definition
    quality_calculator.gd       # Quality determination formula
  resources/
    item_data.gd                # ItemData Resource class (extends existing resources/)
resources/
  items/
    materials/                  # .tres files for each material item
    weapons/                    # .tres files for weapons
    armor/                      # .tres files for armor
    consumables/                # .tres files for consumables
    tools/                      # .tres files for tools
    evidence/                   # .tres files for evidence items
    quest/                      # .tres files for quest items
  recipes/
    smithing/                   # .tres files for forge recipes
    alchemy/                    # .tres files for potion/salve recipes
    cooking/                    # .tres files for food recipes
    campfire/                   # .tres files for basic player recipes
scenes/
  ui/
    inventory_panel.tscn        # Player inventory UI
    trade_panel.tscn            # Buy/sell interface
    crafting_panel.tscn         # Crafting station interface
    item_tooltip.tscn           # Item detail popup
```

### Save/Load

Economic state saves alongside WorldState:

```gdscript
# In EconomyManager
func save() -> Dictionary:
    return {
        "settlement_economies": _serialize_economies(),
        "trade_routes": _serialize_routes(),
        "price_history": price_history
    }

# In PlayerInventory
func save() -> Dictionary:
    return {
        "items": _serialize_items(),
        "gold": gold,
        "known_recipes": known_recipes
    }
```

### Performance Considerations

- The economic simulation tick runs once per game-day (not per frame). With 3-4 settlements and 10 commodities each, this is trivially cheap.
- NPC inventories are only loaded when the NPC is in the active scene. Off-screen NPC inventories are stored as save data.
- Price calculations are memoized per game-day (recalculated only when supply/demand changes).
- The price history array is capped at 30 days per commodity per settlement to prevent unbounded growth.

---

## Appendix B: Narrative Economy Cheat Sheet

Quick reference for how economic systems serve specific story moments:

| Story Moment | Economic System Involved | What the Player Experiences |
|-------------|-------------------------|----------------------------|
| Arriving in Thornhaven | Baseline prices | Gregor's shop is well-stocked. Others less so. First hint. |
| Noticing Gregor's prosperity | Price comparison | His prices are fair but his stock is suspiciously good for a struggling village. |
| Trade route worsens | Supply drop, price spike | Bread costs more. NPCs complain. Tension rises. |
| Finding the ledger | Evidence item | Physical proof that can be presented to NPCs for emergent reactions. |
| Showing ledger to Aldric | Evidence presentation | Claude-powered reaction based on Aldric's personality, goals, and relationship. |
| Bjorn learns the truth | Economic disruption | He stops filling weapon orders. Bandit supply chain breaks. |
| Gregor exposed/arrested | Supply vacuum | His shop closes. Village scrambles. Prices spike further. |
| Escorting merchant caravan | Trade route improvement | Safety improves. Supply increases. Prices stabilize. Villagers thank player. |
| Black market discovery | Alternative trade | Player can trace the stolen goods back to Thornhaven. Economic evidence of conspiracy. |
| Village liberation | Economic recovery | Trade route reopens. Supplies flow. Prices normalize. Prosperity rises. NPCs are hopeful. |
| Iron Crown path | Economic control | Player controls black market. Sets prices. Extorts merchants. Power through economics. |
