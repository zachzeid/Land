extends Node
class_name LocalSDGenerator
## LocalSDGenerator - Local Stable Diffusion / FLUX generation via CLI or API
## Supports: ComfyUI, Automatic1111, or direct diffusers CLI

signal generation_started(request_id: String)
signal generation_completed(request_id: String, image_path: String)
signal generation_failed(request_id: String, error: String)

enum LocalBackend {
	COMFYUI,       # ComfyUI with API
	AUTO1111,      # Automatic1111 WebUI API
	DIFFUSERS_CLI, # Direct Python diffusers call
	FLUX_CLI       # FLUX model via CLI
}

@export var backend: LocalBackend = LocalBackend.DIFFUSERS_CLI
@export var api_url: String = "http://127.0.0.1:7860"  # For ComfyUI/Auto1111
@export var python_cmd: String = "python3"
@export var model_path: String = ""  # Path to local model weights

const CLI_SCRIPT_PATH = "res://scripts/generation/sd_cli.py"

var http_request: HTTPRequest
var pending_requests: Dictionary = {}  # request_id -> GenerationRequest

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func is_available() -> bool:
	match backend:
		LocalBackend.COMFYUI, LocalBackend.AUTO1111:
			return _check_api_available()
		LocalBackend.DIFFUSERS_CLI, LocalBackend.FLUX_CLI:
			return _check_cli_available()
	return false

func get_backend_name() -> String:
	match backend:
		LocalBackend.COMFYUI:
			return "ComfyUI (Local)"
		LocalBackend.AUTO1111:
			return "Automatic1111 (Local)"
		LocalBackend.DIFFUSERS_CLI:
			return "Diffusers CLI (Local)"
		LocalBackend.FLUX_CLI:
			return "FLUX CLI (Local)"
	return "Local SD"

func generate(request) -> String:
	if not is_available():
		generation_failed.emit(request.id, "Local backend not available")
		return ""

	generation_started.emit(request.id)
	pending_requests[request.id] = request

	match backend:
		LocalBackend.COMFYUI:
			_generate_comfyui(request)
		LocalBackend.AUTO1111:
			_generate_auto1111(request)
		LocalBackend.DIFFUSERS_CLI, LocalBackend.FLUX_CLI:
			_generate_cli(request)

	return request.id

## Check if local API is responding
func _check_api_available() -> bool:
	# Quick ping check - in real implementation, make async
	var output = []
	var exit_code = OS.execute("curl", ["-s", "-o", "/dev/null", "-w", "%{http_code}", api_url], output, true)
	return exit_code == 0 and output.size() > 0 and output[0].strip_edges() == "200"

## Check if Python and required packages are available
func _check_cli_available() -> bool:
	var output = []
	var exit_code = OS.execute(python_cmd, ["-c", "import torch; import diffusers; print('ok')"], output, true)
	return exit_code == 0 and output.size() > 0 and "ok" in output[0]

## Generate via ComfyUI API
func _generate_comfyui(request):
	# ComfyUI uses workflow-based generation
	var workflow = _build_comfyui_workflow(request)

	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({"prompt": workflow})

	http_request.set_meta("current_request_id", request.id)
	http_request.request(api_url + "/prompt", headers, HTTPClient.METHOD_POST, body)

func _build_comfyui_workflow(request) -> Dictionary:
	# Simplified ComfyUI workflow - would need customization for your setup
	return {
		"3": {
			"class_type": "KSampler",
			"inputs": {
				"seed": request.seed if request.seed >= 0 else randi(),
				"steps": 20,
				"cfg": 7.5,
				"sampler_name": "euler",
				"scheduler": "normal",
				"denoise": 1.0,
				"model": ["4", 0],
				"positive": ["6", 0],
				"negative": ["7", 0],
				"latent_image": ["5", 0]
			}
		},
		"4": {
			"class_type": "CheckpointLoaderSimple",
			"inputs": {"ckpt_name": model_path if model_path != "" else "v1-5-pruned.ckpt"}
		},
		"5": {
			"class_type": "EmptyLatentImage",
			"inputs": {"width": request.width, "height": request.height, "batch_size": 1}
		},
		"6": {
			"class_type": "CLIPTextEncode",
			"inputs": {"text": request.prompt, "clip": ["4", 1]}
		},
		"7": {
			"class_type": "CLIPTextEncode",
			"inputs": {"text": request.negative_prompt, "clip": ["4", 1]}
		},
		"8": {
			"class_type": "VAEDecode",
			"inputs": {"samples": ["3", 0], "vae": ["4", 2]}
		},
		"9": {
			"class_type": "SaveImage",
			"inputs": {"filename_prefix": "godot_gen", "images": ["8", 0]}
		}
	}

