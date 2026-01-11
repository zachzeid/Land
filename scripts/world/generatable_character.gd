@tool
extends Node
class_name GeneratableCharacter
## GeneratableCharacter - Component for AI-generated character sprites with animations
## Attach to Player or NPC nodes to generate animated sprites from text descriptions
##
## Features:
## - Generates 64x64 character sprites with transparent backgrounds
## - Creates 4 directional views (up, down, left, right)
## - Generates walk and idle animations for each direction
## - Builds SpriteFrames resource for AnimatedSprite2D
## - Caches generated assets for instant loading on subsequent runs
##
## Asset loading priority:
## 1. Pre-generated assets (res://assets/generated/characters/) - fastest, offline
## 2. Runtime cache (user://generated_characters/) - previously generated
## 3. Runtime generation (API call) - slowest, requires network

const PregeneratedLoaderScript = preload("res://scripts/generation/pregenerated_loader.gd")

## Unique identifier for this character (used for caching)
@export var character_id: String = ""

## Text description of the character's appearance for AI generation
@export_multiline var appearance_prompt: String = ""

## Whether to auto-generate on ready if not cached
@export var auto_generate: bool = false

## Color to use for placeholder while generating
@export var placeholder_color: Color = Color(0.6, 0.3, 0.8, 1.0)

## Reference to the AnimatedSprite2D to apply textures to
## If not set, will search for sibling AnimatedSprite2D
var animated_sprite: AnimatedSprite2D = null

## Current SpriteFrames resource
var sprite_frames: SpriteFrames = null

## Generation state
var is_generating: bool = false
var is_loaded: bool = false
var generation_error: String = ""

signal character_ready(sprite_frames: SpriteFrames)
signal character_failed(error: String)
signal generation_progress(stage: String, progress: float)

func _ready():
	if Engine.is_editor_hint():
		return

	# Auto-generate ID from parent node if not set
	if character_id.is_empty():
		character_id = _generate_character_id()

	# Try to inherit appearance_prompt from parent if not set
	if appearance_prompt.is_empty():
		_try_get_parent_appearance()

	# Find AnimatedSprite2D sibling
	_find_animated_sprite()

	# Connect to CharacterGen signals
	if CharacterGen:
		if not CharacterGen.character_ready.is_connected(_on_character_ready):
			CharacterGen.character_ready.connect(_on_character_ready)
		if not CharacterGen.character_failed.is_connected(_on_character_failed):
			CharacterGen.character_failed.connect(_on_character_failed)
		if not CharacterGen.generation_progress.is_connected(_on_generation_progress):
			CharacterGen.generation_progress.connect(_on_generation_progress)

	# Try to load from cache
	call_deferred("_try_load_cached")

func _generate_character_id() -> String:
	var parent = get_parent()
	if parent:
		# Use parent's npc_id if available
		if "npc_id" in parent and parent.npc_id != "":
			return parent.npc_id
		# Use parent's name
		return parent.name.to_snake_case()
	return "character_%d" % get_instance_id()

func _try_get_parent_appearance():
	var parent = get_parent()
	if parent and "appearance_prompt" in parent:
		var parent_prompt = parent.appearance_prompt
		if parent_prompt != "":
			appearance_prompt = parent_prompt
			print("[GeneratableCharacter] Using parent's appearance_prompt for %s" % character_id)

func _find_animated_sprite():
	var parent = get_parent()
	if not parent:
		return

	# Look for sibling AnimatedSprite2D
	for child in parent.get_children():
		if child is AnimatedSprite2D:
			animated_sprite = child
			print("[GeneratableCharacter] Found AnimatedSprite2D sibling")
			return

	# Look for child named "AnimatedSprite2D"
	if parent.has_node("AnimatedSprite2D"):
		animated_sprite = parent.get_node("AnimatedSprite2D")
		print("[GeneratableCharacter] Found AnimatedSprite2D child")

func _try_load_cached():
	# Priority 1: Check pre-generated assets (res://assets/generated/characters/)
	if _try_load_pregenerated():
		return

	# Priority 2: Check runtime cache (user://generated_characters/)
	if CharacterGen and CharacterGen.is_cached(character_id):
		sprite_frames = CharacterGen.get_cached(character_id)
		if sprite_frames:
			print("[GeneratableCharacter] Loaded from runtime cache: %s" % character_id)
			_apply_sprite_frames(sprite_frames)
			return

	# Priority 3: Apply placeholder and generate at runtime if auto_generate is on
	_apply_placeholder()

	if auto_generate and not appearance_prompt.is_empty():
		print("[GeneratableCharacter] Auto-generating (no pre-generated or cached): %s" % character_id)
		generate()

