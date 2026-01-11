@tool
class_name PregeneratedBuilder
extends RefCounted
## PregeneratedBuilder - Builds Godot resources from pre-generated PixelLab assets
## Used during development to convert MCP-generated assets into Godot-compatible formats

const BASE_PATH := "res://assets/generated"

## Direction mapping from PixelLab to Godot-friendly names
const DIRECTION_MAP := {
	"south": "down",
	"north": "up",
	"east": "right",
	"west": "left",
	"south-east": "down_right",
	"south-west": "down_left",
	"north-east": "up_right",
	"north-west": "up_left"
}

## Animation mapping from PixelLab to Godot-friendly names
const ANIM_MAP := {
	"breathing-idle": "idle",
	"walk": "walk"
}

## Helper to convert res:// path to absolute path
static func _to_absolute(res_path: String) -> String:
	return ProjectSettings.globalize_path(res_path)

## Helper to load texture from file (bypasses resource import)
static func _load_texture_from_file(res_path: String) -> Texture2D:
	var abs_path = _to_absolute(res_path)
	if not FileAccess.file_exists(abs_path):
		return null
	var image = Image.new()
	var err = image.load(abs_path)
	if err != OK:
		return null
	return ImageTexture.create_from_image(image)

## Build SpriteFrames from a pre-generated character directory
## character_id: ID of the character (matches folder name)
## Returns: SpriteFrames resource or null if failed
static func build_character_sprite_frames(character_id: String) -> SpriteFrames:
	var char_dir = "%s/characters/%s" % [BASE_PATH, character_id]

	# Check if directory exists
	if not DirAccess.dir_exists_absolute(_to_absolute(char_dir)):
		push_warning("[PregeneratedBuilder] Character directory not found: %s" % char_dir)
		return null

	var sprite_frames = SpriteFrames.new()

	# Remove default animation
	if sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")

	# Load rotation images for idle fallbacks
	var rotations := {}
	var rot_dir = "%s/rotations" % char_dir
	for pixellab_dir in DIRECTION_MAP:
		var godot_dir = DIRECTION_MAP[pixellab_dir]
		var rot_path = "%s/%s.png" % [rot_dir, pixellab_dir]
		var tex = _load_texture_from_file(rot_path)
		if tex:
			rotations[godot_dir] = tex
			print("[PregeneratedBuilder] Loaded rotation: %s" % pixellab_dir)

	# Load animations
	var anim_dir = "%s/animations" % char_dir
	var animations_loaded := {}

	for pixellab_anim in ANIM_MAP:
		var godot_anim = ANIM_MAP[pixellab_anim]
		var anim_type_dir = "%s/%s" % [anim_dir, pixellab_anim]

		# Check each direction
		for pixellab_dir in DIRECTION_MAP:
			var godot_dir = DIRECTION_MAP[pixellab_dir]
			var dir_path = "%s/%s" % [anim_type_dir, pixellab_dir]
			var anim_name = "%s_%s" % [godot_anim, godot_dir]

			# Load all frames for this animation
			var frames: Array[Texture2D] = []
			var frame_idx = 0
			while true:
				var frame_path = "%s/frame_%03d.png" % [dir_path, frame_idx]
				var tex = _load_texture_from_file(frame_path)
				if tex:
					frames.append(tex)
					frame_idx += 1
				else:
					break

			if frames.size() > 0:
				animations_loaded[anim_name] = frames

	# Add loaded animations to SpriteFrames
	for anim_name in animations_loaded:
		var frames = animations_loaded[anim_name]
		sprite_frames.add_animation(anim_name)
		sprite_frames.set_animation_speed(anim_name, 8.0)
		sprite_frames.set_animation_loop(anim_name, true)
		for frame in frames:
			sprite_frames.add_frame(anim_name, frame)
		print("[PregeneratedBuilder] Added %s with %d frames" % [anim_name, frames.size()])

	# Add idle fallbacks using rotations where animations are missing
	var required_idles = ["idle_down", "idle_up", "idle_left", "idle_right"]
	for idle_name in required_idles:
		if not sprite_frames.has_animation(idle_name):
			var dir = idle_name.split("_")[1]
			if rotations.has(dir):
				sprite_frames.add_animation(idle_name)
				sprite_frames.set_animation_speed(idle_name, 1.0)
				sprite_frames.set_animation_loop(idle_name, true)
				sprite_frames.add_frame(idle_name, rotations[dir])
				print("[PregeneratedBuilder] Added %s from rotation fallback" % idle_name)

	# Add walk fallbacks using rotations where animations are missing
	var required_walks = ["walk_down", "walk_up", "walk_left", "walk_right"]
	for walk_name in required_walks:
		if not sprite_frames.has_animation(walk_name):
			var dir = walk_name.split("_")[1]
			if rotations.has(dir):
				sprite_frames.add_animation(walk_name)
				sprite_frames.set_animation_speed(walk_name, 8.0)
				sprite_frames.set_animation_loop(walk_name, true)
				sprite_frames.add_frame(walk_name, rotations[dir])
				print("[PregeneratedBuilder] Added %s from rotation fallback" % walk_name)

	return sprite_frames

## Save SpriteFrames to the character's directory
static func save_character_sprite_frames(character_id: String, sprite_frames: SpriteFrames) -> bool:
	var save_path = "%s/characters/%s/sprite_frames.tres" % [BASE_PATH, character_id]
	var err = ResourceSaver.save(sprite_frames, save_path)
	if err != OK:
		push_warning("[PregeneratedBuilder] Failed to save: %s (error %d)" % [save_path, err])
		return false
	print("[PregeneratedBuilder] Saved SpriteFrames to: %s" % save_path)
	return true

## Build and save SpriteFrames for a character (convenience method)
static func build_and_save_character(character_id: String) -> bool:
	var sf = build_character_sprite_frames(character_id)
	if sf == null:
		return false
	return save_character_sprite_frames(character_id, sf)

## Build all pre-generated characters
static func build_all_characters() -> int:
	var count = 0
	var chars_dir = "%s/characters" % BASE_PATH
	var dir = DirAccess.open(chars_dir)
	if dir:
		dir.list_dir_begin()
		var folder = dir.get_next()
		while folder != "":
			if dir.current_is_dir() and not folder.begins_with("."):
				if build_and_save_character(folder):
					count += 1
			folder = dir.get_next()
		dir.list_dir_end()
	return count
