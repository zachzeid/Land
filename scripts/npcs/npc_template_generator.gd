extends Node
class_name NPCTemplateGenerator
## NPCTemplateGenerator - Generates lightweight Tier 1 NPC profiles from templates
##
## Given a role (baker, guard, farmer, merchant) and a settlement, produces a
## Tier1Profile dictionary with name, personality tags, schedule, inventory,
## gossip tendency, and economic role. No .tres file, no ChromaDB, no full
## personality — just enough data to feel alive.

signal npc_generated(npc_id: String, profile: Dictionary)
signal npc_promoted(npc_id: String, old_tier: int, new_tier: int)

## All generated Tier 1 profiles {npc_id: Tier1Profile dict}
var tier1_profiles: Dictionary = {}

## Interaction counters for promotion tracking {npc_id: int}
var _interaction_counts: Dictionary = {}

## Promotion threshold: disposition + interaction count triggers upgrade
const PROMOTION_DISPOSITION_THRESHOLD := 60.0
const PROMOTION_INTERACTION_THRESHOLD := 5

# =============================================================================
# NAME POOLS — per settlement culture
# =============================================================================

## Name pools grouped by settlement culture
var _name_pools: Dictionary = {
	"thornhaven": {
		"male": ["Aldwin", "Bram", "Cedric", "Dunstan", "Edric", "Finn", "Gareth",
				 "Hale", "Ivo", "Jareth", "Kael", "Lewin", "Marsh", "Norbert",
				 "Oswin", "Phelan", "Ralf", "Soren", "Tomas", "Wulf"],
		"female": ["Ada", "Brenna", "Cora", "Dagna", "Elspeth", "Faye", "Gwen",
				  "Hilda", "Ingrid", "Josslyn", "Kira", "Lotte", "Maren", "Nessa",
				  "Odelina", "Petra", "Rhea", "Sigrid", "Thea", "Wren"],
		"surname": ["Ashford", "Birchwood", "Copperfield", "Duskwater", "Elmgrove",
				   "Fairweather", "Greymoor", "Hedgerow", "Ironwill", "Kettlewell",
				   "Longmead", "Millbrook", "Northgate", "Oakbarrel", "Ploughman"],
	},
	"millhaven": {
		"male": ["Anton", "Bertram", "Conrad", "Darius", "Emeric", "Felix",
				"Gustav", "Henrik", "Ivan", "Julian", "Klaus", "Lorenz",
				"Matthias", "Nikolai", "Otto", "Percival", "Reinhold", "Stefan"],
		"female": ["Annette", "Beatrix", "Clara", "Dorothea", "Elise", "Frieda",
				  "Gretchen", "Helena", "Ilse", "Johanna", "Katarina", "Liselotte",
				  "Margit", "Natalia", "Ottilie", "Paulina", "Rosa", "Sylvie"],
		"surname": ["Brewer", "Coinsworth", "Dockham", "Eastmere", "Fairholm",
				   "Goldmark", "Harborton", "Innskeeper", "Journeyman", "Kessler",
				   "Ledgerwood", "Marketson", "Newbridge", "Oldport", "Pitchford"],
	},
	"iron_hollow": {
		"male": ["Axe", "Blade", "Crow", "Dirk", "Fang", "Grim", "Hook",
				"Jackal", "Knife", "Lash", "Maw", "Nails", "Pike", "Rattler",
				"Scar", "Thorn", "Vex", "Wolf"],
		"female": ["Ash", "Briar", "Cinder", "Dagger", "Edge", "Flint",
				  "Ghost", "Hex", "Ivy", "Jinx", "Kestrel", "Lynx",
				  "Moth", "Needle", "Onyx", "Pyre", "Raven", "Spite"],
		"surname": ["Blackhand", "Cutpurse", "Dreadnought", "Eyeless", "Frostbite",
				   "Gallows", "Hollowbone", "Ironteeth", "Jawbreaker", "Knifetongue"],
	},
	"the_capital": {
		"male": ["Alaric", "Baldric", "Cassius", "Dorian", "Edmund", "Frederick",
				"Godfrey", "Hadrian", "Ignatius", "Justinian", "Leopold", "Maximilian",
				"Norbert", "Oswald", "Reginald", "Sebastian", "Theobald", "Valentine"],
		"female": ["Adrienne", "Bernadette", "Celestine", "Dominique", "Evangeline",
				  "Florence", "Genevieve", "Henrietta", "Isabelle", "Josephine",
				  "Katrina", "Lavinia", "Millicent", "Nicolette", "Ophelia",
				  "Rosalind", "Seraphina", "Vivienne"],
		"surname": ["Ashworth", "Blackwell", "Cromwell", "Davenport", "Everett",
				   "Fairfax", "Grantham", "Highcastle", "Ivory", "Kingsford",
				   "Langford", "Montague", "Northcotte", "Pemberton", "Ravencroft"],
	},
}

