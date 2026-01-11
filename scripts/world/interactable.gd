extends Area2D
class_name Interactable
## Interactable - Base class for objects player can interact with
## Doors, chests, wells, signs, etc.

## Collision layer constants
const LAYER_INTERACTABLE = 5

## Display name shown in interaction prompt
@export var interaction_name: String = "Interact"

## Custom prompt text (defaults to "[E] {interaction_name}")
@export var prompt_text: String = ""

## Whether this interactable is currently enabled
@export var enabled: bool = true

## Signals
signal interaction_available(interactable: Interactable)
signal interaction_ended(interactable: Interactable)
signal interacted(interactable: Interactable)

var player_in_range: bool = false

func _ready():
	# Set collision layer to interactable (layer 5)
	collision_layer = 1 << (LAYER_INTERACTABLE - 1)
	# Monitor player (layer 1)
	collision_mask = 1 << 0

	# Ensure Area2D is set to monitoring
	monitoring = true
	monitorable = false

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _unhandled_input(event: InputEvent):
	if not enabled or not player_in_range:
		return

	if event.is_action_pressed("interact"):
		_on_interact()
		get_viewport().set_input_as_handled()

func _on_body_entered(body: Node2D):
	if body.is_in_group("player") or body.name == "Player":
		player_in_range = true
		interaction_available.emit(self)
		_show_prompt(true)

func _on_body_exited(body: Node2D):
	if body.is_in_group("player") or body.name == "Player":
		player_in_range = false
		interaction_ended.emit(self)
		_show_prompt(false)

func _on_interact():
	interacted.emit(self)

func _show_prompt(show: bool):
	# Override in subclasses or find InteractionPrompt child
	if has_node("InteractionPrompt"):
		var prompt = get_node("InteractionPrompt")
		prompt.visible = show
		if show and prompt is Label:
			prompt.text = get_prompt_text()

func get_prompt_text() -> String:
	if prompt_text != "":
		return prompt_text
	return "[E] %s" % interaction_name

## Disable interaction (e.g., locked door)
func set_enabled(value: bool):
	enabled = value
	if not enabled and player_in_range:
		_show_prompt(false)
