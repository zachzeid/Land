extends Node
# WorldKnowledge - Single source of truth for canonical world facts
# Prevents NPCs from hallucinating inconsistent details about locations, establishments, NPCs, etc.
# All AI-generated responses must reference these facts for consistency

## Knowledge scope levels - determines what NPCs know based on location
enum KnowledgeScope {
	INTIMATE,   # Personal details - own home, family, daily routine
	LOCAL,      # Village they live in - establishments, neighbors, local gossip
	REGIONAL,   # Nearby areas - trade routes, neighboring villages (vague)
	DISTANT,    # Far places - rumors only, explicitly uncertain
	UNKNOWN     # Places NPC has never heard of
}

## Location hierarchy - which locations contain which others
var location_hierarchy = {
	"thornhaven": {
		"parent": null,
		"contains": ["market_square", "thornhaven_gregor_shop", "thornhaven_tavern", "thornhaven_blacksmith"],
		"region": "northern_trade_region"
	},
	"market_square": {
		"parent": "thornhaven",
		"contains": [],
		"region": "northern_trade_region"
	},
	"thornhaven_gregor_shop": {
		"parent": "thornhaven",
		"contains": [],
		"region": "northern_trade_region"
	},
	"thornhaven_tavern": {
		"parent": "thornhaven",
		"contains": [],
		"region": "northern_trade_region"
	},
	"thornhaven_blacksmith": {
		"parent": "thornhaven",
		"contains": [],
		"region": "northern_trade_region"
	},
	"kings_castle": {
		"parent": null,
		"contains": ["throne_room", "royal_quarters", "dungeon"],
		"region": "capital_region"
	}
}

## NPC home locations - determines their knowledge scope
var npc_locations = {
	"gregor_merchant_001": "thornhaven_gregor_shop",
	"elena_daughter_001": "thornhaven_gregor_shop",
	"mira_tavern_keeper_001": "thornhaven_tavern",
	"bjorn_blacksmith_001": "thornhaven_blacksmith"
}

## Canonical world facts - these NEVER change unless updated through gameplay events
var world_facts = {
	"locations": {
		"thornhaven": {
			"name": "Thornhaven",
			"type": "village",
			"description": "A small trading village on the northern trade route",
			"population": 150,
			"notable_features": ["market square", "northern gate", "village well"]
		},
		"market_square": {
			"name": "Market Square",
			"type": "area",
			"parent": "thornhaven",
			"description": "The central marketplace where merchants sell their wares",
			"notable_features": ["stone fountain", "merchant stalls", "guard post"]
		}
	},
	
	"establishments": {
		"gregor_shop": {
			"name": "Gregor's General Goods",
			"type": "shop",
			"owner": "gregor_merchant_001",
			"location": "market_square",
			"description": "A well-stocked general store selling tools, supplies, and everyday items",
			"goods": ["tools", "rope", "lanterns", "basic supplies"],
			"reputation": "reliable and fairly priced"
		},
		"tavern": {
			"name": "The Rusty Nail",
			"type": "tavern",
			"owner": "mira_tavern_keeper_001",
			"location": "market_square",
			"description": "The only tavern in Thornhaven, a warm and welcoming place for travelers and locals alike",
			"goods": ["ale", "mead", "hot meals", "rooms for rent"],
			"reputation": "friendly atmosphere, decent food, reasonable prices"
		},
		"blacksmith": {
			"name": "Bjorn's Forge",
			"type": "blacksmith",
			"owner": "bjorn_blacksmith_001",
			"location": "market_square",
			"description": "A sturdy stone smithy where weapons, tools, and metal goods are crafted",
			"goods": ["weapons", "armor repairs", "tools", "horseshoes", "metal goods"],
			"reputation": "quality craftsmanship, honest work"
		}
	},
	
	"npcs": {
		"gregor_merchant_001": {
			"name": "Gregor",
			"full_name": "Gregor Stoneheart",
			"age": 52,
			"occupation": "merchant",
			"family": ["elena_daughter_001"],
			"residence": "Above his shop in Market Square",
			"known_for": "Fair prices and quality goods",
			"backstory": "Has run his shop for 20 years, widowed 5 years ago"
		},
		"elena_daughter_001": {
			"name": "Elena",
			"full_name": "Elena Stoneheart",
			"age": 24,
			"occupation": "shop assistant",
			"family": ["gregor_merchant_001"],
			"residence": "Above father's shop in Market Square",
			"known_for": "Her father's protectiveness",
			"backstory": "Helps run the family business, dreams of adventure"
		},
		"mira_tavern_keeper_001": {
			"name": "Mira",
			"full_name": "Mira Hearthwood",
			"age": 38,
			"occupation": "tavern keeper",
			"family": [],
			"residence": "The Rusty Nail tavern",
			"known_for": "Warm hospitality and knowing everyone's business",
			"backstory": "Inherited the tavern from her late husband 8 years ago, has run it ever since"
		},
		"bjorn_blacksmith_001": {
			"name": "Bjorn",
			"full_name": "Bjorn Ironhand",
			"age": 45,
			"occupation": "blacksmith",
			"family": [],
			"residence": "Behind his forge in Market Square",
			"known_for": "Exceptional metalwork and gruff demeanor",
			"backstory": "Former soldier who settled in Thornhaven after the Border Wars, built his forge from nothing"
		}
	},
	
	"organizations": {
		"village_guard": {
			"name": "Thornhaven Guard",
			"type": "law_enforcement",
			"leader": "captain_marcus",
			"size": 8,
			"jurisdiction": "thornhaven",
			"reputation": "Understaffed but dedicated"
		}
	},
	
	"history": {
		"recent_events": [
			"The harvest festival was held last month and was well-attended",
			"Bandit raids have increased on the northern trade route in recent weeks",
			"A traveling bard performed in the village square three days ago"
		],
		"important_dates": {
			"founding_day": "200 years ago",
			"last_major_conflict": "The Border Wars, 30 years ago"
		}
	}
}

