extends SceneTree

# Tests Crafting and gathering (docs/PLAYER_SYSTEMS.md §4):
# - content loads (recipes, stations, nodes); Greystone ore, the story-gated deep vein
# - gathering: tools, stamina, yield by skill, skill gain, depletion and regrowth on the game clock
# - taking from someone's land or stores: theft about the owner, witnessed by line of sight; leave
#   from the owner's soul makes it honest
# - stations: leave decided by the owner's real soul (Bjorn refuses a stranger, grants one he
#   respects, and his ally:varn Line refuses work for Varn); public stations need no leave
# - working a station without leave: trespass, and theft of fuel when seen
# - recipes: discovered by holding the inputs at the station, taught, found by a flag
# - quality from skill, station grade and material grade; durability by quality; the maker's mark
# - crafting advances the clock, uses the skill, records crafted (witnessed) and a feat when it stands out
# - repair (durability back, quality and maker kept) and re-forge of a broken blade
# - cook delegates to Herbcraft.cook (or says it is not built yet); commissions; save/load
# Fakes only (PlayerStats / Inventory stand-ins, fake NPC bodies): no API calls, no ChromaDB, no save file
# Run: godot --headless --path . -s res://scripts/debug/test_crafting.gd

const StationScript = preload("res://scripts/crafting/station.gd")
const NodeScript = preload("res://scripts/crafting/resource_node.gd")

class FakeStats extends RefCounted:
	var skills: Dictionary = {}
	var perks: Array = []
	var stamina: float = 100.0
	var calls: Array = []
	func use_skill(skill: String, difficulty_factor: float = 1.0, context: Dictionary = {}) -> Dictionary:
		var level = float(skills.get(skill, 0.0))
		var gain = 2.0 * difficulty_factor * (1.0 - level / 110.0)
		skills[skill] = minf(100.0, level + gain)
		calls.append({"skill": skill, "difficulty": difficulty_factor, "context": context})
		return {"gained": gain, "level": skills[skill], "milestone": 0}
	func get_skill(skill: String) -> float:
		return float(skills.get(skill, 0.0))
	func has_perk(perk_id: String) -> bool:
		return perk_id in perks
	func spend_stamina(amount: float) -> bool:
		if stamina < amount:
			return false
		stamina -= amount
		return true

class FakeInventory extends RefCounted:
	var records: Array = []
	var equipped: Dictionary = {}
	func add(item_id: String, qty: int = 1, props: Dictionary = {}) -> bool:
		var r = {"id": item_id, "qty": qty, "quality": 50, "durability": 0.0, "max_durability": 0.0, "maker": "",
			"provenance": {"from": "", "stolen": false, "owner": ""}}
		for k in props:
			r[k] = props[k]
		records.append(r)
		return true
	func count(item_id: String) -> int:
		var n = 0
		for r in records:
			if r.id == item_id:
				n += int(r.qty)
		return n
	func has(item_id: String, qty: int = 1) -> bool:
		return count(item_id) >= qty
	## The most worn first, so a repair takes the record it mends
	func remove(item_id: String, qty: int = 1) -> bool:
		if not has(item_id, qty):
			return false
		var mine = records.filter(func(r): return r.id == item_id)
		mine.sort_custom(func(a, b): return float(a.durability) < float(b.durability))
		for r in mine:
			if qty <= 0:
				break
			var take = mini(qty, int(r.qty))
			r.qty -= take
			qty -= take
			if r.qty <= 0:
				records.erase(r)
		return true
	func get_items() -> Array:
		return records.map(func(r): return r.duplicate(true))
	func get_equipped(slot: String) -> Dictionary:
		return equipped.get(slot, {})
	func wear(slot: String, amount: float = 1.0) -> Dictionary:
		if equipped.has(slot):
			equipped[slot].durability = float(equipped[slot].get("durability", 0)) - amount
		return {"broke": false}
	## Inventory.repair: the most worn record, broken first, fully
	func repair(item_id: String, _amount: float = -1.0) -> bool:
		var mine = records.filter(func(r): return r.id == item_id and float(r.durability) < float(r.max_durability))
		if mine.is_empty():
			return false
		mine.sort_custom(func(a, b): return float(a.durability) < float(b.durability))
		mine[0].durability = mine[0].max_durability
		mine[0].erase("broken")
		return true
	func get_definition(item_id: String) -> Dictionary:
		return {"id": item_id, "kind": "weapon" if item_id in ["arming_sword", "fighting_knife"] else "material"}
	func clear() -> void:
		records.clear()

