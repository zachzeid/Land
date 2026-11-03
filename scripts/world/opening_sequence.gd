extends Node
class_name OpeningSequence
## OpeningSequence - The Tithe Night's first scene, played rather than watched (docs/WORLD_SCHEMA.md §14)
## On a new game (no save file) the player starts in the Chapel of the Dawn on day 1, 20:00, with the
## village around them. SceneManager owns one of these (child "OpeningSequence"); GameWorld asks it to
## play instead of starting in the square
## - The congregation: DRAWING_KEYS plus Thornhaven's generics (population.json), placed through
##   WorldState NPC locations, which the spawner honours. Each carries npc_states[id].at_drawing
## - A short, skippable establishing card, then the player has control. Nothing else is narrated
## - The drawing is the movable fixed point tn_drawing (world.json calendar, Day 1 20:10). When it
##   fires, everyone in the chapel is marked witnessed_drawing, and if the player is there Mathias
##   reads Elena's name and tithe_drawing_witnessed is set (a discovery flag: those present witness it)
## - Before it the player can talk (each conversation turn moves the clock a minute, as well as the
##   idle clock), speak up at the urn (drawing_urn.gd -> disrupt(): tn_drawing_disrupted plus an
##   accusation or refusal PlayerEvent, which the drawing's shift rule moves to the next evening),
##   slip out (a seen_at PlayerEvent; they hear the name later, as gossip) or watch
## - A moved drawing gathers its congregation again an hour before its new time
## - Afterwards the congregation walks home (world.json route minutes) when the player leaves the
##   chapel, or DISPERSE_AFTER minutes after gathering; a broken-off drawing empties sooner
## Nothing here writes a save: the first save comes from whatever the player does next

signal opening_started
## The establishing card closed and the player has control (skipped: Skip/Esc, or the drawing came first)
signal opening_finished(skipped: bool)
## What became of the drawing for the player: "witnessed" | "disrupted" | "slipped_out" | "heard"
signal drawing_resolved(outcome: String)

const CHAPEL = "thornhaven_chapel"
const SPAWN_POINT = "opening"           # the chapel's middle aisle; "default" if a scene lacks it
const FLAG = "tithe_drawing_witnessed"   # the player stood there and saw it
const KNOWN = "tithe_drawing_known"      # the player knows Elena's name was drawn, by any route
const POINT = "tn_drawing"              # the drawing's calendar fixed point (movable)
const DISRUPTED = "tn_drawing_disrupted"
const DRAWING_KEYS = ["mathias", "gregor", "elena", "mira", "bjorn"]
const VILLAGE_AREA = "Thornhaven Village"  # generics who live here come to the drawing
const MAX_GENERICS = 10
const DISPERSE_AFTER = 120              # game minutes after gathering (22:00) the chapel empties
const BROKEN_OFF_AFTER = 30             # ...or this long after the player broke the rite off
const REGATHER_LEAD = 60                # a moved drawing gathers its congregation this early
const TURN_MINUTES = 1                  # a conversation turn before the drawing takes a minute
const HEAR_AFTER = 15                   # a player who slipped out hears the name this much later
const AT_DRAWING = "at_drawing"         # npc_states marker: still standing at the drawing
const WITNESSED = "witnessed_drawing"   # npc_states marker: in the chapel when the name was read
const PEW_SLOTS = "PewPlaces"           # chapel Marker2Ds where the generics stand
const FADE = 0.6