## Determine what knowledge scope an NPC has for a given location
func get_knowledge_scope_for_location(npc_id: String, target_location: String) -> KnowledgeScope:
	var npc_home = npc_locations.get(npc_id, "")
	if npc_home.is_empty():
		return KnowledgeScope.LOCAL  # Default to local knowledge if not specified

	# Get NPC's region
	var npc_region = location_hierarchy.get(npc_home, {}).get("region", "")
	var npc_parent = _get_root_location(npc_home)

	# Get target's region
	var target_region = location_hierarchy.get(target_location, {}).get("region", "")
	var target_parent = _get_root_location(target_location)

	# INTIMATE: NPC's own home/workplace
	if target_location == npc_home:
		return KnowledgeScope.INTIMATE

	# LOCAL: Same village/settlement
	if npc_parent == target_parent or target_location == npc_parent:
		return KnowledgeScope.LOCAL

	# REGIONAL: Same region but different settlement
	if npc_region == target_region and not target_region.is_empty():
		return KnowledgeScope.REGIONAL

	# DISTANT: Different region but exists in world
	if location_hierarchy.has(target_location):
		return KnowledgeScope.DISTANT

	# UNKNOWN: Not in our world data
	return KnowledgeScope.UNKNOWN

## Get root location (e.g., thornhaven_gregor_shop -> thornhaven)
func _get_root_location(location_id: String) -> String:
	var current = location_id
	while location_hierarchy.has(current):
		var parent = location_hierarchy[current].get("parent")
		if parent == null or parent.is_empty():
			return current
		current = parent
	return location_id

## Get all world facts relevant to an NPC's context with GEOGRAPHIC SCOPING
## Returns formatted string for injection into system prompt
func get_world_facts_for_npc(npc_id: String) -> String:
	var facts = ""

	# ==========================================================================
	# CRITICAL ANTI-HALLUCINATION HEADER
	# ==========================================================================
	facts += "## ⚠️ STRICT WORLD KNOWLEDGE RULES ⚠️\n\n"
	facts += "You MUST follow these rules when discussing the world:\n\n"
	facts += "1. **ONLY use names/places listed below** - If a place isn't listed, you DON'T KNOW IT\n"
	facts += "2. **NEVER invent establishment names** - No 'Weary Wanderer', 'Golden Goose', etc.\n"
	facts += "3. **When uncertain, say so** - 'I've heard rumors...' or 'I don't know that place'\n"
	facts += "4. **Your knowledge is LIMITED** - You only know your village well. Distant places are rumors.\n\n"
	facts += "---\n\n"

	# ==========================================================================
	# INTIMATE KNOWLEDGE: About the NPC themselves
	# ==========================================================================
	if world_facts.npcs.has(npc_id):
		var npc_data = world_facts.npcs[npc_id]
		facts += "## YOUR IDENTITY (You know this perfectly)\n\n"
		facts += "- **Your Name:** %s\n" % npc_data.full_name
		facts += "- **Age:** %d years old\n" % npc_data.age
		facts += "- **Occupation:** %s\n" % npc_data.occupation
		facts += "- **Where You Live:** %s\n" % npc_data.residence
		facts += "- **Known For:** %s\n" % npc_data.known_for
		facts += "- **Your Story:** %s\n\n" % npc_data.backstory

	# Family members (intimate knowledge)
	var family_ids = world_facts.npcs.get(npc_id, {}).get("family", [])
	if family_ids.size() > 0:
		facts += "## YOUR FAMILY (You know them intimately)\n\n"
		for family_id in family_ids:
			if world_facts.npcs.has(family_id):
				var family_member = world_facts.npcs[family_id]
				facts += "- **%s** - %s. %s\n" % [family_member.full_name, family_member.occupation, family_member.backstory]
		facts += "\n"

	# NPC's own establishment (intimate knowledge)
	for est_id in world_facts.establishments:
		var est = world_facts.establishments[est_id]
		if est.owner == npc_id:
			facts += "## YOUR ESTABLISHMENT (You know every detail)\n\n"
			facts += "- **Name:** \"%s\" ← USE THIS EXACT NAME\n" % est.name
			facts += "- **Type:** %s\n" % est.type
			facts += "- **What You Sell:** %s\n" % ", ".join(est.goods)
			facts += "- **Reputation:** %s\n\n" % est.reputation

	# ==========================================================================
	# LOCAL KNOWLEDGE: The village and its establishments
	# ==========================================================================
	facts += "## YOUR VILLAGE: THORNHAVEN (You know this well)\n\n"
	facts += "Thornhaven is %s with about %d people.\n" % [world_facts.locations.thornhaven.description, world_facts.locations.thornhaven.population]
	facts += "Notable features: %s\n\n" % ", ".join(world_facts.locations.thornhaven.notable_features)

	facts += "### ESTABLISHMENTS IN THORNHAVEN (Use ONLY these names!)\n\n"
	facts += "⚠️ These are the ONLY establishments in Thornhaven. There are NO others.\n\n"
	for est_id in world_facts.establishments:
		var est = world_facts.establishments[est_id]
		var owner_info = ""
		if est.owner != npc_id:
			var owner_name = world_facts.npcs.get(est.owner, {}).get("name", "someone")
			owner_info = " (run by %s)" % owner_name
		facts += "- **\"%s\"** - the %s%s\n" % [est.name, est.type, owner_info]
	facts += "\n⚠️ Do NOT mention any tavern/shop/smithy other than those listed above!\n\n"

	# Other villagers (local knowledge)
	facts += "### PEOPLE YOU KNOW IN THORNHAVEN\n\n"
	for other_npc_id in world_facts.npcs:
		if other_npc_id != npc_id:
			var other = world_facts.npcs[other_npc_id]
			facts += "- **%s** the %s - %s\n" % [other.name, other.occupation, other.known_for]
	facts += "\n"

	# Recent events (local knowledge)
	facts += "### RECENT LOCAL NEWS\n\n"
	for event in world_facts.history.recent_events:
		facts += "- %s\n" % event
	facts += "\n"

	# ==========================================================================
	# KNOWLEDGE BOUNDARIES: What the NPC does NOT know
	# ==========================================================================
	facts += "## WHAT YOU DON'T KNOW (Be honest about this!)\n\n"
	facts += "- You have NEVER been to the King's castle or the capital\n"
	facts += "- You don't know the layout of places outside Thornhaven\n"
	facts += "- Distant places are only RUMORS to you - preface with uncertainty\n"
	facts += "- If asked about unknown places, say: \"I've never been there\" or \"I've only heard stories\"\n\n"

	facts += "---\n\n"
	facts += "⚠️ **FINAL WARNING:** If you mention ANY establishment, person, or place not listed above, you are HALLUCINATING. Stop and use only the provided names.\n\n"

	return facts

