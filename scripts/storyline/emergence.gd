extends RefCounted
# Emergence - Emergent beats (docs/WORLD_SCHEMA.md §12): stories that grow out of what the player did
# Templates (resources/emergence/*.json) are instantiated whenever the world matches their trigger:
# a player event (PlayerEvents signals), a reputation or relationship threshold, flags. Roles bind to
# real NPCs (generics included) at instantiation; slots ({role}, {role.home}, {event.summary},
# {event.id}, {player}) are filled in. Each instance is a transient beat whose hooks join the
# StorylineDirector's decision queue (storyline id "emergent:<instance id>") and are decided on the
# normal story clock. The offline chooser scores options by `appeal` (dot product with the bound
# NPC's feelings toward the player), filtered by its soul's Lines and Agency.
# Emergent beats act at personal scope (plus spread_event and shift_fixed_point): they NEVER set,
# block or unlock storyline flags or beats. They resolve on talked_to:<role>, expired, days:<n> or flags
# The StorylineDirector owns this object; it saves inside the Director's save

const PREFIX = "emergent:"
const PERSONAL_EFFECTS = ["agenda", "move_npc", "adjust_relationship", "shift_want", "spread_rumor"]
const EXTRA_EFFECTS = ["spread_event", "shift_fixed_point"]
const STORY_ONLY = ["set_flag", "block_beat", "unlock_beat"]
const DIMENSIONS = ["trust", "respect", "affection", "fear", "familiarity"]
const HOOK_TYPES = ["intercept", "react", "scheme", "reveal", "aid", "betray"]
const DEFAULT_COOLDOWN_DAYS = 1.0
const DEFAULT_MAX_ACTIVE = 1
const DEFAULT_EXPIRES_DAYS = 3.0
const MAX_CLOSED_KEPT = 100
const MINUTES_PER_DAY = 1440
const ACTION_BUDGET = 3
const IDENT_FIELDS = ["npc", "event", "location", "point", "storyline", "beat", "want", "flag", "dimension"]

var director: Node

# Content
var templates: Dictionary = {}       # id -> normalized template
var template_order: Array = []       # ids in file-name order
var load_errors: Array = []          # ["file: reason"]

# State (saved)
var instances: Dictionary = {}       # instance id -> instance
var instance_order: Array = []       # oldest first
var seq: int = 0
var template_last: Dictionary = {}   # template id -> game minute it last instantiated
var seen: Dictionary = {}            # "template|event id" -> true (one instance per template per event)
var events_seen: Dictionary = {}     # event id -> event, as the PlayerEvents signals delivered it (min_count, first)

func _init(owner_director: Node = null):
	director = owner_director

# =============================================================================
# CONTENT
# =============================================================================

## Load every *.json under dir. A file holds one template, an array of them, or {"templates": [...]}
func load_templates(dir_path: String) -> int:
	templates.clear()
	template_order.clear()
	load_errors.clear()
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return 0
	var names: Array = []
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			names.append(file_name)
	names.sort()
	for file_name in names:
		var file = FileAccess.open("%s/%s" % [dir_path, file_name], FileAccess.READ)
		if file == null:
			continue
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		var list: Array = []
		if data is Dictionary and data.get("templates") is Array:
			list = data.templates
		elif data is Dictionary:
			list = [data]
		elif data is Array:
			list = data
		else:
			load_errors.append("%s: not JSON" % file_name)
			continue
		for raw in list:
			var checked = _normalize_template(raw)
			if not checked.ok:
				load_errors.append("%s: %s" % [file_name, checked.reason])
				push_warning("[Emergence] Skipping template in %s: %s" % [file_name, checked.reason])
				continue
			var t: Dictionary = checked.template
			if templates.has(t.id):
				load_errors.append("%s: duplicate template id '%s'" % [file_name, t.id])
				continue
			t["file"] = file_name
			templates[t.id] = t
			template_order.append(t.id)
	return templates.size()

func _normalize_template(raw) -> Dictionary:
	if not raw is Dictionary:
		return {"ok": false, "reason": "a template must be an object"}
	var t: Dictionary = raw.duplicate(true)
	if not t.get("id") is String or str(t.id).strip_edges() == "":
		return {"ok": false, "reason": "no string id"}
	var tid = str(t.id)
	if not t.get("hooks") is Array or t.hooks.is_empty():
		return {"ok": false, "reason": "%s has no hooks" % tid}
	if not t.get("trigger") is Dictionary or t.trigger.is_empty():
		return {"ok": false, "reason": "%s has no trigger" % tid}
	var roles = t.get("roles", {})
	if not roles is Dictionary:
		return {"ok": false, "reason": "%s: roles must be an object" % tid}
	for role in roles:
		if not roles[role] is Dictionary or roles[role].get("from") == null:
			return {"ok": false, "reason": "%s: role '%s' needs from" % [tid, role]}
	var hook_ids: Dictionary = {}
	for hook in t.hooks:
		if not hook is Dictionary or not hook.get("id") is String or not hook.get("options") is Array:
			return {"ok": false, "reason": "%s: every hook needs an id and options" % tid}
		if hook_ids.has(hook.id):
			return {"ok": false, "reason": "%s: duplicate hook id '%s'" % [tid, hook.id]}
		hook_ids[hook.id] = true
		if str(hook.get("type", "react")) not in HOOK_TYPES:
			return {"ok": false, "reason": "%s/%s: unknown hook type '%s'" % [tid, hook.id, hook.get("type", "")]}
		for role in _hook_roles(hook):
			if not roles.has(role):
				return {"ok": false, "reason": "%s/%s: eligible role '%s' is not declared" % [tid, hook.id, role]}
		for option in hook.options:
			if not option is Dictionary or not option.get("id") is String:
				return {"ok": false, "reason": "%s/%s: every option needs an id" % [tid, hook.id]}
			for effect in option.get("effects", []):
				if effect is Dictionary and str(effect.get("type", "")) in STORY_ONLY:
					return {"ok": false, "reason": "%s/%s/%s: emergent beats never use %s" % [tid, hook.id, option.id, effect.type]}
	t["id"] = tid
	t["title"] = str(t.get("title", tid))
	t["roles"] = roles
	t["cooldown_days"] = float(t.get("cooldown_days", DEFAULT_COOLDOWN_DAYS))
	t["max_active"] = maxi(int(t.get("max_active", DEFAULT_MAX_ACTIVE)), 1)
	t["expires_days"] = float(t.get("expires_days", DEFAULT_EXPIRES_DAYS))
	var resolves = t.get("resolves_on", ["expired"])
	t["resolves_on"] = resolves if resolves is Array else [str(resolves)]
	return {"ok": true, "template": t}

