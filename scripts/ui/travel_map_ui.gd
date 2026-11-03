extends CanvasLayer
## TravelMapUI - Road list, route detail and arrival card for the TravelMap autoload.
## Instanced once by TravelMap (scenes/ui/travel_map.tscn) and kept across scene changes.

signal destination_chosen(dest: String, mode: String)
signal close_requested()

const MODE_ORDER := ["mixed", "horse", "foot", "cart", "barge"]
const CARD_FADE := 0.6
const CARD_HOLD := 3.0

@onready var map_root: Control = $MapRoot
@onready var title_label: Label = $MapRoot/Panel/Margin/VBox/Header/TitleLabel
@onready var close_button: Button = $MapRoot/Panel/Margin/VBox/Header/CloseButton
@onready var subtitle_label: Label = $MapRoot/Panel/Margin/VBox/Subtitle
@onready var destination_list: ItemList = $MapRoot/Panel/Margin/VBox/Body/DestinationList
@onready var empty_label: Label = $MapRoot/Panel/Margin/VBox/Body/Detail/EmptyLabel
@onready var dest_name_label: Label = $MapRoot/Panel/Margin/VBox/Body/Detail/DestName
@onready var legs_text: RichTextLabel = $MapRoot/Panel/Margin/VBox/Body/Detail/LegsText
@onready var mode_buttons: VBoxContainer = $MapRoot/Panel/Margin/VBox/Body/Detail/ModeButtons
@onready var arrival_card: Control = $ArrivalCard
@onready var card_text: Label = $ArrivalCard/CardText
@onready var card_hint: Label = $ArrivalCard/CardHint

var _routes: Array = []
var _names: Dictionary = {}
var _card_waiting: bool = false
var _card_token: int = 0

signal _card_dismissed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	map_root.visible = false
	arrival_card.visible = false
	destination_list.item_selected.connect(_on_destination_selected)
	destination_list.item_activated.connect(_on_destination_activated)
	close_button.pressed.connect(func(): close_requested.emit())


func _input(event: InputEvent) -> void:
	if map_root.visible:
		if event.is_action_pressed("ui_cancel"):
			close_requested.emit()
			get_viewport().set_input_as_handled()
		return
	if _card_waiting and _is_press(event):
		_card_dismissed.emit()
		get_viewport().set_input_as_handled()


static func _is_press(event: InputEvent) -> bool:
	if event is InputEventKey or event is InputEventJoypadButton:
		return event.is_pressed() and not event.is_echo()
	if event is InputEventMouseButton:
		return event.is_pressed()
	return false


# --------------------------------------------------------------------------
# Map
# --------------------------------------------------------------------------

## routes: TravelMap.plan_routes() output.
func show_routes(from_location: String, from_name: String, routes: Array) -> void:
	_routes = routes
	_names = {from_location: from_name}
	for route in routes:
		_names[route["dest"]] = route["name"]
		for leg in route["legs"]:
			_names[leg["from"]] = TravelMap.location_name(leg["from"])
			_names[leg["to"]] = TravelMap.location_name(leg["to"])

	title_label.text = "The Road from %s" % from_name
	subtitle_label.text = "Where will you go? Every road costs time." if not routes.is_empty() else ""
	destination_list.clear()
	for route in routes:
		destination_list.add_item("%s   (%s)" % [route["name"], TravelMap.format_duration(route["fastest_minutes"])])

	var has_routes := not routes.is_empty()
	destination_list.visible = has_routes
	empty_label.visible = not has_routes
	dest_name_label.visible = has_routes
	legs_text.visible = has_routes
	mode_buttons.visible = has_routes
	_clear_mode_buttons()

	map_root.visible = true
	if has_routes:
		destination_list.select(0)
		_on_destination_selected(0)
		destination_list.grab_focus()
	else:
		close_button.grab_focus()


func hide_map() -> void:
	map_root.visible = false
	_clear_mode_buttons()


func _on_destination_selected(index: int) -> void:
	if index < 0 or index >= _routes.size():
		return
	var route: Dictionary = _routes[index]
	dest_name_label.text = route["name"]

	var lines: Array = []
	for leg in route["legs"]:
		lines.append("• %s → %s  [color=#a0a0a0](%s, %s)[/color]" % [
			_names.get(leg["from"], leg["from"]),
			_names.get(leg["to"], leg["to"]),
			TravelMap.format_duration(leg["travel_minutes"]),
			leg["mode"],
		])
	legs_text.clear()
	legs_text.append_text("[b]Route[/b]\n" + "\n".join(lines))

	_clear_mode_buttons()
	for mode in MODE_ORDER:
		var minutes := -1
		if mode == TravelMap.MIXED:
			if not route["mixed"].is_empty():
				minutes = route["mixed"]["minutes"]
		elif route["minutes_by_mode"].has(mode):
			minutes = route["minutes_by_mode"][mode]
		if minutes < 0:
			continue
		var button := Button.new()
		button.text = "%s  —  %s" % [TravelMap.MODE_LABELS.get(mode, mode), TravelMap.format_duration(minutes)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 16)
		var dest: String = route["dest"]
		var chosen_mode: String = mode
		button.pressed.connect(func(): destination_chosen.emit(dest, chosen_mode))
		mode_buttons.add_child(button)


func _on_destination_activated(index: int) -> void:
	if index < 0 or index >= _routes.size():
		return
	var route: Dictionary = _routes[index]
	destination_chosen.emit(route["dest"], route["fastest_mode"])


func _clear_mode_buttons() -> void:
	for child in mode_buttons.get_children():
		mode_buttons.remove_child(child)
		child.queue_free()


# --------------------------------------------------------------------------
# Arrival card
# --------------------------------------------------------------------------

## Cover the screen with the departure line while the scene changes underneath.
func begin_arrival_card(departure_line: String) -> void:
	card_text.text = departure_line
	card_hint.visible = false
	arrival_card.modulate.a = 0.0
	arrival_card.visible = true
	var tween := create_tween()
	tween.tween_property(arrival_card, "modulate:a", 1.0, 0.25)


## Add the arrival line, hold (gameplay paused, any key skips), then fade out.
func finish_arrival_card(arrival_line: String) -> void:
	card_text.text = "%s\n%s" % [card_text.text, arrival_line]
	card_hint.visible = true
	arrival_card.modulate.a = 1.0

	var tree := get_tree()
	var was_paused := tree.paused
	tree.paused = true
	_card_token += 1
	var token := _card_token
	_card_waiting = true
	var timer := tree.create_timer(CARD_HOLD, true)
	timer.timeout.connect(func():
		if _card_waiting and token == _card_token:
			_card_dismissed.emit())
	await _card_dismissed
	_card_waiting = false

	var tween := create_tween()
	tween.tween_property(arrival_card, "modulate:a", 0.0, CARD_FADE)
	await tween.finished
	arrival_card.visible = false
	tree.paused = was_paused