class _FakeUI extends Node:
	var opened: String = ""
	func open_crafting(station_id: String) -> void:
		opened = station_id

class _Body extends Node2D:
	var npc_id: String = ""
	var is_alive: bool = true

var failures: int = 0
var crafting: Node
var world_state: Node
var director: Node
var pe: Node
var stats: FakeStats
var inv: FakeInventory

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	world_state.set_idle_clock_rate(0.0)
	director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	pe = root.get_node("PlayerEvents")
	crafting = root.get_node("Crafting")
	stats = FakeStats.new()
	inv = FakeInventory.new()
	crafting.stats_override = stats
	crafting.inventory_override = inv
	crafting.reset()
	print("============================================================")
	print("🧪 CRAFTING TEST")
	print("============================================================\n")

	_content()
	await _gathering()
	await _theft()
	await _leave()
	await _trespass()
	_recipes()
	await _quality_and_deeds()
	await _repair()
	_cook()
	_commissions()
	_save_load()

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# -----------------------------------------------------------------------------

func _content() -> void:
	print("Content")
	_check("Recipes, stations and nodes load", crafting.recipes.size() >= 15 and crafting.stations.size() >= 8 and crafting.nodes.size() >= 8)
	_check("Bjorn's forge is a forge he owns", crafting.get_station("bjorn_forge").get("owner", "") == "bjorn" and crafting.get_station("bjorn_forge").kind == "forge")
	_check("Greystone yields iron ore", crafting.nodes_at("greystone_mines").any(func(id): return crafting.get_node_def(id).item == "iron_ore"))
	_check("The deep vein is shut until the story opens it", not crafting.node_exists("greystone_deep_vein_salt") and not "greystone_deep_vein_salt" in crafting.nodes_at("greystone_mines"))
	world_state.set_world_flag("vein_deep_vein_reopened", true)
	_check("...and there once it is (vein_deep_vein_reopened)", crafting.node_exists("greystone_deep_vein_salt"))
	world_state.set_world_flag("vein_deep_vein_reopened", false)

