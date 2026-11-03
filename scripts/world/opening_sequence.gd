extends Node
class_name OpeningSequence
## OpeningSequence - The Tithe Night's first scene (docs/STORY_NARRATIVE.md, "The seven days")
## On a new game (no save file) the player starts in the Chapel of the Dawn on day 1, 20:00, as
## Elder Mathias reads Elena's name. SceneManager owns one of these (child "OpeningSequence");
## GameWorld asks it to play instead of starting in the square
## - The drawing's congregation (DRAWING_KEYS) stand in the chapel through WorldState NPC locations,
##   which the spawner honours. Each carries npc_states[id].at_drawing until they leave
## - A short narration in the StoryItem popup style; Continue pages through it, Skip (or Esc) ends it
## - tithe_drawing_witnessed is set when the narration starts, so skipping still counts
## - Afterwards the congregation walks home (world.json route minutes) when the player leaves the
##   chapel, or at DISPERSE_AFTER minutes past the drawing, whichever comes first
## Nothing here writes a save: the first save comes from whatever the player does next

signal opening_started
signal opening_finished(skipped: bool)

const CHAPEL = "thornhaven_chapel"
const SPAWN_POINT = "opening"           # the chapel's back pews; "default" if a scene lacks it
const FLAG = "tithe_drawing_witnessed"
const DRAWING_KEYS = ["mathias", "gregor", "elena", "mira", "bjorn"]
const DISPERSE_AFTER = 120              # game minutes after the drawing (22:00) the chapel empties
const AT_DRAWING = "at_drawing"         # npc_states marker: still standing at the drawing
const FADE = 0.6

const PAGES = [
	"[b]The Tithe Night[/b]\n\nYou come into Thornhaven at dusk, on the one night of the year its people least want a stranger. The Chapel of the Dawn is full to the walls and nobody sits.\n\nOn the altar stands an iron urn. In it is a tile for every name in the village, and once a year one of them is drawn for Iron Hollow. Nobody drawn has ever come back.",
	"Elder Mathias draws with his eyes shut, as the rite asks. He reads the tile once to himself, and his hand shakes before he reads it aloud.\n\n[i]\"Elena. The merchant's daughter.\"[/i]\n\nA pale girl near the front, a cough kept behind her hand, does not cry out. She only nods, as if she had been waiting to hear it.",
	"Beside her, Gregor the merchant has gone the colour of ash. It is not only grief on his face. It is disbelief, as if the lot had broken a promise made to him. The widow Mira takes his arm. Bjorn the smith stares at the tile in Mathias's palm as if he were weighing it.\n\n[i]\"Seven days,\"[/i] Mathias says. [i]\"The Hollow comes on the seventh night. Go home, all of you.\"[/i]",
]

var playing: bool = false
var _page: int = 0
var _canvas: CanvasLayer = null
var _label: RichTextLabel = null
var _continue: Button = null
var _drawing_minute: int = -1

func _ready():
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.time_advanced.connect(_on_time_advanced)
	var scene_manager = get_parent()
	if scene_manager and scene_manager.has_signal("scene_transition_started"):
		scene_manager.scene_transition_started.connect(_on_transition_started)

## A new game whose drawing has not been seen yet (and no --no-opening user arg)
func should_play() -> bool:
	var world_state = get_node_or_null("/root/WorldState")
	if world_state == null or playing:
		return false
	if "--no-opening" in OS.get_cmdline_user_args():
		return false
	return world_state.has_method("is_new_game") and world_state.is_new_game() and not world_state.get_world_flag(FLAG)

## Put the congregation in the chapel, take the player there and tell the drawing
func play() -> void:
	if playing:
		return
	playing = true
	opening_started.emit()
	gather_congregation()
	var scene_manager = get_parent()
	if scene_manager and scene_manager.has_method("transition_to") and scene_manager.get_location(CHAPEL) != null:
		if "fade_overlay" in scene_manager and scene_manager.fade_overlay:
			scene_manager.fade_overlay.modulate.a = 1.0  # never show the square first
		var spawn = SPAWN_POINT if _chapel_has_spawn(SPAWN_POINT) else "default"
		await scene_manager.transition_to(CHAPEL, spawn, FADE, false)  # the drawing is at 20:00 sharp
	start_narration()

## Every drawing NPC who is alive stands in the chapel, marked at_drawing
func gather_congregation() -> Array:
	var world_state = get_node_or_null("/root/WorldState")
	var registry = get_node_or_null("/root/WorldRegistry")
	var gathered: Array = []
	if world_state == null or registry == null:
		return gathered
	_drawing_minute = world_state.get_game_minutes()
	for key in DRAWING_KEYS:
		var npc_id = registry.get_npc_id(key)
		if npc_id == "" or not world_state.is_npc_alive(npc_id):
			continue
		world_state.set_npc_location(npc_id, CHAPEL)
		world_state.npc_states[npc_id][AT_DRAWING] = _drawing_minute
		gathered.append(key)
	return gathered

