extends SceneTree

# Tests Puzzles (docs/PLAYER_SYSTEMS.md §5.2, §5.3):
# - the five lore puzzles load from resources/puzzles/, and get_puzzle never shows the answer
# - each lore puzzle: locked until its clues are found; wrong answers say why and set nothing; the
#   right answer sets its flag (world.json discovery flag or a storyline flag), records a `solved`
#   deed, uses the lore skill and emits `solved`; answering again changes nothing
# - naming the wrong person aloud is a false accusation; the right name aloud a true one; a near
#   miss is no accusation; a name said in thought is no deed at all
# - hints open with the lore skill; a solve done in a scene is seen by line of sight
# - save/load: attempts, solved and room state survive a JSON round trip and WorldState's block
# - the two rooms' logic against fake plates and ropes: the old workings (brake + rope, a jammed cage,
#   the burned barricade) and the abbey undercroft (two kneelers, the letters, the shelves burning)
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_puzzles.gd

class FakeStats extends Node:
	var uses: Array = []
	var lore: float = 0.0
	func use_skill(skill: String, difficulty_factor: float = 1.0, context: Dictionary = {}) -> Dictionary:
		uses.append({"skill": skill, "difficulty": difficulty_factor, "context": context})
		return {"gained": 0.5, "level": lore, "milestone": 0}
	func get_skill(skill: String) -> float:
		return lore if skill == "lore" else 0.0

class FakePlate extends Node2D:
	signal pressed(on: bool)

class FakeRope extends Node2D:
	signal cut

class FakeBook extends Node2D:
	signal interacted(item)
	var enabled: bool = false

class _Body extends Node2D:
	var npc_id: String = ""
	var is_alive: bool = true

const LORE_FLAGS = {
	"weigh_the_tiles": "tn_lot_rigged_known", "makers_marks": "spare_tiles_traced_to_davin",
	"gregors_ledger": "ledger_names_decoded", "tally_sticks": "tally_matched_to_register",
	"abbey_receipt": "grey_cure_recipe_known",
}
const RIGHT = {
	"weigh_the_tiles": "lectern_tile", "makers_marks": "davin", "tally_sticks": "warehouse_seven",
	"abbey_receipt": "iii_7_leaf_12",
	"gregors_ledger": {"year_1": "Corin Ashby", "year_2": "davin", "year_3": "hesk_marlow", "year_4": "Willa", "year_5": "ada fenn"},
}
const WRONG = {
	"weigh_the_tiles": "urn_elena", "makers_marks": "the smith", "tally_sticks": "cathedral_almonry",
	"abbey_receipt": "ii_4_leaf_31",
	"gregors_ledger": ["corin ashby", "davin", "willa brand", "hesk marlow", "ada fenn"],
}

var world_state: Node
var puzzles: Node
var pe: Node
var stats: FakeStats
var real_stats: Node
var failures: int = 0
var solved_signals: Array = []

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	world_state.set_idle_clock_rate(0.0)
	var director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	pe = root.get_node("PlayerEvents")
	pe.player_location_override = "thornhaven_blacksmith"
	puzzles = root.get_node("Puzzles")
	puzzles.solved.connect(func(id): solved_signals.append(id))
	# A fake PlayerStats in the autoload's place, to see the lore skill used (real one restored at the end)
	real_stats = root.get_node("PlayerStats")
	real_stats.name = "PlayerStatsReal"
	stats = FakeStats.new()
	stats.name = "PlayerStats"
	root.add_child(stats)
	print("============================================================")
	print("🧪 PUZZLES TEST")
	print("============================================================\n")

	_test_content()
	_test_lore_puzzles()
	_test_accusations()
	await _test_hints_and_sight()
	_test_save_load()
	_test_old_workings()
	_test_undercroft()

	stats.free()
	real_stats.name = "PlayerStats"
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _reset() -> void:
	puzzles.load_from_dict({})
	for f in ["recut_tile_seen", "duplicate_tiles_found", "ledger_found", "oskar_tally_seen", "abbey_fever_records_read",
			"old_workings_way_found", "salt_letters_second_set_found"] + LORE_FLAGS.values():
		world_state.set_world_flag(f, false)
	stats.uses.clear()
	stats.lore = 0.0
	solved_signals.clear()

func _unlock(id: String) -> void:
	for f in puzzles.puzzles[id].get("requires", []):
		world_state.set_world_flag(f, true)

