extends Node
## DynamicNPCRegistry - Tracks and auto-generates NPCs referenced in dialogue/story
## When NPCs like "bandits" are mentioned, this system creates entries for them
## so they can appear later with proper assets

## NPC type templates for auto-generation
const NPC_TEMPLATES = {
	"bandit": {
		"occupation": "bandit",
		"appearance_base": "rugged outlaw, tattered dark clothing, hooded cloak, menacing expression, leather armor pieces, fantasy medieval style",
		"personality_traits": ["aggressive", "greedy", "cunning"],
		"default_hostility": true,
		"variants": ["bandit_leader", "bandit_archer", "bandit_brute"]
	},
	"guard": {
		"occupation": "guard",
		"appearance_base": "village guard, chainmail armor, simple helmet, sword at belt, stern expression, fantasy medieval style",
		"personality_traits": ["dutiful", "suspicious", "protective"],
		"default_hostility": false,
		"variants": ["guard_captain", "gate_guard", "patrol_guard"]
	},
	"merchant": {
		"occupation": "traveling merchant",
		"appearance_base": "traveling merchant, colorful robes, large pack, friendly face, weathered from travel, fantasy medieval style",
		"personality_traits": ["shrewd", "friendly", "talkative"],
		"default_hostility": false,
		"variants": ["spice_merchant", "weapons_dealer", "potion_seller"]
	},
	"villager": {
		"occupation": "villager",
		"appearance_base": "simple villager, modest peasant clothing, work-worn hands, humble expression, fantasy medieval style",
		"personality_traits": ["humble", "hardworking", "cautious"],
		"default_hostility": false,
		"variants": ["farmer", "fisherman", "woodcutter"]
	},
	"soldier": {
		"occupation": "soldier",
		"appearance_base": "kingdom soldier, plate armor with tabard, professional bearing, disciplined stance, fantasy medieval style",
		"personality_traits": ["disciplined", "loyal", "battle-hardened"],
		"default_hostility": false,
		"variants": ["footman", "cavalry", "archer"]
	},
	"noble": {
		"occupation": "noble",
		"appearance_base": "minor noble, fine silk clothing, jewelry, refined bearing, condescending expression, fantasy medieval style",
		"personality_traits": ["arrogant", "educated", "political"],
		"default_hostility": false,
		"variants": ["lord", "lady", "young_heir"]
	},
	"thief": {
		"occupation": "thief",
		"appearance_base": "street thief, dark practical clothing, quick eyes, lithe build, shadowy presence, fantasy medieval style",
		"personality_traits": ["sneaky", "opportunistic", "street-smart"],
		"default_hostility": false,
		"variants": ["pickpocket", "burglar", "fence"]
	},
	"bard": {
		"occupation": "bard",
		"appearance_base": "traveling bard, colorful performer's garb, lute or instrument, charismatic smile, dramatic flair, fantasy medieval style",
		"personality_traits": ["charming", "creative", "gossip-loving"],
		"default_hostility": false,
		"variants": ["singer", "storyteller", "jester"]
	}
}

## Registry of referenced NPCs awaiting full definition/assets
## Format: {reference_id: {type, source, context, registered_at, asset_status, npc_data}}
var referenced_npcs: Dictionary = {}

## Registry of fully generated dynamic NPCs (have assets)
## Format: {npc_id: full NPC data dict}
var generated_npcs: Dictionary = {}

## Queue of NPCs waiting for asset generation
var asset_generation_queue: Array = []

## Signal when a new NPC reference is detected
signal npc_referenced(reference_id: String, npc_type: String, context: String)
## Signal when an NPC's assets are ready
signal npc_assets_ready(npc_id: String)
## Signal when a dynamic NPC is fully created
signal dynamic_npc_created(npc_id: String, npc_data: Dictionary)

## Counter for unique IDs
var _id_counter: int = 0

