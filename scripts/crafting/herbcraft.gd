extends RefCounted
## Herbcraft - cooking and remedies by free combination (docs/PLAYER_SYSTEMS.md §4, Breath of the Wild)
## 1-5 ingredients from resources/crafting/ingredients.json; effects come from their summed tags and
## the cook's herbcraft skill raises potency. Pure and deterministic: the same ingredients (in any
## order) and skill always make the same thing. Nothing here touches the world: Crafting.cook calls
## cook(), adds the item, records the deed and sets story_flag_for(item_id) when it is first made.
##
## Effects (what the rest of the game applies, all ints unless noted):
##   healing          points of health restored (PlayerStats.heal)
##   stamina          points of stamina restored
##   warmth_minutes   game minutes the cold is kept out
##   sleep_minutes    game minutes of heavy sleep for whoever drinks or eats it
##   poison           points of health lost by whoever eats it
##   fever            String effect id: FEVER_QUIET (root or salt alone; with fever_quiet_days, 2-4)
##                    or FEVER_CURE (fever-root steeped with white salt: the Grey Fever broken for good)
##   fever_quiet_days int, only with FEVER_QUIET

const DATA_PATH = "res://resources/crafting/ingredients.json"
const MAX_INGREDIENTS = 5

const FEVER_QUIET = "fever_quiet"
const FEVER_CURE = "fever_cure"

## Canon (WORLD_BIBLE): fever-root steeped with the white salt of Greystone's deep vein
const FEVER_ROOT = "fever_root"
const WHITE_SALT = "white_salt"
const CURE_ITEM = "grey_fever_cure"
const ROOT_ITEM = "fever_root_tea"
const SALT_ITEM = "salt_draught"
const DUBIOUS_ITEM = "dubious_food"

## Per point of summed tag strength, at potency 1.0
const PER_POINT = {"healing": 6, "stamina": 8, "warmth": 30, "sleep": 45, "poison": 8}
const EFFECT_KEY = {"healing": "healing", "stamina": "stamina", "warmth": "warmth_minutes", "sleep": "sleep_minutes", "poison": "poison"}
## A remedy is named for its strongest tag; ties go in this order
const TAG_ORDER = ["healing", "stamina", "warmth", "sleep"]
const REMEDY_ITEM = {"healing": "healing_draught", "stamina": "rousing_tonic", "warmth": "warming_tonic", "sleep": "sleeping_draught"}
## Food bases make a meal instead of a remedy; first match in this order names it
const FOOD_ORDER = [["meat", "meat_stew"], ["fish", "fish_stew"], ["grain", "pottage"], ["vegetable", "pottage"], ["fruit", "pottage"], ["mushroom", "pottage"]]
## One rouses and one dulls: together they are nonsense
const CLASHES = [["sleep", "stamina"]]
## More distinct effects than this (healing aside) is a muddle
const MAX_EFFECTS = 2
const DUBIOUS_HEALING = 2
const SEASONED_BONUS = 0.1

static var _ingredients: Dictionary = {}
static var _dishes: Dictionary = {}
static var _loaded: bool = false

## The ingredient's definition ({id, name, category, tags, strength, found_at, season, text}), or {}
static func ingredient(id: String) -> Dictionary:
	_load()
	return _ingredients.get(id, {}).duplicate(true)

## A made item's definition ({id, name, kind, text, story_flag?, deed?}), or {}
static func dish(item_id: String) -> Dictionary:
	_load()
	return _dishes.get(item_id, {}).duplicate(true)

static func all_ingredient_ids() -> Array:
	_load()
	var ids = _ingredients.keys()
	ids.sort()
	return ids

## Ingredients that grow or are sold at a location; season "" ignores the season
static func ingredients_at(location_id: String, season: String = "") -> Array:
	_load()
	var out: Array = []
	for id in all_ingredient_ids():
		var ing: Dictionary = _ingredients[id]
		if not location_id in ing.get("found_at", []):
			continue
		var s = str(ing.get("season", "any"))
		if season == "" or s == "any" or s == season:
			out.append(id)
	return out

## The world flag the caller sets the first time this item is made ("" for none). The cure's is the
## Grey Fever storyline's own receipt flag, so its beats react exactly as if the receipt were found
static func story_flag_for(item_id: String) -> String:
	return str(dish(item_id).get("story_flag", ""))

## The feat summary for PlayerEvents.record when making this item is a story act ("" for none)
static func deed_for(item_id: String) -> String:
	return str(dish(item_id).get("deed", ""))

