extends SceneTree
## Test script for Elena's voice synthesis via ElevenLabs
## Run with: godot --headless --script scripts/audio/test_elena_voice.gd

const ElevenLabsClientScript = preload("res://scripts/audio/elevenlabs_client.gd")

var elevenlabs_client: Node
var test_complete := false
var test_started := false

func _init():
	print("\n=== ElevenLabs Voice Test for Elena ===\n")

func _process(_delta):
	if test_started:
		return

	test_started = true
	run_test.call_deferred()

func run_test():
	# Create client
	elevenlabs_client = ElevenLabsClientScript.new()
	root.add_child(elevenlabs_client)

	# Connect signals
	elevenlabs_client.audio_ready.connect(_on_audio_ready)
	elevenlabs_client.audio_error.connect(_on_audio_error)
	elevenlabs_client.generation_started.connect(_on_generation_started)

	# Wait for client to initialize
	await create_timer(1.0).timeout

	# Check if API is configured
	if not elevenlabs_client.is_configured():
		print("ERROR: ElevenLabs API key not configured!")
		print("Set ELEVENLABS_API_KEY in environment or .env file")
		quit(1)
		return

	print("API key loaded successfully")
	print("")

	# Test Elena's voice with sample dialogue
	var test_lines := [
		"[warmly] Hello there! I'm Elena, Gregor's daughter. Welcome to our village.",
		"[curious] You're not from around here, are you? *tilts head* What brings you to Thornhaven?",
		"[softly] Sometimes I dream *sighs wistfully* of seeing what lies beyond these village walls.",
		"*smiles brightly* It's so nice to meet someone new!",
		"I hope you'll stay a while. **looks away** The village could use some excitement.",
	]

	# Test tone bracket and action marker stripping
	print("Testing text cleanup for TTS:")
	for line in test_lines:
		var clean = ElevenLabsClientScript.strip_tone_brackets(line)
		print("  Original: %s" % line)
		print("  Cleaned:  %s" % clean)
		print("")

	# Generate speech for the first line
	var test_line = test_lines[0]
	var clean_text = ElevenLabsClientScript.strip_tone_brackets(test_line)

	print("Generating speech for Elena...")
	print("Text: \"%s\"" % clean_text)
	print("")

	var request_id = await elevenlabs_client.generate_speech_for_npc("elena_daughter_001", clean_text)

	if request_id.is_empty():
		print("ERROR: Failed to start speech generation")
		quit(1)
		return

	print("Request started with ID: %s" % request_id)
	print("Waiting for response...")

	# Wait for completion (with timeout)
	var timeout = 30.0
	var elapsed = 0.0
	while not test_complete and elapsed < timeout:
		await create_timer(0.5).timeout
		elapsed += 0.5

	if not test_complete:
		print("ERROR: Request timed out after %d seconds" % int(timeout))
		quit(1)

	quit(0)

func _on_generation_started(request_id: String):
	print("[Signal] Generation started: %s" % request_id)

func _on_audio_ready(audio_data: PackedByteArray, request_id: String):
	print("")
	print("=== SUCCESS ===")
	print("Audio received for request: %s" % request_id)
	print("Audio size: %d bytes" % audio_data.size())

	# Save to file for verification
	var output_path = "user://elena_test_audio.mp3"
	var file = FileAccess.open(output_path, FileAccess.WRITE)
	if file:
		file.store_buffer(audio_data)
		file.close()
		print("Audio saved to: %s" % ProjectSettings.globalize_path(output_path))
	else:
		print("Warning: Could not save audio file")

	print("")
	print("Voice synthesis test PASSED!")
	test_complete = true

func _on_audio_error(error: String, request_id: String):
	print("")
	print("=== ERROR ===")
	print("Request ID: %s" % request_id)
	print("Error: %s" % error)
	test_complete = true
