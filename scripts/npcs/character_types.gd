extends RefCounted
## CharacterTypes - what kind of person someone is beyond what they carry
## (resources/characters/character_types.json; docs/WORLD_SCHEMA.md §9.1).
## A type gives base traits (behaviour switches below), skills (0-100 by skills.json id: Combat reads
## them as it reads the player's), temperament (Big Five offsets on a generic's roll), morale, bow
## tactics and senses. Main NPCs take a type by world.json key (`npcs`, whose values override the
## type's); generics by their archetype's `type:` header. No type: ordinary folk, and every query
## below answers neutral (no traits, no skills, no bonus).
## A resolved "kind" is {type, name, traits, skills, temperament, morale, tactics, senses,
## indoor_hours, prompt}; callers resolve once and pass it to the queries

const DATA_PATH = "res://resources/characters/character_types.json"
const CREATURES_PATH = "res://resources/combat/creatures.json"
const Herbcraft = preload("res://scripts/crafting/herbcraft.gd")
const Seasons = preload("res://scripts/world/seasons.gd")

## What each trait does in the engine (the validator keeps this list in step)
const TRAITS = {
	"trail_reader": "reads tracks: a body found where they stand is laid at the stranger's door as if the stranger had been seen there (trail_fidelity)",
	"woodwise": "under the sky they see farther (sight_factor) and are harder to see (concealment)",
	"keeps_distance": "with a bow they hold a foe at range, and draw the sidearm only when closed on",
	"beast_and_herb_lore": "they know which creatures range where they stand and which herbs are in season there (craft_lines)",
	"weather_eye": "they can read the sky some hours ahead (craft_lines)",
	"wilds_over_towns": "under a roof only by day (indoor_hours); outdoors at any hour",
}
## Any NPC with a bow and no type fights like this
const DEFAULT_TACTICS = {"keep_range": [120.0, 300.0], "close_range": 70.0, "shoot_seconds": 2.2, "switch_seconds": 0.6}
const MIN_SHOOT_SECONDS = 1.3      # never faster than the bow's own draw (weapons.json speed 0.8)
const DRAW_SKILL = 0.4             # bows 100 draws 40% faster ("draw speed", skills.json)
const TRAIL_BASE = 0.5             # PlayerEvents.FOUND_LINKED: a trail read is as good as being seen there
const TRAIL_SKILL = 0.3            # woodcraft 100 adds this much
const TRAIL_CAP = 0.8
const WEATHER_AHEAD_MINUTES = 360
const OUTDOOR_STEALTH_SHARE = 0.5  # stealth counts half under a roof or without woodwise

static var _data: Dictionary = {}
static var _creatures: Array = []

