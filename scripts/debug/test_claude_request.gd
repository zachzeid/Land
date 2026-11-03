extends SceneTree

# Tests the Claude request and response shapes for Claude Opus 5.5, offline (no API call):
# - the request names claude-opus-5-5, sets effort and fallbacks, and sends no temperature/prefill
# - a reply's text is read from its text blocks, skipping the thinking block that comes first
# - a refusal is reported as one, not as an empty reply
# - a conversation always starts and ends on a user turn
# Run: godot --headless --path . -s res://scripts/debug/test_claude_request.gd

const ClaudeClientScript = preload("res://scripts/dialogue/claude_client.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	print("============================================================")
	print("🧪 CLAUDE REQUEST TEST (offline)")
	print("============================================================\n")

	var src = FileAccess.get_file_as_string("res://scripts/dialogue/claude_client.gd")
	_check("Model is claude-opus-5-5", ClaudeClientScript.MODEL == "claude-opus-5-5")
	_check("max_tokens leaves room for thinking", ClaudeClientScript.MAX_TOKENS >= 8000)
	_check("Effort goes in output_config", '"output_config": {"effort": _effort()}' in src)
	_check("Refusal fallbacks: default with its beta header", '"fallbacks": "default"' in src and ClaudeClientScript.FALLBACK_BETA == "server-side-fallback-2026-07-01")
	_check("No sampling parameters or thinking budget", not ("temperature" in src or "budget_tokens" in src))
	var analyzer = FileAccess.get_file_as_string("res://scripts/generation/scene_analyzer.gd")
	_check("Scene analysis uses the same model and reads text blocks", '"claude-opus-5-5"' in analyzer and "extract_text" in analyzer and "content[0]" not in analyzer)

	var content = [
		{"type": "thinking", "thinking": "", "signature": "x"},
		{"type": "text", "text": "{\"response\": \"Aye.\"}"}]
	_check("Text is read past the thinking block", ClaudeClientScript.extract_text(content) == "{\"response\": \"Aye.\"}")
	_check("No text blocks: empty", ClaudeClientScript.extract_text([{"type": "thinking", "thinking": ""}]) == "")
	var refusal_check = src.find('== "refusal"')
	_check("A refusal is checked before an empty reply is", refusal_check > 0 and refusal_check < src.find('data.content.is_empty()'))

	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	var npc_first = builder._build_message_history([{"speaker": "npc", "message": "Stranger. Sit."}], "")
	_check("An NPC who spoke first still follows a user turn", npc_first[0].role == "user" and npc_first[1].role == "assistant")
	_check("...and the history ends on a user turn (no prefill)", npc_first[-1].role == "user")
	var normal = builder._build_message_history([{"speaker": "player", "message": "Hello"}, {"speaker": "npc", "message": "Hm."}], "What news?")
	_check("A normal turn is unchanged", normal.size() == 3 and normal[0].content == "Hello" and normal[-1].content == "What news?")
	builder.free()

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
