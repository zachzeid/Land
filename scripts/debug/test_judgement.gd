extends SceneTree

# Tests judgement (docs/WORLD_SCHEMA.md §16 "Who judges a visit"): each person judges a visit to the
# back rooms by their own nature, from the rules in resources/characters/judgement.json
# - the devout (faith among their values, a church calling, a devout archetype or voice) disapprove;
#   the strait-laced and the proper disapprove less; most do not care; some approve (the companion,
#   the house's keeper, the worldly); a merciful soul disapproves in kinder words
# - anyone courting the player is hurt, more than by anything else, by their relationship style;
#   one only growing fond is hurt less
# - children are never asked, and weigh nothing in a party's mean
# - weights stay in the rules' range; a faction or region is the mean of its people
# - what someone knows of the visit carries their own view: the heard block and the memory text
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_judgement.gd

const TAVERNS = preload("res://scripts/world/taverns.gd")
const Rep = preload("res://scripts/world_state/reputation.gd")
const WAY = "kingsroad_waystation"

var taverns: Node
var made_taverns: bool = false
var pe: Node
var world_state: Node
var director: Node
var registry: Node
var gm = null
var failures: int = 0
var saved_pe: Dictionary
var saved_flags: Dictionary
var save_existed: bool

func _init():
	await process_frame
	await process_frame
	taverns = root.get_node_or_null("Taverns")
	if taverns == null:
		taverns = TAVERNS.new()
		taverns.name = "Taverns"
		root.add_child(taverns)
		made_taverns = true
	pe = root.get_node("PlayerEvents")
	world_state = root.get_node("WorldState")
	director = root.get_node("StorylineDirector")
	registry = root.get_node("WorldRegistry")
	var dyn = root.get_node_or_null("DynamicNPCRegistry")
	gm = dyn.generics if dyn and "generics" in dyn else null
	world_state.set_idle_clock_rate(0.0)
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	saved_pe = pe.save()
	saved_flags = world_state.world_flags.duplicate(true)
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	pe.capture_enabled = false
	print("============================================================")
	print("🧪 JUDGEMENT TEST")
	print("============================================================\n")

	_print_table()
	_test_mains()
	_test_generics()
	_test_courting()
	_test_parties()
	_test_knowledge()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _fresh() -> void:
	director.relationship_dims_override = {}
	pe.reset()
	world_state.world_flags.erase("elena_romance_started")

## Every main NPC's judgement, for a person to check against the souls
func _print_table() -> void:
	_fresh()
	print("Every main NPC, untouched by the player")
	for key in registry.get_npc_keys():
		var j = taverns.judge(str(key))
		print("  %-10s %+5.1f %-11s %s" % [key, j.weight, j.stance, j.reason])

func _test_mains() -> void:
	print("\nMain NPCs, by their souls")
	_fresh()
	for key in ["ysolde", "anselm", "mathias"]:
		var j = taverns.judge(key)
		_check("%s disapproves as the devout do (%s)" % [key, j.reason], j.stance == "disapproves" and is_equal_approx(j.weight, taverns.DISAPPROVAL))
	_check("Ysolde's mercy shows in her words, not her weight", taverns.judge("ysolde").feels.contains("not turn them") and "mercy" in taverns.judge("ysolde").rules)
	_check("Mathias says it plainly", taverns.judge("mathias").feels.contains("think the less"))
	_check("Bjorn, strait-laced and proud of his family's honour, disapproves less", taverns.judge("bjorn").stance == "disapproves" and taverns.judge("bjorn").weight > taverns.DISAPPROVAL)
	_check("Lady Seraphine minds how it looks", taverns.judge("seraphine").weight < 0.0)
	_check("Hollis: respectability outweighs the coin", taverns.judge("hollis").weight < 0.0 and "coin" in taverns.judge("hollis").rules)
	_check("Old Wren keeps the house: good custom", taverns.judge("wren").stance == "approves" and "keeps_the_house" in taverns.judge("wren").rules)
	_check("Varn: coin is coin", taverns.judge("varn").stance == "approves")
	_check("Gregor is not one to talk", taverns.judge("gregor").weight == 0.0 and taverns.judge("gregor").feels.contains("hardly one to talk"))
	for key in ["aldric", "corwin", "edric", "lucan", "dagna", "oskar", "davin", "renna", "elena", "mira"]:
		_check("%s does not care" % key, taverns.judge(key).stance == "indifferent")
	_check("A child is never asked", taverns.judge("rook").stance == "child" and taverns.judge("rook").feels == "" and taverns.reaction("rook") == "")
	var span: Array = taverns._judgement().company.range
	_check("Every weight is inside the range", registry.get_npc_keys().all(func(k): var w = taverns.judge(str(k)).weight; return w >= float(span[0]) and w <= float(span[1])))
	_check("Only the devout count as pious", taverns.is_pious("ysolde") and taverns.is_pious("mathias") and not taverns.is_pious("bjorn") and not taverns.is_pious("wren"))
	_check("Other deeds are weighed by no one", taverns.judge("ysolde", "no_such_deed").weight == 0.0 and taverns.judge("ysolde", "no_such_deed").feels == "")

