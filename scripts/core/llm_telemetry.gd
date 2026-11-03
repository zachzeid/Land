extends RefCounted
## LlmTelemetry - one JSON line per model call, for tuning cost and latency later
## Written to user://telemetry/llm_<session>.jsonl (one file per game session). Each line holds what
## was sent (sizes, purpose, settings), what came back (the API's own token counts, cache use, stop
## reason, the model that served it), how long it took, the context window used and the cost
## Off with LLM_TELEMETRY=off (.env or environment) or --no-telemetry (after --)
## Summarise with: python3 tools/llm_telemetry_report.py
## Nothing here is estimated where the API reports it: token counts are the response's usage fields;
## the context window comes from GET /v1/models/{id}; a model without a price below is logged with
## cost_usd null rather than a guessed price

const DIR = "user://telemetry"
static var dir: String = DIR  # tests point this at their own folder

## USD per million tokens, from the Claude API model table (cached 2026-10-06) and its prompt
## caching economics: cache reads are 0.05x input on Claude Opus 5.5 (stated: $0.20) and 0.1x on
## the others; cache writes are 1.25x input for the 5-minute TTL and 2x for the 1-hour TTL.
## The fallback models are the ones "default" fallbacks may route Opus 5.5 to
const PRICES = {
	"claude-opus-5-5": {"input": 4.0, "output": 20.0, "cache_read": 0.20},
	"claude-opus-5": {"input": 5.0, "output": 25.0, "cache_read": 0.50},
	"claude-opus-4-8": {"input": 5.0, "output": 25.0, "cache_read": 0.50},
}
const WRITE_5M = 1.25
const WRITE_1H = 2.0

static var _session: String = ""
static var _context_windows: Dictionary = {}  # model -> {"max_input_tokens", "max_tokens"} from the Models API

static func enabled() -> bool:
	if "--no-telemetry" in OS.get_cmdline_user_args():
		return false
	var tree = Engine.get_main_loop() as SceneTree
	var config = tree.root.get_node_or_null("Config") if tree else null
	return config == null or not ("llm_telemetry" in config) or bool(config.llm_telemetry)

static func session_id() -> String:
	if _session == "":
		var t = Time.get_datetime_dict_from_system()
		_session = "%04d%02d%02d_%02d%02d%02d_%d" % [t.year, t.month, t.day, t.hour, t.minute, t.second, OS.get_process_id()]
	return _session

static func log_path() -> String:
	return "%s/llm_%s.jsonl" % [dir, session_id()]

## Append one call record. Adds ts, session and the game clock; never throws
static func record(entry: Dictionary) -> void:
	if not enabled():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path = log_path()
	var file = FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[LlmTelemetry] Cannot write %s" % path)
		return
	var line = {"ts": Time.get_unix_time_from_system(), "session": session_id()}
	var tree = Engine.get_main_loop() as SceneTree
	var world_state = tree.root.get_node_or_null("WorldState") if tree else null
	if world_state and world_state.has_method("get_game_minutes"):
		line["game_minute"] = world_state.get_game_minutes()
	line.merge(entry, true)
	file.seek_end()
	file.store_line(JSON.stringify(line))
	file.close()

## Cost of one call from its usage block; null when the model has no price here
static func cost_usd(model: String, usage: Dictionary):
	if not PRICES.has(model):
		return null
	var p: Dictionary = PRICES[model]
	var creation: Dictionary = usage.get("cache_creation", {}) if usage.get("cache_creation") is Dictionary else {}
	var write_5m = float(creation.get("ephemeral_5m_input_tokens", usage.get("cache_creation_input_tokens", 0)))
	var write_1h = float(creation.get("ephemeral_1h_input_tokens", 0))
	var dollars = float(usage.get("input_tokens", 0)) * p.input
	dollars += write_5m * p.input * WRITE_5M + write_1h * p.input * WRITE_1H
	dollars += float(usage.get("cache_read_input_tokens", 0)) * p.cache_read
	dollars += float(usage.get("output_tokens", 0)) * p.output
	return dollars / 1_000_000.0

## Prompt size the model saw: the uncached remainder plus cache writes plus cache reads
static func prompt_tokens(usage: Dictionary) -> int:
	return int(usage.get("input_tokens", 0)) + int(usage.get("cache_creation_input_tokens", 0)) + int(usage.get("cache_read_input_tokens", 0))

static func context_window(model: String) -> Dictionary:
	return _context_windows.get(model, {})

static func has_context_window(model: String) -> bool:
	return _context_windows.has(model)

static func set_context_window(model: String, info: Dictionary) -> void:
	_context_windows[model] = info

## client.send_message with telemetry labels, for clients that take them (test fakes take two
## arguments: messages and system prompt)
static func send(client: Object, messages: Array, system_prompt, meta: Dictionary) -> Variant:
	if client.has_method("get_method_argument_count") and client.get_method_argument_count("send_message") >= 3:
		return await client.send_message(messages, system_prompt, meta)
	return await client.send_message(messages, system_prompt)
