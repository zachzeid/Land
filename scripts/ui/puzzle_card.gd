extends CanvasLayer
## PuzzleCard - the player gives their answer to a lore or evidence puzzle (docs/PLAYER_SYSTEMS.md §5.2)
## Opened by PlayerUI.open_puzzle(puzzle_id), from whatever the player examines. The game checks the
## answer; the player does the reasoning. Four shapes, read from the puzzle (Puzzles.get_puzzle):
## - choose: pick one of the options (which tile is light)
## - arrange: put the options in order (the tally notches against the barge dates)
## - name: write a name (whose hand cut the tile)
## - decode: read a cipher and write what it says (Gregor's ledger)
## Answer sends it to Puzzles.answer(puzzle_id, answer): choose gives the option id, arrange an Array
## of option ids in order, name and decode the text. A wrong answer keeps the card open; Esc leaves it.
## It pauses the world like the menu

signal answered(puzzle_id: String, result: Dictionary)

const UI = preload("res://scripts/ui/player_ui.gd")
const SHAPES = ["choose", "arrange", "name", "decode"]

## Injectable for tests; the Puzzles autoload otherwise
var puzzles: Node = null
var is_open: bool = false
var puzzle_id: String = ""
var puzzle: Dictionary = {}
var shape: String = "name"
var choice: String = ""      # choose
var order: Array = []        # arrange: option ids, top first
var last_result: Dictionary = {}
var _was_paused: bool = false
var _title: Label
var _prompt: Label
var _cipher: Label
var _body: VBoxContainer
var _field: LineEdit
var _message: Label

func _ready() -> void:
	layer = 52
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()

func _build() -> void:
	var parts = UI.centred_frame(self, Vector2(560, 0))
	var vbox: VBoxContainer = parts[1]
	_title = UI.label("", 22, UI.GOLD)
	vbox.add_child(_title)
	_prompt = UI.label("", 15)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size = Vector2(510, 0)
	vbox.add_child(_prompt)
	_cipher = UI.label("", 16, UI.GOLD)
	_cipher.name = "Cipher"
	_cipher.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cipher.custom_minimum_size = Vector2(510, 0)
	vbox.add_child(_cipher)
	_body = VBoxContainer.new()
	_body.name = "Answer"
	_body.add_theme_constant_override("separation", 6)
	vbox.add_child(_body)
	_message = UI.label("", 14, UI.WARN)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(510, 0)
	vbox.add_child(_message)
	var bottom = HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(UI.label("Esc to leave it   ", 12, UI.FAINT))
	bottom.add_child(UI.button("Not now", close))
	bottom.add_child(UI.button("Answer", submit))
	vbox.add_child(bottom)

func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func open(id: String) -> bool:
	var p = _puzzles()
	puzzle_id = id
	puzzle = p.get_puzzle(id) if p else {}
	if not puzzle is Dictionary:
		puzzle = {}
	shape = shape_of(puzzle)
	choice = ""
	order = options().map(func(o): return o.id)
	last_result = {}
	_message.text = ""
	_title.text = str(puzzle.get("title", puzzle.get("name", "A question")))
	_prompt.text = str(puzzle.get("prompt", puzzle.get("question", puzzle.get("text", "What do you make of it?"))))
	var cipher = str(puzzle.get("cipher", puzzle.get("encoded", ""))) if shape == "decode" else ""
	_cipher.text = cipher
	_cipher.visible = cipher != ""
	_build_answer()
	if not is_open:
		is_open = true
		visible = true
		_was_paused = get_tree().paused
		get_tree().paused = true
	if _field and shape in ["name", "decode"]:
		_focus_field.call_deferred()
	return not puzzle.is_empty()

func _focus_field() -> void:
	if is_open and is_instance_valid(_field) and _field.is_inside_tree():
		_field.grab_focus()

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	if _field and _field.has_focus():
		_field.release_focus()
	get_tree().paused = _was_paused

