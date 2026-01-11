extends "res://scripts/npcs/base_npc.gd"
# Varn - Bandit Lieutenant
# Personality loaded from: resources/npc_personalities/varn_bandit.tres
# Gregor's contact, killed Mira's husband, main antagonist presence in village

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("bandits")
	add_to_group("enemies")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, medieval bandit enforcer man, mid 30s, cruel scarred face with cold smile, dark leather armor with iron studs, short dark hair slicked back, dagger at belt, intimidating muscular build, confident threatening stance, standing pose at isometric angle, full body visible, fantasy villain style, shadow to bottom-right"

	# Set up known NPCs - Varn knows about key village figures
	known_npcs["gregor_merchant_001"] = {
		"type": "informant",
		"importance": 9,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["mira_tavern_keeper_001"] = {
		"type": "victim",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
