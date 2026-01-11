extends Area2D
class_name SceneTrigger
## SceneTrigger - Zone that triggers scene transitions
## Used for building doors, cave entrances, town exits

## Collision layer constants
const LAYER_TRIGGER = 6

## Target location ID (must match a LocationData resource)
@export var target_location: String = ""

## Spawn point name in target scene
@export var target_spawn_point: String = "default"

## Whether to require player input (E) or auto-transition on enter
@export var require_input: bool = true

## Display text for interaction prompt
@export var prompt_text: String = "Enter"

## Optional: fade duration for transition
@export var fade_duration: float = 0.3

signal triggered(trigger: SceneTrigger)

var player_in_range: bool = false
var transition_cooldown: bool = false
const COOLDOWN_TIME: float = 0.5

func _ready():
	# Add to group for debug discovery
	add_to_group("scene_triggers")
	add_to_group("interactables")

	# Set collision layer to trigger (layer 6)
	collision_layer = 1 << (LAYER_TRIGGER - 1)
	# Monitor player (layer 1)
	collision_mask = 1 << 0

	monitoring = true
	monitorable = false

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	print("[SceneTrigger] %s ready → %s (require_input: %s)" % [name, target_location, require_input])

func _unhandled_input(event: InputEvent):
	if not require_input or not player_in_range:
		return

	if event.is_action_pressed("interact"):
		_trigger_transition()
		get_viewport().set_input_as_handled()

func _on_body_entered(body: Node2D):
	print("[SceneTrigger] %s: body_entered - %s (groups: %s)" % [name, body.name, body.get_groups()])
	if body.is_in_group("player") or body.name == "Player":
		print("[SceneTrigger] %s: PLAYER ENTERED!" % name)
		player_in_range = true
		if require_input:
			_show_prompt(true)
		else:
			# Auto-transition (with cooldown check)
			if not transition_cooldown:
				_trigger_transition()

func _on_body_exited(body: Node2D):
	print("[SceneTrigger] %s: body_exited - %s" % [name, body.name])
	if body.is_in_group("player") or body.name == "Player":
		print("[SceneTrigger] %s: PLAYER EXITED!" % name)
		player_in_range = false
		_show_prompt(false)

func _trigger_transition():
	if transition_cooldown:
		return

	transition_cooldown = true
	triggered.emit(self)

	# Use SceneManager if available
	if has_node("/root/SceneManager"):
		var scene_manager = get_node("/root/SceneManager")
		scene_manager.transition_to(target_location, target_spawn_point, fade_duration)
	else:
		push_warning("[SceneTrigger] SceneManager not found - cannot transition to %s" % target_location)

	# Reset cooldown after delay
	await get_tree().create_timer(COOLDOWN_TIME).timeout
	transition_cooldown = false

func _show_prompt(show: bool):
	if has_node("InteractionPrompt"):
		var prompt = get_node("InteractionPrompt")
		prompt.visible = show
		if show and prompt is Label:
			prompt.text = "[E] %s" % prompt_text
