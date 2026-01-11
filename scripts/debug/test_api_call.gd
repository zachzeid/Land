extends SceneTree
# Test actual Claude API call

func _init():
	print("\n=== Claude API Integration Test ===\n")
	
	# Load API key directly from .env file
	var api_key = ""
	var env_path = "res://.env"
	if FileAccess.file_exists(env_path):
		var file = FileAccess.open(env_path, FileAccess.READ)
		while not file.eof_reached():
			var line = file.get_line().strip_edges()
			if line.begins_with("CLAUDE_API_KEY="):
				api_key = line.substr(15).strip_edges()
				# Remove quotes if present
				if api_key.begins_with("'") or api_key.begins_with('"'):
					api_key = api_key.substr(1, api_key.length() - 2)
				break
		file.close()
	
	if api_key.is_empty() or api_key == "your_claude_api_key_here":
		print("❌ ERROR: Claude API key not found in .env file")
		print("Please add your key: CLAUDE_API_KEY=sk-ant-...")
		print("\n=== Test Complete ===\n")
		quit()
		return
	
	var claude_client = load("res://scripts/dialogue/claude_client.gd").new()
	root.add_child(claude_client)
	
	# Set API key manually for testing
	claude_client.api_key_override = api_key
	
	# Connect signals
	claude_client.response_received.connect(_on_response)
	claude_client.error_occurred.connect(_on_error)
	
	print("Sending test message to Claude API...")
	print("(This will use a small amount of tokens)\n")
	
	var messages = [
		{"role": "user", "content": "Say 'API test successful' in exactly 3 words."}
	]
	
	var system_prompt = "You are a helpful test assistant. Follow instructions precisely."
	
	# Call API
	var result = await claude_client.send_message(messages, system_prompt)
	
	# Print results
	if result.has("error"):
		print("❌ ERROR: %s\n" % result.error)
		if result.has("status_code"):
			print("Status Code: %d" % result.status_code)
	elif result.has("text"):
		print("✅ SUCCESS!")
		print("\nResponse from Claude:")
		var separator = ""
		for i in range(50):
			separator += "─"
		print(separator)
		print(result.text)
		print(separator)
		print("\nAPI Details:")
		print("  Model: %s" % result.get("model", "unknown"))
		print("  Stop Reason: %s" % result.get("stop_reason", "unknown"))
		
		if result.has("usage"):
			var usage = result.usage
			print("\nToken Usage:")
			print("  Input tokens: %d" % usage.get("input_tokens", 0))
			print("  Output tokens: %d" % usage.get("output_tokens", 0))
			print("  Total tokens: %d" % (usage.get("input_tokens", 0) + usage.get("output_tokens", 0)))
		
		var stats = claude_client.get_usage_stats()
		print("\nEstimated Cost: $%.6f" % stats.estimated_cost_usd)
	
	print("\n=== Test Complete ===\n")
	quit()

func _on_response(data: Dictionary):
	pass  # Handled in main flow

func _on_error(msg: String):
	pass  # Handled in main flow