## Returns {item_id, effects, potency, dubious, name, text, kind, quality (0-100), reason}.
## item_id is "" when the ingredients cannot be cooked at all (none, too many, unknown); reason says why
static func cook(ingredient_ids: Array, skill: float) -> Dictionary:
	_load()
	var out = {"item_id": "", "effects": {}, "potency": 0.0, "dubious": false, "name": "", "text": "", "kind": "", "quality": 0, "reason": ""}
	if ingredient_ids.is_empty() or ingredient_ids.size() > MAX_INGREDIENTS:
		out.reason = "cook with one to five ingredients"
		return out
	var ids: Array = []
	for raw in ingredient_ids:
		var id = str(raw)
		if not _ingredients.has(id):
			out.reason = "unknown ingredient '%s'" % id
			return out
		ids.append(id)
	ids.sort()  # order never matters

	skill = clampf(skill, 0.0, 100.0)
	var totals: Dictionary = {}
	var categories: Dictionary = {}
	for id in ids:
		var ing: Dictionary = _ingredients[id]
		categories[ing.category] = true
		for tag in ing.get("tags", []):
			totals[tag] = int(totals.get(tag, 0)) + int(ing.get("strength", 0))
	var food_item = ""
	for pair in FOOD_ORDER:
		if categories.has(pair[0]):
			food_item = pair[1]
			break
	var seasoned = categories.has("seasoning") and food_item != ""
	var potency = snappedf(0.6 + skill * 0.009 + (SEASONED_BONUS if seasoned else 0.0), 0.01)
	out.potency = potency
	out.quality = clampi(roundi(20 + skill * 0.8 + (10 if seasoned else 0)), 0, 100)

	# Poison spoils everything else in the pot, the cure included
	if int(totals.get("poison", 0)) > 0:
		return _finish(out, "tainted_food" if food_item != "" else "poison_draught", {"poison": _amount("poison", totals, potency)}, "")

	var reason = _nonsense(totals)
	if reason != "":
		out.dubious = true
		return _finish(out, DUBIOUS_ITEM, {"healing": DUBIOUS_HEALING}, reason)

	var effects: Dictionary = {}
	for tag in PER_POINT:
		if int(totals.get(tag, 0)) > 0:
			effects[EFFECT_KEY[tag]] = _amount(tag, totals, potency)
	var item_id = food_item
	if int(totals.get("fever", 0)) > 0:
		var has_root = FEVER_ROOT in ids
		var has_salt = WHITE_SALT in ids
		if has_root and has_salt:
			effects.fever = FEVER_CURE
			item_id = CURE_ITEM
		else:
			effects.fever = FEVER_QUIET
			effects.fever_quiet_days = clampi(1 + int(totals.fever * potency / 3.0), 2, 4)
			item_id = ROOT_ITEM if has_root else SALT_ITEM
	elif item_id == "":
		item_id = REMEDY_ITEM[_strongest(totals)]
	return _finish(out, item_id, effects, "")

# =============================================================================
# INTERNALS
# =============================================================================

## Why this pot is nonsense, or "" if it is not
static func _nonsense(totals: Dictionary) -> String:
	var sum = 0
	for tag in totals:
		sum += int(totals[tag])
	if sum == 0:
		return "nothing in it does anything"
	for pair in CLASHES:
		if int(totals.get(pair[0], 0)) > 0 and int(totals.get(pair[1], 0)) > 0:
			return "%s and %s work against each other" % [pair[0], pair[1]]
	var distinct = 0
	for tag in totals:
		if tag != "healing" and int(totals[tag]) > 0:
			distinct += 1
	if distinct > MAX_EFFECTS:
		return "too many things pulling different ways"
	return ""

static func _amount(tag: String, totals: Dictionary, potency: float) -> int:
	return maxi(1, roundi(int(totals.get(tag, 0)) * PER_POINT[tag] * potency))

static func _strongest(totals: Dictionary) -> String:
	var best = TAG_ORDER[0]
	for tag in TAG_ORDER:
		if int(totals.get(tag, 0)) > int(totals.get(best, 0)):
			best = tag
	return best

static func _finish(out: Dictionary, item_id: String, effects: Dictionary, reason: String) -> Dictionary:
	var d: Dictionary = _dishes.get(item_id, {})
	out.item_id = item_id
	out.effects = effects
	out.name = str(d.get("name", item_id))
	out.text = str(d.get("text", ""))
	out.kind = str(d.get("kind", "food"))
	out.reason = reason
	return out

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var raw = FileAccess.get_file_as_string(DATA_PATH)
	var data = JSON.parse_string(raw) if raw != "" else null
	if not (data is Dictionary):
		push_error("[Herbcraft] cannot read %s" % DATA_PATH)
		return
	for ing in data.get("ingredients", []):
		_ingredients[str(ing.id)] = ing
	for d in data.get("dishes", []):
		_dishes[str(d.id)] = d
