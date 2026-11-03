extends "res://scripts/npcs/base_npc.gd"
# Guildmaster Hollis Marrow - Master of the Merchants' Guild
# Personality loaded from: resources/npc_personalities/hollis.tres
# Soul: souls/hollis/SOUL.md. Home: capitol_guildhall. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("capitol")
	add_to_group("merchants")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, prosperous medieval guildmaster, age 57, round genial face with shrewd small eyes, balding with grey side hair, rich mustard and brown velvet coat with fur trim, gold guild chain, rings on thick fingers, a small black ledger in his coat pocket, standing pose at isometric angle, full body visible, fantasy merchant style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["seraphine_ashdown_001"] = {
		"type": "debtor",
		"importance": 8,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["rook_broker_001"] = {
		"type": "asset",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["dagna_foreman_001"] = {
		"type": "employee",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["corwin_magistrate_001"] = {
		"type": "threat",
		"importance": 7,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["edric_protector_001"] = {
		"type": "prospect",
		"importance": 7,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
