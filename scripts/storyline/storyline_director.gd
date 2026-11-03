extends Node
# StorylineDirector - Runs authored storylines and lets NPC agents act inside them
# Beats open and resolve from WorldState flags at once; their triggered hooks join a decision queue
# A story clock paces NPCs: each round (conversation end, player choice or flag, scene change,
# idle timer) decides at most N queued hooks per storyline. Only effects both the hook and the
# NPC's SOUL.md permit apply. Every decision lands in an inspectable chronicle. Contract: docs/WORLD_SCHEMA.md

signal hook_offered(storyline_id: String, hook_id: String, npc_key: String)
signal npc_acted(entry: Dictionary)          # a decision that was not "pass"
signal decision_recorded(entry: Dictionary)  # every decision, passes included
signal beat_opened(storyline_id: String, beat_id: String)
signal beat_resolved(storyline_id: String, beat_id: String)
signal beat_block_changed(storyline_id: String, beat_id: String, blocked: bool)
signal ending_reached(storyline_id: String, ending_id: String)
signal decision_queued(storyline_id: String, hook_id: String)
signal round_completed(round_number: int, reason: String, entries: Array)
signal conversation_acted(entry: Dictionary)  # an NPC acted (or tried to) in conversation
# Personal arcs (docs/WORLD_SCHEMA.md §8): the third tier of free will
signal personal_step_completed(npc_key: String, arc_id: String, step_id: String)
signal personal_arc_ended(npc_key: String, arc_id: String, outcome: String)  # "completed" | "failed"
signal personal_turn_taken(entry: Dictionary)                                # every personal turn (mode "personal")
signal personal_round_completed(personal_round: int, entries: Array)
# Soul registration (generics engine contract, docs/WORLD_BUILD_PLAN.md Phase 3)
signal soul_registered(npc_key: String, tier: String)
signal soul_unregistered(npc_key: String)
signal soul_tier_changed(npc_key: String, old_tier: String, new_tier: String)
# The non-linear world (docs/WORLD_SCHEMA.md Part II, §11-15)
signal fixed_point_shifted(point: String, entry: Dictionary)   # a calendar point moved (chronicle entry)
signal emergent_opened(instance: Dictionary)                   # an emergent beat grew from what the player did
signal emergent_closed(instance: Dictionary)                   # resolved or expired
signal emergent_acted(entry: Dictionary)                       # an NPC acted in an emergent beat
signal epilogue_ready(epilogue: Dictionary)                    # end_game(): the world the player made

const Soul = preload("res://scripts/storyline/soul.gd")
const TimeWindowScript = preload("res://scripts/storyline/time_window.gd")
const EffectApplier = preload("res://scripts/storyline/effect_applier.gd")
const NpcAgent = preload("res://scripts/storyline/npc_agent.gd")
const Emergence = preload("res://scripts/storyline/emergence.gd")
const EpilogueScript = preload("res://scripts/storyline/epilogue.gd")
const REPUTATION_PATH = "res://scripts/world_state/reputation.gd"
const DEFAULT_EMERGENCE_DIR = "res://resources/emergence"
const SEASON_END_POINT = "season_end"

const DEFAULT_STORYLINE_DIR = "res://resources/storylines"
const DEFAULT_SOUL_DIR = "res://souls"
# NPC keys, homes and places come from WorldRegistry (resources/world/world.json)
const DEFAULT_ROUND_SECONDS = 300.0  # idle fallback between rounds (unpaused time; STORY_ROUND_SECONDS)
const MAX_CHRONICLE = 500
const MAX_CASCADE = 32        # flag changes processed per burst before we assume a loop
const MINUTES_PER_ROUND = 120 # one story round per this many game minutes advanced
const MAX_TIME_ROUNDS = 24    # rounds owed by one long journey are capped here

# Conversation agency (docs/WORLD_SCHEMA.md §6)
const CONVERSATION_ACTION_BUDGET = 3   # rule 7: actions per reply
const MAX_COMMITMENTS = 2              # player commitments recognised per reply
const NEAR_MINUTES = 30                # farther than this is "far": word travels, it does not teleport
const MAX_PLACES_LISTED = 8
const MAX_BEATS_DETAILED = 3           # beats shown with suggested options in the agency block
const MAX_OPTIONS_PER_BEAT = 2
const MAX_BEATS_NAMED = 6              # further beats named only ("also in play")
const MAX_FLAGS_LISTED = 8
const MAX_COMMITMENTS_LISTED = 4

# Tiers and personal turns (docs/WORLD_SCHEMA.md §8-9)
const TIERS = ["main", "promoted", "generic"]
const TURN_TIERS = ["main", "promoted"]          # only these get personal turns
const DEFAULT_PERSONAL_DECISIONS = 4             # world.json tiers.personal_decisions_per_round wins
const PERSONAL_ACTION_BUDGET = 3                 # effects per completed step
const STORY_ONLY_EFFECTS = ["set_flag", "block_beat", "unlock_beat"]  # never personal scope

var agency_mode: String = "offline"
var decisions_per_round_per_storyline: int = 1
var round_boundaries_enabled: bool = true  # false: rounds only via advance_round() (tests)
var cascade_limit: int = MAX_CASCADE
var cascade_overflows: int = 0         # bursts cut short by cascade_limit (inspectable)
var storyline_dir: String = DEFAULT_STORYLINE_DIR
var soul_dir: String = DEFAULT_SOUL_DIR
var personal_turns_enabled: bool = true    # advance_round() ends with a personal phase
var personal_decisions_per_round: int = -1 # -1: world.json tiers.personal_decisions_per_round (default 4)
var player_location_override: String = "" # tests/debug: where the player stands ("" = SceneManager)
# Part II (non-linear world): collaborators, overridable by tests
var emergence_dir: String = DEFAULT_EMERGENCE_DIR
var player_events_override: Node = null    # tests: a fake PlayerEvents (null = /root/PlayerEvents)
var reputation_override: Callable = Callable()  # tests: (scope, id) -> float (invalid = Reputation.of)
var relationship_dims_override: Dictionary = {} # tests: npc key -> {dimension: value} toward the player
var inner_voice_override: Node = null      # tests: another InnerVoice (null = /root/InnerVoice)
var end_on_season_end: bool = true          # season_end fires -> end_game("season_end")

# Content
var _storylines: Dictionary = {}       # storyline id -> parsed JSON
var _storyline_order: Array = []       # ids in load order (file name order)
var _souls: Dictionary = {}            # npc key -> Soul
var _declared_flags: Dictionary = {}   # flag -> storyline id that declares it
var _tiers: Dictionary = {}            # npc key -> "main" | "promoted" | "generic" (file souls are main)
## Souls registered at runtime (register_soul). Their TEXT is not saved here: the registrar (the
## generics engine) persists it and calls register_soul again after a load. What this Director saves
## for them is runtime state only (want weights, Life progress, tier), held in _pending_soul_state
## until the soul is registered again. load_content() re-parses these, so they survive a content reload
var _registered: Dictionary = {}       # npc key -> {"text", "npc_id", "tier", "home"}
var _registered_ids: Dictionary = {}   # lowercase npc_id -> key (registered souls)
var _personal_flags: Dictionary = {}   # personal flag -> owning npc key (known flags, never settable by effects)

# State (saved through WorldState)
var _opened: Dictionary = {}           # "storyline/beat" -> true (sticky until resolved)
var _opened_seq: Dictionary = {}       # "storyline/beat" -> order it opened in (recency for the agency block)
var _open_counter: int = 0
var _resolved: Dictionary = {}         # "storyline/beat" -> true
var _blocked: Dictionary = {}          # "storyline/beat" -> true
var _hook_acts: Dictionary = {}        # "storyline/hook" -> times an NPC acted there
var _endings: Dictionary = {}          # storyline id -> ending id (first reached wins)
var _drift_applied: Dictionary = {}    # "npc|flag|want" -> true
var _agendas: Dictionary = {}          # npc key -> Array of agenda dicts
var _pending_relationships: Dictionary = {}  # npc key -> {dimension: summed delta}
var _chronicle: Array = []
var _seq: int = 0
var _agenda_seq: int = 0
var _round: int = 0
var _decision_queue: Array = []        # [{storyline, beat, hook, trigger, queued_round}] in arrival order
var _pending_moves: Dictionary = {}    # speaker key -> [{npc, location, minutes}] applied when that conversation ends
var _scheduled: Array = []             # [{at, effect, actor, source, note}] effects landing later on the game clock
var _minutes_toward_round: int = 0     # game minutes since the last time-driven round
var _personal_round: int = 0           # personal phases run (longest-waiting uses it)
var _pending_soul_state: Dictionary = {}  # key -> {"weights", "life", "tier"} saved for a soul not registered yet
var _time_rounds_owed: int = 0

var _flag_queue: Array = []            # flag changes waiting for evaluation
var _processing: bool = false
var _effects: EffectApplier
var _agent: NpcAgent
var _claude_client: Node = null
var _round_timer: Timer
var _effect_depth: int = 0             # > 0 while the Director itself is applying effects
var _booted: bool = false              # no rounds until the startup evaluation is done
var _in_round: bool = false
var _round_requested: bool = false
var _rerun_round: bool = false
var _round_reasons: Array = []
var _in_personal: bool = false
var _emergence                         # Emergence runtime (emergent beats)
var _current_actor: String = ""        # npc key whose effect is being applied (shift rule attribution)
var _flag_actors: Dictionary = {}      # flag -> who last turned it true: npc key | "player" | "world" | "director"
## The player's causal chain (the world-only advance cap, docs/WORLD_SCHEMA.md §11): a flag is
## player-chained when the player set it, or an effect set it whose cause traces to the player (a hook
## triggered on_flag by a player-chained flag, a conversation with the player, an emergent beat grown
## from a player event). Saved
var _flag_player_chain: Dictionary = {}
var _causal_player: bool = false       # true while an effect with the player in its causal chain applies
var _player_events_connected: Node = null
var _epilogue: Dictionary = {}         # the last epilogue generated (end_game)
var _game_ended: String = ""           # why the game ended ("" = still playing)

func _init():
	_effects = EffectApplier.new(self)
	_agent = NpcAgent.new()
	_emergence = Emergence.new(self)

func _ready():
	_agent.tree = get_tree()
	var config = get_node_or_null("/root/Config")
	if config and "npc_agency_mode" in config:
		set_agency_mode(config.npc_agency_mode)
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.world_flag_changed.connect(_on_world_flag_changed)
		bus.time_advanced.connect(_on_time_advanced)
		bus.calendar_flag_fired.connect(_on_calendar_flag_fired)
	var ws = get_node_or_null("/root/WorldState")
	if ws and ws.has_signal("calendar_point_shifted"):
		ws.calendar_point_shifted.connect(_on_calendar_point_shifted)
	if ws and ws.has_signal("calendar_shift_clamped"):
		ws.calendar_shift_clamped.connect(_on_calendar_shift_clamped)
	load_content()
	var world_state = get_node_or_null("/root/WorldState")
	if world_state and "storyline_state" in world_state and not world_state.storyline_state.is_empty():
		load_from_dict(world_state.storyline_state)

	_round_timer = Timer.new()
	_round_timer.wait_time = max(float(config.story_round_seconds) if config and "story_round_seconds" in config else DEFAULT_ROUND_SECONDS, 1.0)
	_round_timer.process_mode = Node.PROCESS_MODE_PAUSABLE  # the story waits while the game is paused
	_round_timer.timeout.connect(request_round.bind("idle_timer"))
	add_child(_round_timer)
	_round_timer.start()
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_signal("scene_transition_completed"):
		scene_manager.scene_transition_completed.connect(func(_location): request_round("scene_transition"))

	# Other autoloads finish _ready first. Boot only evaluates beats and enqueues; nothing is decided
	call_deferred("_boot")
	print("StorylineDirector initialized (%d storylines, %d souls, agency %s)" % [_storylines.size(), _souls.size(), agency_mode])

# =============================================================================
# CONTENT
# =============================================================================

## Load storylines and souls, replacing any loaded before. Clears runtime state
## Tests pass fixture directories; "" means the default res:// locations
func load_content(storyline_path: String = "", soul_path: String = "") -> void:
	if storyline_path != "":
		storyline_dir = storyline_path
	if soul_path != "":
		soul_dir = soul_path
	_storylines.clear()
	_storyline_order.clear()
	_souls.clear()
	_declared_flags.clear()
	_tiers.clear()
	_registered_ids.clear()
	_personal_flags.clear()
	StoryFlags.clear_registered_flag_descriptions()
	var registry = _registry()
	if registry:
		registry.clear_registered_canon()

	for key in _list_dirs(soul_dir):
		var soul = Soul.load_from_file("%s/%s/SOUL.md" % [soul_dir, key])
		if soul == null:
			push_warning("[StorylineDirector] Could not parse %s/%s/SOUL.md" % [soul_dir, key])
			continue
		_souls[soul.npc_key] = soul
		_tiers[soul.npc_key] = "main"  # the authored souls are anchored: main, never demoted

	for file_name in _list_files(storyline_dir, ".json"):
		var storyline = _load_storyline("%s/%s" % [storyline_dir, file_name])
		if storyline.is_empty():
			continue
		var sid = str(storyline.id)
		if _storylines.has(sid):
			push_warning("[StorylineDirector] Duplicate storyline id '%s' in %s" % [sid, file_name])
			continue
		_storylines[sid] = storyline
		_storyline_order.append(sid)
		var flags: Dictionary = storyline.get("flags", {})
		for flag in flags:
			_declared_flags[flag] = sid
		StoryFlags.register_flag_descriptions(flags)
	_register_canon()
	var ws_cal = get_node_or_null("/root/WorldState") if is_inside_tree() else null
	if ws_cal and ws_cal.has_method("refresh_calendar_descriptions"):
		ws_cal.refresh_calendar_descriptions()  # a storyline may declare <point>_cancelled / _eve: its text wins
	var file_keys = _souls.keys()
	file_keys.sort()
	for key in file_keys:
		_claim_personal_flags(key)
	for key in _registered.keys():
		if _souls.has(key):
			push_warning("[StorylineDirector] Registered soul '%s' now has a SOUL.md file; the file wins" % key)
			_registered.erase(key)
			continue
		if not _install_registered(key):
			push_warning("[StorylineDirector] Registered soul '%s' no longer parses; dropped" % key)
			_registered.erase(key)
	_emergence.load_templates(emergence_dir)
	reset_state()

