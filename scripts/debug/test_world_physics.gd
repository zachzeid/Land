extends SceneTree

# Tests WorldPhysics, the systemic world physics (docs/PLAYER_SYSTEMS.md §5.1):
# - fire spreads to dry flammables in reach on a timer, not to wet ones; rain soaks things outdoors
#   (fire goes out, will not light), not indoors
# - wind: get_wind follows the weather; fire reaches farther downwind than upwind; the clock's wind
#   turns over game time; light things drift; projectiles get a drift
# - burn-out: a burnt thing is destroyed, charred or kept (burned signal)
# - lamps: lit by fire in reach and by ignite, put out by douse and rain (open flames outdoors);
#   they light the dark (darkness_at), shadows hide
# - dousing: douse and a poured basin put fire out; basins fill with rain; metal sinks in them
# - rope: burning or cutting it drops the weight it holds onto a plate
# - plates: press by weight (crates, the player, NPC bodies), counterweights, latching
# - metal: a hot blade lights tinder; iron rusts when left wet, bronze does not; a lodestone pulls iron
# - deeds: a fire the player lit that burns an owner's thing is a `fire` deed about them, with the
#   witnesses who saw it lit, or none (a rumour); one deed per owner per fire; nobody else's fire is
#   the player's deed; dousing someone's burning thing is `help`
# - save/load: fire, wetness, heat, rust, ropes, plates, basins, weather; burnt things stay burnt when
#   a scene is built again
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_world_physics.gd

const FLAMMABLE = preload("res://scripts/world/physics/flammable.gd")
const ROPE = preload("res://scripts/world/physics/rope.gd")
const LAMP = preload("res://scripts/world/physics/lamp.gd")
const BASIN = preload("res://scripts/world/physics/basin.gd")
const METAL = preload("res://scripts/world/physics/metal.gd")
const WEIGHT = preload("res://scripts/world/physics/weight.gd")
const PLATE = preload("res://scripts/world/physics/pressure_plate.gd")
const SHADOW = preload("res://scripts/world/physics/shadow.gd")

class _Body extends Node2D:
	var npc_id: String = ""
	var is_alive: bool = true

var physics: Node
var pe: Node
var failures: int = 0
var scene: Node2D

func _init():
	await process_frame
	await process_frame
	var world_state = root.get_node("WorldState")
	world_state.set_idle_clock_rate(0.0)
	var director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	physics = root.get_node("WorldPhysics")
	pe = root.get_node("PlayerEvents")
	physics.auto_step = false
	physics.region_override = "test_region"
	print("============================================================")
	print("🧪 WORLD PHYSICS TEST")
	print("============================================================\n")

	_contract()
	await _fire_spread()
	await _wind()
	await _burn_out()
	await _lamps_and_light()
	await _dousing_and_water()
	await _rope_and_plates()
	await _metal()
	await _deeds()
	await _save_load()
	await _prefabs()

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _contract() -> void:
	print("Contract")
	for m in ["ignite", "douse", "get_wind", "save", "load_from_dict", "weight_on", "darkness_at"]:
		_check("WorldPhysics.%s" % m, physics.has_method(m))
	_check("Signals fire_started and burned", physics.has_signal("fire_started") and physics.has_signal("burned"))
	var f = FLAMMABLE.new()
	var p = PLATE.new()
	_check("flammable.gd exports owner_key and burn_seconds", "owner_key" in f and "burn_seconds" in f)
	_check("pressure_plate.gd exports weight_needed and has pressed(on)", "weight_needed" in p and p.has_signal("pressed"))
	var r = ROPE.new()
	_check("rope.gd has signal cut", r.has_signal("cut"))
	for s in [f, p, r]:
		s.free()

