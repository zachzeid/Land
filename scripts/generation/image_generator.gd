extends Node
class_name ImageGenerator
## ImageGenerator - Abstract base class for AI image generation backends
## Supports both cloud APIs (Recraft, Leonardo) and local generation (Stable Diffusion)

signal generation_started(request_id: String)
signal generation_completed(request_id: String, image_path: String)
signal generation_failed(request_id: String, error: String)
signal generation_progress(request_id: String, progress: float)

## Generation request structure
class GenerationRequest:
	var id: String
	var prompt: String
	var negative_prompt: String = ""
	var width: int = 512
	var height: int = 512
	var style_preset: String = ""  # e.g., "pixel_art", "painterly", "realistic"
	var seed: int = -1  # -1 = random
	var reference_images: Array[String] = []  # Paths to style reference images
	var metadata: Dictionary = {}  # Extra backend-specific params

	func _init(p_prompt: String = ""):
		id = str(Time.get_ticks_usec()) + "_" + str(randi())
		prompt = p_prompt

## Backend type enum
enum BackendType {
	RECRAFT,
	LEONARDO,
	LOCAL_SD,
	LOCAL_FLUX,
	MOCK  # For testing without API calls
}

## Must be implemented by subclasses
func generate(request: GenerationRequest) -> String:
	push_error("ImageGenerator.generate() must be implemented by subclass")
	return ""

## Check if backend is available/configured
func is_available() -> bool:
	push_error("ImageGenerator.is_available() must be implemented by subclass")
	return false

## Get backend name for logging
func get_backend_name() -> String:
	return "BaseImageGenerator"

## Cancel a pending generation
func cancel(request_id: String) -> bool:
	return false  # Override if backend supports cancellation

## Helper to save image data to file
func _save_image(image_data: PackedByteArray, filename: String) -> String:
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

## Helper to load image as texture
static func load_generated_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null

	var image = Image.new()
	var err = image.load(path)
	if err != OK:
		return null

	return ImageTexture.create_from_image(image)