const ESTABLISHING = "[b]The Tithe Night[/b]\n\nYou come into Thornhaven at dusk, on the one night of the year its people least want a stranger. The Chapel of the Dawn is full to the walls, and nobody sits.\n\nOn the altar stands an iron urn holding a tile for every name in the village. Once a year one is drawn for Iron Hollow, and nobody drawn has ever come back. Elder Mathias will draw at ten past the hour.\n\n[color=#9aa7b4][i]Talk to anyone. Go up to the urn. Leave. Or stand and watch.[/i][/color]"
const DRAWING = "[b]The drawing[/b]\n\nElder Mathias draws with his eyes shut, as the rite asks. He reads the tile once to himself, and his hand shakes before he reads it aloud.\n\n[i]\"Elena. The merchant's daughter.\"[/i]\n\nA pale girl near the front, a cough kept behind her hand, only nods. Gregor has gone the colour of ash; Mira takes his arm. Bjorn stares at the tile in the Elder's palm as if he were weighing it.\n\n[i]\"Seven days,\"[/i] Mathias says. [i]\"The Hollow comes on the seventh night. Go home, all of you.\"[/i]"
const DRAWING_ANYWAY = "[b]The drawing[/b]\n\nMathias waits until the murmuring dies. Then, without looking at you, he puts his hand in the urn.\n\n[i]\"Elena. The merchant's daughter.\"[/i]\n\nThe pale girl at the front only nods. Gregor has gone the colour of ash; Mira takes his arm. Bjorn stares at the tile as if he were weighing it.\n\n[i]\"Seven days,\"[/i] Mathias says. [i]\"Go home, all of you.\"[/i]"
const HEARD = "[b]Word in the village[/b]\n\nYou hear it before you ask. They drew at the chapel tonight, and the tile said [i]Elena[/i]: the merchant's daughter, the girl with the cough. Seven days, and the Hollow's cart comes for her."
const DISRUPT_TEXT = {
	"accusation": "[b]You speak up[/b]\n\nYour voice carries further than you meant it to. [i]\"That lot is not the Dawn's. Someone's hand is in it.\"[/i]\n\nMathias's hand stops above the urn. Every face in the chapel turns from him to you. Gregor does not look at you at all.",
	"refusal": "[b]You stand in the way[/b]\n\nYou walk up the aisle and put yourself between Elder Mathias and the urn. [i]\"Nobody draws tonight.\"[/i]\n\nThe Elder looks at you a long moment. Somewhere behind you a woman starts, very quietly, to cry. Bjorn has stood up.",
}
const DISRUPT_SUMMARY = {
	"accusation": "stood up in the chapel and called the Tithe lot rigged before Elder Mathias could draw",
	"refusal": "stepped between Elder Mathias and the urn and would not let the Tithe drawing go on",
}
const PLAYER_UI_SCENE = "res://scenes/ui/player_ui.tscn"

## Injectable for tests; the PlayerEvents autoload otherwise (events engine, WORLD_SCHEMA §10)
var player_events: Node = null
var playing: bool = false               # from play() until the drawing resolves for the player
var phase: String = "idle"              # idle | establishing | awaiting | narrating | done
var outcome: String = ""                # the drawing_resolved outcome, once there is one
var gathered_generics: Array = []
var _canvas: CanvasLayer = null
var _label: RichTextLabel = null
var _continue: Button = null
var _pages: Array = []
var _page: int = 0
var _card_kind: String = ""
var _gathered_minute: int = -1
var _disrupted_minute: int = -1
var _regathered_for: int = -1
var _hear_due: int = -1                 # minute from which a slipped-out player hears the name

func _ready():
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.time_advanced.connect(_on_time_advanced)
		bus.calendar_flag_fired.connect(_on_calendar_flag_fired)
		if bus.has_signal("npc_response_generated"):
			bus.npc_response_generated.connect(_on_conversation_turn)
	var scene_manager = get_parent()
	if scene_manager and scene_manager.has_signal("scene_transition_started"):
		scene_manager.scene_transition_started.connect(_on_transition_started)
		scene_manager.scene_transition_completed.connect(_on_transition_completed)
	_attach_player_ui()

## A new game whose drawing has not happened yet (and no --no-opening user arg)
func should_play() -> bool:
	var world_state = get_node_or_null("/root/WorldState")
	if world_state == null or playing:
		return false
	if "--no-opening" in OS.get_cmdline_user_args():
		return false
	if not (world_state.has_method("is_new_game") and world_state.is_new_game()):
		return false
	return not world_state.get_world_flag(KNOWN) and not world_state.has_calendar_fired(POINT)

## Forget this run of the opening (debug `opening`, tests); the world state is the caller's to reset
func reset() -> void:
	_close_card(true)
	playing = false
	phase = "idle"
	outcome = ""
	gathered_generics = []
	_gathered_minute = -1
	_disrupted_minute = -1
	_regathered_for = -1
	_hear_due = -1

