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

## A world flag that must be set before this way is open (empty: always open). A way found by a
## puzzle (old_workings_way_found) stays shut, with closed_text said in the world, until it is found
@export var requires_flag: String = ""
## What the player is told while requires_flag is unset: the in-world reason the way is shut
@export_multiline var closed_text: String = ""

## Set at runtime by whatever owns the way (a puzzle room): why it is shut now, "" when not
var closed_reason: String = ""

signal triggered(trigger: SceneTrigger)
signal refused(trigger: SceneTrigger, reason: String)

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

## Open: the required flag is set and nothing has shut the way
func is_open() -> bool:
	return why_closed() == ""

## Why the way is shut ("" when open): the owner's reason first, then the missing flag's
func why_closed() -> String:
	if closed_reason != "":
		return closed_reason
	if requires_flag != "":
		var ws = get_node_or_null("/root/WorldState")
		if ws == null or not ws.get_world_flag(requires_flag):
			return closed_text if closed_text != "" else "The way is shut."
	return ""

func _trigger_transition():
	if transition_cooldown:
		return
	var reason = why_closed()
	if reason != "":
		refused.emit(self, reason)
		_say(reason)
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

## The reason a way is shut, said in the world (a narration line, else a short-lived panel)
func _say(text: String) -> void:
	print("[SceneTrigger] %s is shut: %s" % [name, text])
	if not is_inside_tree():
		return
	var dialogue_ui = get_tree().get_first_node_in_group("dialogue_ui")
	if dialogue_ui and dialogue_ui.has_method("show_narration"):
		dialogue_ui.show_narration(text)
		return
	var scene = get_tree().current_scene
	if scene == null or DisplayServer.get_name() == "headless":
		return
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	var panel = PanelContainer.new()
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	panel.add_child(label)
	canvas.add_child(panel)
	scene.add_child(canvas)
	panel.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 - 220.0, 40.0)
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_instance_valid(canvas):
			canvas.queue_free())
