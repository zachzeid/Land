extends Node2D
## GameWorld - Main game scene controller
## Handles NPC initialization and world setup

## Whether to use ChromaDB for NPC memory persistence
@export var use_chromadb: bool = true

func _ready():
	print("[GameWorld] Initializing world...")

	# Wait one frame to ensure all child nodes are ready
	await get_tree().process_frame

	# Initialize all NPCs in the scene
	await _initialize_all_npcs()

	print("[GameWorld] World initialization complete")

## Initialize all NPCs in the "npcs" group
func _initialize_all_npcs():
	var npcs = get_tree().get_nodes_in_group("npcs")
	print("[GameWorld] Found %d NPCs to initialize" % npcs.size())

	for npc in npcs:
		if npc.has_method("initialize"):
			var npc_name = npc.get("npc_name") if "npc_name" in npc else npc.name
			print("[GameWorld] Initializing NPC: %s" % npc_name)

			# Initialize with ChromaDB setting
			var success = await npc.initialize(use_chromadb, false)

			if success:
				print("[GameWorld]   ✓ %s initialized" % npc_name)
			else:
				push_warning("[GameWorld]   ✗ %s failed to initialize" % npc_name)
		else:
			push_warning("[GameWorld] Node in 'npcs' group missing initialize(): %s" % npc.name)
