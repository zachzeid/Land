extends CanvasLayer
## CraftingPanel - what the player can make at the station they stand at, and cooking (docs/PLAYER_SYSTEMS.md §4, §8)
## Opened by PlayerUI.open_crafting(station_id): the craft action (B) near a station, or the station
## itself when used. B or Esc closes it; it pauses the world like the menu
## - Make: the station's recipes, each with its inputs (what is missing marked), the skill it wants,
##   a result quality preview and a Make button that is live only when Crafting.can_craft says so
## - Cook: ingredients in the pack to combine, one to five (BotW), through Crafting.cook
## Recipes come from Crafting.get_recipes(station_id) when the crafting slice offers it, else straight
## from resources/crafting/recipes.json. All making goes through the Crafting contract

const UI = preload("res://scripts/ui/player_ui.gd")
const RECIPES_PATH = "res://resources/crafting/recipes.json"
const HERBCRAFT_PATH = "res://scripts/crafting/herbcraft.gd"
const MAX_INGREDIENTS = 5
const INGREDIENT_KINDS = ["food", "material", "remedy"]

## Injectable for tests; the autoloads otherwise
var crafting: Node = null
var inventory: Node = null
var stats: Node = null
var is_open: bool = false
var station_id: String = ""
var mode: String = "make"   # make | cook
var selected: Array = []    # ingredient ids chosen to cook
var last_result: Dictionary = {}
var _was_paused: bool = false
var _title: Label
var _list: VBoxContainer
var _message: Label
var _cook_button: Button

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()

func _build() -> void:
	var parts = UI.centred_frame(self, Vector2(660, 460))
	var vbox: VBoxContainer = parts[1]
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vbox.add_child(top)
	_title = UI.label("", 24, UI.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	top.add_child(UI.button("Make", func(): show_mode("make"), 90))
	top.add_child(UI.button("Cook", func(): show_mode("cook"), 90))
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_message = UI.label("", 14)
	_message.name = "Message"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(600, 0)
	vbox.add_child(_message)
	var bottom = HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	_cook_button = UI.button("Combine", cook_selected)
	bottom.add_child(_cook_button)
	bottom.add_child(UI.label("   B or Esc to close   ", 12, UI.FAINT))
	bottom.add_child(UI.button("Close", close))
	vbox.add_child(bottom)

func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or (event.is_action_pressed("craft") and not event.is_echo()):
		get_viewport().set_input_as_handled()
		close()

func open(at_station: String) -> void:
	station_id = at_station
	selected = []
	last_result = {}
	_message.text = ""
	if not is_open:
		is_open = true
		visible = true
		_was_paused = get_tree().paused
		get_tree().paused = true
	show_mode(mode)

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = _was_paused

func show_mode(which: String) -> void:
	mode = which
	_title.text = ("At the %s" if which == "make" else "Cooking at the %s") % station_id.replace("_", " ")
	_cook_button.visible = which == "cook"
	refresh()

func refresh() -> void:
	UI.clear(_list)
	if mode == "cook":
		_refresh_cook()
	else:
		_refresh_make()

# =============================================================================
# MAKE
# =============================================================================

## The station's recipes as records: {id, name, station(s), inputs, output, skill, min_level, ...}
func recipes() -> Array:
	var c = _crafting()
	if c and c.has_method("get_recipes"):
		var got = c.get_recipes(station_id)
		return UI.records(got, "recipes")
	return UI.records(UI.read_json(RECIPES_PATH), "recipes").filter(func(r): return _at_this_station(r))

func _at_this_station(recipe: Dictionary) -> bool:
	var at = recipe.get("station", recipe.get("stations", ""))
	return station_id in at if at is Array else (str(at) == "" or str(at) == station_id)

## {item_id: qty} from either {id: qty} or [{id, qty}]
static func inputs_of(recipe: Dictionary) -> Dictionary:
	var raw = recipe.get("inputs", {})
	if raw is Dictionary:
		return raw
	var out = {}
	for entry in raw:
		if entry is Dictionary:
			out[str(entry.get("id", entry.get("item", "")))] = int(entry.get("qty", 1))
		else:
			out[str(entry)] = out.get(str(entry), 0) + 1
	return out

static func output_of(recipe: Dictionary) -> String:
	var out = recipe.get("output", recipe.get("result", recipe.get("id", "")))
	return str(out.get("id", out.get("item", ""))) if out is Dictionary else str(out)

## Expected quality, 0-100: Crafting's own preview when it gives one; otherwise the recipe skill's
## level, which the spec puts first among skill, station and material (§4). Marked as a guess
func preview_quality(recipe: Dictionary) -> Dictionary:
	var c = _crafting()
	var id = str(recipe.get("id", ""))
	if c and c.has_method("preview_quality"):
		return {"quality": roundi(float(c.preview_quality(id, station_id))), "guess": false}
	var s = _stats()
	var skill = str(recipe.get("skill", ""))
	var level = float(s.get_skill(skill)) if s and skill != "" else 0.0
	return {"quality": clampi(roundi(level), 0, 100), "guess": true}

func _refresh_make() -> void:
	var list = recipes()
	if list.is_empty():
		_list.add_child(UI.label("You know nothing you could make here yet.", 14, UI.FAINT))
		return
	var inv = _inventory()
	var c = _crafting()
	for recipe in list:
		var id = str(recipe.get("id", ""))
		var box = VBoxContainer.new()
		box.name = "Recipe_" + id
		var head = HBoxContainer.new()
		var name_label = UI.label(str(recipe.get("name", UI.item_name(output_of(recipe), _inventory()))), 16, UI.GOLD)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_label)
		var check: Dictionary = c.can_craft(id, station_id) if c else {"ok": false, "reason": ""}
		var make = UI.button("Make", craft.bind(id), 90)
		make.disabled = not check.get("ok", false)
		head.add_child(make)
		box.add_child(head)
		var needs: Array = []
		var inputs = inputs_of(recipe)
		for item_id in inputs:
			var have = inv != null and inv.has(item_id, int(inputs[item_id]))
			needs.append("%s ×%d%s" % [UI.item_name(item_id, _inventory()), int(inputs[item_id]), "" if have else " (missing)"])
		box.add_child(UI.label("Needs: " + (", ".join(needs) if not needs.is_empty() else "nothing"), 13))
		var preview = preview_quality(recipe)
		var skill = str(recipe.get("skill", ""))
		var line = "Quality: %s%s (%d)" % ["about " if preview.guess else "", _quality_word(preview.quality), preview.quality]
		if skill != "":
			line += "   ·   %s %d" % [skill.capitalize(), int(recipe.get("min_level", recipe.get("level", 0)))]
		box.add_child(UI.label(line, 13, UI.FAINT))
		if not check.get("ok", false) and str(check.get("reason", "")) != "":
			box.add_child(UI.label(str(check.reason), 13, UI.WARN))
		_list.add_child(box)