func _fire_spread() -> void:
	print("\nFire spreads to dry things, not wet")
	physics.set_weather("clear", Vector2.ZERO, -1)
	_new_scene("FireSpread")
	var a = _hay("A", Vector2(0, 0))
	var b = _hay("B", Vector2(50, 0))
	var c = _hay("C", Vector2(400, 0))
	var d = _hay("D", Vector2(-50, 0))
	physics.douse(d, "test")
	await process_frame
	var started: Array = []
	physics.fire_started.connect(func(n, by): started.append([n, by]))
	_check("ignite lights dry hay", physics.ignite(a, "test"))
	_check("...not twice", not physics.ignite(a, "test"))
	_check("A wet thing will not light", not physics.ignite(d, "test"))
	physics.step(0.5)
	_check("Spread is on a timer: B not yet alight after 0.5 s", not _f(b).burning)
	_steps(4, 0.5)
	_check("B (in reach, dry) catches", _f(b).burning)
	_check("...as part of the same fire, lit by the same hand", _f(b).fire_id == _f(a).fire_id and _f(b).lit_by == "test")
	_check("fire_started fired for each", started.size() >= 2)
	_check("C (out of reach) does not", not _f(c).burning and _f(c).heat == 0.0)
	_check("D (soaked) does not", not _f(d).burning and not _f(d).burnt)
	await _end_scene()

	print("\nRain")
	_new_scene("Rain")
	var out_hay = _hay("Outside", Vector2(0, 0))
	var in_hay = _hay("Inside", Vector2(600, 0))
	_f(in_hay).exposure = "indoors"
	await process_frame
	physics.ignite(out_hay, "test")
	physics.set_weather("rain", Vector2.ZERO, 6)
	_check("Rain is a weather state", physics.is_raining() and physics.get_weather().weather == "rain")
	_check("Rain puts out a fire outdoors", not _f(out_hay).burning and _f(out_hay).is_wet())
	_check("...and it will not light again in the rain", not physics.ignite(out_hay, "test"))
	_check("Indoors stays dry and lights", not _f(in_hay).is_wet() and physics.ignite(in_hay, "test"))
	physics.douse(in_hay, "test")
	physics.set_weather("clear", Vector2.ZERO, -1)
	physics.advance_game(3 * 60)
	_check("Three dry hours later it has not dried yet", _f(out_hay).is_wet())
	physics.advance_game(2 * 60)
	_check("Five dry hours later it has, and lights", not _f(out_hay).is_wet() and physics.ignite(out_hay, "test"))
	await _end_scene()

func _wind() -> void:
	print("\nWind")
	physics.set_weather("clear", Vector2(1, 0), -1)
	_check("get_wind gives the weather's wind", physics.get_wind().is_equal_approx(Vector2(1, 0)))
	_check("Projectiles drift with it", physics.projectile_drift().x > 0.0)
	_new_scene("Wind")
	var src = _hay("Source", Vector2(0, 0))
	var downwind = _hay("Downwind", Vector2(100, 0))
	var upwind = _hay("Upwind", Vector2(-100, 0))
	var sack = _thing("Sack", Vector2(0, 300))
	var sw = WEIGHT.new()
	sw.drifts = true
	sw.mass = 2.0
	sack.add_child(sw)
	await process_frame
	physics.ignite(src, "test")
	_steps(5, 0.5)
	_check("Fire carries downwind past its still-air reach", _f(downwind).burning)
	_check("...but not as far upwind", not _f(upwind).burning)
	_check("A light thing drifts downwind", sack.position.x > 50.0)
	await _end_scene()
	physics.clear_weather()
	var w1 = physics.weather_at(0, "test_region")
	var again = physics.weather_at(0, "test_region")
	_check("The clock's weather is the same for the same hour", w1.wind.is_equal_approx(again.wind) and w1.weather == again.weather)
	var turned = false
	var states = {}
	for h in range(0, 24 * 10):
		var w = physics.weather_at(h * 60, "test_region")
		states[w.weather] = true
		if absf(angle_difference(w.wind.angle(), w1.wind.angle())) > 0.5:
			turned = true
	_check("The wind turns over game time", turned)
	_check("Ten days hold more than one kind of weather", states.size() >= 2)
	_check("Regions have their own wind", not physics.weather_at(600, "test_region").wind.is_equal_approx(physics.weather_at(600, "other_region").wind))

func _burn_out() -> void:
	print("\nBurn-out")
	physics.set_weather("clear", Vector2.ZERO, -1)
	_new_scene("BurnOut")
	var gone = _hay("Gone", Vector2(0, 0), 2.0)
	var charred = _hay("Charred", Vector2(0, 500), 2.0)
	_f(charred).on_burnt = "char"
	await process_frame
	var burned: Array = []
	physics.burned.connect(func(n, _key): burned.append(n))
	physics.ignite(gone, "test")
	physics.ignite(charred, "test")
	var gone_f = _f(gone)
	var char_f = _f(charred)
	_steps(5, 0.5)
	_check("It burns out after burn_seconds (burned signal)", gone_f in burned and char_f in burned)
	await process_frame
	_check("A destroyed thing is gone", not is_instance_valid(gone))
	_check("A charred thing stays, burnt and blackened", is_instance_valid(charred) and char_f.burnt and charred.modulate.r < 0.5)
	_check("Burnt things do not light again", not physics.ignite(charred, "test"))
	await _end_scene()

