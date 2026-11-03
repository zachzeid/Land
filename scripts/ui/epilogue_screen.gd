extends CanvasLayer
## EpilogueScreen - The world the player made, told when their story ends (docs/WORLD_SCHEMA.md §15)
## Full screen and scrollable, in the travel map's palette. It reads Epilogue.generate() (director
## engine) and lays out its sections in order: the people, the places, the fixed points that moved,
## the named highlights, and what the player meant set against what they did. Unknown keys still show,
## under their own name. PlayerUI opens it from the menu ("End my story here") and at season_end
## The structure it accepts, loosely (every key optional):
##   {title, subtitle|summary, people: [..], places: [..], fixed_points|moved_fixed_points: [..],
##    highlights: [..], intentions|intentions_vs_deeds: [..], closing}
## where each item is a String, or a Dictionary with a name (name/title/npc/place/point/goal/label)
## and a body (text/passage/prose/summary/description), plus short facts shown beneath it

signal closed
signal quit_requested

const SECTIONS = [
	{"id": "people", "title": "The people", "keys": ["people", "npcs", "persons"]},
	{"id": "places", "title": "The places", "keys": ["places", "settlements", "regions"]},
	{"id": "fixed_points", "title": "What moved", "keys": ["fixed_points", "moved_fixed_points", "fixed_points_moved", "moved_points"]},
	{"id": "highlights", "title": "Remembered", "keys": ["highlights", "endings"]},
	{"id": "intentions", "title": "What you meant, and what you did", "keys": ["intentions", "intentions_vs_deeds", "intentions_and_deeds", "deeds"]},
]
const META_KEYS = ["title", "subtitle", "summary", "opening", "closing", "generated_at", "mode", "version", "facts"]
const NAME_KEYS = ["name", "title", "npc", "place", "settlement", "region", "point", "goal", "label", "id"]
const BODY_KEYS = ["text", "passage", "prose", "summary", "description", "body"]
const FACT_KEYS = ["state", "ending", "outcome", "verdict", "status", "reason", "reputation", "deeds", "result"]

const COLOR_BG = Color(0.06, 0.05, 0.04, 0.97)
const COLOR_TITLE = Color(0.94, 0.75, 0.25, 1)
const COLOR_HEADING = Color(0.94, 0.75, 0.25, 0.9)
const COLOR_TEXT = Color(0.86, 0.82, 0.74, 1)
const COLOR_MUTED = Color(0.62, 0.58, 0.5, 1)
const COLOR_RULE = Color(0.55, 0.42, 0.22, 0.6)

## Injectable for tests; else the Epilogue autoload (or the director's epilogue) is asked
var source: Object = null
var is_open: bool = false
var sections_built: Array = []      # section ids in the order shown (tests)
var data: Dictionary = {}
var _root: Control
var _content: VBoxContainer
var _scroll: ScrollContainer
var _was_paused: bool = false
var _plain: PackedStringArray = []

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("epilogue_screen")
	_build()
	_root.visible = false

func _build() -> void:
	_root = Control.new()
	_root.name = "EpilogueRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg = ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var outer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_top = 32
	outer.offset_bottom = -24
	_root.add_child(outer)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.custom_minimum_size = Vector2(820, 0)
	_content.add_theme_constant_override("separation", 10)
	center.add_child(_content)
	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	outer.add_child(buttons)
	var close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.add_theme_font_size_override("font_size", 16)
	close_button.pressed.connect(close)
	buttons.add_child(close_button)
	var quit_button = Button.new()
	quit_button.name = "QuitButton"
	quit_button.text = "Quit"
	quit_button.add_theme_font_size_override("font_size", 16)
	quit_button.pressed.connect(func(): quit_requested.emit())
	buttons.add_child(quit_button)

func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

## Show the epilogue. given: an already generated epilogue (else Epilogue.generate() is asked)
func show_epilogue(given: Dictionary = {}) -> bool:
	data = given if not given.is_empty() else generate()
	build(data)
	_was_paused = get_tree().paused
	get_tree().paused = true
	is_open = true
	_root.visible = true
	_scroll.scroll_vertical = 0
	return not data.is_empty()

func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	get_tree().paused = _was_paused
	closed.emit()

## Ask the director engine for the epilogue ({} when it is not in yet)
func generate() -> Dictionary:
	var target = _source()
	if target == null:
		return {}
	var result = null
	if target.has_method("generate"):
		result = target.generate()
	elif target.has_method("generate_epilogue"):
		result = target.generate_epilogue()
	return result if result is Dictionary else {}