func _test_generics() -> void:
	print("\nGenerics, by archetype, voice and temperament")
	_fresh()
	if gm == null:
		_check("Generics are loaded", false)
		return
	var companion = _first_of("house_companion")
	_check("A companion approves: it is their living", companion != "" and taverns.judge(companion).stance == "approves" and "companion" in taverns.judge(companion).rules)
	var pilgrims: Array = gm.get_ids().filter(func(id): return str(gm.get_instance(id).archetype_id) == "pilgrim")
	_check("Every pilgrim disapproves", not pilgrims.is_empty() and pilgrims.all(func(id): return taverns.judge(id).stance == "disapproves"))
	var devout = pilgrims.filter(func(id): return _voice(id).to_lower().contains("devout"))
	var other = pilgrims.filter(func(id): return not _voice(id).to_lower().contains("devout"))
	if not devout.is_empty() and not other.is_empty():
		_check("A devout pilgrim more than a doubting one", taverns.judge(devout[0]).weight < taverns.judge(other[0]).weight)
	var urchin = _first_of("warrens_urchin")
	_check("An urchin is a child, never asked", urchin != "" and taverns.judge(urchin).stance == "child")
	var stances: Dictionary = {}
	for id in gm.get_ids():
		var j = taverns.judge(id)
		var a = str(gm.get_instance(id).archetype_id)
		stances[a] = stances.get(a, {})
		stances[a][j.stance] = int(stances[a].get(j.stance, 0)) + 1
	for a in stances:
		print("    %-20s %s" % [a, stances[a]])
	_check("Ordinary folk mostly do not care", stances.get("valley_farmer", {}).get("indifferent", 0) >= stances.get("valley_farmer", {}).get("disapproves", 0))

func _test_courting() -> void:
	print("\nWho is courting the player is hurt")
	_fresh()
	director.relationship_dims_override = {"renna": {"trust": 75, "affection": 70, "familiarity": 60}}
	var j = taverns.judge("renna")
	_check("Renna with the romance in reach: hurt, the heaviest there is (%s)" % j.reason, j.stance == "hurt" and j.weight == -12.0 and j.feels.contains("hurts"))
	director.relationship_dims_override = {"renna": {"trust": 20, "affection": 50, "familiarity": 20}}
	j = taverns.judge("renna")
	_check("...growing fond: hurt, but less (%.1f)" % j.weight, j.stance == "hurt" and j.weight > -12.0 and j.weight < -6.0)
	director.relationship_dims_override = {"renna": {"trust": 20, "affection": 10, "familiarity": 20}}
	_check("...barely acquainted: does not care", taverns.judge("renna").stance == "indifferent")
	director.relationship_dims_override = {}
	world_state.world_flags["elena_romance_started"] = true
	_check("Elena, whose romance has begun, is hurt", taverns.judge("elena").stance == "hurt")
	world_state.world_flags.erase("elena_romance_started")
	director.relationship_dims_override = {"bjorn": {"trust": 60, "affection": 60, "familiarity": 70}}
	_check("Bjorn courting: hurt outweighs his propriety", taverns.judge("bjorn").stance == "hurt" and taverns.judge("bjorn").weight == -12.0)
	director.relationship_dims_override = {"aldric": {"trust": 100, "affection": 100, "familiarity": 100}}
	_check("Aldric, who is not looking for love, is never 'courting'", taverns.judge("aldric").stance != "hurt")
	director.relationship_dims_override = {}