func _gathering() -> void:
	print("\nGathering")
	crafting.player_location_override = "greystone_mines"
	var r = crafting.gather("greystone_old_workings")
	_check("No pick, no ore", not r.ok and "pick" in r.reason)
	inv.add("pick", 1, {"durability": 50.0, "max_durability": 50.0})
	inv.equipped["tool"] = {"id": "pick", "durability": 50.0}
	crafting.player_location_override = "forest_path"
	_check("Not from another place", not crafting.gather("greystone_old_workings").ok)
	crafting.player_location_override = "greystone_mines"
	var t0 = world_state.get_game_minutes()
	r = crafting.gather("greystone_old_workings")
	_check("A take of iron ore", r.ok and r.item.id == "iron_ore" and r.qty == 1 and inv.count("iron_ore") == 1)
	_check("...took the node's game minutes", world_state.get_game_minutes() - t0 == 45)
	_check("...raised mining (PlayerStats.use_skill)", stats.get_skill("mining") > 0.0 and stats.calls.back().skill == "mining")
	_check("...wore the pick and spent stamina", inv.equipped.tool.durability < 50.0 and stats.stamina < 100.0)
	_check("...honest ore: not stolen, nobody's", r.stolen == false and r.item.provenance.stolen == false)
	_check("The node has one take fewer", crafting.node_available("greystone_old_workings") == 3)
	for i in 3:
		crafting.gather("greystone_old_workings")
	r = crafting.gather("greystone_old_workings")
	_check("Depleted after its charges", not r.ok and "bare" in r.reason and crafting.node_available("greystone_old_workings") == 0)
	var regrow = int(crafting.nodes.greystone_old_workings.regrow_minutes)
	var back_at = crafting.node_regrows_at("greystone_old_workings")
	_check("...grows back on the game clock", back_at > world_state.get_game_minutes() and back_at <= world_state.get_game_minutes() + regrow)
	crafting.nodes.greystone_old_workings.regrow_minutes = 60   # test speed: an hour per take
	world_state.advance_time(60, "test")
	_check("One take back after its regrow time", crafting.node_available("greystone_old_workings") >= 1)
	world_state.advance_time(60 * 5, "test")
	_check("Fully grown back given time", crafting.node_available("greystone_old_workings") == 4)
	crafting.nodes.greystone_old_workings.regrow_minutes = regrow
	stats.skills["mining"] = 70.0
	r = crafting.gather("greystone_old_workings")
	_check("A skilled miner takes more (yield by skill)", r.ok and r.qty == 1 + 2)
	_check("...and better ore", r.item.quality > int(crafting.nodes.greystone_old_workings.grade))
	stats.stamina = 0.0
	_check("Too tired to dig", not crafting.gather("greystone_old_workings").ok)
	stats.stamina = 100.0

func _theft() -> void:
	print("\nTaking from someone's land or stores")
	var scene = Node2D.new()
	root.add_child(scene)
	var face = NodeScript.new()
	face.node_id = "greystone_ore_face"
	face.position = Vector2(0, 0)
	scene.add_child(face)
	var dagna = _npc("dagna_foreman_001", Vector2(80, 0))
	scene.add_child(dagna)
	await physics_frame
	await physics_frame
	var before = pe.get_events().size()
	var r = face.interact()
	var theft = _last_event("theft")
	_check("Ore from Dagna's working face is stolen", r.ok and r.stolen and r.item.provenance.stolen and r.item.provenance.owner == "dagna")
	_check("...a theft deed about Dagna", theft.get("about", []).has("dagna") and pe.get_events().size() > before)
	_check("...witnessed by line of sight (she saw it)", "dagna_foreman_001" in theft.get("witnesses", []))
	dagna.position = Vector2(5000, 0)
	await physics_frame
	r = face.interact()
	theft = _last_event("theft")
	_check("Unseen, it is still theft, with no witnesses", r.stolen and theft.get("witnesses", ["x"]).is_empty() and r.events.size() == 1)
	director.relationship_dims_override["dagna"] = {"respect": 40.0, "trust": 30.0}
	var leave = await crafting.ask_leave("greystone_ore_face")
	_check("Dagna's soul gives leave to one she respects", leave.granted and leave.choice == "grant")
	r = face.interact()
	_check("...and then the ore is honest (no theft)", r.ok and not r.stolen and r.events.is_empty())
	crafting.player_location_override = "thornhaven_gregor_shop"
	r = crafting.gather("gregor_stock_charcoal")
	_check("Gregor's stock taken is theft about Gregor", r.ok and r.stolen and _last_event("theft").about.has("gregor"))
	director.relationship_dims_override.erase("dagna")
	scene.queue_free()
	await process_frame

