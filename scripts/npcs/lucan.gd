extends "res://scripts/npcs/base_npc.gd"
# Commander Lucan Ferrow - Commander of Fort Ashguard
# Personality loaded from: resources/npc_personalities/lucan.tres
# Soul: souls/lucan/SOUL.md. Home: fort_ashguard. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("eastern_march")
	add_to_group("soldiers")
	add_to_group("crown")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, medieval garrison commander, age 55, handsome battered face with a neat grey moustache, polished steel breastplate over a crimson surcoat, two campaign medals, officer's sword, red cloak, parade-ground posture, standing pose at isometric angle, full body visible, fantasy knight style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["varn_bandit_001"] = {
		"type": "deserter",
		"importance": 10,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["renna_captain_001"] = {
		"type": "rival",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["aldric_peacekeeper_001"] = {
		"type": "old_comrade",
		"importance": 5,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["corwin_magistrate_001"] = {
		"type": "threat",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["dagna_foreman_001"] = {
		"type": "neighbour",
		"importance": 4,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