## Roles that may act at a hook: eligible_role, eligible_roles, or eligible ["{role}" | "role"]
func _hook_roles(hook: Dictionary) -> Array:
	var roles: Array = []
	if hook.get("eligible_role") is String:
		roles.append(str(hook.eligible_role))
	for role in hook.get("eligible_roles", []) if hook.get("eligible_roles") is Array else []:
		roles.append(str(role))
	for role in hook.get("eligible", []) if hook.get("eligible") is Array else []:
		roles.append(str(role).trim_prefix("{").trim_suffix("}"))
	return roles

func get_template(template_id: String) -> Dictionary:
	return templates.get(template_id, {})

# =============================================================================
# TRIGGERS
# =============================================================================

## A player event was recorded or changed (PlayerEvents signals): instantiate every template it matches
func on_player_event(ev: Dictionary) -> Array:
	var made: Array = []
	if ev.is_empty():
		return made
	if str(ev.get("id", "")) != "":
		events_seen[str(ev.id)] = ev.duplicate(true)
	for tid in _templates_by_priority():
		var t: Dictionary = templates[tid]
		var spec = t.trigger.get("event")
		if not spec is Dictionary or not event_matches(spec, ev) or not _count_holds(spec, ev):
			continue
		var conditions = _conditions(t.trigger)
		if not conditions.ok:
			continue
		var inst = try_instantiate(tid, ev, conditions.matches)
		if not inst.is_empty():
			made.append(inst)
	return made

## Templates without an event trigger: instantiate those whose conditions hold now (each round)
func evaluate_conditions() -> Array:
	var made: Array = []
	for tid in _templates_by_priority():
		var t: Dictionary = templates[tid]
		if t.trigger.has("event"):
			continue
		var conditions = _conditions(t.trigger)
		if not conditions.ok:
			continue
		var inst = try_instantiate(tid, conditions.get("event", {}), conditions.matches)
		if not inst.is_empty():
			made.append(inst)
	return made

# =============================================================================
# CROWDS (trigger "crowd"): a mob forms from the NPCs themselves, not from a plot point
# A target with at least `min` hostile souls in its area (not travelling) draws a crowd. Hostility
# comes from the souls: against an NPC, a Lines `ally:<target>` rule ("he'll get nothing from this
# forge"); against the player, the NPC's own feelings crossing the template's `hostile` thresholds.
# Protectors are souls in the area with a `harm:<target>` Line. Roles: crowd_target, crowd_aggrieved
# (most hostile first), crowd_protector. Who joins, refuses or defends is each soul's own choice
# (offline appeal or Claude), under its Agency and Lines as always
# =============================================================================

var _crowd: Dictionary = {}  # the crowd the last "crowd" condition found: {target, aggrieved, protectors}
var crowd_members: Dictionary = {}  # target -> every soul that was ever in a crowd against it (saved)

func _crowd_condition(spec: Dictionary) -> Dictionary:
	var need = maxi(int(spec.get("min", 3)), 2)
	var against = str(spec.get("against", "npc"))
	var registry = director._registry()
	if registry == null:
		return {}
	var people: Array = []  # [key, area]
	for key in director.get_soul_keys():
		if not director._is_npc_alive(key) or director.is_npc_travelling(key):
			continue
		var here = director.get_npc_location(key)
		if here == "" or not registry.has_location(here):
			continue
		people.append([key, registry.get_area(here)])
	people.sort_custom(func(a, b): return a[0] < b[0])
	if against == "player":
		var where = director.get_player_location()
		if where == "" or not registry.has_location(where):
			return {}
		var area = registry.get_area(where)
		var hostile: Array = []
		for p in people:
			if p[1] == area and _hostile_to_player(p[0], spec.get("hostile", {})):
				hostile.append(p[0])
		if hostile.size() < need:
			return {}
		hostile.sort_custom(func(a, b): return _player_hostility(a) > _player_hostility(b))
		return {"target": "player", "aggrieved": hostile, "protectors": [], "location": where, "area": area}
	var best: Dictionary = {}
	var only = str(spec.get("target", ""))  # optional: crowds against one person only
	for t in people:
		var target: String = t[0]
		if only != "" and target != director._npc_key(only):
			continue
		if _is_minor(target):
			continue  # no crowd ever forms against a child (§1.4)
		var aggrieved: Array = []
		var protectors: Array = []
		for p in people:
			if p[0] == target or p[1] != t[1]:
				continue
			var soul = director.get_soul(p[0])
			if soul == null:
				continue
			if soul._forbidding_rule("ally:" + target) != "":
				aggrieved.append(p[0])
			elif soul._forbidding_rule("harm:" + target) != "":
				protectors.append(p[0])
		# Those whose own Lines refuse crowds (`crowd`) may be in one, but are not the ones asked to lead it
		aggrieved.sort_custom(func(a, b):
			var a_refuses = director.get_soul(a)._forbidding_rule("crowd") != ""
			var b_refuses = director.get_soul(b)._forbidding_rule("crowd") != ""
			return (not a_refuses and b_refuses) or (a_refuses == b_refuses and a < b))
		if aggrieved.size() >= need and aggrieved.size() > best.get("aggrieved", []).size():
			best = {"target": target, "aggrieved": aggrieved, "protectors": protectors,
				"location": director.get_npc_location(target), "area": t[1]}
	return best

## Thresholds per dimension on the NPC's feelings toward the player, all of which must hold
func _hostile_to_player(key: String, thresholds) -> bool:
	if not thresholds is Dictionary or thresholds.is_empty():
		return false
	var dims: Dictionary = director.get_relationship_dims(key)
	for dim in thresholds:
		if str(dim) not in DIMENSIONS or not thresholds[dim] is Dictionary or not _threshold(float(dims.get(dim, 0.0)), thresholds[dim]):
			return false
	return true

func _player_hostility(key: String) -> float:
	var dims: Dictionary = director.get_relationship_dims(key)
	return -float(dims.get("trust", 0.0)) - float(dims.get("affection", 0.0))