func _test_content() -> void:
	print("Content")
	_check("Five lore puzzles", puzzles.get_puzzle_ids("lore") == ["abbey_receipt", "gregors_ledger", "makers_marks", "tally_sticks", "weigh_the_tiles"])
	_check("Two rooms", puzzles.get_puzzle_ids("room") == ["abbey_undercroft", "old_workings"])
	for id in LORE_FLAGS:
		var view = puzzles.get_puzzle(id)
		_check("%s: shows its question and clues, never the answer" % id, view.question != "" and not view.clues.is_empty() and not view.has("answer") and not view.has("correct") and not JSON.stringify(view).contains("\"correct\""))
	_check("Unknown puzzle: {}", puzzles.get_puzzle("no_such_puzzle").is_empty() and not puzzles.answer("no_such_puzzle", "x").ok)
	_check("Room scenes exist", ResourceLoader.exists("res://scenes/puzzles/old_workings.tscn") or FileAccess.file_exists("res://scenes/puzzles/old_workings.tscn"))
	_check("...built from the physics components by path", FileAccess.get_file_as_string("res://scenes/puzzles/abbey_undercroft.tscn").contains("res://scripts/world/physics/pressure_plate.gd") and FileAccess.get_file_as_string("res://scenes/puzzles/old_workings.tscn").contains("res://scripts/world/physics/rope.gd"))
	for f in ["spare_tiles_traced_to_davin", "ledger_names_decoded", "tally_matched_to_register", "old_workings_way_found", "salt_letters_second_set_found"]:
		_check("%s is a discovery flag (world.json)" % f, StoryFlags.is_discovery_flag(f) and StoryFlags.get_flag_description(f) != "")

func _test_lore_puzzles() -> void:
	print("\nLore puzzles")
	for id in LORE_FLAGS:
		_reset()
		var flag = LORE_FLAGS[id]
		var locked = puzzles.answer(id, RIGHT[id])
		_check("%s: locked until its clues are found" % id, not locked.ok and locked.reason == "missing_clues" and not world_state.get_world_flag(flag) and int(puzzles.attempts.get(id, 0)) == 0)
		_unlock(id)
		_check("%s: available once they are" % id, puzzles.get_puzzle(id).available)
		var before = pe.get_events().size()
		var wrong = puzzles.answer(id, WRONG[id])
		_check("%s: a wrong answer fails with a reason and sets nothing" % id, not wrong.ok and wrong.flag == "" and wrong.reason != "" and not world_state.get_world_flag(flag) and not puzzles.is_solved(id))
		_check("%s: ...a thought, not a deed" % id, pe.get_events().size() == before and stats.uses.is_empty())
		var right = puzzles.answer(id, RIGHT[id])
		_check("%s: the right answer sets %s" % [id, flag], right.ok and right.flag == flag and world_state.get_world_flag(flag))
		var ev = pe.get_event(str(right.get("event_id", "")))
		_check("%s: records a solved deed" % id, ev.get("kind", "") == "solved" and ev.get("flag", "") == flag)
		_check("%s: uses the lore skill" % id, stats.uses.size() == 1 and stats.uses[0].skill == "lore" and stats.uses[0].context.puzzle == id)
		_check("%s: emits solved, counts two attempts" % id, solved_signals == [id] and int(puzzles.attempts[id]) == 2 and puzzles.get_puzzle(id).solved)
		var again = puzzles.answer(id, WRONG[id])
		_check("%s: answering again changes nothing" % id, again.ok and again.reason == "already_solved" and stats.uses.size() == 1 and solved_signals.size() == 1)
	_reset()
	_unlock("gregors_ledger")
	var partial = puzzles.answer("gregors_ledger", {"year_1": "corin", "year_2": "davin", "year_3": "willa"})
	_check("Ledger: a partial reading names the lines that are wrong", not partial.ok and partial.wrong == ["year_3", "year_4", "year_5"] and partial.reason.begins_with("2 of 5"))
	var card = puzzles.get_puzzle("gregors_ledger")
	_check("The card's fields: answer_kind, prompt, cipher", card.answer_kind == "decode" and card.prompt == card.question and card.cipher.split("\n").size() == 5)
	_check("Options are {id, label}", puzzles.get_puzzle("tally_sticks").options[0].has("label") and puzzles.get_puzzle("makers_marks").answer_kind == "name")
	_check("A decode read as one String, in line order", puzzles.answer("gregors_ledger", "Corin Ashby, Davin; Hesk Marlow\nWilla Brand, Ada Fenn").ok)
	_unlock("weigh_the_tiles")
	_check("Not an option is not an answer", puzzles.answer("weigh_the_tiles", "the moon").reason == "not_an_option")
	_check("A room is not answered from a card", not puzzles.answer("old_workings", "x").ok)

