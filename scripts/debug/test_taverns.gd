extends SceneTree

# Tests taverns (docs/WORLD_SCHEMA.md "Taverns"): rooms that exist, renting by the night, lodgers,
# locked rooms and trespass, a keeper's refusal, renting in conversation, the back rooms of a house
# that keeps them (brothel: true), who judges a visit, the companions' night talk, and save/load
# - every tavern's scene holds at least `rooms` Bed nodes at its rent, each with its own spawn marker,
#   door and walls on layer 3; the Halfway House has back rooms, the Rusty Nail none
# - a room costs its rent once a night, is the player's until checkout, and sets where they wake
# - travellers take free rooms of an evening, one to a room, never a child; a lodger's room is locked
#   and walking in is a trespass deed
# - a keeper who thinks badly of the player will not let a room, at the bed or in conversation
# - companions are adults; the back rooms shut while a child is in the house; a visit costs coin,
#   passes time and is a seen_at deed; the pious disapprove and others do not care
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_taverns.gd

const TAVERNS = preload("res://scripts/world/taverns.gd")
const Rep = preload("res://scripts/world_state/reputation.gd")

const WAY = "kingsroad_waystation"
const NAIL = "thornhaven_tavern"
const DAY = 1440

var taverns: Node
var made_taverns: bool = false
var inv: Node
var pe: Node
var world_state: Node
var director: Node
var registry: Node
var stats: Node
var gm = null
var failures: int = 0
var saved_pe: Dictionary
var saved_minutes: int
var saved_flags: Dictionary
var save_existed: bool

func _init():
	await process_frame
	await process_frame
	taverns = root.get_node_or_null("Taverns")
	if taverns == null:
		taverns = TAVERNS.new()
		taverns.name = "Taverns"
		root.add_child(taverns)
		made_taverns = true
	inv = root.get_node("Inventory")
	pe = root.get_node("PlayerEvents")
	world_state = root.get_node("WorldState")
	director = root.get_node("StorylineDirector")
	registry = root.get_node("WorldRegistry")
	stats = root.get_node("PlayerStats")
	var dyn = root.get_node_or_null("DynamicNPCRegistry")
	gm = dyn.generics if dyn and "generics" in dyn else null
	world_state.set_idle_clock_rate(0.0)
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	stats.move_on_respawn = false
	inv.auto_recognise = false
	saved_pe = pe.save()
	saved_minutes = world_state.game_minutes
	saved_flags = world_state.world_flags.duplicate(true)
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	pe.capture_enabled = false
	print("============================================================")
	print("🧪 TAVERNS TEST")
	print("============================================================\n")

	_test_rooms_exist()
	_test_renting_at_the_bed()
	_test_lodgers_and_trespass()
	_test_keeper_refuses()
	_test_renting_in_conversation()
	_test_back_rooms()
	_test_judgement_and_talk()
	_test_save()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _at(day: int, hour: int) -> int:
	return day * DAY + hour * 60

func _clock(minute: int) -> void:
	taverns.now_override = minute
	pe.now_override = minute
	world_state.game_minutes = minute

func _fresh() -> void:
	taverns.reset()
	taverns.present_override = {}
	inv.reset()
	stats.reset()
	pe.reset()
	director.relationship_dims_override = {}

# =============================================================================
# 1. ROOMS THAT EXIST
# =============================================================================

