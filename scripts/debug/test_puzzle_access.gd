extends SceneTree

# Tests that the puzzles can be reached and played (docs/PLAYER_SYSTEMS.md §5.2, §5.3):
# - the two rooms are world.json locations with LocationData, walking routes and no travel point;
#   the secret way to the Pit shortens nobody's road and the travel map never offers a room
# - the ways in and out are SceneTriggers that name built locations and real spawn points: Greystone
#   to the old workings and back, the abbey to its undercroft and back, the old workings to the Pit and
#   the Pit back up; every spawn point, exit and creature marker stands on open ground inside the walls
# - the way to the Pit is shut, with an in-world reason, until old_workings_way_found; and in the room
#   only the way the player opened (the winze once the cage rode down, the adit once the timbers burned)
# - the room actions: no blade, no cut; the ore tub rolled onto the treadle weighs the brake down; a cut
#   with the brake on opens the winze and finds the way; the timbers lit from the room's lamp burn and
#   open the adit; the reliquary chest on one kneeling stone and a person on the other lift the grate
# - the puzzles' flags open story beats (choices for the NPCs, a road for the player), never a
#   resolution: each beat opens on its flag and waits for the player or a soul to decide
# - the clue examinables (urn tiles, Bjorn's scale, Anselm's index) are StoryItems naming their puzzle,
#   show the clue and never the answer, and offer the answer card only once the puzzle is open
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_puzzle_access.gd

const SCENE_TRIGGER = "res://scripts/world/scene_trigger.gd"
const STORY_ITEM = "res://scripts/world/story_item.gd"
const PLAYER_BODY = Vector2(32, 48)   # scenes/player/player.tscn: feet at the origin, body above

class FakeUI extends Node:
	var opened: Array = []
	func open_puzzle(id: String) -> bool:
		opened.append(id)
		return true

class FakeDialogue extends Node:
	var said: Array = []
	func show_narration(text: String) -> void:
		said.append(text)

var failures: int = 0
var world_state: Node
var puzzles: Node
var physics: Node
var inventory: Node
var registry: Node

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	world_state.set_idle_clock_rate(0.0)
	var director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	root.get_node("PlayerEvents").player_location_override = "greystone_mines"
	puzzles = root.get_node("Puzzles")
	physics = root.get_node("WorldPhysics")
	inventory = root.get_node("Inventory")
	registry = root.get_node("WorldRegistry")
	print("============================================================")
	print("🧪 PUZZLE ACCESS TEST")
	print("============================================================\n")

	_test_registration()
	_test_scene_wiring()
	_test_ground()
	_test_gate()
	await _test_old_workings_play()
	await _test_old_workings_fire()
	await _test_undercroft_play()
	await _test_examinables()
	await _test_story_reactions()

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _reset() -> void:
	puzzles.load_from_dict({})
	physics.load_from_dict({})   # the rooms' ropes, tubs and timbers as built
	for f in ["old_workings_way_found", "salt_letters_second_set_found", "recut_tile_seen", "abbey_fever_records_read", "tn_drawing"]:
		world_state.set_world_flag(f, false)
	while inventory.has("knife"):
		inventory.remove("knife")

# =============================================================================

func _test_registration() -> void:
	print("Registration")
	var scene_manager = root.get_node("SceneManager")
	for id in ["old_workings", "abbey_undercroft"]:
		_check("%s is a built world.json location" % id, registry.has_location(id) and registry.is_built(id))
		_check("%s is walked to, never a travel point" % id, not registry.is_travel_point(id))
		_check("%s has LocationData for its scene" % id, scene_manager.get_location(id) != null
			and scene_manager.get_location(id).scene_path == registry.get_location_scene(id))
	_check("Greystone to the old workings is a walk", registry.get_route_minutes("greystone_mines", "old_workings") > 0)
	_check("The abbey to its undercroft is a walk", registry.get_route_minutes("brackenmoor_abbey", "abbey_undercroft") > 0)
	_check("The old workings route on to the Pit", registry.get_route_minutes("old_workings", "the_pit") > 0)
	_check("The secret way shortens nobody's road (Greystone to the Pit stays 300)", registry.travel_minutes("greystone_mines", "the_pit") == 300)
	var dests = root.get_node("TravelMap").plan_routes("greystone_mines").map(func(r): return r.dest)
	_check("The travel map never offers a room", not "old_workings" in dests and not "abbey_undercroft" in dests and "the_pit" in dests)

