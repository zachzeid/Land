extends SceneTree

# Tests the player-systems UI (docs/PLAYER_SYSTEMS.md §8 "UI"):
# - PlayerUI builds the HUD and the four panels beside the menu; each opens, pauses the world and
#   closes with Esc (and I / B for their own keys) without errors, headless
# - the HUD reads PlayerStats (stub and fake), shows the level, flashes when health falls, and hides
#   during the opening card and the epilogue
# - coin as crowns, gold, silver and copper
# - the inventory panel: quality, durability, maker, the stolen marker, equip / unequip; the skills
#   page beside it: skills, derived level, perks, deaths, difficulty
# - the crafting panel at a station: recipes, inputs, quality preview, make; cooking through Crafting.cook
# - the puzzle card's four shapes (choose, arrange, name, decode) answering through Puzzles.answer
# - the difficulty choice at a new game sets PlayerStats.difficulty, and the opening still plays
# - with the Phase 0 stubs nothing errors
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_player_systems_ui.gd

const UI = preload("res://scripts/ui/player_ui.gd")
const CHAPEL = "thornhaven_chapel"

class FakeStats extends Node:
	var difficulty: String = "normal"
	var health: float = 80.0
	var deaths: int = 2
	var skills = {"blades": 31.5, "smithing": 52.0}
	func get_health() -> float: return health
	func get_max_health() -> float: return 120.0
	func get_stamina() -> float: return 45.0
	func get_max_stamina() -> float: return 130.0
	func get_level() -> int: return 3
	func get_skill(skill: String) -> float: return skills.get(skill, 0.0)
	func has_perk(id: String) -> bool: return id == "makers_mark"
	func get_perks() -> Array: return ["makers_mark"]

class FakeInventory extends Node:
	signal changed()
	var coin: int = 2 * 10000 + 3 * 100 + 5
	var equipped: Dictionary = {}
	var calls: Array = []
	var items: Array = [
		{"id": "iron_knife", "qty": 1, "quality": 72, "durability": 18, "max_durability": 40, "maker": "bjorn", "provenance": {"from": "bjorn", "stolen": false}},
		{"id": "ranger_sword", "qty": 1, "quality": 55, "durability": 30, "max_durability": 60, "maker": "", "provenance": {"from": "fort", "stolen": true, "owner": "aldric"}},
		{"id": "fever_root", "qty": 3, "quality": 40, "provenance": {}},
	]
	func get_items() -> Array: return items
	func get_coin() -> int: return coin
	func has(id: String, qty: int = 1) -> bool:
		return items.any(func(i): return i.id == id and i.qty >= qty)
	func get_equipped(slot: String) -> Dictionary: return equipped.get(slot, {})
	func equip(id: String, slot: String) -> bool:
		calls.append(["equip", id, slot])
		if id == "":
			equipped.erase(slot)
		else:
			equipped[slot] = items.filter(func(i): return i.id == id)[0]
		changed.emit()
		return true
	func get_item_def(id: String) -> Dictionary:
		return {"iron_knife": {"name": "Iron knife", "kind": "weapon"}, "ranger_sword": {"name": "Ranger's sword", "kind": "weapon"},
			"fever_root": {"name": "Fever-root", "kind": "material"}}.get(id, {})

class FakeCrafting extends Node:
	var crafted: Array = []
	var cooked: Array = []
	func get_recipes(station: String) -> Array:
		return [{"id": "iron_knife", "name": "Iron knife", "station": station, "inputs": {"iron_bar": 1}, "skill": "smithing", "min_level": 10},
			{"id": "nails", "name": "Nails", "station": station, "inputs": [{"id": "iron_bar", "qty": 2}], "skill": "smithing", "min_level": 0}]
	func can_craft(recipe: String, _station: String) -> Dictionary:
		return {"ok": recipe == "nails", "reason": "" if recipe == "nails" else "You need an iron bar."}
	func craft(recipe: String, station: String) -> Dictionary:
		crafted.append([recipe, station])
		return {"ok": true, "item": {"id": recipe, "quality": 61}, "reason": ""}
	func cook(ingredients: Array, station: String) -> Dictionary:
		cooked.append([ingredients, station])
		return {"ok": true, "item": {"id": "fever_broth", "quality": 30}, "reason": ""}