## Does a player event match a trigger's "event" part? kind / status / truth (a value or a list),
## about (any overlap; npc keys, npc_ids or faction:<id>), min_fidelity
func event_matches(spec: Dictionary, ev: Dictionary) -> bool:
	for field in ["kind", "status", "truth", "skill"]:
		if spec.has(field):
			var wanted = spec[field]
			var values: Array = wanted if wanted is Array else [wanted]
			if str(ev.get(field, "")) not in values.map(func(v): return str(v)):
				return false
	for field in ["victim_minor", "self_defence"]:  # violence marks (PlayerEvents), false when absent
		if spec.has(field) and bool(ev.get(field, false)) != bool(spec[field]):
			return false
	if spec.has("about"):
		var wanted = spec.about if spec.about is Array else [spec.about]
		var about: Array = _event_keys(ev.get("about", []))
		var hit = false
		for w in wanted:
			if _about_hit(str(w), about):
				hit = true
		if not hit:
			return false
	if spec.has("tone"):
		var tones: Array = _as_list(spec.tone).map(func(v): return str(v))
		if str(ev.get("tone", "")) not in tones:
			return false
	if spec.has("location"):
		var places: Array = _as_list(spec.location).map(func(v): return str(v))
		if str(ev.get("location", "")) not in places:
			return false
	if spec.has("region"):
		var registry = director._registry()
		var region = registry.get_region(str(ev.get("location", ""))) if registry and str(ev.get("location", "")) != "" else ""
		if region not in _as_list(spec.region).map(func(v): return str(v)):
			return false
	return true

## min_count (at least N matching events, this one included) and first (this is the first one)
func _count_holds(spec: Dictionary, ev: Dictionary) -> bool:
	if not spec.has("min_count") and spec.get("first", false) != true:
		return true
	var base: Dictionary = spec.duplicate()
	base.erase("min_count")
	base.erase("first")
	var count = 0
	var earlier = 0
	for other in _known_events(ev):
		if event_matches(base, other):
			count += 1
			if str(other.get("id", "")) != str(ev.get("id", "")) and int(other.get("minute", 0)) <= int(ev.get("minute", 0)):
				earlier += 1
	if spec.has("min_count") and count < int(spec.min_count):
		return false
	if spec.get("first", false) == true and earlier > 0:
		return false
	return true

## Every player event known: PlayerEvents.events_matching({}) when it answers, plus those seen via signals
func _known_events(current: Dictionary) -> Array:
	var by_id: Dictionary = {}
	var player_events = director.get_player_events()
	if player_events and player_events.has_method("events_matching"):
		var all = player_events.events_matching({})
		for ev in all if all is Array else []:
			if ev is Dictionary and str(ev.get("id", "")) != "":
				by_id[str(ev.id)] = ev
	for id in events_seen:
		if not by_id.has(id):
			by_id[id] = events_seen[id]
	if str(current.get("id", "")) != "":
		by_id[str(current.id)] = current
	return by_id.values()

## An event-about entry: npc key/id, faction:<id> or archetype:<id> (generic instances of it)
func _about_hit(want: String, about: Array) -> bool:
	if want.begins_with("faction:"):
		var members = faction_members(want.substr(8))
		return about.any(func(k): return k in members)
	if want.begins_with("archetype:"):
		var arch = want.substr(10)
		var generics = director.get_generics()
		for key in about:
			var inst = generics.get_instance(key) if generics and generics.has_method("get_instance") else null
			if inst and str(inst.archetype_id) == arch:
				return true
		return false
	return director._npc_key(want) in about

## Reputation, relationship and flag parts of a trigger. Returns {"ok", "matches": [npc keys]}:
## matches are the NPCs a relationship (npc "any") or npc reputation part matched (role from: trigger_match)
func _conditions(trigger: Dictionary) -> Dictionary:
	var matches: Array = []
	var crowd_event: Dictionary = {}
	if trigger.get("crowd") is Dictionary:
		_crowd = _crowd_condition(trigger.crowd)
		if _crowd.is_empty():
			return {"ok": false, "matches": []}
		matches.append_array(_crowd.aggrieved)
		var target_name = director.get_player_name() if _crowd.target == "player" else director.get_display_name(_crowd.target)
		# A crowd gathers again against the same person only when someone new joins the grievance: the
		# same people with nothing new do not. Cooldown and max_active cap it as for any template
		var before: Array = crowd_members.get(_crowd.target, [])
		var newcomers: Array = _crowd.aggrieved.filter(func(k): return not k in before)
		if newcomers.is_empty():
			return {"ok": false, "matches": []}
		newcomers.sort()
		crowd_event = {"id": "crowd:%s:%s" % [_crowd.target, ",".join(newcomers)], "kind": "crowd",
			"summary": "%d people in %s with a grievance against %s" % [_crowd.aggrieved.size(), _crowd.area, target_name],
			"about": [] if _crowd.target == "player" else [_crowd.target], "location": str(_crowd.location)}
	var flags: Array = []
	if trigger.get("flags") is Array:
		flags.append_array(trigger.flags)
	if trigger.get("flag") is String:
		flags.append(trigger.flag)
	if not flags.is_empty() and not director._requirements_hold(flags):
		return {"ok": false, "matches": []}
	for part in _as_list(trigger.get("reputation")):
		if not part is Dictionary:
			return {"ok": false, "matches": []}
		var scope = ""
		for s in ["npc", "faction", "region"]:
			if part.has(s):
				scope = s
		if scope == "":
			return {"ok": false, "matches": []}
		var value = director.get_reputation(scope, str(part[scope]))
		if not _threshold(value, part):
			return {"ok": false, "matches": []}
		if scope == "npc":
			matches.append(director._npc_key(str(part.npc)))
	for part in _as_list(trigger.get("relationship")):
		if not part is Dictionary or str(part.get("dimension", "")) not in DIMENSIONS:
			return {"ok": false, "matches": []}
		var who = str(part.get("npc", "any"))
		var keys: Array = director.get_soul_keys() if who == "any" else [director._npc_key(who)]
		keys.sort()
		var hits: Array = []
		for key in keys:
			if director._is_npc_alive(key) and _threshold(float(director.get_relationship_dims(key).get(part.dimension, 0.0)), part):
				hits.append(key)
		if hits.is_empty():
			return {"ok": false, "matches": []}
		for key in hits:
			if key not in matches:
				matches.append(key)
	return {"ok": true, "matches": matches, "event": crowd_event}

