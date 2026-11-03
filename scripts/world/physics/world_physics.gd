extends Node
## WorldPhysics - fire, water, wind, weight, rope, metal, light: systemic rules on components
## docs/PLAYER_SYSTEMS.md §5.1 (Breath of the Wild chemistry, not scripts). Components
## (scripts/world/physics/*.gd: flammable, rope, lamp, basin, metal, weight, pressure_plate, shadow)
## register here; this runs the rules on them:
## - fire: heat from burning things builds in flammables within reach (farther downwind, none while
##   wet) until they catch; they burn for burn_seconds and burn out (burned), destroyed, charred or
##   kept; a burnt rope is cut. Fire and open flames light lamps; water (douse, a poured basin, rain
##   outdoors) puts fire out
## - weather on the game clock, per region: clear | overcast | rain | storm, with a wind that turns
##   and gusts (get_wind). Rain soaks everything outdoors and fills basins; things dry after
## - weight: plates press under the resting weight inside them; ropes hold weights until cut
## - metal: heats in fire and lights tinder while hot, cools, rusts while wet, sinks; lodestones
##   pull loose iron. Light: lamps and fires reveal, shadows and night hide (darkness_at)
## Deeds go through PlayerEvents.record, never NPC state: when a fire the player lit catches a thing
## with an owner_key, that is a `fire` deed about the owner then (one per owner per fire), witnessed by
## whoever saw the player light it (Witnesses.in_sight; nobody: no witnesses, a rumour at most). How it
## ended for that owner (doused | burned) is kept on the fire and signalled (fire_outcome), never a
## second deed. Putting out a fire on someone's thing that the player did not light is `help`.
## Physics never sets story flags

signal fire_started(node: Node, by: String)
signal burned(node: Node, owner_key: String)
signal doused(node: Node, by: String)
signal weather_changed(state: Dictionary)
## How a player's fire ended for one owner: "doused" (put out before it burned through) or "burned"
signal fire_outcome(fire_id: String, owner_key: String, outcome: String, event_id: String)

const Witnesses = preload("res://scripts/world/witnesses.gd")

# Fire
const HEAT_RATE = 0.8            # heat per second beside a fire (a flammable catches at 1.0)
const HEAT_FALLOFF = 0.25        # heat lost per second away from fire
const WIND_REACH = 1.0           # full wind doubles reach downwind and cuts it upwind
const MIN_REACH_FACTOR = 0.25
const FIRE_LIGHT = 180.0         # a burning thing lights this far (pixels)
const MAX_CATCHUP_SECONDS = 300.0  # a clock jump runs a burning fire this long, then it is out
# Metal
const HOT = 0.6                  # metal this hot lights tinder it touches
const CONTACT_REACH = 28.0
const METAL_HEAT_RATE = 0.5      # per second in a fire's reach
const METAL_COOL_RATE = 0.1      # per second out of it (a white-hot blade is cold in ten)
const RUST_PER_HOUR = 0.02
# Water and weather
const DRY_PER_HOUR = 0.25        # wetness lost per dry game hour
const RAIN_FILL_PER_HOUR = 0.25  # an outdoor basin fills in four hours of rain
const WEATHERS = ["clear", "overcast", "rain", "storm"]
const WEATHER_KNOT_HOURS = 6     # weather and wind direction drift between these knots
const GUST_KNOT_HOURS = 2
# Wind
const WIND_SPEED = 40.0          # pixels per second a drifting thing moves at full wind
const PROJECTILE_DRIFT = 90.0    # pixels per second² on a projectile at full wind (Combat)
# Weight
const PERSON_WEIGHT = 70.0
const CHILD_WEIGHT = 35.0
# Light
const NIGHT_DARK = 0.85
const INDOOR_DARK = 0.6
const GLARE = 0.5                # a watcher in full lamp light sees half as far into the black

const BURNABLE = ["flammable", "rope"]

