@tool
extends SceneTree
## Run this script from command line to build SpriteFrames for pre-generated characters
## Usage: godot --headless --script scripts/generation/build_pregenerated.gd

const PregeneratedBuilderScript = preload("res://scripts/generation/pregenerated_builder.gd")

func _init():
	print("=== Building Pre-Generated Character SpriteFrames ===")

	var chars_dir = "res://assets/generated/characters"
	var dir = DirAccess.open(chars_dir)

	if not dir:
		print("ERROR: Could not open %s" % chars_dir)
		quit(1)
		return

	var built_count = 0
	var failed_count = 0

	dir.list_dir_begin()
	var folder = dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			print("\nProcessing: %s" % folder)
			var sf = PregeneratedBuilderScript.build_character_sprite_frames(folder)
			if sf:
				if PregeneratedBuilderScript.save_character_sprite_frames(folder, sf):
					built_count += 1
					print("✓ Built %s (%d animations)" % [folder, sf.get_animation_names().size()])
				else:
					failed_count += 1
					print("✗ Failed to save %s" % folder)
			else:
				failed_count += 1
				print("✗ Failed to build %s" % folder)
		folder = dir.get_next()
	dir.list_dir_end()

	print("\n=== Summary ===")
	print("Built: %d" % built_count)
	print("Failed: %d" % failed_count)

	quit(0)
