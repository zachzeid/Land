extends SceneTree
## CLI tool to download character assets from PixelLab
## Usage: godot --headless --script scripts/debug/download_pixellab_assets.gd -- [character_id] [target_folder_name]
##
## Examples:
##   godot --headless --script scripts/debug/download_pixellab_assets.gd -- 5b673979-b0f2-48ab-b562-93fd76e279ce gregor_merchant
##   godot --headless --script scripts/debug/download_pixellab_assets.gd -- --list

const ASSET_DIR = "res://assets/generated/characters/"

func _init():
	var args = OS.get_cmdline_user_args()

	print("\n" + "=".repeat(60))
	print("PIXELLAB ASSET DOWNLOADER")
	print("=".repeat(60))

	if args.is_empty() or "--help" in args:
		_print_help()
		quit(0)
		return

	if "--list" in args:
		print("\nKnown character IDs from this session:")
		print("  Gregor: 5b673979-b0f2-48ab-b562-93fd76e279ce -> gregor_merchant")
		print("  Mira:   4ca4bdbb-6ae6-4c79-9c7d-70b4a8d4530f -> mira_tavern_keeper")
		print("  Bjorn:  34480637-7699-42a4-80d0-59a61185972e -> bjorn_blacksmith")
		print("\nUse the Download as ZIP link from get_character to download manually.")
		quit(0)
		return

	if args.size() < 2:
		print("ERROR: Need character_id and target_folder_name")
		_print_help()
		quit(1)
		return

	var character_id = args[0]
	var folder_name = args[1]

	print("\nCharacter ID: %s" % character_id)
	print("Target folder: %s%s/" % [ASSET_DIR, folder_name])

	_print_download_instructions(character_id, folder_name)

	quit(0)

func _print_help():
	print("""
Usage: godot --headless --script scripts/debug/download_pixellab_assets.gd -- [options]

Options:
  --list                List known character IDs from this session
  --help                Show this help message
  <id> <folder>         Download character to specified folder

To download assets, use curl with the ZIP URL from PixelLab:

  curl --fail -o character.zip "https://api.pixellab.ai/mcp/characters/<id>/download"
  unzip character.zip -d assets/generated/characters/<folder_name>/

Example:
  curl --fail -o gregor.zip "https://api.pixellab.ai/mcp/characters/5b673979-b0f2-48ab-b562-93fd76e279ce/download"
  unzip gregor.zip -d assets/generated/characters/gregor_merchant/
""")

func _print_download_instructions(character_id: String, folder_name: String):
	var target_dir = "assets/generated/characters/%s" % folder_name
	var zip_url = "https://api.pixellab.ai/mcp/characters/%s/download" % character_id

	print("""

=== DOWNLOAD INSTRUCTIONS ===

Run these commands in terminal:

# 1. Create target directory
mkdir -p %s

# 2. Download the ZIP file
curl --fail -L -o /tmp/%s.zip "%s"

# 3. Unzip to target directory
unzip -o /tmp/%s.zip -d %s/

# 4. Clean up
rm /tmp/%s.zip

# Or as a one-liner:
mkdir -p %s && curl --fail -L -o /tmp/%s.zip "%s" && unzip -o /tmp/%s.zip -d %s/ && rm /tmp/%s.zip

================================
""" % [
		target_dir,
		folder_name, zip_url,
		folder_name, target_dir,
		folder_name,
		target_dir, folder_name, zip_url, folder_name, target_dir, folder_name
	])