## Used names to avoid duplicates
var _used_names: Dictionary = {}

# =============================================================================
# OCCUPATION TEMPLATES
# =============================================================================

## Occupation-based defaults: personality tags, gossip, schedule, inventory, trade
var _occupation_templates: Dictionary = {
	"baker": {
		"personality_tags": ["early_riser", "cheerful", "community_minded"],
		"speaking_style": "warm",
		"gossip_tendency": 0.5,
		"schedule": [
			{"time_period": "dawn", "location": "bakery", "activity": "baking bread"},
			{"time_period": "morning", "location": "market_square", "activity": "selling bread"},
			{"time_period": "noon", "location": "market_square", "activity": "selling bread"},
			{"time_period": "evening", "location": "tavern", "activity": "drinking ale"},
			{"time_period": "night", "location": "home", "activity": "sleeping"},
		],
		"sells": ["bread", "grain"],
		"buys": ["grain", "herbs", "timber"],
		"starting_silver": 30,
		"starting_stock": {"bread": 12, "grain": 5},
		"backstory_templates": [
			"Has baked for the village since {pronoun} was a teenager.",
			"Learned the trade from a traveling baker years ago.",
			"Makes the best rye bread in the region, or so {pronoun} claims.",
		],
	},
	"guard": {
		"personality_tags": ["dutiful", "watchful", "stern"],
		"speaking_style": "formal",
		"gossip_tendency": 0.2,
		"schedule": [
			{"time_period": "dawn", "location": "barracks", "activity": "suiting up"},
			{"time_period": "morning", "location": "gate", "activity": "standing guard"},
			{"time_period": "noon", "location": "market_square", "activity": "patrolling"},
			{"time_period": "evening", "location": "gate", "activity": "standing guard"},
			{"time_period": "night", "location": "barracks", "activity": "resting"},
		],
		"sells": [],
		"buys": ["iron_ore", "leather"],
		"starting_silver": 15,
		"starting_stock": {},
		"backstory_templates": [
			"Joined the guard after the bandit raids started.",
			"A former farmhand who took up the spear when the village needed defenders.",
			"Served in the Border Wars and settled here to keep the peace.",
		],
	},
	"farmer": {
		"personality_tags": ["hardworking", "superstitious", "plain_spoken"],
		"speaking_style": "casual",
		"gossip_tendency": 0.3,
		"schedule": [
			{"time_period": "dawn", "location": "fields", "activity": "tending crops"},
			{"time_period": "morning", "location": "fields", "activity": "tending crops"},
			{"time_period": "noon", "location": "home", "activity": "midday meal"},
			{"time_period": "evening", "location": "market_square", "activity": "selling produce"},
			{"time_period": "night", "location": "home", "activity": "sleeping"},
		],
		"sells": ["grain", "herbs"],
		"buys": ["tools", "rope", "timber"],
		"starting_silver": 20,
		"starting_stock": {"grain": 15, "herbs": 4},
		"backstory_templates": [
			"Works a small plot outside the village walls.",
			"Family has farmed this land for three generations.",
			"Lost half the crop last season to blight. Praying for a better year.",
		],
	},
	"merchant": {
		"personality_tags": ["shrewd", "talkative", "well_traveled"],
		"speaking_style": "confident",
		"gossip_tendency": 0.7,
		"schedule": [
			{"time_period": "dawn", "location": "home", "activity": "preparing wares"},
			{"time_period": "morning", "location": "market_square", "activity": "trading"},
			{"time_period": "noon", "location": "market_square", "activity": "trading"},
			{"time_period": "evening", "location": "tavern", "activity": "making deals"},
			{"time_period": "night", "location": "home", "activity": "counting coins"},
		],
		"sells": ["rope", "leather", "herbs", "iron_ore"],
		"buys": ["grain", "timber", "iron_ore", "leather"],
		"starting_silver": 80,
		"starting_stock": {"rope": 3, "leather": 5, "herbs": 6, "iron_ore": 4},
		"backstory_templates": [
			"Travels between settlements, always looking for a good deal.",
			"Set up shop here after the trade route brought more traffic.",
			"Has connections in Millhaven and knows the market prices well.",
		],
	},
	"herbalist": {
		"personality_tags": ["knowledgeable", "eccentric", "kind"],
		"speaking_style": "warm",
		"gossip_tendency": 0.4,
		"schedule": [
			{"time_period": "dawn", "location": "fields", "activity": "gathering herbs"},
			{"time_period": "morning", "location": "home", "activity": "preparing remedies"},
			{"time_period": "noon", "location": "market_square", "activity": "selling remedies"},
			{"time_period": "evening", "location": "home", "activity": "studying plants"},
			{"time_period": "night", "location": "home", "activity": "sleeping"},
		],
		"sells": ["herbs", "health_potion"],
		"buys": ["herbs", "grain"],
		"starting_silver": 25,
		"starting_stock": {"herbs": 10, "health_potion": 3},
		"backstory_templates": [
			"Learned herbalism from {pronoun_possessive} grandmother.",
			"Came to the village seeking rare mountain herbs.",
			"The only one in town who knows how to treat snakebites.",
		],
	},
	"tavern_worker": {
		"personality_tags": ["sociable", "perceptive", "gossipy"],
		"speaking_style": "casual",
		"gossip_tendency": 0.8,
		"schedule": [
			{"time_period": "dawn", "location": "home", "activity": "sleeping in"},
			{"time_period": "morning", "location": "tavern", "activity": "cleaning up"},
			{"time_period": "noon", "location": "tavern", "activity": "serving food"},
			{"time_period": "evening", "location": "tavern", "activity": "serving drinks"},
			{"time_period": "night", "location": "tavern", "activity": "closing up"},
		],
		"sells": ["ale", "bread"],
		"buys": ["grain", "herbs"],
		"starting_silver": 12,
		"starting_stock": {"ale": 8, "bread": 4},
		"backstory_templates": [
			"Works at the tavern and hears everything worth hearing.",
			"Took the job to pay off a debt. Stayed because the tips are good.",
			"Knows every regular's drink order and most of their secrets.",
		],
	},
	"council_member": {
		"personality_tags": ["political", "cautious", "authoritative"],
		"speaking_style": "formal",
		"gossip_tendency": 0.4,
		"schedule": [
			{"time_period": "dawn", "location": "home", "activity": "reviewing documents"},
			{"time_period": "morning", "location": "council_hall", "activity": "council duties"},
			{"time_period": "noon", "location": "council_hall", "activity": "council duties"},
			{"time_period": "evening", "location": "tavern", "activity": "meeting constituents"},
			{"time_period": "night", "location": "home", "activity": "sleeping"},
		],
		"sells": [],
		"buys": [],
		"starting_silver": 50,
		"starting_stock": {},
		"backstory_templates": [
			"Has served on the council for a decade, always cautious.",
			"Rose to the council through shrewd alliances and patience.",
			"Believes the village needs stronger leadership in troubled times.",
		],
	},
	"blacksmith_apprentice": {
		"personality_tags": ["eager", "clumsy", "ambitious"],
		"speaking_style": "nervous",
		"gossip_tendency": 0.3,
		"schedule": [
			{"time_period": "dawn", "location": "blacksmith", "activity": "stoking the forge"},
			{"time_period": "morning", "location": "blacksmith", "activity": "working metal"},
			{"time_period": "noon", "location": "market_square", "activity": "eating lunch"},
			{"time_period": "evening", "location": "blacksmith", "activity": "cleaning up"},
			{"time_period": "night", "location": "home", "activity": "sleeping"},
		],
		"sells": ["iron_ore"],
		"buys": ["iron_ore", "timber"],
		"starting_silver": 8,
		"starting_stock": {"iron_ore": 3},
		"backstory_templates": [
			"Dreams of forging a blade worthy of a knight someday.",
			"Apprenticed to the blacksmith to escape the family farm.",
			"Not very skilled yet, but makes up for it with enthusiasm.",
		],
	},
	"bandit": {
		"personality_tags": ["aggressive", "cunning", "distrustful"],
		"speaking_style": "cold",
		"gossip_tendency": 0.2,
		"schedule": [
			{"time_period": "dawn", "location": "camp", "activity": "sleeping"},
			{"time_period": "morning", "location": "camp", "activity": "training"},
			{"time_period": "noon", "location": "camp", "activity": "scouting"},
			{"time_period": "evening", "location": "camp", "activity": "drinking"},
			{"time_period": "night", "location": "road", "activity": "ambushing travelers"},
		],
		"sells": ["leather", "iron_ore"],
		"buys": ["ale", "bread", "iron_ore"],
		"starting_silver": 35,
		"starting_stock": {"leather": 3, "hunting_knife": 1},
		"backstory_templates": [
			"Turned to banditry after losing everything in the last drought.",
			"Says it's just business. Doesn't like hurting people, but will.",
			"Grew up on the roads. Never knew anything else.",
		],
	},
	"guild_leader": {
		"personality_tags": ["ambitious", "calculating", "charismatic"],
		"speaking_style": "confident",
		"gossip_tendency": 0.5,
		"schedule": [
			{"time_period": "dawn", "location": "guild_hall", "activity": "reviewing ledgers"},
			{"time_period": "morning", "location": "guild_hall", "activity": "meeting merchants"},
			{"time_period": "noon", "location": "market_square", "activity": "inspecting trade"},
			{"time_period": "evening", "location": "tavern", "activity": "networking"},
			{"time_period": "night", "location": "home", "activity": "plotting"},
		],
		"sells": [],
		"buys": [],
		"starting_silver": 200,
		"starting_stock": {},
		"backstory_templates": [
			"Built the guild from a handful of traders into a regional power.",
			"Controls the flow of goods and isn't shy about leveraging that.",
			"Smiles a lot. Trusting that smile would be a mistake.",
		],
	},
}

