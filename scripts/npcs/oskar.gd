extends "res://scripts/npcs/base_npc.gd"
# Oskar - Ferryman and toll-keeper at Ferrisford
# Personality loaded from: resources/npc_personalities/oskar.tres
# Soul: souls/oskar/SOUL.md. Home: ferrisford. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("kingsroad")
	add_to_group("ferrisford")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, broad medieval ferryman, age 46, heavy weathered face with a short brown beard, thick rope-scarred hands, tarred canvas smock and rolled sleeves, wide-brimmed hat, a long ferry pole, standing pose at isometric angle, full body visible, fantasy river folk style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["varn_bandit_001"] = {
		"type": "enemy",
		"importance": 8,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["renna_captain_001"] = {
		"type": "threat",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["hollis_guildmaster_001"] = {
		"type": "unknown_buyer",
		"importance": 4,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["rook_broker_001"] = {
		"type": "rumour",
		"importance": 3,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
