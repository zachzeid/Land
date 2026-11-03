extends Node
## PlayerUI - The player's own persistent UI: their thoughts, the menu and the epilogue
## Instanced once beside the opening under SceneManager (scenes/ui/player_ui.tscn), so it outlives
## every scene change
## - InnerVoiceUI (scenes/ui/inner_voice_ui.tscn): the inner_voice action (T), WORLD_SCHEMA §13
## - The menu: Esc when nothing else is open pauses and offers Resume or "End my story here"; ending
##   asks for confirmation, then shows the epilogue
## - EpilogueScreen (scenes/ui/epilogue_screen.tscn): WORLD_SCHEMA §15, also shown by itself when the
##   season_end fixed point fires
## - The player systems (docs/PLAYER_SYSTEMS.md §8 "UI"): the HUD (health, stamina, level, hit
##   feedback), the inventory panel (I) with the skills page beside it, the crafting panel (B, at a
##   station), the puzzle answer card and the difficulty choice at a new game. Every panel pauses the
##   world like the menu and closes with Esc. They talk to the autoloads through the contract calls
##   only (docs/PLAYER_SYSTEMS_BUILD.md), so they work with the Phase 0 stubs and the real systems

signal story_ended(reason: String)

const SEASON_END = "season_end"
## How close the player must stand to a crafting station for B to open it (px)
const STATION_REACH = 96.0

## Pennies to the mark and marks to the crown: the old reckoning (12 pence a shilling, 20 a pound).
## Canon names the coins but not the rates; Inventory's own constants win once it declares them
const PENNIES_PER_MARK = 12
const MARKS_PER_CROWN = 20

var inner_voice_ui: CanvasLayer
var epilogue_screen: CanvasLayer
var story_over: bool = false
var _menu_layer: CanvasLayer
var _menu: Control
var _confirm: Control
var hud: CanvasLayer
var inventory_panel: CanvasLayer
var crafting_panel: CanvasLayer
var puzzle_card: CanvasLayer
var difficulty_choice: CanvasLayer
## Ask normal or hard when a new game's opening starts. Off headless: nobody is there to answer, and
## a modal choice would hold an unattended world paused (tests turn it on to check the hook)
var ask_difficulty: bool = DisplayServer.get_name() != "headless"
var _difficulty_asked: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("player_ui")
	inner_voice_ui = load("res://scenes/ui/inner_voice_ui.tscn").instantiate()
	add_child(inner_voice_ui)
	epilogue_screen = load("res://scenes/ui/epilogue_screen.tscn").instantiate()
	add_child(epilogue_screen)
	epilogue_screen.quit_requested.connect(func(): get_tree().quit())
	_build_menu()
	_build_player_systems()
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
	if event.is_action_pressed("inventory") and not event.is_echo():
		if can_open_menu():
			get_viewport().set_input_as_handled()
			open_inventory()
		return
	if event.is_action_pressed("craft") and not event.is_echo():
		if can_open_menu():
			get_viewport().set_input_as_handled()
			var station = find_station()
			if station == "":
				hud.show_note("There is nothing to work with here.")
			else:
				open_crafting(station)
		return
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
	if story_over or get_tree().paused or epilogue_screen.is_open or inner_voice_ui.is_open or is_panel_open():
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
	close_panels()
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

# =============================================================================
# THE PLAYER SYSTEMS (docs/PLAYER_SYSTEMS.md §8 "UI")
# =============================================================================

func _build_player_systems() -> void:
	hud = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	inventory_panel = load("res://scenes/ui/inventory_panel.tscn").instantiate()
	add_child(inventory_panel)
	crafting_panel = load("res://scenes/ui/crafting_panel.tscn").instantiate()
	add_child(crafting_panel)
	puzzle_card = load("res://scenes/ui/puzzle_card.tscn").instantiate()
	add_child(puzzle_card)
	difficulty_choice = load("res://scenes/ui/difficulty_choice.tscn").instantiate()
	add_child(difficulty_choice)
	var opening = _opening()
	if opening and opening.has_signal("opening_started"):
		opening.opening_started.connect(_on_opening_started)
		# PlayerUI arrives a frame after the opening: catch a play() that began before it
		if "playing" in opening and opening.playing and opening.phase == "establishing":
			_on_opening_started.call_deferred()

func _process(_delta: float) -> void:
	if hud:
		hud.visible = not (story_over or epilogue_screen.is_open or _opening_card_open())

func is_panel_open() -> bool:
	for panel in [inventory_panel, crafting_panel, puzzle_card, difficulty_choice]:
		if panel and panel.is_open:
			return true
	return false

func close_panels() -> void:
	for panel in [inventory_panel, crafting_panel, puzzle_card, difficulty_choice]:
		if panel and panel.is_open:
			panel.close()

func open_inventory() -> bool:
	if not can_open_menu():
		return false
	inventory_panel.open()
	return true

## A station calls this when the player uses it (or B finds one in reach)
func open_crafting(station_id: String) -> bool:
	if station_id == "" or not can_open_menu():
		return false
	crafting_panel.open(station_id)
	return true

## An examinable puzzle object calls this; the card answers through Puzzles.answer
func open_puzzle(puzzle_id: String) -> bool:
	if story_over or epilogue_screen.is_open or is_panel_open():
		return false
	puzzle_card.open(puzzle_id)
	return true

