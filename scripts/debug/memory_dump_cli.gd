extends SceneTree
## CLI tool to dump NPC memories from ChromaDB
## Usage: godot --headless --script scripts/debug/memory_dump_cli.gd -- [options]
##
## Options:
##   --npc <npc_id>     Dump specific NPC's memories (e.g., elena_daughter_001)
##   --all              Dump all NPC memories
##   --stats            Show memory statistics only
##   --help             Show this help message
##
## Examples:
##   godot --headless --script scripts/debug/memory_dump_cli.gd -- --all
##   godot --headless --script scripts/debug/memory_dump_cli.gd -- --npc elena_daughter_001
##   godot --headless --script scripts/debug/memory_dump_cli.gd -- --stats

const KNOWN_NPCS = [
	"elena_daughter_001",
	"gregor_merchant_001",
	"mira_tavern_keeper_001",
	"bjorn_blacksmith_001"
]

var chroma_client: Node = null

func _init():
	# Parse command line arguments
	var args = OS.get_cmdline_user_args()

	print("\n" + "=".repeat(60))
	print("NPC MEMORY DUMP CLI")
	print("=".repeat(60))

	if args.is_empty() or "--help" in args:
		_print_help()
		quit(0)
		return

	# Initialize ChromaDB client
	var ChromaClient = load("res://scripts/memory/chroma_client.gd")
	if ChromaClient == null:
		print("ERROR: Could not load ChromaClient")
		quit(1)
		return

	chroma_client = ChromaClient.new()
	root.add_child(chroma_client)

	# Process arguments
	if "--all" in args:
		await _dump_all_npcs()
	elif "--stats" in args:
		await _show_stats()
	else:
		var npc_idx = args.find("--npc")
		if npc_idx != -1 and npc_idx + 1 < args.size():
			var npc_id = args[npc_idx + 1]
			await _dump_npc(npc_id)
		else:
			print("ERROR: Invalid arguments. Use --help for usage.")
			quit(1)
			return

	quit(0)

func _print_help():
	print("""
Usage: godot --headless --script scripts/debug/memory_dump_cli.gd -- [options]

Options:
  --npc <npc_id>     Dump specific NPC's memories
  --all              Dump all known NPC memories
  --stats            Show memory statistics only
  --help             Show this help message

Known NPCs:
  - elena_daughter_001
  - gregor_merchant_001
  - mira_tavern_keeper_001
  - bjorn_blacksmith_001

Examples:
  godot --headless --script scripts/debug/memory_dump_cli.gd -- --all
  godot --headless --script scripts/debug/memory_dump_cli.gd -- --npc elena_daughter_001
  godot --headless --script scripts/debug/memory_dump_cli.gd -- --stats
""")

func _dump_all_npcs():
	print("\nDumping memories for all known NPCs...\n")

	for npc_id in KNOWN_NPCS:
		await _dump_npc(npc_id)
		print("")

func _dump_npc(npc_id: String):
	var collection_name = "npc_%s_memories" % npc_id.to_lower().replace(" ", "_")

	print("\n" + "-".repeat(60))
	print("NPC: %s" % npc_id)
	print("Collection: %s" % collection_name)
	print("-".repeat(60))

	# Query all memories from this NPC's collection
	var result = await chroma_client.query_memories({
		"collection": collection_name,
		"query": "memory conversation event player",
		"limit": 100,
		"min_importance": 1
	})

	if result.has("error"):
		print("  ERROR: %s" % result.error)
		return

	var memories = result if result is Array else result.get("memories", [])

	if memories.is_empty():
		print("  No memories found (collection may not exist)")
		return

	# Sort by timestamp
	memories.sort_custom(func(a, b):
		var ts_a = a.get("metadata", {}).get("timestamp", 0)
		var ts_b = b.get("metadata", {}).get("timestamp", 0)
		return ts_a > ts_b
	)

	# Group by tier
	var pinned = []
	var important = []
	var regular = []

	for mem in memories:
		var meta = mem.get("metadata", {})
		var tier = meta.get("memory_tier", 2)
		match tier:
			0: pinned.append(mem)
			1: important.append(mem)
			_: regular.append(mem)

	print("\nTotal memories: %d (Pinned: %d, Important: %d, Regular: %d)\n" % [
		memories.size(), pinned.size(), important.size(), regular.size()
	])

	if pinned.size() > 0:
		print("--- PINNED MEMORIES ---")
		for mem in pinned:
			_print_memory(mem)
		print("")

	if important.size() > 0:
		print("--- IMPORTANT MEMORIES ---")
		for mem in important:
			_print_memory(mem)
		print("")

	if regular.size() > 0:
		print("--- REGULAR MEMORIES ---")
		for mem in regular:
			_print_memory(mem)

func _print_memory(mem: Dictionary):
	var meta = mem.get("metadata", {})
	var text = mem.get("document", "[no text]")
	var event_type = meta.get("event_type", "unknown")
	var importance = meta.get("importance", 0)
	var timestamp = meta.get("timestamp", 0)

	var time_str = ""
	if timestamp > 0:
		var dt = Time.get_datetime_dict_from_unix_time(int(timestamp))
		time_str = "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]

	print("  [%s] (%s, imp:%d)" % [time_str, event_type, importance])
	print("    %s" % text.substr(0, 200))
	if text.length() > 200:
		print("    ...")

func _show_stats():
	print("\nMemory Statistics for all NPCs:\n")

	var total_memories = 0
	var total_pinned = 0
	var total_important = 0
	var total_regular = 0

	for npc_id in KNOWN_NPCS:
		var collection_name = "npc_%s_memories" % npc_id.to_lower().replace(" ", "_")

		var result = await chroma_client.query_memories({
			"collection": collection_name,
			"query": "memory",
			"limit": 100
		})

		var memories = result if result is Array else result.get("memories", [])

		var pinned = 0
		var important = 0
		var regular = 0

		for mem in memories:
			var tier = mem.get("metadata", {}).get("memory_tier", 2)
			match tier:
				0: pinned += 1
				1: important += 1
				_: regular += 1

		var total = memories.size()
		total_memories += total
		total_pinned += pinned
		total_important += important
		total_regular += regular

		print("  %-25s: %3d total (P:%d I:%d R:%d)" % [npc_id, total, pinned, important, regular])

	print("\n" + "-".repeat(50))
	print("  %-25s: %3d total (P:%d I:%d R:%d)" % ["TOTAL", total_memories, total_pinned, total_important, total_regular])
