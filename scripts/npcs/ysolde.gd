extends "res://scripts/npcs/base_npc.gd"
# Sister Ysolde - Infirmarian of the Cathedral of the Dawn
# Personality loaded from: resources/npc_personalities/ysolde.tres
# Soul: souls/ysolde/SOUL.md. Home: capitol_cathedral. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("capitol")
	add_to_group("clergy")
	add_to_group("healers")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, medieval nun infirmarian, age 44, strong plain weathered face, sleeves rolled to the elbow, rough red hands, pale grey and white habit with a sun-disc pendant, apron with herb pouches, standing pose at isometric angle, full body visible, fantasy healer style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["anselm_archivist_001"] = {
		"type": "friend",
		"importance": 8,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["elena_daughter_001"] = {
		"type": "patient",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["hollis_guildmaster_001"] = {
		"type": "enemy",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["dagna_foreman_001"] = {
		"type": "source",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
