extends SceneTree

# Tests the Inventory (docs/PLAYER_SYSTEMS.md §2 the pack, §6 the player's tools):
# - item definitions (resources/items) load; coin is copper, 100 a silver, 100 silver a gold, 100 gold a crown
# - stacking by id/quality/maker/provenance, slots and the carry-weight limit, refused adds change nothing
# - equipment slots, two-handed weapons and the off hand, wear and break, repair
# - provenance: a stolen item worn where its owner (or anyone who knows it) has line of sight is a
#   `theft` deed about the owner, once per item; a wall hides it
# - drop_all_at: everything (coin too) as a pack node; taking it back; packs and inventory through a JSON
#   save, respawned in their scene
# - a_pack_by_the_road: the soul of whoever comes upon the pack takes it, keeps it safe (handed back when
#   the player talks to them), hands it to the watch, or leaves it
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_inventory.gd

class _Body extends Node2D:
	var npc_id: String = ""
	var is_alive: bool = true

var inv: Node
var pe: Node
var world_state: Node
var director: Node
var registry: Node
var propagator: Node
var failures: int = 0
var saved_pe: Dictionary
var saved_propagation: Dictionary
var saved_flags: Dictionary
var saved_npc_states: Dictionary
var saved_minutes: int
var save_existed: bool

func _init():
	await process_frame
	await process_frame
	inv = root.get_node("Inventory")
	pe = root.get_node("PlayerEvents")
	world_state = root.get_node("WorldState")
	director = root.get_node("StorylineDirector")
	registry = root.get_node("WorldRegistry")
	propagator = root.get_node("EventPropagator")
	world_state.set_idle_clock_rate(0.0)
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	saved_pe = pe.save()
	saved_propagation = propagator.save()
	saved_flags = world_state.world_flags.duplicate(true)
	saved_npc_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	inv.auto_recognise = false
	print("============================================================")
	print("🧪 INVENTORY TEST")
	print("============================================================\n")

	_test_definitions_and_coin()
	_test_stacking_and_weight()
	_test_equipment()
	_test_wear_and_break()
	await _test_recognition()
	await _test_drop_and_take_back()
	_test_save_load()
	await _test_pack_by_the_road()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _fresh() -> void:
	inv.reset()
	inv.carry_override = -1.0
	inv.location_override = ""

# =============================================================================

func _test_definitions_and_coin():
	print("Definitions and coin")
	_fresh()
	_check("Item definitions load (%d)" % inv.defs.size(), inv.defs.size() >= 70)
	var kinds = {}
	for d in inv.defs.values():
		kinds[d.kind] = true
	_check("Every kind of the brief is present", ["weapon", "armour", "tool", "material", "food", "remedy", "misc"].all(func(k): return kinds.has(k)))
	for id in ["iron_ore", "steel_bar", "fever_root", "white_salt", "smiths_hammer", "arming_sword", "hunting_bow", "arrows", "mail_shirt", "fever_root_tea", "grey_fever_cure", "spare_lot_tile"]:
		_check("%s is defined" % id, inv.get_definition(id).get("id", "") == id)
	_check("get_item_def (UI) returns the definition", inv.get_item_def("bread").get("name", "") == "Bread" and inv.COPPER_PER_SILVER == 100 and inv.SILVER_PER_GOLD == 100 and inv.GOLD_PER_CROWN == 100)
	_check("A crown is a million copper, a gold ten thousand", inv.COPPER_PER_CROWN == 1000000 and inv.COPPER_PER_GOLD == 10000)
	_check("A labourer's season (7 silver 20) is 720 copper", inv.to_copper(0, 0, 7, 20) == 720)
	_check("A mail shirt costs about a season's wage", inv.get_definition("mail_shirt").value == inv.to_copper(0, 0, 7, 20))
	_check("format_coin: nothing", inv.format_coin(0) == "nothing")
	_check("format_coin: 1 copper", inv.format_coin(1) == "1 copper")
	_check("format_coin: 100 is 1 silver", inv.format_coin(100) == "1 silver")
	_check("format_coin: 1,010,203 is 1 crown, 1 gold, 2 silver, 3 copper", inv.format_coin(1010203) == "1 crown, 1 gold, 2 silver, 3 copper" and inv.to_copper(1, 1, 2, 3) == 1010203)
	_check("format_coin: crowns take a plural, the metals do not", inv.format_coin(inv.to_copper(3, 2, 0, 5)) == "3 crowns, 2 gold, 5 copper")
	inv.add_coin(inv.to_copper(0, 0, 0, 29))
	_check("add_coin and get_coin are copper", inv.get_coin() == 29)
	_check("Spending more than the purse holds is refused", not inv.spend_coin(30) and inv.get_coin() == 29)
	_check("...spending what it holds is not", inv.spend_coin(9) and inv.get_coin() == 20)
	inv.add_coin(-100)
	_check("Taking coin never leaves a debt", inv.get_coin() == 0)
	_check("Unknown items are refused", not inv.add("silver_spoon_of_nowhere", 1))