## Put the congregation in the chapel, take the player there and set the scene
func play() -> void:
	if playing:
		return
	playing = true
	outcome = ""
	phase = "establishing"
	opening_started.emit()
	gather_congregation()
	var scene_manager = get_parent()
	if scene_manager and scene_manager.has_method("transition_to") and scene_manager.get_location(CHAPEL) != null:
		if "fade_overlay" in scene_manager and scene_manager.fade_overlay:
			scene_manager.fade_overlay.modulate.a = 1.0  # never show the square first
		var spawn = SPAWN_POINT if _chapel_has_spawn(SPAWN_POINT) else "default"
		await scene_manager.transition_to(CHAPEL, spawn, FADE, false)  # no walking minutes: 20:00 sharp
	if phase == "establishing":
		show_establishing()

## Every drawing NPC who is alive stands in the chapel, marked at_drawing; Thornhaven's generics too
## Returns the roster keys gathered (the generics are in gathered_generics)
func gather_congregation() -> Array:
	var world_state = get_node_or_null("/root/WorldState")
	var registry = get_node_or_null("/root/WorldRegistry")
	var gathered: Array = []
	gathered_generics = []
	if world_state == null or registry == null:
		return gathered
	_gathered_minute = world_state.get_game_minutes()
	_disrupted_minute = -1
	for key in DRAWING_KEYS:
		var npc_id = registry.get_npc_id(key)
		if npc_id == "" or not world_state.is_npc_alive(npc_id):
			continue
		_place(world_state, npc_id)
		gathered.append(key)
	for id in _village_generics():
		_place(world_state, id)
		gathered_generics.append(id)
	return gathered

func _place(world_state: Node, npc_id: String) -> void:
	world_state.set_npc_location(npc_id, CHAPEL)
	world_state.npc_states[npc_id][AT_DRAWING] = _gathered_minute

## Generics who live in Thornhaven Village and are about at this hour; the chapel's own first
func _village_generics() -> Array:
	var manager = _generics()
	var registry = get_node_or_null("/root/WorldRegistry")
	if manager == null or registry == null:
		return []
	var own: Array = []
	var others: Array = []
	for id in manager.get_ids():
		var inst = manager.get_instance(id)
		if inst == null or registry.get_area(inst.home) != VILLAGE_AREA:
			continue
		var where = manager.get_location(id)
		if registry.get_area(where) != VILLAGE_AREA or not manager.is_present(id, where):
			continue  # away, travelling, dead or outside their hours
		(own if inst.home == CHAPEL else others).append(id)
	return (own + others).slice(0, MAX_GENERICS)

# =============================================================================
# THE CARDS (StoryItem popup style)
# =============================================================================

## The establishing card. Begin, Skip or Esc closes it; then the player has control
func show_establishing() -> void:
	phase = "establishing"
	_show_card("establishing", [ESTABLISHING])
	var world_state = get_node_or_null("/root/WorldState")
	print("[OpeningSequence] The chapel, %s: the drawing is at %s" % [world_state.get_time_string() if world_state else "?", _point_time_string()])

## End whatever card is showing now (the establishing card counts as skipped)
func skip() -> void:
	_close_card(true)

func is_card_open() -> bool:
	return is_instance_valid(_canvas)

func get_card_kind() -> String:
	return _card_kind if is_card_open() else ""

func get_card_text() -> String:
	return _label.text if is_card_open() and _label else ""

func _show_card(kind: String, pages: Array) -> void:
	_close_card(true)
	_card_kind = kind
	_pages = pages
	_page = 0
	_build_popup()
	_show_page()

func _close_card(skipped: bool) -> void:
	var kind = _card_kind
	var was_open = is_instance_valid(_canvas)
	if was_open:
		_canvas.queue_free()
	_canvas = null
	_label = null
	_card_kind = ""
	if not was_open:
		return
	if kind == "establishing":
		if phase == "establishing":
			phase = "awaiting"
		opening_finished.emit(skipped)
	elif kind == "drawing" and phase == "narrating":
		phase = "done"

func _unhandled_input(event: InputEvent) -> void:
	if is_card_open() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		skip()

