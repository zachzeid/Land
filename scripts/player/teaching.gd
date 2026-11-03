extends RefCounted
## Teaching - an NPC with the trade trains the player (docs/PLAYER_SYSTEMS.md §2 "Teachers")
## Who can teach what is data (resources/player/teachers.json: named mains, generics by archetype).
## Whether they will is the soul's choice: StorylineDirector.decide_situation with options refuse /
## teach (for coin) or teach_for_favour (when the player cannot pay), appeal on trust and respect.
## A lesson takes game time and multiplies gain for that skill for a while. Minors never teach a
## combat skill (stealth is fine). Owned by PlayerStats: PlayerStats.get_teaching()

const TEACHERS_PATH = "res://resources/player/teachers.json"
const COMBAT_SKILLS = ["blades", "blunt", "bows", "defence"]
const DEFAULT_BASE_COPPER = 12
const DEFAULT_UP_TO = 50

## Seams (null = autoloads)
var stats = null
var director = null
var inventory = null
var world_state = null
var registry = null

var _data: Dictionary = {}

func _init(owner_stats = null):
	stats = owner_stats
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TEACHERS_PATH)) if FileAccess.file_exists(TEACHERS_PATH) else null
	_data = parsed if parsed is Dictionary else {}

## Ask teacher_key to train skill. Async (the soul decides). Returns {ok, reason, cost_copper, minutes}
## (plus choice and paid: "coin" | "favour" when ok)
func request_training(teacher_key: String, skill: String) -> Dictionary:
	var key = npc_key(teacher_key)
	var out = {"ok": false, "reason": "", "cost_copper": 0, "minutes": 0}
	out.reason = lesson_denial(key, skill, teacher_key)
	if out.reason != "":
		return out
	var row = teacher_row(key)
	var cost = lesson_cost(row, _stats().get_skill(skill))
	out.cost_copper = cost
	out.minutes = lesson_minutes()
	var dir = _director()
	if dir == null:
		out.reason = "no one to ask"
		return out
	var can_pay = _coin() >= cost
	var decision: Dictionary = await dir.decide_situation(key, _hook(key, skill, cost, can_pay), "Teach the stranger %s?" % skill)
	out["choice"] = str(decision.get("choice", "pass"))
	if out.choice not in ["teach", "teach_for_favour"]:
		out.reason = "refused" if out.choice == "refuse" else str(decision.get("reason", "would not answer"))
		return out
	if dir.has_method("apply_situation_effects") and not decision.get("effects", []).is_empty():
		dir.apply_situation_effects(key, decision, {"teaching": skill})
	var lesson = give_lesson(key, skill, "coin" if out.choice == "teach" else "favour", cost)
	out.merge(lesson, true)
	return out

## Why this NPC cannot teach this skill ("" when they can): no such skill, not their trade, a child
## and a fighting skill, or the player already past what they know
func lesson_denial(teacher_key: String, skill: String, raw: String = "") -> String:
	var key = npc_key(teacher_key)
	var s = _stats()
	if s == null or not skill in s.get_skill_ids():
		return "no such skill"
	if _is_minor(key, raw if raw != "" else teacher_key) and skill in COMBAT_SKILLS:
		return "a child does not teach fighting"
	var row = teacher_row(key)
	if row.is_empty() or not skill in row.get("skills", []):
		return "does not know that trade"
	if s.get_skill(skill) >= float(row.get("up_to", DEFAULT_UP_TO)):
		return "has nothing more to teach you"
	return ""

## The usual fee for a lesson from this teacher now (0 when they cannot teach it)
func usual_cost(teacher_key: String, skill: String) -> int:
	var row = teacher_row(npc_key(teacher_key))
	var s = _stats()
	return lesson_cost(row, s.get_skill(skill)) if not row.is_empty() and s else 0

func lesson_minutes() -> int:
	return int(_data.get("lesson_minutes", 120))

## The lesson itself, once the teacher has said yes (by soul: decide_situation here, or their own
## `teach` action in conversation). paid: "coin" (cost is taken from the purse; false when it is
## short) or "favour" (a promise deed). Takes game time and boosts gain for a while.
## Returns {ok, reason, paid, cost_copper, minutes, recipes_learned}
func give_lesson(teacher_key: String, skill: String, paid: String, cost: int) -> Dictionary:
	var key = npc_key(teacher_key)
	var out = {"ok": false, "reason": "", "paid": paid, "cost_copper": 0, "minutes": lesson_minutes(), "recipes_learned": []}
	var denial = lesson_denial(key, skill)
	if denial != "":
		out.reason = denial
		return out
	var s = _stats()
	if paid == "coin":
		if not _pay(maxi(cost, 0)):
			out.reason = "cannot pay"
			return out
		out.cost_copper = maxi(cost, 0)
	else:
		out.paid = "favour"
		var events = _node("PlayerEvents")
		if events:
			events.record("promise", "promised a favour in return for lessons in %s" % skill, [key], {"witnesses": [key], "spread": false})
	var ws = _world_state()
	var now = ws.get_game_minutes() if ws else 0
	s.add_training(skill, float(_data.get("boost_multiplier", 2.0)), now + out.minutes + int(_data.get("boost_minutes", 1440)))
	if ws and ws.has_method("advance_time"):
		ws.advance_time(out.minutes, "training")
	out.recipes_learned = _learn_taught_recipes(skill)
	out.ok = true
	out.reason = "taught"
	return out