func _test_stacking_and_weight():
	print("\nStacking, slots and weight")
	_fresh()
	var signals = [0]
	var counter = func(): signals[0] += 1
	inv.changed.connect(counter)
	_check("25 iron ore", inv.add("iron_ore", 25))
	var ore = inv.get_items().filter(func(r): return r.id == "iron_ore")
	_check("...stacks 20 and 5", ore.size() == 2 and ore[0].qty == 20 and ore[1].qty == 5)
	_check("...and changed fires", signals[0] >= 1)
	inv.changed.disconnect(counter)
	inv.add("iron_ore", 3)
	_check("More ore fills the open stack first", inv.get_items().filter(func(r): return r.id == "iron_ore").size() == 2 and inv.count("iron_ore") == 28)
	inv.add("iron_ore", 1, {"quality": 90})
	_check("Different quality does not stack", inv.get_items().filter(func(r): return r.id == "iron_ore").size() == 3)
	inv.add("iron_ore", 1, {"provenance": {"from": "greystone_mines", "stolen": true, "owner": "dagna"}})
	_check("Stolen ore does not stack with honest ore", inv.get_items().filter(func(r): return r.id == "iron_ore").size() == 4)
	_check("has counts across stacks", inv.has("iron_ore", 30) and not inv.has("iron_ore", 31))
	_check("remove takes across stacks", inv.remove("iron_ore", 22) and inv.count("iron_ore") == 8)
	_check("Removing more than there is is refused, and removes nothing", not inv.remove("iron_ore", 9) and inv.count("iron_ore") == 8)
	_check("Weight is summed from definitions", is_equal_approx(inv.get_weight(), 16.0))
	_check("The default carry limit is 60", is_equal_approx(inv.get_max_carry(), 60.0))
	_fresh()
	inv.carry_override = 12.0
	_check("A mail shirt fits a 12 limit", inv.add("mail_shirt", 1))
	_check("...a pick on top does not", not inv.add("pick", 1) and not inv.has("pick"))
	_check("...forced (a pack taken back), it does", inv.add("pick", 1, {"force": true}) and inv.get_weight() > inv.get_max_carry())
	_fresh()
	inv.carry_override = 1000.0
	for i in inv.MAX_SLOTS:
		inv.add("knife", 1)
	_check("%d knives fill every slot (knives do not stack)" % inv.MAX_SLOTS, inv.get_free_slots() == 0)
	_check("...one more is refused", not inv.add("knife", 1) and inv.count("knife") == inv.MAX_SLOTS)
	_check("...and so is a new stack, but an open stack still fills", not inv.add("bread", 1))