# =============================================================================
# ADDITIONAL PERSONALITY TAGS — randomly added for variety
# =============================================================================

var _extra_personality_tags: Array[String] = [
	"stubborn", "generous", "jealous", "patient", "impulsive", "loyal",
	"curious", "pessimistic", "optimistic", "humble", "proud", "nervous",
	"brave", "gentle", "hot_tempered", "forgiving", "resentful", "devout",
	"skeptical", "romantic", "practical", "lazy", "ambitious",
]

# =============================================================================
# PUBLIC API
# =============================================================================

func _ready():
	print("[NPCTemplateGenerator] Initialized with %d occupation templates" % _occupation_templates.size())

## Generate a Tier 1 NPC profile from a role and settlement
func generate_npc(occupation: String, settlement: String, gender: String = "") -> Dictionary:
	if not _occupation_templates.has(occupation):
		push_warning("[NPCTemplateGenerator] Unknown occupation: %s, using merchant defaults" % occupation)
		occupation = "merchant"

	var template = _occupation_templates[occupation]

	# Determine gender if not specified
	if gender == "":
		gender = "male" if randf() < 0.5 else "female"

	# Generate name
	var name_data = _generate_name(settlement, gender)
	var npc_id = "%s_%s_%s" % [occupation, name_data.first.to_lower(), settlement]

	# Ensure unique ID
	var counter = 1
	var base_id = npc_id
	while tier1_profiles.has(npc_id):
		npc_id = "%s_%d" % [base_id, counter]
		counter += 1

	# Build personality tags: occupation defaults + 1-2 random extras
	var personality_tags: Array[String] = []
	for tag in template.personality_tags:
		personality_tags.append(tag)
	var extras_count = randi_range(1, 2)
	var shuffled_extras = _extra_personality_tags.duplicate()
	shuffled_extras.shuffle()
	for i in range(min(extras_count, shuffled_extras.size())):
		if shuffled_extras[i] not in personality_tags:
			personality_tags.append(shuffled_extras[i])

	# Generate backstory
	var pronouns = _get_pronouns(gender)
	var backstory_templates = template.backstory_templates
	var backstory = backstory_templates[randi() % backstory_templates.size()]
	backstory = backstory.replace("{pronoun}", pronouns.subject)
	backstory = backstory.replace("{pronoun_possessive}", pronouns.possessive)

	# Adapt schedule locations to settlement
	var schedule = _adapt_schedule_to_settlement(template.schedule, settlement)

	# Build the profile
	var profile: Dictionary = {
		"npc_id": npc_id,
		"display_name": name_data.first,
		"full_name": "%s %s" % [name_data.first, name_data.surname],
		"occupation": occupation,
		"gender": gender,
		"settlement": settlement,
		"tier": 1,
		"personality_tags": personality_tags,
		"speaking_style": template.speaking_style,
		"backstory_sentence": backstory,
		"disposition": 0.0,  # Neutral toward player
		"gossip_tendency": template.gossip_tendency + randf_range(-0.1, 0.1),
		"schedule": schedule,
		"sells": template.sells.duplicate(),
		"buys": template.buys.duplicate(),
		"starting_silver": template.starting_silver,
		"starting_stock": template.starting_stock.duplicate(),
		"heard_rumors": [],
		"behavior_flags": {
			"anxious": false,
			"celebratory": false,
			"mourning": false,
			"suspicious": false,
		},
		"dialogue_templates": _generate_dialogue_templates(occupation, name_data.first, personality_tags),
		"home_location": settlement,
	}

	# Clamp gossip tendency
	profile.gossip_tendency = clampf(profile.gossip_tendency, 0.0, 1.0)

	# Store
	tier1_profiles[npc_id] = profile
	npc_generated.emit(npc_id, profile)
	print("[NPCTemplateGenerator] Generated Tier 1 NPC: %s (%s in %s)" % [
		profile.full_name, occupation, settlement])

	return profile