## The station the player stands at: Crafting's own answer when it gives one, else the nearest node
## in the crafting_stations group (station.gd) within reach of the player
func find_station() -> String:
	var crafting = get_node_or_null("/root/Crafting")
	if crafting and crafting.has_method("get_current_station"):
		return str(crafting.get_current_station())
	var player = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return ""
	var best = ""
	var best_distance = STATION_REACH
	for station in get_tree().get_nodes_in_group("crafting_stations"):
		if not (station is Node2D) or not "station_id" in station:
			continue
		var distance = (station as Node2D).global_position.distance_to(player.global_position)
		if distance <= best_distance:
			best = str(station.station_id)
			best_distance = distance
	return best

func _on_opening_started() -> void:
	if not ask_difficulty or _difficulty_asked or story_over:
		return
	var world_state = get_node_or_null("/root/WorldState")
	if world_state and world_state.has_method("is_new_game") and not world_state.is_new_game():
		return
	_difficulty_asked = true
	difficulty_choice.open()

func _opening() -> Node:
	var scene_manager = get_parent()
	return scene_manager.opening if scene_manager and "opening" in scene_manager else null

func _opening_card_open() -> bool:
	var opening = _opening()
	return opening != null and opening.has_method("is_card_open") and opening.is_card_open()

## Coin as the valley counts it: "2 crowns, 3 marks, 5 pennies" (pennies held internally)
static func format_coin(pennies: int) -> String:
	var per_mark = PENNIES_PER_MARK
	var per_crown = MARKS_PER_CROWN
	var inventory = autoload("Inventory")
	if inventory and "PENNIES_PER_MARK" in inventory:
		per_mark = int(inventory.PENNIES_PER_MARK)
	if inventory and "MARKS_PER_CROWN" in inventory:
		per_crown = int(inventory.MARKS_PER_CROWN)
	var neg = "-" if pennies < 0 else ""
	pennies = absi(pennies)
	var crowns = pennies / (per_mark * per_crown)
	var marks = (pennies / per_mark) % per_crown
	var pence = pennies % per_mark
	var parts: Array = []
	if crowns > 0:
		parts.append("%d crown%s" % [crowns, "" if crowns == 1 else "s"])
	if marks > 0:
		parts.append("%d mark%s" % [marks, "" if marks == 1 else "s"])
	if pence > 0 or parts.is_empty():
		parts.append("%d penn%s" % [pence, "y" if pence == 1 else "ies"])
	return neg + ", ".join(parts)

# =============================================================================
# STYLE (shared by the panels: the travel map's palette)
# =============================================================================

const GOLD = Color(0.94, 0.75, 0.25, 1)
const PARCHMENT = Color(0.75, 0.7, 0.6, 1)
const FAINT = Color(0.55, 0.52, 0.46, 1)
const WARN = Color(0.85, 0.4, 0.3, 1)

static func frame_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08, 0.96)
	style.border_color = Color(0.55, 0.42, 0.22, 1)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	return style

static func label(text: String, size: int = 15, color: Color = PARCHMENT) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l

static func button(text: String, action: Callable, width: float = 120) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 30)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(action)
	return b

## A full-screen shade with a centred frame; returns [center, vbox] for the panel to fill
static func centred_frame(layer_node: CanvasLayer, min_size: Vector2) -> Array:
	var shade = ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer_node.add_child(shade)
	var center = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer_node.add_child(center)
	var panel = PanelContainer.new()
	panel.name = "Frame"
	panel.custom_minimum_size = min_size
	panel.add_theme_stylebox_override("panel", frame_style())
	center.add_child(panel)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	return [center, vbox]

## Remove every child now (the panels rebuild their lists on refresh)
static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

## A JSON file's content, or null (content files belong to other slices and may not exist yet)
static func read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## Records out of a JSON content file in any of the shapes the slices use: an Array, {key: [...]},
## or {id: {...}} (the id filled in from the key)
static func records(data, key: String = "") -> Array:
	if data is Array:
		return data.filter(func(r): return r is Dictionary)
	if not data is Dictionary:
		return []
	if key != "" and data.get(key) != null:
		return records(data[key])
	var out: Array = []
	for id in data:
		if data[id] is Dictionary:
			var r: Dictionary = data[id].duplicate()
			if not r.has("id"):
				r["id"] = id
			out.append(r)
	return out

static var _item_defs: Dictionary = {}

## An autoload by name, safe from a node that is not in the tree yet
static func autoload(autoload_name: String) -> Node:
	var tree = Engine.get_main_loop()
	return tree.root.get_node_or_null(autoload_name) if tree is SceneTree else null

## An item's definition (resources/items/*.json): Inventory's own lookup when it has one
static func item_def(item_id: String, inventory: Node = null) -> Dictionary:
	if inventory == null:
		inventory = autoload("Inventory")
	for method in ["get_item_def", "get_def", "item_def"]:
		if inventory and inventory.has_method(method):
			var d = inventory.call(method, item_id)
			if d is Dictionary and not d.is_empty():
				return d
	if _item_defs.is_empty():
		var dir = DirAccess.open("res://resources/items")
		if dir:
			for file in dir.get_files():
				if file.ends_with(".json"):
					for r in records(read_json("res://resources/items/" + file), "items"):
						_item_defs[str(r.get("id", ""))] = r
		_item_defs["__loaded"] = {}
	return _item_defs.get(item_id, {})

static func item_name(item_id: String, inventory: Node = null) -> String:
	var d = item_def(item_id, inventory)
	return str(d.get("name", item_id.replace("_", " ").capitalize()))

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
