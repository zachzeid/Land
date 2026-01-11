extends Node
class_name PixelLabGenerator
## PixelLabGenerator - PixelLab.ai API integration for pixel art game assets
## https://api.pixellab.ai/v1/docs
##
## Endpoints:
##   /generate-image-pixflux  - Text-to-pixel-art (32x32 to 400x400) - scenes/backgrounds
##   /generate-image-bitforge - Style-consistent generation (up to 200x200) - with reference
##   /rotate                   - Rotate objects/characters between directions (16x16 to 200x200)
##   /animate-with-text        - Generate animations from text + reference (64x64 only!)
##
## Character Generation Workflow:
##   1. generate_character_sprite() - Create base 64x64 character with transparent bg
##   2. generate_rotation()         - Generate specific directional view from base
##   3. generate_animation_frames() - Generate walk/idle animation spritesheet

signal generation_started(request_id: String)
signal generation_completed(request_id: String, image_path: String)
signal generation_failed(request_id: String, error: String)
signal rotation_completed(request_id: String, image_path: String, direction: String)
signal animation_completed(request_id: String, image_path: String, action: String, frame_count: int)

const API_BASE_URL = "https://api.pixellab.ai/v1"
const REQUEST_TIMEOUT_MS = 180000  # 180 seconds (3 minutes - large images can be slow)

var api_key: String = ""
var pending_requests: Dictionary = {}  # request_id -> HTTPRequest node
var request_start_times: Dictionary = {}  # request_id -> start time in msec

## Generation modes
enum Mode {
	PIXFLUX,    # Text-to-pixel (scenes, up to 400x400)
	BITFORGE,   # Style-consistent (sprites with reference, up to 200x200)
	ROTATE,     # Directional views (up to 128x128)
	ANIMATE     # Add animations (up to 128x128)
}

## Default generation settings
var default_mode: Mode = Mode.PIXFLUX
var style_reference_path: String = ""  # Path to reference image for consistent style

func _ready():
	_load_api_key()

func _load_api_key():
	# Check environment variable
	var env_key = OS.get_environment("PIXELLAB_API_KEY")
	if env_key != "":
		api_key = env_key
		print("[PixelLab] API key loaded from environment")
		return

	# Check Config autoload
	if Config and "pixellab_api_key" in Config and Config.pixellab_api_key != "":
		api_key = Config.pixellab_api_key
		print("[PixelLab] API key loaded from Config")
		return

	# Check local .env file
	var env_path = "res://.env"
	if FileAccess.file_exists(env_path):
		var file = FileAccess.open(env_path, FileAccess.READ)
		while not file.eof_reached():
			var line = file.get_line().strip_edges()
			if line.begins_with("PIXELLAB_API_KEY="):
				api_key = line.substr(17)
				print("[PixelLab] API key loaded from .env")
				break
		file.close()

	if api_key == "":
		print("[PixelLab] WARNING: No API key configured")

func is_available() -> bool:
	return api_key != ""

func get_backend_name() -> String:
	return "PixelLab.ai"