## Tests and tools: false = the rules run only when step(delta) is called
var auto_step: bool = true
## The weather everywhere until a game minute: {weather, wind: [x, y], until (-1: until cleared)}
var weather_override: Dictionary = {}
var weather_seed: int = 1347
var region_override: String = ""

var components: Array = []
var _saved: Dictionary = {}       # physics key -> state, for things not in the tree (and the save)
var _fires: Dictionary = {}       # fire id -> {by, witnesses, minute, owners_recorded, deeds: {owner: event id}, outcomes: {owner: doused|burned}}
var _fire_counter: int = 0
var _last_weather: String = ""

func _ready() -> void:
	var bus = get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("time_advanced"):
		bus.time_advanced.connect(_on_time_advanced)
	_last_weather = get_weather().weather

func _physics_process(delta: float) -> void:
	if auto_step and not components.is_empty():
		step(delta)

# =============================================================================
# CONTRACT
# =============================================================================

## Set something alight. node: a component or a thing holding one. by: "player", an NPC key, or ""
## A flammable catches (not when wet, burning or burnt); a lamp is lit; metal is heated white-hot.
## Returns whether anything new is alight
func ignite(node: Node, by: String = "") -> bool:
	var c = component_of(node, ["flammable", "rope", "lamp", "metal"])
	if c == null:
		return false
	match c.kind():
		"lamp":
			if c.open_flame and c.is_outdoors() and is_raining():
				return false
			return c.set_lit(true)
		"metal":
			c.heat = 1.0
			c.heated_by = by
			return true
	if c.burning or c.burnt or c.is_wet():
		return false
	_catch(c, _new_fire(c, by), by)
	return true

## Put water on something; it is soaked either way. Returns whether a fire, a lamp or hot metal went
## out. by: who ("player" by default, "rain"); the player saving someone's thing from a fire they did
## not light is `help`. A basin is filled instead
func douse(node: Node, by: String = "player") -> bool:
	var c = component_of(node, ["flammable", "rope", "lamp", "metal", "basin"])
	if c == null:
		return false
	if c.kind() == "basin":
		c.fill_with(1.0)
		return false
	c.wetness = 1.0
	var out := false
	match c.kind():
		"lamp":
			out = c.set_lit(false)
		"metal":
			out = c.heat >= HOT
			c.heat = 0.0
		_:
			c.heat = 0.0
			if c.burning:
				out = true
				c.burning = false
				c._show_fire(false)
				c.extinguished.emit(by)
				if by == "player" and c.owner_key != "" and c.lit_by != "player":
					_record_help(c)
				if c.owner_key != "":
					_fire_outcome(c, "doused")
	if out:
		doused.emit(c, by)
	return out

## The wind here: its direction scaled by strength (length 0 calm .. 1 a gale). Fire reaches farther
## downwind; drifting things move at WIND_SPEED px/s at full wind; projectile_drift() for arrows
func get_wind() -> Vector2:
	return get_weather().wind

# =============================================================================
# WEATHER (on the game clock)
# =============================================================================

## {weather, raining, wind: Vector2, strength, direction_deg, region}
func get_weather(region: String = "") -> Dictionary:
	if region == "":
		region = current_region()
	var now = _now()
	if not weather_override.is_empty() and (int(weather_override.get("until", -1)) < 0 or now < int(weather_override.until)):
		var w = weather_override.get("wind", [0.0, 0.0])
		var wind = Vector2(float(w[0]), float(w[1])) if w is Array and w.size() == 2 else Vector2.ZERO
		return _weather_dict(str(weather_override.get("weather", "clear")), wind, region)
	return weather_at(now, region)

