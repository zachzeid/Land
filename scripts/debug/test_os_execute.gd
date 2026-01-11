extends SceneTree

func _init():
	print("=== Testing ChromaDB CLI from Godot ===")
	
	var cli_path = ProjectSettings.globalize_path("res://chroma_cli.py")
	print("CLI path: " + cli_path)
	
	var output = []
	var exit_code = OS.execute("python3", [cli_path, "create_collection", "test_godot_exec"], output, true)
	
	print("Exit code: " + str(exit_code))
	print("Output count: " + str(output.size()))
	if output.size() > 0:
		print("Output: " + output[0])
	
	if exit_code == 0 and output.size() > 0:
		print("✓ CLI call successful!")
	else:
		print("✗ CLI call failed - exit code: " + str(exit_code))
	
	quit()
