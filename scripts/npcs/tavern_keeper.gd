extends "res://scripts/npcs/base_npc.gd"
# Mira - Tavern Keeper NPC
# Personality loaded from: resources/npc_personalities/mira_tavern_keeper.tres

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, medieval tavern keeper woman, late 30s, weary tired expression, brown hair in practical bun with strands loose, simple dress with apron, worn hands, standing pose at isometric angle, full body visible, fantasy village style, shadow to bottom-right"

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
