extends Node
class_name ElevenLabsClient
## ElevenLabs Text-to-Speech API client
## Converts text to speech using ElevenLabs API

const BASE_URL = "https://api.elevenlabs.io/v1"

signal audio_ready(audio_data: PackedByteArray, request_id: String)
signal audio_error(error: String, request_id: String)
signal generation_started(request_id: String)

var api_key: String = ""
var http_request: HTTPRequest
var pending_requests: Dictionary = {}  # request_id -> metadata

## Voice IDs for different NPC types (pre-made ElevenLabs voices)
## These can be customized with actual voice IDs from ElevenLabs library
var voice_presets := {
	"young_female": "EXAVITQu4vr4xnSDxMaL",    # Sarah - soft, young female
	"middle_aged_male": "VR6AewLTigWG4xSOukaG", # Arnold - deep male
	"elderly_male": "ErXwobaYiN019PkySvjV",     # Antoni - mature male
	"adult_female": "21m00Tcm4TlvDq8ikWAM",    # Rachel - adult female
	"gruff_male": "yoZ06aMxZJJ28mfd3POQ",      # Sam - gruff male
	"menacing_male": "pNInz6obpgDQGcFmaJgB",   # Adam - deep, menacing
}

## NPC to voice mapping
var npc_voice_mapping := {
	"elena_daughter_001": "young_female",
	"gregor_001": "middle_aged_male",
	"mira_tavern_001": "adult_female",
	"bjorn_blacksmith_001": "gruff_male",
	"aldric_captain_001": "middle_aged_male",
	"mathias_elder_001": "elderly_male",
	"varn_bandit_001": "menacing_male",
}

## Voice settings per character type
var voice_settings := {
	"young_female": {"stability": 0.6, "similarity_boost": 0.75, "style": 0.1},
	"middle_aged_male": {"stability": 0.5, "similarity_boost": 0.8, "style": 0.0},
	"adult_female": {"stability": 0.5, "similarity_boost": 0.75, "style": 0.0},
	"elderly_male": {"stability": 0.6, "similarity_boost": 0.7, "style": 0.0},
	"gruff_male": {"stability": 0.7, "similarity_boost": 0.8, "style": 0.0},
	"menacing_male": {"stability": 0.5, "similarity_boost": 0.85, "style": 0.2},
}

func _ready():
	# Allow HTTP requests to work during pause (dialogue pauses the game)
	process_mode = Node.PROCESS_MODE_ALWAYS

	http_request = HTTPRequest.new()
	http_request.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

	# Load API key from environment
	_load_api_key()

func _load_api_key():
	# Try environment variable first
	api_key = OS.get_environment("ELEVENLABS_API_KEY")

	# If not set, try loading from .env file
	if api_key.is_empty():
		var env_path = "res://.env"
		if FileAccess.file_exists(env_path):
			var file = FileAccess.open(env_path, FileAccess.READ)
			if file:
				while not file.eof_reached():
					var line = file.get_line().strip_edges()
					if line.begins_with("ELEVENLABS_API_KEY"):
						var parts = line.split("=", true, 1)
						if parts.size() == 2:
							api_key = parts[1].trim_prefix("'").trim_suffix("'")
							api_key = api_key.trim_prefix('"').trim_suffix('"')
							break
				file.close()

	if api_key.is_empty():
		push_warning("[ElevenLabs] No API key found. Set ELEVENLABS_API_KEY environment variable or add to .env file.")
	else:
		print("[ElevenLabs] API key loaded successfully")

## Generate speech for an NPC
func generate_speech_for_npc(npc_id: String, text: String) -> String:
	var voice_type = npc_voice_mapping.get(npc_id, "middle_aged_male")
	var voice_id = voice_presets.get(voice_type, voice_presets["middle_aged_male"])
	var settings = voice_settings.get(voice_type, voice_settings["middle_aged_male"])

	return await generate_speech(text, voice_id, settings, npc_id)