class FakePuzzles extends Node:
	var answers: Array = []
	var defs = {
		"tiles": {"title": "Weigh the tiles", "prompt": "Which tile is light?", "answer_kind": "choose", "options": [{"id": "t1", "label": "The first"}, {"id": "t2", "label": "The second"}]},
		"tally": {"title": "The tally sticks", "shape": "arrange", "options": ["spring", "summer", "autumn"]},
		"marks": {"title": "The maker's marks", "answer": {"kind": "name"}, "prompt": "Whose hand?"},
		"ledger": {"title": "Gregor's ledger", "answer_kind": "decode", "cipher": "XLI JMZI CIEVW"},
	}
	func get_puzzle(id: String) -> Dictionary: return defs.get(id, {})
	func answer(id: String, a) -> Dictionary:
		answers.append([id, a])
		var right = {"tiles": "t2", "tally": ["summer", "spring", "autumn"], "marks": "Davin", "ledger": "the five years"}
		var ok = str(right.get(id)) == str(a) if not a is String else str(right.get(id)).to_lower() == a.to_lower()
		return {"ok": ok, "flag": "%s_solved" % id if ok else "", "reason": "" if ok else "That is not it."}

var failures: int = 0
var scene_manager: Node
var player_ui: Node
var world_state: Node

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	world_state.set_idle_clock_rate(0.0)
	var director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	scene_manager = root.get_node("SceneManager")
	scene_manager.npc_spawner.initialize_spawned = false
	var saved_flags = world_state.world_flags.duplicate(true)
	var saved_npc_states = world_state.npc_states.duplicate(true)
	var saved_minutes = world_state.game_minutes
	var saved_fired = world_state._calendar_fired.duplicate()
	var save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	print("============================================================")
	print("🧪 PLAYER SYSTEMS UI TEST")
	print("============================================================\n")

	player_ui = scene_manager.get_node_or_null("PlayerUI")
	_check("PlayerUI hangs under SceneManager", player_ui != null)
	if player_ui == null:
		quit(1)
		return
	_check("It builds the HUD and the four panels", player_ui.hud != null and player_ui.inventory_panel != null and player_ui.crafting_panel != null
		and player_ui.puzzle_card != null and player_ui.difficulty_choice != null)
	_test_keys()
	_test_coin()
	_test_hud()
	_test_inventory()
	_test_crafting()
	_test_puzzles()
	_test_difficulty_and_opening()
	_test_stubs()

	var opening = scene_manager.opening
	opening.reset()
	world_state.load_calendar()
	world_state.world_flags = saved_flags
	world_state.npc_states = saved_npc_states
	world_state.game_minutes = saved_minutes
	world_state._calendar_fired = saved_fired
	paused = false
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _test_keys():
	print("Keys")
	var keys = {}
	for action in ["inventory", "craft", "ui_cancel", "open_journal", "inner_voice", "interact"]:
		for e in InputMap.action_get_events(action):
			if e is InputEventKey and e.physical_keycode != 0:
				keys[e.physical_keycode] = keys.get(e.physical_keycode, []) + [action]
	_check("I opens the pack, B the station", _bound("inventory", KEY_I) and _bound("craft", KEY_B))
	_check("No key shared between the panels, Esc, the journal, thoughts and interact", keys.values().all(func(a): return a.size() == 1))

func _test_coin():
	print("\nCoin")
	_check("0 → 0 copper", UI.format_coin(0) == "0 copper")
	_check("1 → 1 copper", UI.format_coin(1) == "1 copper")
	_check("100 → 1 silver", UI.format_coin(100) == "1 silver")
	_check("10,000 → 1 gold", UI.format_coin(10000) == "1 gold")
	_check("1,000,000 → 1 crown", UI.format_coin(1000000) == "1 crown")
	_check("1,010,203 → 1 crown, 1 gold, 2 silver, 3 copper", UI.format_coin(1010203) == "1 crown, 1 gold, 2 silver, 3 copper")
	_check("2,000,000 → 2 crowns", UI.format_coin(2000000) == "2 crowns")