func _leave() -> void:
	print("\nStation leave, decided by the owner's soul")
	crafting.leave.clear()
	director.relationship_dims_override.erase("bjorn")
	var r = await crafting.ask_leave("bjorn_forge")
	_check("Bjorn refuses a stranger his forge", not r.granted and r.choice == "refuse" and crafting.leave_status("bjorn_forge") == "refused")
	var again = await crafting.ask_leave("bjorn_forge")
	_check("...and the refusal stands for the day (not asked again)", not again.granted and again.decision.is_empty())
	crafting.leave.clear()
	director.relationship_dims_override["bjorn"] = {"respect": 40.0, "trust": 20.0}
	r = await crafting.ask_leave("bjorn_forge")
	_check("Bjorn gives leave to one he respects", r.granted and r.choice == "grant" and crafting.leave_status("bjorn_forge") == "granted")
	crafting.leave.clear()
	r = await crafting.ask_leave("bjorn_forge", {"for": "varn"})
	_check("His ally:varn Line refuses forging for Varn's men", not r.granted and r.choice == "refuse")
	var hook = crafting.leave_hook("bjorn_forge", {"for": "varn"})
	_check("...the grant option is tagged aids: varn", hook.options.any(func(o): return o.id == "grant" and o.get("aids", "") == "varn"))
	_check("A public loom needs no leave", (await crafting.ask_leave("thornhaven_loom")).granted and crafting.leave_status("thornhaven_loom") == "public")
	_check("Leave lapses after three days", _lapses())
	crafting.leave.clear()
	director.relationship_dims_override.erase("bjorn")

func _lapses() -> bool:
	crafting.leave["bjorn_forge"] = {"granted": true, "minute": world_state.get_game_minutes() - crafting.LEAVE_MINUTES - 1, "choice": "grant", "reason": ""}
	return crafting.leave_status("bjorn_forge") == "none"

func _trespass() -> void:
	print("\nWorking a station without leave")
	crafting.player_location_override = "thornhaven_blacksmith"
	inv.clear()
	inv.add("iron_ore", 2, {"quality": 60})
	inv.add("charcoal", 1, {"quality": 50})
	var c = crafting.can_craft("smelt_steel", "bjorn_forge")
	_check("Can work it, but it would be trespass", c.ok and c.trespass and c.leave == "none")
	var r = crafting.craft("smelt_steel", "bjorn_forge")
	var tres = _last_event("trespass")
	_check("Trespass about Bjorn, unseen", r.ok and tres.get("about", []).has("bjorn") and tres.witnesses.is_empty())
	_check("...no theft of fuel when nobody saw", not r.events.any(func(id): return pe.get_event(id).kind == "theft"))
	var scene = Node2D.new()
	root.add_child(scene)
	var forge = StationScript.new()
	forge.station_id = "bjorn_forge"
	scene.add_child(forge)
	scene.add_child(_npc("bjorn_blacksmith_001", Vector2(60, 0)))
	await physics_frame
	await physics_frame
	inv.add("iron_ore", 2, {"quality": 60})
	inv.add("charcoal", 1, {"quality": 50})
	r = forge.craft("smelt_steel")
	var kinds = r.events.map(func(id): return pe.get_event(id).kind)
	_check("Seen by Bjorn: trespass and theft of his charcoal", "trespass" in kinds and "theft" in kinds)
	_check("...both witnessed by him", r.events.all(func(id): return "bjorn_blacksmith_001" in pe.get_event(id).witnesses))
	crafting.leave["bjorn_forge"] = {"granted": true, "minute": world_state.get_game_minutes(), "choice": "grant", "reason": ""}
	inv.add("iron_ore", 2, {"quality": 60})
	inv.add("charcoal", 1, {"quality": 50})
	r = forge.craft("smelt_steel")
	kinds = r.events.map(func(id): return pe.get_event(id).kind)
	_check("With leave: no trespass, no theft", r.ok and not "trespass" in kinds and not "theft" in kinds)
	crafting.leave.clear()
	scene.queue_free()
	await process_frame

