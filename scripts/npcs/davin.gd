extends "res://scripts/npcs/base_npc.gd"
# Davin - Bjorn's former apprentice, taken in the second Tithe, escaped the Pit
# Personality loaded from: resources/npc_personalities/davin.tres
# Soul: souls/davin/SOUL.md. Home: healer_hut. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("thornhaven")
	add_to_group("the_taken")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, thin pale young medieval man, age 20, gaunt fevered face with shadowed eyes and short dark hair, ragged undyed shirt under a borrowed wool blanket worn as a cloak, right hand wrapped in linen and tucked into his sleeve, bare feet, hunched wary stance, standing pose at isometric angle, full body visible, fantasy peasant style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["bjorn_blacksmith_001"] = {
		"type": "father_figure",
		"importance": 10,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["varn_bandit_001"] = {
		"type": "captor",
		"importance": 9,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["elena_daughter_001"] = {
		"type": "neighbour",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["gregor_merchant_001"] = {
		"type": "neighbour",
		"importance": 4,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["mira_tavern_keeper_001"] = {
		"type": "neighbour",
		"importance": 3,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