func _lamps_and_light() -> void:
	print("\nLamps and light")
	physics.set_weather("clear", Vector2.ZERO, -1)
	_new_scene("Lamps")
	var hay = _hay("Hay", Vector2(0, 0))
	var lamp = _lamp("Lamp", Vector2(30, 0))
	var far_lamp = _lamp("FarLamp", Vector2(0, 600))
	var torch = _lamp("Torch", Vector2(600, 600))
	var lantern = _lamp("Lantern", Vector2(900, 600))
	lantern.get_child(0).open_flame = false
	var shade = _thing("Alcove", Vector2(-600, 0))
	var sh = SHADOW.new()
	sh.radius = 80.0
	sh.depth = 0.8
	shade.add_child(sh)
	await process_frame
	physics.ignite(hay, "test")
	physics.step(0.1)
	_check("A fire in reach lights a lamp", lamp.get_child(0).lit)
	_check("...not one out of reach", not far_lamp.get_child(0).lit)
	_check("ignite lights a lamp", physics.ignite(far_lamp, "test") and far_lamp.get_child(0).lit)
	_check("douse puts it out", physics.douse(far_lamp, "test") and not far_lamp.get_child(0).lit)
	var night = {"hour": 23, "scene_root": scene}
	_check("Night is dark away from light", physics.darkness_at(Vector2(0, 600), night) > 0.7)
	_check("A lit lamp reveals the ground around it", physics.darkness_at(Vector2(30, 10), night) < 0.2 and physics.is_lit(Vector2(30, 10), night))
	_check("Day is bright; a shadow hides even by day", physics.darkness_at(Vector2(0, 600), {"hour": 12, "scene_root": scene}) < 0.1 and physics.darkness_at(Vector2(-600, 0), {"hour": 12, "scene_root": scene}) >= 0.8)
	_check("Darkness cuts how far a watcher sees", physics.sight_factor(Vector2(0, 600), night) < physics.sight_factor(Vector2(30, 10), night))
	physics.douse(hay, "test")
	physics.ignite(torch, "test")
	physics.ignite(lantern, "test")
	physics.set_weather("rain", Vector2.ZERO, 6)
	_check("Rain puts out a torch outdoors", not torch.get_child(0).lit)
	_check("...not a shuttered lantern", lantern.get_child(0).lit)
	physics.set_weather("clear", Vector2.ZERO, -1)
	await _end_scene()

func _dousing_and_water() -> void:
	print("\nDousing and water")
	physics.set_weather("clear", Vector2.ZERO, -1)
	_new_scene("Water")
	var hay = _hay("Hay", Vector2(0, 0))
	var bale = _hay("Bale", Vector2(0, 200))
	var trough = _thing("Trough", Vector2(20, 200))
	var basin = BASIN.new()
	basin.exposure = "outdoors"
	trough.add_child(basin)
	await process_frame
	physics.ignite(hay, "test")
	var doused: Array = []
	physics.doused.connect(func(n, by): doused.append(n))
	_check("douse puts a fire out", physics.douse(hay, "test") and not _f(hay).burning and _f(hay).is_wet())
	_check("...doused signal", _f(hay) in doused)
	_check("Dousing what is not burning only soaks it", not physics.douse(hay, "test"))
	physics.ignite(bale, "test")
	_check("An empty basin pours nothing", basin.pour("test") == 0 and _f(bale).burning)
	physics.set_weather("rain", Vector2.ZERO, 6)
	physics.ignite(bale, "test")   # wet now; rain put it out
	physics.advance_game(4 * 60)
	_check("Rain fills an outdoor basin", basin.is_full())
	physics.set_weather("clear", Vector2.ZERO, -1)
	physics.advance_game(6 * 60)
	_check("...and the bale dries", not _f(bale).is_wet())
	physics.ignite(bale, "test")
	_check("A poured basin puts out fire in reach", basin.pour("test") == 1 and not _f(bale).burning and basin.fill == 0.0)
	await _end_scene()