## Generate a batch of NPCs for a settlement based on its size
func generate_settlement_npcs(settlement: String, size: String) -> Array[Dictionary]:
	var roster: Dictionary = _get_roster_for_size(size)
	var generated: Array[Dictionary] = []

	for occ in roster:
		var count: int = roster[occ]
		for i in range(count):
			var profile = generate_npc(occ, settlement)
			generated.append(profile)

	print("[NPCTemplateGenerator] Generated %d Tier 1 NPCs for %s (%s)" % [
		generated.size(), settlement, size])
	return generated

## Get a Tier 1 profile by ID
func get_profile(npc_id: String) -> Dictionary:
	return tier1_profiles.get(npc_id, {})

## Get all NPCs in a settlement
func get_npcs_in_settlement(settlement: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in tier1_profiles:
		if tier1_profiles[id].settlement == settlement:
			result.append(tier1_profiles[id])
	return result

## Record a player interaction (tracks toward promotion)
func record_interaction(npc_id: String, disposition_change: float = 0.0):
	if not tier1_profiles.has(npc_id):
		return

	_interaction_counts[npc_id] = _interaction_counts.get(npc_id, 0) + 1
	tier1_profiles[npc_id].disposition += disposition_change
	tier1_profiles[npc_id].disposition = clampf(tier1_profiles[npc_id].disposition, -100.0, 100.0)

	# Check promotion conditions
	var profile = tier1_profiles[npc_id]
	var interactions = _interaction_counts[npc_id]
	if profile.disposition >= PROMOTION_DISPOSITION_THRESHOLD and interactions >= PROMOTION_INTERACTION_THRESHOLD:
		_promote_to_tier0(npc_id)

## Set a behavior flag on a Tier 1 NPC (from world events)
func set_behavior_flag(npc_id: String, flag: String, value: bool):
	if tier1_profiles.has(npc_id):
		tier1_profiles[npc_id].behavior_flags[flag] = value

## Give a rumor to a Tier 1 NPC
func give_rumor(npc_id: String, packet_id: String):
	if tier1_profiles.has(npc_id):
		if packet_id not in tier1_profiles[npc_id].heard_rumors:
			tier1_profiles[npc_id].heard_rumors.append(packet_id)

# =============================================================================
# INTERNALS
# =============================================================================

func _generate_name(settlement: String, gender: String) -> Dictionary:
	var culture = settlement
	if not _name_pools.has(culture):
		culture = "thornhaven"  # Default

	var pool = _name_pools[culture]
	var first_names: Array = pool.get(gender, pool.get("male", []))
	var surnames: Array = pool.get("surname", [])

	# Track used names per settlement to avoid duplicates
	if not _used_names.has(settlement):
		_used_names[settlement] = []

	# Find an unused first name
	var available = first_names.filter(func(n): return n not in _used_names[settlement])
	if available.is_empty():
		available = first_names  # Reset if all used

	var first = available[randi() % available.size()]
	_used_names[settlement].append(first)

	var surname = surnames[randi() % surnames.size()]

	return {"first": first, "surname": surname}

func _get_pronouns(gender: String) -> Dictionary:
	if gender == "female":
		return {"subject": "she", "object": "her", "possessive": "her"}
	return {"subject": "he", "object": "him", "possessive": "his"}

func _adapt_schedule_to_settlement(base_schedule: Array, settlement: String) -> Array[Dictionary]:
	var adapted: Array[Dictionary] = []
	for entry in base_schedule:
		var new_entry = entry.duplicate()
		# Prefix generic locations with settlement name for uniqueness
		var loc = entry.location
		match loc:
			"market_square":
				new_entry.location = "%s_market_square" % settlement if settlement != "thornhaven" else "market_square"
			"tavern":
				new_entry.location = "%s_tavern" % settlement if settlement != "thornhaven" else "thornhaven_tavern"
			"blacksmith":
				new_entry.location = "%s_blacksmith" % settlement if settlement != "thornhaven" else "thornhaven_blacksmith"
			"home":
				new_entry.location = "%s_residential" % settlement
			"gate":
				new_entry.location = "%s_gate" % settlement
			"barracks":
				new_entry.location = "%s_barracks" % settlement
			"fields":
				new_entry.location = "%s_fields" % settlement
			"bakery":
				new_entry.location = "%s_bakery" % settlement
			"council_hall":
				new_entry.location = "%s_council_hall" % settlement
			"guild_hall":
				new_entry.location = "%s_guild_hall" % settlement
			"camp":
				new_entry.location = "%s_camp" % settlement
			"road":
				new_entry.location = "%s_road" % settlement
			_:
				new_entry.location = "%s_%s" % [settlement, loc]
		adapted.append(new_entry)
	return adapted

func _get_roster_for_size(size: String) -> Dictionary:
	match size:
		"village":
			return {
				"baker": 1,
				"guard": 2,
				"farmer": 3,
				"merchant": 1,
				"herbalist": 1,
				"tavern_worker": 1,
				"council_member": 1,
			}
		"town":
			return {
				"baker": 2,
				"guard": 4,
				"farmer": 5,
				"merchant": 4,
				"herbalist": 1,
				"tavern_worker": 2,
				"council_member": 2,
				"guild_leader": 1,
				"blacksmith_apprentice": 1,
			}
		"bandit_camp":
			return {
				"bandit": 6,
				"merchant": 1,  # Fence
			}
		"city":
			return {
				"baker": 3,
				"guard": 6,
				"farmer": 4,
				"merchant": 6,
				"herbalist": 2,
				"tavern_worker": 3,
				"council_member": 4,
				"guild_leader": 2,
				"blacksmith_apprentice": 2,
			}
		_:
			return {"farmer": 2, "guard": 1}

func _generate_dialogue_templates(occupation: String, name: String, tags: Array) -> Dictionary:
	var templates: Dictionary = {
		"greeting_positive": [],
		"greeting_negative": [],
		"greeting_anxious": [],
		"shop_buy": [],
		"shop_sell": [],
		"gossip": [],
		"farewell": [],
		"idle_chat": [],
	}

	# Generic greetings
	templates.greeting_positive = [
		"Good day to you!",
		"Ah, a friendly face. Welcome.",
		"Hello there! What brings you around?",
	]
	templates.greeting_negative = [
		"What do you want?",
		"I'm busy. Make it quick.",
		"Hmph. You again.",
	]
	templates.greeting_anxious = [
		"Oh! Didn't see you there. Jumpy lately...",
		"Keep it down, will you? Strange times.",
		"You haven't heard anything... unusual, have you?",
	]
	templates.farewell = [
		"Safe travels.",
		"Take care of yourself.",
		"See you around.",
	]
	templates.gossip = [
		"Did you hear? {rumor_content}",
		"Word is that {rumor_content}",
		"Between you and me... {rumor_content}",
	]

	# Occupation-specific additions
	match occupation:
		"baker":
			templates.greeting_positive.append("Fresh bread today! Still warm.")
			templates.shop_buy = ["Looking for something to eat? I've got bread and grain.", "Best bread in the village, if I say so myself."]
			templates.idle_chat = ["The oven keeps me up before dawn. Worth it though.", "Nothing like the smell of fresh bread, eh?"]
		"guard":
			templates.greeting_positive.append("Citizen. Everything alright?")
			templates.idle_chat = ["Keep your eyes open. Roads aren't safe lately.", "Nothing to report. Which is how I like it."]
		"farmer":
			templates.greeting_positive.append("The soil's been good this season.")
			templates.shop_buy = ["Need grain? Herbs? Fresh from the field.", "I've got surplus if you're buying."]
			templates.idle_chat = ["Rain's coming. I can feel it in my knees.", "The harvest will make or break the year."]
		"merchant":
			templates.greeting_positive.append("Looking to trade? I've got wares from across the region.")
			templates.shop_buy = ["Everything has a price, friend. Let's deal.", "I've got goods you won't find elsewhere."]
			templates.idle_chat = ["Trade's been slow since the road troubles.", "A good merchant knows when to buy and when to hold."]
		"herbalist":
			templates.greeting_positive.append("Need a remedy? I might have just the thing.")
			templates.shop_buy = ["Herbs, tinctures, poultices — what ails you?", "Nature provides, if you know where to look."]
			templates.idle_chat = ["Found a rare bloom by the creek yesterday.", "The old remedies are still the best."]
		"tavern_worker":
			templates.greeting_positive.append("What'll it be? Ale or something stronger?")
			templates.shop_buy = ["Sit down, have a drink. You look like you need it.", "Food and drink — the essentials."]
			templates.idle_chat = ["You hear all sorts working the bar.", "Last night was wild. Won't say more than that."]
		"council_member":
			templates.greeting_positive.append("Ah, good. I wanted to speak with you.")
			templates.idle_chat = ["The council is... deliberating. As always.", "These are trying times for governance."]
		"bandit":
			templates.greeting_positive = ["You don't look like a guard. That's good for you."]
			templates.greeting_negative = ["Wrong place to be wandering, stranger.", "Give me one reason not to take your coin."]
			templates.idle_chat = ["Life's hard on the road. Harder for the people we rob.", "Don't judge me. You don't know my story."]

	# Modify based on personality tags
	if "gossipy" in tags or "sociable" in tags:
		templates.gossip.append("Oh, you have to hear this — {rumor_content}")
		templates.gossip.append("I really shouldn't say, but... {rumor_content}")

	if "nervous" in tags or "anxious" in tags:
		templates.greeting_anxious.append("Is someone following you? No? Sorry, never mind...")

	return templates

## Promote a Tier 1 NPC to Tier 0 (creates a full NPCPersonality resource)
func _promote_to_tier0(npc_id: String):
	if not tier1_profiles.has(npc_id):
		return

	var profile = tier1_profiles[npc_id]
	print("[NPCTemplateGenerator] PROMOTING %s (%s) from Tier 1 -> Tier 0!" % [
		profile.display_name, profile.occupation])

	# Build a basic NPCPersonality from the Tier 1 data
	var personality = NPCPersonality.new()
	personality.npc_id = npc_id
	personality.display_name = profile.display_name
	personality.core_identity = "%s is a %s in %s. %s" % [
		profile.full_name, profile.occupation, profile.settlement, profile.backstory_sentence]
	personality.identity_anchors = [
		"You are %s, a %s." % [profile.full_name, profile.occupation],
		"You live in %s." % profile.settlement,
		profile.backstory_sentence,
	]

	# Map personality tags to Big Five traits (rough heuristic)
	for tag in profile.personality_tags:
		match tag:
			"cheerful", "optimistic", "sociable":
				personality.trait_extraversion += 20
			"stern", "dutiful":
				personality.trait_conscientiousness += 25
			"superstitious", "nervous", "anxious":
				personality.trait_neuroticism += 20
			"curious", "eccentric":
				personality.trait_openness += 25
			"kind", "generous", "gentle":
				personality.trait_agreeableness += 20
			"shrewd", "calculating":
				personality.trait_agreeableness -= 15
			"aggressive", "hot_tempered":
				personality.trait_agreeableness -= 25
			"distrustful", "suspicious":
				personality.trait_neuroticism += 15

	# Clamp traits
	personality.trait_openness = clampi(personality.trait_openness, -100, 100)
	personality.trait_conscientiousness = clampi(personality.trait_conscientiousness, -100, 100)
	personality.trait_extraversion = clampi(personality.trait_extraversion, -100, 100)
	personality.trait_agreeableness = clampi(personality.trait_agreeableness, -100, 100)
	personality.trait_neuroticism = clampi(personality.trait_neuroticism, -100, 100)

	personality.speaking_style = profile.speaking_style
	personality.gossip_tendency = profile.gossip_tendency
	personality.daily_schedule = profile.schedule

	# Register in WorldKnowledge
	WorldKnowledge.world_facts.npcs[npc_id] = {
		"name": profile.display_name,
		"full_name": profile.full_name,
		"age": randi_range(20, 60),
		"occupation": profile.occupation,
		"family": [],
		"residence": profile.settlement,
		"known_for": profile.backstory_sentence,
		"backstory": profile.backstory_sentence,
	}

	# Register in WorldState
	WorldState.npc_states[npc_id] = {"is_alive": true, "tier": 0}

	# Mark as promoted in the profile
	profile["tier"] = 0
	profile["personality_resource"] = personality

	npc_promoted.emit(npc_id, 1, 0)
	EventBus.world_event.emit({
		"event_type": "npc_promoted",
		"npc_id": npc_id,
		"npc_name": profile.display_name,
		"from_tier": 1,
		"to_tier": 0,
		"description": "%s has become an important figure in %s." % [profile.display_name, profile.settlement],
	})
