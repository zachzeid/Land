extends RefCounted
# GenericSoulBuilder - Turns an archetype + instance seed (+ layers) into SOUL.md text
# - rolled souls (tier generic): archetype base with the seed's name, weights and voice variant
# - promoted souls: a full individual SOUL.md grown from the layers, with a generated ## Life arc
#   from the strongest want in the exact docs/WORLD_SCHEMA.md §8 format
# Every soul is checked by the storyline Soul parser plus a strict §8 Life check before use

const Soul = preload("res://scripts/storyline/soul.gd")
const Archetype = preload("res://scripts/generics/archetype.gd")
const PERSONAL_EFFECTS = ["agenda", "move_npc", "adjust_relationship", "shift_want", "spread_rumor"]

const ARC_RE = "^### Arc: `([a-z0-9_]+)` \\(serves `([A-Za-z0-9_]+)`\\)$"
const STEP_RE = "^- `([a-z0-9_]+)`: (.+?) \\| after: ([a-z0-9_]+|none) \\| needs: (.+?) \\| at: ([a-z0-9_]+|any) \\| takes: ([1-6]) \\| effects: ([a-z_]+(?:, [a-z_]+)*)(?: \\| player: (helps|needed))?$"
const RESULT_RE = "^- result: `([a-z0-9_]+)`: (.+)$"
const FAILS_RE = "^- fails_if: `[^`]+`(?:, `[^`]+`)*$"

## Slots for an instance: name, home (location name), region (region name), id
static func slots_for(inst, ctx: Dictionary) -> Dictionary:
	return {"name": inst.name, "home": ctx.get("home_name", inst.home), "region": ctx.get("region_name", inst.region), "id": inst.id}

static func voice_for(inst, arch) -> String:
	var parts: Array = []
	if arch.voice_shared != "":
		parts.append(arch.voice_shared)
	if not arch.voice_variants.is_empty():
		parts.append(arch.voice_variants[posmod(inst.voice_variant, arch.voice_variants.size())])
	return Archetype.fill_slots(" ".join(parts), slots_for(inst, {})).strip_edges()

## The archetype's Life lines for this instance: {id}_ (and every slot) filled in
static func instance_life_lines(inst, arch, ctx: Dictionary) -> Array:
	var slots = slots_for(inst, ctx)
	var out: Array = []
	for raw in arch.life_lines:
		var line = str(raw).replace("{id}_", inst.id + "_")
		out.append(Archetype.fill_slots(line, slots))
	while not out.is_empty() and str(out[0]).strip_edges() == "":
		out.pop_front()
	while not out.is_empty() and str(out[-1]).strip_edges() == "":
		out.pop_back()
	return out

## Tier generic: archetype base + seed
static func build_rolled_soul(inst, arch, ctx: Dictionary) -> String:
	var slots = slots_for(inst, ctx)
	var t = "# SOUL: %s\nnpc: %s\nnpc_id: %s\n\n" % [inst.name, inst.id, inst.id]
	t += "## Essence\n%s\n\n" % Archetype.fill_slots(arch.essence if arch.essence != "" else "{name} is a %s of {home}." % arch.title.to_lower(), slots)
	t += _wants_block(inst, arch)
	t += _fears_block(arch)
	t += _lines_block(arch)
	t += "## Agency\n- converse: %s\n\n" % ", ".join(arch.converse if not arch.converse.is_empty() else ["agenda", "adjust_relationship"])
	t += "## Voice\n%s\n\n" % voice_for(inst, arch)
	var life = instance_life_lines(inst, arch, ctx)
	if not life.is_empty():
		t += "## Life\n%s\n" % "\n".join(life)
	return t

## Tier promoted: a full individual SOUL.md from the archetype plus the instance's layers
static func build_promoted_soul(inst, arch, ctx: Dictionary, now_minute: int) -> String:
	var slots = slots_for(inst, ctx)
	var t = "# SOUL: %s\nnpc: %s\nnpc_id: %s\n\n" % [inst.name, inst.id, inst.id]
	var essence = Archetype.fill_slots(arch.essence if arch.essence != "" else "{name} is a %s of {home}." % arch.title.to_lower(), slots)
	t += "## Essence\n%s\n\n" % essence
	var lived = inst.top_layers(4, now_minute).filter(func(l): return l.kind != "acquaintance")
	if not lived.is_empty():
		t += "%s is no longer just one of the %s folk of %s. The stranger changed that:\n" % [inst.name, arch.title.to_lower(), slots.home]
		for layer in lived:
			t += "- %s\n" % layer.text
		t += "\n"
	t += _wants_block(inst, arch)
	t += _fears_block(arch)
	t += _lines_block(arch)
	t += "## Agency\n- converse: %s\n\n" % ", ".join(PERSONAL_EFFECTS)
	t += "## Voice\n%s\n\n" % voice_for(inst, arch)
	var secrets = inst.layers.filter(func(l): return l.get("tag", "") == "moment:secret_shared").map(func(l): return l.text)
	if not secrets.is_empty():
		t += "## Secrets\n%s\n\n" % " ".join(secrets)
	t += "## Life\n"
	var life = instance_life_lines(inst, arch, ctx)
	if not life.is_empty():
		t += "\n".join(life) + "\n\n"
	t += "\n".join(build_generated_arc(inst, arch, ctx, life)) + "\n"
	return t

