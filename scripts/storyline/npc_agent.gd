extends RefCounted
# NpcAgent - Decides what one NPC does when a storyline hook is offered to it
# offline: deterministic, picks the permitted option whose `serves` wants weigh most right now
# claude: asks Claude for strict JSON, validates it, and falls back to offline on any problem
# The agent only chooses. The Director re-checks every effect before anything is applied

const MODES = ["offline", "claude"]
const DEFAULT_TIMEOUT = 20.0
const EFFECT_SHAPES = {
	"set_flag": '{"type": "set_flag", "flag": "<flag>", "value": true}',
	"adjust_relationship": '{"type": "adjust_relationship", "npc": "<npc key>", "dimension": "trust|respect|affection|fear|familiarity", "delta": -20..20}',
	"spread_rumor": '{"type": "spread_rumor", "flag": "<flag>", "to": ["<npc key>"] or ["*"], "via": "<how it travels>"}',
	"agenda": '{"type": "agenda", "npc": "<npc key>", "text": "<160 chars max>"}',
	"move_npc": '{"type": "move_npc", "npc": "<npc key>", "location": "<location id>"}',
	"block_beat": '{"type": "block_beat", "storyline": "<id>", "beat": "<id>"}',
	"unlock_beat": '{"type": "unlock_beat", "storyline": "<id>", "beat": "<id>"}',
	"shift_want": '{"type": "shift_want", "npc": "<npc key>", "want": "<want id>", "delta": -3..3}',
	"shift_fixed_point": '{"type": "shift_fixed_point", "point": "<calendar point>", "days": -3..3, "reason": "<why, in-world>"} or {"type": "shift_fixed_point", "point": "<calendar point>", "cancel": true, "reason": "<why>"}',
	"spread_event": '{"type": "spread_event", "event": "<event id>", "to": ["<npc key>"] or ["*"], "via": "<how it travels>"}',
}

var mode: String = "offline"
var client: Object = null         # anything with send_message(messages, system_prompt) -> Dictionary
var tree: SceneTree = null        # for the timeout timer and the Config lookup
var timeout_seconds: float = DEFAULT_TIMEOUT

## Decide at a hook. Returns:
## {"choice": option_id|"pass"|"freeform", "option": Dictionary, "effects": Array,
##  "reason": String, "mode": "offline"|"claude"|"claude_fallback", "fallback_reason": String}
func decide(soul, hook: Dictionary, context: Dictionary = {}) -> Dictionary:
	if mode != "claude":
		return decide_offline(soul, hook)
	# Nothing to ask Claude when the soul cannot act here at all
	if soul == null or not soul.engages(str(hook.get("type", ""))):
		return decide_offline(soul, hook)
	if client == null:
		return _fallback(soul, hook, "no Claude client")
	if not _has_api_key():
		return _fallback(soul, hook, "no API key")

	var prompt = build_prompt(soul, hook, context)
	var response = await _send_with_timeout([{"role": "user", "content": prompt.user}], prompt.system)
	if response.has("error"):
		return _fallback(soul, hook, "Claude error: %s" % response.error)
	var parsed = parse_response(str(response.get("text", "")), hook)
	if not parsed.ok:
		return _fallback(soul, hook, parsed.reason)
	parsed.decision["mode"] = "claude"
	parsed.decision["fallback_reason"] = ""
	return parsed.decision

## Deterministic soul-weighted choice: highest want-weight sum among fully permitted options
## Ties go to the earlier option; "pass" when the soul permits none
func decide_offline(soul, hook: Dictionary) -> Dictionary:
	var hook_type = str(hook.get("type", ""))
	if soul == null:
		return _pass("no SOUL.md for this NPC")
	if not soul.engages(hook_type):
		return _pass("this soul does not act at %s hooks" % hook_type)

	var best: Dictionary = {}
	var best_score = -1
	for option in hook.get("options", []):
		if soul.get_option_denial_reason(option) != "":
			continue
		var permitted = true
		for effect in option.get("effects", []):
			if not effect is Dictionary or not soul.permits(hook_type, effect):
				permitted = false
				break
		if not permitted:
			continue
		var score = soul.score_wants(option.get("serves", []))
		if score > best_score:
			best_score = score
			best = option
	if best.is_empty():
		return _pass("no option this soul permits")
	return {
		"choice": str(best.get("id", "")),
		"option": best,
		"effects": best.get("effects", []).duplicate(true),
		"reason": "serves %s (weight %d)" % [", ".join(best.get("serves", [])) if not best.get("serves", []).is_empty() else "nothing", best_score],
		"mode": "offline",
		"fallback_reason": ""
	}

