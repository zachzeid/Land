extends "res://scripts/npcs/base_npc.gd"
# Lady Seraphine Ashdown - Noblewoman whose house holds the deed to the Western Valley
# Personality loaded from: resources/npc_personalities/seraphine.tres
# Soul: souls/seraphine/SOUL.md. Home: ashdown_manor. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("capitol")
	add_to_group("nobility")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, elegant medieval noblewoman, age 38, composed beautiful face with knowing smile, dark hair pinned up with a silver comb, slightly faded but fine grey and rose silk gown, embroidered gloves, standing pose at isometric angle, full body visible, fantasy court style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["hollis_guildmaster_001"] = {
		"type": "creditor",
		"importance": 9,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["edric_protector_001"] = {
		"type": "patron",
		"importance": 7,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["corwin_magistrate_001"] = {
		"type": "threat",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["elder_mathias_001"] = {
		"type": "obstacle",
		"importance": 4,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