func _test_hud():
	print("\nHUD")
	var hud = player_ui.hud
	hud.stats = null
	hud.refresh()
	_check("Reads the PlayerStats stub: 100 / 100 health and stamina, level 0", hud.get_health_text() == "100 / 100" and hud.get_stamina_text() == "100 / 100"
		and hud.get_level_text() == "Level 0")
	var fake = FakeStats.new()
	root.add_child(fake)
	hud.stats = fake
	hud.refresh()
	_check("Reads a real-shaped PlayerStats: health, stamina, level", hud.get_health_text() == "80 / 120" and hud.get_stamina_text() == "45 / 130" and hud.get_level_text() == "Level 3")
	var before = hud.hit_flashes
	fake.health = 62.0
	hud.refresh()
	_check("A fall in health flashes", hud.hit_flashes == before + 1)
	hud.refresh()
	fake.health = 70.0
	hud.refresh()
	_check("...once, and not for healing", hud.hit_flashes == before + 1)
	hud.stats = null
	fake.queue_free()
	player_ui._process(0.0)
	_check("Shown over the world", hud.visible)
	player_ui.epilogue_screen.is_open = true
	player_ui._process(0.0)
	_check("Hidden during the epilogue", not hud.visible)
	player_ui.epilogue_screen.is_open = false
	player_ui._process(0.0)

func _test_inventory():
	print("\nInventory panel")
	var panel = player_ui.inventory_panel
	var fake = FakeInventory.new()
	root.add_child(fake)
	panel.inventory = fake
	paused = false
	_press(player_ui, "inventory", true)
	_check("I opens it over the world, and it pauses", panel.is_open and paused and player_ui.is_panel_open())
	_check("The menu will not open over it", not player_ui.can_open_menu())
	_check("Coin in gold, silver and copper", panel.get_coin_text() == "Coin: 2 gold, 3 silver, 5 copper")
	var lines: Array = panel.get_item_lines()
	_check("An item shows quality, durability and maker", lines.any(func(l): return l.contains("Iron knife") and l.contains("fine (72)") and l.contains("18/40") and l.contains("made by Bjorn")))
	_check("A stolen item is marked; an honest one is not", lines.any(func(l): return l.contains("Ranger's sword") and l.contains("stolen"))
		and not lines.any(func(l): return l.contains("Iron knife") and l.contains("stolen")))
	_check("A stack shows its count", lines.any(func(l): return l.contains("Fever-root ×3")))
	panel.equip(fake.items[0], "main_hand")
	_check("Equip goes through Inventory.equip to the weapon's slot", fake.calls[-1] == ["equip", "iron_knife", "main_hand"] and panel.is_equipped(fake.items[0]))
	panel.unequip("main_hand")
	_check("Unequip empties the slot", fake.calls[-1] == ["equip", "", "main_hand"] and fake.get_equipped("main_hand").is_empty())
	_check("Material is carried, not worn", panel.slot_for(fake.items[2]) == "")
	var stats = FakeStats.new()
	root.add_child(stats)
	panel.skills_page.stats = stats
	panel.show_tab("skills")
	var text: String = panel.skills_page.get_text()
	_check("Skills page: level, difficulty and deaths", text.contains("Level 3") and text.contains("Normal") and text.contains("died 2 times"))
	_check("...every skill with its level", text.contains("Blades") and text.contains("31") and text.contains("Smithing") and text.contains("52") and text.contains("Lore"))
	_check("...and the perks unlocked", text.contains("Makers Mark"))
	stats.difficulty = "hard"
	panel.skills_page.refresh()
	_check("...hard when chosen", panel.skills_page.get_text().contains("Hard"))
	panel.show_tab("pack")
	_press(panel, "inventory", false)
	_check("I closes it and the world goes on", not panel.is_open and not paused)
	panel.open()
	_press(panel, "ui_cancel", false)
	_check("Esc closes it", not panel.is_open and not paused)
	panel.inventory = null
	panel.skills_page.stats = null
	fake.queue_free()
	stats.queue_free()