## Generate speech with specific voice ID
func generate_speech(text: String, voice_id: String, settings: Dictionary = {}, request_id: String = "") -> String:
	if api_key.is_empty():
		push_error("[ElevenLabs] No API key configured")
		audio_error.emit("No API key configured", request_id)
		return ""

	if text.is_empty():
		push_error("[ElevenLabs] Empty text provided")
		audio_error.emit("Empty text provided", request_id)
		return ""

	# Generate unique request ID if not provided
	if request_id.is_empty():
		request_id = "req_%d" % Time.get_unix_time_from_system()

	var url = "%s/text-to-speech/%s" % [BASE_URL, voice_id]

	var headers = [
		"xi-api-key: %s" % api_key,
		"Content-Type: application/json",
		"Accept: audio/mpeg"
	]

	var body = {
		"text": text,
		"model_id": "eleven_multilingual_v2",
		"output_format": "mp3_22050_32",
		"voice_settings": {
			"stability": settings.get("stability", 0.5),
			"similarity_boost": settings.get("similarity_boost", 0.75),
			"style": settings.get("style", 0.0),
			"use_speaker_boost": true
		}
	}

	# Store request metadata
	pending_requests[request_id] = {
		"text": text,
		"voice_id": voice_id,
		"timestamp": Time.get_unix_time_from_system()
	}

	generation_started.emit(request_id)
	print("[ElevenLabs] Generating speech for: %s..." % text.substr(0, 50))

	var error = http_request.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)

	if error != OK:
		push_error("[ElevenLabs] Failed to send request: %s" % error)
		audio_error.emit("Failed to send request: %s" % error, request_id)
		pending_requests.erase(request_id)
		return ""

	return request_id

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	# Find the request ID (use the most recent one)
	var request_id = ""
	var oldest_time = INF
	for rid in pending_requests:
		var req = pending_requests[rid]
		if req["timestamp"] < oldest_time:
			oldest_time = req["timestamp"]
			request_id = rid

	if request_id.is_empty():
		push_warning("[ElevenLabs] Received response but no pending request found")
		return

	var request_data = pending_requests.get(request_id, {})
	pending_requests.erase(request_id)

	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg = "HTTP request failed with result: %d" % result
		push_error("[ElevenLabs] %s" % error_msg)
		audio_error.emit(error_msg, request_id)
		return

	if response_code == 200:
		print("[ElevenLabs] Audio generated successfully (%d bytes)" % body.size())
		audio_ready.emit(body, request_id)
	else:
		var error_text = body.get_string_from_utf8()
		var error_msg = "API error %d: %s" % [response_code, error_text]
		push_error("[ElevenLabs] %s" % error_msg)
		audio_error.emit(error_msg, request_id)

## Strip tone brackets and action markers from text before TTS
## "[warmly] Hello there" -> "Hello there"
## "Hello **waves hand** friend" -> "Hello friend"
## "Hello *smiles* friend" -> "Hello friend"
static func strip_tone_brackets(text: String) -> String:
	var result = text

	# Strip [tone] brackets (e.g., [warmly], [sarcastically])
	var bracket_regex = RegEx.new()
	bracket_regex.compile("\\[.*?\\]\\s*")
	result = bracket_regex.sub(result, "", true)

	# Strip **action** markers first (e.g., **waves hand**, **sighs**)
	var double_action_regex = RegEx.new()
	double_action_regex.compile("\\*\\*.*?\\*\\*\\s*")
	result = double_action_regex.sub(result, "", true)

	# Strip *action* markers (e.g., *smiles sadly*, *nods*)
	var single_action_regex = RegEx.new()
	single_action_regex.compile("\\*[^*]+\\*\\s*")
	result = single_action_regex.sub(result, "", true)

	return result.strip_edges()

## Get voice ID for an NPC
func get_voice_id_for_npc(npc_id: String) -> String:
	var voice_type = npc_voice_mapping.get(npc_id, "middle_aged_male")
	return voice_presets.get(voice_type, voice_presets["middle_aged_male"])

## Check if API is configured
func is_configured() -> bool:
	return not api_key.is_empty()