func _test_equipment():
	print("\nEquipment")
	_fresh()
	for id in ["arming_sword", "shield", "war_hammer", "mail_shirt", "helm", "pick", "bread"]:
		inv.add(id, 1)
	_check("Sword in the main hand", inv.equip("arming_sword", "main_hand") and inv.get_equipped("main_hand").id == "arming_sword")
	_check("Shield in the off hand", inv.equip("shield", "off_hand") and inv.get_equipped("off_hand").id == "shield")
	_check("Mail on the body, helm on the head, pick as the tool", inv.equip("mail_shirt", "body") and inv.equip("helm", "head") and inv.equip("pick", "tool"))
	_check("Bread is not a helm", not inv.equip("bread", "head"))
	_check("A sword is not a tool", not inv.equip("arming_sword", "tool"))
	_check("An unknown slot is refused", not inv.equip("helm", "feet"))
	_check("Records carry the contract fields", ["id", "qty", "quality", "durability", "max_durability", "maker", "provenance"].all(func(k): return inv.get_equipped("body").has(k)) \
		and ["from", "stolen", "owner"].all(func(k): return inv.get_equipped("body").provenance.has(k)))
	_check("get_items marks the slot", inv.get_items().filter(func(r): return r.slot == "main_hand")[0].id == "arming_sword")
	_check("A war hammer takes both hands", inv.equip("war_hammer", "main_hand") and inv.get_equipped("off_hand").is_empty())
	_check("...and no shield while it is held", not inv.equip("shield", "off_hand"))
	_check("Removing an equipped item takes it off", inv.remove("helm", 1) and inv.get_equipped("head").is_empty())
	_check("You cannot equip what you do not have", not inv.equip("hunting_bow", "main_hand"))
	_check("unequip empties a slot", inv.unequip("tool") and inv.get_equipped("tool").is_empty() and inv.has("pick"))

func _test_wear_and_break():
	print("\nWear and break")
	_fresh()
	inv.add("arming_sword", 1)
	inv.add("arming_sword", 1, {"quality": 100, "maker": "bjorn"})
	var recs = inv.get_items()
	_check("Quality sets durability (50 -> 200, 100 -> 300)", recs[0].max_durability == 200.0 and recs[1].max_durability == 300.0 and recs[1].maker == "bjorn")
	inv.equip("arming_sword", "main_hand")
	var r = inv.wear("main_hand", 150)
	_check("Wear lowers durability", not r.broke and inv.get_equipped("main_hand").durability == 50.0)
	r = inv.wear("main_hand", 80)
	_check("At nothing it breaks", r.broke == true and r.durability == 0.0)
	_check("...leaves the hand", inv.get_equipped("main_hand").is_empty())
	_check("...and stays in the pack, broken", inv.get_items().filter(func(x): return x.get("broken", false)).size() == 1 and inv.count("arming_sword") == 2)
	_check("Wearing an empty slot breaks nothing", inv.wear("main_hand", 5).broke == false)
	_check("Equipping skips the broken one", inv.equip("arming_sword", "main_hand") and inv.get_equipped("main_hand").quality == 100)
	_check("Breaking the second too", inv.wear("main_hand", 1000).broke == true)
	_check("Two broken swords cannot be equipped", inv.count("arming_sword") == 2 and not inv.equip("arming_sword", "main_hand"))
	_check("Mending one (Crafting) makes it whole", inv.repair("arming_sword") and inv.equip("arming_sword", "main_hand") and inv.get_equipped("main_hand").durability == inv.get_equipped("main_hand").max_durability)
	_check("...a broken item can be added as broken (a find)", inv.add("hand_axe", 1, {"broken": true}) and not inv.equip("hand_axe", "main_hand"))
	_check("Materials do not wear", inv.add("wood", 2) and inv.get_items().filter(func(x): return x.id == "wood")[0].max_durability == 0.0)