func _rope_and_plates() -> void:
	print("\nRope and plates")
	physics.set_weather("clear", Vector2.ZERO, -1)
	_new_scene("Plates")
	# A stone hung by a rope over a plate; hay at the rope's foot
	var plate = _plate("Plate", Vector2(0, 0), 30.0)
	var stone = _thing("Stone", Vector2(0, 0))
	var sw = WEIGHT.new()
	sw.mass = 40.0
	stone.add_child(sw)
	var rope = ROPE.new()
	rope.name = "Rope"
	rope.position = Vector2(0, -40)
	scene.add_child(rope)
	rope.holds.assign([rope.get_path_to(stone)])
	rope._ready()
	var hay = _hay("Hay", Vector2(0, -80))
	await process_frame
	var presses: Array = []
	plate.get_child(0).pressed.connect(func(on): presses.append(on))
	var cuts: Array = []
	rope.cut.connect(func(): cuts.append(true))
	physics.step(0.1)
	_check("A hanging stone does not press the plate", sw.hanging and not plate.get_child(0).is_pressed)
	physics.ignite(hay, "test")
	_steps(20, 0.5)
	_check("Fire takes the rope; a burnt rope is cut", rope.burnt and rope.is_cut and cuts.size() == 1)
	_check("The stone drops onto the plate and presses it", not sw.hanging and plate.get_child(0).is_pressed and presses == [true])

	var p2 = _plate("Plate2", Vector2(0, 1000), 50.0)
	var crate1 = _crate("Crate1", Vector2(0, 1000), 20.0)
	physics.step(0.1)
	_check("One light crate is not enough", not p2.get_child(0).is_pressed and is_equal_approx(physics.weight_on(p2.get_child(0)), 20.0))
	var crate2 = _crate("Crate2", Vector2(10, 1005), 40.0)
	await process_frame
	physics.step(0.1)
	_check("Two crates press it", p2.get_child(0).is_pressed)
	crate2.position = Vector2(500, 1000)
	physics.step(0.1)
	_check("Take one off and it rises", not p2.get_child(0).is_pressed)

	var p3 = _plate("Plate3", Vector2(0, 2000), 50.0)
	var who = Node2D.new()
	who.add_to_group("player")
	who.position = Vector2(0, 2000)
	scene.add_child(who)
	physics.step(0.1)
	_check("The player's weight presses a plate", p3.get_child(0).is_pressed)
	who.position = Vector2(0, 2300)
	var body = _npc("test_body_001", Vector2(0, 2000))
	body.is_alive = false
	physics.step(0.1)
	_check("So does an NPC's body, living or dead", p3.get_child(0).is_pressed)

	# A counterweight holds a plate up until its rope is cut
	var p4 = _plate("Plate4", Vector2(0, 3000), 50.0)
	_crate("Barrel", Vector2(0, 3000), 60.0)
	var counter = _thing("Counter", Vector2(300, 3000))
	var cw = WEIGHT.new()
	cw.mass = 30.0
	counter.add_child(cw)
	cw.counters = cw.get_path_to(p4.get_child(0))
	var crope = ROPE.new()
	crope.name = "CounterRope"
	crope.position = Vector2(300, 2960)
	scene.add_child(crope)
	crope.holds.assign([crope.get_path_to(counter)])
	crope._ready()
	await process_frame
	physics.step(0.1)
	_check("A counterweight holds a plate up under a heavy barrel", not p4.get_child(0).is_pressed)
	var severed = crope.sever("player")
	physics.step(0.1)
	_check("Cutting the rope (sever) drops it and the plate sinks", severed and not cw.hanging and p4.get_child(0).is_pressed)
	_check("A rope cuts once", not crope.sever("player"))

	var p5 = _plate("Plate5", Vector2(0, 4000), 50.0)
	p5.get_child(0).latch = true
	var c5 = _crate("Crate5", Vector2(0, 4000), 60.0)
	await process_frame
	physics.step(0.1)
	c5.position = Vector2(400, 4000)
	physics.step(0.1)
	_check("A latching plate stays down", p5.get_child(0).is_pressed)
	await _end_scene()