## Get appropriate response guidance when NPC is asked about a location
## Returns a string to inject into context about how to respond
func get_location_knowledge_guidance(npc_id: String, asked_location: String) -> String:
	var scope = get_knowledge_scope_for_location(npc_id, asked_location)

	match scope:
		KnowledgeScope.INTIMATE:
			return "You know this place intimately - share detailed, personal knowledge."
		KnowledgeScope.LOCAL:
			return "You know this place well - share confident local knowledge."
		KnowledgeScope.REGIONAL:
			return "You've heard of this place but never visited. Share only vague rumors: 'I've heard that...' or 'They say...'"
		KnowledgeScope.DISTANT:
			return "This is a distant place you know almost nothing about. Say: 'I've only heard stories...' or 'That's far from here, I wouldn't know.'"
		KnowledgeScope.UNKNOWN:
			return "You have NEVER heard of this place. Say: 'I don't know that place' or 'Never heard of it.'"

	return "Respond naturally based on your local knowledge."

## Check if a mentioned name is a valid world entity (for hallucination detection)
func is_valid_establishment_name(name: String) -> bool:
	for est_id in world_facts.establishments:
		if world_facts.establishments[est_id].name.to_lower() == name.to_lower():
			return true
	return false

## Get all valid establishment names (for reference)
func get_all_establishment_names() -> Array:
	var names = []
	for est_id in world_facts.establishments:
		names.append(world_facts.establishments[est_id].name)
	return names

## Update a world fact (for dynamic world changes)
func update_world_fact(category: String, key: String, property: String, value):
	if world_facts.has(category) and world_facts[category].has(key):
		world_facts[category][key][property] = value
		print("[WorldKnowledge] Updated %s.%s.%s = %s" % [category, key, property, str(value)])
	else:
		push_warning("[WorldKnowledge] Attempted to update non-existent fact: %s.%s.%s" % [category, key, property])

## Add a new recent event to history
func add_recent_event(event_description: String):
	world_facts.history.recent_events.push_front(event_description)
	# Keep only last 10 events
	if world_facts.history.recent_events.size() > 10:
		world_facts.history.recent_events.pop_back()
	print("[WorldKnowledge] Added recent event: %s" % event_description)

## Get specific fact for validation/lookup
func get_fact(category: String, key: String, property: String = ""):
	if not world_facts.has(category):
		return null
	if not world_facts[category].has(key):
		return null
	if property.is_empty():
		return world_facts[category][key]
	return world_facts[category][key].get(property, null)
