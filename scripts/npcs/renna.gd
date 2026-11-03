extends "res://scripts/npcs/base_npc.gd"
# Captain Renna Thorne - Captain of the King's Rangers
# Personality loaded from: resources/npc_personalities/renna.tres
# Soul: souls/renna/SOUL.md. Home: capitol_gate. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("capitol")
	add_to_group("rangers")
	add_to_group("crown")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, medieval ranger captain woman, age 33, sun-browned face with a scar through one eyebrow, auburn hair in a short practical braid, green and brown riding leathers, crown badge on the shoulder, longbow on her back, dusty boots, confident stance, standing pose at isometric angle, full body visible, fantasy ranger style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["edric_protector_001"] = {
		"type": "commander",
		"importance": 8,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["elder_mathias_001"] = {
		"type": "family",
		"importance": 9,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["varn_bandit_001"] = {
		"type": "target",
		"importance": 7,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["lucan_commander_001"] = {
		"type": "colleague",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["wren_innkeeper_001"] = {
		"type": "old_kindness",
		"importance": 4,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["oskar_ferryman_001"] = {
		"type": "unknown",
		"importance": 3,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
