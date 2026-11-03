extends "res://scripts/npcs/base_npc.gd"
# Brother Anselm - Archivist of Brackenmoor Abbey
# Personality loaded from: resources/npc_personalities/anselm.tres
# Soul: souls/anselm/SOUL.md. Home: brackenmoor_abbey. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("eastern_march")
	add_to_group("clergy")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, elderly medieval monk archivist, age 68, thin stooped figure, gentle lined face with half-moon spectacles, tonsured white hair, brown wool habit with rope belt, ink-stained fingers, carrying a heavy bound book, standing pose at isometric angle, full body visible, fantasy scholar style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["ysolde_sister_001"] = {
		"type": "friend",
		"importance": 9,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["seraphine_ashdown_001"] = {
		"type": "subject_of_record",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["hollis_guildmaster_001"] = {
		"type": "subject_of_record",
		"importance": 4,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["elena_daughter_001"] = {
		"type": "patient_from_letters",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
