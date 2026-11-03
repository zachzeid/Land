extends Node
# Config - Loads and manages configuration (API keys, settings)
# Sources, highest priority first: OS environment variables, user://.env, res://.env
# res://.env is for development only: it is excluded from exports and never read by an exported build

const KNOWN_KEYS = [
	"CLAUDE_API_KEY", "ANTHROPIC_API_KEY", "CHROMA_URL", "PIXELLAB_API_KEY", "NPC_AGENCY_MODE",
	"STORY_ROUND_SECONDS", "CONVERSATION_AGENCY", "GAME_MINUTES_PER_REAL_MINUTE",
	"RECRAFT_API_KEY", "ELEVENLABS_API_KEY",
]
const USER_ENV_PATH = "user://.env"
const DEV_ENV_PATH = "res://.env"

var claude_api_key: String = ""
var anthropic_api_key: String = ""  # Alias for Claude API key
var chroma_url: String = "http://localhost:8000"
var pixellab_api_key: String = ""
var recraft_api_key: String = ""
var elevenlabs_api_key: String = ""
var npc_agency_mode: String = "offline"  # How storyline NPCs decide: offline (deterministic) | claude
var story_round_seconds: float = 300.0   # Idle fallback between story rounds (unpaused seconds)
var conversation_agency: bool = true     # NPCs may act on what is said in conversation (CONVERSATION_AGENCY=off)
var game_minutes_per_real_minute: float = 1.0  # Idle game clock speed (0 = only travel moves time)

## Where each setting came from: key -> "env" | "user://.env" | "res://.env"
var sources: Dictionary = {}

func _ready():
	print("Config initialized")
	load_config()

func load_config():
	var values: Dictionary = {}
	# Lowest priority first; later sources overwrite earlier ones
	if not OS.has_feature("template"):  # editor and development runs only
		_merge(values, _read_env_file(DEV_ENV_PATH), DEV_ENV_PATH)
	_merge(values, _read_env_file(USER_ENV_PATH), USER_ENV_PATH)
	var from_os: Dictionary = {}
	for key in KNOWN_KEYS:
		if OS.has_environment(key) and OS.get_environment(key) != "":
			from_os[key] = OS.get_environment(key)
	_merge(values, from_os, "env")

	for key in values:
		_apply(key, str(values[key]))
	if claude_api_key.is_empty():
		push_warning("Config: no Claude API key. Set CLAUDE_API_KEY in the environment or in %s" % ProjectSettings.globalize_path(USER_ENV_PATH))

func _merge(into: Dictionary, values: Dictionary, source: String) -> void:
	for key in values:
		into[key] = values[key]
		sources[key] = source

## KEY=value lines; # comments and blank lines skipped; surrounding quotes stripped
func _read_env_file(path: String) -> Dictionary:
	var values: Dictionary = {}
	if not FileAccess.file_exists(path):
		return values
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return values
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.begins_with("#") or line.is_empty():
			continue
		if line.begins_with("export "):
			line = line.substr(7).strip_edges()
		var parts = line.split("=", true, 1)
		if parts.size() != 2:
			continue
		var value = parts[1].strip_edges()
		if value.length() >= 2 and ((value.begins_with('"') and value.ends_with('"')) or (value.begins_with("'") and value.ends_with("'"))):
			value = value.substr(1, value.length() - 2)
		values[parts[0].strip_edges()] = value
	file.close()
	return values

func _apply(key: String, value: String) -> void:
	match key:
		"CLAUDE_API_KEY", "ANTHROPIC_API_KEY":
			if value.is_empty() or value == "your_claude_api_key_here":
				push_warning("Config: Claude API key is empty or placeholder (%s)" % sources.get(key, ""))
				return
			claude_api_key = value
			anthropic_api_key = value
			print("Config: Claude API key loaded from %s (%s...)" % [sources.get(key, ""), value.substr(0, 12)])
		"CHROMA_URL":
			chroma_url = value
			print("Config: ChromaDB URL = ", value)
		"NPC_AGENCY_MODE":
			var mode = value.to_lower()
			npc_agency_mode = mode if mode in ["offline", "claude"] else "offline"
			print("Config: NPC agency mode = ", npc_agency_mode)
		"STORY_ROUND_SECONDS":
			if value.is_valid_float() and float(value) > 0.0:
				story_round_seconds = float(value)
		"CONVERSATION_AGENCY":
			conversation_agency = value.to_lower() not in ["0", "off", "false", "no"]
		"GAME_MINUTES_PER_REAL_MINUTE":
			if value.is_valid_float() and float(value) >= 0.0:
				game_minutes_per_real_minute = float(value)
		"RECRAFT_API_KEY":
			recraft_api_key = value
		"ELEVENLABS_API_KEY":
			elevenlabs_api_key = value
		"PIXELLAB_API_KEY":
			pixellab_api_key = value
			if not value.is_empty():
				print("Config: PixelLab API key loaded (", value.substr(0, 12), "...)")

func get_claude_api_key() -> String:
	return claude_api_key

func get_chroma_url() -> String:
	return chroma_url
