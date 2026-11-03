extends "res://scripts/npcs/base_npc.gd"
# Lord Protector Edric Hale - Regent ruling for the nine-year-old King Aubren
# Personality loaded from: resources/npc_personalities/edric.tres
# Soul: souls/edric/SOUL.md. Home: capitol_palace. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("capitol")
	add_to_group("crown")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, medieval regent nobleman, age 51, lean careful face with short greying beard, dark velvet doublet in royal purple with a plain chain of office, sober black cloak, ink-stained fingers, tired watchful eyes, upright quartermaster bearing, standing pose at isometric angle, full body visible, fantasy court style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["renna_captain_001"] = {
		"type": "subordinate",
		"importance": 8,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["corwin_magistrate_001"] = {
		"type": "rival",
		"importance": 7,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["seraphine_ashdown_001"] = {
		"type": "petitioner",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["hollis_guildmaster_001"] = {
		"type": "creditor",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["lucan_commander_001"] = {
		"type": "subordinate",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["wren_innkeeper_001"] = {
		"type": "former_servant",
		"importance": 4,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