func _ready():
	# Scan existing world knowledge for referenced NPCs
	_scan_world_knowledge_for_references()

## Scan WorldKnowledge for NPC references that need generation
func _scan_world_knowledge_for_references():
	# Check recent events for NPC type mentions
	if WorldKnowledge.world_facts.has("history"):
		var history = WorldKnowledge.world_facts.history
		if history.has("recent_events"):
			for event in history.recent_events:
				_extract_npc_references_from_text(event, "world_history")

	# Check organizations for leader references
	if WorldKnowledge.world_facts.has("organizations"):
		for org_id in WorldKnowledge.world_facts.organizations:
			var org = WorldKnowledge.world_facts.organizations[org_id]
			if org.has("leader"):
				var leader_id = org.leader
				# Check if leader exists as full NPC
				if not WorldKnowledge.world_facts.npcs.has(leader_id):
					_register_reference(leader_id, "guard", "organization_leader", {
						"organization": org_id,
						"org_name": org.get("name", "Unknown"),
						"role": "leader"
					})

	print("[DynamicNPCRegistry] Scan complete. Found %d referenced NPCs" % referenced_npcs.size())

## Extract NPC references from text (dialogue, events, etc.)
func _extract_npc_references_from_text(text: String, source: String) -> Array:
	var found_refs = []
	var lower_text = text.to_lower()

	# Check for NPC type keywords
	var type_keywords = {
		"bandit": ["bandit", "bandits", "outlaw", "outlaws", "raider", "raiders", "highwayman"],
		"guard": ["guard", "guards", "watchman", "watchmen", "sentry", "sentries"],
		"merchant": ["merchant", "merchants", "trader", "traders", "peddler", "peddlers"],
		"soldier": ["soldier", "soldiers", "knight", "knights", "warrior", "warriors"],
		"thief": ["thief", "thieves", "pickpocket", "pickpockets", "burglar", "burglars"],
		"bard": ["bard", "bards", "minstrel", "minstrels", "performer", "performers"],
		"noble": ["noble", "nobles", "lord", "lady", "duke", "duchess", "baron"]
	}

	for npc_type in type_keywords:
		for keyword in type_keywords[npc_type]:
			if keyword in lower_text:
				var ref_id = "%s_ref_%d" % [npc_type, _id_counter]
				_id_counter += 1
				_register_reference(ref_id, npc_type, source, {"original_text": text, "keyword": keyword})
				found_refs.append(ref_id)
				break  # Only register one per type per text

	return found_refs

## Register an NPC reference for later generation
func _register_reference(reference_id: String, npc_type: String, source: String, context: Dictionary = {}):
	if referenced_npcs.has(reference_id):
		return  # Already registered

	referenced_npcs[reference_id] = {
		"type": npc_type,
		"source": source,
		"context": context,
		"registered_at": Time.get_unix_time_from_system(),
		"asset_status": "pending",  # pending, queued, generating, ready, failed
		"npc_data": null
	}

	print("[DynamicNPCRegistry] Registered reference: %s (type: %s, source: %s)" % [reference_id, npc_type, source])
	npc_referenced.emit(reference_id, npc_type, source)

## Register an NPC reference from dialogue (called by NPCs during conversation)
func register_dialogue_reference(npc_type: String, mentioned_by: String, dialogue_context: String) -> String:
	var ref_id = "%s_dialogue_%d" % [npc_type, _id_counter]
	_id_counter += 1

	_register_reference(ref_id, npc_type, "dialogue", {
		"mentioned_by": mentioned_by,
		"dialogue_context": dialogue_context
	})

	return ref_id

