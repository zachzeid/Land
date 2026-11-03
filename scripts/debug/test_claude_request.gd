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

	_test_cache_blocks()
	_test_telemetry()

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1

## Prompt caching: ContextBuilder's tiers become system blocks with a breakpoint after each stable one
func _test_cache_blocks():
	print("\nPrompt caching")
	var registry = root.get_node("WorldRegistry")
	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	var npc_id = registry.get_npc_id("gregor")
	var params = {"personality": load("res://resources/npc_personalities/gregor_merchant.tres"), "npc_id": npc_id,
		"tiered_memories": {"pinned": [], "important": ["The stranger watched the drawing."], "relevant": []},
		"relationship_dimensions": {"trust": 10, "respect": 5, "affection": 0, "fear": 0, "familiarity": 10},
		"world_state": {"npc_id": npc_id, "world_flags": {}, "active_quests": []}, "conversation_history": [], "player_input": "Hello"}
	var first: Dictionary = builder.build_context(params)
	var blocks: Array = first.system_blocks
	_check("Three blocks: stable, storyline, per-turn", blocks.size() == 3 and blocks[0].cache and blocks[1].cache and not blocks[2].cache)
	_check("The blocks are the whole prompt, in order", "".join(blocks.map(func(b): return b.text)) == first.system_prompt)
	_check("The stable block opens with the response format", blocks[0].text.begins_with(builder._build_response_format_section()))
	_check("The storyline layer is the second block", blocks[1].text == builder._build_storyline_section(npc_id))
	_check("The stable block is over the 512-token cache minimum (chars/4)", blocks[0].text.length() / 4 > 512)
	params.relationship_dimensions = {"trust": 30, "respect": 9, "affection": 6, "fear": 0, "familiarity": 20}
	params.tiered_memories = {"pinned": [], "important": ["Something else entirely."], "relevant": ["And more."]}
	params.player_input = "What news?"
	var second: Dictionary = builder.build_context(params)
	_check("Next turn: both cached blocks are byte-identical", second.system_blocks[0].text == blocks[0].text and second.system_blocks[1].text == blocks[1].text)
	_check("...and only the per-turn block changed", second.system_blocks[2].text != blocks[2].text)
	var client = ClaudeClientScript.new()
	root.add_child(client)
	var system: Array = client._build_system(blocks + [{"text": "   ", "cache": false}])
	_check("The API gets text blocks, cache_control on the two stable ones", system.size() == 3 and system[0].has("cache_control") and system[1].has("cache_control") and not system[2].has("cache_control"))
	_check("cache_control is the 5-minute ephemeral kind", system[0].cache_control == {"type": "ephemeral"})
	_check("Empty blocks are dropped (the API rejects them)", system.all(func(b): return b.text.strip_edges() != ""))
	_check("A plain string prompt stays a string (uncached)", client._build_system("You are a test.") is String)
	client.free()
	builder.free()

## Telemetry: cost from usage, prompt size, and one JSON line per call
func _test_telemetry():
	print("\nTelemetry")
	var T = load("res://scripts/core/llm_telemetry.gd")
	var usage = {"input_tokens": 1000, "cache_creation_input_tokens": 2000, "cache_read_input_tokens": 3000, "output_tokens": 500,
		"cache_creation": {"ephemeral_5m_input_tokens": 2000, "ephemeral_1h_input_tokens": 0}}
	_check("Prompt tokens = uncached + writes + reads", T.prompt_tokens(usage) == 6000)
	# 1000 x $4 + 2000 x $4 x 1.25 + 3000 x $0.20 + 500 x $20, per million
	_check("Opus 5.5 cost: input, 5m writes at 1.25x, reads at $0.20, output", is_equal_approx(T.cost_usd("claude-opus-5-5", usage), (4000.0 + 10000.0 + 600.0 + 10000.0) / 1e6))
	_check("A model with no price is null, not guessed", T.cost_usd("claude-unknown-9", usage) == null)
	var saved_dir = T.dir
	T.dir = "user://test_telemetry"
	var path = T.log_path()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	T.record({"purpose": "test", "prompt_tokens": 6000})
	T.record({"purpose": "test", "prompt_tokens": 10})
	var lines = FileAccess.get_file_as_string(path).strip_edges().split("\n")
	var first = JSON.parse_string(lines[0]) if lines.size() > 0 else null
	_check("Each call is one JSON line, appended", lines.size() == 2 and first is Dictionary and first.purpose == "test")
	_check("...stamped with time, session and the game clock", first is Dictionary and first.has("ts") and first.session == T.session_id() and first.has("game_minute"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(T.dir))
	T.dir = saved_dir