func _source() -> Object:
	if source:
		return source
	var epilogue = get_node_or_null("/root/Epilogue")
	if epilogue:
		return epilogue
	var director = get_node_or_null("/root/StorylineDirector")
	if director:
		if "epilogue" in director and director.epilogue is Object:
			return director.epilogue
		if director.has_method("generate_epilogue"):
			return director
	return null

## Lay out an epilogue dictionary (callable without showing it: tests)
func build(epilogue: Dictionary) -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	sections_built = []
	_plain = PackedStringArray()
	_add_label(str(epilogue.get("title", "How the story ended")), 30, COLOR_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	var subtitle = str(epilogue.get("subtitle", epilogue.get("summary", epilogue.get("opening", ""))))
	if subtitle == "":
		var world_state = get_node_or_null("/root/WorldState")
		subtitle = "The Western Valley, %s" % world_state.get_time_string() if world_state else ""
	if subtitle != "":
		_add_text(subtitle, 15, COLOR_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	if epilogue.is_empty():
		_add_rule()
		_add_text("The world has not been written down yet: the chronicle that tells it is still being built. Your story is not over.", 16, COLOR_TEXT)
		return
	var used: Dictionary = {}
	for section in SECTIONS:
		for key in section.keys:
			if epilogue.has(key) and not _is_empty(epilogue[key]):
				_add_section(section.title, epilogue[key])
				sections_built.append(section.id)
				used[key] = true
				break
		for key in section.keys:
			used[key] = true
	for key in epilogue:
		if used.has(key) or key in META_KEYS or _is_empty(epilogue[key]):
			continue
		if epilogue[key] is Array or epilogue[key] is Dictionary or epilogue[key] is String:
			_add_section(str(key).replace("_", " ").capitalize(), epilogue[key])
			sections_built.append(str(key))
	var closing = str(epilogue.get("closing", ""))
	if closing != "":
		_add_rule()
		_add_text(closing, 16, COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER)

## Every word on the page, plain (tests)
func get_text() -> String:
	return "\n".join(_plain)

func _add_section(title: String, value) -> void:
	_add_rule()
	_add_label(title, 22, COLOR_HEADING)
	if value is String:
		_add_text(value, 16, COLOR_TEXT)
	elif value is Array:
		for item in value:
			_add_item(item)
	elif value is Dictionary:
		for key in value:
			var item = value[key]
			if item is Dictionary:
				var named = item.duplicate()
				if not NAME_KEYS.any(func(k): return named.has(k)):
					named["name"] = str(key)
				_add_item(named)
			else:
				_add_item({"name": str(key).replace("_", " ").capitalize(), "text": str(item)})

func _add_item(item) -> void:
	if item is String:
		_add_text(item, 16, COLOR_TEXT)
		return
	if not item is Dictionary:
		_add_text(str(item), 16, COLOR_TEXT)
		return
	var name = ""
	for key in NAME_KEYS:
		if item.has(key) and str(item[key]) != "":
			name = str(item[key])
			break
	if name != "":
		_add_label(name, 17, COLOR_TITLE)
	for key in BODY_KEYS:
		if item.has(key) and str(item[key]) != "" and str(item[key]) != name:
			_add_text(str(item[key]), 16, COLOR_TEXT)
			break
	for key in FACT_KEYS:
		if item.has(key) and not _is_empty(item[key]) and not (key in BODY_KEYS):
			var value = item[key]
			var shown = ", ".join(value.map(func(v): return str(v))) if value is Array else str(value)
			_add_text("%s: %s" % [key.capitalize(), shown], 13, COLOR_MUTED)

func _add_label(text: String, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_content.add_child(label)
	_plain.append(text)

func _add_text(text: String, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var rich = RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.custom_minimum_size = Vector2(820, 0)
	rich.add_theme_font_size_override("normal_font_size", size)
	rich.add_theme_font_size_override("italics_font_size", size)
	rich.add_theme_font_size_override("bold_font_size", size)
	rich.add_theme_color_override("default_color", color)
	rich.text = ("[center]%s[/center]" % text) if align == HORIZONTAL_ALIGNMENT_CENTER else text
	_content.add_child(rich)
	_plain.append(text)

func _add_rule() -> void:
	var rule = ColorRect.new()
	rule.color = COLOR_RULE
	rule.custom_minimum_size = Vector2(820, 1)
	_content.add_child(rule)

func _is_empty(value) -> bool:
	if value == null:
		return true
	if value is Array or value is Dictionary or value is String:
		return value.is_empty()
	return false