## The clock's weather at a game minute: smooth noise between knots, the same for a region every time
func weather_at(minute: int, region: String = "") -> Dictionary:
	var hours = minute / 60.0
	var knot = hours / WEATHER_KNOT_HOURS
	var wet = _noise(region + ":sky", knot)
	var angle = lerp_angle(_hash01(region + ":dir", floori(knot)) * TAU, _hash01(region + ":dir", floori(knot) + 1) * TAU,
		knot - floori(knot))
	var strength = clampf(0.1 + 0.6 * _noise(region + ":gust", hours / GUST_KNOT_HOURS) + 0.5 * maxf(wet - 0.6, 0.0), 0.0, 1.0)
	var weather = "clear"
	if wet > 0.88:
		weather = "storm"
		strength = maxf(strength, 0.75)
	elif wet > 0.7:
		weather = "rain"
	elif wet > 0.5:
		weather = "overcast"
	return _weather_dict(weather, Vector2.from_angle(angle) * strength, region)

func is_raining(region: String = "") -> bool:
	return get_weather(region).raining

## Fix the weather for some game hours (story, tests). wind: direction * strength; hours < 0: until cleared
func set_weather(weather: String, wind: Vector2 = Vector2.ZERO, hours: float = 6.0) -> void:
	if not weather in WEATHERS:
		push_warning("[WorldPhysics] Unknown weather '%s'" % weather)
		return
	weather_override = {"weather": weather, "wind": [wind.x, wind.y],
		"until": _now() + int(hours * 60.0) if hours >= 0.0 else -1}
	_note_weather()
	if is_raining():
		_rain_on(0.0)

func clear_weather() -> void:
	weather_override = {}
	_note_weather()

## Drift on a projectile, pixels per second² (Combat: velocity += WorldPhysics.projectile_drift() * delta)
func projectile_drift() -> Vector2:
	return get_wind() * PROJECTILE_DRIFT

func current_region() -> String:
	if region_override != "":
		return region_override
	var scene_manager = get_node_or_null("/root/SceneManager")
	var registry = get_node_or_null("/root/WorldRegistry")
	if scene_manager and scene_manager.has_method("get_current_location_id") and registry:
		var loc = str(scene_manager.get_current_location_id())
		if loc != "":
			return str(registry.get_region(loc))
	return ""

func _weather_dict(weather: String, wind: Vector2, region: String) -> Dictionary:
	return {"weather": weather, "raining": weather in ["rain", "storm"], "wind": wind,
		"strength": wind.length(), "direction_deg": rad_to_deg(wind.angle()) if wind != Vector2.ZERO else 0.0,
		"region": region}

func _hash01(key: String, i: int) -> float:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash("%d:%s:%d" % [weather_seed, key, i])
	return rng.randf()

func _noise(key: String, t: float) -> float:
	var i = floori(t)
	var f = t - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(_hash01(key, i), _hash01(key, i + 1), f)

func _note_weather() -> void:
	var w = get_weather()
	if w.weather != _last_weather:
		_last_weather = w.weather
		weather_changed.emit(w)

func _on_time_advanced(minutes: int, _total: int = 0, _reason: String = "") -> void:
	advance_game(minutes)

## The game clock moved: a fire left burning runs its course, then weather, rain or drying, rust
func advance_game(minutes: int) -> void:
	if minutes <= 0:
		return
	var hours = minutes / 60.0
	if _any_burning():
		simulate(minf(minutes * 60.0, MAX_CATCHUP_SECONDS))
	_note_weather()
	if is_raining():
		_rain_on(hours)
	else:
		for c in _live():
			c.wetness = maxf(c.wetness - DRY_PER_HOUR * hours, 0.0)
	for c in _live("metal"):
		if c.rusts() and (c.is_wet() or c.sunk):
			c.rust = minf(c.rust + RUST_PER_HOUR * hours, 1.0)
			c.rusted.emit(c.rust)

## Rain on everything outdoors: fire out, things soaked, basins filling
func _rain_on(hours: float) -> void:
	for c in _live():
		if not c.is_outdoors():
			continue
		match c.kind():
			"basin":
				c.fill_with(RAIN_FILL_PER_HOUR * hours)
			"plate", "weight", "shadow":
				pass
			"lamp":
				if c.open_flame:
					douse(c, "rain")
			_:
				douse(c, "rain")