func _threshold(value: float, part: Dictionary) -> bool:
	if part.has("below") and not value < float(part.below):
		return false
	if part.has("above") and not value > float(part.above):
		return false
	if part.has("at_least") and not value >= float(part.at_least):
		return false
	if part.has("at_most") and not value <= float(part.at_most):
		return false
	return true

func _as_list(value) -> Array:
	if value == null:
		return []
	return value if value is Array else [value]

## Boosted by the player's intentions first (InnerVoice), then file order
func _templates_by_priority() -> Array:
	var ids: Array = template_order.duplicate()
	var voice = director.get_inner_voice()
	if voice == null or not voice.has_active_intentions():
		return ids
	var scores: Dictionary = {}
	for tid in ids:
		var t: Dictionary = templates[tid]
		var text = str(t.title) + " " + str(t.get("summary", ""))
		for hook in t.hooks:
			text += " " + str(hook.get("situation", ""))
		scores[tid] = voice.score_target({"template": tid, "text": text})
	var index: Dictionary = {}
	for i in ids.size():
		index[ids[i]] = i
	ids.sort_custom(func(a, b):
		if not is_equal_approx(scores[a], scores[b]):
			return scores[a] > scores[b]
		return index[a] < index[b])
	return ids

# =============================================================================
# INSTANTIATION
# =============================================================================

## Why a template cannot instantiate now ("" when it can)
func get_block_reason(template_id: String, event_id: String = "") -> String:
	var t: Dictionary = templates.get(template_id, {})
	if t.is_empty():
		return "unknown template '%s'" % template_id
	if event_id != "" and seen.has("%s|%s" % [template_id, event_id]):
		return "already grew from %s" % event_id
	if count_active(template_id) >= int(t.max_active):
		return "max_active %d reached" % int(t.max_active)
	if template_last.has(template_id) and director._now() - int(template_last[template_id]) < int(float(t.cooldown_days) * MINUTES_PER_DAY):
		return "cooling down (%.1f days)" % float(t.cooldown_days)
	return ""

func count_active(template_id: String) -> int:
	var n = 0
	for iid in instance_order:
		if instances[iid].template == template_id and instances[iid].status == "active":
			n += 1
	return n

## Instantiate now if cooldown, max_active and roles allow. Returns the instance ({} when it did not)
func try_instantiate(template_id: String, ev: Dictionary = {}, matches: Array = []) -> Dictionary:
	var event_id = str(ev.get("id", ""))
	if get_block_reason(template_id, event_id) != "":
		return {}
	var t: Dictionary = templates[template_id]
	var roles = bind_roles(t, ev, matches)
	if roles.is_empty() and not t.roles.is_empty():
		return {}
	seq += 1
	var now = director._now()
	var expires = int(float(t.expires_days) * MINUTES_PER_DAY) if float(t.expires_days) > 0.0 else -1
	var inst = {
		"id": "em_%d" % seq,
		"template": template_id,
		"roles": roles,
		"event_id": event_id,
		"event": {"id": event_id, "kind": str(ev.get("kind", "")), "summary": str(ev.get("summary", "")),
			"about": _event_keys(ev.get("about", [])), "location": str(ev.get("location", ""))},
		"opened_minute": now,
		"opened_round": director.get_round(),
		"expires_minute": now + expires if expires >= 0 else -1,
		"status": "active",
		"outcome": "",
		"closed_minute": -1,
		"hook_acts": {},
	}
	inst["title"] = subst(str(t.title), inst, false)
	inst["location"] = subst(str(t.get("location", "")), inst, true)
	var resolves: Array = []
	for cond in t.resolves_on:
		resolves.append(subst(str(cond), inst, true))
	inst["resolves_on"] = resolves
	instances[inst.id] = inst
	instance_order.append(inst.id)
	if str(ev.get("kind", "")) == "crowd" and not _crowd.is_empty():
		var known: Array = crowd_members.get(_crowd.target, [])
		for k in _crowd.aggrieved:
			if not k in known:
				known.append(k)
		crowd_members[_crowd.target] = known
	template_last[template_id] = now
	if event_id != "":
		seen["%s|%s" % [template_id, event_id]] = true
	var bound: Array = roles.keys().map(func(r): return "%s=%s" % [r, roles[r]])
	print("[Emergence] %s grew from %s: %s (%s)" % [inst.id, template_id if event_id == "" else "%s/%s" % [template_id, event_id], inst.title, ", ".join(bound)])
	var memory = subst(str(t.get("memory", "")), inst, false)
	if memory == "":
		memory = "%s: %s" % [inst.title, inst.event.summary] if inst.event.summary != "" else inst.title
	director.record_emergent(inst, "instantiated", "", [], [], memory, roles.values())
	director.emergent_opened.emit(inst.duplicate(true))
	_enqueue_hooks(inst, "on_open")
	for hook in t.hooks:
		var trigger = str(hook.get("trigger", "on_open"))
		if trigger.begins_with("on_flag:") and director._flag(trigger.substr(8)):
			director.enqueue_external(PREFIX + inst.id, inst.id, str(hook.id), trigger)
	return inst

## Bind every role to a real NPC. Returns role -> npc key ({} when a required role finds nobody)
func bind_roles(t: Dictionary, ev: Dictionary, matches: Array) -> Dictionary:
	var bound: Dictionary = {}
	for role in t.roles:
		var spec: Dictionary = t.roles[role]
		var candidates: Array = []
		for key in role_candidates(spec, ev, matches):
			if key in bound.values() or key in candidates:
				continue
			if not director.has_soul(key) or not director._is_npc_alive(key):
				continue
			if spec.get("tiers") is Array and director.get_soul_tier(key) not in spec.tiers:
				continue
			if spec.get("exclude") is Array and key in spec.exclude.map(func(x): return director._npc_key(str(x))):
				continue
			if spec.has("faction") and key not in faction_members(str(spec.faction)):
				continue
			if spec.has("region"):
				var registry = director._registry()
				var region = registry.get_region(director.get_npc_location(key)) if registry else ""
				if region not in _as_list(spec.region).map(func(v): return str(v)):
					continue
			if spec.get("knows_of_player", false) == true and not knows_of_player(key):
				continue
			# near_event: region | area: only those who are now where the deed was done (rangers where they ride)
			if spec.has("near_event") and not _near_event(key, str(spec.near_event), ev):
				continue
			# Fidelity is per hearer (PlayerEvents heard_by[who].fidelity; witnesses know it at 1.0)
			if spec.has("min_fidelity") and str(ev.get("id", "")) != "" and _fidelity_for(str(ev.id), key) < float(spec.min_fidelity):
				continue
			candidates.append(key)
		if candidates.is_empty():
			if spec.get("optional", false) == true:
				continue
			return {}
		bound[role] = _prefer(candidates, str(spec.get("prefer", "")), ev)[0]
	return bound

