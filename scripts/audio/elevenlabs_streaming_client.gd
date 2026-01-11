extends Node
class_name ElevenLabsStreamingClient
## ElevenLabs WebSocket Streaming TTS Client
## Provides real-time audio streaming with lower latency than HTTP

const WS_URL = "wss://api.elevenlabs.io/v1/text-to-speech/%s/stream-input?model_id=%s&output_format=%s"
const MODEL_ID = "eleven_multilingual_v2"
const OUTPUT_FORMAT = "mp3_44100_128"

signal audio_chunk_ready(audio_data: PackedByteArray, request_id: String)
signal audio_stream_started(request_id: String)
signal audio_stream_complete(request_id: String)
signal audio_error(error: String, request_id: String)

var api_key: String = ""
var socket: WebSocketPeer
var is_connected: bool = false
var current_request_id: String = ""
var current_voice_id: String = ""
var audio_buffer: PackedByteArray = PackedByteArray()

## Voice IDs for different NPC types
var voice_presets := {
	"young_female": "EXAVITQu4vr4xnSDxMaL",
	"middle_aged_male": "VR6AewLTigWG4xSOukaG",
	"elderly_male": "ErXwobaYiN019PkySvjV",
	"adult_female": "21m00Tcm4TlvDq8ikWAM",
	"gruff_male": "yoZ06aMxZJJ28mfd3POQ",
	"menacing_male": "pNInz6obpgDQGcFmaJgB",
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

## Tone modifiers - adjust voice settings based on emotional cues in []
## Format: tone_keyword -> {stability_delta, similarity_delta, style_delta}
var tone_modifiers := {
	# Warm/friendly tones
	"warmly": {"stability": 0.1, "similarity_boost": 0.0, "style": 0.15},
	"friendly": {"stability": 0.1, "similarity_boost": 0.0, "style": 0.1},
	"kindly": {"stability": 0.1, "similarity_boost": 0.0, "style": 0.1},
	"gently": {"stability": 0.15, "similarity_boost": 0.0, "style": 0.1},

	# Soft/quiet tones
	"softly": {"stability": 0.15, "similarity_boost": -0.1, "style": 0.0},
	"quietly": {"stability": 0.15, "similarity_boost": -0.1, "style": 0.0},
	"whispered": {"stability": 0.2, "similarity_boost": -0.15, "style": 0.0},
	"hushed": {"stability": 0.15, "similarity_boost": -0.1, "style": 0.0},

	# Happy/excited tones
	"cheerfully": {"stability": -0.1, "similarity_boost": 0.05, "style": 0.2},
	"excitedly": {"stability": -0.15, "similarity_boost": 0.05, "style": 0.25},
	"happily": {"stability": -0.05, "similarity_boost": 0.0, "style": 0.15},
	"enthusiastically": {"stability": -0.1, "similarity_boost": 0.05, "style": 0.2},

	# Sad/melancholy tones
	"sadly": {"stability": 0.1, "similarity_boost": 0.0, "style": 0.1},
	"wistfully": {"stability": 0.1, "similarity_boost": -0.05, "style": 0.1},
	"mournfully": {"stability": 0.15, "similarity_boost": 0.0, "style": 0.05},
	"solemnly": {"stability": 0.15, "similarity_boost": 0.05, "style": 0.0},

	# Angry/harsh tones
	"angrily": {"stability": -0.2, "similarity_boost": 0.1, "style": 0.25},
	"harshly": {"stability": -0.15, "similarity_boost": 0.1, "style": 0.2},
	"coldly": {"stability": 0.1, "similarity_boost": 0.1, "style": 0.0},
	"bitterly": {"stability": -0.1, "similarity_boost": 0.05, "style": 0.15},

	# Nervous/uncertain tones
	"nervously": {"stability": -0.2, "similarity_boost": -0.05, "style": 0.1},
	"hesitantly": {"stability": -0.15, "similarity_boost": -0.05, "style": 0.05},
	"uncertainly": {"stability": -0.15, "similarity_boost": -0.05, "style": 0.05},
	"anxiously": {"stability": -0.2, "similarity_boost": 0.0, "style": 0.1},

	# Curious/thoughtful tones
	"curiously": {"stability": 0.0, "similarity_boost": 0.0, "style": 0.1},
	"thoughtfully": {"stability": 0.1, "similarity_boost": 0.0, "style": 0.05},
	"puzzled": {"stability": -0.05, "similarity_boost": 0.0, "style": 0.1},

	# Serious/stern tones
	"sternly": {"stability": 0.1, "similarity_boost": 0.1, "style": 0.0},
	"seriously": {"stability": 0.1, "similarity_boost": 0.05, "style": 0.0},
	"gravely": {"stability": 0.15, "similarity_boost": 0.1, "style": 0.0},
	"firmly": {"stability": 0.1, "similarity_boost": 0.1, "style": 0.0},

	# Sarcastic/playful tones
	"sarcastically": {"stability": -0.1, "similarity_boost": 0.0, "style": 0.3},
	"playfully": {"stability": -0.1, "similarity_boost": 0.0, "style": 0.2},
	"teasingly": {"stability": -0.1, "similarity_boost": 0.0, "style": 0.2},
	"mockingly": {"stability": -0.15, "similarity_boost": 0.05, "style": 0.25},

	# Surprised tones
	"surprised": {"stability": -0.15, "similarity_boost": 0.0, "style": 0.15},
	"shocked": {"stability": -0.2, "similarity_boost": 0.05, "style": 0.2},
	"astonished": {"stability": -0.2, "similarity_boost": 0.05, "style": 0.2},

	# Descriptive phrase tones (e.g., "with a friendly smile")
	"friendly smile": {"stability": 0.1, "similarity_boost": 0.0, "style": 0.15},
	"warm smile": {"stability": 0.1, "similarity_boost": 0.0, "style": 0.15},
	"sad smile": {"stability": 0.1, "similarity_boost": -0.05, "style": 0.1},
	"knowing look": {"stability": 0.05, "similarity_boost": 0.05, "style": 0.1},
	"concerned": {"stability": 0.05, "similarity_boost": 0.0, "style": 0.05},
	"relieved": {"stability": 0.1, "similarity_boost": 0.0, "style": 0.1},
}

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_api_key()

func _load_api_key():
	api_key = OS.get_environment("ELEVENLABS_API_KEY")

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
		push_warning("[ElevenLabs-WS] No API key found")
	else:
		print("[ElevenLabs-WS] API key loaded successfully")

func _process(_delta):
	if socket == null:
		return

	socket.poll()

	var state = socket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			while socket.get_available_packet_count() > 0:
				var packet = socket.get_packet()
				_handle_message(packet.get_string_from_utf8())

		WebSocketPeer.STATE_CLOSING:
			pass

		WebSocketPeer.STATE_CLOSED:
			var code = socket.get_close_code()
			var reason = socket.get_close_reason()
			if code != 1000:  # Normal closure
				print("[ElevenLabs-WS] Connection closed: %d - %s" % [code, reason])
			_cleanup_connection()

## Start streaming speech for an NPC
func stream_speech_for_npc(npc_id: String, text: String) -> String:
	var voice_type = npc_voice_mapping.get(npc_id, "middle_aged_male")
	var voice_id = voice_presets.get(voice_type, voice_presets["middle_aged_male"])
	var base_settings = voice_settings.get(voice_type, voice_settings["middle_aged_male"]).duplicate()

	# Extract tone from text and apply modifiers
	var tone = extract_tone(text)
	if not tone.is_empty():
		base_settings = apply_tone_modifiers(base_settings, tone)
		print("[ElevenLabs-WS] Applying tone: [%s]" % tone)

	return await stream_speech(text, voice_id, base_settings, npc_id)

## Extract tone indicator from text (e.g., "[warmly]" or "[with a friendly smile]")
func extract_tone(text: String) -> String:
	var regex = RegEx.new()
	regex.compile("^\\s*\\[([^\\]]+)\\]")
	var result = regex.search(text)
	if result:
		return result.get_string(1).to_lower().strip_edges()
	return ""

## Apply tone modifiers to base voice settings
func apply_tone_modifiers(base_settings: Dictionary, tone: String) -> Dictionary:
	var modified = base_settings.duplicate()

	# Try exact match first
	if tone_modifiers.has(tone):
		var mods = tone_modifiers[tone]
		modified["stability"] = clampf(modified["stability"] + mods["stability"], 0.0, 1.0)
		modified["similarity_boost"] = clampf(modified["similarity_boost"] + mods["similarity_boost"], 0.0, 1.0)
		modified["style"] = clampf(modified["style"] + mods["style"], 0.0, 1.0)
		return modified

	# Try partial match (for phrases like "with a friendly smile")
	for keyword in tone_modifiers:
		if tone.contains(keyword):
			var mods = tone_modifiers[keyword]
			modified["stability"] = clampf(modified["stability"] + mods["stability"], 0.0, 1.0)
			modified["similarity_boost"] = clampf(modified["similarity_boost"] + mods["similarity_boost"], 0.0, 1.0)
			modified["style"] = clampf(modified["style"] + mods["style"], 0.0, 1.0)
			return modified

	# No matching tone found, return base settings
	return modified

## Start streaming speech with specific voice
func stream_speech(text: String, voice_id: String, settings: Dictionary = {}, request_id: String = "") -> String:
	if api_key.is_empty():
		push_error("[ElevenLabs-WS] No API key configured")
		audio_error.emit("No API key configured", request_id)
		return ""

	if text.is_empty():
		push_error("[ElevenLabs-WS] Empty text provided")
		audio_error.emit("Empty text provided", request_id)
		return ""

	# Generate request ID if not provided
	if request_id.is_empty():
		request_id = "ws_req_%d" % Time.get_unix_time_from_system()

	# Close any existing connection
	if socket != null and is_connected:
		_close_connection()
		await get_tree().create_timer(0.1).timeout

	current_request_id = request_id
	current_voice_id = voice_id
	audio_buffer.clear()

	# Create WebSocket connection
	var url = WS_URL % [voice_id, MODEL_ID, OUTPUT_FORMAT]
	socket = WebSocketPeer.new()
	# Increase buffer sizes to handle large audio chunks (default is too small)
	socket.inbound_buffer_size = 1024 * 1024  # 1MB for incoming audio
	socket.outbound_buffer_size = 64 * 1024   # 64KB for outgoing text
	socket.handshake_headers = PackedStringArray(["xi-api-key: %s" % api_key])

	var error = socket.connect_to_url(url)
	if error != OK:
		push_error("[ElevenLabs-WS] Failed to connect: %s" % error)
		audio_error.emit("Failed to connect: %s" % error, request_id)
		return ""

	print("[ElevenLabs-WS] Connecting for: %s..." % text.substr(0, 40))

	# Wait for connection
	var timeout = 5.0
	var elapsed = 0.0
	while socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING and elapsed < timeout:
		socket.poll()
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05

	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_error("[ElevenLabs-WS] Connection timeout")
		audio_error.emit("Connection timeout", request_id)
		return ""

	is_connected = true
	audio_stream_started.emit(request_id)
	print("[ElevenLabs-WS] Connected, sending text...")

	# Strip tone brackets and action markers before sending to ElevenLabs
	var clean_text = strip_tone_brackets(text)

	# Send BOS (Beginning of Stream) message
	var bos_message = {
		"text": " ",
		"voice_settings": {
			"stability": settings.get("stability", 0.5),
			"similarity_boost": settings.get("similarity_boost", 0.75),
			"style": settings.get("style", 0.0)
		},
		"generation_config": {
			"chunk_length_schedule": [50, 120, 200, 300]
		}
	}
	_send_json(bos_message)

	# Send the actual text with flush to trigger generation
	var text_message = {
		"text": clean_text + " ",
		"flush": true
	}
	_send_json(text_message)

	# Send EOS (End of Stream) to signal we're done sending
	var eos_message = {
		"text": ""
	}
	_send_json(eos_message)

	return request_id

func _send_json(data: Dictionary):
	if socket and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var json_str = JSON.stringify(data)
		socket.send_text(json_str)

func _handle_message(message: String):
	var json = JSON.new()
	var error = json.parse(message)

	if error != OK:
		push_warning("[ElevenLabs-WS] Failed to parse message: %s" % message.substr(0, 100))
		return

	var data = json.data

	# Check for error
	if data.has("error"):
		push_error("[ElevenLabs-WS] Server error: %s" % data.error)
		audio_error.emit(str(data.error), current_request_id)
		_close_connection()
		return

	# Handle audio chunk
	if data.has("audio") and data.audio != null and not data.audio.is_empty():
		var audio_bytes = Marshalls.base64_to_raw(data.audio)
		if audio_bytes.size() > 0:
			audio_buffer.append_array(audio_bytes)
			audio_chunk_ready.emit(audio_bytes, current_request_id)
			print("[ElevenLabs-WS] Received chunk: %d bytes (total: %d)" % [audio_bytes.size(), audio_buffer.size()])

	# Check if final
	if data.has("isFinal") and data.isFinal:
		print("[ElevenLabs-WS] Stream complete: %d total bytes" % audio_buffer.size())
		audio_stream_complete.emit(current_request_id)
		_close_connection()

func _close_connection():
	if socket and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.close(1000, "Done")

func _cleanup_connection():
	is_connected = false
	socket = null

## Get voice ID for an NPC
func get_voice_id_for_npc(npc_id: String) -> String:
	var voice_type = npc_voice_mapping.get(npc_id, "middle_aged_male")
	return voice_presets.get(voice_type, voice_presets["middle_aged_male"])

## Check if API is configured
func is_configured() -> bool:
	return not api_key.is_empty()

## Strip tone brackets and action markers from text before TTS
static func strip_tone_brackets(text: String) -> String:
	var result = text

	var bracket_regex = RegEx.new()
	bracket_regex.compile("\\[.*?\\]\\s*")
	result = bracket_regex.sub(result, "", true)

	var double_action_regex = RegEx.new()
	double_action_regex.compile("\\*\\*.*?\\*\\*\\s*")
	result = double_action_regex.sub(result, "", true)

	var single_action_regex = RegEx.new()
	single_action_regex.compile("\\*[^*]+\\*\\s*")
	result = single_action_regex.sub(result, "", true)

	return result.strip_edges()

## Get the full audio buffer (for caching after stream completes)
func get_audio_buffer() -> PackedByteArray:
	return audio_buffer.duplicate()
