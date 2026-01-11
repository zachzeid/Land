extends SceneTree
## CLI tool to build sprite_frames.tres from PixelLab downloaded assets
## Usage: godot --headless --script scripts/debug/build_sprite_frames.gd -- [character_folder_name]
##
## Examples:
##   godot --headless --script scripts/debug/build_sprite_frames.gd -- gregor_merchant
##   godot --headless --script scripts/debug/build_sprite_frames.gd -- all

const ASSET_DIR = "res://assets/generated/characters/"
const DEFAULT_FPS := 8.0

## PixelLab animation names to Godot animation names
const ANIMATION_MAP := {
	"breathing-idle": "idle",
	"walking": "walk",
	"running": "run",
	"attack": "attack"
}

## PixelLab direction names to Godot direction names
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

func _init():
	var args = OS.get_cmdline_user_args()

	print("\n" + "=".repeat(60))
	print("SPRITE FRAMES BUILDER")
	print("=".repeat(60))

	if args.is_empty() or "--help" in args:
		_print_help()
		quit(0)
		return

	var target = args[0]

	if target == "all":
		_build_all()
	else:
		_build_character(target)

	quit(0)

func _print_help():
	print("""
Usage: godot --headless --script scripts/debug/build_sprite_frames.gd -- [target]

Arguments:
  <character_name>   Build sprite_frames.tres for a specific character
  all                Build for all characters in assets/generated/characters/
  --help             Show this help message

Example:
  godot --headless --script scripts/debug/build_sprite_frames.gd -- gregor_merchant
""")

func _build_all():
	var global_path = ProjectSettings.globalize_path(ASSET_DIR)
	var dir = DirAccess.open(global_path)

	if not dir:
		print("ERROR: Cannot open directory: %s" % global_path)
		return

	dir.list_dir_begin()
	var folder = dir.get_next()
	var built_count = 0

	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			print("\n--- Processing: %s ---" % folder)
			if _build_character(folder):
				built_count += 1
		folder = dir.get_next()

	dir.list_dir_end()
	print("\n=== Built %d sprite_frames.tres files ===" % built_count)

func _build_character(folder_name: String) -> bool:
	var char_dir = ASSET_DIR + folder_name
	var global_char_dir = ProjectSettings.globalize_path(char_dir)

	if not DirAccess.dir_exists_absolute(global_char_dir):
		print("ERROR: Character directory not found: %s" % global_char_dir)
		return false

	var animations_dir = global_char_dir + "/animations"
	var rotations_dir = global_char_dir + "/rotations"

	# Check if animations directory exists
	if not DirAccess.dir_exists_absolute(animations_dir):
		print("WARNING: No animations directory found for %s" % folder_name)
		# Try to build from rotations only (static)
		return _build_from_rotations_only(folder_name, rotations_dir)

	print("Building sprite_frames.tres for: %s" % folder_name)

	var sprite_frames = SpriteFrames.new()

	# Remove default animation
	if sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")

	# Scan animations directory
	var anim_dir = DirAccess.open(animations_dir)
	if not anim_dir:
		print("ERROR: Cannot open animations directory")
		return false

	var anim_count = 0
	anim_dir.list_dir_begin()
	var anim_folder = anim_dir.get_next()

	while anim_folder != "":
		if anim_dir.current_is_dir() and not anim_folder.begins_with("."):
			var godot_anim_name = ANIMATION_MAP.get(anim_folder, anim_folder)
			print("  Found animation: %s -> %s" % [anim_folder, godot_anim_name])

			# Process each direction in this animation
			var anim_path = animations_dir + "/" + anim_folder
			anim_count += _process_animation_directions(sprite_frames, anim_path, godot_anim_name)

		anim_folder = anim_dir.get_next()

	anim_dir.list_dir_end()

	if anim_count == 0:
		print("WARNING: No animations found for %s" % folder_name)
		return false

	# Save the sprite_frames.tres
	var output_path = char_dir + "/sprite_frames.tres"
	var err = ResourceSaver.save(sprite_frames, output_path)

	if err != OK:
		print("ERROR: Failed to save sprite_frames.tres (error %d)" % err)
		return false

	print("SUCCESS: Saved %s with %d animations" % [output_path, anim_count])
	return true