func _test_crafting():
	print("\nCrafting panel")
	var panel = player_ui.crafting_panel
	var crafting = FakeCrafting.new()
	var inv = FakeInventory.new()
	var stats = FakeStats.new()
	for n in [crafting, inv, stats]:
		root.add_child(n)
	panel.crafting = crafting
	panel.inventory = inv
	panel.stats = stats
	paused = false
	_press(player_ui, "craft", true)
	_check("B with no station in reach says so and opens nothing", not panel.is_open and player_ui.hud.get_note() != "")
	_check("At a station it opens and pauses", player_ui.open_crafting("forge") and panel.is_open and paused)
	_check("The station's recipes are listed", panel.get_recipe_names() == ["iron_knife", "nails"])
	var knife: Dictionary = crafting.get_recipes("forge")[0]
	_check("Inputs in either shape", panel.inputs_of(knife) == {"iron_bar": 1} and panel.inputs_of(crafting.get_recipes("forge")[1]) == {"iron_bar": 2})
	var preview: Dictionary = panel.preview_quality(knife)
	_check("A quality preview from the skill, marked as a guess", preview.quality == 52 and preview.guess)
	var made: Dictionary = panel.craft("nails")
	_check("Make goes through Crafting.craft at this station", made.ok and crafting.crafted == [["nails", "forge"]] and panel.get_message().contains("Nails"))
	panel.show_mode("cook")
	_check("Cooking lists what can go in the pot", panel.ingredients() == ["fever_root"])
	panel.toggle_ingredient(true, "fever_root")
	var cooked: Dictionary = panel.cook_selected()
	_check("Combine goes through Crafting.cook", cooked.ok and crafting.cooked == [[["fever_root"], "forge"]] and panel.get_message().contains("Fever Broth"))
	for i in 6:
		panel.toggle_ingredient(true, "thing_%d" % i)
	_check("No more than five in the pot", panel.selected.size() == 5)
	panel.show_mode("make")
	_press(panel, "craft", false)
	_check("B closes it", not panel.is_open and not paused)
	player_ui.open_crafting("forge")
	_press(panel, "ui_cancel", false)
	_check("Esc closes it", not panel.is_open and not paused)
	panel.crafting = null
	panel.inventory = null
	panel.stats = null
	for n in [crafting, inv, stats]:
		n.queue_free()

func _test_puzzles():
	print("\nPuzzle card")
	var card = player_ui.puzzle_card
	var fake = FakePuzzles.new()
	root.add_child(fake)
	card.puzzles = fake
	paused = false
	player_ui.open_puzzle("tiles")
	_check("It opens, pauses, and reads the shape: choose", card.is_open and paused and card.shape == "choose")
	card.choose("t1")
	var wrong: Dictionary = card.submit()
	_check("A wrong answer keeps it open with the reason", not wrong.ok and card.is_open and card.get_message() == "That is not it.")
	card.choose("t2")
	_check("Choose answers the option id", card.submit().ok and fake.answers[-1] == ["tiles", "t2"] and not card.is_open and not paused)
	player_ui.open_puzzle("tally")
	_check("arrange", card.shape == "arrange" and card.order == ["spring", "summer", "autumn"])
	card.move(1, -1)
	_check("Arrange answers the order", card.submit().ok and fake.answers[-1] == ["tally", ["summer", "spring", "autumn"]])
	player_ui.open_puzzle("marks")
	_check("name", card.shape == "name")
	card.set_text("  Davin ")
	_check("Name answers the text", card.submit().ok and fake.answers[-1] == ["marks", "Davin"])
	player_ui.open_puzzle("ledger")
	_check("decode shows the cipher", card.shape == "decode" and card.get_node("Center/Frame").find_child("Cipher", true, false).text == "XLI JMZI CIEVW")
	card.set_text("the five years")
	_check("Decode answers the text", card.submit().ok and fake.answers[-1] == ["ledger", "the five years"])
	player_ui.open_puzzle("ledger")
	_press(card, "ui_cancel", false)
	_check("Esc leaves it", not card.is_open and not paused)
	card.puzzles = null
	fake.queue_free()