func _metal() -> void:
	print("\nMetal")
	physics.set_weather("clear", Vector2.ZERO, -1)
	_new_scene("Metal")
	var blade = _metal_thing("Blade", Vector2(0, 0), "steel")
	var tinder = _hay("Tinder", Vector2(20, 0))
	var far_tinder = _hay("FarTinder", Vector2(0, 300))
	await process_frame
	var bm = blade.get_child(0)
	_check("ignite heats metal white-hot", physics.ignite(blade, "player") and bm.heat >= physics.HOT)
	physics.step(0.5)
	_steps(2, 0.5)
	_check("A hot blade lights tinder it touches", _f(tinder).burning and _f(tinder).lit_by == "player")
	_check("...not tinder across the room", not _f(far_tinder).burning)
	physics.douse(tinder, "test")
	physics.douse(blade, "test")
	_check("Water quenches it", bm.heat == 0.0)
	var poker = _metal_thing("Poker", Vector2(0, 600), "iron")
	var fire = _hay("Fire", Vector2(30, 600), 60.0)
	await process_frame
	physics.ignite(fire, "test")
	_steps(4, 0.5)
	_check("Metal heats in a fire's reach (conducts)", poker.get_child(0).heat >= physics.HOT)
	physics.douse(fire, "test")
	_steps(10, 1.0)
	_check("...and cools out of it", poker.get_child(0).heat < 0.5)

	var nail = _metal_thing("Nail", Vector2(0, 900), "iron")
	var bell = _metal_thing("Bell", Vector2(100, 900), "bronze")
	nail.get_child(0).exposure = "outdoors"
	bell.get_child(0).exposure = "outdoors"
	await process_frame
	physics.set_weather("rain", Vector2.ZERO, 2)
	physics.advance_game(2 * 60)
	physics.set_weather("clear", Vector2.ZERO, -1)
	physics.advance_game(60)
	_check("Iron left wet rusts", nail.get_child(0).rust > 0.0)
	_check("Bronze does not", bell.get_child(0).rust == 0.0)
	var dry_rust = nail.get_child(0).rust
	physics.advance_game(10 * 60)
	_check("Dry, it rusts no further", is_equal_approx(nail.get_child(0).rust, dry_rust))

	var stone = _metal_thing("Lodestone", Vector2(0, 1200), "lodestone")
	var key = _metal_thing("Key", Vector2(120, 1200), "iron")
	var coin = _metal_thing("Coin", Vector2(-120, 1200), "gold")
	await process_frame
	_steps(5, 0.5)
	_check("A lodestone pulls iron toward it", key.position.x < 120.0 - 50.0)
	_check("...not gold", is_equal_approx(coin.position.x, -120.0))

	var cistern = _thing("Cistern", Vector2(0, 1500))
	var basin = BASIN.new()
	basin.fill = 1.0
	cistern.add_child(basin)
	var ingot = _metal_thing("Ingot", Vector2(0, 1500), "iron")
	await process_frame
	ingot.get_child(0).heat = 1.0
	_check("Metal sinks in water and is quenched", basin.drop_in(ingot, "test") and ingot.get_child(0).sunk and ingot.get_child(0).heat == 0.0)
	await _end_scene()

