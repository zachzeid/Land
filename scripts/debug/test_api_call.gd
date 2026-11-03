extends SceneTree

# Live Claude API round trip through ClaudeClient: one short message, response text, model, usage and cost
# Makes a PAID API call, so it runs only with: -- --live (key from Config: CLAUDE_API_KEY env, user://.env or res://.env)
# Run: godot --headless --path . -s res://scripts/debug/test_api_call.gd -- --live

const Support = preload("res://scripts/debug/legacy_test_support.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	print("============================================================")
	print("🧪 CLAUDE API LIVE TEST")
	print("============================================================\n")
	if not Support.live_requested():
		print(Support.SKIP_LIVE)
		quit(0)
		return
	Support.start_watchdog(self, "CLAUDE API LIVE TEST")
	Support.guard_save(self)
	var config = root.get_node_or_null("Config")
	if config == null or config.get_claude_api_key().is_empty():
		print("SKIP (no Claude API key: set CLAUDE_API_KEY or user://.env)")
		quit(0)
		return

	var client = load("res://scripts/dialogue/claude_client.gd").new()
	root.add_child(client)
	print("Sending one short message (uses a small number of tokens)...")
	var result = await client.send_message([{"role": "user", "content": "Say 'API test successful' in exactly 3 words."}], "You are a helpful test assistant. Follow instructions precisely.")
	_check("No error (%s)" % result.get("error", "ok"), not result.has("error"))
	_check("Response text", result.get("text", "") != "")
	_check("Model reported", result.get("model", "") != "")
	var usage = result.get("usage", {})
	_check("Token usage reported", usage.get("input_tokens", 0) > 0 and usage.get("output_tokens", 0) > 0)
	if result.has("text"):
		print("\n  Claude: %s" % result.text)
		print("  Estimated cost: $%.6f" % client.get_usage_stats().estimated_cost_usd)
	client.queue_free()
	_finish()

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1

func _finish():
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)