func _test_recognition():
	print("\nStolen items and who knows them")
	_fresh()
	pe.reset()
	inv.location_override = "thornhaven_gregor_shop"
	var scene = Node2D.new()
	root.add_child(scene)
	var player = Node2D.new()
	player.add_to_group("player")
	scene.add_child(player)
	var gregor = _npc(registry.get_npc_id("gregor") if registry.get_npc_id("gregor") != "" else "gregor", Vector2(0, 200))
	var renna = _npc(registry.get_npc_id("renna") if registry.get_npc_id("renna") != "" else "renna", Vector2(-150, 0))
	var mira = _npc(registry.get_npc_id("mira") if registry.get_npc_id("mira") != "" else "mira", Vector2(150, 0))
	for n in [gregor, renna, mira]:
		scene.add_child(n)
	var wall = _wall(Vector2(0, 100), Vector2(400, 20))
	scene.add_child(wall)
	await physics_frame
	await physics_frame
	inv.add("gregors_file", 1, {"provenance": {"from": "thornhaven_gregor_shop", "stolen": true, "owner": "gregor"}})
	inv.equip("gregors_file", "tool")
	_check("Gregor behind a wall does not see his file", inv.check_recognition(scene, Vector2.ZERO).is_empty())
	_check("...nor does anyone else who does not know it", pe.get_events().filter(func(e): return e.kind == "theft").is_empty())
	wall.queue_free()
	await physics_frame
	await physics_frame
	var ids = inv.check_recognition(scene)
	_check("In the open, Gregor recognises it (player found from the group)", ids.size() == 1)
	var ev: Dictionary = pe.get_event(ids[0]) if ids.size() == 1 else {}
	_check("...a theft deed about Gregor", ev.get("kind", "") == "theft" and "gregor" in ev.get("about", []).map(func(a): return registry.get_npc_key(str(a)) if registry.get_npc_key(str(a)) != "" else str(a)))
	_check("...witnessed by Gregor alone, not Mira who does not know it", ev.get("witnesses", []).size() == 1 and registry.get_npc_key(str(ev.witnesses[0])) == "gregor")
	_check("...found out, so it is true", ev.get("truth", "") == "true")
	_check("Once per item", inv.check_recognition(scene).is_empty() and inv.get_equipped("tool").recognised == true)
	inv.add("rangers_sword", 1, {"provenance": {"from": "kingsroad_waystation", "stolen": true, "owner": ""}})
	inv.add("arming_sword", 1)
	inv.equip("arming_sword", "main_hand")
	_check("An honest sword raises nothing", inv.check_recognition(scene).is_empty())
	inv.equip("rangers_sword", "main_hand")
	ids = inv.check_recognition(scene)
	ev = pe.get_event(ids[0]) if ids.size() == 1 else {}
	_check("A ranger's sword is known by the crown's people (Renna), owner or not", ids.size() == 1 and ev.get("witnesses", []).size() == 1 and registry.get_npc_key(str(ev.witnesses[0])) == "renna")
	_check("A stolen item in the pack (not worn) is not seen", inv.recognisers({"id": "gregors_file", "provenance": {"owner": "gregor"}}) == ["gregor"])
	scene.queue_free()
	await process_frame

func _test_drop_and_take_back():
	print("\nDeath drops everything; taking it back")
	_fresh()
	inv.location_override = "forest_path"
	var scene = Node2D.new()
	root.add_child(scene)
	inv.add("arming_sword", 1, {"quality": 80})
	inv.add("bread", 4)
	inv.add("gregors_file", 1, {"provenance": {"from": "thornhaven_gregor_shop", "stolen": true, "owner": "gregor"}})
	inv.equip("arming_sword", "main_hand")
	inv.add_coin(130)
	var weight = inv.get_weight()
	var node = inv.drop_all_at(scene, Vector2(40, 60))
	_check("drop_all_at returns the pack node", node != null and node.is_in_group("dropped_packs") and node.position == Vector2(40, 60))
	_check("...an Interactable", node is Interactable)
	_check("...and leaves nothing on the player, coin and equipment included", inv.get_items().is_empty() and inv.get_coin() == 0 and inv.get_equipped("main_hand").is_empty())
	var pack: Dictionary = inv.get_pack(str(node.pack_id))
	_check("The pack holds it all where they fell", pack.location == "forest_path" and pack.coin == 130 and pack.items.size() == 3 and pack.state == "lying")
	_check("...provenance travels with it", pack.items.any(func(r): return r.id == "gregors_file" and r.provenance.stolen == true))
	_check("Nothing to drop drops nothing", inv.drop_all_at(scene, Vector2.ZERO) == null and inv.get_packs().size() == 1)
	node._on_interact()
	_check("Taking it back returns everything", inv.count("bread") == 4 and inv.has("arming_sword") and inv.has("gregors_file") and inv.get_coin() == 130 and is_equal_approx(inv.get_weight(), weight))
	_check("...quality intact", inv.get_items().filter(func(r): return r.id == "arming_sword")[0].quality == 80)
	_check("...and the pack is gone", inv.get_packs().is_empty() and not inv.take_pack(str(node.pack_id)))
	await process_frame
	_check("...node and all", not is_instance_valid(node))
	scene.queue_free()
	await process_frame

