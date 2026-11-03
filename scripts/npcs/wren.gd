extends "res://scripts/npcs/base_npc.gd"
# Old Wren - Keeper of the Halfway House, retired crown spy
# Personality loaded from: resources/npc_personalities/wren.tres
# Soul: souls/wren/SOUL.md. Home: kingsroad_waystation. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("kingsroad")
	add_to_group("innkeepers")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, elderly medieval innkeeper woman, age 70, small and bent, sharp bright eyes in a deeply lined face, white hair under a linen cap, warm brown shawl over a plain dress and apron, a ladle in one hand, standing pose at isometric angle, full body visible, fantasy tavern style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["edric_protector_001"] = {
		"type": "old_enemy",
		"importance": 7,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["renna_captain_001"] = {
		"type": "fond_memory",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["mira_tavern_keeper_001"] = {
		"type": "suspect",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["seraphine_ashdown_001"] = {
		"type": "correspondent",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["elder_mathias_001"] = {
		"type": "correspondent",
		"importance": 4,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
