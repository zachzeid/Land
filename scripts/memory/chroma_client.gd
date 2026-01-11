extends Node
# ChromaClient - Handles communication with ChromaDB for NPC memory storage
# Uses ChromaDB PersistentClient via CLI for vector-based semantic memory retrieval

const CHROMA_CLI_PATH = "res://chroma_cli.py"
const PYTHON_CMD = "python3"

signal memory_stored(collection_name: String, memory_id: String)
signal memories_retrieved(collection_name: String, memories: Array)
signal error_occurred(error_message: String)

func _ready():
	print("ChromaClient initialized (CLI mode with PersistentClient)")

## Create or get a collection for an NPC's memories
## collection_name: Unique name like "npc_aldric_memories"
## Returns: Dictionary with collection info or error
func create_collection(collection_name: String) -> Dictionary:
	var cli_path = ProjectSettings.globalize_path(CHROMA_CLI_PATH)
	var output = []
	var exit_code = OS.execute(PYTHON_CMD, [cli_path, "create_collection", collection_name], output, true)
	
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
	
	var cli_path = ProjectSettings.globalize_path(CHROMA_CLI_PATH)
	var metadata_json = JSON.stringify(memory.get("metadata", {}))
	
	# Encode both document and metadata as base64 to avoid shell escaping issues
	var document_b64 = Marshalls.utf8_to_base64(memory.document)
	var metadata_b64 = Marshalls.utf8_to_base64(metadata_json)
	
	var output = []
	var exit_code = OS.execute(PYTHON_CMD, [
		cli_path,
		"add_memory",
		memory.collection,
		memory.id,
		document_b64,
		metadata_b64
	], output, true)
	
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

	var cli_path = ProjectSettings.globalize_path(CHROMA_CLI_PATH)
	var limit = query_params.get("limit", 5)
	var min_importance = query_params.get("min_importance", -1)
	var metadata_filter = query_params.get("metadata_filter", {})

	var args = [
		cli_path,
		"query",
		query_params.collection,
		query_params.query,
		str(limit),
		str(min_importance)  # Always pass, -1 means no filter
	]

	# Add memory_tier filter if specified
	if metadata_filter.has("memory_tier"):
		args.append(str(metadata_filter.memory_tier))

	var output = []
	var exit_code = OS.execute(PYTHON_CMD, args, output, true)
	
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

## Delete a collection (use with caution!)
func delete_collection(collection_name: String) -> Dictionary:
	var cli_path = ProjectSettings.globalize_path(CHROMA_CLI_PATH)
	var output = []
	var exit_code = OS.execute(PYTHON_CMD, [cli_path, "delete_collection", collection_name], output, true)

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
	var cli_path = ProjectSettings.globalize_path(CHROMA_CLI_PATH)
	var output = []
	var exit_code = OS.execute(PYTHON_CMD, [cli_path, "get_count", collection_name], output, true)

	if exit_code != 0:
		return 0

	var result = _parse_json_output(output)
	return result.get("count", 0)

## List all collections
func list_collections() -> Array:
	var cli_path = ProjectSettings.globalize_path(CHROMA_CLI_PATH)
	var output = []
	var exit_code = OS.execute(PYTHON_CMD, [cli_path, "list_collections"], output, true)

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
	var cli_path = ProjectSettings.globalize_path(CHROMA_CLI_PATH)
	var output = []
	var exit_code = OS.execute(PYTHON_CMD, [
		cli_path,
		"get_by_id",
		collection_name,
		memory_id
	], output, true)
	
	if exit_code != 0:
		var error = "Failed to get memory by ID: " + str(output)
		error_occurred.emit(error)
		return {"error": error}
	
	var result = _parse_json_output(output)
	
	if result.has("error"):
		error_occurred.emit("Get by ID failed: " + result.error)
		return result
	
	# Safely extract memory, ensuring we always return a dictionary
	if result.has("memory") and result.memory is Dictionary:
		return result.memory
	elif result.has("memory"):
		return {"document": str(result.memory)}
	else:
		return {}