# =============================================================================
# THE RULES, EACH STEP
# =============================================================================

## Run the rules for delta seconds (the physics frame does this; tests call it)
func step(delta: float) -> void:
	_prune()
	var wind = get_wind()
	var burnables = _live("flammable") + _live("rope")
	var metals = _live("metal")
	var flames: Array = []   # [{c, at, reach}]: burning things and open flames
	for f in burnables:
		if f.burning:
			flames.append({"c": f, "at": f.at(), "reach": f.reach})
	for l in _live("lamp"):
		if l.lit and l.open_flame:
			flames.append({"c": l, "at": l.at(), "reach": l.reach})
	var hot: Array = metals.filter(func(m): return m.heat >= HOT and not m.sunk)

	# Fire heats flammables in reach (wind-bent); hot metal heats what it touches
	for f in burnables:
		if f.burning or f.burnt:
			continue
		if f.is_wet():
			f.heat = 0.0
			continue
		var pos = f.at()
		var gain := 0.0
		var best = null
		var best_gain := 0.0
		for src in flames:
			if src.c == f:
				continue
			# Wind bends flames only out of doors; a fire in a room spreads by reach alone
			var g = _heat_from(src.at, src.reach, pos, wind if src.c.is_outdoors() else Vector2.ZERO) * HEAT_RATE * delta
			if g > best_gain:
				best_gain = g
				best = src.c
			gain += g
		for m in hot:
			if m.at().distance_to(pos) <= CONTACT_REACH:
				var g2 = HEAT_RATE * 2.0 * m.heat * delta
				if g2 > best_gain:
					best_gain = g2
					best = m
				gain += g2
		if gain > 0.0:
			f.heat += gain
			if f.heat >= 1.0:
				_catch_from(f, best)
		else:
			f.heat = maxf(f.heat - HEAT_FALLOFF * delta, 0.0)

	# Burning things burn down
	for f in burnables:
		if f.burning:
			f.burn_left -= delta
			if f.burn_left <= 0.0:
				_burn_out(f)

	# Fire and open flames light lamps
	var raining = is_raining()
	for l in _live("lamp"):
		if l.lit or (l.open_flame and raining and l.is_outdoors()):
			continue
		for src in flames:
			if src.c != l and src.at.distance_to(l.at()) <= maxf(src.reach, l.reach):
				l.set_lit(true)
				break

	# Metal heats in a fire's reach and cools out of it
	for m in metals:
		var src_by = null
		for src in flames:
			if src.c.kind() != "lamp" and src.at.distance_to(m.at()) <= src.reach:
				src_by = str(src.c.lit_by)
				break
		if src_by != null and not m.sunk:
			m.heat = minf(m.heat + METAL_HEAT_RATE * delta, 1.0)
			if m.heated_by == "":
				m.heated_by = src_by
		else:
			m.heat = maxf(m.heat - METAL_COOL_RATE * delta, 0.0)
			if m.heat <= 0.0:
				m.heated_by = ""

	# Lodestones pull loose iron until it touches
	for stone in metals:
		if not stone.is_lodestone():
			continue
		for m in metals:
			if m == stone or not m.is_iron() or not m.loose or m.sunk:
				continue
			var d = stone.at() - m.at()
			if d.length() <= stone.pull_range and d.length() > CONTACT_REACH:
				m.thing().global_position += d.normalized() * minf(stone.pull_speed * delta, d.length() - CONTACT_REACH)

	# Light things drift in the wind outdoors
	if wind != Vector2.ZERO:
		for w in _live("weight"):
			if w.drifts and not w.hanging and w.is_outdoors():
				w.thing().global_position += wind * WIND_SPEED * delta

	# Plates
	for p in _live("plate"):
		p.load_weight = weight_on(p)
		p.set_pressed(p.load_weight >= p.weight_needed + p.counterweight + _counter_on(p))

