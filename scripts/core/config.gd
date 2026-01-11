extends Node
# Config - Loads and manages configuration (API keys, settings)

var claude_api_key: String = ""
var anthropic_api_key: String = ""  # Alias for Claude API key
var chroma_url: String = "http://localhost:8000"
var pixellab_api_key: String = ""

func _ready():
	print("Config initialized")
	load_config()

func load_config():
	# Load from .env file
	var env_path = "res://.env"
	if FileAccess.file_exists(env_path):
		var file = FileAccess.open(env_path, FileAccess.READ)
		while not file.eof_reached():
			var line = file.get_line().strip_edges()
			if line.begins_with("#") or line.is_empty():
				continue
			
			var parts = line.split("=", true, 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges()
				var value = parts[1].strip_edges()
				
				# Strip quotes if present
				if value.begins_with('"') and value.ends_with('"'):
					value = value.substr(1, value.length() - 2)
				elif value.begins_with("'") and value.ends_with("'"):
					value = value.substr(1, value.length() - 2)
				
				match key:
					"CLAUDE_API_KEY", "ANTHROPIC_API_KEY":
						claude_api_key = value
						anthropic_api_key = value
						if not value.is_empty() and value != "your_claude_api_key_here":
							print("Config: Claude API key loaded (", value.substr(0, 12), "...)")
						else:
							push_warning("Config: Claude API key is empty or placeholder")
					"CHROMA_URL":
						chroma_url = value
						print("Config: ChromaDB URL = ", value)
					"PIXELLAB_API_KEY":
						pixellab_api_key = value
						if not value.is_empty():
							print("Config: PixelLab API key loaded (", value.substr(0, 12), "...)")
		
		file.close()
	else:
		push_warning("No .env file found. Create one with CLAUDE_API_KEY=your_key_here")

func get_claude_api_key() -> String:
	return claude_api_key

func get_chroma_url() -> String:
	return chroma_url
