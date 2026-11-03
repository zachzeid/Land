extends SceneTree

# Tests five gaps between the player systems and the world (docs/PLAYER_SYSTEMS.md §2, §5.1, §6):
# - a pack by the road: the finder is found where the pack lies (near_event), not where the player is
#   now; who took it is recorded; in conversation the holder's soul may sell or give it back
#   (return_pack), its Lines may refuse; the player may steal it back (a theft deed) or take it by
#   force (a kill deed about the holder)
# - fire deeds: a fire the player lights is a `fire` deed when it catches someone's thing (with the
#   witnesses who saw it lit), doused or burned later as an outcome, never a second deed
# - lamps: a lit lamp lets a watcher see a deed in its light at night, dousing it hides it again, and
#   a watcher standing in lamp light sees less of the dark beyond (lamps reveal and blind)
# - teaching in conversation (teach): a teacher's own action trains the player for coin or a favour,
#   in game time; not their trade, a child and fighting, or a short purse are refused
# - beds and camps: an inn bed (rent) and a bedroll by a campfire outdoors set where the player wakes;
#   death wakes them there; a camp puts them at the bedroll; respawn survives a save
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_world_gaps.gd

const FLAMMABLE = preload("res://scripts/world/physics/flammable.gd")
const LAMP = preload("res://scripts/world/physics/lamp.gd")
const BED = preload("res://scripts/world/bed.gd")
const Camp = preload("res://scripts/world/camp.gd")
const Witnesses = preload("res://scripts/world/witnesses.gd")

class _Body extends Node2D:
	var npc_id: String = ""
	var is_alive: bool = true

var inv: Node
var pe: Node
var world_state: Node
var director: Node
var registry: Node
var propagator: Node
var physics: Node
var stats: Node
var crafting: Node
var failures: int = 0
var saved_pe: Dictionary
var saved_propagation: Dictionary
var saved_flags: Dictionary
var saved_npc_states: Dictionary
var saved_minutes: int
var save_existed: bool

func _init():
	await process_frame
	await process_frame
	inv = root.get_node("Inventory")
	pe = root.get_node("PlayerEvents")
	world_state = root.get_node("WorldState")
	director = root.get_node("StorylineDirector")
	registry = root.get_node("WorldRegistry")
	propagator = root.get_node("EventPropagator")
	physics = root.get_node("WorldPhysics")
	stats = root.get_node("PlayerStats")
	crafting = root.get_node("Crafting")
	world_state.set_idle_clock_rate(0.0)
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	physics.auto_step = false
	physics.region_override = "test_region"
	stats.move_on_respawn = false
	saved_pe = pe.save()
	saved_propagation = propagator.save()
	saved_flags = world_state.world_flags.duplicate(true)
	saved_npc_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	inv.auto_recognise = false
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	director.load_emergence("res://resources/emergence")
	print("============================================================")
	print("🧪 WORLD GAPS TEST")
	print("============================================================\n")

	await _test_pack_recovery()
	await _test_fire_deeds()
	await _test_lamps()
	_test_teach_in_conversation()
	_test_beds_and_camps()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================
# 1. A PACK BY THE ROAD
# =============================================================================

## Drop a pack at `place` with the player elsewhere; the finder's soul (hostile dims) takes it.
## Returns the finder key ("" when nobody came upon it)
func _a_taken_pack(place: String) -> String:
	inv.reset()
	pe.reset()
	world_state.world_flags = {}
	director.reset_state()
	director.get_emergence().reset()
	inv.location_override = place
	director.player_location_override = place
	var there: Array = director.get_emergence().near_event({"location": place})
	var dims = {}
	for k in director.get_soul_keys():
		dims[k] = {}
	for k in there:
		dims[k] = {"trust": -60, "affection": -60, "respect": -40}
	director.relationship_dims_override = dims
	inv.add("short_sword", 1)
	inv.add_coin(50)
	inv.drop_all_at(null, Vector2(10, 10))
	# The player has already woken somewhere else when the fall is told: the finder is found at the pack
	director.player_location_override = "kingsroad_waystation"
	pe.record("fell", "fell in the forge yard", [], {"witnesses": [], "location": place, "spread": false})
	var insts = director.get_emergent_instances(false).filter(func(i): return i.template == "a_pack_by_the_road")
	if insts.is_empty():
		return ""
	await director.advance_round("test")
	return str(insts[0].roles.finder)