func _test_parties() -> void:
	print("\nA party is the mean of its people")
	_fresh()
	var y = taverns.judge("ysolde").weight
	var w = taverns.judge("wren").weight
	_check("Ysolde and Wren together", is_equal_approx(taverns.judgement(["ysolde", "wren"]), (y + w) / 2.0))
	_check("A child in the party changes nothing", is_equal_approx(taverns.judgement(["ysolde", "rook"]), y))
	_check("Nobody: nothing", taverns.judgement([]) == 0.0 and taverns.judgement(["rook"]) == 0.0)
	var ev = pe.record("seen_at", "went through to the back rooms at the Halfway House with one of the companions", [],
		{"witnesses": ["ysolde", "wren"], "location": WAY, "morals": "company", "spread": false})
	var by: Dictionary = {}
	for key in ["ysolde", "wren", "gregor"]:
		for e in Rep.breakdown("npc", key).events:
			if str(e.id) == ev:
				by[key] = float(e.weight)
	_check("Reputation weighs the visit by each witness's nature (%s)" % by, is_equal_approx(float(by.get("ysolde", 0)), y) and is_equal_approx(float(by.get("wren", 0)), w) and not by.has("gregor"))

func _test_knowledge() -> void:
	print("\nWhat they know of it carries their own view")
	_fresh()
	var ev = pe.record("seen_at", "went through to the back rooms at the Halfway House with one of the companions", [],
		{"witnesses": ["mathias", "gregor"], "location": WAY, "morals": "company", "spread": false})
	var block = pe.get_heard_block(registry.get_npc_id("mathias"))
	_check("Mathias's heard block holds his own view", block.contains("Your own view of it") and block.contains(taverns.reaction("mathias")))
	block = pe.get_heard_block(registry.get_npc_id("gregor"))
	_check("Gregor's holds his", block.contains(taverns.reaction("gregor")))
	_check("A plain deed carries no view", pe.view_of({"kind": "theft"}, "mathias") == "")
	_check("A rumour of nobody in particular carries none", pe.view_of(pe.events[ev], "mathias", 0.1) == "")
	_check("Heard word carries it too", pe._view_suffix(pe.events[ev], "ysolde", 0.8).contains("not turn them"))
	var text = str(pe.events[ev].summary).to_lower()
	_check("Nothing explicit in the deed or any view", not RegEx.create_from_string("\\b(sex|naked|nude|lust|erotic|seduc)").search(text + " ".join(registry.get_npc_keys().map(func(k): return taverns.reaction(str(k)))).to_lower()))

func _voice(id: String) -> String:
	var inst = gm.get_instance(id)
	var arch = gm.get_archetype(str(inst.archetype_id))
	return str(arch.voice_variants[int(inst.voice_variant)]) if arch and int(inst.voice_variant) < arch.voice_variants.size() else ""

func _first_of(archetype: String) -> String:
	for id in gm.get_ids():
		if str(gm.get_instance(id).archetype_id) == archetype:
			return id
	return ""

func _restore() -> void:
	director.relationship_dims_override = {}
	pe.capture_enabled = true
	pe.reset()
	pe.load_from_dict(saved_pe)
	world_state.world_flags = saved_flags
	if made_taverns:
		taverns.queue_free()
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
