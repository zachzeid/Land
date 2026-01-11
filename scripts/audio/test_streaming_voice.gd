extends SceneTree
## Test script for WebSocket streaming voice synthesis
## Run with: godot --headless --script scripts/audio/test_streaming_voice.gd

const ElevenLabsStreamingScript = preload("res://scripts/audio/elevenlabs_streaming_client.gd")

var streaming_client: Node
var test_complete := false
var test_started := false
var total_bytes_received := 0
var chunks_received := 0

func _init():
	print("\n=== ElevenLabs WebSocket Streaming Test ===\n")

func _process(_delta):
	if test_started:
		return

	test_started = true
	run_test.call_deferred()

func run_test():
	# Create streaming client
	streaming_client = ElevenLabsStreamingScript.new()
	root.add_child(streaming_client)

	# Connect signals
	streaming_client.audio_chunk_ready.connect(_on_audio_chunk)
	streaming_client.audio_stream_started.connect(_on_stream_started)
	streaming_client.audio_stream_complete.connect(_on_stream_complete)
	streaming_client.audio_error.connect(_on_audio_error)

	# Wait for client to initialize
	await wait(1.0)

	# Check if API is configured
	if not streaming_client.is_configured():
		print("ERROR: ElevenLabs API key not configured!")
		print("Set ELEVENLABS_API_KEY in environment or .env file")
		quit(1)
		return

	print("API key loaded successfully")
	print("")

	# Test text cleanup
	var test_lines := [
		"[warmly] Hello there! Welcome to Thornhaven.",
		"*smiles* It's nice to meet you.",
		"**waves hand** Good morning!",
	]

	print("Testing text cleanup:")
	for line in test_lines:
		var clean = ElevenLabsStreamingScript.strip_tone_brackets(line)
		print("  Original: %s" % line)
		print("  Cleaned:  %s" % clean)
		print("")

	# Test tone extraction
	print("Testing tone extraction:")
	var tone_tests := [
		"[warmly] Hello there!",
		"[with a friendly smile] Good morning!",
		"[sarcastically] Oh, how wonderful.",
		"Just regular text.",
	]
	for test in tone_tests:
		var tone = streaming_client.extract_tone(test)
		print("  Text: \"%s\" -> Tone: \"%s\"" % [test, tone if not tone.is_empty() else "(none)"])
	print("")

	# Test streaming for Elena with tone
	var test_text = "[warmly] Hello there! Welcome to Thornhaven. It's so nice to meet someone new."

	print("Starting WebSocket stream for Elena (with tone)...")
	print("Text: \"%s\"" % test_text)
	print("")

	var start_time = Time.get_ticks_msec()
	var request_id = await streaming_client.stream_speech_for_npc("elena_daughter_001", test_text)

	if request_id.is_empty():
		print("ERROR: Failed to start streaming")
		quit(1)
		return

	print("Request started: %s" % request_id)
	print("Waiting for audio chunks...")

	# Wait for completion (with timeout)
	var timeout = 30.0
	var elapsed = 0.0
	while not test_complete and elapsed < timeout:
		await wait(0.5)
		elapsed += 0.5

	var total_time = Time.get_ticks_msec() - start_time

	if not test_complete:
		print("ERROR: Request timed out after %d seconds" % int(timeout))
		quit(1)
		return

	print("")
	print("=== RESULTS ===")
	print("Total chunks: %d" % chunks_received)
	print("Total bytes: %d" % total_bytes_received)
	print("Total time: %d ms" % total_time)
	print("")

	# Save complete audio
	var audio_buffer = streaming_client.get_audio_buffer()
	if audio_buffer.size() > 0:
		var output_path = "user://streaming_test_audio.mp3"
		var file = FileAccess.open(output_path, FileAccess.WRITE)
		if file:
			file.store_buffer(audio_buffer)
			file.close()
			print("Audio saved to: %s" % ProjectSettings.globalize_path(output_path))

	print("")
	print("WebSocket streaming test PASSED!")
	quit(0)

func wait(seconds: float):
	var timer = create_timer(seconds)
	await timer.timeout

func _on_stream_started(request_id: String):
	print("[Signal] Stream started: %s" % request_id)

func _on_audio_chunk(audio_data: PackedByteArray, request_id: String):
	chunks_received += 1
	total_bytes_received += audio_data.size()
	print("[Chunk %d] Received %d bytes (total: %d)" % [chunks_received, audio_data.size(), total_bytes_received])

func _on_stream_complete(request_id: String):
	print("[Signal] Stream complete: %s" % request_id)
	test_complete = true

func _on_audio_error(error: String, request_id: String):
	print("")
	print("=== ERROR ===")
	print("Request ID: %s" % request_id)
	print("Error: %s" % error)
	test_complete = true