func _deeds() -> void:
	print("\nDeeds")
	physics.set_weather("clear", Vector2.ZERO, -1)
	_new_scene("Deeds")
	_npc("test_watcher_001", Vector2(0, 0))
	var in_flight_before = pe.in_flight.size()
	var barn = _hay("Barn", Vector2(100, 0), 3.0)
	_f(barn).owner_key = "mira"
	_f(barn).what = "barn"
	var stack = _hay("Haystack", Vector2(140, 0), 2.0)
	_f(stack).owner_key = "mira"
	var hidden_barn = _hay("Shed", Vector2(5000, 0), 1.0)
	_f(hidden_barn).owner_key = "gregor"
	var lightning = _hay("Tree", Vector2(9000, 0), 1.0)
	_f(lightning).owner_key = "bjorn"
	var saved = _hay("Cart", Vector2(13000, 0), 30.0)
	_f(saved).owner_key = "elena"
	await process_frame
	var before = pe.get_events().size()
	var flags_before = root.get_node("WorldState").get_flags().duplicate(true)

	physics.ignite(barn, "player")
	_steps(12, 0.5)
	var fires = _new_events(before, "fire")
	_check("Burning Mira's barn is a fire deed about her", fires.size() >= 1 and "mira" in fires[0].about)
	_check("...with the witness who saw it lit", fires.size() >= 1 and "test_watcher_001" in fires[0].witnesses)
	_check("...one deed for the fire, though it took two of her things", fires.size() == 1 and _f_or_null(stack) == null)
	_check("...that says what burned", fires.size() >= 1 and fires[0].summary.contains("barn"))
	if fires.size() >= 1:
		print("    (%s)" % fires[0].summary)

	before = pe.get_events().size()
	physics.ignite(hidden_barn, "player")
	_steps(3, 0.5)
	fires = _new_events(before, "fire")
	_check("Unseen, it is still recorded, with no witnesses (a rumour at most)", fires.size() == 1 and fires[0].witnesses.is_empty() and "gregor" in fires[0].about)

	before = pe.get_events().size()
	physics.ignite(lightning, "")
	_steps(3, 0.5)
	_check("A fire the player did not light is no deed of theirs", _new_events(before, "fire").is_empty())

	before = pe.get_events().size()
	physics.ignite(saved, "")
	physics.douse(saved, "player")
	var helps = _new_events(before, "help")
	_check("Putting out someone's burning cart is help about them", helps.size() == 1 and "elena" in helps[0].about)
	physics.ignite(saved, "player") # wet: will not light
	_check("Physics sets no story flags", root.get_node("WorldState").get_flags() == flags_before)
	# Keep test gossip off the roads
	pe.in_flight = pe.in_flight.slice(0, in_flight_before)
	await _end_scene()

func _save_load() -> void:
	print("\nSave and load")
	physics.set_weather("clear", Vector2.ZERO, -1)
	_new_scene("SaveRoom")
	var burning = _hay("Burning", Vector2(0, 0), 30.0)
	var wet = _hay("Wet", Vector2(0, 500))
	var gone = _hay("Gone", Vector2(0, 1000), 0.5)
	var nail = _metal_thing("Nail", Vector2(0, 1500), "iron")
	var plate = _plate("Plate", Vector2(0, 2000), 10.0)
	plate.get_child(0).latch = true
	var crate = _crate("Crate", Vector2(0, 2000), 20.0)
	var trough = _thing("Trough", Vector2(0, 2500))
	var basin = BASIN.new()
	trough.add_child(basin)
	var rope = ROPE.new()
	rope.name = "Rope"
	rope.position = Vector2(0, 3000)
	scene.add_child(rope)
	await process_frame
	physics.ignite(burning, "player")
	physics.douse(wet, "test")
	_f(gone).owner_key = "mira"
	physics.ignite(gone, "player")
	nail.get_child(0).rust = 0.4
	basin.fill_with(0.5)
	rope.sever("player")
	_steps(2, 0.5)
	physics.set_weather("overcast", Vector2(0, 0.9), -1)
	var data = JSON.parse_string(JSON.stringify(physics.save()))
	_check("The save is plain JSON", data is Dictionary and data.has("objects") and data.has("weather_override"))

	physics.douse(burning, "test")
	_f(wet).wetness = 0.0
	nail.get_child(0).rust = 0.0
	basin.fill = 0.0
	physics.clear_weather()
	physics.load_from_dict(data)
	_check("Fire is restored", _f(burning).burning and _f(burning).lit_by == "player")
	_check("Wetness is restored", _f(wet).is_wet())
	_check("Rust and basins are restored", is_equal_approx(nail.get_child(0).rust, 0.4) and is_equal_approx(basin.fill, 0.5))
	_check("Plates and ropes are restored", plate.get_child(0).is_pressed and rope.is_cut)
	_check("Weather is restored", physics.get_weather().weather == "overcast" and physics.get_wind().is_equal_approx(Vector2(0, 0.9)))
	await _end_scene()

	# The same room built again (a scene change and back): saved state comes back on its own
	physics.load_from_dict(data)
	var before = pe.get_events().size()
	_new_scene("SaveRoom")
	var burning2 = _hay("Burning", Vector2(0, 0), 30.0)
	var wet2 = _hay("Wet", Vector2(0, 500))
	var gone2 = _hay("Gone", Vector2(0, 1000), 0.5)
	await process_frame
	_check("A rebuilt room keeps its fire and wetness", _f(burning2).burning and _f(wet2).is_wet())
	await process_frame
	_check("...and what burnt away stays gone", not is_instance_valid(gone2))
	_check("...with no second deed for it", pe.get_events().size() == before)
	await _end_scene()
	physics.load_from_dict({})
	physics.clear_weather()