func _next_page() -> void:
	_page += 1
	if _page >= _pages.size():
		_close_card(false)
	else:
		_show_page()

func _show_page() -> void:
	if _label == null:
		return
	_label.text = _pages[_page]
	var last = _page >= _pages.size() - 1
	_continue.text = "Continue" if not last else ("Begin" if _card_kind == "establishing" else "Close")

func _build_popup() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "OpeningNarration"
	_canvas.layer = 100
	_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
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
	if _card_kind == "establishing":
		var skip_button = Button.new()
		skip_button.text = "Skip"
		skip_button.pressed.connect(skip)
		buttons.add_child(skip_button)
	_continue = Button.new()
	_continue.pressed.connect(_next_page)
	buttons.add_child(_continue)
	_canvas.add_child(popup)
	# On SceneManager, not the scene: the card outlives a scene change and is never baked into one
	add_child(_canvas)
	popup.size = popup.get_combined_minimum_size()
	_center_popup.call_deferred(popup)

func _center_popup(popup: Control) -> void:
	if is_instance_valid(popup) and popup.is_inside_tree():
		popup.size = popup.get_combined_minimum_size()
		popup.position = (popup.get_viewport_rect().size - popup.size) / 2

## Show a card once no conversation (or other pausing UI) is up, so it never lands mid-sentence
func _show_card_when_free(kind: String, pages: Array) -> void:
	while is_inside_tree() and _busy():
		await get_tree().create_timer(0.25, true, false, true).timeout
	if is_inside_tree():
		_show_card(kind, pages)

func _busy() -> bool:
	if get_tree().paused:
		return true
	var dialogue = get_node_or_null("/root/DialogueManager")
	return dialogue != null and "active_conversations" in dialogue and not dialogue.active_conversations.is_empty()

# =============================================================================
# THE DRAWING (calendar fixed point tn_drawing)
# =============================================================================

func _on_calendar_flag_fired(flag_name: String, at_minute: int) -> void:
	if flag_name == POINT:
		on_drawing(at_minute)

## The name is read. Everyone in the chapel is marked; the player sees it only if they are there
## Returns the npc ids who witnessed it
func on_drawing(at_minute: int = -1) -> Array:
	var world_state = get_node_or_null("/root/WorldState")
	if world_state == null:
		return []
	if at_minute < 0:
		at_minute = world_state.get_game_minutes()
	# Only a drawing the opening set up: not under --no-opening, a test's long jump or an old save
	if phase == "idle" and _drawing_start() < 0 and not world_state.get_world_flag(DISRUPTED):
		return []
	var present = present_in_chapel()
	for npc_id in present:
		var state: Dictionary = world_state.npc_states.get(npc_id, {"is_alive": true})
		state[WITNESSED] = at_minute
		world_state.npc_states[npc_id] = state
	var here = player_in_chapel()
	if here:
		# The shift rule should have moved a disrupted drawing; if it fired anyway, Mathias draws anyway
		var anyway = world_state.get_world_flag(DISRUPTED)
		if not world_state.get_world_flag(FLAG):
			world_state.set_world_flag(FLAG, true)  # a discovery flag: those present witness it
		world_state.set_world_flag(KNOWN, true)
		_record("seen_at", "stood in the Chapel of the Dawn and watched Elder Mathias draw Elena's name for the Tithe", ["mathias", "elena"], present)
		phase = "narrating"
		_resolve("witnessed")
		_show_card_when_free("drawing", [DRAWING_ANYWAY if anyway else DRAWING])
	else:
		if not world_state.get_world_flag(KNOWN):
			_hear_due = at_minute + HEAR_AFTER
		phase = "done"
		playing = false
	print("[OpeningSequence] The drawing (%s): Elena's name read before %d, %s" % [
		world_state.get_time_string(), present.size(), "the player among them" if here else "the player elsewhere"])
	return present

