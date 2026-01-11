class_name WorldSettings
extends Resource
## WorldSettings - Centralized visual configuration for zones
## Controls asset generation prompts, sizing, and color palettes

## Zone dimensions
@export var zone_size: Vector2 = Vector2(1024, 1024)
@export var grid_unit: int = 32

## Recraft API settings
@export var recraft_style: String = "digital_illustration"
@export var recraft_size: Vector2i = Vector2i(1024, 1024)

## Prompt components
@export_multiline var global_style_prefix: String = """2D top-down game scene, bird's eye view at slight angle, medieval fantasy RPG style, painterly hand-drawn look, warm earth tones, soft diffused lighting, complete scene composition, consistent perspective"""

@export_multiline var zone_style: String = """rustic medieval village, weathered wooden buildings, thatched roofs, cobblestone paths, cozy lived-in feel, autumn afternoon lighting"""

## Scene background template (for full scene generation)
@export_group("Scene Templates")

@export_multiline var scene_template: String = """2D top-down game scene, bird's eye view, {location_name}, showing {elements}, with clear paths for character movement, {details}, cohesive single-image composition, 1024x1024"""

## Asset-specific prompt templates (for individual sprites if needed)
@export_group("Prompt Templates")

@export_multiline var building_template: String = """2D top-down game building sprite, bird's eye view, {size} medieval {type}, {details}, transparent background, isolated single building, clear silhouette, shadow beneath, no ground texture"""

@export_multiline var tree_template: String = """2D top-down game tree sprite, bird's eye view, {size} {type} tree, {details}, transparent background, full canopy visible from above, isolated single tree, shadow beneath"""

@export_multiline var prop_template: String = """2D top-down game prop sprite, bird's eye view, {details}, transparent background, medieval village prop, isolated object, shadow beneath"""

@export_multiline var character_template: String = """2D top-down game character sprite, bird's eye view, medieval {type}, {details}, standing pose visible from above"""

## Color palette
@export_group("Color Palette")
@export var color_ground: Color = Color("#384F2E")
@export var color_path: Color = Color("#7A6B57")
@export var color_square: Color = Color("#6B6152")
@export var color_wood: Color = Color("#5C4A3D")
@export var color_thatch: Color = Color("#8B7355")
@export var color_slate: Color = Color("#4A4A4A")
@export var color_foliage: Color = Color("#4A7A3A")
@export var color_accent_gold: Color = Color("#C4A35A")
@export var color_accent_rust: Color = Color("#8B4513")

## Standard asset sizes based on grid
enum AssetSize { TINY, SMALL, MEDIUM, LARGE, BUILDING_S, BUILDING_M, BUILDING_L }

const SIZE_PIXELS: Dictionary = {
	AssetSize.TINY: Vector2(32, 32),
	AssetSize.SMALL: Vector2(64, 64),
	AssetSize.MEDIUM: Vector2(96, 96),
	AssetSize.LARGE: Vector2(128, 128),
	AssetSize.BUILDING_S: Vector2(128, 128),
	AssetSize.BUILDING_M: Vector2(160, 128),
	AssetSize.BUILDING_L: Vector2(192, 160),
}

const SIZE_NAMES: Dictionary = {
	AssetSize.TINY: "tiny",
	AssetSize.SMALL: "small",
	AssetSize.MEDIUM: "medium",
	AssetSize.LARGE: "large",
	AssetSize.BUILDING_S: "small",
	AssetSize.BUILDING_M: "medium",
	AssetSize.BUILDING_L: "large",
}

## Build a complete scene background prompt
func build_scene_prompt(location_name: String, elements: String, details: String = "") -> String:
	var prompt = scene_template.replace("{location_name}", location_name)
	prompt = prompt.replace("{elements}", elements)
	prompt = prompt.replace("{details}", details)
	return global_style_prefix + ", " + zone_style + ", " + prompt

## Build a complete generation prompt for an asset
func build_prompt(asset_type: String, details: String, size: AssetSize = AssetSize.MEDIUM) -> String:
	var template = _get_template(asset_type)
	var size_name = SIZE_NAMES.get(size, "medium")

	# Replace template variables
	var prompt = template.replace("{details}", details)
	prompt = prompt.replace("{size}", size_name)
	prompt = prompt.replace("{type}", asset_type)

	# Combine with global and zone styles
	return global_style_prefix + ", " + zone_style + ", " + prompt

## Build prompt with custom type substitution
func build_prompt_custom(asset_type: String, type_name: String, details: String, size: AssetSize = AssetSize.MEDIUM) -> String:
	var template = _get_template(asset_type)
	var size_name = SIZE_NAMES.get(size, "medium")

	var prompt = template.replace("{details}", details)
	prompt = prompt.replace("{size}", size_name)
	prompt = prompt.replace("{type}", type_name)

	return global_style_prefix + ", " + zone_style + ", " + prompt

## Get pixel dimensions for an asset size
func get_size_pixels(size: AssetSize) -> Vector2:
	return SIZE_PIXELS.get(size, Vector2(96, 96))

## Get the template for an asset type
func _get_template(asset_type: String) -> String:
	match asset_type:
		"building":
			return building_template
		"tree":
			return tree_template
		"prop":
			return prop_template
		"character":
			return character_template
		_:
			return prop_template

## Get color palette as dictionary
func get_palette() -> Dictionary:
	return {
		"ground": color_ground,
		"path": color_path,
		"square": color_square,
		"wood": color_wood,
		"thatch": color_thatch,
		"slate": color_slate,
		"foliage": color_foliage,
		"accent_gold": color_accent_gold,
		"accent_rust": color_accent_rust,
	}

## Calculate zone bounds (centered at origin)
func get_zone_bounds() -> Rect2:
	var half_size = zone_size / 2
	return Rect2(-half_size, zone_size)
