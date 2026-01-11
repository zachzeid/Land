extends "res://scripts/npcs/base_npc.gd"
# Elena - Gregor's daughter
# Personality loaded from: resources/npc_personalities/elena_daughter.tres
# Has special logic to check father's state and react accordingly

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, young woman early twenties, kind gentle face with hint of worry, long brown hair in simple braid, modest medieval village dress in soft purple and cream colors, warm compassionate expression, standing pose at isometric angle, full body visible, fantasy village style, shadow to bottom-right"

	# Set up family relationship BEFORE initialization
	# This ensures she checks father's state when initializing
	known_npcs["gregor_merchant_001"] = {
		"type": "family",
		"importance": 10,  # Family = max importance (never pruned)
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	var result = await initialize(true)
	if result:
		# Update relationship state based on father's status
		await _check_father_state()

## Check father's state and update relationship values accordingly
func _check_father_state():
	# Check if father is in known NPCs and his state
	if known_npcs.has("gregor_merchant_001"):
		var father_state = await rag_memory.check_npc_state("gregor_merchant_001")
		var father_alive = father_state.get("is_alive", true)
		var killed_by_player = (father_state.get("killed_by", "") == "player")

		if not father_alive:
			if killed_by_player:
				# Father killed by player - set maximum hostility
				# The AI will use these values to guide behavior
				relationship_trust = -100
				relationship_affection = -100
				relationship_respect = -100
				relationship_fear = 80
				print("[Elena] Father was killed by player - hostile relationship set")
			else:
				# Father killed by someone else - grieving but seeking answers
				relationship_trust = -20
				relationship_affection = -30
				relationship_fear = 30
				print("[Elena] Father was killed - grieving state set")
		else:
			print("[Elena] Father is alive - normal state")