func craft(recipe_id: String) -> Dictionary:
	var c = _crafting()
	var result: Dictionary = c.craft(recipe_id, station_id) if c else {"ok": false, "reason": "nothing to work with"}
	last_result = result
	_message.text = _result_text(result, "You make")
	refresh()
	return result

# =============================================================================
# COOK
# =============================================================================

## Pack items that can go in a pot: what Herbcraft knows as an ingredient once it is built, else
## food, materials and remedies
func ingredients() -> Array:
	var inv = _inventory()
	if inv == null:
		return []
	var herbcraft = load(HERBCRAFT_PATH) if ResourceLoader.exists(HERBCRAFT_PATH) else null
	var out: Array = []
	for item in inv.get_items():
		if not item is Dictionary:
			continue
		var id = str(item.get("id", ""))
		var known = false
		if herbcraft and _has_static(herbcraft, "ingredient"):
			var d = herbcraft.ingredient(id)
			known = d is Dictionary and not d.is_empty()
		else:
			known = str(UI.item_def(id, inv).get("kind", item.get("kind", ""))) in INGREDIENT_KINDS
		if known and not id in out:
			out.append(id)
	return out

func _refresh_cook() -> void:
	var list = ingredients()
	_list.add_child(UI.label("Choose one to five things to put together.", 14, UI.FAINT))
	if list.is_empty():
		_list.add_child(UI.label("You carry nothing to cook.", 14, UI.FAINT))
	for id in list:
		var box = CheckBox.new()
		box.name = "Ingredient_" + id
		box.text = UI.item_name(id, _inventory())
		box.button_pressed = id in selected
		box.add_theme_font_size_override("font_size", 14)
		box.toggled.connect(toggle_ingredient.bind(id))
		_list.add_child(box)
	_cook_button.disabled = selected.is_empty()

func toggle_ingredient(on: bool, item_id: String) -> void:
	if on and not item_id in selected:
		if selected.size() >= MAX_INGREDIENTS:
			_message.text = "The pot holds no more than %d things." % MAX_INGREDIENTS
			refresh()
			return
		selected.append(item_id)
	elif not on:
		selected.erase(item_id)
	_cook_button.disabled = selected.is_empty()

func cook_selected() -> Dictionary:
	if selected.is_empty():
		return {"ok": false, "reason": "nothing chosen"}
	var c = _crafting()
	var result: Dictionary = c.cook(selected.duplicate(), station_id) if c else {"ok": false, "reason": "nothing to cook on"}
	last_result = result
	_message.text = _result_text(result, "You cook")
	if result.get("ok", false):
		selected = []
	refresh()
	return result

# =============================================================================

func _result_text(result: Dictionary, verb: String) -> String:
	if not result.get("ok", false):
		return str(result.get("reason", "It does not come right."))
	var item = result.get("item", {})
	var id = str(item.get("id", item.get("item_id", ""))) if item is Dictionary else str(item)
	var text = "%s %s" % [verb, UI.item_name(id, _inventory())]
	if item is Dictionary and item.has("quality"):
		text += ", %s (%d)" % [_quality_word(float(item.quality)), roundi(float(item.quality))]
	if item is Dictionary and item.get("dubious", false):
		text += ". It does not look like anything anyone should eat"
	return text + "."

func get_message() -> String:
	return _message.text

func get_recipe_names() -> Array:
	var out: Array = []
	for box in _list.get_children():
		if box.name.begins_with("Recipe_"):
			out.append(str(box.name).trim_prefix("Recipe_"))
	return out

static func _has_static(script: Script, method: String) -> bool:
	return script.get_script_method_list().any(func(m): return m.name == method)

static func _quality_word(q: float) -> String:
	return load("res://scripts/ui/inventory_panel.gd").quality_word(q)

func _crafting() -> Node:
	return crafting if crafting else UI.autoload("Crafting")

func _inventory() -> Node:
	return inventory if inventory else UI.autoload("Inventory")

func _stats() -> Node:
	return stats if stats else UI.autoload("PlayerStats")
