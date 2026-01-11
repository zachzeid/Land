extends Node
class_name RecraftGenerator
## RecraftGenerator - Recraft.ai API integration for consistent game asset generation
## https://www.recraft.ai/docs

signal generation_started(request_id: String)
signal generation_completed(request_id: String, image_path: String)
signal generation_failed(request_id: String, error: String)

const API_BASE_URL = "https://external.api.recraft.ai/v1"
const REQUEST_TIMEOUT_MS = 60000  # 60 second timeout for API requests
const DOWNLOAD_TIMEOUT_MS = 30000  # 30 second timeout for image downloads

var api_key: String = ""
var pending_requests: Dictionary = {}  # request_id -> HTTPRequest node
var request_start_times: Dictionary = {}  # request_id -> start time in msec

## Style presets mapped to Recraft style IDs
## Base styles: realistic_image, digital_illustration, vector_illustration, icon
const STYLE_MAP = {
	"pixel_art": "digital_illustration",
	"painterly": "digital_illustration",
	"realistic": "realistic_image",
	"fantasy": "digital_illustration",
	"isometric": "digital_illustration",
	"icon": "icon",
}

## Default style for Thornhaven assets
var default_style: String = "isometric"

func _ready():
	_load_api_key()

func _load_api_key():
	# Check environment variable first
	var env_key = OS.get_environment("RECRAFT_API_KEY")
	if env_key != "":
		api_key = env_key
		return

	# Check Config autoload
	if Config and Config.recraft_api_key != "":
		api_key = Config.recraft_api_key
		return

	# Check local .env file as fallback
	var env_path = "res://.env"
	if FileAccess.file_exists(env_path):
		var file = FileAccess.open(env_path, FileAccess.READ)
		while not file.eof_reached():
			var line = file.get_line().strip_edges()
			if line.begins_with("RECRAFT_API_KEY="):
				api_key = line.substr(16)
				break
		file.close()

func is_available() -> bool:
	return api_key != ""

func get_backend_name() -> String:
	return "Recraft.ai"

## Main generation function
func generate(request) -> String:
	if not is_available():
		print("[Recraft] ERROR: API key not configured")
		generation_failed.emit(request.id, "Recraft API key not configured")
		return ""

	print("[Recraft] ========== Starting generation ==========")
	print("[Recraft] Request ID: %s" % request.id)
	generation_started.emit(request.id)

	# Track start time
	request_start_times[request.id] = Time.get_ticks_msec()

	# Build the request body
	# Recraft uses preset sizes, not arbitrary dimensions
	var size_preset = _get_size_preset(request.width, request.height)
	var body = {
		"prompt": _enhance_prompt(request.prompt, request.style_preset),
		"style": _get_style_id(request.style_preset),
		"size": size_preset,
	}

	# Add negative prompt if provided
	if request.negative_prompt != "":
		body["negative_prompt"] = request.negative_prompt

	# Add seed for reproducibility
	if request.seed >= 0:
		body["seed"] = request.seed

	# Create a new HTTPRequest for this generation (allows parallel requests)
	var http = HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_MS / 1000.0  # Convert to seconds
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
	print("[Recraft] Sending API request...")
	print("[Recraft]   Prompt: %s" % body.prompt.left(100) + ("..." if body.prompt.length() > 100 else ""))
	print("[Recraft]   Style: %s, Size: %s" % [body.style, body.size])
	print("[Recraft]   Timeout: %d seconds" % (REQUEST_TIMEOUT_MS / 1000))

	var error = http.request(
		API_BASE_URL + "/images/generations",
		headers,
		HTTPClient.METHOD_POST,
		json_body
	)

	if error != OK:
		print("[Recraft] ERROR: HTTP request failed with error code: %d" % error)
		generation_failed.emit(request.id, "HTTP request failed: " + str(error))
		http.queue_free()
		pending_requests.erase(request.id)
		request_start_times.erase(request.id)
		return ""

	print("[Recraft] Request sent, waiting for API response...")
	return request.id