func _recipes() -> void:
	print("\nRecipes: discovered, taught, found")
	crafting.known.clear()
	inv.clear()
	crafting.player_location_override = "thornhaven_blacksmith"
	inv.add("iron_ore", 2)
	inv.add("charcoal", 1)
	var found = crafting.discover("bjorn_forge")
	_check("Holding ore and charcoal at a forge shows smelting", "smelt_steel" in found)
	_check("...not the knife (no steel, no wood yet)", not "forge_knife" in found and not crafting.is_known("forge_knife"))
	_check("Not at a loom", crafting.discover("thornhaven_loom").is_empty())
	inv.add("steel_bar", 3)
	inv.add("wood", 1)
	inv.add("hide", 1)
	stats.skills["smithing"] = 30.0
	var c = crafting.can_craft("forge_arming_sword", "bjorn_forge")
	_check("The arming sword is taught, not discovered", not c.ok and "know" in c.reason and not "forge_arming_sword" in crafting.discover("bjorn_forge"))
	crafting.learn_recipe("forge_arming_sword", "taught")
	_check("...known once taught", crafting.can_craft("forge_arming_sword", "bjorn_forge").ok)
	_check("The mail shirt is found (Ashguard's ledger)", not crafting.is_known("forge_mail_shirt"))
	world_state.set_world_flag("ashguard_ledger_read", true)
	_check("...known once ashguard_ledger_read", crafting.is_known("forge_mail_shirt"))
	world_state.set_world_flag("ashguard_ledger_read", false)
	stats.skills["smithing"] = 10.0
	_check("Below the minimum level it is refused", "smithing 25" in crafting.can_craft("forge_arming_sword", "bjorn_forge").reason)
	_check("Made at the right kind of station only", not crafting.can_craft("forge_knife", "mill_workbench").ok)
	var listed = crafting.recipes_at("bjorn_forge")
	_check("The station lists what the player knows", listed.any(func(x): return x.id == "smelt_steel"))
	var full = crafting.get_recipes("bjorn_forge")
	var smelt = full.filter(func(x): return x.id == "smelt_steel")
	_check("get_recipes gives full recipe dicts with ok and quality", smelt.size() == 1 and smelt[0].has("inputs") and smelt[0].has("ok") and smelt[0].has("quality"))
	var q = crafting.preview_quality("smelt_steel", "bjorn_forge")
	_check("preview_quality matches the formula", q == crafting.quality_for(crafting.recipes.smelt_steel, stats.get_skill("smithing"), 75.0, crafting.material_grade(crafting.recipes.smelt_steel.inputs)) and q > 0 and q <= 100)
	_check("...0 for an unknown recipe", crafting.preview_quality("no_such", "bjorn_forge") == 0)
	var others = get_nodes_in_group("player_ui")
	for o in others:
		o.remove_from_group("player_ui")
	var ui = _FakeUI.new()
	ui.add_to_group("player_ui")
	root.add_child(ui)
	var st = StationScript.new()
	st.station_id = "bjorn_forge"
	root.add_child(st)
	st.interact()
	_check("Using a station joins crafting_stations and opens the panel (player_ui.open_crafting)", st.is_in_group("crafting_stations") and ui.opened == "bjorn_forge")
	st.queue_free()
	ui.queue_free()
	for o in others:
		o.add_to_group("player_ui")