## A personal arc grown from the strongest want (§8 shapes). Its arc id never collides with the
## archetype's arcs, and its result flag starts with the instance id
static func build_generated_arc(inst, arch, ctx: Dictionary, existing_life: Array = []) -> Array:
	var order = inst.wants_by_weight(arch.want_order)
	if order.is_empty():
		return []
	var want_id: String = order[0]
	var text: String = str(arch.wants[want_id].text) if arch.wants.has(want_id) else want_id.replace("_", " ")
	text = Archetype.fill_slots(text, slots_for(inst, ctx)).replace("|", ",").replace("`", "'").strip_edges().trim_suffix(".")
	var goal = text.substr(0, 1).to_lower() + text.substr(1) if text != "" else want_id.replace("_", " ")
	var arc_id = want_id.to_lower() + "_grown"
	var taken = "\n".join(existing_life)
	var n = 2
	while ("`%s`" % arc_id) in taken:
		arc_id = "%s_grown_%d" % [want_id.to_lower(), n]
		n += 1
	var home = inst.home if inst.home != "" else "any"
	return [
		"### Arc: `%s` (serves `%s`)" % [arc_id, want_id],
		"Since the stranger started listening, %s has stopped calling it a daydream: %s. It is time to try." % [inst.name, goal],
		"- `take_stock`: Weigh what it would really cost to %s. | after: none | needs: none | at: %s | takes: 2 | effects: shift_want" % [_as_verb(goal), home],
		"- `tell_the_stranger`: Say it aloud to the stranger who listened. | after: take_stock | needs: none | at: any | takes: 1 | effects: agenda, adjust_relationship | player: helps",
		"- `first_real_step`: Make a real start, whatever the neighbours say. | after: tell_the_stranger | needs: none | at: %s | takes: 3 | effects: agenda, shift_want" % home,
		"- result: `%s_%s_begun`: %s made a real start on what mattered most to them: %s." % [inst.id, arc_id, inst.name, goal],
	]

static func _as_verb(goal: String) -> String:
	# "keep the farm through winter" reads as a verb phrase already; "a cow of her own" does not
	var first = goal.split(" ", false)[0] if goal.split(" ", false).size() > 0 else ""
	if first in ["a", "an", "the", "my", "her", "his", "their", "some", "enough"]:
		return "get " + goal
	return goal

static func _wants_block(inst, arch) -> String:
	var t = "## Wants\n"
	for want_id in arch.want_order:
		if inst.rolled_wants.has(want_id):
			var text = Archetype.fill_slots(str(arch.wants[want_id].text), slots_for(inst, {}))
			t += "- `%s` (%d): %s\n" % [want_id, inst.get_want_weight(want_id), text]
	return t + "\n"

static func _fears_block(arch) -> String:
	if arch.fears.is_empty():
		return ""
	return "## Fears\n%s\n\n" % "\n".join(arch.fears.map(func(f): return "- " + f))

static func _lines_block(arch) -> String:
	if arch.lines.is_empty():
		return ""
	return "## Lines I Will Not Cross\n%s\n\n" % "\n".join(arch.lines)

# =============================================================================
# VALIDATION
# =============================================================================

## Parse with the storyline Soul parser and check the Life section strictly (§8)
## Returns {"ok": bool, "errors": Array, "soul": Soul or null}
static func validate_soul_text(text: String, key: String, require_life_arc: bool = false) -> Dictionary:
	var errors: Array = []
	var soul = Soul.new()
	soul.parse(text)
	if soul.npc_key != key:
		errors.append("npc key '%s' (expected '%s')" % [soul.npc_key, key])
	if soul.wants.is_empty():
		errors.append("no wants parsed")
	for hook_type in soul.agency:
		if hook_type != "converse":
			errors.append("generic souls may only grant converse (found %s)" % hook_type)
		for effect in soul.agency[hook_type]:
			if effect not in PERSONAL_EFFECTS:
				errors.append("converse grants %s (personal scope only)" % effect)
	var life = extract_section(text, "life")
	var life_check = validate_life(life, key, soul.wants.keys())
	errors.append_array(life_check.errors)
	if require_life_arc and life_check.arcs == 0:
		errors.append("no ## Life arc")
	# When the arcs engine's Soul parser reads Life itself, it must accept it and agree on the arc count
	if "life_errors" in soul and soul.get("life_errors") is Array:
		for e in soul.get("life_errors"):
			errors.append("Soul parser: %s" % e)
	for prop in ["arcs", "life_arcs", "life"]:
		if prop in soul and soul.get(prop) is Array and soul.get(prop).size() != life_check.arcs:
			errors.append("Soul parser read %d Life arc(s), strict check %d" % [soul.get(prop).size(), life_check.arcs])
		elif prop in soul and soul.get(prop) is Dictionary and soul.get(prop).size() != life_check.arcs:
			errors.append("Soul parser read %d Life arc(s), strict check %d" % [soul.get(prop).size(), life_check.arcs])
	return {"ok": errors.is_empty(), "errors": errors, "soul": soul, "arcs": life_check.arcs}