func _test_pack_recovery() -> void:
	print("A pack by the road, and getting it back")
	var place = "thornhaven_blacksmith"
	var there: Array = director.get_emergence().near_event({"location": place})
	_check("near_event finds the souls at the pack's place (%s)" % ", ".join(there), not there.is_empty())
	var finder = await _a_taken_pack(place)
	_check("Someone at the pack's place comes upon it, though the player is elsewhere (%s)" % finder, finder != "" and finder in there)
	if finder == "":
		return
	var pack: Dictionary = inv.get_packs(place)[0] if not inv.get_packs(place).is_empty() else {}
	_check("Their soul takes it, and who holds it is recorded", pack.get("state", "") == "taken" and pack.get("holder", "") == finder)
	_check("Inventory knows what they hold", inv.packs_held_by(finder).size() == 1)
	var block: String = director.get_conversation_agency_block(finder)
	_check("The thief's conversation block offers return_pack", block.contains("return_pack"))

	# Sold back: the soul names a price the player cannot meet, then one they can
	inv.coin = 10
	var r: Dictionary = director.apply_conversation_actions(finder, [{"type": "return_pack", "price": 20}])
	_check("Selling it for more than the purse holds is refused", r.applied.is_empty() and r.dropped.size() == 1 and str(r.dropped[0].reason).begins_with("coin:"))
	_check("...and nothing came back", not inv.has("short_sword") and inv.packs_held_by(finder).size() == 1)
	inv.coin = 30
	r = director.apply_conversation_actions(finder, [{"type": "return_pack", "price": 20}])
	_check("Sold back: the price is paid and everything returns", r.applied.size() == 1 and inv.has("short_sword") and inv.get_coin() == 30 - 20 + 50)
	_check("...and they hold nothing now", inv.packs_held_by(finder).is_empty() and inv.get_packs(place).is_empty())
	r = director.apply_conversation_actions(finder, [{"type": "return_pack", "price": 0}])
	_check("A pack they no longer hold cannot be given back", r.applied.is_empty() and str(r.dropped[0].reason).begins_with("truth:"))

	# Lines: a soul that will not hand back what it took
	finder = await _a_taken_pack(place)
	var soul = director.get_soul(finder)
	soul.lines.append({"rule": "effect:return_pack", "reason": "what I find is mine"})
	r = director.apply_conversation_actions(finder, [{"type": "return_pack", "price": 0}])
	_check("A Line refuses giving it back", r.applied.is_empty() and str(r.dropped[0].reason).contains("effect:return_pack"))
	_check("...and the block does not offer it", not director.get_conversation_agency_block(finder).contains("return_pack"))
	soul.lines.pop_back()

	# Theft: taken back unseen, or seen
	var scene = Node2D.new()
	scene.name = "GapsPackScene"
	root.add_child(scene)
	var watcher = _npc(scene, registry.get_npc_id(finder) if registry.get_npc_id(finder) != "" else finder, Vector2(40, 0))
	await process_frame
	var res: Dictionary = inv.steal_pack_back(finder, scene, Vector2(0, 0))
	var theft = pe.get_event(str(res.get("event_id", "")))
	_check("Stolen back: a theft deed about the holder", res.ok and theft.get("kind", "") == "theft" and finder in theft.get("about", []))
	_check("...seen by the holder standing there", not theft.is_empty() and watcher.npc_id in theft.witnesses)
	_check("...and everything is back", inv.has("short_sword") and inv.packs_held_by(finder).is_empty())
	_check("Nothing left to steal", not inv.steal_pack_back(finder, scene, Vector2.ZERO).ok)
	scene.queue_free()
	await process_frame

	# Force: killing the holder takes it back from them
	finder = await _a_taken_pack(place)
	pe.record("kill", "killed %s" % finder, [finder], {"witnesses": [], "location": place, "spread": false})
	_check("Taken by force: a kill deed about the holder brings it back", inv.has("short_sword") and inv.packs_held_by(finder).is_empty())
	director.relationship_dims_override = {}
	director.player_location_override = ""
	inv.location_override = ""

# =============================================================================
# 2. FIRE DEEDS
# =============================================================================