## Run the rules for `seconds` in steps of dt (a clock jump); stops when no fire is left
func simulate(seconds: float, dt: float = 1.0) -> void:
	var left = seconds
	while left > 0.0:
		step(minf(dt, left))
		left -= dt
		if not _any_burning():
			break

## Heat factor (0, or 0.5..1) from a fire at `from` with `reach` on a thing at `to`, wind-bent
func _heat_from(from: Vector2, reach: float, to: Vector2, wind: Vector2) -> float:
	var d = to - from
	var dist = d.length()
	var factor = 1.0
	if wind != Vector2.ZERO and dist > 0.0:
		factor = maxf(1.0 + WIND_REACH * wind.length() * wind.normalized().dot(d / dist), MIN_REACH_FACTOR)
	var r = reach * factor
	if dist > r:
		return 0.0
	return 0.5 + 0.5 * (1.0 - dist / r)

func _any_burning() -> bool:
	for c in components:
		if is_instance_valid(c) and c.get("burning") == true:
			return true
	return false

# =============================================================================
# FIRE
# =============================================================================

## A new fire: who lit it, and (when it was the player) who saw them do it
func _new_fire(c: Node, by: String) -> String:
	_fire_counter += 1
	var id = "fire_%d" % _fire_counter
	var witnesses: Array = []
	if by == "player":
		witnesses = Witnesses.in_sight(scene_root_of(c), c.at(), {"stealth": _player_stealth()})
	_fires[id] = {"by": by, "witnesses": witnesses, "minute": _now(), "owners_recorded": []}
	return id

func _catch(f: Node, fire_id: String, by: String) -> void:
	f.burning = true
	f.heat = 1.0
	f.burn_left = f.burn_seconds
	f.fire_id = fire_id
	f.lit_by = by
	f._show_fire(true)
	f.ignited.emit(by)
	if f.owner_key != "":
		_record_fire(f)
	fire_started.emit(f, by)

## Caught from a burning thing (the same fire), hot metal (a fire of whoever heated it) or a flame
func _catch_from(f: Node, src) -> void:
	if src != null and src.get("fire_id") != null and str(src.fire_id) != "":
		_catch(f, str(src.fire_id), str(src.lit_by))
	elif src != null and src.get("heated_by") != null:
		_catch(f, _new_fire(f, str(src.heated_by)), str(src.heated_by))
	else:
		_catch(f, _new_fire(f, ""), "")

func _burn_out(f: Node) -> void:
	f.burning = false
	f.burnt = true
	f.heat = 0.0
	f.burn_left = 0.0
	if f.owner_key != "":
		_fire_outcome(f, "burned")
	burned.emit(f, f.owner_key)
	# A rope on the same thing parts with it
	var t = f.thing()
	for r in _live("rope"):
		if r != f and r.thing() == t:
			r.sever("fire")
	f._on_burnt()
	_saved[f.physics_key()] = f.get_state()

## The player's fire caught someone's thing: a `fire` deed about them now, whether it is put out or
## burns through (the outcome comes later, _fire_outcome)
func _record_fire(f: Node) -> void:
	var info: Dictionary = _fires.get(f.fire_id, {})
	if str(info.get("by", f.lit_by)) != "player":
		return
	var recorded: Array = info.get("owners_recorded", [])
	if f.owner_key in recorded:
		return   # one deed per owner per fire, however many of their things it took
	recorded.append(f.owner_key)
	info["owners_recorded"] = recorded
	var pe = get_node_or_null("/root/PlayerEvents")
	if pe:
		var deeds: Dictionary = info.get("deeds", {})
		deeds[f.owner_key] = str(pe.record("fire", "set fire to %s's %s" % [_name_of(f.owner_key), f.describe()], [f.owner_key],
			{"witnesses": info.get("witnesses", [])}))
		info["deeds"] = deeds
	_fires[f.fire_id] = info

