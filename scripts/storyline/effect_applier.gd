extends RefCounted
# EffectApplier - The fixed effect vocabulary (docs/WORLD_SCHEMA.md §3), validated and applied
# validate() normalizes and clamps an effect or explains why it is unusable
# apply() performs it through the owning systems (WorldState, EventPropagator, NPCs, Director)

const EFFECT_TYPES = ["set_flag", "adjust_relationship", "spread_rumor", "agenda", "move_npc", "block_beat", "unlock_beat", "shift_want"]
const DIMENSIONS = ["trust", "respect", "affection", "fear", "familiarity"]
# NPC keys and locations come from WorldRegistry (resources/world/world.json), never a list here
const MAX_AGENDA_CHARS = 160
const RUMOR_IMPORTANCE = 7

var director: Node  # StorylineDirector that owns beats, souls and agendas

func _init(owner_director: Node = null):
	director = owner_director

## The WorldRegistry autoload (null outside a running tree)
static func registry() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("WorldRegistry") if tree and tree.root else null

static func is_npc_key(key: String) -> bool:
	var reg = registry()
	return reg != null and reg.has_npc(key)

static func is_location(location_id: String) -> bool:
	var reg = registry()
	return reg != null and reg.has_location(location_id)

## A roster NPC, or a soul registered with the Director at runtime (generics, promoted NPCs)
func _is_actor(key: String) -> bool:
	return is_npc_key(key) or (director != null and director.has_method("has_soul") and director.has_soul(key))

## npc_id for a roster key (the key itself when unknown)
static func npc_id_for(key: String) -> String:
	var reg = registry()
	var npc_id = reg.get_npc_id(key) if reg else ""
	return npc_id if npc_id != "" else key

## Validate an effect against the vocabulary. Returns {"ok": bool, "effect": normalized copy, "reason": String}
func validate(effect) -> Dictionary:
	if not effect is Dictionary:
		return _invalid("effect is not an object")
	var e: Dictionary = effect.duplicate(true)
	var effect_type = str(e.get("type", ""))
	if effect_type not in EFFECT_TYPES:
		return _invalid("unknown effect type '%s'" % effect_type)

	match effect_type:
		"set_flag":
			if not _is_known_flag(str(e.get("flag", ""))):
				return _invalid("unknown flag '%s'" % e.get("flag", ""))
			# Calendar flags (world.json calendar) are world fixed points: only the game clock sets them
			if StoryFlags.is_calendar_flag(str(e.flag)):
				return _invalid("'%s' is a calendar fixed point: only the game clock sets it" % e.flag)
			# Personal flags (docs/WORLD_SCHEMA.md §8) are read by storylines, set only by that NPC's own life
			if director != null and director.has_method("is_personal_flag") and director.is_personal_flag(str(e.flag)):
				return _invalid("'%s' is a personal flag: only that NPC's own life can set it" % e.flag)
			e["value"] = e.get("value", true) == true
		"adjust_relationship":
			if not _is_actor(str(e.get("npc", ""))):
				return _invalid("unknown npc '%s'" % e.get("npc", ""))
			if str(e.get("dimension", "")) not in DIMENSIONS:
				return _invalid("unknown dimension '%s'" % e.get("dimension", ""))
			if not (e.get("delta") is int or e.get("delta") is float):
				return _invalid("delta is not a number")
			e["delta"] = clampi(int(e.delta), -20, 20)
		"spread_rumor":
			var flag = str(e.get("flag", ""))
			if not _is_known_flag(flag) or StoryFlags.get_flag_description(flag) == "":
				return _invalid("no canonical text for flag '%s'" % flag)
			var to = e.get("to", [])
			if to is String:
				to = [to]
			if not to is Array or to.is_empty():
				return _invalid("spread_rumor needs 'to'")
			var keys: Array = []
			for key in to:
				if str(key) != "*" and not _is_actor(str(key)):
					return _invalid("unknown npc '%s' in 'to'" % key)
				keys.append(str(key))
			e["to"] = keys
			e["via"] = str(e.get("via", "word passed quietly from one ear to the next"))
		"agenda":
			if not _is_actor(str(e.get("npc", ""))):
				return _invalid("unknown npc '%s'" % e.get("npc", ""))
			var text = str(e.get("text", "")).strip_edges()
			if text == "":
				return _invalid("agenda text is empty")
			e["text"] = text.substr(0, MAX_AGENDA_CHARS)
		"move_npc":
			if not _is_actor(str(e.get("npc", ""))):
				return _invalid("unknown npc '%s'" % e.get("npc", ""))
			if not is_location(str(e.get("location", ""))):
				return _invalid("unknown location '%s'" % e.get("location", ""))
		"block_beat", "unlock_beat":
			if director == null or not director.has_beat(str(e.get("storyline", "")), str(e.get("beat", ""))):
				return _invalid("unknown beat '%s/%s'" % [e.get("storyline", ""), e.get("beat", "")])
		"shift_want":
			if not _is_actor(str(e.get("npc", ""))):
				return _invalid("unknown npc '%s'" % e.get("npc", ""))
			var soul = director.get_soul(str(e.npc)) if director else null
			if soul == null or not soul.has_want(str(e.get("want", ""))):
				return _invalid("%s has no want '%s'" % [e.get("npc", ""), e.get("want", "")])
			if not (e.get("delta") is int or e.get("delta") is float):
				return _invalid("delta is not a number")
			e["delta"] = clampi(int(e.delta), -3, 3)
	return {"ok": true, "effect": e, "reason": ""}