## Generate via Automatic1111 API
func _generate_auto1111(request):
	var body = {
		"prompt": request.prompt,
		"negative_prompt": request.negative_prompt,
		"width": request.width,
		"height": request.height,
		"steps": 20,
		"cfg_scale": 7.5,
		"seed": request.seed if request.seed >= 0 else -1,
	}

	var headers = ["Content-Type: application/json"]
	http_request.set_meta("current_request_id", request.id)
	http_request.request(api_url + "/sdapi/v1/txt2img", headers, HTTPClient.METHOD_POST, JSON.stringify(body))

## Generate via CLI (diffusers or FLUX)
func _generate_cli(request):
	var cli_path = ProjectSettings.globalize_path(CLI_SCRIPT_PATH)
	var output_dir = ProjectSettings.globalize_path("user://generated_assets/")

	# Ensure output directory exists
	DirAccess.make_dir_recursive_absolute(output_dir)

	var args = [
		cli_path,
		"--prompt", request.prompt,
		"--width", str(request.width),
		"--height", str(request.height),
		"--output", output_dir + request.id + ".png",
	]

	if request.negative_prompt != "":
		args.append_array(["--negative", request.negative_prompt])

	if request.seed >= 0:
		args.append_array(["--seed", str(request.seed)])

	if model_path != "":
		args.append_array(["--model", model_path])

	if backend == LocalBackend.FLUX_CLI:
		args.append("--flux")

	# Run generation in background thread
	var thread = Thread.new()
	thread.start(_run_cli_generation.bind(request.id, args, thread))

func _run_cli_generation(request_id: String, args: Array, thread: Thread):
	var output = []
	var exit_code = OS.execute(python_cmd, args, output, true)

	# Call back to main thread
	call_deferred("_on_cli_complete", request_id, exit_code, output, thread)

func _on_cli_complete(request_id: String, exit_code: int, output: Array, thread: Thread):
	thread.wait_to_finish()

	if exit_code != 0:
		var error = output[0] if output.size() > 0 else "Unknown error"
		generation_failed.emit(request_id, "CLI generation failed: " + error)
		pending_requests.erase(request_id)
		return

	var image_path = "user://generated_assets/" + request_id + ".png"
	if FileAccess.file_exists(image_path):
		generation_completed.emit(request_id, image_path)
	else:
		generation_failed.emit(request_id, "Generated image not found")

	pending_requests.erase(request_id)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var request_id = http_request.get_meta("current_request_id", "unknown")

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		generation_failed.emit(request_id, "API request failed: %d" % response_code)
		pending_requests.erase(request_id)
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		generation_failed.emit(request_id, "Failed to parse response")
		pending_requests.erase(request_id)
		return

	var data = json.data

	# Handle Auto1111 response (base64 encoded image)
	if data.has("images") and data.images.size() > 0:
		var image_b64 = data.images[0]
		var image_data = Marshalls.base64_to_raw(image_b64)
		var filename = "local_%s.png" % request_id
		var path = _save_image_to_file(image_data, filename)

		if path != "":
			generation_completed.emit(request_id, path)
		else:
			generation_failed.emit(request_id, "Failed to save image")

	# Handle ComfyUI response (would need to poll for completion)
	elif data.has("prompt_id"):
		# ComfyUI returns a prompt_id, need to poll for result
		# For simplicity, this is stubbed - full implementation would poll /history
		print("[LocalSD] ComfyUI job submitted: %s" % data.prompt_id)

	pending_requests.erase(request_id)

func _save_image_to_file(image_data: PackedByteArray, filename: String) -> String:
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("generated_assets"):
		dir.make_dir("generated_assets")

	var path = "user://generated_assets/" + filename
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(image_data)
		file.close()
		return path
	return ""