func _quality_and_deeds() -> void:
	print("\nQuality, the mark, the clock, deeds")
	var r = crafting.recipes.forge_knife
	_check("More skill, better work", crafting.quality_for(r, 80, 60, 50) > crafting.quality_for(r, 20, 60, 50))
	_check("A better forge, better work", crafting.quality_for(r, 50, 75, 50) > crafting.quality_for(r, 50, 55, 50))
	_check("Better steel, better work", crafting.quality_for(r, 50, 60, 90) > crafting.quality_for(r, 50, 60, 30))
	crafting.player_location_override = "thornhaven_blacksmith"
	crafting.leave["bjorn_forge"] = {"granted": true, "minute": world_state.get_game_minutes(), "choice": "grant", "reason": ""}
	var scene = Node2D.new()
	root.add_child(scene)
	var forge = StationScript.new()
	forge.station_id = "bjorn_forge"
	scene.add_child(forge)
	scene.add_child(_npc("bjorn_blacksmith_001", Vector2(60, 0)))
	await physics_frame
	await physics_frame
	inv.clear()
	stats.skills["smithing"] = 20.0
	stats.perks.clear()
	inv.add("steel_bar", 1, {"quality": 40})
	inv.add("wood", 1, {"quality": 40})
	var t0 = world_state.get_game_minutes()
	var calls = stats.calls.size()
	var plain = crafting.craft("forge_knife", "bjorn_forge")
	_check("A knife is forged", plain.ok and inv.count("knife") == 1 and inv.count("steel_bar") == 0)
	_check("...taking the recipe's game minutes", world_state.get_game_minutes() - t0 == int(r.minutes))
	_check("...using smithing", stats.calls.size() == calls + 1 and stats.calls.back().skill == "smithing")
	_check("...durability left to Inventory (the item definition, by quality)", not plain.item.has("durability"))
	_check("...no maker's mark without the perk", plain.item.maker == "")
	var crafted_ev = _last_event("crafted")
	_check("A crafted deed, seen by Bjorn", "bjorn_blacksmith_001" in crafted_ev.get("witnesses", []) and "knife" in crafted_ev.summary)
	_check("...plain work is no feat", not plain.events.any(func(id): return pe.get_event(id).kind == "feat"))
	stats.skills["smithing"] = 100.0
	stats.perks = ["smithing_50_makers_mark"]
	inv.add("steel_bar", 1, {"quality": 95})
	inv.add("wood", 1, {"quality": 90})
	var fine = crafting.craft("forge_knife", "bjorn_forge")
	_check("A master's knife is better", fine.ok and fine.quality > plain.quality and fine.quality >= crafting.FEAT_QUALITY)
	_check("...carries the player's mark (makers_mark)", fine.item.maker == "player")
	var feat = _last_event("feat")
	_check("...a feat, witnessed by Bjorn", fine.events.has(feat.get("id", "")) and "bjorn_blacksmith_001" in feat.witnesses)
	var got: Array = []
	crafting.crafted.connect(func(item): got.append(item), CONNECT_ONE_SHOT)
	inv.add("steel_bar", 1)
	inv.add("wood", 1)
	crafting.craft("forge_knife", "bjorn_forge")
	_check("Crafting.crafted fires with the item", got.size() == 1 and got[0].id == "knife")
	crafting.leave.clear()
	scene.queue_free()
	await process_frame

func _repair() -> void:
	print("\nRepair and re-forge")
	inv.clear()
	crafting.player_location_override = "thornhaven_blacksmith"
	crafting.leave["bjorn_forge"] = {"granted": true, "minute": world_state.get_game_minutes(), "choice": "grant", "reason": ""}
	inv.add("knife", 1, {"quality": 77, "durability": 10.0, "max_durability": 80.0, "maker": "player"})
	var t0 = world_state.get_game_minutes()
	var r = crafting.repair("knife", "bjorn_forge")
	var knife = inv.get_items().filter(func(x): return x.id == "knife")
	_check("A worn knife is mended to full", r.ok and not r.reforged and knife.size() == 1 and knife[0].durability == 80.0)
	_check("...its quality and maker kept", knife[0].quality == 77 and knife[0].maker == "player")
	_check("...and it took time", world_state.get_game_minutes() > t0)
	_check("Nothing worn, nothing to mend", not crafting.repair("knife", "bjorn_forge").ok)
	inv.clear()
	inv.add("arming_sword", 1, {"quality": 88, "durability": 0.0, "max_durability": 150.0, "maker": "bjorn"})
	r = crafting.repair("arming_sword", "bjorn_forge")
	_check("A broken blade needs steel to re-forge", not r.ok and "steel bar" in r.reason)
	inv.add("steel_bar", 2)
	r = crafting.repair("arming_sword", "bjorn_forge")
	var sword = inv.get_items().filter(func(x): return x.id == "arming_sword")
	_check("...re-forged: durability back, quality kept, Bjorn's mark kept", r.ok and r.reforged and sword.size() == 1 and sword[0].durability == 150.0 and sword[0].quality == 88 and sword[0].maker == "bjorn")
	_check("...the steel was used", inv.count("steel_bar") == 0)
	inv.clear()
	inv.add("hunting_bow", 1, {"quality": 50, "durability": 5.0, "max_durability": 90.0})
	_check("A bow is mended at a workbench, not a forge", not crafting.repair("hunting_bow", "bjorn_forge").ok)
	crafting.leave.clear()