## Main generation function - matches interface expected by AssetGeneratorManager
func generate(request) -> String:
	if not is_available():
		print("[PixelLab] ERROR: API key not configured")
		generation_failed.emit(request.id, "PixelLab API key not configured")
		return ""

	print("[PixelLab] ========== Starting generation ==========")
	print("[PixelLab] Request ID: %s" % request.id)
	generation_started.emit(request.id)

	# Track start time
	request_start_times[request.id] = Time.get_ticks_msec()

	# Determine best mode based on size
	var mode = _determine_mode(request.width, request.height)

	# Build request based on mode
	var endpoint: String
	var body: Dictionary

	match mode:
		Mode.PIXFLUX:
			endpoint = "/generate-image-pixflux"
			body = _build_pixflux_request(request)
		Mode.BITFORGE:
			endpoint = "/generate-image-bitforge"
			body = _build_bitforge_request(request)
		_:
			endpoint = "/generate-image-pixflux"
			body = _build_pixflux_request(request)

	# Create HTTP request
	var http = HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_MS / 1000.0
	add_child(http)
	pending_requests[request.id] = http

	http.request_completed.connect(
		func(result, code, hdrs, bdy):
			_on_request_completed(request.id, result, code, hdrs, bdy)
			http.queue_free()
			pending_requests.erase(request.id)
	)

	var headers = [
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	]

	var json_body = JSON.stringify(body)
	print("[PixelLab] Endpoint: %s" % endpoint)
	print("[PixelLab] Prompt: %s" % request.prompt.left(100) + ("..." if request.prompt.length() > 100 else ""))
	var img_size = body.get("image_size", {"width": 64, "height": 64})
	print("[PixelLab] Size: %dx%d, Mode: %s" % [img_size.width, img_size.height, Mode.keys()[mode]])
	print("[PixelLab] Timeout: %d seconds" % (REQUEST_TIMEOUT_MS / 1000))

	var error = http.request(
		API_BASE_URL + endpoint,
		headers,
		HTTPClient.METHOD_POST,
		json_body
	)

	if error != OK:
		print("[PixelLab] ERROR: HTTP request failed with error code: %d" % error)
		generation_failed.emit(request.id, "HTTP request failed: " + str(error))
		http.queue_free()
		pending_requests.erase(request.id)
		request_start_times.erase(request.id)
		return ""

	print("[PixelLab] Request sent, waiting for API response...")
	return request.id

## Determine best generation mode based on requested size
func _determine_mode(width: int, height: int) -> Mode:
	var max_dim = max(width, height)

	# Use bitforge for smaller sprites if we have a style reference
	if max_dim <= 200 and style_reference_path != "":
		return Mode.BITFORGE

	# Use pixflux for larger images or when no style reference
	return Mode.PIXFLUX

## Build pixflux request (text-to-pixel, up to 400x400)
## Note: Larger images take significantly longer to generate
func _build_pixflux_request(request) -> Dictionary:
	# Clamp size to pixflux limits (API max is 400x400)
	var width = clampi(request.width, 16, 400)
	var height = clampi(request.height, 16, 400)

	# Ensure area doesn't exceed 400x400 = 160000 (API limit)
	var area = width * height
	if area > 160000:
		var scale_factor = sqrt(160000.0 / area)
		width = int(width * scale_factor)
		height = int(height * scale_factor)

	# PixelLab API uses "description" not "prompt", and "image_size" object
	var body = {
		"description": request.prompt,
		"image_size": {
			"width": width,
			"height": height
		},
		"negative_description": request.negative_prompt if request.negative_prompt != "" else "blurry, modern, 3D render"
	}

	# Add seed if specified
	if request.seed >= 0:
		body["seed"] = request.seed

	return body

## Build bitforge request (style-consistent, up to 200x200)
func _build_bitforge_request(request) -> Dictionary:
	# Clamp size to bitforge limits
	var width = clampi(request.width, 16, 200)
	var height = clampi(request.height, 16, 200)

	# PixelLab API uses "description" not "prompt", and "image_size" object
	var body = {
		"description": request.prompt,
		"image_size": {
			"width": width,
			"height": height
		},
		"negative_description": request.negative_prompt if request.negative_prompt != "" else "blurry, modern, 3D render"
	}

	# Add style reference if available
	if style_reference_path != "" and FileAccess.file_exists(style_reference_path):
		var ref_image = _load_and_encode_image(style_reference_path)
		if ref_image != "":
			body["init_image"] = {
				"type": "base64",
				"base64": ref_image
			}

	# Add seed if specified
	if request.seed >= 0:
		body["seed"] = request.seed

	return body

## Load and base64 encode an image for API requests
func _load_and_encode_image(path: String) -> String:
	var abs_path = path
	if path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)
	elif path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)

	if not FileAccess.file_exists(abs_path):
		return ""

	var image = Image.new()
	var err = image.load(abs_path)
	if err != OK:
		return ""

	var png_data = image.save_png_to_buffer()
	return Marshalls.raw_to_base64(png_data)