## Generate a full NPC from a reference
func generate_npc_from_reference(reference_id: String, custom_name: String = "", custom_appearance: String = "") -> Dictionary:
	if not referenced_npcs.has(reference_id):
		push_warning("[DynamicNPCRegistry] Unknown reference: %s" % reference_id)
		return {}

	var ref = referenced_npcs[reference_id]
	var npc_type = ref.type
	var template = NPC_TEMPLATES.get(npc_type, NPC_TEMPLATES.villager)

	# Generate unique NPC ID
	var npc_id = "%s_%d" % [npc_type, _id_counter]
	_id_counter += 1

	# Generate name if not provided
	var npc_name = custom_name if not custom_name.is_empty() else _generate_name(npc_type)

	# Build appearance prompt
	var appearance = custom_appearance if not custom_appearance.is_empty() else template.appearance_base
	var full_appearance = "isometric 2D game character, 3/4 view facing camera, %s, standing pose at isometric angle, full body visible, shadow to bottom-right" % appearance

	# Create NPC data
	var npc_data = {
		"npc_id": npc_id,
		"name": npc_name,
		"full_name": npc_name,
		"type": npc_type,
		"occupation": template.occupation,
		"appearance_prompt": full_appearance,
		"personality_traits": template.personality_traits.duplicate(),
		"is_hostile": template.default_hostility,
		"source_reference": reference_id,
		"context": ref.context,
		"generated_at": Time.get_unix_time_from_system(),
		"asset_status": "pending",
		"pixellab_character_id": ""
	}

	# Store in generated NPCs
	generated_npcs[npc_id] = npc_data

	# Update reference
	ref.npc_data = npc_data
	ref.asset_status = "generated"

	# Queue for asset generation
	asset_generation_queue.append(npc_id)

	print("[DynamicNPCRegistry] Generated NPC: %s (%s) from reference %s" % [npc_name, npc_id, reference_id])
	dynamic_npc_created.emit(npc_id, npc_data)

	return npc_data

## Generate a random appropriate name for NPC type
func _generate_name(npc_type: String) -> String:
	var first_names = {
		"bandit": ["Scar", "Black", "Red", "Shadow", "Grim", "Fang", "Razor", "Crow"],
		"guard": ["Marcus", "Roland", "Willem", "Garrett", "Thomas", "Harold", "Edwin", "Bernard"],
		"merchant": ["Cornelius", "Aldric", "Tobias", "Jasper", "Felix", "Hugo", "Leopold", "Oswald"],
		"villager": ["John", "Peter", "William", "Thomas", "Robert", "Richard", "Henry", "Edward"],
		"soldier": ["Viktor", "Conrad", "Aldric", "Roderick", "Magnus", "Cedric", "Gareth", "Bram"],
		"noble": ["Percival", "Reginald", "Bartholomew", "Archibald", "Alistair", "Maximilian", "Benedict", "Constantine"],
		"thief": ["Shade", "Whisper", "Quick", "Nimble", "Silent", "Swift", "Grey", "Smoke"],
		"bard": ["Lyric", "Melody", "Verse", "Cadence", "Harmony", "Ballad", "Rhyme", "Song"]
	}

	var last_names = {
		"bandit": ["the Cruel", "Eye", "Hand", "Wolf", "Blade", "Face", "Tooth", "Jack"],
		"guard": ["Ironside", "Strongarm", "Shieldman", "Watchful", "Steadfast", "Dutiful", "Stern", "Vigilant"],
		"merchant": ["Goldweather", "Silvertounge", "Coinsworth", "Tradewell", "Fairprice", "Goodseller", "Barter", "Scales"],
		"villager": ["Smith", "Miller", "Cooper", "Baker", "Carpenter", "Fisher", "Shepherd", "Tanner"],
		"soldier": ["Ironhelm", "Steelbane", "Battleborn", "Warhammer", "Shieldbreaker", "Swordbane", "Axefall", "Spearpoint"],
		"noble": ["Highcastle", "Goldcrest", "Silvervale", "Stonehall", "Ravencroft", "Whitmore", "Ashford", "Blackwood"],
		"thief": ["Fingers", "Step", "Hand", "Eyes", "Shadow", "Coin", "Fox", "Cat"],
		"bard": ["Songweaver", "Storysinger", "Talespinner", "Voicebright", "Stringmaster", "Wordsmith", "Tunecaller", "Notedancer"]
	}

	var firsts = first_names.get(npc_type, first_names.villager)
	var lasts = last_names.get(npc_type, last_names.villager)

	var first = firsts[randi() % firsts.size()]
	var last = lasts[randi() % lasts.size()]

	return "%s %s" % [first, last]

