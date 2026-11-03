extends Node
# ChromaClient - Handles communication with ChromaDB for NPC memory storage
# Uses ChromaDB PersistentClient via chroma_cli.py for vector-based semantic memory retrieval
# Every call goes through one long-lived `chroma_cli.py serve` process shared by all ChromaClients
# (one JSON line in, one out, over its stdin/stdout): starting Python and importing chromadb costs
# 0.4-1 s, and a new game makes ~40 calls at boot, so a process per call blocked frames for 17-39 s.
# If the bridge cannot start or dies, a call falls back to one process per call (the old way).
# LAND_CHROMA_BRIDGE=0 forces that fallback; LAND_CHROMA_TIMING=1 prints each call's time

const CHROMA_CLI_PATH = "res://chroma_cli.py"
const PYTHON_CMD = "python3"
const SafeExec = preload("res://scripts/core/safe_exec.gd")

## The shared bridge: {stdio: FileAccess, pid: int, path: String (LAND_CHROMA_PATH it was started with)}
static var _bridge: Dictionary = {}
## LAND_CHROMA_PATH values whose bridge failed: those use one process per call from then on
static var _bridge_failed: Dictionary = {}
## Call counts and times (ms) since the game started, read by the boot measurements
static var stats: Dictionary = {"calls": 0, "bridge_calls": 0, "process_calls": 0, "ms": 0, "max_ms": 0, "bridge_starts": 0}

signal memory_stored(collection_name: String, memory_id: String)
signal memories_retrieved(collection_name: String, memories: Array)
signal error_occurred(error_message: String)

func _ready():
	_ensure_bridge()  # start Python importing chromadb now, while the scene finishes loading
	print("ChromaClient initialized (%s)" % ("bridge process" if not _bridge.is_empty() else "one process per call"))

## Run one chroma_cli.py command (args without the script path): {"code": exit code, "output": [stdout]}
## Arguments are held to SafeExec's rules on both paths, so the bridge refuses what the CLI would
func _call(args: Array) -> Dictionary:
	for arg in args:
		if not SafeExec.is_safe(arg):
			push_error("[SafeExec] Refused to run chroma_cli.py: an argument holds a shell character")
			return {"code": -1, "output": []}
	var started = Time.get_ticks_usec()
	var result = _bridge_call(args)
	var via_bridge = not result.is_empty()
	if not via_bridge:
		var output = []
		var code = SafeExec.execute(PYTHON_CMD, [ProjectSettings.globalize_path(CHROMA_CLI_PATH)] + args, output, true)
		result = {"code": code, "output": output}
	var ms = (Time.get_ticks_usec() - started) / 1000.0
	stats.calls += 1
	stats.ms += ms
	stats.max_ms = max(stats.max_ms, ms)
	if via_bridge:
		stats.bridge_calls += 1
	else:
		stats.process_calls += 1
	if OS.get_environment("LAND_CHROMA_TIMING") == "1":
		print("[ChromaClient] %s %s: %.1f ms" % [args[0] if args.size() > 0 else "?", "bridge" if via_bridge else "process", ms])
	return result

## Start the bridge for the current LAND_CHROMA_PATH unless it runs already; false = use the fallback
static func _ensure_bridge() -> bool:
	if OS.get_environment("LAND_CHROMA_BRIDGE") == "0":
		return false
	var path = OS.get_environment("LAND_CHROMA_PATH")
	if not _bridge.is_empty():
		if _bridge.path != path:
			stop_bridge()  # a test switched temp directories: this one would write to the old one
		elif OS.is_process_running(_bridge.pid):
			return true
		else:
			_bridge = {}  # it died; start a new one below
	if _bridge_failed.has(path):
		return false
	var started = Time.get_ticks_usec()
	var proc = SafeExec.execute_with_pipe(PYTHON_CMD, [ProjectSettings.globalize_path(CHROMA_CLI_PATH), "serve"], true)
	if proc.is_empty() or proc.get("stdio") == null or int(proc.get("pid", -1)) <= 0:
		_bridge_failed[path] = true
		return false
	_bridge = {"stdio": proc.stdio, "pid": int(proc.pid), "path": path}
	stats.bridge_starts += 1
	if OS.get_environment("LAND_CHROMA_TIMING") == "1":
		print("[ChromaClient] bridge started (pid %d) in %.1f ms" % [_bridge.pid, (Time.get_ticks_usec() - started) / 1000.0])
	return true

