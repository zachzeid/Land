extends "res://scripts/npcs/base_npc.gd"
# Elder Mathias - Council Head
# Personality loaded from: resources/npc_personalities/elder_mathias.tres
# Can authorize official action against bandits if given proof

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("council")
	add_to_group("allies")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, medieval village elder man, age 72, kind weathered face with white beard and balding head, simple but dignified robes in brown and gray, walking staff in hand, wise tired eyes, slightly hunched with age, standing pose at isometric angle, full body visible, fantasy elder style, shadow to bottom-right"

	# Set up known NPCs - Elder knows key village figures
	known_npcs["gregor_merchant_001"] = {
		"type": "suspect",
		"importance": 8,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["aldric_peacekeeper_001"] = {
		"type": "ally",
		"importance": 9,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["mira_tavern_keeper_001"] = {
		"type": "citizen",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["bjorn_blacksmith_001"] = {
		"type": "citizen",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
