extends StoryItem
class_name DrawingUrn
## DrawingUrn - The chapel's lot urn (scenes/interiors/thornhaven_chapel.tscn, Interactables/LotUrn)
## Before the Tithe drawing (tn_drawing) it is where the player can try to stop it: interacting offers
## to look at it as usual, speak up against the lot (an accusation) or stand between Mathias and the
## urn (a refusal). Either of the last two goes through OpeningSequence.disrupt(), which sets
## tn_drawing_disrupted and records the PlayerEvent. Once the name is read (or the rite is broken
## off) it is an ordinary StoryItem again

const CHOICES = [
	{"id": "look", "label": "Look at the urn"},
	{"id": "accusation", "label": "Speak up: \"Someone's hand is in that lot.\""},
	{"id": "refusal", "label": "Stand between Mathias and the urn"},
	{"id": "leave", "label": "Leave it"},
]

var _choice_canvas: CanvasLayer = null

func _opening() -> Node:
	var scene_manager = get_node_or_null("/root/SceneManager")
	return scene_manager.opening if scene_manager and "opening" in scene_manager else null

func _on_interact():
	var opening = _opening()
	if opening and opening.has_method("can_disrupt") and opening.can_disrupt():
		show_choices()
	else:
		super._on_interact()

func get_prompt_text() -> String:
	var opening = _opening()
	if opening and opening.has_method("can_disrupt") and opening.can_disrupt():
		return "[E] Go up to the urn"
	return super.get_prompt_text()

func is_choosing() -> bool:
	return is_instance_valid(_choice_canvas)

## The before-the-drawing choices, in the StoryItem popup style
func show_choices() -> void:
	if is_choosing():
		return
	_choice_canvas = CanvasLayer.new()
	_choice_canvas.name = "UrnChoices"
	_choice_canvas.layer = 100
	var popup = Panel.new()
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18 if side in ["left", "right"] else 14)
	popup.add_child(margin)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.custom_minimum_size = Vector2(440, 0)
	label.text = "[b]The lot urn[/b]\n\nMathias stands over it with his eyes already closed, waiting for ten past the hour. Nobody else is looking at it. Everybody is."
	vbox.add_child(label)
	for choice in CHOICES:
		var button = Button.new()
		button.text = choice.label
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(choose.bind(choice.id))
		vbox.add_child(button)
	_choice_canvas.add_child(popup)
	var host = get_tree().current_scene if get_tree().current_scene else self
	host.add_child(_choice_canvas)
	popup.size = popup.get_combined_minimum_size()
	await get_tree().process_frame
	if is_instance_valid(popup):
		popup.size = popup.get_combined_minimum_size()
		popup.position = (popup.get_viewport_rect().size - popup.size) / 2

## "look" | "accusation" | "refusal" | "leave"
func choose(choice_id: String) -> void:
	if is_instance_valid(_choice_canvas):
		_choice_canvas.queue_free()
	_choice_canvas = null
	match choice_id:
		"look":
			super._on_interact()
		"accusation", "refusal":
			var opening = _opening()
			if opening and opening.has_method("disrupt"):
				opening.disrupt(choice_id)
			_show_prompt(player_in_range)

func _unhandled_input(event: InputEvent):
	if is_choosing() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		choose("leave")
		return
	super._unhandled_input(event)
