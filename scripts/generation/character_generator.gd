extends Node
## CharacterGenerator - Orchestrates complete character sprite generation
## Manages the pipeline: base sprite → rotations → animations → SpriteFrames
##
## Usage:
##   CharacterGen.generate_character("elena", "young woman, purple dress...")
##   CharacterGen.character_ready.connect(func(id, sf): ...)

const SpritesheetBuilderScript = preload("res://scripts/generation/spritesheet_builder.gd")

signal generation_started(character_id: String)
signal generation_progress(character_id: String, stage: String, progress: float)
signal character_ready(character_id: String, sprite_frames: SpriteFrames)
signal character_failed(character_id: String, error: String)

## Directions to generate rotations for
const DIRECTIONS := ["south", "north", "east", "west"]

## Animations to generate for each direction
const ANIMATIONS := ["idle", "walk"]

## Rate limiting settings (PixelLab requires spacing between requests)
const BASE_DELAY_SECONDS := 5.0  # Base delay between requests
const MAX_RETRIES := 3  # Maximum retry attempts for 429 errors
const BACKOFF_MULTIPLIER := 2.0  # Exponential backoff multiplier

## Generation state for each character
class CharacterGenState:
	var character_id: String
	var description: String
	var base_sprite_path: String = ""
	var rotation_paths: Dictionary = {}  # direction -> path
	var animation_paths: Dictionary = {}  # "anim_direction" -> path
	var stage: String = "idle"
	var error: String = ""
	var sprite_frames: SpriteFrames = null
	var retry_counts: Dictionary = {}  # request_id -> retry count
	var pending_requests: Dictionary = {}  # request_id -> callable

	func get_progress() -> float:
		# Total steps: 1 base + 4 rotations + 8 animations = 13
		var completed = 0
		if base_sprite_path != "":
			completed += 1
		completed += rotation_paths.size()
		completed += animation_paths.size()
		return float(completed) / 13.0

	func get_retry_count(request_id: String) -> int:
		return retry_counts.get(request_id, 0)

	func increment_retry(request_id: String) -> int:
		var count = retry_counts.get(request_id, 0) + 1
		retry_counts[request_id] = count
		return count

## Active generation states
var _active_generations: Dictionary = {}  # character_id -> CharacterGenState

## Cache of completed SpriteFrames
var _sprite_frames_cache: Dictionary = {}  # character_id -> SpriteFrames

## Reference to PixelLab generator (from AssetGenerator backend)
var _pixellab: Node = null

func _ready():
	# Get PixelLab generator reference
	call_deferred("_setup_pixellab_reference")

func _setup_pixellab_reference():
	if AssetGenerator and AssetGenerator.backends.has("pixellab"):
		_pixellab = AssetGenerator.backends["pixellab"]
		_connect_pixellab_signals()
		print("[CharacterGen] Connected to PixelLab generator")
	else:
		push_warning("[CharacterGen] PixelLab generator not available")

func _connect_pixellab_signals():
	if not _pixellab:
		return

	if not _pixellab.generation_completed.is_connected(_on_pixellab_completed):
		_pixellab.generation_completed.connect(_on_pixellab_completed)
	if not _pixellab.generation_failed.is_connected(_on_pixellab_failed):
		_pixellab.generation_failed.connect(_on_pixellab_failed)
	if _pixellab.has_signal("rotation_completed") and not _pixellab.rotation_completed.is_connected(_on_rotation_completed):
		_pixellab.rotation_completed.connect(_on_rotation_completed)
	if _pixellab.has_signal("animation_completed") and not _pixellab.animation_completed.is_connected(_on_animation_completed):
		_pixellab.animation_completed.connect(_on_animation_completed)

## Check if a character's SpriteFrames is cached
func is_cached(character_id: String) -> bool:
	if _sprite_frames_cache.has(character_id):
		return true

	# Check for saved resource file
	var cache_path = _get_cache_path(character_id)
	return ResourceLoader.exists(cache_path)

