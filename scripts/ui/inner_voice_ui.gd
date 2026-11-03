extends CanvasLayer
## InnerVoiceUI - "Your thoughts": the player's private intentions (docs/WORLD_SCHEMA.md §13)
## The inner_voice action (T) opens a small box at the bottom left. Enter keeps the thought (it goes
## to InnerVoice.think(), which the director reads), Esc lets it go. A faint acknowledgement follows;
## nothing is ever said to an NPC
## Privacy is the whole point: this script talks to InnerVoice and nothing else. It never touches
## DialogueManager, DialogueUI, an NPC, EventBus or PlayerEvents, and it will not open during a
## conversation (the tree is paused) so a thought can never be typed into the dialogue box by mistake
## The quest journal's Thoughts tab lists get_thoughts()

signal thought_submitted(entry: Dictionary)

const ACTION = "inner_voice"
const ACK_TEXT = "You keep the thought to yourself."
const ACK_SECONDS = 1.8
const MAX_CHARS = 280

## Injectable for tests; the InnerVoice autoload otherwise (director engine)
var voice: Node = null
var is_open: bool = false
var _log: Array = []          # this session's thoughts: {text, intention, minute, time}
var _panel: PanelContainer
var _field: LineEdit
var _ack: Label
var _ack_tween: Tween

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("inner_voice_ui")
	_build()
	_panel.visible = false
	_ack.visible = false

func _build() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08, 0.9)
	style.border_color = Color(0.55, 0.42, 0.22, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	_panel = PanelContainer.new()
	_panel.name = "ThoughtsPanel"
	_panel.add_theme_stylebox_override("panel", style)
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 24
	_panel.offset_right = 24 + 440
	_panel.offset_top = -112
	_panel.offset_bottom = -24
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)
	var title = Label.new()
	title.text = "Your thoughts"
	title.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6, 1))
	title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(title)
	_field = LineEdit.new()
	_field.name = "ThoughtInput"
	_field.placeholder_text = "What do you mean to do?"
	_field.max_length = MAX_CHARS
	_field.custom_minimum_size = Vector2(416, 0)
	_field.add_theme_font_size_override("font_size", 14)
	_field.text_submitted.connect(submit)
	vbox.add_child(_field)
	var hint = Label.new()
	hint.text = "Enter keeps it. Esc lets it go. Nobody else hears."
	hint.add_theme_color_override("font_color", Color(0.55, 0.52, 0.46, 1))
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)
	_ack = Label.new()
	_ack.name = "Acknowledgement"
	_ack.text = ACK_TEXT
	_ack.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6, 1))
	_ack.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_ack.add_theme_constant_override("outline_size", 3)
	_ack.add_theme_font_size_override("font_size", 13)
	_ack.anchor_top = 1.0
	_ack.anchor_bottom = 1.0
	_ack.offset_left = 28
	_ack.offset_top = -48
	_ack.offset_right = 28 + 440
	_ack.offset_bottom = -24
	add_child(_ack)

func _unhandled_input(event: InputEvent) -> void:
	if not is_open and event.is_action_pressed(ACTION) and can_open():
		get_viewport().set_input_as_handled()
		open()

func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

## Never during a conversation, the journal, the travel map or the epilogue (they pause the tree)
func can_open() -> bool:
	if get_tree().paused:
		return false
	var dialogue = get_node_or_null("/root/DialogueManager")
	if dialogue and "active_conversations" in dialogue and not dialogue.active_conversations.is_empty():
		return false
	return true

func open() -> void:
	is_open = true
	_field.text = ""
	_panel.visible = true
	_field.grab_focus.call_deferred()

func close() -> void:
	is_open = false
	_panel.visible = false
	if _field.has_focus():
		_field.release_focus()

## Keep a thought: InnerVoice.think(text) parses it into an intention for the director.
## Returns the entry logged ({} for an empty thought)
func submit(text: String) -> Dictionary:
	text = text.strip_edges().substr(0, MAX_CHARS)
	close()
	if text == "":
		return {}
	var target = _voice()
	var intention = {}
	if target and target.has_method("think"):
		var result = target.think(text)
		intention = result if result is Dictionary else {}
	var world_state = get_node_or_null("/root/WorldState")
	var entry = {"text": text, "intention": intention,
		"minute": world_state.get_game_minutes() if world_state else 0,
		"time": world_state.get_time_string() if world_state else ""}
	_log.append(entry)
	_acknowledge()
	thought_submitted.emit(entry)
	return entry

## Past intentions, oldest first. InnerVoice's own record when it keeps one (it is saved with the
## world), else this session's log. Each is a Dictionary: text / goal / about / stance / strength
func get_thoughts() -> Array:
	var target = _voice()
	if target and target.has_method("get_intentions"):
		var kept = target.get_intentions()
		if kept is Array and not kept.is_empty():
			return kept.duplicate(true)
	return _log.duplicate(true)

func get_ack_text() -> String:
	return _ack.text if _ack and _ack.visible else ""

func _voice() -> Node:
	return voice if voice else get_node_or_null("/root/InnerVoice")

func _acknowledge() -> void:
	if _ack_tween:
		_ack_tween.kill()
	_ack.text = ACK_TEXT
	_ack.visible = true
	_ack.modulate.a = 0.0
	if not is_inside_tree():
		return
	_ack_tween = create_tween()
	_ack_tween.tween_property(_ack, "modulate:a", 0.85, 0.3)
	_ack_tween.tween_interval(ACK_SECONDS)
	_ack_tween.tween_property(_ack, "modulate:a", 0.0, 0.6)
	_ack_tween.tween_callback(func(): _ack.visible = false)