func _test_save_load():
	print("\nSave and load (inventory and packs)")
	_fresh()
	inv.location_override = "forest_path"
	inv.add("hunting_bow", 1, {"quality": 70, "maker": "player"})
	inv.add("arrows", 30)
	inv.add("gregors_file", 1, {"provenance": {"from": "thornhaven_gregor_shop", "stolen": true, "owner": "gregor"}})
	inv.equip("hunting_bow", "main_hand")
	inv.equip("gregors_file", "tool")
	inv.wear("main_hand", 12)
	inv.add_coin(77)
	var before = inv.get_items()
	var dropped = inv.drop_all_at(null, Vector2(300, 120))
	_check("A pack is kept even with no scene loaded", dropped == null and inv.get_packs("forest_path").size() == 1)
	inv.add("padded_jack", 1)
	inv.equip("padded_jack", "body")
	inv.add_coin(5)
	var saved = JSON.parse_string(JSON.stringify(inv.save()))
	inv.reset()
	_check("(reset forgets)", inv.get_items().is_empty() and inv.get_packs().is_empty())
	inv.load_from_dict(saved)
	_check("Items, equipment and coin come back", inv.get_equipped("body").id == "padded_jack" and inv.get_coin() == 5)
	var packs = inv.get_packs("forest_path")
	_check("The pack comes back where it lay", packs.size() == 1 and packs[0].position == [300.0, 120.0] and packs[0].coin == 77)
	var bow = packs[0].items.filter(func(r): return r.id == "hunting_bow")
	_check("...its contents typed and intact", bow.size() == 1 and bow[0].quality == 70 and bow[0].durability == before[0].durability and bow[0].maker == "player" \
		and packs[0].items.any(func(r): return r.id == "arrows" and r.qty == 30 and r.qty is int))
	var scene = Node2D.new()
	root.add_child(scene)
	var nodes = inv.spawn_packs(scene, "forest_path")
	_check("Entering the place puts the pack back in the scene", nodes.size() == 1 and nodes[0].position == Vector2(300, 120))
	_check("...once", inv.spawn_packs(scene, "forest_path").is_empty())
	_check("...and not anywhere else", inv.spawn_packs(scene, "old_mill").is_empty())
	_check("Taken back after a load", inv.take_pack(packs[0].id) and inv.get_equipped("main_hand").is_empty() and inv.count("arrows") == 30 and inv.get_coin() == 82)
	_check("...the stolen file still stolen", inv.get_items().any(func(r): return r.id == "gregors_file" and r.provenance.stolen and r.provenance.owner == "gregor"))
	_check("WorldState saves the Inventory block", world_state.save().get("player_systems", {}).get("Inventory", {}).get("items", []).size() == inv.get_items().size())
	scene.queue_free()

