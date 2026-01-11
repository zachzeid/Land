extends "res://scripts/npcs/base_npc.gd"
# Captain Aldric - Peacekeeper Leader
# Personality loaded from: resources/npc_personalities/aldric_peacekeeper.tres
# Leader of village resistance, potential key ally against bandits

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("peacekeepers")
	add_to_group("allies")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, medieval guard captain man, age 50, weathered stern face with gray beard, worn chainmail over simple tunic, old military cloak, sword at hip, alert watchful eyes, military posture despite age, standing pose at isometric angle, full body visible, fantasy soldier style, shadow to bottom-right"

	# Set up known NPCs - Aldric knows key village figures
	known_npcs["gregor_merchant_001"] = {
		"type": "suspect",
		"importance": 8,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["varn_bandit_001"] = {
		"type": "enemy",
		"importance": 9,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["elder_mathias_001"] = {
		"type": "superior",
		"importance": 7,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