## One request over the bridge; {} when there is no bridge or it failed (the caller falls back)
static func _bridge_call(args: Array) -> Dictionary:
	if not _ensure_bridge():
		return {}
	var stdio: FileAccess = _bridge.stdio
	stdio.store_line(JSON.stringify(args.map(func(a): return str(a))))
	stdio.flush()
	var line = stdio.get_line()
	var reply = JSON.parse_string(line) if not line.is_empty() else null
	if not reply is Dictionary or not reply.has("out"):
		push_warning("[ChromaClient] Memory bridge stopped answering; using one process per call")
		_bridge_failed[_bridge.path] = true
		stop_bridge()
		return {}
	return {"code": int(reply.get("code", 1)), "output": [str(reply.out)]}

## Stop the shared bridge (it also exits by itself when the game closes its stdin)
static func stop_bridge() -> void:
	if _bridge.is_empty():
		return
	if OS.is_process_running(_bridge.pid):
		OS.kill(_bridge.pid)
	_bridge = {}

## Create or get a collection for an NPC's memories
## collection_name: Unique name like "npc_aldric_memories"
## Returns: Dictionary with collection info or error
func create_collection(collection_name: String) -> Dictionary:
	var r = _call(["create_collection", collection_name])
	var output = r.output
	var exit_code = r.code
	
	if exit_code != 0:
		var error = "Failed to create collection: " + str(output)
		error_occurred.emit(error)
		return {"error": error}
	
	var result = _parse_json_output(output)
	if result.has("success"):
		print("Created collection: %s" % collection_name)
		return {"name": collection_name}
	
	return result

## Get existing collection (same as create for PersistentClient)
func get_collection(collection_name: String) -> Dictionary:
	return await create_collection(collection_name)

## Add a memory to an NPC's collection
## memory: {
##   collection: String - collection name
##   id: String - unique memory ID
##   document: String - memory text from NPC's perspective
##   metadata: Dictionary - event_type, importance, emotion, timestamp, etc.
## }
func add_memory(memory: Dictionary) -> Dictionary:
	if not memory.has("collection") or not memory.has("id") or not memory.has("document"):
		return {"error": "Missing required fields: collection, id, document"}
	
	var metadata_json = JSON.stringify(memory.get("metadata", {}))
	
	# Encode both document and metadata as base64 to avoid shell escaping issues
	var document_b64 = Marshalls.utf8_to_base64(memory.document)
	var metadata_b64 = Marshalls.utf8_to_base64(metadata_json)
	
	var r = _call([
		"add_memory",
		memory.collection,
		memory.id,
		document_b64,
		metadata_b64
	])
	var output = r.output
	var exit_code = r.code
	
	if exit_code != 0:
		var error = "Failed to add memory: " + str(output)
		error_occurred.emit(error)
		return {"error": error}
	
	var result = _parse_json_output(output)
	if result.has("success"):
		memory_stored.emit(memory.collection, memory.id)
		print("Stored memory: %s in %s" % [memory.id, memory.collection])
	
	return result

## Query memories from an NPC's collection using semantic similarity
## query_params: {
##   collection: String - collection name
##   query: String - text to find similar memories for
##   limit: int - max number of memories to return (default: 5)
##   min_importance: int - filter memories below this importance (optional)
##   metadata_filter: Dictionary - filter by metadata fields (optional)
##     e.g., {"memory_tier": 0} to get only pinned memories
## }
## Returns: Array of memory documents with metadata
func query_memories(query_params: Dictionary) -> Array:
	if not query_params.has("collection") or not query_params.has("query"):
		error_occurred.emit("Missing required fields: collection, query")
		return []

	var limit = query_params.get("limit", 5)
	var min_importance = query_params.get("min_importance", -1)
	var metadata_filter = query_params.get("metadata_filter", {})

	var args = [
		"query",
		query_params.collection,
		"b64:" + Marshalls.utf8_to_base64(str(query_params.query)),  # player speech: never raw on a command line
		str(limit),
		str(min_importance)  # Always pass, -1 means no filter
	]

	# Add memory_tier filter if specified
	if metadata_filter.has("memory_tier"):
		args.append(str(metadata_filter.memory_tier))

	var r = _call(args)
	var output = r.output
	var exit_code = r.code
	
	if exit_code != 0:
		var error = "Query failed: " + str(output)
		error_occurred.emit(error)
		return []
	
	var result = _parse_json_output(output)
	
	if result.has("error"):
		error_occurred.emit("Query failed: " + result.error)
		return []
	
	var memories = result.get("memories", [])
	memories_retrieved.emit(query_params.collection, memories)
	print("Retrieved %d memories from %s" % [memories.size(), query_params.collection])
	
	return memories