func _on_request_completed(request_id: String, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var elapsed = 0.0
	if request_start_times.has(request_id):
		elapsed = (Time.get_ticks_msec() - request_start_times[request_id]) / 1000.0

	print("[PixelLab] API response received (%.1fs elapsed)" % elapsed)

	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg = _get_result_error_message(result)
		print("[PixelLab] ERROR: Request failed - %s" % error_msg)
		generation_failed.emit(request_id, "Request failed: " + error_msg)
		request_start_times.erase(request_id)
		return

	print("[PixelLab] Response code: %d" % response_code)

	if response_code != 200:
		var error_text = body.get_string_from_utf8()
		print("[PixelLab] ERROR: API returned error %d" % response_code)
		print("[PixelLab]   Response: %s" % error_text.left(500))
		generation_failed.emit(request_id, "API error %d: %s" % [response_code, error_text])
		request_start_times.erase(request_id)
		return

	# Parse response - PixelLab returns base64 image directly
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		print("[PixelLab] ERROR: Failed to parse JSON response")
		generation_failed.emit(request_id, "Failed to parse API response")
		request_start_times.erase(request_id)
		return

	var data = json.data

	# Debug: print response structure
	print("[PixelLab] Response keys: %s" % str(data.keys()))

	# PixelLab returns image as base64 in the response
	# The image might be directly a string or nested in an object
	var image_base64 = _extract_image_base64(data)

	if image_base64 == "":
		print("[PixelLab] ERROR: No image data in response")
		print("[PixelLab]   Full response: %s" % str(data).left(500))
		generation_failed.emit(request_id, "No image in response")
		request_start_times.erase(request_id)
		return

	# Decode and save image
	var image_data = Marshalls.base64_to_raw(image_base64)
	var image = Image.new()

	# Try loading as PNG first
	var err = image.load_png_from_buffer(image_data)
	if err != OK:
		# Try WebP
		err = image.load_webp_from_buffer(image_data)
	if err != OK:
		# Try JPG
		err = image.load_jpg_from_buffer(image_data)

	if err != OK:
		print("[PixelLab] ERROR: Failed to decode image data")
		generation_failed.emit(request_id, "Failed to decode image")
		request_start_times.erase(request_id)
		return

	print("[PixelLab] Image decoded: %dx%d" % [image.get_width(), image.get_height()])

	# Save as PNG
	var filename = "pixellab_%s.png" % request_id
	var path = _save_image_as_png(image, filename)

	if path == "":
		print("[PixelLab] ERROR: Failed to save image to disk")
		generation_failed.emit(request_id, "Failed to save image")
		request_start_times.erase(request_id)
		return

	var total_elapsed = (Time.get_ticks_msec() - request_start_times.get(request_id, Time.get_ticks_msec())) / 1000.0
	request_start_times.erase(request_id)

	print("[PixelLab] ========== Generation complete ==========")
	print("[PixelLab] Saved: %s" % path)
	print("[PixelLab] Total time: %.1f seconds" % total_elapsed)
	generation_completed.emit(request_id, path)

## Extract base64 image data from API response, handling various formats
## PixelLab returns: {"image": {"type": "base64", "base64": "data:image/png;base64,..."}}
func _extract_image_base64(data) -> String:
	var raw_base64 = ""

	# Try direct "image" field (might be string or object)
	if data.has("image"):
		var img = data.image
		if img is String:
			raw_base64 = img
		elif img is Dictionary:
			# PixelLab format: {"type": "base64", "base64": "data:image/png;base64,..."}
			if img.has("base64"):
				raw_base64 = img.base64
			elif img.has("data"):
				raw_base64 = img.data

	# Try "images" array
	if raw_base64 == "" and data.has("images"):
		var images = data.images
		if images is Array and images.size() > 0:
			var first = images[0]
			if first is String:
				raw_base64 = first
			elif first is Dictionary:
				if first.has("base64"):
					raw_base64 = first.base64
				elif first.has("data"):
					raw_base64 = first.data

	# Try "result" field
	if raw_base64 == "" and data.has("result"):
		var result = data.result
		if result is String:
			raw_base64 = result
		elif result is Dictionary:
			if result.has("base64"):
				raw_base64 = result.base64

	# Try "base64" directly
	if raw_base64 == "" and data.has("base64") and data.base64 is String:
		raw_base64 = data.base64

	# Strip data URI prefix if present (e.g., "data:image/png;base64,")
	if raw_base64.begins_with("data:"):
		var comma_pos = raw_base64.find(",")
		if comma_pos != -1:
			raw_base64 = raw_base64.substr(comma_pos + 1)
			print("[PixelLab] Stripped data URI prefix, base64 length: %d" % raw_base64.length())

	return raw_base64

func _save_image_as_png(image: Image, filename: String) -> String:
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("generated_assets"):
		dir.make_dir("generated_assets")

	var path = "user://generated_assets/" + filename
	var abs_path = ProjectSettings.globalize_path(path)

	var err = image.save_png(abs_path)
	if err != OK:
		return ""

	return path

## Convert HTTPRequest result codes to human-readable messages
func _get_result_error_message(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Cannot connect to server"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Cannot resolve hostname"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS/SSL handshake error"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "No response from server"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "Response body too large"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "Failed to decompress response"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "Request failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "Cannot open download file"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "Download file write error"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "Too many redirects"
		HTTPRequest.RESULT_TIMEOUT:
			return "Request timed out"
		_:
			return "Unknown error (code %d)" % result

## Set style reference image for consistent generation
func set_style_reference(image_path: String) -> bool:
	if FileAccess.file_exists(image_path):
		style_reference_path = image_path
		print("[PixelLab] Style reference set: %s" % image_path)
		return true
	return false

## Clear style reference
func clear_style_reference():
	style_reference_path = ""

#region Character Generation Functions

## Generate a 64x64 character sprite with transparent background
## This is optimized for the /animate-with-text endpoint which requires 64x64
func generate_character_sprite(request_id: String, description: String, seed: int = -1) -> String:
	if not is_available():
		generation_failed.emit(request_id, "PixelLab API key not configured")
		return ""

	print("[PixelLab] ========== Generating character sprite ==========")
	print("[PixelLab] Request ID: %s" % request_id)
	print("[PixelLab] Description: %s" % description.left(80))

	request_start_times[request_id] = Time.get_ticks_msec()
	generation_started.emit(request_id)

	# Build request - 64x64 with transparent background for animation compatibility
	var body = {
		"description": description + ", pixel art character, centered, facing forward, full body visible",
		"image_size": {
			"width": 64,
			"height": 64
		},
		"negative_description": "blurry, cropped, partial body, background, scenery, multiple characters",
		"transparent_background": true
	}

	if seed >= 0:
		body["seed"] = seed

	var http = HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_MS / 1000.0
	add_child(http)
	pending_requests[request_id] = http

	http.request_completed.connect(
		func(result, code, hdrs, bdy):
			_on_character_sprite_completed(request_id, result, code, hdrs, bdy)
			http.queue_free()
			pending_requests.erase(request_id)
	)

	var headers = [
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	]

	var error = http.request(
		API_BASE_URL + "/generate-image-pixflux",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)

	if error != OK:
		print("[PixelLab] ERROR: HTTP request failed with error code: %d" % error)
		generation_failed.emit(request_id, "HTTP request failed")
		http.queue_free()
		pending_requests.erase(request_id)
		request_start_times.erase(request_id)
		return ""

	print("[PixelLab] Request sent for character sprite...")
	return request_id

func _on_character_sprite_completed(request_id: String, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var elapsed = 0.0
	if request_start_times.has(request_id):
		elapsed = (Time.get_ticks_msec() - request_start_times[request_id]) / 1000.0

	if result != HTTPRequest.RESULT_SUCCESS:
		print("[PixelLab] ERROR: Character sprite request failed - %s" % _get_result_error_message(result))
		generation_failed.emit(request_id, _get_result_error_message(result))
		request_start_times.erase(request_id)
		return

	if response_code != 200:
		var error_text = body.get_string_from_utf8()
		print("[PixelLab] ERROR: Character sprite API error %d: %s" % [response_code, error_text.left(300)])
		generation_failed.emit(request_id, "API error %d" % response_code)
		request_start_times.erase(request_id)
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		generation_failed.emit(request_id, "Failed to parse response")
		request_start_times.erase(request_id)
		return

	var data = json.data
	var image_base64 = _extract_image_base64(data)

	if image_base64 == "":
		print("[PixelLab] ERROR: No character sprite image in response")
		generation_failed.emit(request_id, "No image in response")
		request_start_times.erase(request_id)
		return

	var image_data = Marshalls.base64_to_raw(image_base64)
	var image = Image.new()

	if image.load_png_from_buffer(image_data) != OK:
		generation_failed.emit(request_id, "Failed to decode image")
		request_start_times.erase(request_id)
		return

	# Save to character-specific directory
	var filename = "char_%s_base.png" % request_id
	var path = _save_character_image(image, request_id, filename)

	if path == "":
		generation_failed.emit(request_id, "Failed to save image")
		request_start_times.erase(request_id)
		return

	request_start_times.erase(request_id)
	print("[PixelLab] Character sprite complete (%.1fs): %s (%dx%d)" % [elapsed, path, image.get_width(), image.get_height()])
	generation_completed.emit(request_id, path)

## Generate a specific directional view of a character sprite
## direction: "north", "south", "east", "west" (or compass like "n", "s", "e", "w")
## Uses image-to-image generation with the base sprite as reference
func generate_rotation(request_id: String, base_image_path: String, target_direction: String) -> String:
	if not is_available():
		generation_failed.emit(request_id, "PixelLab API key not configured")
		return ""

	print("[PixelLab] ========== Generating directional view ==========")
	print("[PixelLab] Request ID: %s, Direction: %s" % [request_id, target_direction])

	var base_image = _load_and_encode_image(base_image_path)
	if base_image == "":
		generation_failed.emit(request_id, "Failed to load base image: " + base_image_path)
		return ""

	request_start_times[request_id] = Time.get_ticks_msec()
	generation_started.emit(request_id)

	# Map direction strings to descriptive prompts for generation
	var direction_prompts = {
		"south": "facing forward, front view, facing the camera",
		"north": "facing away, back view, seen from behind",
		"east": "facing right, right side profile view",
		"west": "facing left, left side profile view",
		"s": "facing forward, front view, facing the camera",
		"n": "facing away, back view, seen from behind",
		"e": "facing right, right side profile view",
		"w": "facing left, left side profile view"
	}

	var dir_prompt = direction_prompts.get(target_direction.to_lower(), "facing forward")

	# Use image-to-image generation to create directional view based on the base sprite
	var body = {
		"description": "pixel art character sprite, %s, full body visible, centered, same character same outfit same colors" % dir_prompt,
		"image_size": {"width": 64, "height": 64},
		"negative_description": "blurry, cropped, partial body, background, scenery, multiple characters, different character, different outfit",
		"transparent_background": true,
		"init_image": {
			"type": "base64",
			"base64": base_image
		},
		"init_image_strength": 35  # Balance between reference and new direction (0-100 scale)
	}

	var http = HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_MS / 1000.0
	add_child(http)
	pending_requests[request_id] = http

	http.request_completed.connect(
		func(result, code, hdrs, bdy):
			_on_rotation_api_completed(request_id, target_direction, result, code, hdrs, bdy)
			http.queue_free()
			pending_requests.erase(request_id)
	)

	var headers = [
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	]

	var error = http.request(
		API_BASE_URL + "/generate-image-pixflux",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)

	if error != OK:
		generation_failed.emit(request_id, "HTTP request failed")
		http.queue_free()
		pending_requests.erase(request_id)
		request_start_times.erase(request_id)
		return ""

	return request_id

func _on_rotation_api_completed(request_id: String, direction: String, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var elapsed = 0.0
	if request_start_times.has(request_id):
		elapsed = (Time.get_ticks_msec() - request_start_times[request_id]) / 1000.0
		request_start_times.erase(request_id)

	if result != HTTPRequest.RESULT_SUCCESS:
		print("[PixelLab] ERROR: Rotation request failed - %s" % _get_result_error_message(result))
		generation_failed.emit(request_id, _get_result_error_message(result))
		return

	if response_code != 200:
		var error_text = body.get_string_from_utf8()
		print("[PixelLab] ERROR: Rotation API error %d: %s" % [response_code, error_text.left(300)])
		generation_failed.emit(request_id, "API error %d" % response_code)
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		generation_failed.emit(request_id, "Failed to parse rotation response")
		return

	var data = json.data
	var image_base64 = _extract_image_base64(data)

	if image_base64 == "":
		print("[PixelLab] ERROR: No rotation image in response")
		print("[PixelLab]   Response keys: %s" % str(data.keys()))
		generation_failed.emit(request_id, "No rotation image in response")
		return

	var image_data = Marshalls.base64_to_raw(image_base64)
	var image = Image.new()

	if image.load_png_from_buffer(image_data) != OK:
		generation_failed.emit(request_id, "Failed to decode rotation image")
		return

	var filename = "char_%s_%s.png" % [request_id.split("_")[0], direction]
	var base_id = request_id.split("_")[0] if "_" in request_id else request_id
	var path = _save_character_image(image, base_id, filename)

	if path == "":
		generation_failed.emit(request_id, "Failed to save rotation image")
		return

	print("[PixelLab] Rotation complete (%.1fs): %s -> %s" % [elapsed, direction, path])
	rotation_completed.emit(request_id, path, direction)
	generation_completed.emit(request_id, path)

## Generate animation frames using /animate-with-text endpoint
## action: "walk", "run", "idle", "attack", etc.
## Returns a spritesheet with 4 frames horizontally arranged
func generate_animation_frames(request_id: String, base_image_path: String, action: String, description: String = "") -> String:
	if not is_available():
		generation_failed.emit(request_id, "PixelLab API key not configured")
		return ""

	print("[PixelLab] ========== Generating animation ==========")
	print("[PixelLab] Request ID: %s, Action: %s" % [request_id, action])

	var base_image = _load_and_encode_image(base_image_path)
	if base_image == "":
		generation_failed.emit(request_id, "Failed to load base image: " + base_image_path)
		return ""

	request_start_times[request_id] = Time.get_ticks_msec()
	generation_started.emit(request_id)

	# Build animation request per PixelLab API docs
	# Note: /animate-with-text requires 64x64 images
	var action_description = description if description != "" else "pixel art character %s animation" % action

	var body = {
		"description": action_description,
		"action": action,
		"image_size": {"width": 64, "height": 64},
		"reference_image": {
			"type": "base64",
			"base64": base_image
		},
		"n_frames": 4  # Default to 4 frames
	}

	var http = HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_MS / 1000.0
	add_child(http)
	pending_requests[request_id] = http

	http.request_completed.connect(
		func(result, code, hdrs, bdy):
			_on_animation_api_completed(request_id, action, result, code, hdrs, bdy)
			http.queue_free()
			pending_requests.erase(request_id)
	)

	var headers = [
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	]

	var error = http.request(
		API_BASE_URL + "/animate-with-text",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)

	if error != OK:
		generation_failed.emit(request_id, "HTTP request failed")
		http.queue_free()
		pending_requests.erase(request_id)
		request_start_times.erase(request_id)
		return ""

	return request_id

func _on_animation_api_completed(request_id: String, action: String, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var elapsed = 0.0
	if request_start_times.has(request_id):
		elapsed = (Time.get_ticks_msec() - request_start_times[request_id]) / 1000.0
		request_start_times.erase(request_id)

	if result != HTTPRequest.RESULT_SUCCESS:
		print("[PixelLab] ERROR: Animation request failed - %s" % _get_result_error_message(result))
		generation_failed.emit(request_id, _get_result_error_message(result))
		return

	if response_code != 200:
		var error_text = body.get_string_from_utf8()
		print("[PixelLab] ERROR: Animation API error %d: %s" % [response_code, error_text.left(300)])
		generation_failed.emit(request_id, "API error %d" % response_code)
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		generation_failed.emit(request_id, "Failed to parse animation response")
		return

	var data = json.data
	var image_base64 = _extract_image_base64(data)

	if image_base64 == "":
		print("[PixelLab] ERROR: No animation image in response")
		print("[PixelLab]   Response keys: %s" % str(data.keys()))
		generation_failed.emit(request_id, "No animation image in response")
		return

	var image_data = Marshalls.base64_to_raw(image_base64)
	var image = Image.new()

	if image.load_png_from_buffer(image_data) != OK:
		generation_failed.emit(request_id, "Failed to decode animation image")
		return

	# Animation returns a horizontal spritesheet with frames
	var frame_count = image.get_width() / 64 if image.get_width() >= 64 else 1
	print("[PixelLab] Animation spritesheet: %dx%d (%d frames)" % [image.get_width(), image.get_height(), frame_count])

	var filename = "char_%s_%s.png" % [request_id.split("_")[0], action]
	var base_id = request_id.split("_")[0] if "_" in request_id else request_id
	var path = _save_character_image(image, base_id, filename)

	if path == "":
		generation_failed.emit(request_id, "Failed to save animation image")
		return

	print("[PixelLab] Animation complete (%.1fs): %s -> %s" % [elapsed, action, path])
	animation_completed.emit(request_id, path, action, frame_count)
	generation_completed.emit(request_id, path)

## Save character image to character-specific directory
func _save_character_image(image: Image, character_id: String, filename: String) -> String:
	var dir = DirAccess.open("user://")

	# Create generated_characters directory if needed
	if not dir.dir_exists("generated_characters"):
		dir.make_dir("generated_characters")

	# Create character-specific subdirectory
	var char_dir = "generated_characters/" + character_id
	if not dir.dir_exists(char_dir):
		dir.make_dir(char_dir)

	var path = "user://" + char_dir + "/" + filename
	var abs_path = ProjectSettings.globalize_path(path)

	var err = image.save_png(abs_path)
	if err != OK:
		print("[PixelLab] ERROR: Failed to save image to: %s" % abs_path)
		return ""

	return path

#endregion

#region Legacy Functions (Deprecated)

## DEPRECATED: Use generate_rotation() instead
## Generate character with directional rotations (4 or 8 directions)
func generate_character_rotations(request_id: String, base_image_path: String, directions: int = 4) -> String:
	if not is_available():
		generation_failed.emit(request_id, "PixelLab API key not configured")
		return ""

	print("[PixelLab] ========== Generating rotations ==========")
	print("[PixelLab] Request ID: %s, Directions: %d" % [request_id, directions])

	var base_image = _load_and_encode_image(base_image_path)
	if base_image == "":
		generation_failed.emit(request_id, "Failed to load base image")
		return ""

	request_start_times[request_id] = Time.get_ticks_msec()
	generation_started.emit(request_id)

	var body = {
		"image": base_image,
		"directions": directions
	}

	var http = HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_MS / 1000.0
	add_child(http)
	pending_requests[request_id] = http

	http.request_completed.connect(
		func(result, code, hdrs, bdy):
			_on_rotation_completed(request_id, result, code, hdrs, bdy)
			http.queue_free()
			pending_requests.erase(request_id)
	)

	var headers = [
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	]

	var error = http.request(
		API_BASE_URL + "/rotate",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)

	if error != OK:
		generation_failed.emit(request_id, "HTTP request failed")
		http.queue_free()
		pending_requests.erase(request_id)
		return ""

	return request_id

func _on_rotation_completed(request_id: String, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var elapsed = 0.0
	if request_start_times.has(request_id):
		elapsed = (Time.get_ticks_msec() - request_start_times[request_id]) / 1000.0
		request_start_times.erase(request_id)

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var error_msg = "Rotation failed (HTTP %d)" % response_code if result == HTTPRequest.RESULT_SUCCESS else _get_result_error_message(result)
		generation_failed.emit(request_id, error_msg)
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		generation_failed.emit(request_id, "Failed to parse rotation response")
		return

	var data = json.data
	var image_base64 = _extract_image_base64(data)

	if image_base64 == "":
		print("[PixelLab] ERROR: No rotation image in response")
		print("[PixelLab]   Response keys: %s" % str(data.keys()))
		generation_failed.emit(request_id, "No rotation image in response")
		return

	var image_data = Marshalls.base64_to_raw(image_base64)
	var image = Image.new()

	if image.load_png_from_buffer(image_data) != OK:
		generation_failed.emit(request_id, "Failed to decode rotation image")
		return

	var filename = "pixellab_rotation_%s.png" % request_id
	var path = _save_image_as_png(image, filename)

	if path == "":
		generation_failed.emit(request_id, "Failed to save rotation image")
		return

	print("[PixelLab] Rotation complete (%.1fs): %s" % [elapsed, path])
	generation_completed.emit(request_id, path)

## Generate animation frames for a character sprite
func generate_animation(request_id: String, base_image_path: String, animation_type: String = "walk") -> String:
	if not is_available():
		generation_failed.emit(request_id, "PixelLab API key not configured")
		return ""

	print("[PixelLab] ========== Generating animation ==========")
	print("[PixelLab] Request ID: %s, Type: %s" % [request_id, animation_type])

	var base_image = _load_and_encode_image(base_image_path)
	if base_image == "":
		generation_failed.emit(request_id, "Failed to load base image")
		return ""

	request_start_times[request_id] = Time.get_ticks_msec()
	generation_started.emit(request_id)

	var body = {
		"image": base_image,
		"animation": animation_type  # walk, run, idle, etc.
	}

	var http = HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_MS / 1000.0
	add_child(http)
	pending_requests[request_id] = http

	http.request_completed.connect(
		func(result, code, hdrs, bdy):
			_on_animation_completed(request_id, result, code, hdrs, bdy)
			http.queue_free()
			pending_requests.erase(request_id)
	)

	var headers = [
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	]

	var error = http.request(
		API_BASE_URL + "/animate",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)

	if error != OK:
		generation_failed.emit(request_id, "HTTP request failed")
		http.queue_free()
		pending_requests.erase(request_id)
		return ""

	return request_id

func _on_animation_completed(request_id: String, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var elapsed = 0.0
	if request_start_times.has(request_id):
		elapsed = (Time.get_ticks_msec() - request_start_times[request_id]) / 1000.0
		request_start_times.erase(request_id)

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var error_msg = "Animation failed (HTTP %d)" % response_code if result == HTTPRequest.RESULT_SUCCESS else _get_result_error_message(result)
		generation_failed.emit(request_id, error_msg)
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		generation_failed.emit(request_id, "Failed to parse animation response")
		return

	var data = json.data
	var image_base64 = _extract_image_base64(data)

	if image_base64 == "":
		print("[PixelLab] ERROR: No animation image in response")
		print("[PixelLab]   Response keys: %s" % str(data.keys()))
		generation_failed.emit(request_id, "No animation image in response")
		return

	var image_data = Marshalls.base64_to_raw(image_base64)
	var image = Image.new()

	if image.load_png_from_buffer(image_data) != OK:
		generation_failed.emit(request_id, "Failed to decode animation image")
		return

	var filename = "pixellab_anim_%s.png" % request_id
	var path = _save_image_as_png(image, filename)

	if path == "":
		generation_failed.emit(request_id, "Failed to save animation image")
		return

	print("[PixelLab] Animation complete (%.1fs): %s" % [elapsed, path])
	generation_completed.emit(request_id, path)

#endregion