func _on_request_completed(request_id: String, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var elapsed = 0
	if request_start_times.has(request_id):
		elapsed = (Time.get_ticks_msec() - request_start_times[request_id]) / 1000.0

	print("[Recraft] API response received (%.1fs elapsed)" % elapsed)

	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg = _get_result_error_message(result)
		print("[Recraft] ERROR: Request failed - %s" % error_msg)
		generation_failed.emit(request_id, "Request failed: " + error_msg)
		request_start_times.erase(request_id)
		return

	print("[Recraft] Response code: %d" % response_code)

	if response_code != 200:
		var error_text = body.get_string_from_utf8()
		print("[Recraft] ERROR: API returned error %d" % response_code)
		print("[Recraft]   Response: %s" % error_text.left(500))
		generation_failed.emit(request_id, "API error %d: %s" % [response_code, error_text])
		request_start_times.erase(request_id)
		return

	# Parse response
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		print("[Recraft] ERROR: Failed to parse JSON response")
		generation_failed.emit(request_id, "Failed to parse API response")
		request_start_times.erase(request_id)
		return

	var data = json.data
	if not data.has("data") or data.data.size() == 0:
		print("[Recraft] ERROR: No image data in response")
		generation_failed.emit(request_id, "No image in response")
		request_start_times.erase(request_id)
		return

	# Download the generated image
	var image_url = data.data[0].url
	print("[Recraft] Image generated successfully, downloading from URL...")
	_download_image(request_id, image_url)

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

func _download_image(request_id: String, url: String):
	print("[Recraft] Starting image download...")

	# Create a separate HTTPRequest for downloading
	var download_request = HTTPRequest.new()
	download_request.timeout = DOWNLOAD_TIMEOUT_MS / 1000.0
	add_child(download_request)

	download_request.request_completed.connect(
		func(result, code, headers, body):
			_on_image_downloaded(result, code, headers, body, request_id)
			download_request.queue_free()
	)

	var error = download_request.request(url)
	if error != OK:
		print("[Recraft] ERROR: Failed to start download (error %d)" % error)
		generation_failed.emit(request_id, "Failed to start image download")
		download_request.queue_free()

func _on_image_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, request_id: String):
	var total_elapsed = 0
	if request_start_times.has(request_id):
		total_elapsed = (Time.get_ticks_msec() - request_start_times[request_id]) / 1000.0
		request_start_times.erase(request_id)

	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg = _get_result_error_message(result)
		print("[Recraft] ERROR: Download failed - %s" % error_msg)
		generation_failed.emit(request_id, "Failed to download image: " + error_msg)
		return

	if response_code != 200:
		print("[Recraft] ERROR: Download returned HTTP %d" % response_code)
		generation_failed.emit(request_id, "Failed to download generated image (HTTP %d)" % response_code)
		return

	print("[Recraft] Download complete (%d bytes)" % body.size())

	# Load image from raw data - try WebP first (Recraft's default format)
	var image = Image.new()
	var err = image.load_webp_from_buffer(body)
	if err != OK:
		print("[Recraft] Not WebP, trying PNG...")
		err = image.load_png_from_buffer(body)
	if err != OK:
		print("[Recraft] Not PNG, trying JPG...")
		err = image.load_jpg_from_buffer(body)
	if err != OK:
		print("[Recraft] ERROR: Failed to decode image (tried WebP, PNG, JPG)")
		generation_failed.emit(request_id, "Failed to decode image (tried WebP, PNG, JPG)")
		return

	print("[Recraft] Image decoded: %dx%d" % [image.get_width(), image.get_height()])

	# Save as PNG for consistency
	var filename = "recraft_%s.png" % request_id
	var path = _save_image_as_png(image, filename)

	if path == "":
		print("[Recraft] ERROR: Failed to save image to disk")
		generation_failed.emit(request_id, "Failed to save image")
		return

	print("[Recraft] ========== Generation complete ==========")
	print("[Recraft] Saved: %s" % path)
	print("[Recraft] Total time: %.1f seconds" % total_elapsed)
	generation_completed.emit(request_id, path)

func _save_image_as_png(image: Image, filename: String) -> String:
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("generated_assets"):
		dir.make_dir("generated_assets")

	var path = "user://generated_assets/" + filename
	var err = image.save_png(ProjectSettings.globalize_path(path))
	if err == OK:
		return path
	return ""

## Enhance prompt with style-specific modifiers
func _enhance_prompt(base_prompt: String, style: String) -> String:
	var enhanced = base_prompt

	match style:
		"pixel_art":
			enhanced = "pixel art, retro game style, " + base_prompt
		"isometric":
			enhanced = "isometric 2D view, 3/4 top-down angle, game asset, clear edges, " + base_prompt + ", on transparent background, shadow to bottom-right"
		"fantasy":
			enhanced = "fantasy illustration, medieval, " + base_prompt
		"icon":
			enhanced = "game icon, simple, clear, " + base_prompt

	return enhanced

func _get_style_id(style_preset: String) -> String:
	if style_preset == "" or not STYLE_MAP.has(style_preset):
		return STYLE_MAP[default_style]
	return STYLE_MAP[style_preset]

## Convert requested dimensions to Recraft size preset
func _get_size_preset(width: int, height: int) -> String:
	# Recraft supports specific size presets
	# https://www.recraft.ai/docs
	var ratio = float(width) / float(height)

	# Square
	if abs(ratio - 1.0) < 0.1:
		return "1024x1024"

	# Landscape ratios
	if ratio > 1.0:
		if ratio >= 1.7:  # ~16:9
			return "1820x1024"
		elif ratio >= 1.3:  # ~4:3
			return "1365x1024"
		else:
			return "1024x1024"

	# Portrait ratios
	if ratio >= 0.75:  # ~3:4
		return "1024x1365"
	else:  # ~9:16
		return "1024x1820"

