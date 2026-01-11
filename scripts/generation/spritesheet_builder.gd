class_name SpritesheetBuilder
extends RefCounted
## SpritesheetBuilder - Utility for building SpriteFrames from generated images
## Converts individual animation spritesheets into Godot SpriteFrames resources

const DEFAULT_FPS := 8.0
const DEFAULT_FRAME_SIZE := Vector2i(64, 64)

## Build a SpriteFrames resource from animation data
## animations: Dictionary of { "anim_name": [Texture2D, Texture2D, ...], ... }
## Returns: SpriteFrames resource ready for AnimatedSprite2D
static func build_sprite_frames(animations: Dictionary, fps: float = DEFAULT_FPS) -> SpriteFrames:
	var sprite_frames = SpriteFrames.new()

	# Remove default animation if it exists
	if sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")

	for anim_name in animations:
		var frames = animations[anim_name]
		if frames.size() == 0:
			continue

		sprite_frames.add_animation(anim_name)
		sprite_frames.set_animation_speed(anim_name, fps)
		sprite_frames.set_animation_loop(anim_name, true)

		for frame in frames:
			if frame is Texture2D:
				sprite_frames.add_frame(anim_name, frame)

		print("[SpritesheetBuilder] Added animation '%s' with %d frames at %d FPS" % [anim_name, frames.size(), int(fps)])

	return sprite_frames

## Split a horizontal spritesheet into individual frame textures
## image: The spritesheet Image (frames arranged horizontally)
## frame_size: Size of each frame (default 64x64)
## Returns: Array of Texture2D for each frame
static func split_spritesheet(image: Image, frame_size: Vector2i = DEFAULT_FRAME_SIZE) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []

	if image == null or image.is_empty():
		push_warning("[SpritesheetBuilder] Cannot split empty image")
		return textures

	var frame_count = image.get_width() / frame_size.x

	for i in range(frame_count):
		var frame_rect = Rect2i(i * frame_size.x, 0, frame_size.x, frame_size.y)

		# Ensure we don't read past image bounds
		if frame_rect.position.x + frame_rect.size.x > image.get_width():
			break
		if frame_rect.size.y > image.get_height():
			frame_rect.size.y = image.get_height()

		var frame_image = image.get_region(frame_rect)
		var texture = ImageTexture.create_from_image(frame_image)
		textures.append(texture)

	print("[SpritesheetBuilder] Split spritesheet into %d frames (%dx%d each)" % [textures.size(), frame_size.x, frame_size.y])
	return textures

## Load an image file and split it into frames
## path: Path to the spritesheet image (user://, res://, or absolute)
## frame_size: Size of each frame
## Returns: Array of Texture2D for each frame
static func load_and_split(path: String, frame_size: Vector2i = DEFAULT_FRAME_SIZE) -> Array[Texture2D]:
	var image = Image.new()
	var abs_path = path

	if path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)
	elif path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)

	var err = image.load(abs_path)
	if err != OK:
		push_warning("[SpritesheetBuilder] Failed to load image: %s (error %d)" % [path, err])
		return []

	return split_spritesheet(image, frame_size)

## Create a complete SpriteFrames from character animation files
## character_dir: Path to character's generated assets directory
## directions: Array of direction names ["south", "north", "east", "west"]
## animations: Array of animation names ["idle", "walk"]
## Returns: SpriteFrames with all animations named "{anim}_{direction}" (e.g., "walk_south")
static func build_character_sprite_frames(
	character_dir: String,
	directions: Array = ["south", "north", "east", "west"],
	animations: Array = ["idle", "walk"],
	fps: float = DEFAULT_FPS
) -> SpriteFrames:
	var all_animations: Dictionary = {}

	for direction in directions:
		for anim_name in animations:
			# Expected filename pattern: char_{id}_{anim}_{direction}.png
			# or simplified: {anim}_{direction}.png
			var possible_paths = [
				"%s/%s_%s.png" % [character_dir, anim_name, direction],
				"%s/char_%s_%s.png" % [character_dir, anim_name, direction]
			]

			var found_path = ""
			for p in possible_paths:
				var check_path = p
				if p.begins_with("user://"):
					check_path = ProjectSettings.globalize_path(p)
				if FileAccess.file_exists(check_path):
					found_path = p
					break

			if found_path == "":
				print("[SpritesheetBuilder] Animation file not found for %s_%s" % [anim_name, direction])
				continue

			var frames = load_and_split(found_path)
			if frames.size() > 0:
				var full_anim_name = "%s_%s" % [anim_name, _direction_to_godot(direction)]
				all_animations[full_anim_name] = frames

	return build_sprite_frames(all_animations, fps)

## Convert PixelLab direction names to Godot-friendly names
## "south" -> "down", "north" -> "up", etc.
static func _direction_to_godot(direction: String) -> String:
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

## Create a simple placeholder SpriteFrames with a colored rectangle
## Useful while waiting for AI generation to complete
static func create_placeholder_sprite_frames(color: Color = Color.MAGENTA, size: Vector2i = Vector2i(64, 64)) -> SpriteFrames:
	var placeholder_image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	placeholder_image.fill(color)

	var texture = ImageTexture.create_from_image(placeholder_image)

	var animations = {
		"idle_down": [texture],
		"idle_up": [texture],
		"idle_left": [texture],
		"idle_right": [texture],
		"walk_down": [texture],
		"walk_up": [texture],
		"walk_left": [texture],
		"walk_right": [texture]
	}

	return build_sprite_frames(animations, 1.0)

## Save SpriteFrames resource to disk for caching
static func save_sprite_frames(sprite_frames: SpriteFrames, path: String) -> bool:
	var dir_path = path.get_base_dir()
	var dir = DirAccess.open("user://")

	# Ensure directory exists
	if dir and dir_path.begins_with("user://"):
		var relative_dir = dir_path.substr(7)  # Remove "user://"
		if not dir.dir_exists(relative_dir):
			dir.make_dir_recursive(relative_dir)

	var err = ResourceSaver.save(sprite_frames, path)
	if err != OK:
		push_warning("[SpritesheetBuilder] Failed to save SpriteFrames to: %s (error %d)" % [path, err])
		return false

	print("[SpritesheetBuilder] Saved SpriteFrames to: %s" % path)
	return true

## Load cached SpriteFrames resource
static func load_sprite_frames(path: String) -> SpriteFrames:
	if not ResourceLoader.exists(path):
		return null

	var resource = ResourceLoader.load(path)
	if resource is SpriteFrames:
		print("[SpritesheetBuilder] Loaded cached SpriteFrames from: %s" % path)
		return resource

	return null