func _test_rooms_exist() -> void:
	print("Rooms that exist")
	for loc in [WAY, NAIL]:
		var t: Dictionary = taverns.tavern(loc)
		var rooms: Array = taverns.lettable(loc)
		_check("%s has a tavern block (%d rooms at %d copper)" % [loc, int(t.get("rooms", 0)), int(t.get("rent_copper", 0))], not t.is_empty())
		_check("...and its scene has a Bed at that rent for every room (%d)" % rooms.size(),
			rooms.size() >= int(t.rooms) and taverns.rooms(loc).filter(func(r): return not r.back_room).all(func(r): return int(r.rent) == int(t.rent_copper)))
		var packed = load(str(registry.get_location(loc).scene))
		var scene: Node = packed.instantiate()
		var spawns = scene.get_node("SpawnPoints")
		_check("...each room has its own spawn marker", rooms.all(func(r): return spawns.get_node_or_null(str(r)) is Marker2D))
		var doors = scene.find_children("*Door", "Area2D", true, false).filter(func(d): return d.get_script() and d.get_script().resource_path.ends_with("room_door.gd"))
		_check("...and a door into it (%d doors)" % doors.size(), doors.size() >= int(t.rooms) - (1 if loc == WAY else 0))
		var bad: Array = scene.find_children("*", "StaticBody2D", true, false).filter(func(b): return b.collision_layer == 1)
		_check("...no wall or bed on the player's layer", bad.is_empty())
		var walls: Array = scene.get_node("Walls").get_children().filter(func(b): return b is StaticBody2D and b.collision_layer == 4)
		_check("...room walls stand on layer 3 (%d)" % walls.size(), walls.size() > 4)
		scene.free()
	_check("The Halfway House keeps back rooms", taverns.is_brothel(WAY) and taverns.back_rooms(WAY).size() == 2)
	_check("The Rusty Nail does not", not taverns.is_brothel(NAIL) and taverns.back_rooms(NAIL).is_empty())

# =============================================================================
# 2. RENTING AT THE BED
# =============================================================================

func _bed(loc: String, room: String) -> Node:
	var packed = load(str(registry.get_location(loc).scene))
	var scene: Node = packed.instantiate()
	var bed: Node = null
	for b in scene.find_children("*", "Area2D", true, false):
		if b is Bed and b.spawn_point == room:
			bed = b
	bed.get_parent().remove_child(bed)
	scene.free()
	root.add_child(bed)
	return bed

func _test_renting_at_the_bed() -> void:
	print("\nRenting at the bed")
	_fresh()
	_clock(_at(3, 20))
	var bed = _bed(NAIL, "room_1")
	inv.coin = 2
	var r: Dictionary = bed.sleep()
	_check("Too little coin: no room", not r.ok and inv.get_coin() == 2 and taverns.my_room(NAIL).is_empty())
	inv.coin = 10
	r = bed.sleep()
	_check("The Rusty Nail's village price: 3 copper, and the player wakes in room 1", r.ok and r.paid == 3 and inv.get_coin() == 7 \
		and stats.get_respawn() == {"location": NAIL, "spawn_point": "room_1"})
	_check("The room is theirs until the morning", str(taverns.my_room(NAIL).get("room", "")) == "room_1" and int(taverns.my_room(NAIL).until) == _at(4, 10))
	r = bed.sleep()
	_check("Sleeping in it again that night costs nothing", r.ok and r.paid == 0 and inv.get_coin() == 7)
	_clock(_at(4, 11))
	_check("After checkout it is not theirs", taverns.my_room(NAIL).is_empty() and taverns.room_status(NAIL, "room_1") == "free")
	r = bed.sleep()
	_check("...and another night costs again", r.ok and r.paid == 3 and inv.get_coin() == 4)
	bed.free()

# =============================================================================
# 3. LODGERS, LOCKED ROOMS AND TRESPASS
# =============================================================================

func _way_people() -> Array:
	return gm.get_ids_at(WAY) if gm else []

func _first_of(archetype: String, location: String = "") -> String:
	if gm == null:
		return ""
	for id in gm.get_ids():
		var inst = gm.get_instance(id)
		if inst and str(inst.archetype_id) == archetype and (location == "" or gm.get_location(id) == location):
			return id
	return ""