## System prompt (soul) and user prompt (situation + numbered options)
func build_prompt(soul, hook: Dictionary, context: Dictionary) -> Dictionary:
	var system = soul.get_prompt_block(true)
	system += "## HOW YOU DECIDE\n"
	system += "You are %s, acting on your own, off-stage, in a moment the player does not see.\n" % (soul.display_name if soul.display_name != "" else soul.npc_key)
	system += "Choose what you would truly do, true to your wants and the lines you will not cross.\n"
	system += "Respond with ONLY a JSON object, no prose before or after:\n"
	system += '{"choice": "<option id>|pass|freeform", "effects": [], "reason": "<one sentence, in your own voice>"}\n'
	system += "Leave effects empty unless choice is freeform.\n"

	var user = ""
	if context.get("storyline_title", "") != "":
		user += "Story: %s. %s\n" % [context.storyline_title, context.get("beat_title", "")]
	user += "Situation: %s\n\nYour options:\n" % str(hook.get("situation", ""))
	var number = 1
	for option in hook.get("options", []):
		user += "%d. id \"%s\": %s\n" % [number, option.get("id", ""), option.get("label", "")]
		number += 1
	user += "Or \"pass\": do nothing at all.\n"
	if hook.get("allow_freeform", false) == true:
		var allowed: Array = []
		for effect_type in hook.get("freeform_effects", []):
			if soul.agency.get(str(hook.get("type", "")), []).has(effect_type) and EFFECT_SHAPES.has(effect_type):
				allowed.append(effect_type)
		if not allowed.is_empty():
			user += "\nOr \"freeform\": compose your own effects, using only these shapes:\n"
			for effect_type in allowed:
				user += "- %s\n" % EFFECT_SHAPES[effect_type]
	return {"system": system, "user": user}

## Validate Claude's text. Returns {"ok": bool, "decision": Dictionary, "reason": String}
## Effects for a picked option always come from the authored option, never from the model
func parse_response(text: String, hook: Dictionary) -> Dictionary:
	var start = text.find("{")
	var finish = text.rfind("}")
	if start == -1 or finish <= start:
		return _bad("response is not JSON")
	var data = JSON.parse_string(text.substr(start, finish - start + 1))
	if not data is Dictionary or not data.get("choice") is String:
		return _bad("response has no string 'choice'")
	var choice: String = data.choice
	var reason = str(data.get("reason", "")).substr(0, 300)
	if choice == "pass":
		return {"ok": true, "decision": {"choice": "pass", "option": {}, "effects": [], "reason": reason}, "reason": ""}
	if choice == "freeform":
		if hook.get("allow_freeform", false) != true:
			return _bad("freeform is not allowed at this hook")
		if not data.get("effects") is Array:
			return _bad("freeform choice has no effects array")
		return {"ok": true, "decision": {"choice": "freeform", "option": {}, "effects": data.effects, "reason": reason}, "reason": ""}
	for option in hook.get("options", []):
		if str(option.get("id", "")) == choice:
			return {"ok": true, "decision": {"choice": choice, "option": option, "effects": option.get("effects", []).duplicate(true), "reason": reason}, "reason": ""}
	return _bad("unknown option '%s'" % choice)

# =============================================================================
# PERSONAL STEPS (docs/WORLD_SCHEMA.md §8)
# =============================================================================