func _cook() -> void:
	print("\nCooking (Herbcraft.cook)")
	crafting.player_location_override = "healer_hut"
	inv.clear()
	inv.add("fever_root", 1)
	if not ResourceLoader.exists(crafting.HERBCRAFT_PATH):
		var none = crafting.cook(["fever_root"], "healer_herb_table")
		_check("No herbcraft.gd yet: {ok: false}", not none.ok and "not built" in none.reason)
	else:
		_check("herbcraft.gd exists: cook delegates to it", crafting.cook(["fever_root"], "healer_herb_table").has("ok"))
	var fake = GDScript.new()
	fake.source_code = "\n".join(["extends RefCounted",
		"static func cook(ids: Array, skill: float) -> Dictionary:",
		"\tif ids.has(\"white_salt\"):",
		"\t\treturn {\"item_id\": \"grey_fever_cure\", \"effects\": [\"cure\"], \"potency\": 80.0, \"quality\": 80, \"dubious\": false, \"name\": \"Grey Fever cure\"}",
		"\treturn {\"item_id\": \"root_tea\", \"effects\": [\"fever\"], \"potency\": 30.0 + ids.size() + skill, \"quality\": 35, \"dubious\": false}",
		"static func story_flag_for(item_id: String) -> String:",
		"\treturn \"grey_cure_recipe_known\" if item_id == \"grey_fever_cure\" else \"\"",
		"static func deed_for(item_id: String) -> String:",
		"\treturn \"steeped fever-root with deep-vein salt, the true cure for the Grey Fever\"", ""])
	fake.reload()
	crafting.herbcraft_override = fake
	stats.skills["herbcraft"] = 10.0
	var r = crafting.cook(["fever_root"], "healer_herb_table")
	_check("Delegated: Herbcraft's result goes into the pack", r.ok and r.item.id == "root_tea" and inv.count("root_tea") == 1 and inv.count("fever_root") == 0)
	_check("...with its potency and effects", r.item.potency == 41.0 and r.item.effects == ["fever"])
	_check("...with Herbcraft's quality", r.item.quality == 35)
	_check("...a plain remedy is no story act", not r.item.has("story_flag") and not r.events.any(func(id): return pe.get_event(id).kind == "feat"))
	inv.add("fever_root", 2)
	inv.add("white_salt", 2)
	r = crafting.cook(["fever_root", "white_salt"], "healer_herb_table")
	var feat = _last_event("feat")
	_check("The cure sets its story flag (grey_cure_recipe_known)", r.ok and world_state.get_world_flag("grey_cure_recipe_known") and r.item.story_flag == "grey_cure_recipe_known")
	_check("...and records Herbcraft's feat", r.events.has(feat.get("id", "")) and "true cure" in feat.summary)
	r = crafting.cook(["fever_root", "white_salt"], "healer_herb_table")
	_check("...only the first time", r.ok and not r.item.has("story_flag"))
	world_state.set_world_flag("grey_cure_recipe_known", false)
	_check("Not at a forge", not crafting.cook(["fever_root"], "bjorn_forge").ok)
	_check("Not without the ingredients", not crafting.cook(["white_salt"], "healer_herb_table").ok)
	crafting.herbcraft_override = null