func _test_fire_deeds() -> void:
	print("\nFire deeds")
	pe.reset()
	physics.set_weather("clear", Vector2.ZERO, -1)
	var scene = _scene("GapsFire")
	_npc(scene, "test_watcher_001", Vector2(0, 0))
	var barn = _hay(scene, "Barn", Vector2(100, 0), 20.0, "mira", "barn")
	var cart = _hay(scene, "Cart", Vector2(6000, 0), 2.0, "gregor", "cart")
	await process_frame
	var outcomes: Array = []
	physics.fire_outcome.connect(func(id, owner, outcome, ev): outcomes.append([id, owner, outcome, ev]))

	physics.ignite(barn, "player")
	var fires = _kind("fire")
	_check("The fire deed is recorded when the barn catches, not when it burns", fires.size() == 1 and "mira" in fires[0].about)
	_check("...witnessed by whoever saw it lit", fires.size() == 1 and "test_watcher_001" in fires[0].witnesses)
	physics.douse(barn, "player")
	_check("Doused before it burned through: still one deed", _kind("fire").size() == 1)
	var fire_id = str(_f(barn).fire_id)
	_check("...and the outcome is doused", str(physics.get_fire(fire_id).get("outcomes", {}).get("mira", "")) == "doused" \
		and outcomes.size() == 1 and outcomes[0][2] == "doused" and outcomes[0][3] == fires[0].id)
	_check("Putting out your own fire is no help to her", _kind("help").is_empty())

	physics.ignite(cart, "player")
	_steps(6, 0.5)
	_check("Burned through: one deed for Gregor, no second", _kind("fire").filter(func(e): return "gregor" in e.about).size() == 1)
	_check("...the outcome is burned", outcomes.size() == 2 and outcomes[1][1] == "gregor" and outcomes[1][2] == "burned")
	var lightning = _hay(scene, "Tree", Vector2(12000, 0), 1.0, "bjorn", "tree")
	await process_frame
	physics.ignite(lightning, "")
	_steps(3, 0.5)
	_check("A fire the player did not light is no deed and no outcome of theirs", _kind("fire").size() == 2 and outcomes.size() == 2)
	var saved = physics.save()
	_check("The fire's deed and outcome are saved", saved.fires.get(fire_id, {}).get("deeds", {}).has("mira"))
	scene.queue_free()
	await process_frame

# =============================================================================
# 3. LAMPS
# =============================================================================

func _test_lamps() -> void:
	print("\nLamps reveal and blind")
	physics.set_weather("clear", Vector2.ZERO, -1)
	var minutes = world_state.game_minutes
	world_state.game_minutes = (minutes / 1440) * 1440 + 23 * 60  # 23:00, same day
	var scene = _scene("GapsLamps")
	var far = _npc(scene, "test_far_watcher_001", Vector2(0, 0))
	var lamp_thing = Node2D.new()
	lamp_thing.name = "Lamp"
	lamp_thing.position = Vector2(300, 0)
	scene.add_child(lamp_thing)
	var lamp = LAMP.new()
	lamp.exposure = "outdoors"
	lamp_thing.add_child(lamp)
	await process_frame
	var at_lamp = Vector2(300, 0)
	_check("Night, unlit: a deed 300 px off is unseen", not far.npc_id in Witnesses.in_sight(scene, at_lamp))
	physics.ignite(lamp_thing, "test")
	_check("A lit lamp raises sight around it", physics.sight_factor(at_lamp, {"scene_root": scene}) > 0.9)
	_check("...so a watcher sees a deed in its light", far.npc_id in Witnesses.in_sight(scene, at_lamp))
	physics.douse(lamp_thing, "test")
	_check("Doused: the light is gone, and so is the witness", physics.sight_factor(at_lamp, {"scene_root": scene}) < 0.5 and not far.npc_id in Witnesses.in_sight(scene, at_lamp))
	physics.ignite(lamp_thing, "test")
	far.queue_free()
	var by_lamp = _npc(scene, "test_lamp_watcher_001", Vector2(300, 0))
	var in_dark = _npc(scene, "test_dark_watcher_001", Vector2(-60, 0))
	await process_frame
	var dark_spot = Vector2(120, 0)  # 180 px from both watchers, outside the lamp's light
	var seen = Witnesses.in_sight(scene, dark_spot)
	_check("Lamps blind: the watcher by the flame misses a deed in the dark", not by_lamp.npc_id in seen)
	_check("...that a watcher in the dark at the same distance sees", in_dark.npc_id in seen)
	_check("...and the watcher by the lamp sees what is in its light", by_lamp.npc_id in Witnesses.in_sight(scene, Vector2(330, 0)))
	_check("Glare is nothing by day", physics.glare_factor(Vector2(300, 0), dark_spot, {"scene_root": scene, "hour": 12}) == 1.0)
	world_state.game_minutes = minutes
	scene.queue_free()
	await process_frame