func _load_storyline(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary or not data.get("id") is String or not data.get("beats") is Array:
		push_warning("[StorylineDirector] Skipping %s: not a storyline (needs string id and beats array)" % path)
		return {}
	if not data.get("flags") is Dictionary:
		data["flags"] = {}
	if not data.get("endings") is Array:
		data["endings"] = []
	return data

# =============================================================================
# BEAT EVALUATION
# =============================================================================

func _boot() -> void:
	connect_player_events()
	evaluate_all()
	_booted = true

## Re-check every beat against current flags (also catches drift for flags already true)
## Opens/resolves beats and enqueues their hooks; decides nothing
func evaluate_all() -> void:
	for key in _souls:
		for rule in _souls[key].drift:
			if _flag(rule.flag):
				_apply_drift(rule.flag)
	_flag_queue.append({"flag": "", "value": null})
	_process_queue()
	_apply_shift_rules("")

## Every flag change opens/resolves beats now. A change the Director did not make is the
## player's doing (StoryItem, dialogue, quests, debug): that is also a round boundary
func _on_world_flag_changed(flag_name: String, _old_value, new_value):
	var player_caused = not is_director_change()
	var world_state = get_node_or_null("/root/WorldState")
	var world_caused = world_state != null and world_state.has_method("is_world_change") and world_state.is_world_change()
	if new_value == true:
		_flag_actors[flag_name] = "world" if world_caused else ("player" if player_caused else (_current_actor if _current_actor != "" else "director"))
		_flag_player_chain[flag_name] = (player_caused and not world_caused) or (is_director_change() and _causal_player)
	_flag_queue.append({"flag": flag_name, "value": new_value})
	_process_queue()
	if new_value == true:
		_apply_shift_rules(flag_name)  # a movable fixed point's shift_rules (docs/WORLD_SCHEMA.md §11)
		_emergence.on_flag(flag_name)
	if world_caused:
		request_round("calendar:" + flag_name)  # a fixed point passed: the village reacts
	elif player_caused:
		request_round("player_flag:" + flag_name)

## True while the Director is applying an NPC or on_resolve effect (EventPropagator asks:
## such flags get gossip but no witnesses, since the player did not do them)
func is_director_change() -> bool:
	return _effect_depth > 0

## Drain queued flag changes. Effects set flags while this runs; they queue and are handled in order
func _process_queue() -> void:
	if _processing:
		return
	_processing = true
	var steps = 0
	while not _flag_queue.is_empty():
		steps += 1
		if steps > cascade_limit:
			cascade_overflows += 1
			push_warning("[StorylineDirector] Flag cascade exceeded %d steps; dropping %d queued changes" % [cascade_limit, _flag_queue.size()])
			_flag_queue.clear()
			break
		var change = _flag_queue.pop_front()
		var turned_true = change.flag if change.value == true else ""
		if turned_true != "":
			_apply_drift(turned_true)
			_check_life_failures(turned_true)
		_evaluate_beats(turned_true)
		_check_endings()
	_processing = false

func _evaluate_beats(turned_true: String) -> void:
	for sid in _storyline_order:
		for beat in _storylines[sid].beats:
			if not beat is Dictionary:
				continue
			var key = _beat_key(sid, str(beat.get("id", "")))
			if _resolved.has(key):
				continue
			if _blocked.has(key):
				# Blocked: only hooks able to unlock this beat may be queued (_enqueue filters)
				if turned_true != "":
					_enqueue_hooks(sid, beat, "on_flag:" + turned_true)
				continue
			if _opened.has(key):
				if turned_true != "":
					_enqueue_hooks(sid, beat, "on_flag:" + turned_true)
			elif _requirements_hold(beat.get("requires", [])):
				_opened[key] = true
				_open_counter += 1
				_opened_seq[key] = _open_counter
				print("[StorylineDirector] Beat opened: %s" % key)
				beat_opened.emit(sid, beat.id)
				_enqueue_hooks(sid, beat, "on_open")
				# on_flag hooks whose flag was already true when the beat opened queue now, or never would
				for hook in beat.get("hooks", []):
					var trigger = str(hook.get("trigger", "")) if hook is Dictionary else ""
					if trigger.begins_with("on_flag:") and _flag(trigger.substr(8)):
						_enqueue(sid, beat, hook, trigger)
			else:
				continue
			# on_flag hooks queue ahead of the resolution's on_resolve hooks
			if not _blocked.has(key) and not _resolved.has(key) and _any_flag_true(beat.get("resolves_on", [])):
				_resolve_beat(sid, beat)

func _resolve_beat(sid: String, beat: Dictionary) -> void:
	var key = _beat_key(sid, beat.id)
	_resolved[key] = true
	print("[StorylineDirector] Beat resolved: %s" % key)
	beat_resolved.emit(sid, beat.id)
	# Authored resolution effects belong to the storyline, not an NPC: vocabulary-checked, no soul gate
	for effect in beat.get("on_resolve", []):
		var checked = _effects.validate(effect)
		if not checked.ok:
			push_warning("[StorylineDirector] %s on_resolve effect dropped: %s" % [key, checked.reason])
			continue
		var result = _apply_effect_as_director(checked.effect, "", {"storyline": sid, "beat": beat.id})
		if not result.ok:
			push_warning("[StorylineDirector] %s on_resolve effect failed: %s" % [key, result.reason])
	_enqueue_hooks(sid, beat, "on_resolve")

func _check_endings() -> void:
	for sid in _storyline_order:
		if _endings.has(sid):
			continue
		# File order: the first ending whose requires all hold is the one reached (at most one)
		for ending in _storylines[sid].endings:
			var requires = ending.get("requires", []) if ending is Dictionary else []
			if requires.is_empty() or not _requirements_hold(requires):
				continue
			_endings[sid] = str(ending.id)
			print("[StorylineDirector] Ending reached: %s/%s" % [sid, ending.id])
			_register_world_event("%s came to an end: %s" % [_storylines[sid].get("title", sid), ending.get("summary", ending.get("title", ending.id))], ["all"])
			ending_reached.emit(sid, str(ending.id))
			break

# =============================================================================
# STORY CLOCK (rounds pace NPC decisions)
# =============================================================================

## Ask for a round at the end of this frame. Several boundaries in one frame make one round
## Ignored during boot and when round_boundaries_enabled is false
func request_round(reason: String) -> void:
	if not _booted or not round_boundaries_enabled:
		return
	_round_reasons.append(reason)
	if _round_requested:
		return
	_round_requested = true
	call_deferred("_run_requested_round")

func _run_requested_round() -> void:
	if _in_round:
		_rerun_round = true  # a decision is still awaiting Claude; run again when it finishes
		return
	_round_requested = false
	var reason = ", ".join(_round_reasons)
	_round_reasons.clear()
	if _time_rounds_owed > 0:
		_time_rounds_owed -= 1
	await advance_round(reason)
	if _time_rounds_owed > 0:
		request_round("game_time")  # a long journey owes the world several rounds, one per frame

## The game clock moved: due delayed effects land, and every MINUTES_PER_ROUND minutes owes a round
func _on_time_advanced(minutes: int, _total_minutes: int, reason: String) -> void:
	_run_scheduled_effects()
	_emergence.check_resolutions()
	var owed = add_game_minutes(minutes)
	if owed > 0:
		request_round("game_time:+%dm (%s)" % [minutes, reason])

## Count game minutes toward story rounds. Returns how many new rounds they owe
func add_game_minutes(minutes: int) -> int:
	if minutes <= 0:
		return 0
	_minutes_toward_round += minutes
	var owed = floori(_minutes_toward_round / float(MINUTES_PER_ROUND))
	_minutes_toward_round -= owed * MINUTES_PER_ROUND
	_time_rounds_owed = mini(_time_rounds_owed + owed, MAX_TIME_ROUNDS)
	return owed

## Rounds still owed by game time, and minutes counted toward the next one
func get_time_round_state() -> Dictionary:
	return {"owed": _time_rounds_owed, "minutes_toward_round": _minutes_toward_round}

## One round: queue idle hooks, then decide up to decisions_per_round_per_storyline queued hooks
## per storyline, oldest first. Hooks their effects trigger join the queue for later rounds
## Returns the chronicle entries made
func advance_round(reason: String = "manual") -> Array:
	if _in_round:
		_rerun_round = true
		return []
	_in_round = true
	_round += 1
	if not TimeWindowScript.is_open(_now()):
		# Opening hours (world.json): nobody acts anywhere; queued hooks wait for the world to open
		_in_round = false
		if _round_timer and _round_timer.is_inside_tree():
			_round_timer.start()
		print("[StorylineDirector] Round %d (%s): the world is closed (opening hours); %d queued" % [_round, reason, _decision_queue.size()])
		round_completed.emit(_round, reason, [])
		return []
	_enqueue_idle_hooks()
	# Emergent beats: close what resolved, grow what the world now matches, queue idle hooks
	_emergence.check_resolutions()
	_emergence.evaluate_conditions()
	_emergence.enqueue_idle_hooks()
	var taken: Dictionary = {}
	var entries: Array = []
	for item in _ordered_queue():
		var sid: String = item.storyline
		if int(taken.get(sid, 0)) >= decisions_per_round_per_storyline:
			continue
		_dequeue(sid, item.hook)
		if _emergence.owns(sid):
			var was_proc = _processing
			_processing = true
			var made_emergent = await _emergence.decide(item)
			_processing = was_proc
			if not was_proc:
				_process_queue()
			if not made_emergent.is_empty():
				taken[sid] = int(taken.get(sid, 0)) + 1
				entries.append_array(made_emergent)
			continue
		var found = _find_hook(sid, item.hook)
		if found.is_empty() or not _may_fire(sid, found.beat, found.hook):
			continue  # stale: the hook is gone, or its beat was blocked meanwhile
		var was_processing = _processing
		_processing = true  # flags set by these effects evaluate after the decision, not mid-way
		var made = await _offer_hook(sid, found.beat, found.hook, item.trigger)
		_processing = was_processing
		if not was_processing:
			_process_queue()
		if made.is_empty():
			continue  # already acted (once), or nobody eligible is alive: costs no decision
		taken[sid] = int(taken.get(sid, 0)) + 1
		entries.append_array(made)
	# Personal phase: entries are chronicled and signalled (personal_round_completed), not returned,
	# so callers that count storyline decisions per round are unaffected
	if personal_turns_enabled:
		await run_personal_turns(reason)
	_in_round = false
	if _round_timer and _round_timer.is_inside_tree():
		_round_timer.start()  # the idle fallback counts from the last round
	print("[StorylineDirector] Round %d (%s): %d decisions, %d queued" % [_round, reason, entries.size(), _decision_queue.size()])
	round_completed.emit(_round, reason, entries)
	if _rerun_round:
		_rerun_round = false
		request_round("deferred")
	return entries

func set_round_seconds(seconds: float) -> void:
	if _round_timer:
		_round_timer.wait_time = max(seconds, 1.0)
		_round_timer.start()

func set_round_timer_paused(paused: bool) -> void:
	if _round_timer:
		_round_timer.paused = paused

func get_round() -> int:
	return _round

## Pending decisions, oldest first
func get_decision_queue() -> Array:
	return _decision_queue.duplicate(true)

# =============================================================================
# HOOKS AND DECISIONS
# =============================================================================

func _enqueue_hooks(sid: String, beat: Dictionary, trigger: String) -> void:
	for hook in beat.get("hooks", []):
		if hook is Dictionary and str(hook.get("trigger", "")) == trigger:
			_enqueue(sid, beat, hook, trigger)

## Queue a hook for a later round (deduplicated by storyline + hook)
func _enqueue(sid: String, beat: Dictionary, hook: Dictionary, trigger: String) -> void:
	var hook_id = str(hook.get("id", ""))
	if not _may_fire(sid, beat, hook):
		return
	if hook.get("once", true) != false and _hook_acts.has(_beat_key(sid, hook_id)):
		return
	for item in _decision_queue:
		if item.storyline == sid and item.hook == hook_id:
			return
	_decision_queue.append({"storyline": sid, "beat": str(beat.get("id", "")), "hook": hook_id, "trigger": trigger, "queued_round": _round})
	decision_queued.emit(sid, hook_id)

func _dequeue(sid: String, hook_id: String) -> void:
	for i in _decision_queue.size():
		if _decision_queue[i].storyline == sid and _decision_queue[i].hook == hook_id:
			_decision_queue.remove_at(i)
			return

## Idle hooks of open (and blocked, for unlockers) beats are offered once per round
func _enqueue_idle_hooks() -> void:
	for sid in _storyline_order:
		for beat in _storylines[sid].beats:
			if beat is Dictionary and get_beat_status(sid, str(beat.get("id", ""))) in ["open", "blocked"]:
				_enqueue_hooks(sid, beat, "idle")

## A blocked beat's hooks do not fire, except hooks with an option that unlocks that same beat
## (checked per hook, so a beat blocked mid-way through its on_open hooks stops the rest)
func _may_fire(sid: String, beat: Dictionary, hook: Dictionary) -> bool:
	var beat_id = str(beat.get("id", ""))
	if not _blocked.has(_beat_key(sid, beat_id)):
		return true
	for option in hook.get("options", []):
		if not option is Dictionary:
			continue
		for effect in option.get("effects", []):
			if effect is Dictionary and effect.get("type") == "unlock_beat" \
					and str(effect.get("storyline", "")) == sid and str(effect.get("beat", "")) == beat_id:
				return true
	return false

## Offer a hook to its eligible NPCs in order. First to act wins unless stack: true
## once (default true) stops a hook from being offered again after someone acted
func _offer_hook(sid: String, beat: Dictionary, hook: Dictionary, trigger: String, only_npc: String = "", force: bool = false) -> Array:
	var hook_key = _beat_key(sid, str(hook.get("id", "")))
	if not force and hook.get("once", true) != false and _hook_acts.has(hook_key):
		return []
	var entries: Array = []
	for eligible in hook.get("eligible", []):
		var npc_key = str(eligible)
		if only_npc != "" and npc_key != only_npc:
			continue
		if not _is_npc_alive(npc_key):
			continue
		hook_offered.emit(sid, str(hook.id), npc_key)
		var soul = _souls.get(npc_key)
		_agent.mode = agency_mode
		if agency_mode == "claude":
			_agent.client = _get_claude_client()
		var decision = await _agent.decide(soul, hook, {
			"storyline_title": _storylines[sid].get("title", sid),
			"beat_title": beat.get("title", ""),
		})
		var entry = _carry_out(sid, beat, hook, trigger, npc_key, soul, decision)
		entries.append(entry)
		if entry.choice != "pass":
			_hook_acts[hook_key] = int(_hook_acts.get(hook_key, 0)) + 1
			if hook.get("stack", false) != true:
				break
	return entries

## Re-check and apply a decision's effects, then chronicle it
## Checks: (a) the effect came from the chosen option (or is a freeform_effects type),
## (b) the soul's Agency grants it at this hook type, (c) no Lines-I-Will-Not-Cross rule forbids it
## ORDER GUARANTEE (authors rely on it): an option's effects apply one by one in array order.
## Callers (advance_round, fire_hook) hold _processing, so each set_flag changes WorldState at once
## (EventBus/EventPropagator see the changes in that order) while beat evaluation waits: the queued
## flag changes are then evaluated in the same order, so a set_flag earlier in the array opens beats
## and queues on_flag:<flag> hooks before a later one does. on_resolve effects and conversation
## actions follow the same rule
func _carry_out(sid: String, beat: Dictionary, hook: Dictionary, trigger: String, npc_key: String, soul, decision: Dictionary) -> Dictionary:
	var hook_type = str(hook.get("type", ""))
	var applied: Array = []
	var dropped: Array = []
	var scheduled: Array = []
	var choice = str(decision.get("choice", "pass"))
	# An option done at a time of day (`"when"`, e.g. "after dark"): decided now, carried out when the
	# window next opens, through the scheduled effects (saved, and validated again when they land)
	var when = str(decision.get("option", {}).get("when", "")) if decision.get("option") is Dictionary else ""
	var act_at = TimeWindowScript.next_open_and_in(when if when != "" else "any", _now())
	var option_denial = ""
	if soul and not decision.get("option", {}).is_empty():
		option_denial = soul.get_option_denial_reason(decision.option)

	for effect in decision.get("effects", []):
		var checked = _effects.validate(effect)
		if not checked.ok:
			dropped.append({"effect": effect, "reason": checked.reason})
			continue
		var e: Dictionary = checked.effect
		var denial = option_denial
		if denial == "" and choice == "freeform" and e.type not in hook.get("freeform_effects", []):
			denial = "%s is not in this hook's freeform_effects" % e.type
		if denial == "":
			denial = soul.get_denial_reason(hook_type, e) if soul else "no SOUL.md for this NPC"
		if denial != "":
			dropped.append({"effect": e, "reason": denial})
			continue
		var chained = trigger.begins_with("on_flag:") and _flag_player_chain.get(trigger.substr(8), false) == true
		if act_at > _now():
			_schedule_effect(act_at, e, npc_key, {"storyline": sid, "hook": str(hook.id), "player_chain": chained},
				"%s, %s" % [str(decision.get("option", {}).get("label", "")), when])
			scheduled.append({"effect": e, "at": act_at})
			continue
		var result = _apply_effect_as_director(e, npc_key, {"storyline": sid, "hook": str(hook.id), "player_chain": chained})
		if result.ok:
			applied.append(e)
		else:
			dropped.append({"effect": e, "reason": result.reason})

	_seq += 1
	var entry = {
		"seq": _seq,
		"round": _round,
		"time": Time.get_unix_time_from_system(),
		"storyline": sid,
		"beat": str(beat.get("id", "")),
		"hook": str(hook.get("id", "")),
		"hook_type": hook_type,
		"trigger": trigger,
		"npc": npc_key,
		"mode": decision.get("mode", "offline"),
		"fallback_reason": decision.get("fallback_reason", ""),
		"choice": choice,
		"label": str(decision.get("option", {}).get("label", "")),
		"reason": str(decision.get("reason", "")),
		"applied": applied,
		"dropped": dropped,
		"scheduled": scheduled,  # effects waiting for the option's time of day ({effect, at})
	}
	_chronicle.append(entry)
	if _chronicle.size() > MAX_CHRONICLE:
		_chronicle = _chronicle.slice(_chronicle.size() - MAX_CHRONICLE)

	print("[StorylineDirector] %s at %s/%s: %s (%d applied, %d dropped)%s" % [
		npc_key, sid, entry.hook, choice, applied.size(), dropped.size(),
		" [fallback: %s]" % entry.fallback_reason if entry.fallback_reason != "" else ""])
	var npc_id = _npc_id(npc_key)
	if choice == "pass":
		_register_world_event("%s let the moment pass (%s)" % [_display_name(npc_key), _storylines[sid].get("title", sid)], [npc_id])
	else:
		var what = entry.label if entry.label != "" else "acted on their own"
		_register_world_event("%s chose: %s (%s)" % [_display_name(npc_key), what, _storylines[sid].get("title", sid)], [npc_id])
	decision_recorded.emit(entry)
	if choice != "pass":
		npc_acted.emit(entry)
	return entry

## Offer one hook right now, ignoring its trigger, beat state and once (debug console, tests)
## npc_key limits the offer to one eligible NPC. Returns the chronicle entries made
func fire_hook(storyline_id: String, hook_id: String, npc_key: String = "") -> Array:
	var found = _find_hook(storyline_id, hook_id)
	if found.is_empty():
		return []
	var was_processing = _processing
	_processing = true  # flags set by these effects evaluate after the decision, not mid-way
	var entries = await _offer_hook(storyline_id, found.beat, found.hook, "manual", _npc_key(npc_key) if npc_key != "" else "", true)
	_processing = was_processing
	if not was_processing:
		await _process_queue()
	return entries

## The player's own choice sets a storyline-declared flag (a pledge, a promise) that no NPC can
## Refuses flags no loaded storyline declares. Chronicled with actor "player"
## Returns {"ok": bool, "reason": String}
func player_choice(flag_name: String) -> Dictionary:
	if not _declared_flags.has(flag_name):
		return {"ok": false, "reason": "'%s' is not a storyline-declared flag" % flag_name}
	var sid: String = _declared_flags[flag_name]
	var effect = {"type": "set_flag", "flag": flag_name, "value": true}
	_seq += 1
	var entry = {
		"seq": _seq, "round": _round, "time": Time.get_unix_time_from_system(), "storyline": sid, "beat": "", "hook": "",
		"hook_type": "", "trigger": "player", "npc": "player", "mode": "player", "fallback_reason": "",
		"choice": "player_choice", "label": StoryFlags.get_flag_description(flag_name), "reason": "the player chose it",
		"applied": [effect], "dropped": [],
	}
	_chronicle.append(entry)
	if _chronicle.size() > MAX_CHRONICLE:
		_chronicle = _chronicle.slice(_chronicle.size() - MAX_CHRONICLE)
	print("[StorylineDirector] player chose %s (%s)" % [flag_name, sid])
	_register_world_event(StoryFlags.get_flag_description(flag_name), ["player"])
	decision_recorded.emit(entry)
	var result = _effects.apply(effect, "player", {"storyline": sid})  # untagged: the player's change
	request_round("player_choice:" + flag_name)
	return {"ok": result.ok, "reason": result.reason}

## Validate and apply one effect with no soul gate (authored content, debug, tests)
## Returns {"ok": bool, "reason": String}
func apply_effect(effect: Dictionary, actor_key: String = "") -> Dictionary:
	var checked = _effects.validate(effect)
	if not checked.ok:
		return {"ok": false, "reason": checked.reason}
	return _apply_effect_as_director(checked.effect, actor_key, {})

## Effects the Director applies are tagged so their flag changes are not taken for the player's
func _apply_effect_as_director(effect: Dictionary, actor_key: String, source: Dictionary) -> Dictionary:
	_effect_depth += 1
	var previous_actor = _current_actor
	var previous_causal = _causal_player
	_current_actor = actor_key
	_causal_player = previous_causal or source.get("player_chain", false) == true or source.get("conversation", false) == true
	var result = _effects.apply(effect, actor_key, source)
	_current_actor = previous_actor
	_causal_player = previous_causal
	_effect_depth -= 1
	return result

# =============================================================================
# EFFECT TARGETS (called by EffectApplier)
# =============================================================================

func set_beat_blocked(storyline_id: String, beat_id: String, blocked: bool) -> void:
	var key = _beat_key(storyline_id, beat_id)
	if blocked == _blocked.has(key):
		return
	if blocked:
		_blocked[key] = true
	else:
		_blocked.erase(key)
	print("[StorylineDirector] Beat %s: %s" % ["blocked" if blocked else "unlocked", key])
	beat_block_changed.emit(storyline_id, beat_id, blocked)
	if not blocked:
		# An unlocked beat may open or resolve on flags that are already true
		_flag_queue.append({"flag": "", "value": null})
		_process_queue()

func shift_want(npc_key: String, want_id: String, delta: int) -> bool:
	var soul = get_soul(npc_key)
	return soul != null and soul.shift_want(want_id, clampi(delta, -3, 3))

## Feelings toward the player: live, initialized NPCs change now; others get it on initialize()
func apply_relationship_delta(npc_key: String, dimension: String, delta: int) -> void:
	var reached = false
	for npc in get_loaded_npcs(npc_key):
		if npc.get("_is_initialized") and npc.has_method("apply_relationship_delta"):
			npc.apply_relationship_delta(dimension, delta)
			reached = true
	if not reached:
		var queued: Dictionary = _pending_relationships.get(npc_key, {})
		queued[dimension] = clampi(int(queued.get(dimension, 0)) + delta, -100, 100)
		_pending_relationships[npc_key] = queued

## Called by BaseNPC at the end of initialize(), next to EventPropagator.deliver_pending()
func deliver_pending(npc: Node) -> void:
	var key = _npc_key(npc.npc_id)
	if not _pending_relationships.has(key) or not npc.has_method("apply_relationship_delta"):
		return
	var queued: Dictionary = _pending_relationships[key]
	_pending_relationships.erase(key)
	for dimension in queued:
		npc.apply_relationship_delta(dimension, int(queued[dimension]))

func get_pending_relationships(npc_key: String) -> Dictionary:
	return _pending_relationships.get(_npc_key(npc_key), {}).duplicate()

# =============================================================================
# AGENDAS (raised by the NPC in its next conversation)
# =============================================================================

func add_agenda(npc_key: String, text: String, from_npc: String = "", source: Dictionary = {}) -> void:
	var list: Array = _agendas.get(npc_key, [])
	for agenda in list:
		if agenda.text == text and agenda.status != "done":
			return
	_agenda_seq += 1
	list.append({
		"id": "agenda_%d" % _agenda_seq,
		"text": text,
		"from": from_npc,
		"storyline": source.get("storyline", ""),
		"hook": source.get("hook", ""),
		"status": "pending",  # pending -> raised (in a conversation's prompt) -> done (conversation ended)
	})
	_agendas[npc_key] = list

## Agendas not yet done (pending or raised). Accepts an npc key or npc_id
func get_agendas(npc: String, include_done: bool = false) -> Array:
	var result = []
	for agenda in _agendas.get(_npc_key(npc), []):
		if include_done or agenda.status != "done":
			result.append(agenda.duplicate())
	return result

## The NPC replied with its agendas in the prompt: they count as raised in this conversation
func mark_agendas_raised(npc: String) -> void:
	for agenda in _agendas.get(_npc_key(npc), []):
		if agenda.status == "pending":
			agenda.status = "raised"

## The conversation ended: agendas raised in it are done. Returns how many
func complete_raised_agendas(npc: String) -> int:
	var count = 0
	for agenda in _agendas.get(_npc_key(npc), []):
		if agenda.status == "raised":
			agenda.status = "done"
			count += 1
	return count

## Soul + agenda block for the conversation system prompt (ContextBuilder injects it)
func get_conversation_block(npc: String) -> String:
	var block = ""
	var soul = get_soul(npc)
	if soul:
		block += soul.get_conversation_prompt_block()
	var open = get_agendas(npc)
	if not open.is_empty():
		block += "## WHAT YOU MEAN TO RAISE WITH THE PLAYER\n"
		block += "You decided these on your own. Work them into this conversation naturally, in your own words:\n"
		for agenda in open:
			block += "- %s\n" % agenda.text
		block += "\n"
	return block

# =============================================================================
# TRAVEL (move_npc really moves NPCs: gone while on the road, then at the destination)
# =============================================================================

## Where an NPC is, or is headed while travelling: WorldState npc_states, else its world.json home
func get_npc_location(npc: String) -> String:
	var key = _npc_key(npc)
	var world_state = _world_state()
	if world_state and world_state.has_method("get_npc_location"):
		var location = str(world_state.get_npc_location(_npc_id(key)))
		if location != "":
			return location
	var registry = _registry()
	var home = registry.get_npc_home(key) if registry else ""
	if home == "" and _registered.has(key):
		home = str(_registered[key].get("home", ""))
	return home

func is_npc_attending(npc: String) -> bool:
	var world_state = _world_state()
	return world_state != null and world_state.has_method("is_npc_attending") and world_state.is_npc_attending(_npc_id(_npc_key(npc)))

func is_npc_travelling(npc: String) -> bool:
	var world_state = _world_state()
	return world_state != null and world_state.has_method("is_npc_travelling") and world_state.is_npc_travelling(_npc_id(_npc_key(npc)))

## A beat's location ("" when it names none)
func get_beat_location(storyline_id: String, beat_id: String) -> String:
	return str(_find_beat(storyline_id, beat_id).get("location", ""))

## Send an NPC along the roads now: absent everywhere for the travel time, then at the destination
## An NPC already travelling finishes its current leg first. Returns {"ok", "reason", "minutes"}
func send_npc(npc: String, location: String) -> Dictionary:
	var key = _npc_key(npc)
	var npc_id = _npc_id(key)
	var registry = _registry()
	var world_state = _world_state()
	var from = get_npc_location(key)
	var minutes = 0
	if from != location and is_npc_attending(key):
		return {"ok": false, "reason": "attending: %s cannot leave %s until the gathering ends" % [key, from], "minutes": 0}
	if world_state and world_state.has_method("is_npc_travelling") and world_state.is_npc_travelling(npc_id):
		var travel: Dictionary = world_state.get_npc_travel(npc_id)
		from = str(travel.get("to", from))
		minutes = maxi(int(travel.get("arrive", 0)) - int(world_state.get_game_minutes()), 0)
	if registry and from != "" and from != location and registry.has_location(from):
		var leg = int(registry.travel_minutes(from, location))
		if leg < 0:
			return {"ok": false, "reason": "place: %s cannot be reached from %s on the roads" % [location, from], "minutes": 0}
		minutes += leg
	# Opening hours: a journey that would arrive while the world is closed leaves later, so it arrives
	# at opening. The move is scheduled and lands (and is chronicled) then
	var depart = TimeWindowScript.departure_for_open_arrival(_now(), minutes)
	if depart > _now():
		_schedule_effect(depart, {"type": "move_npc", "npc": key, "location": location}, key, {"opening_hours": true}, "waits for opening hours")
		print("[StorylineDirector] %s will set off for %s at minute %d (arrives at opening)" % [key, location, depart])
		return {"ok": true, "reason": "", "minutes": minutes, "scheduled_at": depart}
	if world_state and world_state.has_method("start_npc_travel"):
		world_state.start_npc_travel(npc_id, location, minutes, from)
	for live in get_loaded_npcs(key):
		if live.has_method("move_to_location"):
			live.move_to_location(location)
		elif "current_location" in live:
			live.current_location = location
	print("[StorylineDirector] %s sets off: %s -> %s (%d min)" % [key, from, location, minutes])
	var scene_manager = get_node_or_null("/root/SceneManager") if is_inside_tree() else null
	if scene_manager and scene_manager.has_method("refresh_npcs"):
		scene_manager.refresh_npcs()
	return {"ok": true, "reason": "", "minutes": minutes}

# =============================================================================
# CONVERSATION AGENCY (docs/WORLD_SCHEMA.md §6-7)
# Dialogue stays free-form: Claude decides what the NPC says and whether it acts. This only
# tells it what is plausible and enforces plausibility rules 1-7 on what comes back
# =============================================================================

## What this NPC could plausibly do while talking, right now:
## {"npc", "location", "beats": [{storyline, beat, title, summary, location, minutes, status, hooks}],
##  "involved": {"sid/beat": true}, "flags": {flag: {storyline, beat, resolves, location}},
##  "player_flags": {flag: {storyline, beat, text}}, "places": [{location, name, minutes}]}
func get_conversation_reach(npc: String) -> Dictionary:
	var key = _npc_key(npc)
	var here = get_npc_location(key)
	var reach = {"npc": key, "location": here, "beats": [], "involved": {}, "flags": {}, "player_flags": {}, "places": []}
	for sid in _storyline_order:
		var storyline: Dictionary = _storylines[sid]
		var player_flags: Array = storyline.get("player_flags", [])
		for beat in storyline.beats:
			if not beat is Dictionary:
				continue
			var beat_id = str(beat.get("id", ""))
			var status = get_beat_status(sid, beat_id)
			if status != "open" and status != "blocked":
				continue
			var beat_location = str(beat.get("location", ""))
			var minutes = _minutes_between(here, beat_location)
			var hooks: Array = []
			for hook in beat.get("hooks", []):
				if hook is Dictionary and key in hook.get("eligible", []) and _may_fire(sid, beat, hook):
					hooks.append(hook)
			var involved = not hooks.is_empty()
			var near = beat_location == "" or (minutes >= 0 and minutes <= NEAR_MINUTES)
			if status == "open":
				for raw_flag in beat.get("resolves_on", []):
					var flag = str(raw_flag)
					if flag in player_flags:
						if not _flag(flag) and not reach.player_flags.has(flag):
							reach.player_flags[flag] = {"storyline": sid, "beat": beat_id, "text": StoryFlags.get_flag_description(flag)}
					elif (involved or near) and not reach.flags.has(flag) and not _is_player_deed(flag) and not is_personal_flag(flag):
						reach.flags[flag] = {"storyline": sid, "beat": beat_id, "resolves": true, "location": beat_location}
				for hook in hooks:
					for option in hook.get("options", []):
						for effect in (option.get("effects", []) if option is Dictionary else []):
							if effect is Dictionary and effect.get("type") == "set_flag":
								var option_flag = str(effect.get("flag", ""))
								if option_flag != "" and not _is_player_flag(option_flag) and not reach.flags.has(option_flag) and not is_personal_flag(option_flag):
									reach.flags[option_flag] = {"storyline": sid, "beat": beat_id, "resolves": _resolves_open_beat(option_flag), "location": beat_location}
			if involved:
				reach.involved[_beat_key(sid, beat_id)] = true
				reach.beats.append({"storyline": sid, "beat": beat_id, "title": str(beat.get("title", beat_id)),
					"summary": str(beat.get("summary", "")), "location": beat_location, "minutes": minutes, "status": status, "hooks": hooks})
	var registry = _registry()
	if registry and registry.has_location(here):
		var reachable: Dictionary = registry.get_reachable(here)
		var neighbours = registry.get_neighbours(here).map(func(edge): return edge.location)
		var ids = reachable.keys()
		ids.sort_custom(func(a, b):
			var na = a in neighbours
			var nb = b in neighbours
			if na != nb:
				return na
			return int(reachable[a]) < int(reachable[b]))
		for id in ids.slice(0, MAX_PLACES_LISTED):
			reach.places.append({"location": id, "name": registry.get_location_name(id), "minutes": int(reachable[id])})
	return reach

## Compact effect shapes for the conversation block (K = an npc key)
const CONVERSE_SHAPES = {
	"agenda": '{"type":"agenda","npc":K,"text":"<=160 chars"}',
	"adjust_relationship": '{"type":"adjust_relationship","npc":K,"dimension":"trust|respect|affection|fear|familiarity","delta":-20..20}',
	"set_flag": '{"type":"set_flag","flag":F,"value":true}',
	"spread_rumor": '{"type":"spread_rumor","flag":F,"to":[K] or ["*"],"via":"how it travels"}',
	"move_npc": '{"type":"move_npc","npc":K,"location":L}',
	"shift_want": '{"type":"shift_want","npc":K,"want":W,"delta":-3..3}',
	"block_beat": '{"type":"block_beat","storyline":S,"beat":B}',
	"unlock_beat": '{"type":"unlock_beat","storyline":S,"beat":B}',
	"shift_fixed_point": '{"type":"shift_fixed_point","point":P,"days":-3..3 or "cancel":true,"reason":"why, in-world"}',
	"spread_event": '{"type":"spread_event","event":E,"to":[K] or ["*"],"via":"how it travels"}',
}
## Trade actions answer the player's own ask in conversation (docs/PLAYER_SYSTEMS.md §2): any soul may
## make them where they apply (it holds the player's pack; the ask is its trade), and its Lines
## (hook:converse, effect:<type>) still refuse them. Asked, demanded or offered coin, the NPC decides:
## a thief may give the pack back, sell it, refuse or deny it (no action); a teacher may teach for coin
## or a favour, or not. price is in the smallest coin (Inventory.spend_coin)
const TRADE_ACTIONS = ["return_pack", "teach"]
const TRADE_SHAPES = {
	"return_pack": '{"type":"return_pack","price":N}',
	"teach": '{"type":"teach","skill":S,"price":N} or {"type":"teach","skill":S,"favour":true}',
}
## Hard budget for the agency block (~4 chars per token). Caps tighten level by level until it fits
const AGENCY_BLOCK_CHAR_BUDGET = 3400
const AGENCY_CAP_LEVELS = [
	{"beats": MAX_BEATS_DETAILED, "options": MAX_OPTIONS_PER_BEAT, "named": MAX_BEATS_NAMED, "flags": MAX_FLAGS_LISTED, "commit": MAX_COMMITMENTS_LISTED, "places": MAX_PLACES_LISTED},
	{"beats": 2, "options": 2, "named": 4, "flags": 6, "commit": 3, "places": 6},
	{"beats": 2, "options": 1, "named": 3, "flags": 5, "commit": 2, "places": 5},
	{"beats": 1, "options": 1, "named": 2, "flags": 4, "commit": 2, "places": 4},
]

## The per-turn "what you can do" block for the conversation system prompt ("" without a SOUL.md)
## Beats, options, flags and commitments are ranked by relevance to this conversation and capped,
## so the block stays under AGENCY_BLOCK_CHAR_BUDGET however many storylines are open
func get_conversation_agency_block(npc: String) -> String:
	var key = _npc_key(npc)
	var soul = get_soul(key)
	if soul == null:
		return ""
	var reach = get_conversation_reach(key)
	var ranked: Array = _rank_beats(soul, reach)
	var flags: Array = _rank_flags(soul, reach, ranked)
	var committable: Array = _rank_player_flags(reach)
	var block = ""
	for caps in AGENCY_CAP_LEVELS:
		block = _build_agency_block(key, soul, reach, ranked, flags, committable, caps)
		if block.length() <= AGENCY_BLOCK_CHAR_BUDGET:
			break
	return block

func _build_agency_block(key: String, soul, reach: Dictionary, ranked: Array, flags: Array, committable: Array, caps: Dictionary) -> String:
	var registry = _registry()
	var here: String = reach.location
	var world_state = _world_state()
	var block = "## WHAT YOU CAN DO, NOT JUST SAY\n"
	if registry and registry.has_location(here):
		block += "You are at %s (%s, %s)" % [registry.get_location_name(here), registry.get_area(here), registry.get_region_name(registry.get_region(here))]
		block += (", %s.\n" % world_state.get_time_string()) if world_state and world_state.has_method("get_time_string") else ".\n"
		block += "The world: %s\n" % " ".join(registry.get_world_rules())
	var grants: Array = soul.get_converse_grants()
	var trade = _trade_block(key, soul)
	if grants.is_empty():
		block += "You act through words alone right now: leave \"actions\" empty%s.\n" % (" except as below" if trade != "" else "")
	else:
		block += "Answer however you truly would. Only if what was said moves you to act, add \"actions\" (at most %d, usually none), using only these shapes:\n" % CONVERSATION_ACTION_BUDGET
		for effect_type in grants:
			if CONVERSE_SHAPES.has(effect_type):
				block += "- %s\n" % CONVERSE_SHAPES[effect_type]
		if not ranked.is_empty():
			block += "What is unfolding that you have a hand in (ideas, not a menu):\n"
			for beat in ranked.slice(0, caps.beats):
				var where = ""
				if beat.location != "" and beat.location != here and registry:
					where = " [%s, %s]" % [registry.get_location_name(beat.location), _format_minutes(int(beat.minutes))]
				block += "- %s%s: %s\n" % [beat.title, where, _clip(beat.summary, 100)]
				for option in _top_options(soul, beat.hooks).slice(0, caps.options):
					var effects: Array = option.get("effects", []).map(func(e): return _describe_effect(e))
					block += "  · %s%s\n" % [_clip(str(option.get("label", "")), 64), (" (" + "; ".join(effects) + ")") if not effects.is_empty() else ""]
			var named: Array = ranked.slice(caps.beats, caps.beats + caps.named).map(func(b): return b.title)
			var more = ranked.size() - caps.beats - named.size()
			if not named.is_empty() or more > 0:
				block += "Also in play: %s%s\n" % ["; ".join(named), (" (+%d more)" % more) if more > 0 else ""]
		if "set_flag" in grants and not flags.is_empty():
			var hidden = flags.size() - caps.flags
			block += "set_flag may only name: %s%s\n" % [", ".join(flags.slice(0, caps.flags)), (" (+%d less pressing)" % hidden) if hidden > 0 else ""]
		if "move_npc" in grants and not reach.places.is_empty():
			block += "Places you could go (you leave when this talk ends; road time): %s\n" % ", ".join(reach.places.slice(0, caps.places).map(func(p): return "%s %s" % [p.location, _format_minutes(p.minutes)]))
		var people: Array = []
		if registry:
			for other in registry.get_npcs_in_region(registry.get_region(here)):
				if other != key:
					people.append("%s (%s%s)" % [other, registry.get_npc_name(other), ", here" if get_npc_location(other) == here and not is_npc_travelling(other) else ""])
		if not people.is_empty():
			block += "People by key: %s\n" % ", ".join(people)
		block += "Nothing happens instantly at a distance: word to someone far away arrives when a rider could carry it.\n"
	block += trade
	if not committable.is_empty():
		block += "If the player GENUINELY commits to one of these (not a joke, not a lie you saw through), put its id in \"commitments\":\n"
		for flag in committable.slice(0, caps.commit):
			block += "- %s: %s\n" % [flag, _clip(reach.player_flags[flag].text, 90)]
	return block + "\n"

## What this NPC could do for the player's own ask (TRADE_ACTIONS), or "" when nothing applies
func _trade_block(key: String, soul) -> String:
	var lines: Array = []
	var inv = get_node_or_null("/root/Inventory")
	if inv and inv.has_method("packs_held_by") and soul.get_trade_denial_reason({"type": "return_pack"}) == "":
		var held: Array = inv.packs_held_by(key)
		if not held.is_empty():
			var how = "took" if held.any(func(p): return str(p.get("state", "")) == "taken") else "kept"
			lines.append("You %s the stranger's pack where they fell. Only if you choose to give it back (asked, demanded or bought), add %s (N = what you ask, 0 for nothing). You may refuse or deny it instead." % [how, TRADE_SHAPES.return_pack])
	var teaching = _teaching()
	if teaching and soul.get_trade_denial_reason({"type": "teach"}) == "":
		var offers: Array = []
		for skill in teaching.trades_of(key):
			if teaching.lesson_denial(key, str(skill)) == "":
				var cost = int(teaching.usual_cost(key, str(skill)))
				offers.append("%s (your usual fee N=%d, %s)" % [skill, cost, _coin_text(cost)])
		if not offers.is_empty():
			lines.append("You could teach the stranger %s; a lesson takes %s. Only if you choose to, add %s." % [", ".join(offers), _format_minutes(int(teaching.lesson_minutes())), TRADE_SHAPES.teach])
	return "" if lines.is_empty() else "\n".join(lines) + "\n"

## A trade action, checked against the soul's Lines and the world, then done.
## Returns {ok, reason, effect} (effect carries what happened: packs back, lesson)
func _apply_trade_action(key: String, soul, raw: Dictionary) -> Dictionary:
	var e: Dictionary = raw.duplicate(true)
	var out = {"ok": false, "reason": "", "effect": e}
	if soul == null:
		out.reason = "soul: no SOUL.md for %s" % key
		return out
	var denial = soul.get_trade_denial_reason(e)
	if denial != "":
		out.reason = "soul: " + denial
		return out
	var inv = get_node_or_null("/root/Inventory")
	var price = 0
	var priced = e.has("price")
	if priced:
		if not (e.price is int or e.price is float) or int(e.price) < 0:
			out.reason = "vocabulary: price is a whole number of coin, 0 or more"
			return out
		price = int(e.price)
	e["price"] = price
	match str(e.type):
		"return_pack":
			if inv == null or not inv.has_method("packs_held_by") or inv.packs_held_by(key).is_empty():
				out.reason = "truth: %s holds no pack of the player's" % key
				return out
			if price > 0 and not inv.spend_coin(price):
				out.reason = "coin: the player cannot pay %d" % price
				return out
			e["packs"] = inv.recover_from(key, "sold" if price > 0 else "given")
		"teach":
			var teaching = _teaching()
			var skill = str(e.get("skill", "")).strip_edges().to_lower()
			e["skill"] = skill
			if teaching == null:
				out.reason = "no teaching"
				return out
			var why = teaching.lesson_denial(key, skill)
			if why != "":
				out.reason = "teach: " + why
				return out
			var favour = e.get("favour", false) == true
			if not priced and not favour:
				price = int(teaching.usual_cost(key, skill))
				e["price"] = price
			var lesson: Dictionary = teaching.give_lesson(key, skill, "favour" if favour else "coin", 0 if favour else price)
			if not lesson.ok:
				out.reason = "teach: " + str(lesson.reason)
				return out
			e["favour"] = favour
			e["minutes"] = int(lesson.minutes)
	out.ok = true
	out.effect = e
	print("[StorylineDirector] %s: %s" % [key, e])
	return out

func _teaching():
	var stats = get_node_or_null("/root/PlayerStats")
	return stats.get_teaching() if stats and stats.has_method("get_teaching") else null

## Coin as the purse names it (Inventory.format_coin)
func _coin_text(amount: int) -> String:
	var inv = get_node_or_null("/root/Inventory")
	return str(inv.format_coin(amount)) if inv and inv.has_method("format_coin") else str(amount)

## Committable player flags, the beats nearest this NPC (then most recent) first
func _rank_player_flags(reach: Dictionary) -> Array:
	var flags: Array = reach.player_flags.keys()
	var scores: Dictionary = {}
	for flag in flags:
		var info: Dictionary = reach.player_flags[flag]
		scores[flag] = _beat_relevance(str(info.storyline), str(info.beat), get_beat_location(str(info.storyline), str(info.beat)), reach.location) \
			+ (40.0 if reach.involved.has(_beat_key(str(info.storyline), str(info.beat))) else 0.0)
	flags.sort_custom(func(a, b): return scores[a] > scores[b])
	return flags

## Beats this NPC has hooks in, most relevant to this conversation first (each gets a "score"):
## at its location > within walking reach > nearer; options serving its top wants; recently opened
func _rank_beats(soul, reach: Dictionary) -> Array:
	var top_wants: Array = soul.get_top_wants(3) if soul else []
	var ranked: Array = []
	for beat in reach.beats:
		var score = _beat_relevance(beat.storyline, beat.beat, beat.location, reach.location)
		var best = 0
		for hook in beat.hooks:
			for option in hook.get("options", []):
				if option is Dictionary:
					best = maxi(best, _option_score(soul, option, top_wants))
		score += best
		if beat.status == "blocked":
			score -= 20
		ranked.append(beat.merged({"score": score}))
	ranked.sort_custom(func(a, b): return a.score > b.score)
	return ranked

## Place and recency part of a beat's relevance
func _beat_relevance(sid: String, beat_id: String, location: String, here: String) -> float:
	var score = 0.0
	var minutes = _minutes_between(here, location)
	if location == "":
		score += 25.0
	elif location == here:
		score += 100.0
	elif minutes >= 0 and minutes <= NEAR_MINUTES:
		score += 50.0
	elif minutes >= 0 and minutes <= 180:
		score += 15.0
	if _open_counter > 0:
		score += 30.0 * float(_opened_seq.get(_beat_key(sid, beat_id), 0)) / float(_open_counter)
	return score

## Want weights the option serves, with a bonus for the soul's current top wants
func _option_score(soul, option: Dictionary, top_wants: Array) -> int:
	if soul == null:
		return 0
	var serves: Array = option.get("serves", [])
	var score = soul.score_wants(serves)
	for want in serves:
		if str(want) in top_wants:
			score += 10
	return score

## The options worth suggesting: those with effects first, highest soul score first
func _top_options(soul, hooks: Array) -> Array:
	var top_wants: Array = soul.get_top_wants(3) if soul else []
	var options: Array = []
	for hook in hooks:
		for option in hook.get("options", []):
			if option is Dictionary and not option.get("effects", []).is_empty() and soul.get_option_denial_reason(option) == "":
				options.append(option)
	options.sort_custom(func(a, b): return _option_score(soul, a, top_wants) > _option_score(soul, b, top_wants))
	return options.slice(0, MAX_OPTIONS_PER_BEAT)

## In-reach flags, those of the highest-ranked beats first
func _rank_flags(soul, reach: Dictionary, ranked: Array) -> Array:
	var beat_scores: Dictionary = {}
	for beat in ranked:
		beat_scores[_beat_key(beat.storyline, beat.beat)] = float(beat.score)
	var scores: Dictionary = {}
	for flag in reach.flags:
		var info: Dictionary = reach.flags[flag]
		var beat_key = _beat_key(str(info.storyline), str(info.beat))
		scores[flag] = beat_scores.get(beat_key, _beat_relevance(str(info.storyline), str(info.beat), str(info.location), reach.location)) + (5.0 if info.resolves else 0.0)
	var flags: Array = reach.flags.keys()
	flags.sort_custom(func(a, b): return scores[a] > scores[b])
	return flags

## Enforce plausibility rules 1-7 (docs/WORLD_SCHEMA.md §6) on one NPC reply and apply what passes
## actions: effect dicts the NPC chose; commitments: player flags it heard the player genuinely commit to
## Valid actions apply now, a move when the conversation ends (finish_conversation), and an effect
## aimed far away when word could get there (game clock). Everything else is dropped with a reason
## context (optional): {"said": the NPC's reply, "player": what the player said}
## Returns {"applied": Array, "dropped": [{"effect", "reason"}], "entry": the chronicle entry ({} if nothing to record)}
func apply_conversation_actions(npc: String, actions: Array, commitments: Array = [], context: Dictionary = {}) -> Dictionary:
	var key = _npc_key(npc)
	var soul = get_soul(key)
	var reach = get_conversation_reach(key)  # one snapshot: the world as it was when the NPC spoke
	var applied: Array = []
	var dropped: Array = []
	var storylines: Array = []
	var resolving = 0
	var was_processing = _processing
	_processing = true  # flags these actions set evaluate together afterwards
	var index = 0
	for raw in actions:
		index += 1
		if index > CONVERSATION_ACTION_BUDGET:
			dropped.append({"effect": raw, "reason": "budget: at most %d actions per reply" % CONVERSATION_ACTION_BUDGET})
			continue
		if raw is Dictionary and str(raw.get("type", "")) in TRADE_ACTIONS:
			var traded = _apply_trade_action(key, soul, raw)
			if traded.ok:
				applied.append(traded.effect)
			else:
				dropped.append({"effect": traded.effect, "reason": traded.reason})
			continue
		var verdict = _check_conversation_action(key, soul, raw, reach, resolving)
		if not verdict.ok:
			dropped.append({"effect": verdict.effect, "reason": verdict.reason})
			continue
		var e: Dictionary = verdict.effect
		if verdict.resolves:
			resolving += 1
		if verdict.storyline != "" and verdict.storyline not in storylines:
			storylines.append(verdict.storyline)
		var source = {"conversation": true, "storyline": verdict.storyline}
		if verdict.when == "conversation_end":
			var moves: Array = _pending_moves.get(key, [])
			moves.append({"npc": str(e.npc), "location": str(e.location), "minutes": int(verdict.minutes)})
			_pending_moves[key] = moves
			applied.append(e.merged({"when": "conversation_end", "minutes": int(verdict.minutes)}))
			continue
		if verdict.when == "now":
			var result = _apply_effect_as_director(e, key, source)
			if result.ok:
				applied.append(e)
			else:
				dropped.append({"effect": e, "reason": result.reason})
		for part in verdict.later:
			_schedule_effect(int(part.at), part.effect, key, source, str(part.note))
			applied.append(part.effect.merged({"when": "game_minute %d" % int(part.at), "note": str(part.note)}))

	var committed = 0
	for raw_flag in commitments:
		var flag = str(raw_flag).strip_edges()
		if _is_personal_help_id(flag):
			# The player promised to help with this NPC's own life (player: helps|needed steps)
			var help_item = {"type": "personal_help", "flag": flag.trim_prefix("help:")}
			var help_reason = get_personal_help_denial(key, flag)
			if help_reason == "" and committed >= MAX_COMMITMENTS:
				help_reason = "budget: at most %d commitments per reply" % MAX_COMMITMENTS
			if help_reason != "":
				dropped.append({"effect": help_item, "reason": help_reason})
				continue
			_mark_personal_help(key, flag)
			committed += 1
			applied.append(help_item)
			continue
		var item = {"type": "commitment", "flag": flag}
		var reason = _commitment_denial(flag, reach)
		if reason == "" and committed >= MAX_COMMITMENTS:
			reason = "budget: at most %d commitments per reply" % MAX_COMMITMENTS
		if reason != "":
			dropped.append({"effect": item, "reason": reason})
			continue
		var result = player_choice(flag)
		if result.ok:
			committed += 1
			applied.append(item)
			var sid = str(reach.player_flags[flag].storyline)
			if sid not in storylines:
				storylines.append(sid)
		else:
			dropped.append({"effect": item, "reason": "commitment: " + str(result.reason)})
	_processing = was_processing
	if not was_processing:
		_process_queue()

	var entry: Dictionary = {}
	if not actions.is_empty() or not commitments.is_empty():
		entry = _chronicle_conversation(key, "conversation", applied, dropped, storylines, context)
	return {"applied": applied, "dropped": dropped, "entry": entry}

## The conversation ended: moves the NPC decided on now set off (finish_conversation is called by BaseNPC)
## Returns [{"npc", "location", "ok", "reason", "minutes"}]
func finish_conversation(npc: String) -> Array:
	var key = _npc_key(npc)
	_emergence.check_resolutions(key)  # talked_to:<role> resolves when that conversation ends
	var moves: Array = _pending_moves.get(key, [])
	_pending_moves.erase(key)
	var results: Array = []
	var applied: Array = []
	var dropped: Array = []
	for move in moves:
		var effect = {"type": "move_npc", "npc": str(move.npc), "location": str(move.location)}
		var result = send_npc(effect.npc, effect.location) if not is_npc_travelling(effect.npc) else {"ok": false, "reason": "place: %s is already on the road" % effect.npc, "minutes": 0}
		results.append({"npc": effect.npc, "location": effect.location, "ok": result.ok, "reason": result.reason, "minutes": int(result.minutes)})
		if result.ok:
			applied.append(effect.merged({"minutes": int(result.minutes)}))
		else:
			dropped.append({"effect": effect, "reason": result.reason})
	if not moves.is_empty():
		_chronicle_conversation(key, "conversation_end", applied, dropped, [], {})
	return results

## Moves decided in a conversation still waiting for it to end
func get_pending_moves(npc: String = "") -> Dictionary:
	if npc != "":
		return {_npc_key(npc): _pending_moves.get(_npc_key(npc), []).duplicate(true)}
	return _pending_moves.duplicate(true)

## Effects on their way to somewhere far, soonest first
func get_scheduled_effects() -> Array:
	var copy = _scheduled.duplicate(true)
	copy.sort_custom(func(a, b): return int(a.at) < int(b.at))
	return copy

## Player flags an NPC can recognise as a commitment right now (rule 5)
## Returns {flag: {storyline, beat, text}}; npc "" = any NPC (open beats only)
func get_committable_player_flags(npc: String = "") -> Dictionary:
	if npc != "":
		return get_conversation_reach(npc).player_flags
	var result: Dictionary = {}
	for sid in _storyline_order:
		var player_flags: Array = _storylines[sid].get("player_flags", [])
		for beat in _storylines[sid].beats:
			if not beat is Dictionary or get_beat_status(sid, str(beat.get("id", ""))) != "open":
				continue
			for flag in beat.get("resolves_on", []):
				if str(flag) in player_flags and not _flag(str(flag)):
					result[str(flag)] = {"storyline": sid, "beat": str(beat.id), "text": StoryFlags.get_flag_description(str(flag))}
	return result

## Every storyline's player_flags, and whether conversation can reach each one (debug, reports)
## [{flag, storyline, in_resolves_on: [beat ids], status}] status: "committable" | "waiting" | "done" | "not in resolves_on"
func get_player_flag_report() -> Array:
	var committable = get_committable_player_flags()
	var report: Array = []
	for sid in _storyline_order:
		for flag in _storylines[sid].get("player_flags", []):
			var beats: Array = []
			for beat in _storylines[sid].beats:
				if beat is Dictionary and str(flag) in beat.get("resolves_on", []):
					beats.append(str(beat.id))
			var status = "committable" if committable.has(str(flag)) else ("done" if _flag(str(flag)) else ("waiting" if not beats.is_empty() else "not in resolves_on"))
			report.append({"flag": str(flag), "storyline": sid, "in_resolves_on": beats, "status": status})
	return report

## One action against rules 1-4 and 7. Returns {"ok", "reason", "effect", "when": "now"|"conversation_end"|"later",
## "minutes", "later": [{at, effect, note}], "resolves", "storyline"}
func _check_conversation_action(key: String, soul, raw, reach: Dictionary, resolving: int) -> Dictionary:
	var verdict = {"ok": false, "reason": "", "effect": raw, "when": "now", "minutes": 0, "later": [], "resolves": false, "storyline": ""}
	if not raw is Dictionary:
		verdict.reason = "vocabulary: an action must be an effect object"
		return verdict
	var effect: Dictionary = raw.duplicate(true)
	if str(effect.get("type", "")) in ["agenda", "move_npc", "shift_want", "adjust_relationship"] and str(effect.get("npc", "")) == "":
		effect["npc"] = key  # "I will..." without naming anyone means the speaker
	verdict.effect = effect
	# Rule 1: vocabulary, the soul's converse grants, its lines
	var checked = _effects.validate(effect)
	if not checked.ok:
		verdict.reason = "vocabulary: " + checked.reason
		return verdict
	var e: Dictionary = checked.effect
	verdict.effect = e
	if soul == null:
		verdict.reason = "soul: no SOUL.md for %s" % key
		return verdict
	var denial = soul.get_converse_denial_reason(e)
	if denial == "" and (str(e.type) in STORY_ONLY_EFFECTS or str(e.type) == "shift_fixed_point") and get_soul_tier(key) in ["promoted", "generic"]:
		denial = "%s souls act at personal scope only (no %s)" % [get_soul_tier(key), e.type]
	if denial == "":
		denial = _suggested_option_denial(soul, e, reach)
	if denial != "":
		verdict.reason = "soul: " + denial
		return verdict
	_sanitise_effect_text(e)  # rule 6, last line of defence (BaseNPC already regenerated once)

	var here: String = reach.location
	var target = ""  # where the effect lands (rule 4)
	match str(e.type):
		"set_flag":
			# Rule 2: flags in reach only; player flags are commitments, never set_flag
			if _is_player_flag(e.flag):
				verdict.reason = "reach: '%s' is the player's own choice; report a genuine promise in commitments" % e.flag
				return verdict
			if not reach.flags.has(e.flag):
				verdict.reason = "reach: '%s' is not in reach (no open beat near %s or with a hook for %s resolves on it or offers it)" % [e.flag, here, key]
				return verdict
			if _flag(e.flag) == e.value:
				verdict.reason = "no change: '%s' is already %s" % [e.flag, e.value]
				return verdict
			var info: Dictionary = reach.flags[e.flag]
			verdict.storyline = str(info.storyline)
			verdict.resolves = e.value == true and _resolves_open_beat(e.flag)
			if verdict.resolves and resolving >= 1:
				verdict.reason = "budget: only one beat-resolving set_flag per reply"
				return verdict
			target = str(info.location)
		"spread_rumor":
			# Rule 3: rumors carry only what happened
			if not _flag(e.flag):
				verdict.reason = "truth: '%s' is not true; rumors carry only what happened" % e.flag
				return verdict
			return _split_rumor(key, e, here, verdict)
		"agenda", "adjust_relationship", "shift_want":
			if str(e.npc) != key:
				target = get_npc_location(e.npc)
		"move_npc":
			# Rule 4: reachable on the roads; the speaker, or someone standing here; leaves at conversation end
			var mover = str(e.npc)
			if is_npc_travelling(mover):
				verdict.reason = "place: %s is already on the road" % mover
				return verdict
			var from = get_npc_location(mover)
			if mover != key and from != here:
				verdict.reason = "place: %s is not here (at %s); send word with an agenda instead" % [mover, from]
				return verdict
			if from == str(e.location):
				verdict.reason = "place: %s is already at %s" % [mover, e.location]
				return verdict
			for moves in _pending_moves.values():
				for move in moves:
					if str(move.npc) == mover:
						verdict.reason = "place: %s is already leaving for %s" % [mover, move.location]
						return verdict
			var minutes = _minutes_between(from, str(e.location))
			if minutes < 0:
				verdict.reason = "place: %s cannot be reached from %s on the roads" % [e.location, from]
				return verdict
			verdict.ok = true
			verdict.when = "conversation_end"
			verdict.minutes = minutes
			return verdict
		"block_beat", "unlock_beat":
			var beat_key = _beat_key(str(e.storyline), str(e.beat))
			if not reach.involved.has(beat_key):
				verdict.reason = "reach: %s is not a beat %s has a hand in" % [beat_key, key]
				return verdict
			verdict.storyline = str(e.storyline)
			target = get_beat_location(str(e.storyline), str(e.beat))
	return _place_in_time(e, here, target, verdict)

## Rule 4 for one effect: near lands now; far lands when a rider could carry word there
func _place_in_time(e: Dictionary, here: String, target: String, verdict: Dictionary) -> Dictionary:
	var minutes = _minutes_between(here, target)
	if minutes < 0:
		verdict.reason = "place: word cannot reach %s from %s" % [target, here]
		return verdict
	verdict.ok = true
	if target != "" and minutes > NEAR_MINUTES:
		verdict.when = "later"
		verdict.later = [{"at": _now() + minutes, "effect": e, "note": "word reaches %s after %s" % [target, _format_minutes(minutes)]}]
	return verdict

## Rumors: "*" means the speaker's own region, now; named listeners nearby hear it now, far ones later
func _split_rumor(key: String, e: Dictionary, here: String, verdict: Dictionary) -> Dictionary:
	var now_to: Array = []
	var later: Array = []
	for listener in e.to:
		if listener == "*" or listener == key:
			now_to.append(listener)
			continue
		var minutes = _minutes_between(here, get_npc_location(listener))
		if minutes >= 0 and minutes <= NEAR_MINUTES:
			now_to.append(listener)
		elif minutes > NEAR_MINUTES:
			later.append({"at": _now() + minutes, "effect": e.merged({"to": [listener]}, true), "note": "word reaches %s after %s" % [listener, _format_minutes(minutes)]})
	verdict.ok = true
	verdict.later = later
	if now_to.is_empty():
		verdict.when = "later_only"
	else:
		verdict.effect = e.merged({"to": now_to}, true)
	return verdict

## Rule 5. "" when the commitment stands
func _commitment_denial(flag: String, reach: Dictionary) -> String:
	if flag == "":
		return "commitment: empty flag"
	if not _is_player_flag(flag):
		return "commitment: '%s' is not a player flag" % flag if is_known_flag(flag) else "commitment: unknown flag '%s'" % flag
	if _flag(flag):
		return "commitment: '%s' was already made" % flag
	if not reach.player_flags.has(flag):
		return "commitment: no open beat waits on '%s' (its beat is closed or not open yet)" % flag
	return ""

## Option-level lines (ally:, harm:) apply when an action matches a suggested option's effect
func _suggested_option_denial(soul, e: Dictionary, reach: Dictionary) -> String:
	for beat in reach.beats:
		for hook in beat.hooks:
			for option in hook.get("options", []):
				if not option is Dictionary:
					continue
				for effect in option.get("effects", []):
					if effect is Dictionary and _same_effect(effect, e):
						var denial = soul.get_option_denial_reason(option)
						if denial != "":
							return denial
	return ""

func _same_effect(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("type", "")) != str(b.get("type", "")):
		return false
	for field in ["flag", "npc", "location", "storyline", "beat", "text"]:
		if a.has(field) and str(a[field]) != str(b.get(field, "")):
			return false
	return true

func _sanitise_effect_text(e: Dictionary) -> void:
	var registry = _registry()
	if registry == null:
		return
	for field in ["text", "via"]:
		if e.has(field) and registry.contains_forbidden_concept(str(e[field])):
			e[field] = registry.sanitize_forbidden(str(e[field]))

## A flag whose canon says the player did it ("The player discovered...", base or discovery flags):
## only the player's own deeds set it, so an NPC can reach it only through an option it is offered
func _is_player_deed(flag: String) -> bool:
	if StoryFlags.is_discovery_flag(flag):
		return true
	return StoryFlags.get_flag_description(flag).strip_edges().to_lower().begins_with("the player")

func _is_player_flag(flag: String) -> bool:
	for sid in _storyline_order:
		if flag in _storylines[sid].get("player_flags", []):
			return true
	return false

func _resolves_open_beat(flag: String) -> bool:
	for sid in _storyline_order:
		for beat in _storylines[sid].beats:
			if beat is Dictionary and flag in beat.get("resolves_on", []) and get_beat_status(sid, str(beat.get("id", ""))) == "open":
				return true
	return false

## Shortest road minutes between two places (0 when either is unknown or they are the same, -1 unreachable)
func _minutes_between(a: String, b: String) -> int:
	var registry = _registry()
	if a == "" or b == "" or a == b or registry == null or not registry.has_location(a) or not registry.has_location(b):
		return 0
	return int(registry.travel_minutes(a, b))

func _schedule_effect(at: int, effect: Dictionary, actor_key: String, source: Dictionary, note: String) -> void:
	_scheduled.append({"at": at, "effect": effect.duplicate(true), "actor": actor_key, "source": source.duplicate(true), "note": note})

## Delayed effects whose word has arrived land now (called when the game clock moves)
func _run_scheduled_effects() -> void:
	var now = _now()
	if not TimeWindowScript.is_open(now):
		return  # opening hours: they land when the world opens
	var due: Array = []
	var waiting: Array = []
	for item in _scheduled:
		(due if int(item.at) <= now else waiting).append(item)
	if due.is_empty():
		return
	_scheduled = waiting
	due.sort_custom(func(a, b): return int(a.at) < int(b.at))
	var was_processing = _processing
	_processing = true
	for item in due:
		var applied: Array = []
		var dropped: Array = []
		var checked = _effects.validate(item.effect)
		if not checked.ok:
			dropped.append({"effect": item.effect, "reason": "vocabulary: " + checked.reason})
		elif checked.effect.type == "spread_rumor" and not _flag(checked.effect.flag):
			dropped.append({"effect": checked.effect, "reason": "truth: '%s' is no longer true" % checked.effect.flag})
		else:
			var result = _apply_effect_as_director(checked.effect, str(item.actor), item.source)
			if result.ok:
				applied.append(checked.effect)
			else:
				dropped.append({"effect": checked.effect, "reason": result.reason})
		var sid = str(item.source.get("storyline", ""))
		_chronicle_conversation(str(item.actor), "word_arrived", applied, dropped, [sid] if sid != "" else [], {"said": str(item.note)})
	_processing = was_processing
	if not was_processing:
		_process_queue()

func _chronicle_conversation(key: String, trigger: String, applied: Array, dropped: Array, storylines: Array, context: Dictionary) -> Dictionary:
	_seq += 1
	var entry = {
		"seq": _seq,
		"round": _round,
		"time": Time.get_unix_time_from_system(),
		"game_minutes": _now(),
		"storyline": ", ".join(storylines),
		"beat": "",
		"hook": "",
		"hook_type": "converse",
		"trigger": trigger,
		"npc": key,
		"location": get_npc_location(key),
		"mode": "conversation",
		"fallback_reason": "",
		"choice": "acted" if not applied.is_empty() else ("dropped" if not dropped.is_empty() else "none"),
		"label": _clip(str(context.get("said", "")), 160),
		"reason": _clip(str(context.get("player", "")), 160),
		"applied": applied.duplicate(true),
		"dropped": dropped.duplicate(true),
	}
	_chronicle.append(entry)
	if _chronicle.size() > MAX_CHRONICLE:
		_chronicle = _chronicle.slice(_chronicle.size() - MAX_CHRONICLE)
	print("[StorylineDirector] %s in conversation (%s): %d applied, %d dropped%s" % [key, trigger, applied.size(), dropped.size(),
		"" if dropped.is_empty() else " [%s]" % "; ".join(dropped.map(func(d): return d.reason))])
	decision_recorded.emit(entry)
	conversation_acted.emit(entry)
	return entry

func _describe_effect(e) -> String:
	if not e is Dictionary:
		return "?"
	match str(e.get("type", "")):
		"set_flag", "spread_rumor":
			return "%s %s" % [e.type, e.get("flag", "")]
		"move_npc":
			return "move_npc %s->%s" % [e.get("npc", ""), e.get("location", "")]
		"agenda", "adjust_relationship", "shift_want":
			return "%s %s" % [e.type, e.get("npc", "")]
	return str(e.get("type", ""))

func _format_minutes(minutes: int) -> String:
	if minutes < 60:
		return "%dm" % minutes
	if minutes < 24 * 60:
		return "%dh%s" % [floori(minutes / 60.0), ("%02d" % (minutes % 60)) if minutes % 60 != 0 else ""]
	return "%.1fd" % (minutes / 1440.0)

func _clip(text: String, max_chars: int) -> String:
	var flat = text.replace("\n", " ").strip_edges()
	return flat if flat.length() <= max_chars else flat.substr(0, max_chars - 3) + "..."

func _now() -> int:
	var world_state = _world_state()
	return int(world_state.get_game_minutes()) if world_state and world_state.has_method("get_game_minutes") else 0

func _world_state() -> Node:
	return get_node_or_null("/root/WorldState") if is_inside_tree() else null

# =============================================================================
# SOUL REGISTRATION (generics engine contract, docs/WORLD_BUILD_PLAN.md Phase 3)
# The 19 SOUL.md files are tier "main". Everyone else (generics, promoted generics) is registered
# here at runtime from soul text. Registered souls get the same conversation agency rules and soul
# checks as the authored ones (their tier limits them to personal-scope effects), and their Life
# flags are known flags.
#
# PERSISTENCE CONTRACT: this Director saves only RUNTIME state for registered souls (want weights,
# Life progress, tier) inside its save(). It does NOT save their soul text. The registrar persists
# the text (e.g. user://souls/<id>/SOUL.md) and calls register_soul() again after every load; the
# saved state is held until then and applied at that call. opts.tier given at re-registration wins
# over the saved tier.
# =============================================================================

## Register (or replace) a runtime soul. opts: {"tier": "main"|"promoted"|"generic" (default generic),
## "npc_id": String (default: the text's npc_id, else key), "home": location id (where it lives when
## WorldState has no location for it)}. The text goes through the Soul parser and must have at least
## one Want and a clean Life (validate_soul_text says why not). A key owned by a SOUL.md file is
## refused. Re-registering a key keeps its weights and Life progress where wants and arcs still match
## Returns true when registered
func register_soul(key: String, soul_text: String, opts: Dictionary = {}) -> bool:
	key = key.strip_edges().to_lower()
	var tier = str(opts.get("tier", _pending_soul_state.get(key, {}).get("tier", "generic"))).to_lower()
	if tier not in TIERS:
		push_warning("[StorylineDirector] register_soul(%s): unknown tier '%s'" % [key, tier])
		return false
	if _souls.has(key) and not _registered.has(key):
		push_warning("[StorylineDirector] register_soul(%s): that key belongs to a SOUL.md file" % key)
		return false
	var check = validate_soul_text(key, soul_text)
	if not check.ok:
		push_warning("[StorylineDirector] register_soul(%s) refused: %s" % [key, "; ".join(check.errors)])
		return false
	var carry: Dictionary = {}
	if _souls.has(key):
		carry = {"weights": _souls[key].get_weights(), "life": _souls[key].get_life_state()}
		_release_registered(key)
	_registered[key] = {"text": soul_text, "npc_id": str(opts.get("npc_id", "")), "tier": tier, "home": str(opts.get("home", ""))}
	if not _install_registered(key, carry):
		_registered.erase(key)
		return false
	print("[StorylineDirector] Soul registered: %s (%s, %d arcs)" % [key, tier, _souls[key].life_arcs.size()])
	soul_registered.emit(key, tier)
	return true

## Why register_soul would refuse this text: {"ok": bool, "errors": [String]}
func validate_soul_text(key: String, soul_text: String) -> Dictionary:
	key = key.strip_edges().to_lower()
	var errors: Array = []
	if key == "" or RegEx.create_from_string("^[a-z0-9_]+$").search(key) == null:
		errors.append("key '%s' must be lowercase letters, digits and _" % key)
		return {"ok": false, "errors": errors}
	var soul = Soul.from_text(soul_text, key, "registered:" + key)
	if soul == null:
		return {"ok": false, "errors": ["the text does not parse"]}
	if soul.wants.is_empty():
		errors.append("no Wants (need at least one `id` (weight): text line)")
	errors.append_array(soul.life_errors)
	for flag in soul.get_life_flags():
		var clash = _personal_flag_clash(flag, key)
		if clash != "":
			errors.append(clash)
	return {"ok": errors.is_empty(), "errors": errors}

## Remove a runtime soul (its Life flags stop being known flags). File souls cannot be removed
func unregister_soul(key: String) -> bool:
	key = key.strip_edges().to_lower()
	if not _registered.has(key):
		return false
	_release_registered(key)
	_registered.erase(key)
	_pending_soul_state.erase(key)
	print("[StorylineDirector] Soul unregistered: %s" % key)
	soul_unregistered.emit(key)
	return true

## Switch a soul's tier (promotion/demotion). Only main and promoted souls get personal turns.
## The authored souls are anchored at main: any other tier for them is refused
func set_soul_tier(key: String, tier: String) -> bool:
	key = _npc_key(key)
	tier = tier.strip_edges().to_lower()
	if tier not in TIERS or not _souls.has(key):
		return false
	if not _registered.has(key):
		return tier == "main"
	var old = str(_tiers.get(key, ""))
	if old == tier:
		return true
	_set_tier_quiet(key, tier)
	print("[StorylineDirector] Soul tier: %s %s -> %s" % [key, old, tier])
	soul_tier_changed.emit(key, old, tier)
	return true

## "main" | "promoted" | "generic", "" for a key with no soul
func get_soul_tier(key: String) -> String:
	return str(_tiers.get(_npc_key(key), ""))

func has_soul(key: String) -> bool:
	return _souls.has(_npc_key(key))

func is_registered_soul(key: String) -> bool:
	return _registered.has(_npc_key(key))

## key -> {"tier", "npc_id", "home"} for every runtime soul (text omitted: the registrar owns it)
func get_registered_souls() -> Dictionary:
	var result: Dictionary = {}
	for key in _registered:
		result[key] = {"tier": str(_tiers.get(key, _registered[key].tier)), "npc_id": _npc_id(key), "home": str(_registered[key].home)}
	return result

func _set_tier_quiet(key: String, tier: String) -> void:
	_tiers[key] = tier
	if _registered.has(key):
		_registered[key]["tier"] = tier

## Parse and install _registered[key]. carry (or saved pending state) restores weights and Life
func _install_registered(key: String, carry: Dictionary = {}) -> bool:
	var info: Dictionary = _registered[key]
	var soul = Soul.from_text(str(info.text), key, "registered:" + key)
	if soul == null:
		return false
	if str(info.npc_id) != "":
		soul.npc_id = str(info.npc_id)
	elif soul.npc_id == "":
		soul.npc_id = key
	_souls[key] = soul
	_tiers[key] = str(info.tier)
	_registered_ids[soul.npc_id.to_lower()] = key
	_claim_personal_flags(key)
	var state: Dictionary = carry if not carry.is_empty() else _pending_soul_state.get(key, {})
	_pending_soul_state.erase(key)
	if state.get("weights") is Dictionary:
		soul.set_weights(state.weights)
	if state.get("life") is Dictionary:
		soul.set_life_state(state.life)
	# Drift for flags that were already true when this soul arrived (guarded: once per key/flag/want)
	for rule in soul.drift:
		if _flag(rule.flag):
			var drift_key = "%s|%s|%s" % [key, rule.flag, rule.want]
			if not _drift_applied.has(drift_key):
				_drift_applied[drift_key] = true
				soul.shift_want(rule.want, rule.delta)
	return true

func _release_registered(key: String) -> void:
	var soul = _souls.get(key)
	if soul:
		_registered_ids.erase(soul.npc_id.to_lower())
	for flag in _personal_flags.keys():
		if _personal_flags[flag] == key:
			_personal_flags.erase(flag)
	_souls.erase(key)
	_tiers.erase(key)

## Make a soul's Life flags known flags with canon text. Arcs whose flags clash are dropped
func _claim_personal_flags(key: String) -> void:
	var soul = _souls.get(key)
	if soul == null:
		return
	for arc in soul.life_arcs.duplicate():
		var flags: Array = [arc.result.flag]
		for step in arc.steps:
			flags.append(step.flag)
		var clash = ""
		for flag in flags:
			clash = _personal_flag_clash(flag, key)
			if clash != "":
				break
		if clash != "":
			push_warning("[StorylineDirector] %s Life arc '%s' dropped: %s" % [key, arc.id, clash])
			soul.life_arcs.erase(arc)
			soul.life_errors.append("arc `%s`: %s" % [arc.id, clash])
			continue
		for flag in flags:
			_personal_flags[flag] = key
	StoryFlags.register_flag_descriptions(soul.get_life_flags())

## "" when a personal flag is free for this soul; else why it is not
func _personal_flag_clash(flag: String, key: String) -> String:
	if _declared_flags.has(flag):
		return "personal flag '%s' is a %s storyline flag" % [flag, _declared_flags[flag]]
	if StoryFlags.is_base_flag(flag):
		return "personal flag '%s' is a base story flag" % flag
	if _personal_flags.has(flag) and _personal_flags[flag] != key:
		return "personal flag '%s' already belongs to %s" % [flag, _personal_flags[flag]]
	return ""

func _pending(key: String) -> Dictionary:
	if not _pending_soul_state.has(key):
		_pending_soul_state[key] = {}
	return _pending_soul_state[key]

func _save_life() -> Dictionary:
	var life: Dictionary = {}
	for key in _pending_soul_state:  # registered souls not re-registered yet keep their saved progress
		if _pending_soul_state[key].get("life") is Dictionary:
			life[key] = _pending_soul_state[key].life.duplicate(true)
	for key in _souls:
		if _souls[key].has_life():
			life[key] = _souls[key].get_life_state()
	return life

func _save_registered_tiers() -> Dictionary:
	var tiers: Dictionary = {}
	for key in _pending_soul_state:
		if _pending_soul_state[key].has("tier"):
			tiers[key] = _pending_soul_state[key].tier
	for key in _registered:
		tiers[key] = str(_tiers.get(key, _registered[key].tier))
	return tiers

# =============================================================================
# PERSONAL TURNS (docs/WORLD_SCHEMA.md §8: Life is what an NPC pursues for itself)
# Each round, up to personal_decisions_per_round souls of tier main/promoted take a turn on their
# first available step: travel toward its `at` (real road time), or work it. A step completes after
# `takes` turns ("player: helps" halves that once the player promised help; "player: needed" waits
# for that promise). Completion sets <key>_<arc>_<step>; the last step also sets the arc's result.
# Personal effects are personal-scope only and never set a storyline flag; no storyline effect or
# conversation action may set a personal flag (EffectApplier refuses them)
# =============================================================================

## How many personal turns a round gives out: personal_decisions_per_round if >= 0, else world.json
## tiers.personal_decisions_per_round, else 4
func get_personal_decisions_per_round() -> int:
	if personal_decisions_per_round >= 0:
		return personal_decisions_per_round
	var registry = _registry()
	var world = registry.data if registry and "data" in registry and registry.data is Dictionary else {}
	var tiers = world.get("tiers", {})
	if tiers is Dictionary and (tiers.get("personal_decisions_per_round") is int or tiers.get("personal_decisions_per_round") is float):
		return maxi(int(tiers.personal_decisions_per_round), 0)
	return DEFAULT_PERSONAL_DECISIONS

## Where the player is: player_location_override, else SceneManager's current location ("" unknown)
func get_player_location() -> String:
	if player_location_override != "":
		return player_location_override
	var scene_manager = get_node_or_null("/root/SceneManager") if is_inside_tree() else null
	if scene_manager and scene_manager.has_method("get_current_location_id"):
		return str(scene_manager.get_current_location_id())
	return ""

func get_personal_round() -> int:
	return _personal_round

## One personal phase (advance_round runs it; debug life_round runs it alone)
## Returns the personal chronicle entries made, in turn order
func run_personal_turns(_reason: String = "") -> Array:
	if _in_personal:
		return []
	_in_personal = true
	_personal_round += 1
	_check_life_failures("")
	var cap = get_personal_decisions_per_round()
	var entries: Array = []
	for candidate in get_personal_candidates():
		if entries.size() >= cap:
			break
		var plan = _plan_personal_turn(str(candidate.npc))  # earlier turns may have changed the world
		if plan.is_empty():
			continue
		var was_processing = _processing
		_processing = true  # flags this turn sets evaluate after it, as with hook decisions
		var entry = await _take_personal_turn(plan)
		_processing = was_processing
		if not was_processing:
			_process_queue()
		entries.append(entry)
	_in_personal = false
	personal_round_completed.emit(_personal_round, entries)
	return entries

## Souls that could take a personal turn now, in priority order:
## 0. intention focus (InnerVoice.score_target of the step + pressure_for the NPC; 0 without thoughts)
## 1. at the player's location, then within NEAR_MINUTES of it, then everyone else
## 2. higher current weight of the want the active arc serves
## 3. longest waiting (oldest last turn; never = first)
## 4. key (stable)
## Each: {"npc", "arc", "step", "action": "work"|"travel", "minutes", "near": 0|1|2, "weight", "last_turn"}
func get_personal_candidates() -> Array:
	var player_at = get_player_location()
	var candidates: Array = []
	var keys = _souls.keys()
	keys.sort()
	for key in keys:
		var plan = _plan_personal_turn(key)
		if plan.is_empty():
			continue
		var here = get_npc_location(key)
		var near = 2
		if player_at != "" and here != "":
			if here == player_at:
				near = 0
			elif _registry() and _registry().has_location(here) and _registry().has_location(player_at):
				var minutes = _minutes_between(here, player_at)
				if minutes >= 0 and minutes <= NEAR_MINUTES:
					near = 1
		plan["near"] = near
		plan["weight"] = _souls[key].get_weight(str(plan.serves))
		plan["last_turn"] = _souls[key].get_last_personal_turn()
		plan["focus"] = _personal_focus(key, plan)
		candidates.append(plan)
	candidates.sort_custom(func(a, b):
		if not is_equal_approx(a.focus, b.focus):
			return a.focus > b.focus  # the player's intentions (InnerVoice) surface these first
		if a.near != b.near:
			return a.near < b.near
		if a.weight != b.weight:
			return a.weight > b.weight
		if a.last_turn != b.last_turn:
			return a.last_turn < b.last_turn
		return str(a.npc) < str(b.npc))
	return candidates

## What this soul would do with a personal turn now ({} = nothing: wrong tier, dead, on the road,
## Life done, or every step blocked). Its focus step wins when still available; otherwise the arc
## whose served want weighs most (file order on ties). Within an arc: its first available step
func _plan_personal_turn(key: String, any_tier: bool = false) -> Dictionary:
	var soul = _souls.get(key)
	if soul == null or not soul.has_life():
		return {}
	if not any_tier and str(_tiers.get(key, "generic")) not in TURN_TIERS:
		return {}
	if not _is_npc_alive(key) or is_npc_travelling(key):
		return {}
	var best: Dictionary = {}
	var focus: Dictionary = soul.get_life_focus()
	for arc in soul.life_arcs:
		if soul.get_arc_status(arc.id) != "active":
			continue
		var plan = _first_available_step(key, soul, arc)
		if plan.is_empty():
			continue
		if not focus.is_empty() and focus.arc == arc.id and focus.step == plan.step:
			return plan
		if best.is_empty() or soul.get_weight(arc.serves) > soul.get_weight(str(best.serves)):
			best = plan
	return best

func _first_available_step(key: String, soul, arc: Dictionary) -> Dictionary:
	for step in arc.steps:
		if soul.is_step_done(arc.id, step.id) or not soul.is_step_unlocked(arc.id, step):
			continue
		if not _requirements_hold(step.needs):
			continue
		if step.player == "needed" and not soul.is_step_helped(arc.id, step.id) \
				and soul.get_step_progress(arc.id, step.id) >= soul.get_effective_takes(arc.id, step.id):
			continue  # all the work it can do alone is done: it waits for the player's promise
		var place = _personal_place(key, str(step.at))
		if place.is_empty():
			continue
		if place.action == "travel" and is_npc_attending(key):
			continue  # held where they stand: a step here may still be taken
		if not _in_step_window(step, int(place.minutes)):
			continue  # not at this hour: people keep hours (SOUL.md `when`, waking hours by default)
		return {"npc": key, "arc": arc.id, "step": step.id, "serves": arc.serves, "action": place.action, "minutes": int(place.minutes)}
	return {}

## {"action": "work"|"travel", "minutes"} for a step's `at`, {} when it cannot get there
## The step's window holds at the hour the NPC would be there (now, plus any walk to it)
func _in_step_window(step: Dictionary, travel_minutes: int = 0) -> bool:
	var world_state = _world_state()
	if world_state == null or not world_state.has_method("get_game_minutes"):
		return true
	var arrive = int(world_state.get_game_minutes()) + travel_minutes
	var hour = floori((arrive % (24 * 60)) / 60.0)
	return TimeWindowScript.contains(str(step.get("when", "")), hour) and TimeWindowScript.is_open(arrive) \
		and TimeWindowScript.is_open(int(world_state.get_game_minutes()))  # setting off is acting too

func _personal_place(key: String, at: String) -> Dictionary:
	if at == "any":
		return {"action": "work", "minutes": 0}
	var here = get_npc_location(key)
	if here == at:
		return {"action": "work", "minutes": 0}
	var registry = _registry()
	if registry == null or here == "" or not registry.has_location(here) or not registry.has_location(at):
		return {}
	var minutes = int(registry.travel_minutes(here, at))
	return {} if minutes < 0 else {"action": "travel", "minutes": minutes}

func _take_personal_turn(plan: Dictionary) -> Dictionary:
	var key: String = plan.npc
	var soul = _souls[key]
	var arc: Dictionary = soul.get_arc(plan.arc)
	var step: Dictionary = soul.get_step(plan.arc, plan.step)
	soul.set_last_personal_turn(_personal_round)
	soul.set_life_focus(arc.id, step.id)
	if plan.action == "travel":
		var from = get_npc_location(key)
		var moved = send_npc(key, str(step.at))
		var effect = {"type": "move_npc", "npc": key, "location": str(step.at)}
		if moved.ok:
			return _chronicle_personal(key, arc, step, "travel", [effect.merged({"minutes": int(moved.minutes)})], [],
				"sets off from %s for %s (%s)" % [from, step.at, _format_minutes(int(moved.minutes))])
		return _chronicle_personal(key, arc, step, "travel", [], [{"effect": effect, "reason": moved.reason}], "could not set off")

	var progress = soul.add_step_progress(arc.id, step.id)
	var takes = soul.get_effective_takes(arc.id, step.id)
	if progress < takes:
		return _chronicle_personal(key, arc, step, "work", [], [], "%d of %d turns" % [progress, takes])
	if step.player == "needed" and not soul.is_step_helped(arc.id, step.id):
		return _chronicle_personal(key, arc, step, "waiting", [], [], "done all it can alone; needs the player's promise of help")

	# Complete: flags first (so a rumor of them is true), then the step's personal effects
	soul.mark_step_done(arc.id, step.id)
	_set_personal_flag(step.flag)
	var arc_done = soul.is_arc_finished(arc.id)
	if arc_done:
		soul.set_arc_status(arc.id, "completed")
		_set_personal_flag(arc.result.flag)
	var offline = _offline_personal_effects(key, soul, arc, step, arc_done)
	_agent.mode = agency_mode
	if agency_mode == "claude":
		_agent.client = _get_claude_client()
	var decision = await _agent.decide_personal(soul, arc, step, offline, {"location": get_npc_location(key), "people": _people_near(key)})
	var outcome = _apply_personal_effects(key, soul, arc, step, decision.effects)
	soul.set_life_focus("", "")
	var entry = _chronicle_personal(key, arc, step, "completed_arc" if arc_done else "completed_step", outcome.applied, outcome.dropped,
		str(decision.get("reason", "")), str(decision.get("mode", "offline")), str(decision.get("fallback_reason", "")))
	_register_world_event("%s finished something of their own: %s" % [_display_name(key), str(step.text)], [_npc_id(key)])
	personal_step_completed.emit(key, arc.id, step.id)
	if arc_done:
		_register_world_event(str(arc.result.text), [_npc_id(key)])
		print("[StorylineDirector] %s completed personal arc %s -> %s" % [key, arc.id, arc.result.flag])
		personal_arc_ended.emit(key, arc.id, "completed")
	return entry

## Personal flags are set only here, tagged as the Director's change (not the player's)
func _set_personal_flag(flag: String) -> void:
	if not _personal_flags.has(flag):
		push_warning("[StorylineDirector] refusing to set '%s': not a personal flag" % flag)
		return
	var world_state = _world_state()
	if world_state == null:
		world_state = get_node_or_null("/root/WorldState")
	if world_state == null:
		return
	_effect_depth += 1
	world_state.set_world_flag(flag, true)
	_effect_depth -= 1

## The deterministic default: one effect per type the step lists. agenda and adjust_relationship
## reach the NPC the step's text names (that is how a life crosses into another), else the NPC itself;
## adjust_relationship only when the player helped; shift_want strengthens the served want;
## spread_rumor carries the step's (or, on the last step, the arc's result) flag to the NPC's region.
## move_npc adds nothing: travel to `at` already happened
func _offline_personal_effects(key: String, soul, arc: Dictionary, step: Dictionary, arc_done: bool) -> Array:
	var other = _named_npc_in(str(step.text), key)
	var effects: Array = []
	for effect_type in step.effects:
		match effect_type:
			"agenda":
				var text = ("%s came to you about something of their own: %s" % [_display_name(key), step.text]) if other != "" \
					else "Mention, if it fits, what you have been doing for yourself: %s" % step.text
				effects.append({"type": "agenda", "npc": other if other != "" else key, "text": text})
			"adjust_relationship":
				if soul.is_step_helped(arc.id, step.id):
					effects.append({"type": "adjust_relationship", "npc": key, "dimension": "trust", "delta": 5})
			"shift_want":
				effects.append({"type": "shift_want", "npc": key, "want": arc.serves, "delta": 1})
			"spread_rumor":
				effects.append({"type": "spread_rumor", "flag": arc.result.flag if arc_done else step.flag, "to": ["*"], "via": "talk among neighbours"})
	return effects

## Check every personal effect (soul lines, the step's types, personal scope, vocabulary,
## plausibility rules 3-4) and apply what passes. Returns {"applied": Array, "dropped": Array}
func _apply_personal_effects(key: String, soul, arc: Dictionary, step: Dictionary, effects: Array) -> Dictionary:
	var applied: Array = []
	var dropped: Array = []
	var here = get_npc_location(key)
	var source = {"personal": true, "arc": arc.id, "step": step.id}
	var index = 0
	for raw in effects:
		index += 1
		if index > PERSONAL_ACTION_BUDGET:
			dropped.append({"effect": raw, "reason": "budget: at most %d effects per step" % PERSONAL_ACTION_BUDGET})
			continue
		if not raw is Dictionary:
			dropped.append({"effect": raw, "reason": "vocabulary: an effect must be an object"})
			continue
		var e: Dictionary = raw.duplicate(true)
		if str(e.get("type", "")) in ["agenda", "move_npc", "shift_want", "adjust_relationship"] and str(e.get("npc", "")) == "":
			e["npc"] = key
		if str(e.get("type", "")) in STORY_ONLY_EFFECTS:
			dropped.append({"effect": e, "reason": "personal scope: a life never changes the storyline (%s)" % e.type})
			continue
		var denial = soul.get_personal_denial_reason(e, step)
		if denial != "":
			dropped.append({"effect": e, "reason": "soul: " + denial})
			continue
		var checked = _effects.validate(e)
		if not checked.ok:
			dropped.append({"effect": e, "reason": "vocabulary: " + checked.reason})
			continue
		e = checked.effect
		_sanitise_effect_text(e)
		var verdict = {"ok": false, "reason": "", "effect": e, "when": "now", "minutes": 0, "later": [], "resolves": false, "storyline": ""}
		match str(e.type):
			"shift_want":
				if _npc_key(str(e.npc)) != key:
					dropped.append({"effect": e, "reason": "personal scope: a life shifts only its own wants"})
					continue
				verdict.ok = true
			"spread_rumor":
				if not _flag(str(e.flag)):
					dropped.append({"effect": e, "reason": "truth: '%s' is not true; rumors carry only what happened" % e.flag})
					continue
				verdict = _split_rumor(key, e, here, verdict)
			"move_npc":
				var mover = _npc_key(str(e.npc))
				var from = get_npc_location(mover)
				if is_npc_travelling(mover):
					dropped.append({"effect": e, "reason": "place: %s is already on the road" % mover})
					continue
				if mover != key and from != here:
					dropped.append({"effect": e, "reason": "place: %s is not here (at %s)" % [mover, from]})
					continue
				if _minutes_between(from, str(e.location)) < 0:
					dropped.append({"effect": e, "reason": "place: %s cannot be reached from %s on the roads" % [e.location, from]})
					continue
				verdict.ok = true
			"agenda", "adjust_relationship":
				var target = get_npc_location(str(e.npc)) if _npc_key(str(e.npc)) != key else ""
				verdict = _place_in_time(e, here, target, verdict)
		if not verdict.ok:
			dropped.append({"effect": e, "reason": verdict.reason})
			continue
		if verdict.when == "now":
			var result = _apply_effect_as_director(verdict.effect, key, source)
			if result.ok:
				applied.append(verdict.effect)
			else:
				dropped.append({"effect": verdict.effect, "reason": result.reason})
		for part in verdict.later:
			_schedule_effect(int(part.at), part.effect, key, source, str(part.note))
			applied.append(part.effect.merged({"when": "game_minute %d" % int(part.at), "note": str(part.note)}))
	return {"applied": applied, "dropped": dropped}

## fails_if: abandon active arcs (main/promoted souls) whose fail flag is true
## turned_true "" checks every flag; else only arcs listing that flag
func _check_life_failures(turned_true: String) -> void:
	var keys = _souls.keys()
	keys.sort()
	for key in keys:
		if str(_tiers.get(key, "")) not in TURN_TIERS:
			continue
		var soul = _souls[key]
		for arc in soul.life_arcs:
			if soul.get_arc_status(arc.id) != "active":
				continue
			for flag in arc.fails_if:
				if (turned_true == "" or flag == turned_true) and _flag(flag):
					_abandon_arc(key, soul, arc, flag)
					break

## Abandonment is remembered (chronicle, world event) and drifts the served want down by 1
func _abandon_arc(key: String, soul, arc: Dictionary, flag: String) -> void:
	soul.set_arc_status(arc.id, "failed")
	if not soul.get_life_focus().is_empty() and soul.get_life_focus().arc == arc.id:
		soul.set_life_focus("", "")
	var drifted = soul.shift_want(arc.serves, -1)
	var step = {"id": "", "text": "", "flag": ""}
	_chronicle_personal(key, arc, step, "abandoned", [], [], "%s came true%s" % [flag, ("; %s -1" % arc.serves) if drifted else ""])
	_register_world_event("%s gave up on something of their own (%s)" % [_display_name(key), StoryFlags.get_flag_description(flag) if StoryFlags.get_flag_description(flag) != "" else flag], [_npc_id(key)])
	print("[StorylineDirector] %s abandoned personal arc %s (%s)" % [key, arc.id, flag])
	personal_arc_ended.emit(key, arc.id, "failed")

# --- the player's help (conversation commitments and debug) -------------------

func _is_personal_help_id(flag: String) -> bool:
	return flag.begins_with("help:") or _personal_flags.has(flag)

## Why the player cannot promise help with this step of this NPC's life now ("" when they can)
## step_flag: "<key>_<arc>_<step>" or "help:<key>_<arc>_<step>"
func get_personal_help_denial(npc: String, step_flag: String) -> String:
	var key = _npc_key(npc)
	var flag = step_flag.strip_edges().trim_prefix("help:")
	if not _personal_flags.has(flag):
		return "commitment: unknown personal step '%s'" % flag
	if _personal_flags[flag] != key:
		return "commitment: '%s' belongs to %s's life, not %s's" % [flag, _personal_flags[flag], key]
	var soul = _souls.get(key)
	var found: Dictionary = soul.find_step_by_flag(flag) if soul else {}
	if found.is_empty():
		return "commitment: '%s' is an arc result, not a step" % flag
	var arc: Dictionary = found.arc
	var step: Dictionary = found.step
	if step.player == "":
		return "commitment: %s needs no help from the player" % step.id
	if soul.get_arc_status(arc.id) != "active":
		return "commitment: the arc %s is over (%s)" % [arc.id, soul.get_arc_status(arc.id)]
	if soul.is_step_done(arc.id, step.id):
		return "commitment: %s is already done" % step.id
	if not soul.is_step_unlocked(arc.id, step):
		return "commitment: not yet; %s comes after %s" % [step.id, step.after]
	if soul.is_step_helped(arc.id, step.id):
		return "commitment: the player already promised help with %s" % step.id
	return ""

## The player commits to helping (debug console, tests; conversation goes through
## apply_conversation_actions commitments). Returns {"ok": bool, "reason": String}
func commit_personal_help(npc: String, step_flag: String) -> Dictionary:
	var key = _npc_key(npc)
	var reason = get_personal_help_denial(key, step_flag)
	if reason != "":
		return {"ok": false, "reason": reason}
	var found = _mark_personal_help(key, step_flag)
	_chronicle_personal(key, found.arc, found.step, "help_committed", [{"type": "personal_help", "flag": found.step.flag}], [], "the player promised to help")
	return {"ok": true, "reason": ""}

func _mark_personal_help(key: String, step_flag: String) -> Dictionary:
	var soul = _souls[key]
	var found: Dictionary = soul.find_step_by_flag(step_flag)
	soul.mark_step_helped(found.arc.id, found.step.id)
	print("[StorylineDirector] the player promised to help %s with %s" % [key, found.step.flag])
	return found

## Steps of this NPC's life the player could promise to help with right now
func get_personal_help_offers(npc: String) -> Array:
	var key = _npc_key(npc)
	var soul = _souls.get(key)
	var offers: Array = []
	if soul == null:
		return offers
	for arc in soul.life_arcs:
		for step in arc.steps:
			if step.player != "" and get_personal_help_denial(key, step.flag) == "":
				offers.append({"flag": step.flag, "arc": arc.id, "step": step.id, "player": step.player, "text": step.text})
	return offers

## Everything about one soul's Life (debug console `life <npc>`, tests)
func get_life(npc: String) -> Dictionary:
	var key = _npc_key(npc)
	var soul = _souls.get(key)
	if soul == null:
		return {}
	return {"npc": key, "tier": get_soul_tier(key), "registered": _registered.has(key), "location": get_npc_location(key),
		"travelling": is_npc_travelling(key), "arcs": soul.life_to_debug(), "errors": soul.life_errors.duplicate(),
		"focus": soul.get_life_focus(), "last_turn": soul.get_last_personal_turn(), "plan": _plan_personal_turn(key),
		"help_offers": get_personal_help_offers(key)}

func _chronicle_personal(key: String, arc: Dictionary, step: Dictionary, choice: String, applied: Array, dropped: Array,
		reason: String, agent_mode: String = "offline", fallback_reason: String = "") -> Dictionary:
	_seq += 1
	var entry = {
		"seq": _seq,
		"round": _round,
		"personal_round": _personal_round,
		"time": Time.get_unix_time_from_system(),
		"game_minutes": _now(),
		"storyline": "",
		"beat": "",
		"hook": "%s/%s" % [arc.get("id", ""), step.get("id", "")] if str(step.get("id", "")) != "" else str(arc.get("id", "")),
		"hook_type": "personal",
		"trigger": "personal",
		"npc": key,
		"location": get_npc_location(key),
		"mode": "personal",
		"agent_mode": agent_mode,
		"fallback_reason": fallback_reason,
		"arc": str(arc.get("id", "")),
		"step": str(step.get("id", "")),
		"choice": choice,  # travel | work | waiting | completed_step | completed_arc | abandoned | help_committed
		"label": str(step.get("text", "")) if str(step.get("text", "")) != "" else str(arc.get("prose", "")).substr(0, 160),
		"reason": reason,
		"applied": applied.duplicate(true),
		"dropped": dropped.duplicate(true),
	}
	_chronicle.append(entry)
	if _chronicle.size() > MAX_CHRONICLE:
		_chronicle = _chronicle.slice(_chronicle.size() - MAX_CHRONICLE)
	print("[StorylineDirector] %s personal %s %s: %s%s" % [key, choice, entry.hook, reason,
		"" if dropped.is_empty() else " [dropped: %s]" % "; ".join(dropped.map(func(d): return d.reason))])
	decision_recorded.emit(entry)
	personal_turn_taken.emit(entry)
	return entry

## Another NPC this text names (roster key or first name, whole word), "" when none
func _named_npc_in(text: String, self_key: String) -> String:
	var lower = " %s " % text.to_lower()
	var registry = _registry()
	var keys: Array = registry.get_npc_keys() if registry else []
	for key in _registered:
		if key not in keys:
			keys.append(key)
	for key in keys:
		if key == self_key:
			continue
		var names: Array = [str(key)]
		var full = registry.get_npc_name(key) if registry and registry.has_npc(key) else _display_name(key)
		var first = full.split(" ", false)[0].to_lower() if full.strip_edges() != "" else ""
		if first.length() >= 3:
			names.append(first)
		for name in names:
			if RegEx.create_from_string("[^a-z0-9_]%s[^a-z0-9_]" % name).search(lower):
				return key
	return ""

func _people_near(key: String) -> String:
	var registry = _registry()
	if registry == null:
		return ""
	var here = get_npc_location(key)
	var people: Array = []
	for other in registry.get_npcs_in_region(registry.get_region(here)):
		if other != key:
			people.append("%s (%s)" % [other, registry.get_npc_name(other)])
	return ", ".join(people.slice(0, 10))

# =============================================================================
# THE NON-LINEAR WORLD (docs/WORLD_SCHEMA.md Part II: §11 movable fixed points, §12 emergent beats,
# §13 inner-voice steering, §15 epilogues). PlayerEvents/Reputation (the events engine, §10) are
# called through has_method guards so either side can run without the other
# =============================================================================

# --- collaborators -------------------------------------------------------------

## PlayerEvents (player_events_override in tests). null when there is none
func get_player_events() -> Node:
	if player_events_override != null:
		return player_events_override
	return get_node_or_null("/root/PlayerEvents") if is_inside_tree() else null

## Swap PlayerEvents (tests hand in a fake) and listen to its signals
func set_player_events(node: Node) -> void:
	player_events_override = node
	connect_player_events()

## Listen to PlayerEvents: every recorded or changed event may grow an emergent beat
func connect_player_events() -> void:
	var pe = get_player_events()
	if pe == _player_events_connected:
		return
	if _player_events_connected and is_instance_valid(_player_events_connected):
		for sig in ["player_event_recorded", "player_event_changed"]:
			if _player_events_connected.has_signal(sig) and _player_events_connected.is_connected(sig, _on_player_event):
				_player_events_connected.disconnect(sig, _on_player_event)
		if _player_events_connected.has_signal("player_event_heard") and _player_events_connected.is_connected("player_event_heard", _on_player_event_heard):
			_player_events_connected.disconnect("player_event_heard", _on_player_event_heard)
	_player_events_connected = pe
	if pe == null:
		return
	for sig in ["player_event_recorded", "player_event_changed"]:
		if pe.has_signal(sig) and not pe.is_connected(sig, _on_player_event):
			pe.connect(sig, _on_player_event)
	if pe.has_signal("player_event_heard") and not pe.is_connected("player_event_heard", _on_player_event_heard):
		pe.connect("player_event_heard", _on_player_event_heard)

func _on_player_event(ev: Dictionary) -> void:
	if ev is Dictionary:
		_emergence.on_player_event(ev)

## Word of an event reached someone: templates binding heard_event roles may now find their people
func _on_player_event_heard(event_id: String, _who: String, _fidelity: float) -> void:
	var pe = get_player_events()
	if pe and pe.has_method("get_event"):
		var ev: Dictionary = pe.get_event(event_id)
		if not ev.is_empty():
			_emergence.on_player_event(ev)

## The Reputation class (static; null when the events engine has not shipped it)
func get_reputation_script():
	return load(REPUTATION_PATH) if ResourceLoader.exists(REPUTATION_PATH) else null

## Reputation.of(scope, id) (-100..100); 0 when unavailable
func get_reputation(scope: String, id: String) -> float:
	if reputation_override.is_valid():
		return float(reputation_override.call(scope, id))
	var rep = get_reputation_script()
	if rep == null:
		return 0.0
	return float(rep.of(scope, id))

## The InnerVoice the director reads (inner_voice_override in tests)
func get_inner_voice() -> Node:
	if inner_voice_override != null:
		return inner_voice_override
	var voice = get_node_or_null("/root/InnerVoice") if is_inside_tree() else null
	return voice if voice and voice.has_method("score_target") else null

## The generic NPC manager (DynamicNPCRegistry.generics), null when absent
func get_generics() -> Node:
	var registry = get_node_or_null("/root/DynamicNPCRegistry") if is_inside_tree() else null
	return registry.generics if registry and "generics" in registry and registry.generics else null

## This NPC's feelings toward the player, -100..100 per dimension: test override, else the live node,
## else the relationship ledger (every NPC, mains and generics), plus deltas still waiting for delivery
func get_relationship_dims(npc: String) -> Dictionary:
	var key = _npc_key(npc)
	var dims: Dictionary = {"trust": 0.0, "respect": 0.0, "affection": 0.0, "fear": 0.0, "familiarity": 0.0}
	if relationship_dims_override.has(key):
		for dim in relationship_dims_override[key]:
			dims[str(dim)] = float(relationship_dims_override[key][dim])
		return dims
	var found = false
	for live in get_loaded_npcs(key):
		if live.get("_is_initialized"):
			for dim in dims:
				var v = live.get("relationship_" + dim)
				if v != null:
					dims[dim] = float(v)
			found = true
			break
	if not found:
		var generics = get_generics()
		if generics and "ledger" in generics and generics.ledger and generics.ledger.has_entry(_npc_id(key)):
			dims = generics.ledger.get_dims(_npc_id(key))
	for dim in _pending_relationships.get(key, {}):
		dims[dim] = clampf(float(dims.get(dim, 0.0)) + float(_pending_relationships[key][dim]), -100.0, 100.0)
	return dims

func get_display_name(npc: String) -> String:
	var key = _npc_key(npc)
	var registry = _registry()
	if registry and registry.has_npc(key):
		return registry.get_npc_name(key)
	var generics = get_generics()
	var inst = generics.get_instance(key) if generics and generics.has_method("get_instance") else null
	if inst and str(inst.name) != "":
		return str(inst.name)
	return _display_name(key)

func get_npc_home(npc: String) -> String:
	var key = _npc_key(npc)
	var registry = _registry()
	var home = registry.get_npc_home(key) if registry and registry.has_npc(key) else ""
	if home == "" and _registered.has(key):
		home = str(_registered[key].get("home", ""))
	return home if home != "" else get_npc_location(key)

## How NPCs refer to the player: the name they gave, else "the stranger"
func get_player_name() -> String:
	var world_events = get_node_or_null("/root/WorldEvents") if is_inside_tree() else null
	var name = str(world_events.get_player_name()) if world_events and world_events.has_method("get_player_name") else ""
	return "the stranger" if name == "" or name == "stranger" else name

func get_agent():
	return _agent

## A one-off choice put to an NPC's soul, outside any storyline (docs/PLAYER_SYSTEMS.md §8): fight or
## yield, teach or refuse, take a dropped pack or leave it. hook: {id, type, situation, options:
## [{id, label, appeal, effects, aids?, harms?, crowd?}]}. Chosen like an emergent beat's hook (offline
## appeal or Claude, under the soul's Agency and Lines). Returns the decision; nothing is applied
## (the caller acts on decision.choice and applies decision.effects through apply_situation_effects)
func decide_situation(npc_key: String, hook: Dictionary, title: String = "") -> Dictionary:
	var key = _npc_key(npc_key)
	var soul = _souls.get(key)
	if soul == null:
		return {"choice": "pass", "option": {}, "effects": [], "reason": "no soul for this NPC", "mode": "offline", "fallback_reason": ""}
	var ask = hook.duplicate(true)
	ask["id"] = str(ask.get("id", "situation"))
	ask["type"] = str(ask.get("type", "react"))
	return await _emergence.decide_one(soul, key, ask, {"title": title if title != "" else str(ask.get("situation", "")), "roles": {}})

## Apply a situation decision's effects as that NPC (each checked against its soul, like any effect)
func apply_situation_effects(npc_key: String, decision: Dictionary, source: Dictionary = {}) -> Array:
	var results: Array = []
	for effect in decision.get("effects", []):
		var checked = _effects.validate(effect)
		if not checked.ok:
			results.append({"ok": false, "reason": checked.reason})
			continue
		results.append(_apply_effect_as_director(checked.effect, _npc_key(npc_key), source.merged({"situation": true})))
	if not _processing:
		_process_queue()
	return results

func get_claude_client_for_agents() -> Object:
	return _get_claude_client()

# --- movable fixed points (§11) -----------------------------------------------------

var _shift_context: Dictionary = {}  # set while shift_fixed_point is asking WorldState to move a point

## Move a movable calendar point. days_or_cancel: int days (-3..3; negative brings it earlier) or
## "cancel" / true. actor: npc key, "player", or "" (the world). A point that fired, a cancelled point
## and a point that is not movable never move. Shifts are chronicled (mode "fixed_point") and canon
## (WorldEvents); a shift the player caused is also a PlayerEvents event, so the people it touches hear of it
## Returns {"ok", "reason", "point", "action", "days", "from", "to"}
func shift_fixed_point(point: String, days_or_cancel, reason: String = "", actor: String = "", source: Dictionary = {}) -> Dictionary:
	var world_state = get_node_or_null("/root/WorldState")
	if world_state == null or not world_state.has_method("shift_calendar_point"):
		return {"ok": false, "reason": "no calendar", "point": point}
	var cancel = days_or_cancel is bool and days_or_cancel == true or (days_or_cancel is String and str(days_or_cancel).to_lower() == "cancel")
	var days = 0
	if not cancel:
		if not (days_or_cancel is int or days_or_cancel is float):
			return {"ok": false, "reason": "days must be a number (-3..3) or \"cancel\"", "point": point}
		days = clampi(int(days_or_cancel), -EffectApplier.MAX_SHIFT_DAYS, EffectApplier.MAX_SHIFT_DAYS)
	_shift_context = {"actor": actor, "source": source.duplicate(true), "trigger": "effect" if not source.is_empty() else "api"}
	var player_caused = actor == "player" or _causal_player or source.get("player_chain", false) == true or source.get("conversation", false) == true
	var result: Dictionary = world_state.shift_calendar_point(point, days, cancel, reason.strip_edges().substr(0, EffectApplier.MAX_REASON_CHARS), actor, -1, player_caused)
	_shift_context = {}
	return result

## Shift rules (world.json) whose `when` flag is true: WorldState applies them, the signal chronicles them
func _apply_shift_rules(turned_true: String) -> void:
	var world_state = get_node_or_null("/root/WorldState")
	if world_state and world_state.has_method("apply_shift_rules"):
		world_state.apply_shift_rules(turned_true, _flag_player_chain)

## Every shift, whoever asked for it: chronicle, canon, and the player's deed when it was theirs
func _on_calendar_point_shifted(point: String, info: Dictionary) -> void:
	var actor = str(info.get("actor", ""))
	var trigger = str(_shift_context.get("trigger", "api"))
	var source: Dictionary = _shift_context.get("source", {})
	if actor.begins_with("rule:"):
		trigger = "shift_rule:" + actor.substr(5)
		actor = str(_flag_actors.get(actor.substr(5), "world"))
	if actor == "":
		actor = "world"
	var world_state = get_node_or_null("/root/WorldState")
	var entry_point: Dictionary = world_state.get_calendar_point(point) if world_state else {}
	var cancelled = str(info.get("action", "")) == "cancel"
	var why = str(info.get("reason", ""))
	var effect = {"type": "shift_fixed_point", "point": point, "reason": why}
	if cancelled:
		effect["cancel"] = true
	else:
		effect["days"] = int(info.get("days", 0))
	_seq += 1
	var entry = {
		"seq": _seq, "round": _round, "time": Time.get_unix_time_from_system(), "game_minutes": _now(),
		"storyline": str(source.get("storyline", "")), "beat": str(source.get("beat", "")), "hook": point,
		"hook_type": "fixed_point", "trigger": trigger, "npc": actor, "location": "", "mode": "fixed_point",
		"fallback_reason": "", "choice": "cancel" if cancelled else "delay",
		"label": why if why != "" else "%s moved" % point,
		"reason": "%s -> %s" % [_minute_text(int(info.get("from", -1))), "called off" if cancelled else _minute_text(int(info.get("to", -1)))],
		"applied": [effect], "dropped": [], "emergent": str(source.get("emergent", "")),
		"player_caused": info.get("player_caused", false) == true,
	}
	if int(info.get("clamped_from", 0)) != 0:
		entry["clamped_from"] = int(info.clamped_from)
		entry["reason"] += " (clamped from %+d: without the player, a fixed point comes at most %d day early in all)" % [int(info.clamped_from), 1]
	_chronicle.append(entry)
	if _chronicle.size() > MAX_CHRONICLE:
		_chronicle = _chronicle.slice(_chronicle.size() - MAX_CHRONICLE)
	print("[StorylineDirector] fixed point %s %s by %s (%s)" % [point, entry.choice, actor, entry.reason])
	var canon = why if why != "" else ("%s was called off." % str(entry_point.get("description", point)) if cancelled else "%s came at a different hour." % str(entry_point.get("description", point)))
	var affected: Array = _named_npcs_in(canon + " " + str(entry_point.get("description", "")))
	if actor != "player" and actor != "world" and actor != "director" and _npc_id(actor) not in affected:
		affected.append(_npc_id(actor))
	_register_world_event(canon, ["all"] + affected)
	if actor == "player":
		var pe = get_player_events()
		if pe and pe.has_method("record"):
			var summary = "brought it about that " + _decapitalize(canon)
			pe.record("refusal", _clip(summary, 140), affected.map(func(id): return _npc_key(id)), {"location": get_player_location() if get_player_location() != "" else str(""), "spread": true})
	decision_recorded.emit(entry)
	fixed_point_shifted.emit(point, entry)

## An advance with no player in its chain, refused whole by the cap: chronicled with its reason
func _on_calendar_shift_clamped(point: String, info: Dictionary) -> void:
	var actor = str(info.get("actor", ""))
	var trigger = str(_shift_context.get("trigger", "api"))
	if actor.begins_with("rule:"):
		trigger = "shift_rule:" + actor.substr(5)
		actor = str(_flag_actors.get(actor.substr(5), "world"))
	_seq += 1
	var effect = {"type": "shift_fixed_point", "point": point, "days": int(info.get("days", 0)), "reason": str(info.get("reason", ""))}
	var entry = {
		"seq": _seq, "round": _round, "time": Time.get_unix_time_from_system(), "game_minutes": _now(),
		"storyline": str(_shift_context.get("source", {}).get("storyline", "")), "beat": "", "hook": point,
		"hook_type": "fixed_point", "trigger": trigger, "npc": actor if actor != "" else "world", "location": "", "mode": "fixed_point",
		"fallback_reason": "", "choice": "clamped", "label": str(info.get("reason", "")), "reason": str(info.get("clamp", "")),
		"applied": [], "dropped": [{"effect": effect, "reason": str(info.get("clamp", ""))}], "player_caused": false,
	}
	_chronicle.append(entry)
	if _chronicle.size() > MAX_CHRONICLE:
		_chronicle = _chronicle.slice(_chronicle.size() - MAX_CHRONICLE)
	decision_recorded.emit(entry)

func _minute_text(minute: int) -> String:
	if minute < 0:
		return "?"
	return "Day %d, %02d:%02d" % [floori(minute / 1440.0) + 1, floori((minute % 1440) / 60.0), minute % 60]

func _decapitalize(text: String) -> String:
	var t = text.strip_edges()
	return t.substr(0, 1).to_lower() + t.substr(1) if t.length() > 1 and t.substr(1, 1) == t.substr(1, 1).to_lower() else t

## npc ids of every roster NPC this text names (key or first name, whole word)
func _named_npcs_in(text: String) -> Array:
	var ids: Array = []
	var registry = _registry()
	if registry == null:
		return ids
	var lower = " %s " % text.to_lower()
	for key in registry.get_npc_keys():
		var first = registry.get_npc_name(key).split(" ", false)
		var names: Array = [str(key)]
		if not first.is_empty() and first[0].length() >= 3:
			names.append(first[0].to_lower())
		for name in names:
			if RegEx.create_from_string("[^a-z0-9_]%s[^a-z0-9_]" % name).search(lower):
				ids.append(registry.get_npc_id(key))
				break
	return ids

func _on_calendar_flag_fired(flag_name: String, _at_minute: int) -> void:
	if flag_name == SEASON_END_POINT and end_on_season_end and _game_ended == "":
		end_game.call_deferred("season_end")

# --- spread_event (§12) -----------------------------------------------------------

## The spread_event effect: PlayerEvents.spread(event_id, to, via). "*" means the event's region
## Returns {"ok", "reason", "scheduled", "refused"}
func spread_player_event(event_id: String, to: Array, via: String = "", _actor: String = "", _source: Dictionary = {}) -> Dictionary:
	var pe = get_player_events()
	if pe == null or not pe.has_method("spread"):
		return {"ok": false, "reason": "PlayerEvents unavailable", "scheduled": [], "refused": []}
	if pe.has_method("get_event") and pe.get_event(event_id).is_empty():
		return {"ok": false, "reason": "no player event '%s'" % event_id, "scheduled": [], "refused": []}
	var result = pe.spread(event_id, to, via)
	var scheduled: Array = result.get("scheduled", []) if result is Dictionary else []
	var refused: Array = result.get("refused", []) if result is Dictionary else []
	if scheduled.is_empty() and not refused.is_empty():
		return {"ok": false, "reason": "spread refused: %s" % ", ".join(refused.map(func(r): return str(r.get("reason", "")))), "scheduled": [], "refused": refused}
	return {"ok": true, "reason": "", "scheduled": scheduled, "refused": refused}

# --- emergent beats (§12) ---------------------------------------------------------

## Load emergence templates from another folder (tests); "" = the current emergence_dir. Clears instances
func load_emergence(dir_path: String = "") -> int:
	if dir_path != "":
		emergence_dir = dir_path
	_emergence.reset()
	return _emergence.load_templates(emergence_dir)

func get_emergence():
	return _emergence

func get_emergence_templates() -> Array:
	return _emergence.template_order.duplicate()

func get_emergence_errors() -> Array:
	return _emergence.load_errors.duplicate()

## Emergent instances, oldest first (closed ones too unless include_closed is false)
func get_emergent_instances(include_closed: bool = true) -> Array:
	return _emergence.get_instances(include_closed)

## Queue a hook that does not live in a storyline file (emergent beats). Deduplicated like _enqueue
func enqueue_external(sid: String, beat_id: String, hook_id: String, trigger: String) -> void:
	for item in _decision_queue:
		if item.storyline == sid and item.hook == hook_id:
			return
	_decision_queue.append({"storyline": sid, "beat": beat_id, "hook": hook_id, "trigger": trigger, "queued_round": _round})
	decision_queued.emit(sid, hook_id)

## Chronicle an emergent instantiation, decision or close (mode "emergent"); memory (if any) becomes
## the bound NPCs' canon memory (WorldEvents). Never carries the player's thoughts
func record_emergent(inst: Dictionary, choice: String, hook_id: String, applied: Array, dropped: Array, memory: String, npcs: Array, extra: Dictionary = {}) -> Dictionary:
	_seq += 1
	var first_role = str(inst.roles.values()[0]) if not inst.get("roles", {}).is_empty() else ""
	var entry = {
		"seq": _seq, "round": _round, "time": Time.get_unix_time_from_system(), "game_minutes": _now(),
		"storyline": Emergence.PREFIX + str(inst.template), "beat": str(inst.id), "hook": hook_id,
		"hook_type": str(extra.get("hook_type", "emergent")), "trigger": str(extra.get("trigger", choice)),
		"npc": str(extra.get("npc", first_role)), "location": str(inst.get("location", "")), "mode": "emergent",
		"agent_mode": str(extra.get("agent_mode", "offline")), "fallback_reason": str(extra.get("fallback_reason", "")),
		"emergent": str(inst.id), "template": str(inst.template), "roles": inst.get("roles", {}).duplicate(),
		"event_id": str(inst.get("event_id", "")), "choice": choice,
		"label": str(extra.get("label", "")) if str(extra.get("label", "")) != "" else str(inst.get("title", "")),
		"reason": str(extra.get("reason", "")), "applied": applied.duplicate(true), "dropped": dropped.duplicate(true),
	}
	_chronicle.append(entry)
	if _chronicle.size() > MAX_CHRONICLE:
		_chronicle = _chronicle.slice(_chronicle.size() - MAX_CHRONICLE)
	if choice not in ["instantiated", "resolved", "expired"]:
		print("[StorylineDirector] %s at %s/%s: %s (%d applied, %d dropped)" % [entry.npc, inst.id, hook_id, choice, applied.size(), dropped.size()])
	if memory != "":
		_register_world_event(memory, npcs.map(func(k): return _npc_id(str(k))))
	decision_recorded.emit(entry)
	if choice not in ["instantiated", "resolved", "expired", "pass"]:
		emergent_acted.emit(entry)
	return entry

# --- inner-voice steering (§13) -----------------------------------------------------

## The decision queue as this round takes it: the player's intentions (InnerVoice) move matching hooks,
## and hooks of NPCs whose wants oppose them, ahead; otherwise arrival order. priority =
## score_target(hook) + 0.5 * max pressure_for(eligible NPC); ties keep arrival order
func _ordered_queue() -> Array:
	var queue = _decision_queue.duplicate()
	var voice = get_inner_voice()
	if voice == null or not voice.has_active_intentions():
		return queue
	var scored: Array = []
	for i in queue.size():
		scored.append({"p": get_queue_priority(queue[i]), "i": i, "item": queue[i]})
	scored.sort_custom(func(a, b):
		if not is_equal_approx(a.p, b.p):
			return a.p > b.p
		return a.i < b.i)
	return scored.map(func(s): return s.item)

## How strongly the player's intentions pull one queued hook forward (0 without intentions)
func get_queue_priority(item: Dictionary) -> float:
	var voice = get_inner_voice()
	if voice == null or not voice.has_active_intentions():
		return 0.0
	var target: Dictionary = {}
	if _emergence.owns(str(item.storyline)):
		target = _emergence.priority_target(item)
	else:
		var found = _find_hook(str(item.storyline), str(item.hook))
		if found.is_empty():
			return 0.0
		target = hook_target(str(item.storyline), found.beat, found.hook)
	if target.is_empty():
		return 0.0
	var pressure = 0.0
	for key in target.get("npcs", []):
		pressure = maxf(pressure, voice.pressure_for(str(key)))
	return voice.score_target(target) + 0.5 * pressure

## What InnerVoice scores a storyline hook against: its eligible NPCs, storyline, beat, hook, the flags
## the beat and its options touch, and its words
func hook_target(sid: String, beat: Dictionary, hook: Dictionary) -> Dictionary:
	var flags: Array = []
	for f in beat.get("resolves_on", []) + beat.get("requires", []):
		var flag = str(f).trim_prefix("!")
		if flag not in flags:
			flags.append(flag)
	var text = "%s %s %s" % [str(_storylines.get(sid, {}).get("title", "")), str(beat.get("title", "")), str(hook.get("situation", ""))]
	for option in hook.get("options", []):
		if not option is Dictionary:
			continue
		text += " " + str(option.get("label", ""))
		for effect in option.get("effects", []):
			if effect is Dictionary and effect.has("flag") and str(effect.flag) not in flags:
				flags.append(str(effect.flag))
	return {"npcs": hook.get("eligible", []).map(func(k): return str(k)), "storyline": sid, "beat": str(beat.get("id", "")),
		"hook": str(hook.get("id", "")), "flags": flags, "text": text}

## Intention focus of a personal turn: its Life step scored by InnerVoice, plus pressure on that NPC
func _personal_focus(key: String, plan: Dictionary) -> float:
	var voice = get_inner_voice()
	if voice == null or not voice.has_active_intentions():
		return 0.0
	var soul = _souls.get(key)
	var arc: Dictionary = soul.get_arc(str(plan.arc)) if soul else {}
	var step: Dictionary = soul.get_step(str(plan.arc), str(plan.step)) if soul else {}
	var target = {"npcs": [key], "arc": "%s/%s" % [key, plan.arc], "flags": [str(step.get("flag", "")), str(arc.get("result", {}).get("flag", ""))],
		"text": "%s %s" % [str(arc.get("prose", "")), str(step.get("text", ""))]}
	return snappedf(voice.score_target(target) + voice.pressure_for(key), 0.001)

# --- the end (§15) ---------------------------------------------------------------

## End the game: generate the epilogue from the world state (Epilogue.generate), let Claude rewrite it
## in Claude mode (validated: no facts beyond the state, else the offline text stands), keep it and
## emit epilogue_ready. reason: "player" (the player chose to end), "season_end", "debug"
func end_game(reason: String = "player") -> Dictionary:
	var epilogue: Dictionary = EpilogueScript.generate({"trigger": reason})
	if agency_mode == "claude":
		epilogue = await EpilogueScript.rewrite(epilogue, _get_claude_client(), get_tree() if is_inside_tree() else null)
	_epilogue = epilogue
	_game_ended = reason
	print("[StorylineDirector] The game ended (%s): epilogue of %d sections" % [reason, epilogue.get("sections", []).size()])
	epilogue_ready.emit(epilogue)
	return epilogue

## The last epilogue end_game() made ({} before the end)
func get_epilogue() -> Dictionary:
	return _epilogue.duplicate(true)

## Why the game ended ("" while it goes on)
func get_game_ended() -> String:
	return _game_ended

# =============================================================================
# QUERIES
# =============================================================================

func get_storyline_ids() -> Array:
	return _storyline_order.duplicate()

func get_storyline(storyline_id: String) -> Dictionary:
	return _storylines.get(storyline_id, {})

func has_beat(storyline_id: String, beat_id: String) -> bool:
	return not _find_beat(storyline_id, beat_id).is_empty()

## "locked" | "open" | "resolved" | "blocked" ("" for an unknown beat)
func get_beat_status(storyline_id: String, beat_id: String) -> String:
	if not has_beat(storyline_id, beat_id):
		return ""
	var key = _beat_key(storyline_id, beat_id)
	if _resolved.has(key):
		return "resolved"
	if _blocked.has(key):
		return "blocked"
	if _opened.has(key):
		return "open"
	return "locked"

func get_beats(storyline_id: String) -> Array:
	var result = []
	for beat in _storylines.get(storyline_id, {}).get("beats", []):
		# "act" is optional (1-3); 0 when the beat does not say
		var act = int(beat.get("act", 0)) if (beat.get("act") is int or beat.get("act") is float) else 0
		result.append({"id": beat.id, "title": beat.get("title", ""), "act": act, "status": get_beat_status(storyline_id, beat.id)})
	return result

func get_hooks(storyline_id: String) -> Array:
	var result = []
	for beat in _storylines.get(storyline_id, {}).get("beats", []):
		for hook in beat.get("hooks", []):
			result.append({
				"id": hook.id, "beat": beat.id, "type": hook.get("type", ""), "trigger": hook.get("trigger", ""),
				"eligible": hook.get("eligible", []), "acted": int(_hook_acts.get(_beat_key(storyline_id, hook.id), 0))
			})
	return result

## Accepts an npc key ("gregor") or npc_id ("gregor_merchant_001")
func get_soul(npc: String):
	return _souls.get(_npc_key(npc))

func get_soul_keys() -> Array:
	return _souls.keys()

## Last n chronicle entries, oldest first (n = 0: all)
func get_chronicle(count: int = 0) -> Array:
	if count <= 0 or count >= _chronicle.size():
		return _chronicle.duplicate(true)
	return _chronicle.slice(_chronicle.size() - count).duplicate(true)

func get_ending(storyline_id: String) -> String:
	return _endings.get(storyline_id, "")

## A storyline-declared flag, a base flag (built-in or world.json discovery flag), or a personal flag
## (any loaded soul's Life: step and result flags). Storylines may READ every one of them
func is_known_flag(flag: String) -> bool:
	return _declared_flags.has(flag) or StoryFlags.is_base_flag(flag) or _personal_flags.has(flag)

## Set only by its owner's Life (step completion, arc result). No effect may set one (EffectApplier)
func is_personal_flag(flag: String) -> bool:
	return _personal_flags.has(flag)

## personal flag -> owning npc key
func get_personal_flags() -> Dictionary:
	return _personal_flags.duplicate()

func set_agency_mode(mode: String) -> bool:
	mode = mode.strip_edges().to_lower()
	if mode not in NpcAgent.MODES:
		return false
	agency_mode = mode
	return true

## Swap the client Claude-mode decisions use (tests inject a fake; nothing else needs this)
func set_agent_client(client: Object) -> void:
	_claude_client = client
	_agent.client = client

func set_agent_timeout(seconds: float) -> void:
	_agent.timeout_seconds = seconds

## Live NPCs in the scene tree whose npc_id carries this key ("" = all)
func get_loaded_npcs(npc_key: String = "") -> Array:
	var result = []
	if not is_inside_tree():
		return result
	for npc in get_tree().get_nodes_in_group("npcs"):
		if "npc_id" in npc and npc.npc_id != "" and (npc_key == "" or _npc_key(npc.npc_id) == npc_key):
			result.append(npc)
	return result

# =============================================================================
# SAVE / LOAD (stored inside WorldState's save file)
# =============================================================================

func save() -> Dictionary:
	var weights = {}
	for key in _souls:
		weights[key] = _souls[key].get_weights()
	return {
		"opened": _opened.keys(),
		"opened_seq": _opened_seq.duplicate(),
		"open_counter": _open_counter,
		"resolved": _resolved.keys(),
		"blocked": _blocked.keys(),
		"hook_acts": _hook_acts.duplicate(),
		"endings": _endings.duplicate(),
		"drift_applied": _drift_applied.keys(),
		"weights": weights,
		"agendas": _agendas.duplicate(true),
		"pending_relationships": _pending_relationships.duplicate(true),
		"chronicle": _chronicle.duplicate(true),
		"seq": _seq,
		"agenda_seq": _agenda_seq,
		"round": _round,
		"decision_queue": _decision_queue.duplicate(true),
		"pending_moves": _pending_moves.duplicate(true),
		"scheduled": _scheduled.duplicate(true),
		"minutes_toward_round": _minutes_toward_round,
		"personal_round": _personal_round,
		"life": _save_life(),
		"registered_tiers": _save_registered_tiers(),
		"emergence": _emergence.save(),
		"flag_actors": _flag_actors.duplicate(),
		"flag_player_chain": _flag_player_chain.duplicate(),
		"game_ended": _game_ended,
	}

func load_from_dict(data: Dictionary) -> void:
	reset_state()
	for key in data.get("opened", []):
		_opened[key] = true
	for key in data.get("opened_seq", {}):
		_opened_seq[key] = int(data.opened_seq[key])
	_open_counter = int(data.get("open_counter", _opened_seq.size()))
	for key in data.get("resolved", []):
		_resolved[key] = true
	for key in data.get("blocked", []):
		_blocked[key] = true
	for key in data.get("drift_applied", []):
		_drift_applied[key] = true
	for key in data.get("hook_acts", {}):
		_hook_acts[key] = int(data.hook_acts[key])
	_endings = data.get("endings", {}).duplicate()
	_agendas = data.get("agendas", {}).duplicate(true)
	_pending_relationships = data.get("pending_relationships", {}).duplicate(true)
	_chronicle = data.get("chronicle", []).duplicate(true)
	_seq = int(data.get("seq", 0))
	_agenda_seq = int(data.get("agenda_seq", 0))
	_round = int(data.get("round", 0))
	for item in data.get("decision_queue", []):
		if item is Dictionary and item.has("storyline") and item.has("hook"):
			_decision_queue.append({"storyline": str(item.storyline), "beat": str(item.get("beat", "")), "hook": str(item.hook),
				"trigger": str(item.get("trigger", "")), "queued_round": int(item.get("queued_round", 0))})
	_pending_moves = data.get("pending_moves", {}).duplicate(true)
	for key in _pending_moves:
		for move in _pending_moves[key]:
			move["minutes"] = int(move.get("minutes", 0))
	for item in data.get("scheduled", []):
		if item is Dictionary and item.get("effect") is Dictionary:
			var copy: Dictionary = item.duplicate(true)
			copy["at"] = int(copy.get("at", 0))
			_scheduled.append(copy)
	_minutes_toward_round = int(data.get("minutes_toward_round", 0))
	var weights: Dictionary = data.get("weights", {})
	for key in weights:
		if _souls.has(key):
			_souls[key].set_weights(weights[key])
		elif weights[key] is Dictionary:
			_pending(key)["weights"] = weights[key].duplicate()
	# Life progress; souls not registered yet get theirs when register_soul() is called again
	_personal_round = int(data.get("personal_round", 0))
	var life: Dictionary = data.get("life", {}) if data.get("life") is Dictionary else {}
	for key in life:
		if not life[key] is Dictionary:
			continue
		if _souls.has(key):
			_souls[key].set_life_state(life[key])
		else:
			_pending(key)["life"] = life[key].duplicate(true)
	var tiers: Dictionary = data.get("registered_tiers", {}) if data.get("registered_tiers") is Dictionary else {}
	for key in tiers:
		if _registered.has(key) and str(tiers[key]) in TIERS:
			_set_tier_quiet(key, str(tiers[key]))
		elif not _souls.has(key) and str(tiers[key]) in TIERS:
			_pending(key)["tier"] = str(tiers[key])
	_emergence.load_from_dict(data.get("emergence", {}) if data.get("emergence") is Dictionary else {})
	_flag_actors = data.get("flag_actors", {}).duplicate() if data.get("flag_actors") is Dictionary else {}
	_flag_player_chain = data.get("flag_player_chain", {}).duplicate() if data.get("flag_player_chain") is Dictionary else {}
	_game_ended = str(data.get("game_ended", ""))

## Forget all progress (beats, decisions, drift); content stays loaded
func reset_state() -> void:
	_opened.clear()
	_opened_seq.clear()
	_open_counter = 0
	_resolved.clear()
	_blocked.clear()
	_hook_acts.clear()
	_endings.clear()
	_drift_applied.clear()
	_agendas.clear()
	_pending_relationships.clear()
	_chronicle.clear()
	_flag_queue.clear()
	_seq = 0
	_agenda_seq = 0
	_round = 0
	_decision_queue.clear()
	_pending_moves.clear()
	_scheduled.clear()
	_minutes_toward_round = 0
	_time_rounds_owed = 0
	_personal_round = 0
	_pending_soul_state.clear()
	_emergence.reset()
	_flag_actors.clear()
	_flag_player_chain.clear()
	_epilogue = {}
	_game_ended = ""
	for key in _souls:
		_souls[key].reset_weights()
		_souls[key].reset_life()

# =============================================================================
# INTERNALS
# =============================================================================

func _apply_drift(flag_name: String) -> void:
	for key in _souls:
		for rule in _souls[key].get_drift_for_flag(flag_name):
			var drift_key = "%s|%s|%s" % [key, flag_name, rule.want]
			if _drift_applied.has(drift_key):
				continue
			_drift_applied[drift_key] = true
			if _souls[key].shift_want(rule.want, rule.delta):
				print("[StorylineDirector] %s drifts: %s %+d (%s)" % [key, rule.want, rule.delta, flag_name])

func _requirements_hold(requires: Array) -> bool:
	for requirement in requires:
		var text = str(requirement)
		var negated = text.begins_with("!")
		if _flag(text.trim_prefix("!")) == negated:
			return false
	return true

func _any_flag_true(flags: Array) -> bool:
	for flag in flags:
		if _flag(str(flag)):
			return true
	return false

func _flag(flag_name: String) -> bool:
	var world_state = get_node_or_null("/root/WorldState")
	return world_state != null and world_state.get_world_flag(flag_name)

func _is_npc_alive(npc_key: String) -> bool:
	var world_state = get_node_or_null("/root/WorldState")
	return world_state == null or world_state.is_npc_alive(_npc_id(npc_key))

func _find_beat(storyline_id: String, beat_id: String) -> Dictionary:
	for beat in _storylines.get(storyline_id, {}).get("beats", []):
		if beat is Dictionary and str(beat.get("id", "")) == beat_id:
			return beat
	return {}

func _find_hook(storyline_id: String, hook_id: String) -> Dictionary:
	for beat in _storylines.get(storyline_id, {}).get("beats", []):
		for hook in beat.get("hooks", []):
			if hook is Dictionary and str(hook.get("id", "")) == hook_id:
				return {"beat": beat, "hook": hook}
	return {}

func _get_claude_client() -> Object:
	if _claude_client == null:
		_claude_client = load("res://scripts/dialogue/claude_client.gd").new()
		add_child(_claude_client)
	return _claude_client

func _register_world_event(description: String, participants: Array) -> void:
	var world_events = get_node_or_null("/root/WorldEvents")
	if world_events:
		world_events.register_event(world_events.EventCategory.QUEST_PROGRESS, description, participants, "")

func _display_name(npc_key: String) -> String:
	var soul = _souls.get(npc_key)
	return soul.display_name if soul and soul.display_name != "" else npc_key.capitalize()

func _beat_key(storyline_id: String, item_id: String) -> String:
	return "%s/%s" % [storyline_id, item_id]

## Roster key for an npc key or npc_id ("gregor_merchant_001" -> "gregor"); souls off the roster keep their key
func _npc_key(npc_id: String) -> String:
	var exact = npc_id.strip_edges().to_lower()
	if _souls.has(exact):
		return exact
	if _registered_ids.has(exact):
		return _registered_ids[exact]
	var registry = _registry()
	var key = registry.get_npc_key(npc_id) if registry else ""
	if key != "":
		return key
	var lower = npc_id.to_lower()
	for soul_key in _souls:
		if lower == soul_key or lower.begins_with(soul_key + "_") or (_souls[soul_key].npc_id != "" and _souls[soul_key].npc_id.to_lower() == lower):
			return soul_key
	return lower

func _npc_id(npc_key: String) -> String:
	var registry = _registry()
	var npc_id = registry.get_npc_id(npc_key) if registry else ""
	if npc_id == "" and _souls.has(npc_key) and _souls[npc_key].npc_id != "":
		npc_id = _souls[npc_key].npc_id
	return npc_id if npc_id != "" else npc_key

func _registry() -> Node:
	return get_node_or_null("/root/WorldRegistry") if is_inside_tree() else EffectApplier.registry()

## Storyline text is canon for the hallucination checks (titles, beat titles, flag descriptions)
func _register_canon() -> void:
	var registry = _registry()
	if registry == null:
		return
	var texts: Array = []
	for sid in _storylines:
		var storyline: Dictionary = _storylines[sid]
		texts.append(str(storyline.get("title", "")))
		texts.append(str(storyline.get("summary", "")))
		for flag in storyline.get("flags", {}):
			texts.append(str(storyline.flags[flag]))
		for beat in storyline.get("beats", []):
			if beat is Dictionary:
				texts.append(str(beat.get("title", "")))
				texts.append(str(beat.get("summary", "")))
		for ending in storyline.get("endings", []):
			if ending is Dictionary:
				texts.append(str(ending.get("title", "")))
	registry.register_canon_text(texts)

func _list_dirs(path: String) -> Array:
	var dir = DirAccess.open(path)
	if dir == null:
		return []
	var names = Array(dir.get_directories())
	names.sort()
	return names

func _list_files(path: String, extension: String) -> Array:
	var dir = DirAccess.open(path)
	if dir == null:
		return []
	var names = []
	for file_name in dir.get_files():
		if file_name.ends_with(extension):
			names.append(file_name)
	names.sort()
	return names
