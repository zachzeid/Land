extends Node
## DynamicNPCGenerator - Auto-generates assets for NPCs registered in DynamicNPCRegistry
## Integrates with CharacterGenerator and PixelLab to create sprites for referenced NPCs

## Reference to character generator
var character_generator: Node = null

## Reference to dynamic NPC registry (autoloaded)
@onready var registry = get_node_or_null("/root/DynamicNPCRegistry")

## Processing state
var is_processing: bool = false
var current_npc_id: String = ""

## Signals
signal generation_started(npc_id: String)
signal generation_complete(npc_id: String, sprite_frames: SpriteFrames)
signal generation_failed(npc_id: String, error: String)
signal queue_empty()

## Settings
@export var auto_process_queue: bool = true
@export var process_interval: float = 10.0  # Seconds between queue checks

var _process_timer: Timer = null

func _ready():
	# Get character generator reference
	if has_node("/root/CharacterGenerator"):
		character_generator = get_node("/root/CharacterGenerator")
	else:
		# Try to find it as a child or create one
		character_generator = _find_or_create_character_generator()

	# Connect to registry signals
	if registry:
		registry.dynamic_npc_created.connect(_on_dynamic_npc_created)
		print("[DynamicNPCGen] Connected to DynamicNPCRegistry")
	else:
		push_warning("[DynamicNPCGen] DynamicNPCRegistry not found - dynamic NPC generation disabled")

	# Set up auto-processing timer
	if auto_process_queue:
		_process_timer = Timer.new()
		_process_timer.wait_time = process_interval
		_process_timer.timeout.connect(_on_process_timer)
		add_child(_process_timer)
		_process_timer.start()

	# Connect to character generator signals
	if character_generator:
		character_generator.character_ready.connect(_on_character_ready)
		character_generator.character_failed.connect(_on_character_failed)

func _find_or_create_character_generator() -> Node:
	# Look for CharacterGen autoload
	var char_gen = get_node_or_null("/root/CharacterGen")
	if char_gen:
		return char_gen

	# Try to load and instance it
	var CharGenScript = load("res://scripts/generation/character_generator.gd")
	if CharGenScript:
		var instance = CharGenScript.new()
		instance.name = "DynamicCharacterGenerator"
		add_child(instance)
		return instance

	return null

## Called when a new dynamic NPC is created in the registry
func _on_dynamic_npc_created(npc_id: String, npc_data: Dictionary):
	print("[DynamicNPCGen] New dynamic NPC created: %s - queuing for asset generation" % npc_id)
	# The NPC is automatically in the registry's queue
	# Start processing if not already
	if auto_process_queue and not is_processing:
		process_next_in_queue()

## Timer callback for queue processing
func _on_process_timer():
	if not is_processing and registry:
		process_next_in_queue()

## Process the next NPC in the generation queue
func process_next_in_queue():
	if not registry:
		push_warning("[DynamicNPCGen] No registry available")
		return

	if is_processing:
		print("[DynamicNPCGen] Already processing: %s" % current_npc_id)
		return

	var next_npc = registry.process_asset_queue()
	if next_npc.is_empty():
		queue_empty.emit()
		return

	_start_generation(next_npc)

## Start generating assets for an NPC
func _start_generation(npc_data: Dictionary):
	if not character_generator:
		push_warning("[DynamicNPCGen] No character generator available")
		registry.update_asset_status(npc_data.npc_id, "failed")
		return

	is_processing = true
	current_npc_id = npc_data.npc_id

	registry.update_asset_status(npc_data.npc_id, "generating")
	generation_started.emit(npc_data.npc_id)

	print("[DynamicNPCGen] Starting asset generation for: %s" % npc_data.npc_id)
	print("[DynamicNPCGen] Appearance: %s" % npc_data.appearance_prompt.left(80))

	# Use character generator to create sprites
	character_generator.generate_character(npc_data.npc_id, npc_data.appearance_prompt)

## Handle character generation complete
func _on_character_ready(character_id: String, sprite_frames: SpriteFrames):
	if character_id != current_npc_id:
		return  # Not our generation

	print("[DynamicNPCGen] Asset generation complete for: %s" % character_id)

	registry.update_asset_status(character_id, "ready")
	generation_complete.emit(character_id, sprite_frames)

	is_processing = false
	current_npc_id = ""

	# Process next in queue
	if auto_process_queue:
		# Add small delay before processing next
		get_tree().create_timer(2.0).timeout.connect(process_next_in_queue, CONNECT_ONE_SHOT)

## Handle character generation failed
func _on_character_failed(character_id: String, error: String):
	if character_id != current_npc_id:
		return  # Not our generation

	print("[DynamicNPCGen] Asset generation failed for %s: %s" % [character_id, error])

	registry.update_asset_status(character_id, "failed")
	generation_failed.emit(character_id, error)

	is_processing = false
	current_npc_id = ""

	# Continue processing queue even on failure
	if auto_process_queue:
		get_tree().create_timer(5.0).timeout.connect(process_next_in_queue, CONNECT_ONE_SHOT)

## Manually queue an NPC for generation (if not already in registry)
func queue_npc_for_generation(npc_type: String, custom_name: String = "", custom_appearance: String = "") -> String:
	if not registry:
		push_warning("[DynamicNPCGen] No registry available")
		return ""

	# Register a reference
	var ref_id = registry.register_dialogue_reference(npc_type, "manual", "Manually queued for generation")

	# Generate NPC from reference
	var npc_data = registry.generate_npc_from_reference(ref_id, custom_name, custom_appearance)

	if not npc_data.is_empty():
		return npc_data.npc_id

	return ""

## Generate a specific NPC type immediately
func generate_npc_now(npc_type: String, custom_name: String = "", custom_appearance: String = "") -> Dictionary:
	var npc_id = queue_npc_for_generation(npc_type, custom_name, custom_appearance)
	if npc_id.is_empty():
		return {}

	# Start generation immediately
	var npc_data = registry.get_dynamic_npc(npc_id)
	if not npc_data.is_empty():
		_start_generation(npc_data)

	return npc_data

## Create NPCs from world history/story references
func scan_and_generate_story_npcs():
	if not registry:
		return

	# Force a scan of world knowledge
	registry._scan_world_knowledge_for_references()

	# Get all references that don't have NPCs generated yet
	for npc_type in ["bandit", "guard", "merchant", "soldier"]:
		var refs = registry.get_references_by_type(npc_type)
		for ref in refs:
			if ref.npc_data == null:
				# Generate NPC from this reference
				var ref_id = ""
				for key in registry.referenced_npcs:
					if registry.referenced_npcs[key] == ref:
						ref_id = key
						break

				if not ref_id.is_empty():
					registry.generate_npc_from_reference(ref_id)

	# Start processing the queue
	if not is_processing:
		process_next_in_queue()

## Get status of current generation
func get_generation_status() -> Dictionary:
	return {
		"is_processing": is_processing,
		"current_npc": current_npc_id,
		"queue_size": registry.asset_generation_queue.size() if registry else 0
	}

## Debug: Print generation status
func debug_print_status():
	print("\n=== DYNAMIC NPC GENERATOR STATUS ===")
	print("Is Processing: %s" % is_processing)
	print("Current NPC: %s" % current_npc_id)
	if registry:
		print("Queue Size: %d" % registry.asset_generation_queue.size())
		registry.debug_print_status()
	print("=====================================\n")