func _prefabs() -> void:
	print("\nPrefabs (scenes/world/physics/)")
	physics.set_weather("clear", Vector2.ZERO, -1)
	_new_scene("Prefabs")
	var want = {"hay_bale": "flammable", "crate": "weight", "torch": "lamp", "lantern": "lamp",
		"pressure_plate": "plate", "hanging_stone": "rope", "basin": "basin", "lodestone": "metal",
		"iron_key": "metal", "shadow": "shadow"}
	var made = {}
	var i = 0
	for prefab in want:
		var packed = load("res://scenes/world/physics/%s.tscn" % prefab)
		var inst = packed.instantiate() if packed else null
		if inst:
			inst.position = Vector2(i * 1000, 0)
			scene.add_child(inst)
			made[prefab] = inst
		i += 1
	await process_frame
	for prefab in want:
		var inst = made.get(prefab)
		var found = inst != null and not inst.find_children("*", "", true, false).filter(func(n): return n.has_method("kind") and n.kind() == want[prefab]).is_empty()
		_check("%s.tscn loads with a %s" % [prefab, want[prefab]], found)
	var hay = made.get("hay_bale")
	var hay_f = hay.get_node("Flammable")
	_check("A prefab's component acts on the prefab", hay_f.thing() == hay)
	var hang = made.get("hanging_stone")
	var rope = hang.get_node("Rope")
	var stone_w = hang.get_node("Stone/Weight")
	_check("The hanging stone hangs", stone_w.hanging and rope.thing() == rope and stone_w.thing() == hang.get_node("Stone"))
	physics.ignite(rope, "test")
	_steps(8, 0.5)
	_check("Burn its rope and the stone falls", rope.is_cut and not stone_w.hanging)
	physics.ignite(hay, "test")
	_steps(20, 0.5)
	await process_frame
	_check("A burnt hay bale is gone, the room around it is not", not is_instance_valid(hay) and is_instance_valid(scene))
	await _end_scene()

# =============================================================================
# HELPERS
# =============================================================================

func _new_scene(scene_name: String) -> void:
	scene = Node2D.new()
	scene.name = scene_name
	root.add_child(scene)

func _end_scene() -> void:
	scene.queue_free()
	await process_frame
	await process_frame

func _thing(thing_name: String, at: Vector2) -> Node2D:
	var t = Node2D.new()
	t.name = thing_name
	t.position = at
	scene.add_child(t)
	return t

func _hay(thing_name: String, at: Vector2, seconds: float = 6.0) -> Node2D:
	var t = _thing(thing_name, at)
	var f = FLAMMABLE.new()
	f.name = "Flammable"
	f.burn_seconds = seconds
	f.exposure = "outdoors"
	t.add_child(f)
	return t

func _lamp(thing_name: String, at: Vector2) -> Node2D:
	var t = _thing(thing_name, at)
	var l = LAMP.new()
	l.exposure = "outdoors"
	t.add_child(l)
	return t

func _plate(thing_name: String, at: Vector2, need: float) -> Node2D:
	var t = _thing(thing_name, at)
	var p = PLATE.new()
	p.weight_needed = need
	t.add_child(p)
	return t

func _crate(thing_name: String, at: Vector2, mass: float) -> Node2D:
	var t = _thing(thing_name, at)
	var w = WEIGHT.new()
	w.mass = mass
	t.add_child(w)
	return t

func _metal_thing(thing_name: String, at: Vector2, kind: String) -> Node2D:
	var t = _thing(thing_name, at)
	var m = METAL.new()
	m.metal = kind
	t.add_child(m)
	return t

func _npc(id: String, at: Vector2) -> _Body:
	var n = _Body.new()
	n.npc_id = id
	n.position = at
	n.add_to_group("npcs")
	scene.add_child(n)
	return n

func _f(t: Node) -> Node:
	return t.get_node("Flammable")

func _f_or_null(t: Node):
	return t.get_node_or_null("Flammable") if is_instance_valid(t) and not t.is_queued_for_deletion() else null

func _steps(n: int, dt: float) -> void:
	for i in n:
		physics.step(dt)

func _new_events(before: int, kind: String) -> Array:
	return pe.get_events().slice(before).filter(func(e): return e.kind == kind)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