func _test_lodgers_and_trespass() -> void:
	print("\nLodgers, locked rooms and trespass")
	_fresh()
	var people = _way_people()
	var courier = _first_of("courier", WAY)
	var child = _first_of("warrens_urchin")
	_check("The Halfway House has a courier and companions (%s)" % ", ".join(people), courier != "" and people.any(func(w): return taverns.is_companion(str(w))))
	taverns.present_override[WAY] = people + [child, "wren"]
	_clock(_at(5, 14))
	_check("By day nobody lodges", taverns.lodgers(WAY).is_empty())
	_clock(_at(5, 22))
	var lodgers: Dictionary = taverns.lodgers(WAY)
	_check("Of an evening the travellers take rooms (%s)" % str(lodgers), courier in lodgers.values())
	_check("...one to a room", lodgers.values().size() == lodgers.size() and lodgers.keys().all(func(r): return r in taverns.lettable(WAY)))
	_check("...never the keeper, a companion or a child", not lodgers.values().any(func(w): return w == "wren" or w == child or taverns.is_companion(str(w))))
	var taken = ""
	for room in lodgers:
		if lodgers[room] == courier:
			taken = room
	var bed = _bed(WAY, taken)
	inv.coin = 50
	var r: Dictionary = bed.sleep()
	_check("A lodger's room is locked to the player", not r.ok and str(r.reason).contains("locked") and inv.get_coin() == 50)
	bed.free()
	var door = load("res://scripts/world/room_door.gd").new()
	door.location_id = WAY
	door.room = taken
	root.add_child(door)
	var deed = door.enter(Vector2.ZERO)
	_check("Walking into it is a trespass deed about the lodger", deed != "" and pe.events[deed].kind == "trespass" and _who(courier) in pe.events[deed].about)
	_check("...once a night", door.enter(Vector2.ZERO) == "")
	var free_room = taverns.free_rooms(WAY)[0]
	door.room = free_room
	_check("An empty, unlet room is nobody's: no deed", door.enter(Vector2.ZERO) == "")
	door.free()
	r = taverns.rent(WAY)
	_check("Renting takes a free room, never the lodger's (%s)" % str(r.get("room", "")), r.ok and r.room != taken and r.paid == 4)
	_check("...and the lodgers keep theirs", taverns.lodgers(WAY).get(taken, "") == courier)

# =============================================================================
# 4. A KEEPER'S REFUSAL
# =============================================================================

func _test_keeper_refuses() -> void:
	print("\nA keeper who will not let a room")
	_fresh()
	_clock(_at(6, 19))
	inv.coin = 50
	_check("A stranger nobody knows may have a room", taverns.refusal(NAIL) == "")
	for i in 3:
		pe.record("harm", "beat a regular senseless in the Rusty Nail", ["mira"], {"witnesses": ["mira"], "location": NAIL, "spread": false})
	_check("Mira thinks badly of the player (%.0f)" % Rep.of("npc", "mira"), Rep.of("npc", "mira") < taverns.REFUSE_BELOW)
	var bed = _bed(NAIL, "room_2")
	var r: Dictionary = bed.sleep()
	_check("...and will not let them a room at the bed", not r.ok and str(r.reason).contains("will not let") and inv.get_coin() == 50)
	bed.free()
	var block: String = director.get_conversation_agency_block("mira")
	_check("...her conversation says so", block.contains("will not let this stranger a room"))
	var res: Dictionary = director.apply_conversation_actions("mira", [{"type": "rent_room", "price": 3}])
	_check("...and her own rent_room is refused", res.applied.is_empty() and str(res.dropped[0].reason).contains("will not let"))
	_check("Old Wren, who knows nothing of it, still would", taverns.refusal(WAY) == "")

# =============================================================================
# 5. RENTING IN CONVERSATION
# =============================================================================