# =============================================================================
# 4. TEACHING IN CONVERSATION
# =============================================================================

func _test_teach_in_conversation() -> void:
	print("\nTeaching in conversation")
	pe.reset()
	stats.reset()
	inv.reset()
	var block: String = director.get_conversation_agency_block("bjorn")
	_check("Bjorn's block offers to teach smithing", block.contains("\"teach\"") and block.contains("smithing"))
	_check("Gregor's offers no lesson", not director.get_conversation_agency_block("gregor").contains("\"teach\""))
	var cost = int(stats.get_teaching().usual_cost("bjorn", "smithing"))
	inv.coin = cost - 1
	var r: Dictionary = director.apply_conversation_actions("bjorn", [{"type": "teach", "skill": "smithing"}])
	_check("His usual fee, and the purse is short: no lesson", r.applied.is_empty() and str(r.dropped[0].reason).contains("cannot pay"))
	inv.coin = cost + 5
	var clock = world_state.get_game_minutes()
	r = director.apply_conversation_actions("bjorn", [{"type": "teach", "skill": "smithing", "price": cost}])
	_check("He chooses to teach for coin: paid", r.applied.size() == 1 and inv.get_coin() == 5)
	_check("...the lesson takes game time", world_state.get_game_minutes() == clock + int(stats.get_teaching().lesson_minutes()))
	_check("...and gain is boosted", stats.training_multiplier("smithing") > 1.0)
	inv.coin = 0
	r = director.apply_conversation_actions("bjorn", [{"type": "teach", "skill": "smithing", "favour": true}])
	_check("For a favour: taught, with a promise owed", r.applied.size() == 1 and _kind("promise").size() == 1)
	r = director.apply_conversation_actions("gregor", [{"type": "teach", "skill": "smithing", "price": 0}])
	_check("Not his trade: refused", r.applied.is_empty() and str(r.dropped[0].reason).contains("does not know that trade"))
	r = director.apply_conversation_actions("rook", [{"type": "teach", "skill": "blades", "price": 0}])
	_check("A child does not teach fighting", r.applied.is_empty() and str(r.dropped[0].reason).contains("child"))
	var soul = director.get_soul("bjorn")
	soul.lines.append({"rule": "effect:teach", "reason": "my trade is my own"})
	r = director.apply_conversation_actions("bjorn", [{"type": "teach", "skill": "smithing", "favour": true}])
	_check("A Line refuses teaching", r.applied.is_empty() and str(r.dropped[0].reason).contains("effect:teach"))
	soul.lines.pop_back()
	stats.reset()

# =============================================================================
# 5. BEDS AND CAMPS
# =============================================================================