## How the player's fire ended for this owner. "burned" is final; "doused" holds until another of
## their things burns through in the same fire. Kept on the fire and signalled; PlayerEvents gets
## it through set_outcome when it has one (no second deed)
func _fire_outcome(f: Node, outcome: String) -> void:
	var info: Dictionary = _fires.get(f.fire_id, {})
	if info.is_empty() or str(info.get("by", "")) != "player" or not f.owner_key in info.get("owners_recorded", []):
		return
	var outcomes: Dictionary = info.get("outcomes", {})
	var was = str(outcomes.get(f.owner_key, ""))
	if was == "burned" or was == outcome:
		return
	if outcome == "doused" and _owner_still_burning(f.fire_id, f.owner_key, f):
		return
	outcomes[f.owner_key] = outcome
	info["outcomes"] = outcomes
	_fires[f.fire_id] = info
	var event_id = str(info.get("deeds", {}).get(f.owner_key, ""))
	var pe = get_node_or_null("/root/PlayerEvents")
	if pe and event_id != "" and pe.has_method("set_outcome"):
		pe.set_outcome(event_id, outcome)
	fire_outcome.emit(str(f.fire_id), f.owner_key, outcome, event_id)

func _owner_still_burning(fire_id: String, owner: String, except: Node) -> bool:
	for c in _live("flammable") + _live("rope"):
		if c != except and c.burning and str(c.fire_id) == fire_id and c.owner_key == owner:
			return true
	return false

## The player's fires: {by, witnesses, minute, owners_recorded, deeds, outcomes} (a copy; {} unknown)
func get_fire(fire_id: String) -> Dictionary:
	return _fires.get(fire_id, {}).duplicate(true)

func _record_help(f: Node) -> void:
	var pe = get_node_or_null("/root/PlayerEvents")
	if pe:
		var seen = Witnesses.in_sight(scene_root_of(f), f.at(), {"stealth": _player_stealth()})
		pe.record("help", "put out the fire on %s's %s" % [_name_of(f.owner_key), f.describe()], [f.owner_key],
			{"witnesses": seen})

## Douse every fire within radius of a point (a poured basin, a bucket). Returns how many went out
func douse_area(at: Vector2, radius: float, by: String = "player") -> int:
	var out = 0
	for c in _live():
		if c.kind() in ["flammable", "rope", "lamp", "metal"] and c.at().distance_to(at) <= radius:
			if douse(c, by):
				out += 1
	return out

## Something goes into a basin's water: metal sinks, fire goes out, everything is soaked
func into_water(node: Node, basin: Node, by: String = "player") -> bool:
	var c = component_of(node, ["metal", "flammable", "rope", "lamp"])
	if c == null:
		return false
	douse(c, by)
	if c.kind() == "metal":
		c.sunk = true
		c.heat = 0.0
		if not c.physics_key() in basin.sunk:
			basin.sunk.append(c.physics_key())
	return true

## Put heat into a thing (a forge, a brand): metal warms; a flammable heats toward catching
func heat(node: Node, amount: float, by: String = "") -> void:
	var c = component_of(node, ["metal", "flammable", "rope"])
	if c == null:
		return
	if c.kind() == "metal":
		c.heat = clampf(c.heat + amount, 0.0, 1.0)
		if by != "":
			c.heated_by = by
	elif not c.burning and not c.burnt and not c.is_wet():
		c.heat += amount
		if c.heat >= 1.0:
			_catch(c, _new_fire(c, by), by)

# =============================================================================
# WEIGHT
# =============================================================================