func _test_scene_wiring() -> void:
	print("\nWays in and out")
	var want = [
		["greystone_mines", "old_workings", "default", ""],
		["old_workings", "greystone_mines", "from_old_workings", ""],
		["old_workings", "the_pit", "from_old_workings", "old_workings_way_found"],
		["the_pit", "old_workings", "from_pit", "old_workings_way_found"],
		["brackenmoor_abbey", "abbey_undercroft", "default", ""],
		["abbey_undercroft", "brackenmoor_abbey", "from_undercroft", ""],
	]
	var scenes = {}
	for row in want:
		for id in [row[0], row[1]]:
			if not scenes.has(id):
				scenes[id] = load(registry.get_location_scene(id)).instantiate()
	for row in want:
		var found = _triggers(scenes[row[0]]).filter(func(t): return str(t.target_location) == row[1])
		_check("%s has a way to %s" % [row[0], row[1]], not found.is_empty())
		for t in found:
			_check("...%s lands on %s/%s" % [t.name, row[1], row[2]], str(t.target_spawn_point) == row[2] and _spawn(scenes[row[1]], row[2]) != null)
			_check("...%s needs '%s'%s" % [t.name, row[3], " and says why it is shut" if row[3] != "" else ""],
				str(t.requires_flag) == row[3] and (row[3] == "" or str(t.closed_text).length() > 20))
	_check("Two ways down from the old workings (winze and adit)", _triggers(scenes.old_workings).filter(func(t): return t.target_location == "the_pit").size() == 2)
	for s in scenes.values():
		s.free()

## Every spawn point, way and creature marker stands on open ground inside the walls
func _test_ground() -> void:
	print("\nOpen ground")
	for id in ["greystone_mines", "the_pit", "old_workings", "abbey_undercroft", "brackenmoor_abbey"]:
		var scene = load(registry.get_location_scene(id)).instantiate()
		var solids = _solids(scene)
		var bounds = _bounds(solids)
		var bad: Array = []
		var points: Array = []
		for group in ["SpawnPoints", "CreatureSpawns"]:
			var holder = scene.find_child(group, true, false)
			if holder:
				for m in holder.get_children():
					if m is Marker2D:
						points.append(["%s/%s" % [group, m.name], _pos(m)])
		for t in _triggers(scene):
			points.append(["way %s" % t.name, _pos(t)])
		for p in points:
			var body = Rect2(p[1] - Vector2(PLAYER_BODY.x / 2.0, PLAYER_BODY.y), PLAYER_BODY)
			var inside = bounds.has_area() and bounds.encloses(Rect2(p[1], Vector2.ONE))
			if not inside or (p[0].begins_with("way ") == false and solids.any(func(r): return r.intersects(body))):
				bad.append(p[0])
		_check("%s: %d points on open ground inside the walls%s" % [id, points.size(), "" if bad.is_empty() else " (" + ", ".join(bad) + ")"], bad.is_empty())
		if id in ["greystone_mines", "the_pit"]:
			var holder = scene.find_child("CreatureSpawns", true, false)
			_check("%s has CreatureSpawns markers" % id, holder != null and holder.get_children().filter(func(m): return m is Marker2D).size() >= 3)
		scene.free()

func _test_gate() -> void:
	print("\nThe way to the Pit")
	_reset()
	var t = load(SCENE_TRIGGER).new()
	t.target_location = "the_pit"
	t.requires_flag = "old_workings_way_found"
	t.closed_text = "No way down you have found."
	var refused: Array = []
	t.refused.connect(func(_trigger, reason): refused.append(reason))
	root.add_child(t)
	_check("Shut until the way is found, with its reason", not t.is_open() and t.why_closed() == "No way down you have found.")
	t._trigger_transition()
	_check("...trying it says so and goes nowhere", refused == ["No way down you have found."] and not t.transition_cooldown)
	world_state.set_world_flag("old_workings_way_found", true)
	_check("Open once the way is found", t.is_open())
	t.closed_reason = "The cage is wedged in the winze."
	_check("...unless the room says this way is stopped", not t.is_open() and t.why_closed() == "The cage is wedged in the winze.")
	t.free()
	_reset()