## Strict §8 check of a Life section's lines. Returns {"errors": Array, "arcs": int}
static func validate_life(lines: Array, key: String, want_ids: Array) -> Dictionary:
	var arc_re = RegEx.create_from_string(ARC_RE)
	var step_re = RegEx.create_from_string(STEP_RE)
	var result_re = RegEx.create_from_string(RESULT_RE)
	var fails_re = RegEx.create_from_string(FAILS_RE)
	var errors: Array = []
	var arcs = 0
	var arc_ids: Dictionary = {}
	var steps: Dictionary = {}
	var current = ""
	var has_result = true
	var has_steps = true
	for raw in lines:
		var line = str(raw).strip_edges()
		if line == "":
			continue
		var m = arc_re.search(line)
		if m:
			if current != "" and not has_result:
				errors.append("arc `%s` has no result" % current)
			if current != "" and not has_steps:
				errors.append("arc `%s` has no steps" % current)
			current = m.get_string(1)
			if arc_ids.has(current):
				errors.append("duplicate arc `%s`" % current)
			arc_ids[current] = true
			if m.get_string(2) not in want_ids:
				errors.append("arc `%s` serves unknown want `%s`" % [current, m.get_string(2)])
			arcs += 1
			has_result = false
			has_steps = false
			steps = {}
			continue
		if line.begins_with("### "):
			errors.append("bad arc header: %s" % line)
			continue
		if not line.begins_with("- "):
			continue  # prose
		if current == "":
			errors.append("Life line before any arc: %s" % line)
			continue
		m = result_re.search(line)
		if m:
			has_result = true
			if not m.get_string(1).begins_with(key + "_"):
				errors.append("result `%s` must start with `%s_`" % [m.get_string(1), key])
			if "{" in line:
				errors.append("unfilled slot in result: %s" % line)
			continue
		if line.begins_with("- fails_if:"):
			if not fails_re.search(line):
				errors.append("bad fails_if line: %s" % line)
			continue
		m = step_re.search(line)
		if m == null:
			errors.append("bad step line: %s" % line)
			continue
		has_steps = true
		var step_id = m.get_string(1)
		var after = m.get_string(3)
		if after != "none" and not steps.has(after):
			errors.append("step `%s` comes after unknown step `%s`" % [step_id, after])
		steps[step_id] = true
		for effect in m.get_string(7).split(", "):
			if effect not in PERSONAL_EFFECTS:
				errors.append("step `%s` uses %s (personal scope only)" % [step_id, effect])
	if current != "" and not has_result:
		errors.append("arc `%s` has no result" % current)
	if current != "" and not has_steps:
		errors.append("arc `%s` has no steps" % current)
	return {"errors": errors, "arcs": arcs}

## Raw lines of one `## <name>` section ([] when absent)
static func extract_section(text: String, section_name: String) -> Array:
	var out: Array = []
	var inside = false
	for raw in text.split("\n"):
		var line = raw.strip_edges()
		if line.begins_with("## "):
			inside = line.substr(3).strip_edges().to_lower() == section_name
			continue
		if inside:
			out.append(raw)
	return out

## Every machine line of a soul (header ids, wants, lines, agency, drift, Life machine lines),
## in order. A soul rewritten in character must keep this signature exactly
static func machine_signature(text: String) -> Array:
	var sig: Array = []
	var section = ""
	for raw in text.split("\n"):
		var line = raw.strip_edges()
		if line.begins_with("## "):
			section = line.substr(3).strip_edges().to_lower()
			continue
		if section == "" and (line.begins_with("npc:") or line.begins_with("npc_id:")):
			sig.append(line)
		elif section in ["wants", "lines i will not cross", "agency", "drift"] and line.begins_with("- "):
			sig.append(line)
		elif section == "life" and (line.begins_with("### ") or line.begins_with("- ")):
			sig.append(line)
	return sig