## Everything resting inside a plate: the player, NPC bodies, Weights not hanging, basins' water
func weight_on(plate: Node) -> float:
	var r: Rect2 = plate.rect()
	var scene = scene_root_of(plate)
	var total := 0.0
	var counted := {}
	for w in _live("weight"):
		var t = w.thing()
		if w.hanging or counted.has(t) or not _same_scene(scene, w):
			continue
		if r.has_point(t.global_position):
			total += w.mass
			counted[t] = true
	for b in _live("basin"):
		if _same_scene(scene, b) and r.has_point(b.at()):
			total += b.water_mass * b.fill
	for group in ["player", "npcs"]:
		for n in plate.get_tree().get_nodes_in_group(group):
			if n is Node2D and not counted.has(n) and _same_scene(scene, n) and r.has_point(n.global_position):
				total += weight_of(n)
				counted[n] = true
	return total

## What a body weighs: its Weight, else a `weight` property, else a grown person (a child less)
func weight_of(n: Node) -> float:
	var w = component_of(n, ["weight"])
	if w:
		return w.mass
	var prop = n.get("weight")
	if prop is float or prop is int:
		return float(prop)
	var registry = get_node_or_null("/root/WorldRegistry")
	var id = str(n.get("npc_id")) if n.get("npc_id") != null else ""
	if id != "" and registry and registry.is_minor(id):
		return CHILD_WEIGHT
	return PERSON_WEIGHT

## Counterweights holding a plate up: hanging Weights that counter it
func _counter_on(plate: Node) -> float:
	var total := 0.0
	for w in _live("weight"):
		if w.hanging and w.countered_plate() == plate:
			total += w.mass
	return total

# =============================================================================
# LIGHT
# =============================================================================

## How dark it is at a point, 0 bright .. 1 black. opts: scene_root (only lamps, fires and shadows
## there), outdoors (default true), hour (default the clock), indoor_dark. Night and rain darken
## outdoors; indoors is dim; shadows deepen it; lit lamps and fires light it. For Witnesses later
func darkness_at(at: Vector2, opts: Dictionary = {}) -> float:
	var dark: float
	if bool(opts.get("outdoors", true)):
		var hour = float(opts.get("hour", _hour()))
		if hour >= 7.0 and hour < 18.0:
			dark = 0.0
		elif hour >= 5.0 and hour < 7.0:
			dark = NIGHT_DARK * (7.0 - hour) / 2.0
		elif hour >= 18.0 and hour < 21.0:
			dark = NIGHT_DARK * (hour - 18.0) / 3.0
		else:
			dark = NIGHT_DARK
		if get_weather().weather != "clear":
			dark = minf(dark + 0.15, 1.0)
	else:
		dark = float(opts.get("indoor_dark", INDOOR_DARK))
	var scene = opts.get("scene_root", null)
	for s in _live("shadow"):
		if _same_scene(scene, s) and s.at().distance_to(at) <= s.radius:
			dark = maxf(dark, s.depth)
	return clampf(dark * (1.0 - light_at(at, opts)), 0.0, 1.0)

## Light from lit lamps and fires at a point, 0 none .. 1 full (opts.scene_root: only those there)
func light_at(at: Vector2, opts: Dictionary = {}) -> float:
	var scene = opts.get("scene_root", null)
	var light := 0.0
	for l in _live("lamp"):
		if l.lit and _same_scene(scene, l):
			light = maxf(light, _falloff(l.at().distance_to(at), l.light_radius))
	for f in _live("flammable") + _live("rope"):
		if f.burning and _same_scene(scene, f):
			light = maxf(light, _falloff(f.at().distance_to(at), FIRE_LIGHT))
	return light

## Lamps blind (§5.1 "lamps reveal and blind"): a watcher standing in lamp or fire light sees less of
## a dark spot beyond it, as eyes used to the flame do. Factor on that watcher's sight (1 .. 1-GLARE):
## light where they stand times darkness where they look. A spot inside the same light is not dark,
## so a witness by a lit lamp sees what happens in its light
func glare_factor(watcher_at: Vector2, at: Vector2, opts: Dictionary = {}) -> float:
	var glare = light_at(watcher_at, opts)
	if glare <= 0.0:
		return 1.0
	return 1.0 - GLARE * glare * darkness_at(at, opts)