func _commissions() -> void:
	print("\nCommissions")
	inv.clear()
	var day = world_state.get_day()
	var c = crafting.offer_commission("aldric", "arming_sword", day + 2)
	var promise = pe.get_event(c.event_id)
	_check("A commission is a promise with a due day", c.ok and promise.kind == "promise" and promise.status == "open" and int(promise.due.get("day", 0)) == day + 2)
	_check("...heard by Aldric", promise.about.has("aldric") and "aldric_peacekeeper_001" in promise.witnesses)
	_check("Nothing to deliver yet", not crafting.deliver_commission("aldric", "arming_sword").ok)
	inv.add("arming_sword", 1, {"quality": 92, "maker": "player", "durability": 150.0, "max_durability": 150.0})
	var d = crafting.deliver_commission("aldric", "arming_sword")
	var kinds = d.events.map(func(id): return pe.get_event(id).kind)
	_check("Delivered: help and a gift", d.ok and "help" in kinds and "gift" in kinds and inv.count("arming_sword") == 0)
	var gift = pe.get_event(d.events[kinds.find("gift")])
	_check("...the gift carries its quality and the maker", d.quality == 92 and "masterwork" in gift.summary and "own make" in gift.summary)
	_check("...the promise kept", pe.get_event(c.event_id).status == "kept" and crafting.get_commissions("delivered").size() == 1)
	inv.add("fighting_knife", 1, {"quality": 60})
	var g = crafting.give_item("varn", "fighting_knife")
	var help = g.events.map(func(id): return pe.get_event(id)).filter(func(e): return e.kind == "help")
	_check("A blade given to Varn is a gift and a help about him (arming the Hollow)", g.ok and help.size() == 1 and help[0].about.has("varn"))
	inv.add("wood", 1)
	_check("...wood is only a gift", crafting.give_item("varn", "wood").events.size() == 1)

func _save_load() -> void:
	print("\nSave / load")
	crafting.player_location_override = "forest_path"
	inv.clear()
	inv.add("wood", 3)
	var built = crafting.build_station("campfire", "forest_path")
	_check("The player builds a campfire of their own", built.ok and crafting.leave_status(built.station_id) == "own" and inv.count("wood") == 0)
	crafting.learn_recipe("forge_arming_sword", "taught")
	crafting.leave["bjorn_forge"] = {"granted": true, "minute": world_state.get_game_minutes(), "choice": "grant", "reason": "appeal"}
	crafting.player_location_override = "greystone_mines"
	stats.skills["mining"] = 0.0
	inv.add("pick", 1)
	_check("Stone from the spoil heap", crafting.gather("greystone_spoil_stone").ok)
	var saved = crafting.save()
	var through_json = JSON.parse_string(JSON.stringify(saved))
	crafting.reset()
	_check("Reset forgets", crafting.known.is_empty() and crafting.node_available("greystone_spoil_stone") == 10 and not crafting.stations.has(built.station_id))
	crafting.load_from_dict(through_json)
	_check("Known recipes restored", crafting.is_known("forge_arming_sword") and crafting.known.size() == saved.known.size())
	_check("Node depletion restored", crafting.node_available("greystone_spoil_stone") == 9)
	_check("Leave restored", crafting.leave_status("bjorn_forge") == "granted")
	_check("Commissions restored", crafting.get_commissions("delivered").size() == 1)
	_check("The player's campfire restored", crafting.stations.has(built.station_id) and crafting.get_station(built.station_id).owner == "player")
	_check("WorldState saves a Crafting block", world_state.save().get("player_systems", {}).get("Crafting", {}).has("known"))
	crafting.reset()
	crafting.stats_override = null
	crafting.inventory_override = null
	crafting.player_location_override = ""

# -----------------------------------------------------------------------------

func _last_event(kind: String) -> Dictionary:
	var all = pe.get_events()
	for i in range(all.size() - 1, -1, -1):
		if all[i].kind == kind:
			return all[i]
	return {}

func _npc(id: String, at: Vector2) -> Node2D:
	var n = _Body.new()
	n.npc_id = id
	n.position = at
	n.add_to_group("npcs")
	return n

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