## Apply an already-validated effect. actor_key is the NPC who caused it ("" = the storyline itself)
## Returns {"ok": bool, "reason": String}
func apply(e: Dictionary, actor_key: String = "", source: Dictionary = {}) -> Dictionary:
	match str(e.type):
		"set_flag":
			var world_state = _node("WorldState")
			if world_state == null:
				return _failed("WorldState unavailable")
			world_state.set_world_flag(e.flag, e.value)
		"adjust_relationship":
			director.apply_relationship_delta(e.npc, e.dimension, e.delta)
		"spread_rumor":
			var propagator = _node("EventPropagator")
			if propagator == null or not propagator.has_method("spread_flag"):
				return _failed("EventPropagator unavailable")
			# Rumors carry canon, so only things that actually happened can spread
			var world_state = _node("WorldState")
			if world_state == null or not world_state.get_world_flag(e.flag):
				return _failed("rumor of untrue flag (%s)" % e.flag)
			propagator.spread_flag(e.flag, e.to, e.via, int(e.get("importance", RUMOR_IMPORTANCE)), _origin_region(actor_key, source))
		"agenda":
			director.add_agenda(e.npc, e.text, actor_key, source)
		"move_npc":
			var moved: Dictionary = director.send_npc(e.npc, e.location)
			if not moved.ok:
				return _failed(moved.reason)
		"block_beat":
			director.set_beat_blocked(e.storyline, e.beat, true)
		"unlock_beat":
			director.set_beat_blocked(e.storyline, e.beat, false)
		"shift_want":
			director.shift_want(e.npc, e.want, e.delta)
	return {"ok": true, "reason": ""}

## Where "*" listeners for a rumor live: the actor's region, else the beat's, else "" (EventPropagator decides)
func _origin_region(actor_key: String, source: Dictionary) -> String:
	var reg = registry()
	if reg == null:
		return ""
	if actor_key != "" and reg.has_npc(actor_key) and director and director.has_method("get_npc_location"):
		return reg.get_region(director.get_npc_location(actor_key))
	if director and source.has("storyline") and source.has("beat") and director.has_method("get_beat_location"):
		return reg.get_region(director.get_beat_location(str(source.storyline), str(source.beat)))
	return ""

## Flags effects may name: base flags (built-in + world.json discovery_flags) plus storyline-declared flags
func _is_known_flag(flag: String) -> bool:
	if flag == "":
		return false
	if StoryFlags.is_base_flag(flag):  # built-in flags and world.json discovery flags
		return true
	return director != null and director.is_known_flag(flag)

func _node(autoload: String) -> Node:
	if director and director.is_inside_tree():
		return director.get_node_or_null("/root/" + autoload)
	return null

func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "effect": {}, "reason": reason}

func _failed(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