## How far a watcher's sight reaches into that darkness, as a factor (1 full .. 0.3 near blind)
func sight_factor(at: Vector2, opts: Dictionary = {}) -> float:
	return lerpf(1.0, 0.3, darkness_at(at, opts))

func is_lit(at: Vector2, opts: Dictionary = {}) -> bool:
	return darkness_at(at, opts) < 0.4

func _falloff(dist: float, radius: float) -> float:
	if dist >= radius:
		return 0.0
	var x = dist / radius
	return 1.0 - x * x

# =============================================================================
# COMPONENTS
# =============================================================================

## Components call these as they enter and leave the tree; a known key gets its saved state back
func register(c: Node) -> void:
	if c in components:
		return
	components.append(c)
	var key = c.physics_key()
	if _saved.has(key):
		c.apply_state(_saved[key])

func unregister(c: Node) -> void:
	if c in components:
		_saved[c.physics_key()] = c.get_state()
		components.erase(c)

## The component of one of `kinds` on a node: the node itself or a child of it
func component_of(node: Node, kinds: Array) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if node.has_method("physics_key") and node.kind() in kinds:
		return node
	for k in kinds:
		for child in node.get_children():
			if child.has_method("physics_key") and child.kind() == k:
				return child
	return null

## The level a node is in (its top ancestor under the tree root)
func scene_root_of(node: Node) -> Node:
	var n = node
	while n and n.get_parent() and n.get_parent() != n.get_tree().root:
		n = n.get_parent()
	return n

func _same_scene(scene, n: Node) -> bool:
	return scene == null or scene == n or scene.is_ancestor_of(n)

func _live(kind: String = "") -> Array:
	var out: Array = []
	for c in components:
		if is_instance_valid(c) and c.is_inside_tree() and not c.is_queued_for_deletion() and (kind == "" or c.kind() == kind):
			out.append(c)
	return out

func _prune() -> void:
	components = components.filter(func(c): return is_instance_valid(c))

func _name_of(key: String) -> String:
	var registry = get_node_or_null("/root/WorldRegistry")
	if registry and registry.has_method("get_npc_name"):
		var n = str(registry.get_npc_name(key))
		if n != "":
			return n
	return key.capitalize()

func _player_stealth() -> float:
	var stats = get_node_or_null("/root/PlayerStats")
	return float(stats.get_skill("stealth")) if stats and stats.has_method("get_skill") else 0.0

func _now() -> int:
	var world_state = get_node_or_null("/root/WorldState")
	return world_state.get_game_minutes() if world_state and world_state.has_method("get_game_minutes") else 0

func _hour() -> int:
	var world_state = get_node_or_null("/root/WorldState")
	return world_state.get_hour() if world_state and world_state.has_method("get_hour") else 12

# =============================================================================
# SAVE / LOAD (WorldState "player_systems" block)
# =============================================================================

## Fire, wetness, heat and rust, plates, ropes, basins and loose weights of every scene visited; the
## weather seed and override; the fires the player started (so no deed is recorded twice)
func save() -> Dictionary:
	var objects = _saved.duplicate(true)
	for c in _live():
		objects[c.physics_key()] = c.get_state()
	return {"version": 1, "weather_seed": weather_seed, "weather_override": weather_override.duplicate(true),
		"objects": objects, "fires": _fires.duplicate(true), "fire_counter": _fire_counter}

func load_from_dict(data: Dictionary) -> void:
	weather_seed = int(data.get("weather_seed", weather_seed))
	weather_override = data.weather_override.duplicate(true) if data.get("weather_override") is Dictionary else {}
	_saved = data.objects.duplicate(true) if data.get("objects") is Dictionary else {}
	_fires = data.fires.duplicate(true) if data.get("fires") is Dictionary else {}
	_fire_counter = int(data.get("fire_counter", _fire_counter))
	for c in _live():
		if _saved.has(c.physics_key()):
			c.apply_state(_saved[c.physics_key()])
	_last_weather = get_weather().weather