func _test_renting_in_conversation() -> void:
	print("\nRenting from the keeper in conversation")
	_fresh()
	_clock(_at(7, 18))
	inv.coin = 20
	var block: String = director.get_conversation_agency_block("wren")
	_check("Wren's conversation offers rent_room at her usual 4", block.contains("rent_room") and block.contains("N=4"))
	var res: Dictionary = director.apply_conversation_actions("wren", [{"type": "rent_room", "price": 4}])
	_check("Her rent_room lets the player a room for the night", res.applied.size() == 1 and str(taverns.my_room(WAY).get("room", "")) != "" and inv.get_coin() == 16)
	_check("...priced by her (applied %s)" % str(res.applied), int(res.applied[0].price) == 4 and str(res.applied[0].room) == str(taverns.my_room(WAY).room))
	block = director.get_conversation_agency_block("wren")
	_check("Then her block knows the stranger has a room", block.contains("already has a room"))
	var bed = _bed(WAY, str(taverns.my_room(WAY).room))
	var r: Dictionary = bed.sleep()
	_check("Sleeping in the room she let costs nothing more", r.ok and r.paid == 0 and inv.get_coin() == 16 and stats.get_respawn().spawn_point == bed.spawn_point)
	bed.free()
	res = director.apply_conversation_actions("gregor", [{"type": "rent_room", "price": 1}])
	_check("Someone who keeps no tavern cannot let a room", res.applied.is_empty())
	_clock(_at(7, 19))
	res = director.apply_conversation_actions("mira", [{"type": "rent_room", "price": 0}])
	_check("Mira may give a room on the house", res.applied.size() == 1 and int(res.applied[0].price) == 0 and inv.get_coin() == 16)

# =============================================================================
# 6. THE BACK ROOMS
# =============================================================================

func _test_back_rooms() -> void:
	print("\nThe back rooms")
	_fresh()
	_clock(_at(8, 20))
	var arch = gm.archetypes.get("house_companion") if gm else null
	_check("The companion archetype loads, and is not a child", arch != null and not gm.is_minor("house_companion"))
	_check("...its essence says they are grown, and choose", arch != null and arch.essence.contains("twenty") and arch.essence.contains("decides who"))
	var companion = _first_of("house_companion", WAY)
	_check("Companions live at the Halfway House only (%s)" % companion, companion != "" \
		and gm.get_ids().filter(func(id): return str(gm.get_instance(id).archetype_id) == "house_companion").all(func(id): return taverns.is_brothel(gm.get_location(id))))
	taverns.present_override[WAY] = _way_people()
	_check("The back rooms are open with no child about", taverns.brothel_open(WAY) and companion in taverns.companions(WAY))
	var block: String = director.get_conversation_agency_block(companion)
	_check("A companion's conversation offers company, theirs to refuse, never described", block.contains("\"company\"") and block.contains("may refuse anyone") and block.contains("never describe it"))
	inv.coin = 10
	var res: Dictionary = director.apply_conversation_actions(companion, [{"type": "company", "price": 15}])
	_check("It costs coin: refused when the purse is short", res.applied.is_empty() and inv.get_coin() == 10)
	inv.coin = 40
	var before = world_state.game_minutes
	res = director.apply_conversation_actions(companion, [{"type": "company", "price": 15}])
	_check("Their yes: coin paid, an hour passes", res.applied.size() == 1 and inv.get_coin() == 25 and world_state.game_minutes - before == 60)
	var seen = pe.order.map(func(id): return pe.events[id]).filter(func(e): return e.kind == "seen_at" and str(e.summary).contains("back rooms"))
	_check("...and it is a deed those present may learn of", seen.size() == 1 and _who(companion) in seen[0].about)
	_check("...that says nothing of what passed", not str(seen[0].summary).to_lower().contains("bed"))
	var child = _first_of("warrens_urchin")
	taverns.present_override[WAY] = _way_people() + [child]
	_check("With a child in the house the back rooms are shut", not taverns.brothel_open(WAY) and taverns.company_denial(companion, WAY).contains("child"))
	_check("...and company is not even offered", not director.get_conversation_agency_block(companion).contains("\"company\""))
	res = director.apply_conversation_actions(companion, [{"type": "company", "price": 15}])
	_check("...nor taken", res.applied.is_empty() and inv.get_coin() == 25)
	_check("The Rusty Nail keeps no back rooms", taverns.company_denial(companion, NAIL) != "")
	_check("Wren is no companion", not taverns.is_companion("wren"))
	var door = load("res://scripts/world/room_door.gd").new()
	door.location_id = WAY
	door.room = "back_room_1"
	root.add_child(door)
	taverns.present_override[WAY] = _way_people()
	var deed = door.enter(Vector2.ZERO)
	_check("Walking into a back room uninvited is trespass", deed != "" and pe.events[deed].kind == "trespass")
	door.free()
	var bed = _bed(WAY, "back_room_1")
	_check("A back room is never let to sleep in", not bed.sleep().ok)
	bed.free()