func _near_event(key: String, scope: String, ev: Dictionary) -> bool:
	var registry = director._registry()
	var at = str(ev.get("location", ""))
	var here = director.get_npc_location(key)
	if registry == null or not _has_location(at) or not _has_location(here):
		return false
	if scope == "area":
		return registry.get_area(here) == registry.get_area(at)
	return registry.get_region(here) == registry.get_region(at)

## Who could fill a role, from one source or a list of them (keys, sorted for determinism)
func role_candidates(spec: Dictionary, ev: Dictionary, matches: Array) -> Array:
	var out: Array = []
	for source in _as_list(spec.get("from")):
		var src = str(source)
		var keys: Array = []
		if src == "event_witness":
			keys = _event_keys(ev.get("witnesses", []))
		elif src == "event_about":
			keys = _event_keys(ev.get("about", []))
		elif src == "heard_event":
			var heard = ev.get("heard_by", {})
			keys = _event_keys(heard.keys() if heard is Dictionary else heard)
		elif src == "trigger_match":
			keys = matches.duplicate()
		elif src == "crowd_target":
			keys = [_crowd.target] if _crowd.get("target", "player") != "player" else []
		elif src == "crowd_aggrieved":
			keys = _crowd.get("aggrieved", []).duplicate()
		elif src == "crowd_protector":
			keys = _crowd.get("protectors", []).duplicate()
		elif src == "near_player":
			keys = near_player()
		elif src == "near_event":
			keys = near_event(ev)
		elif src.begins_with("faction:"):
			keys = faction_members(src.substr(8))
		elif src.begins_with("archetype:"):
			keys = archetype_members(src.substr(10))
		elif src.begins_with("npc:"):
			keys = [director._npc_key(src.substr(4))]
		if src != "crowd_aggrieved":
			keys.sort()
		for key in keys:
			if key not in out:
				out.append(key)
	return out

## prefer: <dimension>_asc | <dimension>_desc (feelings toward the player), nearest (to the event, else
## the player), or "" (source order). Stable: ties keep the candidate order
func _prefer(candidates: Array, prefer: String, ev: Dictionary) -> Array:
	if prefer == "" or candidates.size() < 2:
		return candidates
	var scores: Dictionary = {}
	var ascending = true
	if prefer == "nearest":
		var origin = str(ev.get("location", ""))
		if origin == "" or not _has_location(origin):
			origin = director.get_player_location()
		for key in candidates:
			var here = director.get_npc_location(key)
			var minutes = 0 if here == origin else (director._minutes_between(origin, here) if _has_location(here) and _has_location(origin) else -1)
			scores[key] = float(minutes) if minutes >= 0 else 1.0e9
	else:
		var parts = prefer.rsplit("_", true, 1)
		if parts.size() != 2 or parts[0] not in DIMENSIONS or parts[1] not in ["asc", "desc"]:
			return candidates
		ascending = parts[1] == "asc"
		for key in candidates:
			scores[key] = float(director.get_relationship_dims(key).get(parts[0], 0.0))
	var index: Dictionary = {}
	for i in candidates.size():
		index[candidates[i]] = i
	var sorted = candidates.duplicate()
	sorted.sort_custom(func(a, b):
		if not is_equal_approx(scores[a], scores[b]):
			return scores[a] < scores[b] if ascending else scores[a] > scores[b]
		return index[a] < index[b])
	return sorted

func _has_location(location: String) -> bool:
	var registry = director._registry()
	return registry != null and location != "" and registry.has_location(location)

func _fidelity_for(event_id: String, key: String) -> float:
	var player_events = director.get_player_events()
	if player_events and player_events.has_method("fidelity_for"):
		return float(player_events.fidelity_for(event_id, key))
	return 1.0

## Has this NPC heard anything of the player (PlayerEvents.known_by), or met them?
func knows_of_player(key: String) -> bool:
	var player_events = director.get_player_events()
	if player_events and player_events.has_method("known_by"):
		var known = player_events.known_by(key)
		if (known is Array or known is Dictionary) and not known.is_empty():
			return true
	if player_events and player_events.has_method("known_by"):
		var by_id = player_events.known_by(director._npc_id(key))
		if (by_id is Array or by_id is Dictionary) and not by_id.is_empty():
			return true
	var dims = director.get_relationship_dims(key)
	return float(dims.get("familiarity", 0.0)) > 0.0

## Souls standing where the player is (not travelling)
func near_player() -> Array:
	var here = director.get_player_location()
	var keys: Array = []
	if here == "":
		return keys
	for key in director.get_soul_keys():
		if director.get_npc_location(key) == here and not director.is_npc_travelling(key):
			keys.append(key)
	return keys

## Souls standing where the event happened (not travelling): whoever could come upon what it left,
## a pack where the player fell, after the player is gone. Falls back to near_player without a place
func near_event(ev: Dictionary) -> Array:
	var where = str(ev.get("location", ""))
	if where == "":
		return near_player()
	var keys: Array = []
	for key in director.get_soul_keys():
		if director.get_npc_location(key) == where and not director.is_npc_travelling(key):
			keys.append(key)
	return keys

## Who a faction reckons as its own now: Reputation.faction_members (hidden members under cover,
## archetype generics of the faction's region) when available, else world.json members plus
## registered generic souls of the faction's archetypes
func faction_members(faction_id: String) -> Array:
	var rep = director.get_reputation_script()
	if rep != null:
		var keys: Array = []
		for who in rep.faction_members(faction_id):
			var key = director._npc_key(str(who))
			if key not in keys:
				keys.append(key)
		return keys
	var registry = director._registry()
	var world = registry.data if registry and "data" in registry and registry.data is Dictionary else {}
	var members: Array = []
	var archetypes: Array = []
	for faction in world.get("factions", []):
		if faction is Dictionary and str(faction.get("id", "")) == faction_id:
			for key in faction.get("members", []):
				members.append(str(key))
			for arch in faction.get("archetypes", []):
				archetypes.append(str(arch))
	if not archetypes.is_empty():
		var generics = director.get_generics()
		for key in director.get_registered_souls():
			var inst = generics.get_instance(key) if generics and generics.has_method("get_instance") else null
			if inst and str(inst.archetype_id) in archetypes and key not in members:
				members.append(key)
	return members

