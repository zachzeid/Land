extends SceneTree

func _init():
	print("=== Testing OS.execute() Argument Passing ===")
	
	var output = []
	var exit_code = OS.execute("python3", [
		"-c",
		"import sys; import json; print(json.dumps({'argc': len(sys.argv), 'args': sys.argv}))",
		"collection_name",
		"memory_id", 
		"This is a document with multiple words",
		"base64encodedmetadata"
	], output, true)
	
	print("Exit code: ", exit_code)
	print("Output: ", output)
	
	if output.size() > 0:
		var result = JSON.parse_string(output[0])
		print("\nParsed result:")
		print("  argc: ", result.argc)
		print("  args:")
		for i in range(result.args.size()):
			print("    [%d] = %s" % [i, result.args[i]])
	
	quit()