func _test_accusations() -> void:
	print("\nAccusations")
	_reset()
	_unlock("makers_marks")
	var thought = puzzles.answer("makers_marks", "bjorn")
	_check("Naming Bjorn in thought: wrong, no deed", not thought.ok and not thought.has("accusation_id"))
	var aloud = puzzles.answer("makers_marks", "Bjorn", {"aloud": true, "witnesses": ["gregor"]})
	var acc = pe.get_event(str(aloud.get("accusation_id", "")))
	_check("Naming Bjorn aloud is an accusation", acc.get("kind", "") == "accusation" and "bjorn" in acc.get("about", []))
	_check("...that is false (Bjorn never knew of the spares)", acc.get("truth", "") == "false" and not aloud.ok)
	_check("...heard by whoever was there", acc.get("witnesses", []).size() == 1)
	var near = puzzles.answer("makers_marks", "gregor", {"aloud": true, "witnesses": ["bjorn"]})
	_check("Gregor is a near miss: no accusation, a reason to think again", not near.ok and not near.has("accusation_id") and near.reason.contains("Kept is not poured"))
	_check("A stranger's name is nobody", puzzles.answer("makers_marks", "Old Tom").reason == "nobody_by_that_name")
	var right = puzzles.answer("makers_marks", "the smith's boy", {"aloud": true, "witnesses": ["bjorn"]})
	var named = pe.get_event(str(right.get("accusation_id", "")))
	_check("Davin named aloud: solved, and a true accusation (word that he lives can travel)", right.ok and named.get("truth", "") == "true" and "davin" in named.get("about", []))
	_check("Wrong accusations lower standing (reputation weighs them)", load("res://scripts/world_state/reputation.gd").KIND_WEIGHTS.accusation < 0)

func _test_hints_and_sight() -> void:
	print("\nHints and sight")
	_reset()
	_check("No lore: one hint", puzzles.get_puzzle("makers_marks").hints.size() == 1)
	stats.lore = 30.0
	_check("Lore 30: the second hint opens", puzzles.get_puzzle("makers_marks").hints.size() == 2)
	_check("Clues found follow their flags", not puzzles.get_puzzle("makers_marks").clues[0].found)
	_unlock("weigh_the_tiles")
	_check("...and show once found", puzzles.get_puzzle("weigh_the_tiles").clues[0].found)
	var scene = Node2D.new()
	root.add_child(scene)
	var watcher = _Body.new()
	watcher.npc_id = "test_watcher_001"
	watcher.add_to_group("npcs")
	scene.add_child(watcher)
	await physics_frame
	await physics_frame
	var res = puzzles.answer("weigh_the_tiles", "lectern_tile", {"scene_root": scene, "at": Vector2(50, 0)})
	_check("Weighing in a scene is seen by line of sight", "test_watcher_001" in pe.get_event(str(res.get("event_id", ""))).get("witnesses", []))
	_check("...and the skill use knows who watched", "test_watcher_001" in stats.uses[-1].context.witnessed_by)
	scene.free()

func _test_save_load() -> void:
	print("\nSave and load")
	_reset()
	_unlock("tally_sticks")
	puzzles.answer("tally_sticks", "fort_ashguard")
	puzzles.answer("tally_sticks", "warehouse_seven")
	_unlock("abbey_receipt")
	puzzles.answer("abbey_receipt", "iii_1")
	puzzles.set_room_state("old_workings", "cage", "jammed")
	var saved = JSON.parse_string(JSON.stringify(puzzles.save()))
	puzzles.load_from_dict({})
	_check("Cleared", not puzzles.is_solved("tally_sticks") and puzzles.get_room_state("old_workings").is_empty())
	puzzles.load_from_dict(saved)
	_check("Solved survives a JSON round trip", puzzles.is_solved("tally_sticks") and not puzzles.is_solved("abbey_receipt"))
	_check("Attempts survive", int(puzzles.attempts.tally_sticks) == 2 and int(puzzles.attempts.abbey_receipt) == 1)
	_check("Room state survives", puzzles.get_room_state("old_workings").get("cage", "") == "jammed")
	_check("WorldState carries the block", world_state.save().get("player_systems", {}).get("Puzzles", {}).get("solved", {}).has("tally_sticks"))
	_check("A solved puzzle stays solved after load", puzzles.answer("tally_sticks", "fort_ashguard").reason == "already_solved")

func _room(script_path: String, parts: Dictionary) -> Node2D:
	var room = Node2D.new()
	room.set_script(load(script_path))
	for n in parts:
		parts[n].name = n
		room.add_child(parts[n])
	root.add_child(room)
	return room