func _test_old_workings_play() -> void:
	print("\nPlaying the old workings: the winze")
	_reset()
	var room = load("res://scenes/puzzles/old_workings.tscn").instantiate()
	root.add_child(room)
	await process_frame
	var winze = room.find_child("WinzeWay", true, false)
	var adit = room.find_child("AditWay", true, false)
	var tub = room.find_child("OreTub", true, false)
	var push = tub.find_child("Push", false, false)
	var cut = room.find_child("CageRope", true, false).find_child("Cut", false, false)
	_check("Both ways down are shut before anything is done", not winze.is_open() and not adit.is_open())
	_check("...the winze for want of a cage that can ride", winze.why_closed().contains("cage"))
	var out = cut.perform()
	_check("No blade, no cut: the rope holds and says why", not out.ok and out.reason == "no_blade" and str(out.text).contains("nothing") and not room.find_child("CageRope", true, false).is_cut)
	out = push.perform()
	physics.step(0.1)
	_check("The ore tub rolled onto the treadle", out.ok and push.at_destination() and puzzles.get_room_state("old_workings").get("tub_on_brake", false))
	_check("...weighs the winch brake down", puzzles.get_room_state("old_workings").get("brake_on", false))
	inventory.add("knife")
	out = cut.perform()
	_check("With a knife the rope is cut, and the cage rides down on the brake", out.ok and puzzles.get_room_state("old_workings").cage == "down")
	_check("The way into the Pit is found", world_state.get_world_flag("old_workings_way_found") and puzzles.is_solved("old_workings"))
	_check("...the winze is open, the barred adit still shut", winze.is_open() and not adit.is_open() and adit.why_closed().contains("timbers"))
	room.free()
	await process_frame
	room = load("res://scenes/puzzles/old_workings.tscn").instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	_check("Back in the room: the tub still on the treadle, the winze still open",
		room.find_child("OreTub", true, false).find_child("Push", false, false).at_destination() and room.find_child("WinzeWay", true, false).is_open())
	room.free()
	_reset()

	print("\nPlaying the old workings: the cage jams")
	room = load("res://scenes/puzzles/old_workings.tscn").instantiate()
	root.add_child(room)
	await process_frame
	inventory.add("knife")
	room.find_child("CageRope", true, false).find_child("Cut", false, false).perform()
	physics.step(0.1)
	_check("Cut with the brake off: the cage jams and nothing is found", puzzles.get_room_state("old_workings").get("cage", "") == "jammed" and not world_state.get_world_flag("old_workings_way_found"))
	world_state.set_world_flag("old_workings_way_found", true)
	_check("...and the winze stays stopped even once the way is known", not room.find_child("WinzeWay", true, false).is_open())
	room.free()
	await process_frame
	_reset()

func _test_old_workings_fire() -> void:
	print("\nPlaying the old workings: the adit")
	_reset()
	var room = load("res://scenes/puzzles/old_workings.tscn").instantiate()
	root.add_child(room)
	await process_frame
	var fire = room.find_child("Barricade", true, false).find_child("Fire", false, false)
	var lamp = room.find_child("Lamp", true, false)
	lamp.set_lit(false)
	var out = fire.perform()
	_check("No flame and the lamp out: the timbers will not light", not out.ok and out.reason == "no_flame")
	lamp.set_lit(true)
	out = fire.perform()
	_check("The room's lamp lends its flame: the timbers catch", out.ok)
	physics.simulate(30.0, 0.5)
	await process_frame
	var events = root.get_node("PlayerEvents").get_events().filter(func(e): return e.kind == "fire" and "dagna" in e.get("about", []))
	_check("...a fire the player started, in Dagna's timber: a deed", not events.is_empty())
	_check("Burned out: the adit is the way, and it is found", puzzles.get_room_state("old_workings").get("adit", "") == "open"
		and world_state.get_world_flag("old_workings_way_found"))
	var adit = room.find_child("AditWay", true, false)
	_check("...the adit is open, the winze (cage still up) shut", adit.is_open() and not room.find_child("WinzeWay", true, false).is_open())
	_check("...and the block across it is gone", room.find_child("AditBlock", true, false) == null)
	room.free()
	await process_frame
	_reset()

