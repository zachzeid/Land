extends Interactable
class_name StoryItem
## StoryItem - Interactable that sets world flags and shows discovery text
## Used for key story items like ledgers, letters, evidence, etc.

## The world flag to set when this item is examined
@export var flag_to_set: String = ""

## Text shown when player first discovers this item
@export_multiline var discovery_text: String = "You found something interesting."

## Text shown if player examines item again after discovery
@export_multiline var reexamine_text: String = "You've already examined this."

## Whether this item can only be interacted with once
@export var one_time_only: bool = false

## Optional: Flag that must be set before this item is visible/interactable
@export var requires_flag: String = ""

## Sound effect to play on discovery (optional)
@export var discovery_sound: AudioStream

var has_been_discovered: bool = false

func _ready():
	super._ready()
	add_to_group("story_items")

	# Check if already discovered (from save data)
	if flag_to_set != "" and WorldState:
		has_been_discovered = WorldState.get_world_flag(flag_to_set)

	# Check prerequisite flag
	_update_visibility()

	# Listen for flag changes to update visibility
	if requires_flag != "" and EventBus:
		EventBus.world_flag_changed.connect(_on_world_flag_changed)

func _update_visibility():
	if requires_flag != "":
		var prereq_met = WorldState.get_world_flag(requires_flag) if WorldState else false
		visible = prereq_met
		enabled = prereq_met

func _on_world_flag_changed(flag_name: String, _old_value, new_value):
	if flag_name == requires_flag:
		visible = new_value
		enabled = new_value

func _on_interact():
	if one_time_only and has_been_discovered:
		_show_message(reexamine_text)
		return

	if not has_been_discovered:
		# First discovery
		has_been_discovered = true

		# Set the world flag
		if flag_to_set != "" and WorldState:
			WorldState.set_world_flag(flag_to_set, true)
			print("[StoryItem] Set flag: %s" % flag_to_set)

		# Play discovery sound
		if discovery_sound:
			var audio_player = AudioStreamPlayer.new()
			add_child(audio_player)
			audio_player.stream = discovery_sound
			audio_player.play()
			audio_player.finished.connect(audio_player.queue_free)

		_show_message(discovery_text)

		# Emit signal for any listeners
		interacted.emit(self)

		# Emit event bus signal for discovery
		if EventBus:
			EventBus.world_event.emit({
				"type": "item_discovered",
				"item_id": name,
				"flag": flag_to_set
			})
	else:
		_show_message(reexamine_text)

func _show_message(text: String):
	# Find or create a message display
	# For now, use a simple approach - look for DialogueUI or create popup
	var dialogue_ui = get_tree().get_first_node_in_group("dialogue_ui")
	if dialogue_ui and dialogue_ui.has_method("show_narration"):
		dialogue_ui.show_narration(text)
	else:
		# Fallback: Create a simple popup
		_show_popup(text)

func _show_popup(text: String):
	# Create a simple centered popup for the discovery text
	var popup = Panel.new()
	popup.name = "DiscoveryPopup"

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	popup.add_child(margin)

	var vbox = VBoxContainer.new()
	margin.add_child(vbox)

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = text
	label.fit_content = true
	label.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(label)

	var button = Button.new()
	button.text = "Continue"
	button.pressed.connect(func(): popup.queue_free())
	vbox.add_child(button)

	# Add to canvas layer so it's on top
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	canvas.add_child(popup)
	get_tree().current_scene.add_child(canvas)

	# Center the popup
	await get_tree().process_frame
	popup.position = (get_viewport().get_visible_rect().size - popup.size) / 2

	# Auto-close after delay if player doesn't click
	get_tree().create_timer(10.0).timeout.connect(func():
		if is_instance_valid(canvas):
			canvas.queue_free()
	)
