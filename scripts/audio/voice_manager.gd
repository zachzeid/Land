extends Node
## VoiceManager - Singleton for NPC voice synthesis
## Uses WebSocket streaming for low-latency real-time voice playback

const ElevenLabsStreamingScript = preload("res://scripts/audio/elevenlabs_streaming_client.gd")
const ElevenLabsClientScript = preload("res://scripts/audio/elevenlabs_client.gd")

signal voice_started(npc_id: String)
signal voice_finished(npc_id: String)
signal voice_error(npc_id: String, error: String)

var streaming_client: Node
var audio_player: AudioStreamPlayer
var voice_enabled: bool = true
var voice_volume: float = 1.0
var use_streaming: bool = true  # Use WebSocket streaming for lower latency

## Audio cache: hash(text + voice_id) -> PackedByteArray
var audio_cache: Dictionary = {}
var cache_hits: int = 0
var cache_misses: int = 0

## Queue for sequential playback
var playback_queue: Array = []  # Array of {npc_id, audio_data}
var is_playing: bool = false

## Pending requests: request_id -> request_info
var pending_requests: Dictionary = {}

## Streaming state
var streaming_buffer: PackedByteArray = PackedByteArray()
var streaming_npc_id: String = ""
var playback_started: bool = false
var min_buffer_for_playback: int = 8000  # Start playing after ~8KB (enough MP3 frames)

func _ready():
	# Allow voice to work during pause (dialogue pauses the game)
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Create streaming client
	streaming_client = ElevenLabsStreamingScript.new()
	streaming_client.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(streaming_client)

	# Connect streaming signals
	streaming_client.audio_chunk_ready.connect(_on_audio_chunk_ready)
	streaming_client.audio_stream_started.connect(_on_stream_started)
	streaming_client.audio_stream_complete.connect(_on_stream_complete)
	streaming_client.audio_error.connect(_on_audio_error)

	# Create audio player
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = "Master"
	audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(audio_player)
	audio_player.finished.connect(_on_audio_finished)

	print("[VoiceManager] Initialized with WebSocket streaming")

	if not streaming_client.is_configured():
		push_warning("[VoiceManager] ElevenLabs API not configured - voice synthesis disabled")
		voice_enabled = false

## Speak dialogue for an NPC
## Extracts tone for voice modulation, then generates/plays audio
func speak(npc_id: String, dialogue_text: String):
	if not voice_enabled:
		return

	if dialogue_text.is_empty():
		return

	# Strip tone brackets for cache key and display (tone is extracted separately in streaming client)
	var clean_text = ElevenLabsStreamingScript.strip_tone_brackets(dialogue_text)

	if clean_text.is_empty():
		return

	# Check cache first (using clean text without tone markers)
	var voice_id = streaming_client.get_voice_id_for_npc(npc_id)
	# Include tone in cache key so different tones produce different audio
	var tone = streaming_client.extract_tone(dialogue_text)
	var cache_key = _get_cache_key(clean_text + tone, voice_id)

	if audio_cache.has(cache_key):
		cache_hits += 1
		print("[VoiceManager] Cache hit for %s (%d hits, %d misses)" % [npc_id, cache_hits, cache_misses])
		_queue_audio(npc_id, audio_cache[cache_key])
		return

	cache_misses += 1
	print("[VoiceManager] Streaming voice for %s: \"%s...\"" % [npc_id, clean_text.substr(0, 40)])

	# Reset streaming state
	streaming_buffer.clear()
	streaming_npc_id = npc_id
	playback_started = false

	# Store request info for caching later (include tone for cache key)
	pending_requests[npc_id] = {
		"npc_id": npc_id,
		"text": clean_text,
		"tone": tone,
		"voice_id": voice_id
	}

	# Start streaming with original text (includes tone for voice modulation)
	streaming_client.stream_speech_for_npc(npc_id, dialogue_text)

## Stop current playback and clear queue
func stop():
	audio_player.stop()
	playback_queue.clear()
	streaming_buffer.clear()
	streaming_npc_id = ""
	playback_started = false
	is_playing = false

## Set voice volume (0.0 to 1.0)
func set_volume(volume: float):
	voice_volume = clamp(volume, 0.0, 1.0)
	audio_player.volume_db = linear_to_db(voice_volume)