## Get cached SpriteFrames for a character
func get_cached(character_id: String) -> SpriteFrames:
	if _sprite_frames_cache.has(character_id):
		return _sprite_frames_cache[character_id]

	var cache_path = _get_cache_path(character_id)
	var loaded = SpritesheetBuilderScript.load_sprite_frames(cache_path)
	if loaded:
		_sprite_frames_cache[character_id] = loaded
		return loaded

	return null

## Check if generation is in progress for a character
func is_generating(character_id: String) -> bool:
	return _active_generations.has(character_id)

## Generate a complete character with rotations and animations
## Returns immediately; listen for character_ready signal
func generate_character(character_id: String, description: String, force_regenerate: bool = false) -> void:
	# Check cache first
	if not force_regenerate and is_cached(character_id):
		var cached = get_cached(character_id)
		if cached:
			print("[CharacterGen] Using cached SpriteFrames for: %s" % character_id)
			character_ready.emit(character_id, cached)
			return

	# Check if already generating
	if is_generating(character_id):
		print("[CharacterGen] Already generating: %s" % character_id)
		return

	# Ensure PixelLab is available
	if not _pixellab or not _pixellab.is_available():
		character_failed.emit(character_id, "PixelLab generator not available")
		return

	print("[CharacterGen] ========== Starting character generation ==========")
	print("[CharacterGen] Character ID: %s" % character_id)
	print("[CharacterGen] Description: %s" % description.left(60))

	# Create generation state
	var state = CharacterGenState.new()
	state.character_id = character_id
	state.description = description
	state.stage = "base_sprite"
	_active_generations[character_id] = state

	generation_started.emit(character_id)
	generation_progress.emit(character_id, "base_sprite", 0.0)

	# Start with base sprite generation
	_pixellab.generate_character_sprite(character_id, description)

## Handle PixelLab generation completed
func _on_pixellab_completed(request_id: String, image_path: String):
	# Check if this is for one of our active generations
	var character_id = _extract_character_id(request_id)
	if not _active_generations.has(character_id):
		return

	var state = _active_generations[character_id]

	# Determine what just completed based on request_id pattern
	if state.stage == "base_sprite" and request_id == character_id:
		_handle_base_sprite_complete(state, image_path)
	elif "_rot_" in request_id:
		var direction = request_id.split("_rot_")[1] if "_rot_" in request_id else ""
		_handle_rotation_complete(state, direction, image_path)
	elif "_anim_" in request_id:
		var parts = request_id.split("_anim_")
		if parts.size() > 1:
			var anim_dir = parts[1]  # e.g., "walk_south"
			_handle_animation_complete(state, anim_dir, image_path)

func _on_rotation_completed(request_id: String, image_path: String, direction: String):
	var character_id = _extract_character_id(request_id)
	if not _active_generations.has(character_id):
		return

	var state = _active_generations[character_id]
	_handle_rotation_complete(state, direction, image_path)

func _on_animation_completed(request_id: String, image_path: String, action: String, frame_count: int):
	var character_id = _extract_character_id(request_id)
	if not _active_generations.has(character_id):
		return

	var state = _active_generations[character_id]
	# The request_id contains direction info
	var parts = request_id.split("_anim_")
	if parts.size() > 1:
		_handle_animation_complete(state, parts[1], image_path)