## Show the narration and set the flag (also callable alone: tests, debug)
func start_narration() -> void:
	var world_state = get_node_or_null("/root/WorldState")
	if world_state and not world_state.get_world_flag(FLAG):
		world_state.set_world_flag(FLAG, true)
	_page = 0
	_build_popup()
	_show_page()
	print("[OpeningSequence] The drawing: narration shown (%s)" % (world_state.get_time_string() if world_state else "?"))

## End the narration now
func skip() -> void:
	_finish(true)

func _finish(skipped: bool) -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = null
	if playing:
		playing = false
		opening_finished.emit(skipped)

func _unhandled_input(event: InputEvent) -> void:
	if _canvas != null and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		skip()

func _next_page() -> void:
	_page += 1
	if _page >= PAGES.size():
		_finish(false)
	else:
		_show_page()

func _show_page() -> void:
	if _label == null:
		return
	_label.text = PAGES[_page]
	_continue.text = "Continue" if _page < PAGES.size() - 1 else "Begin"

## The StoryItem discovery popup, with a Skip button beside Continue
func _build_popup() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = CanvasLayer.new()
	_canvas.name = "OpeningNarration"
	_canvas.layer = 100
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
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(_label)
	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(buttons)
	var skip_button = Button.new()
	skip_button.text = "Skip"
	skip_button.pressed.connect(skip)
	buttons.add_child(skip_button)
	_continue = Button.new()
	_continue.pressed.connect(_next_page)
	buttons.add_child(_continue)
	_canvas.add_child(popup)
	# On SceneManager, not the scene: the popup outlives a scene change and is never baked into one
	add_child(_canvas)
	popup.size = popup.get_combined_minimum_size()
	await get_tree().process_frame
	if is_instance_valid(popup):
		popup.size = popup.get_combined_minimum_size()
		popup.position = (popup.get_viewport_rect().size - popup.size) / 2

func _chapel_has_spawn(spawn_name: String) -> bool:
	var scene_manager = get_parent()
	var location = scene_manager.get_location(CHAPEL) if scene_manager else null
	return location != null and "spawn_points" in location and location.spawn_points.has(spawn_name)

# =============================================================================
# AFTERWARDS: the congregation goes home
# =============================================================================

func _on_transition_started(from_location: String, to_location: String) -> void:
	if from_location == CHAPEL and to_location != CHAPEL:
		disperse("player_left")

func _on_time_advanced(_minutes: int, total_minutes: int, _reason: String) -> void:
	var start = _drawing_start(total_minutes)
	if start >= 0 and total_minutes - start >= DISPERSE_AFTER:
		disperse("late")

## Earliest at_drawing minute among those still marked (-1 when nobody is)
func _drawing_start(_now: int) -> int:
	var world_state = get_node_or_null("/root/WorldState")
	if world_state == null:
		return -1
	var earliest = -1
	for npc_id in world_state.npc_states:
		var state = world_state.npc_states[npc_id]
		if state is Dictionary and state.has(AT_DRAWING):
			var at = int(state[AT_DRAWING])
			earliest = at if earliest < 0 else mini(earliest, at)
	return earliest

## Everyone still standing at the drawing walks home along the shortest route. Returns their keys
func disperse(reason: String = "") -> Array:
	var world_state = get_node_or_null("/root/WorldState")
	var registry = get_node_or_null("/root/WorldRegistry")
	var sent: Array = []
	if world_state == null or registry == null:
		return sent
	for npc_id in world_state.npc_states.keys():
		var state = world_state.npc_states[npc_id]
		if not (state is Dictionary and state.has(AT_DRAWING)):
			continue
		state.erase(AT_DRAWING)
		if world_state.get_npc_location(npc_id) != CHAPEL or world_state.is_npc_travelling(npc_id) or not world_state.is_npc_alive(npc_id):
			continue  # something else moved them since the drawing
		var key = registry.get_npc_key(npc_id)
		var home = registry.get_npc_home(key)
		if home == "" or home == CHAPEL:
			continue
		var minutes = maxi(registry.travel_minutes(CHAPEL, home), 0)
		world_state.start_npc_travel(npc_id, home, minutes, CHAPEL)
		sent.append(key)
	if not sent.is_empty():
		print("[OpeningSequence] The drawing is over (%s): %s go home" % [reason, sent])
	return sent