## Get next NPC in asset generation queue
func get_next_for_asset_generation() -> Dictionary:
	if asset_generation_queue.is_empty():
		return {}

	var npc_id = asset_generation_queue.pop_front()
	if generated_npcs.has(npc_id):
		return generated_npcs[npc_id]
	return {}

## Update asset generation status for an NPC
func update_asset_status(npc_id: String, status: String, pixellab_id: String = ""):
	if generated_npcs.has(npc_id):
		generated_npcs[npc_id].asset_status = status
		if not pixellab_id.is_empty():
			generated_npcs[npc_id].pixellab_character_id = pixellab_id

		if status == "ready":
			npc_assets_ready.emit(npc_id)

		print("[DynamicNPCRegistry] Asset status for %s: %s" % [npc_id, status])

## Get all referenced NPCs of a specific type
func get_references_by_type(npc_type: String) -> Array:
	var results = []
	for ref_id in referenced_npcs:
		if referenced_npcs[ref_id].type == npc_type:
			results.append(referenced_npcs[ref_id])
	return results

## Get all generated NPCs
func get_all_generated_npcs() -> Dictionary:
	return generated_npcs.duplicate()

## Check if an NPC ID is a dynamic NPC
func is_dynamic_npc(npc_id: String) -> bool:
	return generated_npcs.has(npc_id)

## Get dynamic NPC data
func get_dynamic_npc(npc_id: String) -> Dictionary:
	return generated_npcs.get(npc_id, {})

## Register dynamic NPC to WorldKnowledge (makes them "official")
func promote_to_world_knowledge(npc_id: String, location: String = ""):
	if not generated_npcs.has(npc_id):
		return

	var npc = generated_npcs[npc_id]

	# Add to WorldKnowledge.world_facts.npcs
	WorldKnowledge.world_facts.npcs[npc_id] = {
		"name": npc.name.split(" ")[0],  # First name only
		"full_name": npc.full_name,
		"age": randi_range(20, 50),
		"occupation": npc.occupation,
		"family": [],
		"residence": location if not location.is_empty() else "Unknown",
		"known_for": "Recently encountered",
		"backstory": "A %s who was encountered during adventures" % npc.type
	}

	# Add to npc_locations if location provided
	if not location.is_empty():
		WorldKnowledge.npc_locations[npc_id] = location

	print("[DynamicNPCRegistry] Promoted %s to WorldKnowledge" % npc_id)

## Process asset generation queue (call periodically or on demand)
func process_asset_queue() -> Dictionary:
	var next_npc = get_next_for_asset_generation()
	if next_npc.is_empty():
		return {}

	# Mark as queued
	update_asset_status(next_npc.npc_id, "queued")

	return next_npc

## Debug: Print registry status
func debug_print_status():
	print("\n=== DYNAMIC NPC REGISTRY ===")
	print("Referenced NPCs: %d" % referenced_npcs.size())
	for ref_id in referenced_npcs:
		var ref = referenced_npcs[ref_id]
		print("  [%s] Type: %s, Source: %s, Status: %s" % [ref_id, ref.type, ref.source, ref.asset_status])

	print("\nGenerated NPCs: %d" % generated_npcs.size())
	for npc_id in generated_npcs:
		var npc = generated_npcs[npc_id]
		print("  [%s] %s - %s (assets: %s)" % [npc_id, npc.name, npc.type, npc.asset_status])

	print("\nAsset Queue: %d pending" % asset_generation_queue.size())
	print("================================\n")