func _on_pixellab_failed(request_id: String, error: String):
	var character_id = _extract_character_id(request_id)
	if not _active_generations.has(character_id):
		return

	var state = _active_generations[character_id]

	# Check if this is a rate limit error (429)
	if "429" in error or "rate" in error.to_lower() or "wait" in error.to_lower():
		var retry_count = state.increment_retry(request_id)

		if retry_count <= MAX_RETRIES:
			# Calculate exponential backoff delay
			var backoff_delay = BASE_DELAY_SECONDS * pow(BACKOFF_MULTIPLIER, retry_count)
			print("[CharacterGen] Rate limited on %s, retry %d/%d in %.1fs" % [
				request_id, retry_count, MAX_RETRIES, backoff_delay
			])

			# Retry the request after backoff delay
			if state.pending_requests.has(request_id):
				var request_callable = state.pending_requests[request_id]
				get_tree().create_timer(backoff_delay).timeout.connect(request_callable, CONNECT_ONE_SHOT)
				return  # Don't fail yet, we're retrying
			else:
				print("[CharacterGen] WARNING: No pending request found for retry: %s" % request_id)

		print("[CharacterGen] Max retries exceeded for %s" % request_id)

	# Non-retryable error or retries exhausted
	state.error = error
	print("[CharacterGen] Generation failed for %s: %s" % [character_id, error])

	_active_generations.erase(character_id)
	character_failed.emit(character_id, error)

## Handle base sprite completion - start rotations
func _handle_base_sprite_complete(state: CharacterGenState, image_path: String):
	state.base_sprite_path = image_path
	state.stage = "rotations"

	print("[CharacterGen] Base sprite complete: %s" % image_path)
	generation_progress.emit(state.character_id, "rotations", state.get_progress())

	# Generate rotations for each direction with delays to avoid rate limiting
	_queue_rotations(state, image_path)

## Queue rotation requests with delays between them
func _queue_rotations(state: CharacterGenState, image_path: String):
	var delay = 0.0
	for direction in DIRECTIONS:
		var request_id = "%s_rot_%s" % [state.character_id, direction]
		# Store the request callable for potential retries
		var request_callable = func(): _pixellab.generate_rotation(request_id, image_path, direction)
		state.pending_requests[request_id] = request_callable
		# Stagger requests by BASE_DELAY_SECONDS to avoid rate limiting
		print("[CharacterGen] Scheduling rotation '%s' in %.1fs" % [direction, delay])
		get_tree().create_timer(delay).timeout.connect(request_callable, CONNECT_ONE_SHOT)
		delay += BASE_DELAY_SECONDS

## Handle rotation completion - check if all rotations done, then start animations
func _handle_rotation_complete(state: CharacterGenState, direction: String, image_path: String):
	state.rotation_paths[direction] = image_path

	print("[CharacterGen] Rotation complete: %s -> %s" % [direction, image_path])
	generation_progress.emit(state.character_id, "rotations", state.get_progress())

	# Check if all rotations are done
	if state.rotation_paths.size() >= DIRECTIONS.size():
		state.stage = "animations"
		_start_animation_generation(state)

## Start generating animations for all directions
func _start_animation_generation(state: CharacterGenState):
	print("[CharacterGen] Starting animation generation...")
	generation_progress.emit(state.character_id, "animations", state.get_progress())

	# Queue animations with delays to avoid rate limiting
	var delay = 0.0
	for direction in DIRECTIONS:
		if not state.rotation_paths.has(direction):
			continue

		var rotation_path = state.rotation_paths[direction]

		for anim in ANIMATIONS:
			var request_id = "%s_anim_%s_%s" % [state.character_id, anim, direction]
			var anim_description = "%s %s animation cycle" % [state.description.left(40), anim]
			# Store the request callable for potential retries
			var request_callable = func(): _pixellab.generate_animation_frames(request_id, rotation_path, anim, anim_description)
			state.pending_requests[request_id] = request_callable
			# Stagger requests by BASE_DELAY_SECONDS to avoid rate limiting
			print("[CharacterGen] Scheduling animation '%s_%s' in %.1fs" % [anim, direction, delay])
			get_tree().create_timer(delay).timeout.connect(request_callable, CONNECT_ONE_SHOT)
			delay += BASE_DELAY_SECONDS

## Handle animation completion - check if all done, then build SpriteFrames
func _handle_animation_complete(state: CharacterGenState, anim_dir: String, image_path: String):
	state.animation_paths[anim_dir] = image_path

	print("[CharacterGen] Animation complete: %s -> %s" % [anim_dir, image_path])
	generation_progress.emit(state.character_id, "animations", state.get_progress())

	# Check if all animations are done (4 directions x 2 animations = 8)
	var expected_count = DIRECTIONS.size() * ANIMATIONS.size()
	if state.animation_paths.size() >= expected_count:
		_finalize_character(state)