func _test_pack_by_the_road():
	print("\nA pack by the road (souls decide)")
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	var n = director.load_emergence("res://resources/emergence")
	_check("The template loads with the rest (%d)" % n, director.get_emergence().get_template("a_pack_by_the_road").size() > 0 and director.get_emergence_errors().is_empty())
	var place = "thornhaven_blacksmith"
	var cases = [
		["kind", {"trust": 60, "affection": 60, "familiarity": 30}, "keep_it_safe", "held"],
		["hostile", {"trust": -60, "affection": -60, "respect": -40}, "take_it", "taken"],
		["dutiful", {"respect": 70, "familiarity": -60, "fear": 20}, "hand_to_watch", "held"],
		["wary", {"fear": 80, "familiarity": 20}, "leave_it", "lying"],
	]
	for c in cases:
		_fresh()
		pe.reset()
		world_state.world_flags = {}
		director.reset_state()
		director.get_emergence().reset()
		director.player_location_override = place
		inv.location_override = place
		var near: Array = director.get_emergence().near_player()
		if near.is_empty():
			_check("(someone stands at %s)" % place, false)
			return
		var dims = {}
		for k in director.get_soul_keys():
			dims[k] = {}
		for k in near:
			dims[k] = c[1]
		director.relationship_dims_override = dims
		inv.add("short_sword", 1)
		inv.add_coin(50)
		inv.drop_all_at(null, Vector2(10, 10))
		var fell = pe.record("fell", "fell in the forge yard", [], {"witnesses": [], "location": place, "spread": false})
		var pack_id = inv.get_packs(place)[0].id
		_check("[%s] The fall is linked to the pack" % c[0], inv.get_pack(pack_id).event_id == fell)
		var insts = director.get_emergent_instances(false).filter(func(i): return i.template == "a_pack_by_the_road")
		_check("[%s] Someone comes upon it (%s)" % [c[0], insts[0].roles.finder if insts.size() > 0 else "nobody"], insts.size() == 1)
		if insts.is_empty():
			continue
		var finder = str(insts[0].roles.finder)
		await director.advance_round("test")
		var acted = director.get_chronicle(0).filter(func(e): return e.get("template", "") == "a_pack_by_the_road" and e.get("choice", "") not in ["instantiated", "resolved", "expired"])
		_check("[%s] %s chooses %s" % [c[0], finder, acted[0].choice if acted.size() > 0 else "nothing"], acted.size() > 0 and acted[0].choice == c[2])
		var pack = inv.get_pack(pack_id)
		_check("[%s] ...and the pack is %s" % [c[0], c[3]], pack.get("state", "") == c[3])
		match c[2]:
			"keep_it_safe":
				_check("[keep] %s holds it" % finder, pack.holder == finder)
				director.finish_conversation(finder)
				_check("[keep] Talking to them hands it back", inv.get_pack(pack_id).is_empty() and inv.has("short_sword") and inv.get_coin() == 50)
			"take_it":
				_check("[take] %s has it" % finder, pack.holder == finder)
				_check("[take] ...and will not hand it back", inv.reclaim_from(finder) == 0 and not inv.take_pack(pack_id) and not inv.has("short_sword"))
			"hand_to_watch":
				var watch = str(insts[0].roles.get("watch", finder))
				_check("[watch] The watch (%s) holds it" % watch, pack.holder == watch)
				_check("[watch] ...and gives it back when asked", inv.reclaim_from(watch) == 1 and inv.get_coin() == 50)
			"leave_it":
				_check("[leave] It still lies there for the player", inv.take_pack(pack_id) and inv.has("short_sword"))
	director.relationship_dims_override = {}
	director.player_location_override = ""

# =============================================================================

func _npc(id: String, at: Vector2) -> Node2D:
	var b = _Body.new()
	b.npc_id = id
	b.position = at
	b.add_to_group("npcs")
	return b

func _wall(at: Vector2, size: Vector2) -> StaticBody2D:
	var b = StaticBody2D.new()
	b.position = at
	b.collision_layer = 4
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	b.add_child(shape)
	return b

func _restore() -> void:
	inv.reset()
	inv.location_override = ""
	inv.carry_override = -1.0
	inv.auto_recognise = true
	director.relationship_dims_override = {}
	director.player_location_override = ""
	director.reset_state()
	director.get_emergence().reset()
	world_state.world_flags = saved_flags
	world_state.npc_states = saved_npc_states
	world_state.game_minutes = saved_minutes
	pe.reset()
	pe.load_from_dict(saved_pe)
	propagator.load_from_dict(saved_propagation)
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