## Registered generic souls of one archetype (garrison soldiers wherever they are posted)
func archetype_members(archetype_id: String) -> Array:
	var out: Array = []
	var generics = director.get_generics()
	if generics == null or not generics.has_method("get_instance"):
		return out
	for key in director.get_registered_souls():
		var inst = generics.get_instance(key)
		if inst and str(inst.archetype_id) == archetype_id:
			out.append(key)
	return out

## npc keys from npc ids / keys (skips the player and anything that is not an NPC with a soul or roster entry)
func _event_keys(raw) -> Array:
	var keys: Array = []
	for item in raw if raw is Array else []:
		var text = str(item)
		if text == "" or text == "player":
			continue
		var key = director._npc_key(text)
		if (director.has_soul(key) or (director._registry() and director._registry().has_npc(key))) and key not in keys:
			keys.append(key)
	return keys

# =============================================================================
# SLOTS
# =============================================================================

## Fill {role}, {role.key}, {role.name}, {role.home}, {role.location}, {event.summary}, {event.id},
## {event.kind}, {event.location}, {player}. ident = true fills {role} with the npc key (effect fields),
## false with the display name (text). Unknown slots stay as written
func subst(text: String, inst: Dictionary, ident: bool) -> String:
	if not "{" in text:
		return text
	var re = RegEx.create_from_string("\\{([A-Za-z0-9_]+)(?:\\.([A-Za-z_]+))?\\}")
	var out = ""
	var last = 0
	for m in re.search_all(text):
		out += text.substr(last, m.get_start() - last)
		last = m.get_end()
		out += _slot(m.get_string(1), m.get_string(2), inst, ident, m.get_string(0))
	return out + text.substr(last)

func _slot(name: String, field: String, inst: Dictionary, ident: bool, raw: String) -> String:
	if name == "player":
		return director.get_player_name()
	if name == "event":
		var ev: Dictionary = inst.get("event", {})
		match field:
			"summary":
				return str(ev.get("summary", ""))
			"id":
				return str(ev.get("id", ""))
			"kind":
				return str(ev.get("kind", ""))
			"location":
				return str(ev.get("location", ""))
		return raw
	var roles: Dictionary = inst.get("roles", {})
	if not roles.has(name):
		return raw
	var key = str(roles[name])
	match field:
		"":
			return key if ident else director.get_display_name(key)
		"key", "id":
			return key if field == "key" else director._npc_id(key)
		"name":
			return director.get_display_name(key)
		"home":
			return director.get_npc_home(key)
		"location":
			return director.get_npc_location(key)
	return raw

## A template hook with every slot filled, eligible = bound role keys
func resolved_hook(inst: Dictionary, hook_id: String) -> Dictionary:
	var t: Dictionary = templates.get(str(inst.template), {})
	for hook in t.get("hooks", []):
		if str(hook.id) != hook_id:
			continue
		var eligible: Array = []
		for role in _hook_roles(hook):
			if inst.roles.has(role) and str(inst.roles[role]) not in eligible:
				eligible.append(str(inst.roles[role]))
		var options: Array = []
		for option in hook.options:
			var effects: Array = []
			for effect in option.get("effects", []):
				effects.append(_subst_effect(effect, inst))
			var copy = {"id": str(option.id), "label": subst(str(option.get("label", option.id)), inst, false),
				"appeal": option.get("appeal", {}) if option.get("appeal") is Dictionary else {}, "effects": effects, "serves": []}
			if option.has("aids"):
				copy["aids"] = subst(str(option.aids), inst, true)
			if option.has("harms"):
				copy["harms"] = _as_list(option.harms).map(func(h): return subst(str(h), inst, true))
			if option.get("crowd", false) == true:
				copy["crowd"] = true
			# Engine rule (docs/PLAYER_SYSTEMS.md §1.4): no NPC harms a child, whatever its soul would choose
			if copy.get("harms", []).any(func(h): return _is_minor(str(h))):
				continue
			options.append(copy)
		return {"id": hook_id, "type": str(hook.get("type", "react")), "trigger": str(hook.get("trigger", "on_open")),
			"eligible": eligible, "situation": subst(str(hook.get("situation", "")), inst, false), "options": options,
			"once": hook.get("once", true), "stack": hook.get("stack", false)}
	return {}

func _is_minor(key: String) -> bool:
	var registry = director._registry() if director else null
	return key != "" and registry != null and registry.has_method("is_minor") and registry.is_minor(key)

func _subst_effect(effect, inst: Dictionary):
	if not effect is Dictionary:
		return effect
	var e: Dictionary = {}
	for field in effect:
		var value = effect[field]
		if value is String:
			e[field] = subst(value, inst, field in IDENT_FIELDS)
		elif value is Array:
			e[field] = value.map(func(v): return subst(v, inst, true) if v is String else v)
		else:
			e[field] = value
	return e

# =============================================================================
# DECISIONS (StorylineDirector.advance_round calls decide for "emergent:" queue items)
# =============================================================================

func owns(storyline_id: String) -> bool:
	return storyline_id.begins_with(PREFIX)

func _enqueue_hooks(inst: Dictionary, trigger: String) -> void:
	var t: Dictionary = templates.get(str(inst.template), {})
	for hook in t.get("hooks", []):
		if str(hook.get("trigger", "on_open")) == trigger:
			if hook.get("once", true) != false and inst.hook_acts.has(str(hook.id)):
				continue
			director.enqueue_external(PREFIX + inst.id, inst.id, str(hook.id), trigger)

## Idle hooks of every active instance, once per round
func enqueue_idle_hooks() -> void:
	for iid in instance_order:
		if instances[iid].status == "active":
			_enqueue_hooks(instances[iid], "idle")

## A flag turned true: on_flag hooks of active instances queue, and flag resolutions are checked
func on_flag(flag_name: String) -> void:
	for iid in instance_order:
		if instances[iid].status == "active":
			_enqueue_hooks(instances[iid], "on_flag:" + flag_name)
	check_resolutions()

