extends "res://scripts/npcs/base_npc.gd"
# Foreman Dagna Holt - Foreman of Greystone Mines
# Personality loaded from: resources/npc_personalities/dagna.tres
# Soul: souls/dagna/SOUL.md. Home: greystone_mines. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("eastern_march")
	add_to_group("miners")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, tough medieval mine foreman woman, age 49, broad shoulders, coal-smudged square face, grey-streaked hair tied back under a leather cap, heavy leather apron over a wool tunic, a pick on her shoulder and a lamp at her belt, standing pose at isometric angle, full body visible, fantasy miner style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["hollis_guildmaster_001"] = {
		"type": "landlord",
		"importance": 7,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["bjorn_blacksmith_001"] = {
		"type": "customer",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["varn_bandit_001"] = {
		"type": "protection",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["lucan_commander_001"] = {
		"type": "neighbour",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["ysolde_sister_001"] = {
		"type": "unknown",
		"importance": 2,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
