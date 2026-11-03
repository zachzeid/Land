extends CanvasLayer
## DifficultyChoice - normal or hard, asked once at a new game (docs/PLAYER_SYSTEMS.md §2, §10.2)
## PlayerUI opens it when the opening starts (OpeningSequence.opening_started), before the chapel
## card, so the choice is made before the story begins. It sits above the opening card and pauses the
## world; the card waits beneath it and plays as before once the choice is made. Esc keeps normal
## The choice sets PlayerStats.difficulty, which PlayerStats saves; it is not offered again

signal chosen(difficulty: String)

const UI = preload("res://scripts/ui/player_ui.gd")
const NORMAL_TEXT = "Each death costs you a little of every skill: one part in a hundred the first time, one more part each time after, never more than a quarter. Everything you carry stays where you fell, for whoever finds it."
const HARD_TEXT = "Each death costs twice what the last one did: one part in a hundred, then two, four, eight, up to half of every skill. Everything you carry stays where you fell, for whoever finds it."

## Injectable for tests; the PlayerStats autoload otherwise
var stats: Node = null
var is_open: bool = false
var choice: String = ""
var _was_paused: bool = false

func _ready() -> void:
	layer = 110   # above the opening card (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()

func _build() -> void:
	var parts = UI.centred_frame(self, Vector2(640, 0))
	var vbox: VBoxContainer = parts[1]
	var title = UI.label("How hard is the valley on you?", 24, UI.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	vbox.add_child(row)
	row.add_child(_column("Normal", NORMAL_TEXT, "normal"))
	row.add_child(_column("Hard", HARD_TEXT, "hard"))
	var note = UI.label("Chosen once, for this whole story. Esc keeps Normal.", 12, UI.FAINT)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(note)

func _column(heading: String, text: String, value: String) -> VBoxContainer:
	var col = VBoxContainer.new()
	col.name = heading
	col.add_theme_constant_override("separation", 8)
	col.add_child(UI.label(heading, 18, UI.GOLD))
	var body = UI.label(text, 14)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(290, 0)
	col.add_child(body)
	col.add_child(UI.button(heading, choose.bind(value), 200))
	return col

func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		choose("normal")

func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = _was_paused

func choose(value: String) -> void:
	choice = "hard" if value == "hard" else "normal"
	var s = stats if stats else UI.autoload("PlayerStats")
	if s and s.has_method("set_difficulty"):
		s.set_difficulty(choice)
	elif s and "difficulty" in s:
		s.difficulty = choice
	close()
	chosen.emit(choice)
	print("[DifficultyChoice] %s" % choice)
