extends "res://scripts/npcs/base_npc.gd"
# Rook - Information broker and fence of the Warrens
# Personality loaded from: resources/npc_personalities/rook.tres
# Soul: souls/rook/SOUL.md. Home: capitol_warrens. Spawned by the engine's NPC spawner, not baked into scenes.

func _ready():
	# Add to NPCs group for discovery system
	add_to_group("npcs")
	add_to_group("capitol")
	add_to_group("underworld")

	# Set appearance for AI asset generation
	appearance_prompt = "isometric 2D game character, 3/4 view facing camera, teenage street broker of a medieval slum, about 17, sharp clever face smudged with soot, short ragged dark hair under a patched cap, oversized patched brown coat with many pockets, fingerless gloves, quick wary eyes, ready to run, standing pose at isometric angle, full body visible, fantasy rogue style, shadow to bottom-right"

	# Set up known NPCs
	known_npcs["hollis_guildmaster_001"] = {
		"type": "dangerous_patron",
		"importance": 8,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["seraphine_ashdown_001"] = {
		"type": "the_lady_on_the_hill",
		"importance": 6,
		"last_interaction": Time.get_unix_time_from_system()
	}
	known_npcs["oskar_ferryman_001"] = {
		"type": "river_contact",
		"importance": 3,
		"last_interaction": Time.get_unix_time_from_system()
	}

	# Initialize with ChromaDB (deferred to ensure scene is ready)
	call_deferred("_deferred_init")

func _deferred_init():
	initialize(true)