## Alive, not travelling, and standing in the chapel now (roster NPCs and generics)
func present_in_chapel() -> Array:
	var world_state = get_node_or_null("/root/WorldState")
	var registry = get_node_or_null("/root/WorldRegistry")
	var result: Array = []
	if world_state == null or registry == null:
		return result
	for key in registry.get_npc_keys():
		var npc_id = registry.get_npc_id(key)
		if npc_id != "" and world_state.is_npc_alive(npc_id) and not world_state.is_npc_travelling(npc_id) and world_state.get_npc_location(npc_id) == CHAPEL:
			result.append(npc_id)
	var manager = _generics()
	if manager:
		for id in manager.get_present_ids(CHAPEL):
			if id not in result:
				result.append(id)
	return result

func player_in_chapel() -> bool:
	var scene_manager = get_parent()
	return scene_manager != null and scene_manager.has_method("get_current_location_id") and scene_manager.get_current_location_id() == CHAPEL

## Still to come: not fired and not cancelled (a moved point waits for its new minute)
func is_drawing_pending() -> bool:
	var world_state = get_node_or_null("/root/WorldState")
	return world_state != null and not world_state.has_calendar_fired(POINT) and not world_state.get_world_flag(POINT + "_cancelled")

## The urn offers "speak up" only before the name is read, once, with the player in the chapel
func can_disrupt() -> bool:
	var world_state = get_node_or_null("/root/WorldState")
	return world_state != null and is_drawing_pending() and not world_state.get_world_flag(DISRUPTED) and player_in_chapel()

## The player breaks the rite off. kind: "accusation" | "refusal". Records the first PlayerEvent,
## witnessed by everyone present, then sets tn_drawing_disrupted, whose shift rule (director engine)
## moves the drawing to the next evening. Returns the event id ("" before the events engine lands)
func disrupt(kind: String = "refusal") -> String:
	var world_state = get_node_or_null("/root/WorldState")
	if world_state == null or not is_drawing_pending() or world_state.get_world_flag(DISRUPTED):
		return ""
	if kind not in DISRUPT_SUMMARY:
		kind = "refusal"
	var present = present_in_chapel()
	_disrupted_minute = world_state.get_game_minutes()
	var before = point_minute()
	var event_id = _record(kind, DISRUPT_SUMMARY[kind], ["mathias"], present, {"flag": DISRUPTED})
	world_state.set_world_flag(DISRUPTED, true)
	phase = "done"
	_resolve("disrupted")
	_show_card("disruption", [DISRUPT_TEXT[kind]])
	_after_disruption.call_deferred(before)
	print("[OpeningSequence] The drawing broken off (%s) before %d, %s" % [kind, present.size(), world_state.get_time_string()])
	return event_id

## Once the director has applied the shift rule, say what the world did with the drawing
func _after_disruption(before: int) -> void:
	var moved = point_minute()
	if moved != before and is_card_open() and _card_kind == "disruption":
		_pages = [_pages[0] + "\n\n[color=#9aa7b4][i]%s[/i][/color]" % _shift_reason()]
		_show_page()
	elif moved == before:
		print("[OpeningSequence] tn_drawing has not moved (the director's shift rules are not in yet)")

## The drawing's minute now, as the calendar has it (a shift moves it)
func point_minute() -> int:
	var world_state = get_node_or_null("/root/WorldState")
	if world_state:
		for entry in world_state.get_calendar():
			if entry.flag == POINT:
				return int(entry.minute)
	return -1

func _point_time_string() -> String:
	var minute = point_minute()
	if minute < 0:
		return "?"
	return "Day %d, %02d:%02d" % [minute / 1440 + 1, (minute % 1440) / 60, minute % 60]

func _shift_reason() -> String:
	var registry = get_node_or_null("/root/WorldRegistry")
	var entry = registry.get_calendar().get("flags", {}).get(POINT, {}) if registry else {}
	for rule in entry.get("shift_rules", []):
		if rule is Dictionary and str(rule.get("when", "")) == DISRUPTED:
			return str(rule.get("reason", ""))
	return "The drawing was called again for another night."

# =============================================================================
# PLAYER EVENTS (events engine, WORLD_SCHEMA §10)
# =============================================================================

func _record(kind: String, summary: String, about: Array, witnesses: Array, extra: Dictionary = {}) -> String:
	var events = player_events if player_events else get_node_or_null("/root/PlayerEvents")
	if events == null or not events.has_method("record"):
		return ""
	var opts = {"location": CHAPEL, "witnesses": witnesses.duplicate()}
	opts.merge(extra, true)
	var result = events.record(kind, summary, about, opts)
	return str(result) if result != null else ""