## Delete one memory. memory: {collection, id}. Returns {"success": true} or {"error"}
func delete_memory(memory: Dictionary) -> Dictionary:
	if not memory.has("collection") or not memory.has("id"):
		return {"error": "Missing required fields: collection, id"}
	var r = _call(["delete_memory", memory.collection, memory.id])
	var output = r.output
	var exit_code = r.code
	if exit_code != 0:
		return {"error": "Failed to delete memory: " + str(output)}
	return _parse_json_output(output)

## Replace one memory's metadata (its text and embedding stay). memory: {collection, id, metadata}
func update_memory(memory: Dictionary) -> Dictionary:
	if not memory.has("collection") or not memory.has("id") or not memory.has("metadata"):
		return {"error": "Missing required fields: collection, id, metadata"}
	var metadata_b64 = Marshalls.utf8_to_base64(JSON.stringify(memory.metadata))
	var r = _call(["update_metadata", memory.collection, memory.id, metadata_b64])
	var output = r.output
	var exit_code = r.code
	if exit_code != 0:
		return {"error": "Failed to update memory: " + str(output)}
	return _parse_json_output(output)

## Exact metadata lookup, no embedding: memories whose metadata matches every key/value in where
## Returns: Array of {id, document, metadata} (empty on error or no match)
func get_where(collection_name: String, where: Dictionary, limit: int = 10) -> Array:
	var where_b64 = Marshalls.utf8_to_base64(JSON.stringify(where))
	var r = _call(["get_where", collection_name, where_b64, str(limit)])
	var output = r.output
	var exit_code = r.code
	if exit_code != 0:
		error_occurred.emit("get_where failed: " + str(output))
		return []
	var result = _parse_json_output(output)
	if result.has("error"):
		return []
	return result.get("memories", [])

## Delete a collection (use with caution!)
func delete_collection(collection_name: String) -> Dictionary:
	var r = _call(["delete_collection", collection_name])
	var output = r.output
	var exit_code = r.code

	if exit_code != 0:
		var error = "Failed to delete collection: " + str(output)
		error_occurred.emit(error)
		return {"error": error}

	var result = _parse_json_output(output)
	if result.has("deleted"):
		print("[ChromaClient] Deleted collection: %s" % collection_name)
	return result

## Get count of memories in a collection
func get_collection_count(collection_name: String) -> int:
	var r = _call(["get_count", collection_name])
	var output = r.output
	var exit_code = r.code

	if exit_code != 0:
		return 0

	var result = _parse_json_output(output)
	return result.get("count", 0)

## List all collections
func list_collections() -> Array:
	var r = _call(["list_collections"])
	var output = r.output
	var exit_code = r.code

	if exit_code != 0:
		return []

	var result = _parse_json_output(output)
	return result.get("collections", [])

## Parse JSON output from CLI
func _parse_json_output(output: Array) -> Dictionary:
	if output.size() == 0:
		return {"error": "No output from CLI"}
	
	var json_str = output[0].strip_edges()
	var json = JSON.new()
	var parse_result = json.parse(json_str)
	
	if parse_result != OK:
		return {"error": "Failed to parse JSON: " + json_str}
	
	# Ensure we return a dictionary
	if json.data is Dictionary:
		return json.data
	else:
		return {"error": "Expected dictionary, got: " + str(type_string(typeof(json.data)))}

## Test ChromaDB connection
func test_connection() -> bool:
	var test_collection = "test_connection_" + str(Time.get_ticks_msec())
	var result = await create_collection(test_collection)
	
	if result.has("error"):
		push_warning("ChromaDB CLI test failed: " + result.error)
		return false
	
	print("ChromaDB CLI connection successful!")
	return true

## Get memory by ID (direct lookup, not semantic search)
func get_memory_by_id(collection_name: String, memory_id: String) -> Dictionary:
	var r = _call([
		"get_by_id",
		collection_name,
		memory_id
	])
	var output = r.output
	var exit_code = r.code
	
	if exit_code != 0:
		var error = "Failed to get memory by ID: " + str(output)
		error_occurred.emit(error)
		return {"error": error}
	
	var result = _parse_json_output(output)
	
	if result.has("error"):
		error_occurred.emit("Get by ID failed: " + result.error)
		return result
	
	# Safely extract memory, ensuring we always return a dictionary
	if result.get("memory") is Dictionary:
		return result.memory
	return {}  # no such memory (the CLI answers null, which must not become a "<null>" document)