# =============================================================================
# 7. JUDGEMENT AND NIGHT TALK
# =============================================================================

func _test_judgement_and_talk() -> void:
	print("\nWho judges, and what the companions hear")
	_fresh()
	_check("The infirmarian of the Cathedral disapproves", taverns.is_pious("ysolde"))
	_check("The abbey's archivist disapproves", taverns.is_pious("anselm"))
	var pilgrim = _first_of("pilgrim")
	_check("A pilgrim disapproves", pilgrim != "" and taverns.is_pious(pilgrim))
	var pious: Array = director.get_soul_keys().filter(func(k): return registry.get_npc_key(str(k)) != "" and taverns.is_pious(str(k)))
	_check("Most do not care (%s)" % ", ".join(pious), not taverns.is_pious("gregor") and not taverns.is_pious("wren") and not taverns.is_pious("rook") and pious.size() <= 4)
	_check("A party's judgement is the mean of its people", is_equal_approx(taverns.judgement(["ysolde", "gregor"]), taverns.DISAPPROVAL / 2.0) and taverns.judgement(["gregor"]) == 0.0)
	_clock(_at(9, 22))
	var people = _way_people()
	taverns.present_override[WAY] = people
	var lodger = str(taverns.lodgers(WAY).values()[0]) if not taverns.lodgers(WAY).is_empty() else ""
	var ev = pe.record("theft", "lifted a purse at Ferrisford", [], {"witnesses": [lodger], "location": "ferrisford", "spread": false})
	var passed: Array = taverns.pillow_talk(WAY)
	_check("What a lodger knows of the stranger reaches the companions by night (%s)" % lodger, lodger != "" and ev in passed)
	var hearer = str(taverns.companions(WAY)[0])
	_check("...a companion knows it now, and can tell it on", pe.knowledge_of([hearer]).has(ev) or pe.in_flight.any(func(f): return str(f.event) == ev and str(f.via) == taverns.PILLOW_TALK_VIA))
	_check("...once a night", taverns.pillow_talk(WAY).is_empty())
	taverns.present_override[WAY] = people + [_first_of("warrens_urchin")]
	_clock(_at(10, 22))
	_check("No back-room talk while a child is in the house", taverns.pillow_talk(WAY).is_empty())

# =============================================================================
# 8. SAVE / LOAD
# =============================================================================

func _test_save() -> void:
	print("\nSave and load")
	_fresh()
	_clock(_at(11, 21))
	inv.coin = 10
	taverns.rent(NAIL, "room_3")
	var data = taverns.save()
	taverns.reset()
	_check("Reset: no room", taverns.my_room(NAIL).is_empty())
	taverns.load_from_dict(JSON.parse_string(JSON.stringify(data)))
	_check("Loaded: the night's room is the player's again", str(taverns.my_room(NAIL).get("room", "")) == "room_3" and int(taverns.my_room(NAIL).until) == _at(12, 10))

# =============================================================================

func _who(x: String) -> String:
	return str(pe._who(x))

func _restore() -> void:
	taverns.reset()
	taverns.now_override = -1
	taverns.present_override = {}
	if made_taverns:
		taverns.queue_free()
	inv.reset()
	inv.auto_recognise = true
	stats.reset()
	stats.move_on_respawn = true
	director.relationship_dims_override = {}
	pe.now_override = -1
	pe.capture_enabled = true
	pe.reset()
	pe.load_from_dict(saved_pe)
	world_state.world_flags = saved_flags
	world_state.game_minutes = saved_minutes
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