func _resolve(how: String) -> void:
	outcome = how
	if how != "slipped_out":
		playing = false
	drawing_resolved.emit(how)

# =============================================================================
# THE CLOCK: conversation turns, slipping out, hearing, a moved drawing
# =============================================================================

## A conversation turn in the chapel before the drawing takes a minute (the idle clock runs too)
func _on_conversation_turn(_npc_id: String, _data: Dictionary) -> void:
	var world_state = get_node_or_null("/root/WorldState")
	if world_state and phase in ["establishing", "awaiting"] and is_drawing_pending() and player_in_chapel():
		world_state.advance_time(TURN_MINUTES, "talk")

func _on_transition_started(from_location: String, to_location: String) -> void:
	if from_location != CHAPEL or to_location == CHAPEL:
		return
	var world_state = get_node_or_null("/root/WorldState")
	if world_state and is_drawing_pending() and not world_state.get_world_flag(DISRUPTED) and _drawing_start() >= 0:
		slip_out(to_location)
	else:
		disperse("player_left")

## The player leaves before the name is read: seen going by everyone there; the drawing goes on
func slip_out(to_location: String = "") -> String:
	if get_card_kind() == "establishing":
		_close_card(true)
	var event_id = _record("seen_at", "slipped out of the Chapel of the Dawn before the Tithe drawing", ["mathias"], present_in_chapel(),
		{"to": to_location} if to_location != "" else {})
	phase = "done"
	_resolve("slipped_out")
	print("[OpeningSequence] The player slipped out before the drawing")
	return event_id

func _on_transition_completed(location: String) -> void:
	if location == CHAPEL:
		_stand_generics_in_pews()
		if outcome == "slipped_out" and is_drawing_pending():
			phase = "awaiting"  # back in time for the drawing
			outcome = ""
	_maybe_hear(true)

func _on_time_advanced(_minutes: int, total_minutes: int, _reason: String) -> void:
	var start = _drawing_start()
	if start >= 0:
		var limit = DISPERSE_AFTER
		var since = total_minutes - start
		if _disrupted_minute >= 0:
			limit = BROKEN_OFF_AFTER
			since = total_minutes - _disrupted_minute
		if since >= limit:
			disperse("late" if _disrupted_minute < 0 else "broken_off")
	_maybe_regather(total_minutes)
	_maybe_hear(false)

## A slipped-out player hears the name: on their next arrival somewhere, or HEAR_AFTER minutes on
func _maybe_hear(arrived: bool) -> void:
	var world_state = get_node_or_null("/root/WorldState")
	if _hear_due < 0 or world_state == null:
		return
	if world_state.get_world_flag(KNOWN):
		_hear_due = -1
		return
	if not arrived and world_state.get_game_minutes() < _hear_due:
		return
	_hear_due = -1
	world_state.set_world_flag(KNOWN, true)  # heard, not witnessed: tithe_drawing_witnessed stays false
	_resolve("heard")
	_show_card_when_free("heard", [HEARD])
	print("[OpeningSequence] The player heard Elena's name through gossip (%s)" % world_state.get_time_string())

func is_hearing_pending() -> bool:
	return _hear_due >= 0

## A drawing moved to another night: its congregation walks back to the chapel an hour before
func _maybe_regather(now: int) -> void:
	var world_state = get_node_or_null("/root/WorldState")
	var registry = get_node_or_null("/root/WorldRegistry")
	if world_state == null or registry == null or not is_drawing_pending() or not world_state.get_world_flag(DISRUPTED):
		return
	var minute = point_minute()
	if minute < 0 or now < minute - REGATHER_LEAD or now >= minute or _regathered_for == minute:
		return
	_regathered_for = minute
	_disrupted_minute = -1
	_gathered_minute = now
	var sent: Array = []
	for key in DRAWING_KEYS:
		var npc_id = registry.get_npc_id(key)
		if npc_id == "" or not world_state.is_npc_alive(npc_id):
			continue
		var from = world_state.get_npc_location(npc_id)
		if from != CHAPEL:
			var walk = clampi(registry.travel_minutes(from, CHAPEL), 0, REGATHER_LEAD - 5)
			world_state.start_npc_travel(npc_id, CHAPEL, walk, from)
		world_state.npc_states[npc_id][AT_DRAWING] = now
		sent.append(key)
	print("[OpeningSequence] The drawing is called again for %s: %s come to the chapel" % [_point_time_string(), sent])