func _test_undercroft_play() -> void:
	print("\nPlaying the undercroft")
	_reset()
	var room = load("res://scenes/puzzles/abbey_undercroft.tscn").instantiate()
	root.add_child(room)
	await process_frame
	var chest = room.find_child("ReliquaryChest", true, false)
	var push = chest.find_child("Push", false, false)
	var book = room.find_child("SaintsDaysBook", true, false)
	var lamp = room.find_child("HangingLamp", true, false)
	_check("The undercroft lamp hangs lit, a closed lantern that lights nothing it does not fall on", lamp.lit and not lamp.open_flame)
	physics.simulate(20.0, 0.5)
	_check("...so the dull shelves do not catch on their own", puzzles.get_room_state("abbey_undercroft").get("letters", "hidden") == "hidden")
	push.perform()
	physics.step(0.1)
	_check("The chest dragged onto the southern kneeling stone weighs it", puzzles.get_room_state("abbey_undercroft").get("south", false)
		and puzzles.get_room_state("abbey_undercroft").get("grate", "shut") == "shut")
	var person = Node2D.new()
	person.add_to_group("player")
	room.add_child(person)
	person.global_position = room.find_child("KneelerNorth", true, false).global_position
	physics.step(0.1)
	_check("A person on the other: the grate lifts", puzzles.get_room_state("abbey_undercroft").get("grate", "") == "open" and book.enabled)
	person.global_position = Vector2(0, 400)
	physics.step(0.1)
	_check("...and the pawl holds it when they step off", puzzles.get_room_state("abbey_undercroft").grate == "open")
	_check("The stair back up to the archive is open", room.find_child("StairUp", true, false).is_open())
	room.free()
	await process_frame
	_reset()

	room = load("res://scenes/puzzles/abbey_undercroft.tscn").instantiate()
	root.add_child(room)
	await process_frame
	var cut = room.find_child("LampRope", true, false).find_child("Cut", false, false)
	_check("No blade: the lamp rope holds", not cut.perform().ok and not puzzles.get_room_state("abbey_undercroft").get("lamp_fallen", false))
	inventory.add("knife")
	_check("Cut it while the lamp burns and it falls into the shelves", cut.perform().ok and puzzles.get_room_state("abbey_undercroft").get("lamp_fallen", false))
	physics.simulate(40.0, 0.5)
	await process_frame
	_check("...the shelves burn, and the letters with them", puzzles.get_room_state("abbey_undercroft").get("letters", "") == "burned"
		and not world_state.get_world_flag("salt_letters_second_set_found"))
	room.free()
	await process_frame
	_reset()

func _test_examinables() -> void:
	print("\nClue examinables")
	var expect = {
		"weigh_the_tiles": [["UrnTiles", "res://scenes/interiors/thornhaven_chapel.tscn"], ["BjornsScale", "res://scenes/interiors/blacksmith_interior.tscn"]],
		"abbey_receipt": [["AnselmShelfIndex", "res://scenes/interiors/brackenmoor_abbey.tscn"]],
	}
	# What would give the answer away: the answer itself, the right option's words, the conclusion
	var giveaways = {
		"weigh_the_tiles": ["lectern", "light", "filed", "recut"],
		"abbey_receipt": ["seventh", "iii.7, leaf", "leaf twelve", "remedy that answered", "one that worked"],
	}
	for pid in expect:
		var p = puzzles.puzzles[pid]
		var right = str(p.answer.correct)
		var label = ""
		for o in p.answer.options:
			if str(o.id) == right:
				label = str(o.label).to_lower()
		for row in expect[pid]:
			var scene = load(row[1]).instantiate()
			var node = scene.find_child(row[0], true, false)
			var ok = node != null and node.get_script() and node.get_script().resource_path == STORY_ITEM
			_check("%s is a StoryItem in %s" % [row[0], row[1].get_file()], ok)
			if ok:
				var text = (str(node.discovery_text) + " " + str(node.reexamine_text)).to_lower()
				_check("...opens %s" % pid, str(node.puzzle_id) == pid)
				var leaks = giveaways[pid].filter(func(w): return text.contains(w))
				_check("...shows the clue, never the answer%s" % ("" if leaks.is_empty() else " (" + ", ".join(leaks) + ")"),
					text.length() > 80 and leaks.is_empty() and not text.contains(label) and not text.contains(right.replace("_", " ")))
				var clue = p.clues.filter(func(c): return str(c.id) == row[0])
				_check("...and is the puzzle's clue in its scene", clue.size() == 1 and str(clue[0].kind) == "story_item" and str(clue[0].scene) == row[1])
			scene.free()

	_reset()
	# The real PlayerUI (and any DialogueUI) step aside for the fakes while the item is examined
	var real_ui = get_nodes_in_group("player_ui") + get_nodes_in_group("dialogue_ui")
	for n in real_ui:
		n.remove_from_group("player_ui")
		n.remove_from_group("dialogue_ui")
	var ui = FakeUI.new()
	ui.add_to_group("player_ui")
	root.add_child(ui)
	var dialogue = FakeDialogue.new()
	dialogue.add_to_group("dialogue_ui")
	root.add_child(dialogue)
	var item = load(STORY_ITEM).new()
	item.name = "BjornsScale"
	item.puzzle_id = "weigh_the_tiles"
	item.discovery_text = "A brass beam scale."
	root.add_child(item)
	item._on_interact()
	await process_frame
	_check("Looked at before the drawn tile is seen: the clue, no answer card", ui.opened.is_empty() and dialogue.said.size() == 1)
	world_state.set_world_flag("recut_tile_seen", true)
	item._on_interact()
	await process_frame
	_check("Once the puzzle is open: the answer card", ui.opened == ["weigh_the_tiles"])
	puzzles.answer("weigh_the_tiles", "lectern_tile")
	item._on_interact()
	await process_frame
	_check("Solved: no card again", ui.opened.size() == 1)
	item.free()
	ui.free()
	dialogue.free()
	for n in real_ui:
		n.add_to_group("player_ui" if n.has_method("open_puzzle") else "dialogue_ui")
	world_state.set_world_flag("tn_lot_rigged_known", false)
	_reset()