## A lesson also passes on the recipes of that craft that can only be taught (recipes.json "learn": "taught")
func _learn_taught_recipes(skill: String) -> Array:
	var crafting = _node("Crafting")
	if crafting == null or not "recipes" in crafting or not crafting.has_method("learn_recipe"):
		return []
	var learned: Array = []
	for id in crafting.recipes:
		var r: Dictionary = crafting.recipes[id]
		if str(r.get("learn", "")) == "taught" and str(r.get("skill", "")) == skill and crafting.learn_recipe(str(id), "taught"):
			learned.append(str(id))
	return learned

## Copper for a lesson: dearer the further along the player already is
static func lesson_cost(row: Dictionary, current_level: float) -> int:
	return int(round(float(row.get("base_copper", DEFAULT_BASE_COPPER)) * (1.0 + current_level / 25.0)))

## The teachers.json row for a main key or a generic id (by its archetype); {} when none
func teacher_row(key: String) -> Dictionary:
	var named: Dictionary = _data.get("named", {})
	if named.has(key):
		return named[key]
	var arch = _archetype_of(key)
	var archetypes: Dictionary = _data.get("archetypes", {})
	return archetypes.get(arch, {}) if arch != "" else {}

## The skills that are this NPC's trade (also used for respect from feats)
func trades_of(key: String) -> Array:
	return teacher_row(npc_key(key)).get("skills", [])

## A main's key from its key or npc id; generics keep their id
func npc_key(who: String) -> String:
	var reg = _registry()
	if reg:
		if reg.has_npc(who):
			return who
		var k = str(reg.get_npc_key(who))
		if k != "":
			return k
	return who

func _hook(key: String, skill: String, cost: int, can_pay: bool) -> Dictionary:
	var options: Array = [{"id": "refuse", "label": "Refuse to teach the stranger", "appeal": {"fear": 0.5, "trust": -0.5}, "effects": []}]
	if can_pay:
		options.append({"id": "teach", "label": "Teach them %s for %s" % [skill, _coin_text(cost)],
			"appeal": {"trust": 1.0, "respect": 1.0, "familiarity": 0.5}, "effects": []})
	else:
		options.append({"id": "teach_for_favour", "label": "Teach them %s for a favour owed" % skill,
			"appeal": {"trust": 1.0, "respect": 0.5, "affection": 1.0}, "effects": []})
	return {"id": "teach_%s" % skill, "type": "react",
		"situation": "The stranger asks you to teach them %s, your own trade." % skill, "options": options}

func _archetype_of(key: String) -> String:
	var generics = _generics()
	if generics and generics.has_method("get_instance"):
		var inst = generics.get_instance(key)
		if inst != null and "archetype_id" in inst:
			return str(inst.archetype_id)
	if key.begins_with("gen_"):
		# gen_<archetype>_<n>, when the manager has not populated (tests, early load)
		var rest = key.substr(4)
		var cut = rest.rfind("_")
		return rest.substr(0, cut) if cut > 0 else rest
	return ""

func _is_minor(key: String, raw: String) -> bool:
	var reg = _registry()
	return reg != null and (reg.is_minor(key) or reg.is_minor(raw))

func _coin() -> int:
	var inv = _inventory()
	return int(inv.get_coin()) if inv and inv.has_method("get_coin") else 0

## Pay from the purse (Inventory.spend_coin). false when it is short
func _pay(copper: int) -> bool:
	if copper <= 0:
		return true
	var inv = _inventory()
	if inv == null:
		return false
	if inv.has_method("spend_coin"):
		return inv.spend_coin(copper)
	if _coin() < copper or not inv.has_method("add_coin"):
		return false  # a purse without spend_coin (test fakes): check, then take
	inv.add_coin(-copper)
	return true

## The price as coin is named (Inventory.format_coin), never denominations written here
func _coin_text(amount: int) -> String:
	var inv = _inventory()
	return str(inv.format_coin(amount)) if inv and inv.has_method("format_coin") else str(amount)

func _stats():
	return stats if stats != null else _node("PlayerStats")

func _director():
	return director if director != null else (stats.director if stats != null and stats.director != null else _node("StorylineDirector"))

func _inventory():
	return inventory if inventory != null else (stats.inventory if stats != null and stats.inventory != null else _node("Inventory"))

func _world_state():
	return world_state if world_state != null else _node("WorldState")

func _registry():
	return registry if registry != null else _node("WorldRegistry")

func _generics():
	var dir = _node("StorylineDirector")
	return dir.get_generics() if dir and dir.has_method("get_generics") else null

func _node(node_name: String) -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree else null