## Offer one queued hook to its bound NPCs. Returns the chronicle entries made ([] when stale)
func decide(item: Dictionary) -> Array:
	var inst: Dictionary = instances.get(str(item.get("beat", "")), {})
	if inst.is_empty():
		return []
	var trigger = str(item.get("trigger", ""))
	if inst.status != "active" and trigger != "on_resolve":
		return []
	var hook = resolved_hook(inst, str(item.hook))
	if hook.is_empty():
		return []
	if hook.once != false and inst.hook_acts.has(hook.id):
		return []
	var entries: Array = []
	for key in hook.eligible:
		if not director._is_npc_alive(key):
			continue
		director.hook_offered.emit(PREFIX + inst.id, hook.id, key)
		var soul = director.get_soul(key)
		var decision = await decide_one(soul, key, hook, inst)
		var entry = carry_out(inst, hook, trigger, key, soul, decision)
		entries.append(entry)
		if entry.choice != "pass":
			inst.hook_acts[hook.id] = int(inst.hook_acts.get(hook.id, 0)) + 1
			if hook.stack != true:
				break
	return entries

## Hook type whose Agency grants apply: the hook's own when the soul engages it, else converse
## (generics and promoted NPCs act through converse: only)
func effective_type(soul, hook: Dictionary) -> String:
	return str(hook.type) if soul and soul.engages(str(hook.type)) else "converse"

## Claude mode chooses as at any hook (falling back to appeal); offline uses appeal
func decide_one(soul, key: String, hook: Dictionary, inst: Dictionary) -> Dictionary:
	if soul == null:
		return {"choice": "pass", "option": {}, "effects": [], "reason": "no soul for this NPC", "mode": "offline", "fallback_reason": ""}
	var offline = choose_by_appeal(soul, key, hook)
	if director.agency_mode != "claude":
		return offline
	var agent = director.get_agent()
	agent.mode = "claude"
	agent.client = director.get_claude_client_for_agents()
	var etype = effective_type(soul, hook)
	if not soul.engages(etype):
		return offline.merged({"mode": "claude_fallback", "fallback_reason": "soul has no Agency for %s" % hook.type}, true)
	var ask = hook.duplicate(true)
	ask["type"] = etype
	ask.erase("allow_freeform")
	var decision = await agent.decide(soul, ask, {"storyline_title": str(inst.title), "beat_title": ""})
	if str(decision.get("mode", "")) == "claude":
		return decision
	return offline.merged({"mode": "claude_fallback", "fallback_reason": str(decision.get("fallback_reason", "offline"))}, true)

## The offline chooser: appeal = Σ coefficient × the NPC's feeling toward the player (-100..100) over the
## option's appeal dimensions. Options the soul's Lines refuse, or with any effect its Agency (or the
## emergent scope) denies, are skipped. Highest appeal wins; ties go to the earlier option; none = pass
func choose_by_appeal(soul, key: String, hook: Dictionary) -> Dictionary:
	var dims: Dictionary = director.get_relationship_dims(key)
	var etype = effective_type(soul, hook)
	var best: Dictionary = {}
	var best_score = -INF
	var notes: Array = []
	for option in hook.options:
		if soul.get_option_denial_reason(option) != "":
			continue
		var permitted = true
		for effect in option.get("effects", []):
			if effect_denial(soul, key, etype, effect) != "":
				permitted = false
				break
		if not permitted:
			continue
		var score = appeal_score(option.get("appeal", {}), dims)
		notes.append("%s %.1f" % [option.id, score])
		if score > best_score:
			best_score = score
			best = option
	if best.is_empty():
		return {"choice": "pass", "option": {}, "effects": [], "reason": "no option this soul permits", "mode": "offline", "fallback_reason": ""}
	return {"choice": str(best.id), "option": best, "effects": best.get("effects", []).duplicate(true),
		"reason": "appeal %.1f (%s)" % [best_score, ", ".join(notes)], "mode": "offline", "fallback_reason": ""}

static func appeal_score(appeal: Dictionary, dims: Dictionary) -> float:
	var score = 0.0
	for dim in appeal:
		if str(dim) in DIMENSIONS and (appeal[dim] is float or appeal[dim] is int):
			score += float(appeal[dim]) * float(dims.get(str(dim), 0.0))
	return score

## Why this NPC may not cause this effect in an emergent beat ("" when it may):
## vocabulary; personal scope + spread_event + shift_fixed_point only, never a storyline change;
## shift_want only its own wants; rumors only of true flags; shift_fixed_point only for main souls;
## the soul's Agency for the effective hook type and its Lines (generic souls: Lines only, see below)
func effect_denial(soul, key: String, hook_type: String, raw) -> String:
	if not raw is Dictionary:
		return "vocabulary: an effect must be an object"
	var e: Dictionary = raw
	var etype = str(e.get("type", ""))
	if etype in STORY_ONLY:
		return "emergent beats never change storylines (%s)" % etype
	if etype not in PERSONAL_EFFECTS and etype not in EXTRA_EFFECTS:
		return "%s is not an emergent effect" % etype
	var checked = director._effects.validate(e)
	if not checked.ok:
		return "vocabulary: " + str(checked.reason)
	e = checked.effect
	if etype == "shift_want" and director._npc_key(str(e.npc)) != key:
		return "personal scope: shift_want only on its own wants"
	if etype == "spread_rumor" and not director._flag(str(e.flag)):
		return "truth: '%s' is not true; rumors carry only what happened" % e.flag
	if etype == "shift_fixed_point" and director.get_soul_tier(key) != "main":
		return "%s souls act at personal scope only (no shift_fixed_point)" % director.get_soul_tier(key)
	# Lead ruling: a generic soul may use every emergent effect but shift_fixed_point whatever its
	# converse line says (gossip is what generics do); its Lines still apply. Main and promoted souls
	# use their normal Agency for the hook type
	if director.get_soul_tier(key) == "generic":
		var rule = soul._forbidding_rule("hook:" + hook_type)
		if rule != "":
			return "line 'hook:%s': %s" % [hook_type, rule]
		return soul._effect_line_denial(e)
	return _grant_denial(soul, hook_type, e)

func _grant_denial(soul, hook_type: String, e: Dictionary) -> String:
	if hook_type != "converse":
		return soul.get_denial_reason(hook_type, e)
	return soul.get_converse_denial_reason(e)