## Build final SpriteFrames and emit completion
func _finalize_character(state: CharacterGenState):
	print("[CharacterGen] ========== Finalizing character ==========")
	state.stage = "building"

	# Build SpriteFrames from all animation spritesheets
	var all_animations: Dictionary = {}

	for anim_key in state.animation_paths:
		var path = state.animation_paths[anim_key]
		var frames = SpritesheetBuilderScript.load_and_split(path)

		if frames.size() > 0:
			# Convert anim_key (e.g., "walk_south") to Godot-friendly name (e.g., "walk_down")
			var parts = anim_key.split("_")
			if parts.size() >= 2:
				var anim_name = parts[0]
				var direction = parts[1]
				var godot_dir = _direction_to_godot(direction)
				var full_name = "%s_%s" % [anim_name, godot_dir]
				all_animations[full_name] = frames
				print("[CharacterGen]   Added: %s (%d frames)" % [full_name, frames.size()])

	if all_animations.is_empty():
		print("[CharacterGen] ERROR: No animations built!")
		_active_generations.erase(state.character_id)
		character_failed.emit(state.character_id, "Failed to build animations")
		return

	# Build SpriteFrames
	state.sprite_frames = SpritesheetBuilderScript.build_sprite_frames(all_animations)

	# Cache the result
	_sprite_frames_cache[state.character_id] = state.sprite_frames

	# Save to disk for persistence
	var cache_path = _get_cache_path(state.character_id)
	SpritesheetBuilderScript.save_sprite_frames(state.sprite_frames, cache_path)

	# Cleanup
	_active_generations.erase(state.character_id)

	print("[CharacterGen] ========== Character complete: %s ==========" % state.character_id)
	character_ready.emit(state.character_id, state.sprite_frames)

## Get cache path for a character's SpriteFrames
func _get_cache_path(character_id: String) -> String:
	return "user://generated_characters/%s/sprite_frames.tres" % character_id

## Extract character ID from request ID
## "elena_rot_south" -> "elena"
## "elena_anim_walk_south" -> "elena"
func _extract_character_id(request_id: String) -> String:
	if "_rot_" in request_id:
		return request_id.split("_rot_")[0]
	elif "_anim_" in request_id:
		return request_id.split("_anim_")[0]
	return request_id

## Convert PixelLab direction to Godot direction
func _direction_to_godot(direction: String) -> String:
	match direction.to_lower():
		"south", "s":
			return "down"
		"north", "n":
			return "up"
		"east", "e":
			return "right"
		"west", "w":
			return "left"
		_:
			return direction

## Cancel generation for a character
func cancel_generation(character_id: String):
	if _active_generations.has(character_id):
		_active_generations.erase(character_id)
		print("[CharacterGen] Cancelled generation for: %s" % character_id)

## Clear cache for a character
func clear_cache(character_id: String):
	_sprite_frames_cache.erase(character_id)

	# Remove saved files
	var dir_path = "user://generated_characters/%s" % character_id
	var dir = DirAccess.open("user://")
	if dir and dir.dir_exists(dir_path.substr(7)):  # Remove "user://"
		# Delete all files in directory
		var char_dir = DirAccess.open(dir_path)
		if char_dir:
			char_dir.list_dir_begin()
			var file = char_dir.get_next()
			while file != "":
				if not char_dir.current_is_dir():
					char_dir.remove(file)
				file = char_dir.get_next()
			char_dir.list_dir_end()

		# Remove directory
		dir.remove(dir_path.substr(7))

	print("[CharacterGen] Cleared cache for: %s" % character_id)

## Create a placeholder SpriteFrames while waiting for generation
func create_placeholder(color: Color = Color.MAGENTA) -> SpriteFrames:
	return SpritesheetBuilderScript.create_placeholder_sprite_frames(color)