func _test_old_workings() -> void:
	print("\nRoom: the old workings")
	_reset()
	var plate = FakePlate.new()
	var rope = FakeRope.new()
	var room = _room("res://scripts/puzzles/room_old_workings.gd", {"BrakePlate": plate, "CageRope": rope,
		"Barricade": Node2D.new(), "AditBlock": StaticBody2D.new(), "Winze": Node2D.new(), "Adit": Node2D.new()})
	plate.pressed.emit(true)
	_check("The brake weighed down", puzzles.get_room_state("old_workings").get("brake_on", false))
	_check("Nothing opens on the brake alone", not world_state.get_world_flag("old_workings_way_found"))
	rope.cut.emit()
	_check("Rope cut on the brake: the cage rides down", puzzles.get_room_state("old_workings").cage == "down" and puzzles.get_room_state("old_workings").way == "winze")
	_check("The way into the Pit is found", world_state.get_world_flag("old_workings_way_found") and puzzles.is_solved("old_workings"))
	var ev = pe.get_events().back()
	_check("...a solved deed, not a lore skill use", ev.kind == "solved" and ev.flag == "old_workings_way_found" and stats.uses.is_empty())
	room.free()

	_reset()
	plate = FakePlate.new()
	rope = FakeRope.new()
	var barricade = Node2D.new()
	room = _room("res://scripts/puzzles/room_old_workings.gd", {"BrakePlate": plate, "CageRope": rope,
		"Barricade": barricade, "AditBlock": StaticBody2D.new(), "Winze": Node2D.new(), "Adit": Node2D.new()})
	rope.cut.emit()
	_check("Rope cut with the brake off: the cage jams, nothing opens", puzzles.get_room_state("old_workings").cage == "jammed" and not world_state.get_world_flag("old_workings_way_found"))
	plate.pressed.emit(true)
	rope.cut.emit()
	_check("...and stays jammed", puzzles.get_room_state("old_workings").cage == "jammed" and not puzzles.is_solved("old_workings"))
	var physics = root.get_node("WorldPhysics")
	var stray = Node2D.new()
	physics.burned.emit(stray, "dagna")
	stray.free()
	_check("Something else burning opens nothing", not puzzles.is_solved("old_workings"))
	physics.burned.emit(barricade, "dagna")
	_check("The barricade burned: the adit is the way", puzzles.get_room_state("old_workings").adit == "open" and puzzles.get_room_state("old_workings").way == "adit" and world_state.get_world_flag("old_workings_way_found"))
	_check("...and its block is gone", room.find_child("AditBlock", true, false) == null)
	room.free()

func _test_undercroft() -> void:
	print("\nRoom: the abbey undercroft")
	_reset()
	var north = FakePlate.new()
	var south = FakePlate.new()
	var rope = FakeRope.new()
	var book = FakeBook.new()
	var shelves = Node2D.new()
	var room = _room("res://scripts/puzzles/room_abbey_undercroft.gd", {"KneelerNorth": north, "KneelerSouth": south,
		"LampRope": rope, "HangingLamp": Node2D.new(), "DullShelves": shelves, "GrateShut": StaticBody2D.new(), "SaintsDaysBook": book})
	_check("The book is out of reach behind the grate", not book.enabled and not room.take_letters().ok)
	north.pressed.emit(true)
	_check("One kneeler lifts nothing", puzzles.get_room_state("abbey_undercroft").get("grate", "shut") == "shut")
	north.pressed.emit(false)
	south.pressed.emit(true)
	_check("...nor the other alone", puzzles.get_room_state("abbey_undercroft").get("grate", "shut") == "shut")
	north.pressed.emit(true)
	_check("Both at once: the grate lifts and the book can be taken", puzzles.get_room_state("abbey_undercroft").grate == "open" and book.enabled)
	north.pressed.emit(false)
	_check("...and the pawl holds it", puzzles.get_room_state("abbey_undercroft").grate == "open")
	book.interacted.emit(book)
	_check("Opening the book finds the second set of salt letters", world_state.get_world_flag("salt_letters_second_set_found") and puzzles.get_room_state("abbey_undercroft").letters == "taken")
	_check("...a solved deed", pe.get_events().back().kind == "solved" and puzzles.is_solved("abbey_undercroft"))
	room.free()

	_reset()
	north = FakePlate.new()
	south = FakePlate.new()
	rope = FakeRope.new()
	book = FakeBook.new()
	shelves = Node2D.new()
	room = _room("res://scripts/puzzles/room_abbey_undercroft.gd", {"KneelerNorth": north, "KneelerSouth": south,
		"LampRope": rope, "HangingLamp": Node2D.new(), "DullShelves": shelves, "GrateShut": StaticBody2D.new(), "SaintsDaysBook": book})
	rope.cut.emit()
	_check("The lamp rope cut: the lamp falls", puzzles.get_room_state("abbey_undercroft").get("lamp_fallen", false))
	root.get_node("WorldPhysics").burned.emit(shelves, "anselm")
	_check("The dull shelves burn, and the letters with them", puzzles.get_room_state("abbey_undercroft").letters == "burned")
	north.pressed.emit(true)
	south.pressed.emit(true)
	_check("The grate still lifts, on nothing", puzzles.get_room_state("abbey_undercroft").grate == "open" and not book.enabled)
	_check("No letters, no flag", not room.take_letters().ok and not world_state.get_world_flag("salt_letters_second_set_found"))
	room.free()

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