## The answer shape: the puzzle's answer_kind / shape / answer.kind, else choose when it has options
static func shape_of(p: Dictionary) -> String:
	var answer = p.get("answer", null)
	for value in [p.get("answer_kind", ""), p.get("shape", ""), answer.get("kind", "") if answer is Dictionary else "", p.get("kind", "")]:
		if str(value) in SHAPES:
			return str(value)
	return "choose" if not p.get("options", p.get("choices", [])).is_empty() else "name"

## [{id, label}] from options given as strings or {id, label|text|name}
func options() -> Array:
	var raw = puzzle.get("options", puzzle.get("choices", puzzle.get("pieces", [])))
	var out: Array = []
	var list: Array = raw if raw is Array else []
	for o in list:
		if o is Dictionary:
			var id = str(o.get("id", o.get("label", o.get("text", ""))))
			out.append({"id": id, "label": str(o.get("label", o.get("text", o.get("name", id))))})
		else:
			out.append({"id": str(o), "label": str(o)})
	return out

func _build_answer() -> void:
	UI.clear(_body)
	_field = null
	match shape:
		"choose":
			var group = ButtonGroup.new()
			for o in options():
				var b = CheckBox.new()
				b.name = "Option_" + o.id
				b.text = o.label
				b.button_group = group
				b.button_pressed = o.id == choice
				b.add_theme_font_size_override("font_size", 15)
				b.pressed.connect(choose.bind(o.id))
				_body.add_child(b)
		"arrange":
			_body.add_child(UI.label("Put them in order, first at the top.", 13, UI.FAINT))
			var labels = {}
			for o in options():
				labels[o.id] = o.label
			for i in order.size():
				var row = HBoxContainer.new()
				row.name = "Place_%d" % i
				var l = UI.label("%d.  %s" % [i + 1, labels.get(order[i], order[i])], 15)
				l.custom_minimum_size = Vector2(380, 0)
				row.add_child(l)
				var up = UI.button("Up", move.bind(i, -1), 54)
				up.disabled = i == 0
				row.add_child(up)
				var down = UI.button("Down", move.bind(i, 1), 54)
				down.disabled = i == order.size() - 1
				row.add_child(down)
				_body.add_child(row)
		_:
			_field = LineEdit.new()
			_field.name = "AnswerInput"
			_field.placeholder_text = "Who?" if shape == "name" else "What does it say?"
			_field.custom_minimum_size = Vector2(500, 0)
			_field.add_theme_font_size_override("font_size", 15)
			_field.text_submitted.connect(func(_t): submit())
			_body.add_child(_field)

func choose(option_id: String) -> void:
	choice = option_id

## Arrange: move the piece at index one place up (-1) or down (+1)
func move(index: int, step: int) -> void:
	var to = index + step
	if index < 0 or to < 0 or index >= order.size() or to >= order.size():
		return
	var piece = order[index]
	order[index] = order[to]
	order[to] = piece
	_build_answer()

## Typed answers (name, decode); also used by tests
func set_text(text: String) -> void:
	if _field:
		_field.text = text

func current_answer():
	match shape:
		"choose":
			return choice
		"arrange":
			return order.duplicate()
		_:
			return _field.text.strip_edges() if _field else ""

func submit() -> Dictionary:
	var answer = current_answer()
	if (answer is String and answer == ""):
		_message.text = "Choose first." if shape == "choose" else "Write your answer first."
		return {"ok": false, "flag": "", "reason": "no answer"}
	var p = _puzzles()
	var result: Dictionary = p.answer(puzzle_id, answer) if p else {"ok": false, "flag": "", "reason": ""}
	last_result = result
	answered.emit(puzzle_id, result)
	if result.get("ok", false):
		close()
		var hud = get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
		if hud and hud.has_method("show_note"):
			hud.show_note(str(result.get("text", "It fits. You are sure of it now.")))
	else:
		var reason = str(result.get("reason", ""))
		_message.text = reason if reason != "" else "It does not fit."
	return result

func get_message() -> String:
	return _message.text

func _puzzles() -> Node:
	return puzzles if puzzles else UI.autoload("Puzzles")