## Enable/disable voice synthesis
func set_voice_enabled(enabled: bool):
	voice_enabled = enabled
	if not enabled:
		stop()

## Check if voice is available
func is_available() -> bool:
	return voice_enabled and streaming_client.is_configured()

## Get cache statistics
func get_cache_stats() -> Dictionary:
	return {
		"entries": audio_cache.size(),
		"hits": cache_hits,
		"misses": cache_misses,
		"hit_rate": float(cache_hits) / max(cache_hits + cache_misses, 1)
	}

## Clear audio cache
func clear_cache():
	audio_cache.clear()
	cache_hits = 0
	cache_misses = 0
	print("[VoiceManager] Cache cleared")

# =============================================================================
# INTERNAL
# =============================================================================

func _get_cache_key(text: String, voice_id: String) -> int:
	return (text + voice_id).hash()

func _queue_audio(npc_id: String, audio_data: PackedByteArray):
	playback_queue.append({
		"npc_id": npc_id,
		"audio_data": audio_data
	})
	_process_queue()

func _process_queue():
	if is_playing or playback_queue.is_empty():
		return

	var item = playback_queue.pop_front()
	_play_audio(item.npc_id, item.audio_data)

func _play_audio(npc_id: String, audio_data: PackedByteArray):
	is_playing = true
	voice_started.emit(npc_id)

	var stream = AudioStreamMP3.new()
	stream.data = audio_data
	audio_player.stream = stream
	audio_player.volume_db = linear_to_db(voice_volume)
	audio_player.play()

	print("[VoiceManager] Playing audio for %s (%d bytes)" % [npc_id, audio_data.size()])

func _on_audio_finished():
	is_playing = false
	playback_started = false

	# Continue with queue
	_process_queue()

	if playback_queue.is_empty():
		voice_finished.emit(streaming_npc_id)

func _on_stream_started(request_id: String):
	print("[VoiceManager] Stream started: %s" % request_id)
	voice_started.emit(streaming_npc_id)

func _on_audio_chunk_ready(audio_data: PackedByteArray, request_id: String):
	# Add to buffer
	streaming_buffer.append_array(audio_data)

	# Start playback early once we have enough buffer
	if not playback_started and streaming_buffer.size() >= min_buffer_for_playback:
		print("[VoiceManager] Starting early playback with %d bytes buffered" % streaming_buffer.size())
		playback_started = true
		is_playing = true
		_play_streaming_audio()

func _play_streaming_audio():
	var stream = AudioStreamMP3.new()
	stream.data = streaming_buffer.duplicate()
	audio_player.stream = stream
	audio_player.volume_db = linear_to_db(voice_volume)
	audio_player.play()

func _on_stream_complete(request_id: String):
	print("[VoiceManager] Stream complete: %d total bytes" % streaming_buffer.size())

	# Cache the full audio
	if pending_requests.has(streaming_npc_id):
		var request_info = pending_requests[streaming_npc_id]
		pending_requests.erase(streaming_npc_id)
		# Include tone in cache key so different tones produce different cached audio
		var tone = request_info.get("tone", "")
		var cache_key = _get_cache_key(request_info.text + tone, request_info.voice_id)
		audio_cache[cache_key] = streaming_buffer.duplicate()
		print("[VoiceManager] Cached audio for %s (cache size: %d)" % [streaming_npc_id, audio_cache.size()])

	# If playback hasn't started yet (short audio), play the full buffer
	if not playback_started and streaming_buffer.size() > 0:
		print("[VoiceManager] Playing full buffer: %d bytes" % streaming_buffer.size())
		playback_started = true
		is_playing = true
		_play_streaming_audio()

func _on_audio_error(error: String, request_id: String):
	if not streaming_npc_id.is_empty():
		voice_error.emit(streaming_npc_id, error)
		push_error("[VoiceManager] Voice generation failed for %s: %s" % [streaming_npc_id, error])
		pending_requests.erase(streaming_npc_id)
	else:
		push_error("[VoiceManager] Voice generation failed: %s" % error)

	streaming_buffer.clear()
	streaming_npc_id = ""
	playback_started = false