func _process_animation_directions(sprite_frames: SpriteFrames, anim_path: String, anim_name: String) -> int:
	var dir = DirAccess.open(anim_path)
	if not dir:
		return 0

	var count = 0
	dir.list_dir_begin()
	var direction_folder = dir.get_next()

	while direction_folder != "":
		if dir.current_is_dir() and not direction_folder.begins_with("."):
			var godot_direction = DIRECTION_MAP.get(direction_folder, direction_folder)
			var full_anim_name = "%s_%s" % [anim_name, godot_direction]

			var frames_path = anim_path + "/" + direction_folder
			var frames = _load_animation_frames(frames_path)

			if frames.size() > 0:
				sprite_frames.add_animation(full_anim_name)
				sprite_frames.set_animation_speed(full_anim_name, DEFAULT_FPS)
				sprite_frames.set_animation_loop(full_anim_name, true)

				for frame in frames:
					sprite_frames.add_frame(full_anim_name, frame)

				print("    Added: %s (%d frames)" % [full_anim_name, frames.size()])
				count += 1

		direction_folder = dir.get_next()

	dir.list_dir_end()
	return count

func _load_animation_frames(frames_path: String) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	var dir = DirAccess.open(frames_path)

	if not dir:
		return textures

	# Collect frame files
	var frame_files: Array[String] = []
	dir.list_dir_begin()
	var file = dir.get_next()

	while file != "":
		if not dir.current_is_dir() and file.ends_with(".png"):
			frame_files.append(file)
		file = dir.get_next()

	dir.list_dir_end()

	# Sort by frame number (frame_000.png, frame_001.png, etc.)
	frame_files.sort()

	# Load each frame
	for frame_file in frame_files:
		var full_path = frames_path + "/" + frame_file
		var image = Image.new()
		var err = image.load(full_path)

		if err == OK:
			var texture = ImageTexture.create_from_image(image)
			textures.append(texture)

	return textures

func _build_from_rotations_only(folder_name: String, rotations_dir: String) -> bool:
	if not DirAccess.dir_exists_absolute(rotations_dir):
		print("ERROR: No rotations directory found either")
		return false

	print("Building static sprite_frames from rotations only for: %s" % folder_name)

	var sprite_frames = SpriteFrames.new()

	if sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")

	var dir = DirAccess.open(rotations_dir)
	if not dir:
		return false

	var count = 0
	dir.list_dir_begin()
	var file = dir.get_next()

	while file != "":
		if not dir.current_is_dir() and file.ends_with(".png"):
			var direction = file.get_basename()
			var godot_direction = DIRECTION_MAP.get(direction, direction)

			var full_path = rotations_dir + "/" + file
			var image = Image.new()
			var err = image.load(full_path)

			if err == OK:
				var texture = ImageTexture.create_from_image(image)

				# Create idle animation for this direction
				var anim_name = "idle_%s" % godot_direction
				sprite_frames.add_animation(anim_name)
				sprite_frames.set_animation_speed(anim_name, 1.0)
				sprite_frames.set_animation_loop(anim_name, false)
				sprite_frames.add_frame(anim_name, texture)

				print("  Added static: %s" % anim_name)
				count += 1

		file = dir.get_next()

	dir.list_dir_end()

	if count == 0:
		return false

	var output_path = ASSET_DIR + folder_name + "/sprite_frames.tres"
	var err = ResourceSaver.save(sprite_frames, output_path)

	if err != OK:
		print("ERROR: Failed to save sprite_frames.tres (error %d)" % err)
		return false

	print("SUCCESS: Saved %s with %d static directions" % [output_path, count])
	return true
