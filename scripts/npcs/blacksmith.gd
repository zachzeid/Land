extends "res://scripts/npcs/base_npc.gd"
# Bjorn - Blacksmith NPC
# Personality loaded from: resources/npc_personalities/bjorn_blacksmith.tres

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, medieval blacksmith man, burly muscular build, mid 40s, scarred arms from forge work, bald head with thick gray beard, leather apron over bare chest, holding hammer, serious weathered face, standing pose at isometric angle, full body visible, fantasy village style, shadow to bottom-right"

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
