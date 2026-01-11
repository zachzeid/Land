extends Node2D
class_name WorldProp
## WorldProp - Non-blocking scenery (grass, flowers, puddles, cracks)
## Pure visual decoration with no collision

## Optional: support for GeneratableAsset
@export var asset_id: String = ""
@export_multiline var generation_prompt: String = ""
