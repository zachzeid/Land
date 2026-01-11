extends "res://scripts/npcs/base_npc.gd"
# Gregor - Merchant NPC
# Personality loaded from: resources/npc_personalities/gregor_merchant.tres

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, medieval merchant man, middle-aged, friendly but nervous face, brown leather apron over simple tunic, slightly balding with short brown beard, warm smile with hint of worry in eyes, standing pose at isometric angle, full body visible, fantasy village style, shadow to bottom-right"

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