## Decide the effects of finishing one personal step. offline_effects is the deterministic default
## the Director built from the step's effect types. Claude may phrase its own instead, but only with
## the step's types; the Director re-checks every effect (soul lines, personal scope, plausibility)
## Returns {"effects": Array, "reason": String, "mode": "offline"|"claude"|"claude_fallback", "fallback_reason": String}
func decide_personal(soul, arc: Dictionary, step: Dictionary, offline_effects: Array, context: Dictionary = {}) -> Dictionary:
	var offline = {"effects": offline_effects.duplicate(true), "reason": "works at %s" % step.get("id", ""), "mode": "offline", "fallback_reason": ""}
	if mode != "claude" or soul == null or step.get("effects", []).is_empty():
		return offline
	if client == null:
		return offline.merged({"mode": "claude_fallback", "fallback_reason": "no Claude client"}, true)
	if not _has_api_key():
		return offline.merged({"mode": "claude_fallback", "fallback_reason": "no API key"}, true)
	var prompt = build_personal_prompt(soul, arc, step, context)
	var response = await _send_with_timeout([{"role": "user", "content": prompt.user}], prompt.system)
	if response.has("error"):
		return offline.merged({"mode": "claude_fallback", "fallback_reason": "Claude error: %s" % response.error}, true)
	var text = str(response.get("text", ""))
	var start = text.find("{")
	var finish = text.rfind("}")
	var data = JSON.parse_string(text.substr(start, finish - start + 1)) if start != -1 and finish > start else null
	if not data is Dictionary or not data.get("effects") is Array:
		return offline.merged({"mode": "claude_fallback", "fallback_reason": "response has no effects array"}, true)
	return {"effects": data.effects, "reason": str(data.get("reason", "")).substr(0, 300), "mode": "claude", "fallback_reason": ""}

func build_personal_prompt(soul, arc: Dictionary, step: Dictionary, context: Dictionary) -> Dictionary:
	var system = soul.get_prompt_block(true)
	system += "## HOW YOU DECIDE\n"
	system += "You are %s, living your own life, off-stage. You have just finished something you set out to do for yourself.\n" % (soul.display_name if soul.display_name != "" else soul.npc_key)
	system += "Say what follows from it, true to your wants and the lines you will not cross. Nothing you do here can change the region's larger events.\n"
	system += "Respond with ONLY a JSON object, no prose before or after:\n"
	system += '{"effects": [], "reason": "<one sentence, in your own voice>"}\n'
	var user = "What you are pursuing: %s\n" % str(arc.get("prose", arc.get("id", "")))
	user += "What you just finished: %s\n" % str(step.get("text", ""))
	if context.get("location", "") != "":
		user += "Where you are: %s\n" % context.location
	if context.get("people", "") != "":
		user += "People by key: %s\n" % context.people
	user += "\nEffects you may use (none is fine; at most 3), only these shapes:\n"
	for effect_type in step.get("effects", []):
		if EFFECT_SHAPES.has(effect_type):
			user += "- %s\n" % EFFECT_SHAPES[effect_type]
	return {"system": system, "user": user}

# =============================================================================
# INTERNALS
# =============================================================================

## Race the request against a timer; whichever finishes first wins
class _Race extends RefCounted:
	signal finished
	signal request_returned
	var done: bool = false
	var result: Dictionary = {}

	func run(target: Object, messages: Array, system_prompt: String) -> void:
		var response = await target.send_message(messages, system_prompt)
		request_returned.emit()
		_finish(response if response is Dictionary else {"error": "bad response"})

	func expire() -> void:
		_finish({"error": "timeout"})

	func _finish(value: Dictionary) -> void:
		if done:
			return
		done = true
		result = value
		finished.emit()

var _inflight: Array = []  # races kept alive until their request returns, even after a timeout

func _send_with_timeout(messages: Array, system_prompt: String) -> Dictionary:
	var race = _Race.new()
	_inflight.append(race)
	race.request_returned.connect(func(): _inflight.erase(race), CONNECT_ONE_SHOT)
	race.run(client, messages, system_prompt)
	if not race.done:
		if tree:
			tree.create_timer(timeout_seconds, true).timeout.connect(race.expire)
		await race.finished
	return race.result

func _has_api_key() -> bool:
	if client and "api_key_override" in client and str(client.api_key_override) != "":
		return true
	var config = tree.root.get_node_or_null("Config") if tree else null
	if config == null or not config.has_method("get_claude_api_key"):
		return false
	var key = str(config.get_claude_api_key())
	return key != "" and key != "your_claude_api_key_here" and not ("xxxxxxxx" in key)

func _fallback(soul, hook: Dictionary, why: String) -> Dictionary:
	var decision = decide_offline(soul, hook)
	decision["mode"] = "claude_fallback"
	decision["fallback_reason"] = why
	return decision

func _pass(reason: String) -> Dictionary:
	return {"choice": "pass", "option": {}, "effects": [], "reason": reason, "mode": "offline", "fallback_reason": ""}

func _bad(reason: String) -> Dictionary:
	return {"ok": false, "decision": {}, "reason": reason}
