extends "res://scripts/npcs/base_npc.gd"
# High Magistrate Corwin Vane - The crown's chief judge and investigator
# Personality loaded from: resources/npc_personalities/corwin.tres
# Soul: souls/corwin/SOUL.md. Home: capitol_magistry. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("capitol")
	add_to_group("crown")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, elderly medieval high judge, age 63, gaunt severe clean-shaven face, white hair cut short, long black magistrate's robe with a white collar band, heavy iron chain of office, carrying a sheaf of papers, standing pose at isometric angle, full body visible, fantasy court style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["edric_protector_001"] = {
		"type": "superior",
		"importance": 8,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["hollis_guildmaster_001"] = {
		"type": "suspect",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["seraphine_ashdown_001"] = {
		"type": "litigant",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["gregor_merchant_001"] = {
		"type": "witness",
		"importance": 7,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["oskar_ferryman_001"] = {
		"type": "complainant",
		"importance": 4,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