# =============================================================================
# AFTERWARDS: the congregation goes home
# =============================================================================

## Earliest at_drawing minute among those still marked (-1 when nobody is)
func _drawing_start(_now: int = 0) -> int:
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
## (a generic's id). Nobody leaves while the drawing is still to come, unless it was broken off
func disperse(reason: String = "") -> Array:
	var world_state = get_node_or_null("/root/WorldState")
	var registry = get_node_or_null("/root/WorldRegistry")
	var sent: Array = []
	if world_state == null or registry == null:
		return sent
	if is_drawing_pending() and not world_state.get_world_flag(DISRUPTED) and reason != "force":
		return sent
	for npc_id in world_state.npc_states.keys():
		var state = world_state.npc_states[npc_id]
		if not (state is Dictionary and state.has(AT_DRAWING)):
			continue
		state.erase(AT_DRAWING)
		if world_state.get_npc_location(npc_id) != CHAPEL or world_state.is_npc_travelling(npc_id) or not world_state.is_npc_alive(npc_id):
			continue  # something else moved them since the drawing
		var home = _home_of(npc_id)
		if home == "" or home == CHAPEL:
			continue
		var minutes = maxi(registry.travel_minutes(CHAPEL, home), 0)
		world_state.start_npc_travel(npc_id, home, minutes, CHAPEL)
		var key = registry.get_npc_key(npc_id)
		sent.append(key if key != "" else npc_id)
	_disrupted_minute = -1
	if not sent.is_empty():
		print("[OpeningSequence] The drawing is over (%s): %s go home" % [reason, sent])
	return sent

func _home_of(npc_id: String) -> String:
	var manager = _generics()
	if manager and manager.is_generic(npc_id):
		var inst = manager.get_instance(npc_id)
		return inst.home if inst else ""
	var registry = get_node_or_null("/root/WorldRegistry")
	return registry.get_npc_home(registry.get_npc_key(npc_id)) if registry else ""

func _generics() -> Node:
	var registry = get_node_or_null("/root/DynamicNPCRegistry")
	return registry.generics if registry and "generics" in registry and registry.generics else null

## The spawner rings generics round the door; at the drawing they stand in the pews
func _stand_generics_in_pews() -> void:
	var scene_root = get_tree().current_scene if is_inside_tree() else null
	var slots_node = scene_root.find_child(PEW_SLOTS, true, false) if scene_root else null
	if slots_node == null or gathered_generics.is_empty():
		return
	var slots = slots_node.get_children().filter(func(n): return n is Marker2D)
	var index = 0
	for npc in get_tree().get_nodes_in_group("npcs"):
		if index >= slots.size():
			break
		if npc is Node2D and npc.has_meta("generic_id") and str(npc.get_meta("generic_id")) in gathered_generics and scene_root.is_ancestor_of(npc):
			npc.global_position = slots[index].global_position
			index += 1

func _chapel_has_spawn(spawn_name: String) -> bool:
	var scene_manager = get_parent()
	var location = scene_manager.get_location(CHAPEL) if scene_manager and scene_manager.has_method("get_location") else null
	return location != null and "spawn_points" in location and location.spawn_points.has(spawn_name)

# =============================================================================
# THE PLAYER'S OWN UI (thoughts, the menu, the epilogue: scripts/ui/player_ui.gd)
# =============================================================================

## SceneManager outlives every scene, so the player's persistent UI hangs beside the opening there
func _attach_player_ui() -> void:
	var host = get_parent()
	if host == null or host.get_node_or_null("PlayerUI") != null or not ResourceLoader.exists(PLAYER_UI_SCENE):
		return
	var ui = load(PLAYER_UI_SCENE).instantiate()
	ui.name = "PlayerUI"
	host.add_child.call_deferred(ui)