func _test_beds_and_camps() -> void:
	print("\nBeds and camps")
	stats.reset()
	inv.reset()
	var packed = load("res://scenes/interiors/kingsroad_waystation.tscn")
	var way = packed.instantiate() if packed else null
	_check("The waystation has a bunk to rent and a bed spawn point", way != null and way.get_node_or_null("Bed") != null \
		and way.get_node_or_null("SpawnPoints/bed") is Marker2D and int(way.get_node("Bed").rent) > 0)
	if way:
		way.free()
	var scene = _scene("GapsBed")
	var bed = BED.new()
	bed.location_id = "kingsroad_waystation"
	bed.rent = 4
	scene.add_child(bed)
	inv.coin = 2
	var r: Dictionary = bed.sleep()
	_check("A room costs its rent: refused with too little", not r.ok and stats.get_respawn().is_empty() and inv.get_coin() == 2)
	inv.coin = 10
	r = bed.sleep()
	_check("Paid: the player will wake in the bed", r.ok and inv.get_coin() == 6 and stats.get_respawn() == {"location": "kingsroad_waystation", "spawn_point": "bed"})
	var info: Dictionary = stats.die({"scene_root": scene, "position": Vector2.ZERO})
	_check("Death wakes them there", info.respawn == {"location": "kingsroad_waystation", "spawn_point": "bed"})
	scene.queue_free()

	var outdoors = ""
	var indoors = ""
	for id in registry.get_location_ids():
		var kind = str(registry.get_location(id).get("kind", ""))
		if outdoors == "" and kind == "exterior":
			outdoors = id
		if indoors == "" and kind == "interior":
			indoors = id
	inv.reset()
	var spot = Vector2(120, -40)
	r = Camp.make_camp(outdoors, spot)
	_check("No bedroll, no camp", not r.ok and str(r.reason).contains("bedroll"))
	inv.add("bedroll", 1)
	var built_before = crafting.built.duplicate(true)
	r = Camp.make_camp(outdoors, spot)
	_check("A bedroll and no wood for a fire: no camp", not r.ok and str(r.reason).contains("fire"))
	inv.add("wood", 3)
	r = Camp.make_camp(outdoors, spot)
	_check("Bedroll and a fire built from wood: camp at %s" % outdoors, r.ok and r.built_fire and crafting.built.has(r.station_id))
	_check("...the player will wake at the bedroll", stats.get_respawn() == {"location": outdoors, "spawn_point": "camp", "position": [spot.x, spot.y]})
	_check("...and the bedroll stays in the pack", inv.has("bedroll"))
	var again = Camp.make_camp(outdoors, spot + Vector2(10, 0))
	_check("Camping again by the same fire builds none", again.ok and not again.built_fire and again.station_id == r.station_id)
	_check("No camp indoors", not Camp.make_camp(indoors, spot).ok)
	info = stats.die({"scene_root": null, "position": Vector2.ZERO})
	_check("Death wakes them at camp", str(info.respawn.get("location", "")) == outdoors and info.respawn.get("spawn_point", "") == "camp")
	var body = Node2D.new()
	body.add_to_group("player")
	root.add_child(body)
	stats.set("_waking", true)
	stats._on_scene_arrived(outdoors)
	_check("...and the scene puts them at the bedroll", body.global_position.is_equal_approx(spot + Vector2(10, 0)))
	body.free()
	var data = stats.save()
	stats.reset()
	stats.load_from_dict(data)
	_check("The camp survives a save", stats.get_respawn().get("position", []) == [spot.x + 10.0, spot.y])
	crafting.built = built_before
	stats.reset()
	inv.reset()

# =============================================================================

func _scene(scene_name: String) -> Node2D:
	var s = Node2D.new()
	s.name = scene_name
	root.add_child(s)
	return s

func _npc(scene: Node, id: String, at: Vector2) -> _Body:
	var b = _Body.new()
	b.npc_id = id
	b.position = at
	b.add_to_group("npcs")
	scene.add_child(b)
	return b

func _hay(scene: Node, thing_name: String, at: Vector2, seconds: float, owner: String, what: String) -> Node2D:
	var t = Node2D.new()
	t.name = thing_name
	t.position = at
	scene.add_child(t)
	var f = FLAMMABLE.new()
	f.name = "Flammable"
	f.burn_seconds = seconds
	f.exposure = "outdoors"
	f.owner_key = owner
	f.what = what
	t.add_child(f)
	return t

func _f(t: Node) -> Node:
	return t.get_node("Flammable")

func _steps(n: int, dt: float) -> void:
	for i in n:
		physics.step(dt)

func _kind(kind: String) -> Array:
	return pe.get_events().filter(func(e): return e.kind == kind)

func _restore() -> void:
	inv.reset()
	inv.location_override = ""
	inv.auto_recognise = true
	stats.reset()
	stats.move_on_respawn = true
	physics.auto_step = true
	physics.region_override = ""
	physics.clear_weather()
	director.relationship_dims_override = {}
	director.player_location_override = ""
	director.reset_state()
	director.get_emergence().reset()
	world_state.world_flags = saved_flags
	world_state.npc_states = saved_npc_states
	world_state.game_minutes = saved_minutes
	pe.reset()
	pe.load_from_dict(saved_pe)
	propagator.load_from_dict(saved_propagation)
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