## Each puzzle flag opens a beat in its storyline; nothing is decided for anyone by the flag alone
func _test_story_reactions() -> void:
	print("\nThe world reacts")
	var director = root.get_node("StorylineDirector")
	var rows = [
		["smiths_oath", "the_hand_at_the_mould", ["spare_tiles_traced_to_davin", "davin_found"]],
		["iron_hand", "five_names_in_the_sums", ["ledger_names_decoded"]],
		["fence_of_highmarch", "the_ferrymans_mark", ["tally_matched_to_register"]],
		["tithe_night", "the_back_seam", ["old_workings_way_found", "tn_taken_alive_known"]],
		["grey_fever", "letters_from_the_undercroft", ["salt_letters_second_set_found"]],
	]
	for row in rows:
		_check("%s/%s waits for its flags" % [row[0], row[1]], director.get_beat_status(row[0], row[1]) == "locked")
	for row in rows:
		for f in row[2]:
			world_state.set_world_flag(f, true)
	await process_frame
	for row in rows:
		_check("%s/%s opens on %s, and is not decided by it" % [row[0], row[1], ", ".join(row[2])], director.get_beat_status(row[0], row[1]) == "open")
	_check("The back seam is a road to the Pit before the cart, not the Pit freed", not world_state.get_world_flag("tn_freed_the_pit"))
	director.reset_state()
	for row in rows:
		for f in row[2]:
			world_state.set_world_flag(f, false)

# =============================================================================

func _triggers(scene: Node) -> Array:
	return _all(scene).filter(func(n): return n.get_script() != null and n.get_script().resource_path == SCENE_TRIGGER)

func _spawn(scene: Node, spawn_name: String) -> Node:
	var points = scene.find_child("SpawnPoints", true, false)
	var m = points.find_child(spawn_name, false, false) if points else null
	return m if m is Marker2D else null

## Rects of every StaticBody2D's rectangle shapes, in scene coordinates
func _solids(scene: Node) -> Array:
	var out: Array = []
	for n in _all(scene):
		if n is StaticBody2D:
			for c in n.get_children():
				if c is CollisionShape2D and c.shape is RectangleShape2D:
					var size: Vector2 = c.shape.size
					out.append(Rect2(_pos(c) - size / 2.0, size))
	return out

## The inner rectangle of the walls: the largest box the solids at the edges close in
func _bounds(solids: Array) -> Rect2:
	if solids.is_empty():
		return Rect2()
	var outer = solids[0]
	for r in solids:
		outer = outer.merge(r)
	var left = outer.position.x
	var right = outer.end.x
	var top = outer.position.y
	var bottom = outer.end.y
	for r in solids:
		if r.size.y > outer.size.y * 0.8:   # an east or west wall
			if r.get_center().x < outer.get_center().x:
				left = maxf(left, r.end.x)
			else:
				right = minf(right, r.position.x)
		if r.size.x > outer.size.x * 0.8:   # a north or south wall
			if r.get_center().y < outer.get_center().y:
				top = maxf(top, r.end.y)
			else:
				bottom = minf(bottom, r.position.y)
	return Rect2(left, top, right - left, bottom - top)

## Position in scene coordinates (the scenes use no rotation or scale on these nodes)
func _pos(n: Node) -> Vector2:
	var p = Vector2.ZERO
	var cur = n
	while cur and cur.get_parent() != null:
		if cur is Node2D:
			p += cur.position
		cur = cur.get_parent()
	return p

func _all(node: Node) -> Array:
	var out: Array = [node]
	for c in node.get_children():
		out.append_array(_all(c))
	return out

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