static func _load() -> Dictionary:
	if _data.is_empty():
		var file = FileAccess.open(DATA_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				_data = parsed
		if _data.is_empty():
			_data = {"types": {}, "npcs": {}}
	return _data

## Tests: read a fixture (or the real file again with "")
static func reload(path: String = "") -> void:
	_data = {}
	if path != "":
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		_data = parsed if parsed is Dictionary else {"types": {}, "npcs": {}}
	_load()

static func type_ids() -> Array:
	return _load().get("types", {}).keys()

static func has_type(type_id: String) -> bool:
	return _load().get("types", {}).has(type_id)

## The type a main NPC was given by world.json key ("" for none)
static func type_for_npc(npc_key: String) -> String:
	var row = _load().get("npcs", {}).get(npc_key, {})
	return str(row.get("type", "")) if row is Dictionary else ""

## A type, with a main NPC's own values over it. "" or unknown: ordinary folk
static func resolve(type_id: String, npc_key: String = "") -> Dictionary:
	var base = _load().get("types", {}).get(type_id, {})
	var own = _load().get("npcs", {}).get(npc_key, {}) if npc_key != "" else {}
	if not base is Dictionary or base.is_empty():
		return neutral()
	if not own is Dictionary:
		own = {}
	var skills: Dictionary = {}
	for source in [base.get("skills", {}), own.get("skills", {})]:
		for s in source:
			skills[str(s)] = clampf(float(source[s]), 0.0, 100.0)
	var tactics: Dictionary = DEFAULT_TACTICS.duplicate(true)
	for source in [base.get("tactics", {}), own.get("tactics", {})]:
		for k in source:
			tactics[str(k)] = source[k]
	var traits: Array = []
	for t in base.get("traits", []) + own.get("traits", []):
		if str(t) in TRAITS and not str(t) in traits:
			traits.append(str(t))
	return {"type": type_id, "name": str(base.get("name", type_id)), "traits": traits, "skills": skills,
		"temperament": base.get("temperament", {}).duplicate(), "morale": float(own.get("morale", base.get("morale", 0.0))),
		"tactics": tactics, "senses": base.get("senses", {}).duplicate(), "indoor_hours": base.get("indoor_hours", []).duplicate(),
		"prompt": str(base.get("prompt", ""))}

static func neutral() -> Dictionary:
	return {"type": "", "name": "", "traits": [], "skills": {}, "temperament": {}, "morale": 0.0,
		"tactics": DEFAULT_TACTICS.duplicate(true), "senses": {}, "indoor_hours": [], "prompt": ""}

## By combat/npc key: a main NPC by world.json key, a generic by its archetype's type (GenericManager)
static func of_key(key: String) -> Dictionary:
	if key == "" or key == "player" or key.begins_with("creature:"):
		return neutral()
	var main = type_for_npc(key)
	if main != "":
		return resolve(main, key)
	var gm = _generics()
	if gm and gm.has_method("character_kind") and gm.has_method("is_generic") and gm.is_generic(key):
		return gm.character_kind(key)
	return neutral()

# =============================================================================
# QUERIES (kind = a resolved dictionary)
# =============================================================================

static func has_trait(kind: Dictionary, trait_id: String) -> bool:
	return trait_id in kind.get("traits", [])

static func skill(kind: Dictionary, skill_id: String) -> float:
	return float(kind.get("skills", {}).get(skill_id, 0.0))

static func tactics(kind: Dictionary) -> Dictionary:
	var t: Dictionary = kind.get("tactics", DEFAULT_TACTICS)
	var out = DEFAULT_TACTICS.duplicate(true)
	for k in t:
		out[k] = t[k]
	return out

## Seconds between loosed arrows: the type's draw, quicker with the bows skill
static func shoot_seconds(kind: Dictionary) -> float:
	var base = float(tactics(kind).get("shoot_seconds", DEFAULT_TACTICS.shoot_seconds))
	return maxf(base * (1.0 - DRAW_SKILL * skill(kind, "bows") / 100.0), MIN_SHOOT_SECONDS)

static func morale_bonus(kind: Dictionary) -> float:
	return float(kind.get("morale", 0.0))

## How far they see, as a multiple of anyone's (Witnesses range): woodwise under the sky
static func sight_factor(kind: Dictionary, outdoors: bool) -> float:
	if outdoors and has_trait(kind, "woodwise"):
		return float(kind.get("senses", {}).get("outdoor_sight", 1.0))
	return 1.0

## 0-100, how hard they are to see (Witnesses' stealth scale): full stealth for the woodwise under the
## sky, half of it anywhere else
static func concealment(kind: Dictionary, outdoors: bool) -> float:
	var s = skill(kind, "stealth")
	return s if outdoors and has_trait(kind, "woodwise") else s * OUTDOOR_STEALTH_SHARE

## How well someone who comes upon a body knows who did it. A trail reader reads the stranger's tracks
## (PlayerEvents.check_traces: FOUND_ANON -> at least TRAIL_BASE, more with woodcraft)
static func trail_fidelity(kind: Dictionary, found_fidelity: float) -> float:
	if not has_trait(kind, "trail_reader"):
		return found_fidelity
	return maxf(found_fidelity, minf(TRAIL_BASE + TRAIL_SKILL * skill(kind, "woodcraft") / 100.0, TRAIL_CAP))

## Present now, given the place: a wilds_over_towns type is under a roof only within indoor_hours
static func present_at(kind: Dictionary, indoors: bool, hour: int) -> bool:
	var h: Array = kind.get("indoor_hours", [])
	if not indoors or not has_trait(kind, "wilds_over_towns") or h.size() < 2:
		return true
	var start = int(h[0])
	var end = int(h[1])
	return (hour >= start and hour < end) if start <= end else (hour >= start or hour < end)

## What their craft tells them where they stand, for a conversation prompt: the creatures that range
## here, the herbs in season here, the sky a few hours on. [] for ordinary folk
static func craft_lines(kind: Dictionary, location: String, minute: int) -> Array:
	var lines: Array = []
	if location == "" or kind.get("type", "") == "":
		return lines
	if has_trait(kind, "beast_and_herb_lore"):
		var beasts: Array = []
		for c in _creature_rows():
			for w in c.get("where", []):
				if w is Dictionary and str(w.get("location", "")) == location and not str(c.get("name", "")) in beasts:
					beasts.append(str(c.get("name", c.get("id", ""))))
		if not beasts.is_empty():
			lines.append("Creatures that range here: %s." % ", ".join(beasts))
		var season = Seasons.season_at(minute)
		var herbs: Array = []
		for id in Herbcraft.ingredients_at(location, season):
			var ing = Herbcraft.ingredient(id)
			herbs.append(str(ing.get("name", id)).to_lower())
		if not herbs.is_empty():
			lines.append("Growing or to be had here this %s: %s." % [season, ", ".join(herbs.slice(0, 6))])
	if has_trait(kind, "weather_eye"):
		var physics = _node("WorldPhysics")
		var registry = _node("WorldRegistry")
		if physics and physics.has_method("weather_at"):
			var region = registry.get_region(location) if registry and registry.has_method("get_region") else ""
			var now = physics.weather_at(minute, region)
			var later = physics.weather_at(minute + WEATHER_AHEAD_MINUTES, region)
			if str(now.get("weather", "")) == str(later.get("weather", "")):
				lines.append("The sky will hold %s for the next few hours." % str(later.get("weather", "clear")))
			else:
				lines.append("The sky will turn from %s to %s within a few hours." % [str(now.get("weather", "")), str(later.get("weather", ""))])
	return lines

static func _creature_rows() -> Array:
	if _creatures.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CREATURES_PATH)) if FileAccess.file_exists(CREATURES_PATH) else null
		if parsed is Dictionary and parsed.get("creatures") is Array:
			_creatures = parsed.creatures
	return _creatures

static func _generics() -> Node:
	var reg = _node("DynamicNPCRegistry")
	return reg.generics if reg and "generics" in reg else null

static func _node(path: String) -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(path) if tree else null
