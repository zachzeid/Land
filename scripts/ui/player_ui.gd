extends Node
## PlayerUI - The player's own persistent UI: their thoughts, the menu and the epilogue
## Instanced once beside the opening under SceneManager (scenes/ui/player_ui.tscn), so it outlives
## every scene change
## - InnerVoiceUI (scenes/ui/inner_voice_ui.tscn): the inner_voice action (T), WORLD_SCHEMA §13
## - The menu: Esc when nothing else is open pauses and offers Resume or "End my story here"; ending
##   asks for confirmation, then shows the epilogue
## - EpilogueScreen (scenes/ui/epilogue_screen.tscn): WORLD_SCHEMA §15, also shown by itself when the
##   season_end fixed point fires

signal story_ended(reason: String)

const SEASON_END = "season_end"

var inner_voice_ui: CanvasLayer
var epilogue_screen: CanvasLayer
var story_over: bool = false
var _menu_layer: CanvasLayer
var _menu: Control
var _confirm: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("player_ui")
	inner_voice_ui = load("res://scenes/ui/inner_voice_ui.tscn").instantiate()
	add_child(inner_voice_ui)
	epilogue_screen = load("res://scenes/ui/epilogue_screen.tscn").instantiate()
	add_child(epilogue_screen)
	epilogue_screen.quit_requested.connect(func(): get_tree().quit())
	_build_menu()
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.calendar_flag_fired.connect(_on_calendar_flag_fired)

func _on_calendar_flag_fired(flag_name: String, _at_minute: int) -> void:
	if flag_name == SEASON_END:
		_end_when_free("season_end")

# =============================================================================
# THE MENU
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if is_menu_open():
		get_viewport().set_input_as_handled()
		if _confirm.visible:
			cancel_end_story()
		else:
			close_menu()
	elif can_open_menu():
		get_viewport().set_input_as_handled()
		open_menu()

## Only over the world itself: not over a conversation, the journal, a map, a card or a thought
func can_open_menu() -> bool:
	if get_tree().paused or epilogue_screen.is_open or inner_voice_ui.is_open:
		return false
	var scene_manager = get_parent()
	var opening = scene_manager.opening if scene_manager and "opening" in scene_manager else null
	if opening and opening.has_method("is_card_open") and opening.is_card_open():
		return false
	for urn in get_tree().get_nodes_in_group("story_items"):
		if urn.has_method("is_choosing") and urn.is_choosing():
			return false
	return true

func is_menu_open() -> bool:
	return _menu_layer.visible

func open_menu() -> void:
	_menu_layer.visible = true
	_menu.visible = true
	_confirm.visible = false
	get_tree().paused = true

func close_menu() -> void:
	_menu_layer.visible = false
	get_tree().paused = false

## "End my story here": ask first
func request_end_story() -> void:
	_menu_layer.visible = true
	_menu.visible = false
	_confirm.visible = true
	get_tree().paused = true

func cancel_end_story() -> void:
	_confirm.visible = false
	_menu.visible = true

## Confirmed: the epilogue, generated from the world as it stands
func confirm_end_story() -> void:
	_menu_layer.visible = false
	end_story("player")

## Show the epilogue. reason: "player" (the menu) | "season_end" | "debug"
func end_story(reason: String = "player", given: Dictionary = {}) -> void:
	story_over = true
	if inner_voice_ui.is_open:
		inner_voice_ui.close()
	get_tree().paused = false  # the epilogue screen pauses again, remembering an unpaused world
	epilogue_screen.show_epilogue(given)
	story_ended.emit(reason)
	print("[PlayerUI] The story ends (%s)" % reason)

func _end_when_free(reason: String) -> void:
	while is_inside_tree() and _in_conversation():
		await get_tree().create_timer(0.5, true, false, true).timeout
	if is_inside_tree() and not epilogue_screen.is_open:
		end_story(reason)

func _in_conversation() -> bool:
	var dialogue = get_node_or_null("/root/DialogueManager")
	return dialogue != null and "active_conversations" in dialogue and not dialogue.active_conversations.is_empty()

func _build_menu() -> void:
	_menu_layer = CanvasLayer.new()
	_menu_layer.name = "GameMenu"
	_menu_layer.layer = 55
	_menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_layer.visible = false
	add_child(_menu_layer)
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(shade)
	_menu = _panel("Paused", "", [["Resume", close_menu], ["End my story here", request_end_story]])
	_menu.name = "MenuPanel"
	_menu_layer.add_child(_menu)
	_confirm = _panel("End your story here?",
		"The world will be told as it stands now: the people you touched, the places you changed, and what you meant set against what you did.",
		[["Not yet", cancel_end_story], ["End my story", confirm_end_story]])
	_confirm.name = "ConfirmPanel"
	_confirm.visible = false
	_menu_layer.add_child(_confirm)

## A centred panel in the travel map's palette: a gold title, optional text, a row of buttons
func _panel(title_text: String, body: String, buttons: Array) -> Control:
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08, 0.96)
	style.border_color = Color(0.55, 0.42, 0.22, 1)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	var title = Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25, 1))
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	if body != "":
		var text = Label.new()
		text.text = body
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(420, 0)
		text.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6, 1))
		text.add_theme_font_size_override("font_size", 15)
		vbox.add_child(text)
	var row = VBoxContainer.new() if body == "" else HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if row is HBoxContainer:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	for spec in buttons:
		var button = Button.new()
		button.text = spec[0]
		button.custom_minimum_size = Vector2(200, 34)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(spec[1])
		row.add_child(button)
	return center