## Try to load from pre-generated assets (res://assets/generated/characters/)
func _try_load_pregenerated() -> bool:
	# Try direct character_id match
	if PregeneratedLoaderScript.has_character(character_id):
		var sf = PregeneratedLoaderScript.load_character(character_id)
		if sf:
			print("[GeneratableCharacter] Loaded pre-generated: %s" % character_id)
			_apply_sprite_frames(sf)
			return true

	# Try base character type (e.g., "villager_1" -> "villager_male")
	# This allows multiple NPCs to share the same base character sprite
	var parent = get_parent()
	if parent and "character_type" in parent:
		var char_type = parent.character_type
		if PregeneratedLoaderScript.has_character(char_type):
			var sf = PregeneratedLoaderScript.load_character(char_type)
			if sf:
				print("[GeneratableCharacter] Loaded pre-generated (type): %s -> %s" % [character_id, char_type])
				_apply_sprite_frames(sf)
				return true

	return false

## Apply placeholder sprite while waiting for generation
func _apply_placeholder():
	if not animated_sprite:
		return

	var placeholder = CharacterGen.create_placeholder(placeholder_color) if CharacterGen else _create_local_placeholder()
	animated_sprite.sprite_frames = placeholder
	animated_sprite.play("idle_down")
	print("[GeneratableCharacter] Applied placeholder for: %s" % character_id)

func _create_local_placeholder() -> SpriteFrames:
	var sf = SpriteFrames.new()

	# Create simple colored placeholder
	var image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(placeholder_color)
	var texture = ImageTexture.create_from_image(image)

	# Add basic animations
	for dir in ["down", "up", "left", "right"]:
		for anim in ["idle", "walk"]:
			var anim_name = "%s_%s" % [anim, dir]
			sf.add_animation(anim_name)
			sf.set_animation_speed(anim_name, 8.0)
			sf.add_frame(anim_name, texture)

	return sf

## Manually trigger character generation
func generate():
	if appearance_prompt.is_empty():
		push_warning("[GeneratableCharacter] No appearance_prompt set for %s" % character_id)
		character_failed.emit("No appearance prompt")
		return

	if not CharacterGen:
		push_warning("[GeneratableCharacter] CharacterGen autoload not available")
		character_failed.emit("CharacterGen not available")
		return

	if is_generating:
		print("[GeneratableCharacter] Already generating: %s" % character_id)
		return

	print("[GeneratableCharacter] Starting generation for: %s" % character_id)
	is_generating = true
	generation_error = ""

	CharacterGen.generate_character(character_id, appearance_prompt)

## Force regeneration (clears cache first)
func regenerate():
	if CharacterGen:
		CharacterGen.clear_cache(character_id)

	is_loaded = false
	sprite_frames = null

	_apply_placeholder()
	generate()

## Apply generated SpriteFrames to AnimatedSprite2D
func _apply_sprite_frames(sf: SpriteFrames):
	sprite_frames = sf
	is_loaded = true
	is_generating = false

	if animated_sprite:
		var current_anim = animated_sprite.animation if animated_sprite.sprite_frames else "idle_down"
		animated_sprite.sprite_frames = sf

		# Try to continue playing the same animation
		if sf.has_animation(current_anim):
			animated_sprite.play(current_anim)
		elif sf.has_animation("idle_down"):
			animated_sprite.play("idle_down")

		print("[GeneratableCharacter] Applied SpriteFrames to %s (%d animations)" % [character_id, sf.get_animation_names().size()])

	character_ready.emit(sf)

## Handle CharacterGen signals
func _on_character_ready(id: String, sf: SpriteFrames):
	if id != character_id:
		return

	print("[GeneratableCharacter] Character ready: %s" % id)
	_apply_sprite_frames(sf)

func _on_character_failed(id: String, error: String):
	if id != character_id:
		return

	is_generating = false
	generation_error = error
	print("[GeneratableCharacter] Character failed: %s - %s" % [id, error])
	character_failed.emit(error)

func _on_generation_progress(id: String, stage: String, progress: float):
	if id != character_id:
		return

	generation_progress.emit(stage, progress)

## Get the current facing direction based on animation name
func get_current_direction() -> String:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return "down"

	var anim = animated_sprite.animation
	if "_" in anim:
		return anim.split("_")[1]  # "walk_down" -> "down"
	return "down"

## Play an animation with direction
func play_animation(anim_type: String, direction: String = ""):
	if not animated_sprite or not sprite_frames:
		return

	if direction.is_empty():
		direction = get_current_direction()

	var anim_name = "%s_%s" % [anim_type, direction]
	if sprite_frames.has_animation(anim_name):
		animated_sprite.play(anim_name)