## Re-check and apply a decision's effects, chronicle it (mode "emergent"), and make it the NPC's memory
func carry_out(inst: Dictionary, hook: Dictionary, trigger: String, key: String, soul, decision: Dictionary) -> Dictionary:
	var applied: Array = []
	var dropped: Array = []
	var choice = str(decision.get("choice", "pass"))
	var etype = effective_type(soul, hook)
	var option_denial = soul.get_option_denial_reason(decision.option) if soul and not decision.get("option", {}).is_empty() else ""
	var index = 0
	for raw in decision.get("effects", []):
		index += 1
		if index > ACTION_BUDGET:
			dropped.append({"effect": raw, "reason": "budget: at most %d effects" % ACTION_BUDGET})
			continue
		var denial = option_denial
		if denial == "":
			denial = effect_denial(soul, key, etype, raw) if soul else "no soul for this NPC"
		if denial != "":
			dropped.append({"effect": raw, "reason": denial})
			continue
		var e: Dictionary = director._effects.validate(raw).effect
		if str(e.get("type", "")) in ["agenda", "move_npc", "adjust_relationship", "shift_want"] and str(e.get("npc", "")) == "":
			e["npc"] = key
		# Grown from a player event: the player is in this effect's causal chain
		var result = director._apply_effect_as_director(e, key, {"emergent": inst.id, "template": inst.template, "hook": hook.id,
			"player_chain": str(inst.get("event_id", "")) != ""})
		if result.ok:
			applied.append(e)
		else:
			dropped.append({"effect": e, "reason": result.reason})
	var label = str(decision.get("option", {}).get("label", ""))
	var memory = ""
	if choice != "pass":
		memory = "%s chose: %s (%s)" % [director.get_display_name(key), label if label != "" else "acted on their own", inst.title]
	var entry = director.record_emergent(inst, choice, hook.id, applied, dropped, memory, [key],
		{"npc": key, "trigger": trigger, "hook_type": str(hook.type), "label": label, "reason": str(decision.get("reason", "")),
		 "agent_mode": str(decision.get("mode", "offline")), "fallback_reason": str(decision.get("fallback_reason", ""))})
	return entry

# =============================================================================
# RESOLUTION
# =============================================================================

## Close instances whose resolves_on holds: talked_to:<role|key> (the conversation that just ended),
## days:<n> since it opened, a flag (! allowed); expiry closes it as "expired" whatever resolves_on says
func check_resolutions(talked_to: String = "") -> Array:
	var closed: Array = []
	var now = director._now()
	for iid in instance_order.duplicate():
		var inst: Dictionary = instances[iid]
		if inst.status != "active":
			continue
		var outcome = ""
		for raw in inst.resolves_on:
			var cond = str(raw)
			if cond.begins_with("talked_to:"):
				var who = cond.substr(10)
				var key = str(inst.roles.get(who, director._npc_key(who)))
				if talked_to != "" and key == talked_to:
					outcome = "talked_to:" + key
			elif cond.begins_with("days:"):
				if now >= int(inst.opened_minute) + int(float(cond.substr(5)) * MINUTES_PER_DAY):
					outcome = cond
			elif cond == "expired":
				continue
			elif cond != "" and director._requirements_hold([cond]):
				outcome = cond
			if outcome != "":
				break
		if outcome == "" and int(inst.expires_minute) >= 0 and now >= int(inst.expires_minute):
			outcome = "expired"
		if outcome != "":
			close(inst, outcome)
			closed.append(inst)
	return closed

func close(inst: Dictionary, outcome: String) -> void:
	inst["status"] = "expired" if outcome == "expired" else "resolved"
	inst["outcome"] = outcome
	inst["closed_minute"] = director._now()
	print("[Emergence] %s %s (%s)" % [inst.id, inst.status, outcome])
	director.record_emergent(inst, inst.status, "", [], [], "", [], {"reason": outcome})
	director.emergent_closed.emit(inst.duplicate(true))
	_enqueue_hooks(inst, "on_resolve")
	_trim_closed()

func _trim_closed() -> void:
	var closed: Array = instance_order.filter(func(iid): return instances[iid].status != "active")
	while closed.size() > MAX_CLOSED_KEPT:
		var oldest = closed.pop_front()
		instance_order.erase(oldest)
		instances.erase(oldest)

# =============================================================================
# QUERIES, SAVE
# =============================================================================

func get_instances(include_closed: bool = true) -> Array:
	var out: Array = []
	for iid in instance_order:
		if include_closed or instances[iid].status == "active":
			out.append(instances[iid].duplicate(true))
	return out

## What InnerVoice scores a queued emergent hook against
func priority_target(item: Dictionary) -> Dictionary:
	var inst: Dictionary = instances.get(str(item.get("beat", "")), {})
	if inst.is_empty():
		return {}
	var hook = resolved_hook(inst, str(item.hook))
	var text = str(inst.title) + " " + str(hook.get("situation", ""))
	for option in hook.get("options", []):
		text += " " + str(option.get("label", ""))
	return {"npcs": hook.get("eligible", []), "template": str(inst.template), "text": text}

func reset() -> void:
	instances.clear()
	instance_order.clear()
	seq = 0
	template_last.clear()
	seen.clear()
	events_seen.clear()
	crowd_members.clear()

func save() -> Dictionary:
	return {"instances": instances.duplicate(true), "order": instance_order.duplicate(), "seq": seq,
		"template_last": template_last.duplicate(), "seen": seen.keys(), "events_seen": events_seen.duplicate(true),
		"crowd_members": crowd_members.duplicate(true)}

func load_from_dict(data: Dictionary) -> void:
	reset()
	if not data is Dictionary:
		return
	var saved: Dictionary = data.get("instances", {}) if data.get("instances") is Dictionary else {}
	for iid in data.get("order", []):
		if not saved.has(iid) or not saved[iid] is Dictionary:
			continue
		var inst: Dictionary = saved[iid].duplicate(true)
		for field in ["opened_minute", "opened_round", "expires_minute", "closed_minute"]:
			inst[field] = int(inst.get(field, -1))
		var acts: Dictionary = {}
		for hook_id in inst.get("hook_acts", {}):
			acts[hook_id] = int(inst.hook_acts[hook_id])
		inst["hook_acts"] = acts
		instances[str(iid)] = inst
		instance_order.append(str(iid))
	seq = int(data.get("seq", instance_order.size()))
	for tid in data.get("template_last", {}):
		template_last[str(tid)] = int(data.template_last[tid])
	for k in data.get("seen", []):
		seen[str(k)] = true
	if data.get("events_seen") is Dictionary:
		events_seen = data.events_seen.duplicate(true)
	if data.get("crowd_members") is Dictionary:
		crowd_members = data.crowd_members.duplicate(true)