func _test_difficulty_and_opening():
	print("\nDifficulty and the opening")
	var stats = root.get_node("PlayerStats")
	var choice = player_ui.difficulty_choice
	_check("Headless nobody is asked (nobody is there to answer)", DisplayServer.get_name() != "headless" or not player_ui.ask_difficulty)
	choice.open()
	_check("The choice pauses the world", choice.is_open and paused)
	choice.choose("hard")
	_check("Hard sets PlayerStats.difficulty", stats.difficulty == "hard" and not choice.is_open and not paused)
	choice.open()
	_press(choice, "ui_cancel", false)
	_check("Esc keeps normal", stats.difficulty == "normal" and not choice.is_open)

	# A new game: the opening starts, the choice comes first, the chapel card waits beneath it
	var opening = scene_manager.opening
	opening.reset()
	world_state.load_calendar()
	world_state.world_flags = {}
	world_state.npc_states = {}
	world_state.reset_calendar(world_state.start_minute)
	var chapel = scene_manager.locations.get(CHAPEL)
	scene_manager.locations.erase(CHAPEL)  # no chapel scene headless: play() shows the card where it stands
	player_ui.ask_difficulty = true
	player_ui._difficulty_asked = false
	opening.play()
	scene_manager.locations[CHAPEL] = chapel
	_check("At a new game the choice opens with the opening", choice.is_open)
	_check("...and the establishing card still shows beneath it", opening.get_card_kind() == "establishing" and choice.layer > 100)
	player_ui._process(0.0)
	_check("The HUD hides while the card is up", not player_ui.hud.visible)
	choice.choose("hard")
	_check("Choosing sets it and leaves the card", stats.difficulty == "hard" and opening.get_card_kind() == "establishing" and not paused)
	opening.skip()
	_check("The card hands control to the player as before", opening.phase == "awaiting" and not opening.is_card_open())
	player_ui._process(0.0)
	_check("...and the HUD comes back", player_ui.hud.visible)
	opening.reset()
	opening.play()
	_check("It is asked only once", not choice.is_open)
	opening.skip()
	player_ui.ask_difficulty = false
	stats.difficulty = "normal"

func _test_stubs():
	print("\nWith the Phase 0 stubs")
	paused = false
	_check("The pack opens empty", player_ui.open_inventory() and player_ui.inventory_panel.get_coin_text() == "Coin: 0 copper")
	player_ui.inventory_panel.show_tab("skills")
	_check("...the skills page lists the twelve at 0", player_ui.inventory_panel.skills_page.get_text().contains("Herbcraft") and player_ui.inventory_panel.skills_page.get_text().contains("never died"))
	player_ui.inventory_panel.show_tab("pack")
	player_ui.inventory_panel.close()
	_check("A station opens with nothing to make", player_ui.open_crafting("campfire") and player_ui.crafting_panel.get_recipe_names().is_empty())
	player_ui.crafting_panel.show_mode("cook")
	player_ui.crafting_panel.close()
	player_ui.crafting_panel.mode = "make"
	_check("A name-shaped puzzle card opens", player_ui.open_puzzle("makers_marks") and player_ui.puzzle_card.is_open)
	player_ui.puzzle_card.set_text("Nobody at all")
	var result: Dictionary = player_ui.puzzle_card.submit()
	var expected = str(result.reason) if str(result.get("reason", "")) != "" else "It does not fit."
	_check("...a wrong answer keeps it open with the reason (or the card's own word)", not result.ok and player_ui.puzzle_card.is_open and player_ui.puzzle_card.get_message() == expected)
	player_ui.puzzle_card.close()
	player_ui.puzzle_card.close()
	_check("All closed, the world unpaused", not player_ui.is_panel_open() and not paused)

# =============================================================================

func _press(node: Node, action: String, unhandled: bool) -> void:
	var ev = InputEventAction.new()
	ev.action = action
	ev.pressed = true
	if unhandled:
		node._unhandled_input(ev)
	else:
		node._input(ev)

func _bound(action: String, key: int) -> bool:
	return InputMap.has_action(action) and InputMap.action_get_events(action).any(func(e): return e is InputEventKey and e.physical_keycode == key)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
