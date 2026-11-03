extends SceneTree
# Tests the generic NPC system (docs/WORLD_SCHEMA.md §9): archetypes, seeded instances, layers,
# decay for every NPC, significance, promotion/demotion with hysteresis, anchored mains, canon
# names, gossip, save/load, the spawner and the GenericNPC body
# Run: godot --headless --path . -s res://scripts/debug/test_generics.gd
# No API spend, nothing written to ./chroma (in-memory RAG); souls go to user://test_generics_souls

const Manager = preload("res://scripts/generics/generic_manager.gd")
const Archetype = preload("res://scripts/generics/archetype.gd")
const SoulBuilder = preload("res://scripts/generics/generic_soul_builder.gd")
const GenericInstance = preload("res://scripts/generics/generic_instance.gd")
const Spawner = preload("res://scripts/world/npc_spawner.gd")
const Soul = preload("res://scripts/storyline/soul.gd")

const FIX = "res://scripts/debug/fixtures/generics"
const SOULS = "user://test_generics_souls"
const DAY = 1440
const T0 = 8 * 60  # day 1, 08:00

## Stands in for the arcs engine's StorylineDirector API (register_soul / unregister_soul /
## set_soul_tier). Personal turns go only to main and promoted souls, as the contract says
class FakeDirector extends Node:
	signal round_completed(round_number: int, reason: String, entries: Array)
	var souls: Dictionary = {}   # key -> {"text", "tier", "npc_id", "soul"}
	var calls: Array = []
	func register_soul(key: String, soul_text: String, opts: Dictionary = {}) -> bool:
		calls.append(["register_soul", key, opts.get("tier", "")])
		var soul = Soul.new()
		soul.parse(soul_text)
		if soul.npc_key != key or soul.wants.is_empty():
			return false
		souls[key] = {"text": soul_text, "tier": str(opts.get("tier", "main")), "npc_id": str(opts.get("npc_id", key)), "soul": soul}
		return true
	func unregister_soul(key: String) -> void:
		calls.append(["unregister_soul", key])
		souls.erase(key)
	func set_soul_tier(key: String, tier: String) -> void:
		calls.append(["set_soul_tier", key, tier])
		if souls.has(key):
			souls[key].tier = tier
	func get_soul(key: String):
		return souls[key].soul if souls.has(key) else null
	func tier_of(key: String) -> String:
		return souls[key].tier if souls.has(key) else ""
	func personal_turn_pool() -> Array:
		return souls.keys().filter(func(k): return souls[k].tier in ["main", "promoted"])
	## A personal turn: the first step of the first Life arc (only for main/promoted souls)
	func personal_turn(key: String) -> String:
		if key not in personal_turn_pool():
			return ""
		var step_re = RegEx.create_from_string("^- `([a-z0-9_]+)`: ")
		for line in SoulBuilder.extract_section(souls[key].text, "life"):
			var m = step_re.search(str(line).strip_edges())
			if m:
				return m.get_string(1)
		return ""

class FakeNPC extends Node:
	var npc_id: String = ""
	var is_in_conversation: bool = false
	var relationship_trust: float = 0.0
	var relationship_respect: float = 0.0
	var relationship_affection: float = 0.0
	var relationship_fear: float = 0.0
	var relationship_familiarity: float = 0.0

var failures: int = 0
var passed: int = 0
var _managers: Array = []
var _fakes: Array = []

func _init():
	await process_frame
	await process_frame
	print("============================================================")
	print("GENERIC NPC SYSTEM TEST")
	print("============================================================\n")
	_clean_souls_dir()

	_test_archetype_parsing()
	_test_deterministic_rolls()
	_test_rolled_soul_and_personality()
	_test_layering_and_cap()
	_test_prompt_compactness()
	_test_decay_mains_included()
	_test_significance()
	_test_promotion_hysteresis()
	await _test_in_character_rewrite()
	_test_demotion_residue()
	_test_repromotion_bonus()
	_test_mains_never_demote()
	_test_generic_names_canon()
	_test_gossip_reaches_generics()
	_test_save_load_roundtrip()
	_test_spawner()
	await _test_generic_npc_body()
	await _test_real_director_contract()

	_clean_souls_dir()
	for m in _managers:
		if m.director_override is FakeDirector and m.director_override not in _fakes:
			_fakes.append(m.director_override)
		m.director_override = null
		m.queue_free()
	for fake in _fakes:
		fake.free()
	await process_frame
	await process_frame
	print("\n============================================================")
	print("%d passed, %d failed" % [passed, failures])
	print("ALL TESTS PASSED" if failures == 0 else "%d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================
# TESTS
# =============================================================================

func _test_archetype_parsing():
	print("-- archetype parsing --")
	var farmer = Archetype.load_from_file(FIX + "/archetypes/farmer.md")
	_check("farmer parses valid", farmer != null and farmer.is_valid())
	_check("header: id and regions", farmer.id == "farmer" and farmer.regions == ["western_valley"])
	_check("want ranges (lo-hi)", farmer.wants.keep_the_farm.lo == 6 and farmer.wants.keep_the_farm.hi == 9 and farmer.want_order.size() == 3)
	_check("converse-only agency, personal effects", farmer.converse == ["agenda", "adjust_relationship", "spread_rumor"])
	_check("voice: shared prose + 3 variants", farmer.voice_shared.begins_with("Plain words") and farmer.voice_variants.size() == 3)
	_check("Life: 1 arc with {id}_ result", farmer.life_arc_count == 1 and "\n".join(farmer.life_lines).contains("`{id}_bought_a_cow`"))
	var guard = Archetype.load_from_file(FIX + "/archetypes/gate_guard.md")
	_check("gate_guard: two regions, sprite header", guard.is_valid() and guard.regions == ["western_valley", "kingsroad"] and guard.sprite == "villager_male")

	var no_header = Archetype.load_from_file(FIX + "/malformed/no_header.md")
	_check("missing archetype: header is an error", not no_header.is_valid() and _has_error(no_header, "missing `archetype:`"))
	var bad_range = Archetype.load_from_file(FIX + "/malformed/bad_range.md")
	_check("bad ranges (8-3, 0-12) are errors", not bad_range.is_valid() and bad_range.errors.filter(func(e): return "range" in e).size() == 2)
	var schemer = Archetype.load_from_file(FIX + "/malformed/storyline_agency.md")
	_check("intercept: agency refused", _has_error(schemer, "only grant converse"))
	_check("set_flag in converse refused", _has_error(schemer, "set_flag"))
	_check("block_beat in a Life step refused", _has_error(schemer, "block_beat"))
	_check("Life result without {id}_ refused", _has_error(schemer, "{id}_"))
	var m = _make_manager(FIX + "/malformed")
	_check("malformed files are skipped with errors", m.archetypes.is_empty() and m.archetype_errors.size() == 3)

func _test_deterministic_rolls():
	print("-- deterministic rolls --")
	var a = _make_manager()
	var b = _make_manager()
	_check("population ids (unknown archetype skipped)", a.get_ids() == ["gen_farmer_1", "gen_farmer_2", "gen_gate_guard_1", "gen_gate_guard_2", "gen_farmer_3"])
	var same = true
	for id in a.get_ids():
		var x = a.get_instance(id)
		var y = b.get_instance(id)
		same = same and x.name == y.name and x.rolled_wants == y.rolled_wants and x.voice_variant == y.voice_variant and x.seed_value == y.seed_value and x.rolled_traits == y.rolled_traits
	_check("same seed -> same names, want weights, traits and voice variant", same)
	var in_range = true
	for id in a.get_ids():
		var inst = a.get_instance(id)
		var arch = a.get_archetype(inst.archetype_id)
		for w in inst.rolled_wants:
			in_range = in_range and inst.rolled_wants[w] >= arch.wants[w].lo and inst.rolled_wants[w] <= arch.wants[w].hi
		in_range = in_range and inst.voice_variant >= 0 and inst.voice_variant < maxi(arch.voice_variants.size(), 1)
	_check("rolls stay inside the archetype ranges", in_range)
	var names = a.get_ids().map(func(id): return a.get_instance(id).name)
	var unique = {}
	for n in names:
		unique[n] = true
	_check("names unique and from the region pool", unique.size() == names.size() and names.all(func(n): return n.split(" ")[0] in ["Thomas", "Hild", "Odo", "Maren", "Wat", "Agnes", "Piers", "Elsbet"]))
	print("    names: %s" % ", ".join(names))
	var c = _make_manager("", 4242)
	var differs = false
	for id in a.get_ids():
		differs = differs or c.get_instance(id).name != a.get_instance(id).name or c.get_instance(id).rolled_wants != a.get_instance(id).rolled_wants
	_check("a different world seed rolls differently", differs)
	_check("instance home + region from population/world.json", a.get_instance("gen_farmer_3").home == "old_mill" and a.get_instance("gen_farmer_3").region == "western_valley")

func _test_rolled_soul_and_personality():
	print("-- rolled souls (tier generic) and runtime personality --")
	var director = FakeDirector.new()
	var m = _make_manager("", -1, director)
	var inst = m.get_instance("gen_farmer_1")
	var check = SoulBuilder.validate_soul_text(inst.soul_text, inst.id)
	_check("rolled soul passes the Soul parser + strict Life check", check.ok)
	if not check.ok:
		print("    errors: %s" % [check.errors])
	_check("slots filled: name, home, region, {id}_", inst.soul_text.contains(inst.name) and inst.soul_text.contains("Thornhaven Square") and inst.soul_text.contains("Western Valley") and not inst.soul_text.contains("{"))
	_check("Life result prefixed with the instance id", inst.soul_text.contains("`gen_farmer_1_bought_a_cow`"))
	_check("want lines carry the rolled weights", inst.soul_text.contains("- `keep_the_farm` (%d):" % inst.rolled_wants.keep_the_farm))
	_check("registered with the Director as tier generic", director.tier_of("gen_farmer_1") == "generic" and director.souls.size() == 5)
	_check("generics are not in the personal-turn pool", director.personal_turn_pool().is_empty() and director.personal_turn("gen_farmer_1") == "")
	var p = m.build_personality("gen_farmer_1")
	_check("NPCPersonality built at runtime", p is NPCPersonality and p.display_name == inst.name and p.npc_id == "gen_farmer_1")
	_check("personality prompt names the generic", p.generate_system_prompt().contains(inst.name) and p.trait_agreeableness == inst.get_trait("agreeableness"))
	_check("sprite reused by archetype", m.sprite_for("gen_farmer_1") == "villager_male" and m.sprite_for("gen_gate_guard_1") == "villager_male")

func _test_layering_and_cap():
	print("-- layers from interactions, and the cap --")
	var m = _make_manager()
	var id = "gen_farmer_1"
	var inst = m.get_instance(id)
	var top_want = inst.wants_by_weight(m.get_archetype("farmer").want_order)[0]
	var before_want = inst.get_want_weight(top_want)
	m.record_learned(id, {"name": "Rowan", "occupation": "sellsword", "origin": "the Capitol", "notable_facts": ["is looking for work"]})
	m.test_now += 60
	m.record_interaction(id, "gift_given", {"player_message": "Take this bread for your children."})
	m.test_now += 60
	m.record_interaction(id, "threat_made", {"player_message": "Tell me where the bandits camp or else."})
	m.record_interaction(id, "casual_conversation", {})
	var kinds = {}
	for layer in inst.layers:
		kinds[layer.kind] = true
	_check("learned, moment and acquaintance layers", kinds.has("learned") and kinds.has("moment") and kinds.has("acquaintance"))
	_check("the player's name is pinned and ranks first", inst.ranked_layers(m.test_now)[0].text == "The stranger's name is Rowan." and inst.ranked_layers(m.test_now)[0].pinned)
	_check("moment keeps the gist of what was said", inst.layers.any(func(l): return l.text.begins_with("The stranger gave me a gift (\"Take this bread")))
	_check("acquaintance layer counts conversations", inst.layers.any(func(l): return l.text == "You and the stranger have talked 3 times."))
	_check("trait nudges: gift +2 then threat -2 agreeableness, neuroticism +3", int(inst.trait_nudges.get("agreeableness", 0)) == 0 and int(inst.trait_nudges.neuroticism) == 3)
	_check("want nudges: gift +1 hope, threat +1 to a safety want", inst.get_want_weight(top_want) == clampi(before_want + 1 + (1 if top_want == "keep_the_farm" else 0), 1, 10) and int(inst.want_nudges.get("keep_the_farm", 0)) >= 1)
	_check("interactions count as contact", m.ledger.is_met(id) and m.ledger.days_apart(id, m.test_now) == 0.0)
	m.record_interaction(id, "gift_given", {"player_message": "Take this bread for your children."})
	var gifts = inst.layers.filter(func(l): return l.tag == "moment:gift_given")
	_check("the same moment reinforces instead of duplicating", gifts.size() == 1 and gifts[0].count == 2)
	for i in 30:
		m.on_news_spread("fx_flag_%d" % i, "Something small happened (%d)." % i, "gossip", ["*"], "western_valley", "")
	_check("layers capped at %d" % GenericInstance.MAX_LAYERS, inst.layers.size() == GenericInstance.MAX_LAYERS)
	_check("the cap keeps the pinned name and the strong moments", inst.layers.any(func(l): return l.pinned) and inst.layers.any(func(l): return l.tag == "moment:threat_made"))
	print("    layers after cap: %s" % ", ".join(inst.ranked_layers(m.test_now).slice(0, 5).map(func(l): return "%s:%d" % [l.kind, l.importance])))

func _test_prompt_compactness():
	print("-- prompt compactness --")
	var m = _make_manager()
	var id = "gen_farmer_1"
	m.record_learned(id, {"name": "Rowan", "occupation": "sellsword"})
	for t in ["gift_given", "threat_made", "secret_shared", "emotional_support", "life_saved", "betrayal"]:
		m.test_now += 30
		m.record_interaction(id, t, {"player_message": "A sentence the player said about %s, long enough to be cut." % t})
	for i in 8:
		m.on_news_spread("fx_news_%d" % i, "The miller's cart lost a wheel on the forest road, and everyone saw it (%d)." % i, "gossip", ["*"], "western_valley", "")
	var with_soul = m.get_prompt_block(id, true)
	var layers_only = m.get_prompt_block(id, false)
	var t_soul = Manager.estimate_tokens(with_soul)
	var t_layers = Manager.estimate_tokens(layers_only)
	print("    generic block with soul: %d chars ~%d tokens; seed + layers only: %d chars ~%d tokens (layers held: %d)" % [with_soul.length(), t_soul, layers_only.length(), t_layers, m.get_instance(id).layers.size()])
	_check("block with soul <= 400 tokens", t_soul <= 400)
	_check("seed + layers only <= 220 tokens", t_layers <= 220)
	_check("shows at most %d layers" % GenericInstance.PROMPT_LAYERS, layers_only.count("\n- ") <= GenericInstance.PROMPT_LAYERS)
	_check("most important first: the name, then the life saved", layers_only.find("Rowan") < layers_only.find("saved my life") and layers_only.find("saved my life") > 0)
	_check("archetype base + seed present", with_soul.contains("strip of land") and with_soul.contains(m.get_instance(id).name) and with_soul.contains("Your voice:"))
	# The whole system prompt a conversation would send (ContextBuilder, generic personality)
	var registry = root.get_node("DynamicNPCRegistry")
	var saved = registry.generics
	registry.generics = m
	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	root.add_child(builder)
	var context = builder.build_context({"personality": m.build_personality(id), "npc_id": id,
		"tiered_memories": {"pinned": [], "important": [], "relevant": []},
		"relationship_dimensions": {"trust": 10, "respect": 5, "affection": 20, "fear": 15, "familiarity": 30, "memory_count": 0},
		"conversation_history": [], "player_input": "Hello again."})
	registry.generics = saved
	builder.queue_free()
	var full_tokens = Manager.estimate_tokens(context.system_prompt)
	print("    full conversation system prompt for the generic: %d chars ~%d tokens" % [context.system_prompt.length(), full_tokens])
	_check("ContextBuilder injects the generic's layers", context.system_prompt.contains("WHAT HAS HAPPENED TO YOU") and context.system_prompt.contains("Rowan"))

func _test_decay_mains_included():
	print("-- decay over days, mains included, familiarity floor --")
	var m = _make_manager()
	var main_id = "gregor_merchant_001"
	m.ledger.set_dims(main_id, {"trust": 40, "respect": 30, "affection": 50, "fear": 20, "familiarity": 30}, T0)
	m.ledger.note_contact(main_id, T0)
	m.ledger.set_dims("elena_daughter_001", {"familiarity": 10, "trust": -10}, T0)  # never met (no contact)
	m.test_now = T0 + DAY / 2
	m.process_time()
	_check("half a day apart: nothing fades yet", m.ledger.get_dims(main_id).trust == 40.0)
	m.test_now = T0 + 3 * DAY
	m.process_time()
	var d = m.ledger.get_dims(main_id)
	_check("3 days: trust -0.75, respect -1.5, affection -2.25, fear -3, familiarity -6",
		is_equal_approx(d.trust, 39.25) and is_equal_approx(d.respect, 28.5) and is_equal_approx(d.affection, 47.75) and is_equal_approx(d.fear, 17.0) and is_equal_approx(d.familiarity, 24.0))
	m.process_time()
	_check("decay is idempotent for the same clock", is_equal_approx(m.ledger.get_dims(main_id).familiarity, 24.0))
	m.test_now = T0 + 20 * DAY
	m.process_time()
	d = m.ledger.get_dims(main_id)
	_check("20 days: familiarity stops at the floor 5 once met", is_equal_approx(d.familiarity, 5.0))
	_check("20 days: fear reaches baseline 0 and stops", is_equal_approx(d.fear, 0.0))
	_check("20 days: trust fades slowest (35)", is_equal_approx(d.trust, 35.0) and is_equal_approx(d.affection, 35.0) and is_equal_approx(d.respect, 20.0))
	var e = m.ledger.get_dims("elena_daughter_001")
	_check("never met: familiarity falls below the floor; negative trust rises to 0", is_equal_approx(e.familiarity, 0.0) and is_equal_approx(e.trust, -5.0))
	# A loaded main follows the ledger
	var node = FakeNPC.new()
	node.npc_id = main_id
	node.add_to_group("npcs")
	root.add_child(node)
	m.test_now = T0 + 22 * DAY
	m.process_time()
	_check("a loaded NPC's feelings follow the decay", is_equal_approx(node.relationship_trust, 34.5) and is_equal_approx(node.relationship_familiarity, 5.0))
	m.note_contact(main_id)
	m.test_now = T0 + 22 * DAY + DAY - 1
	m.process_time()
	_check("contact restarts the clock", is_equal_approx(m.ledger.get_dims(main_id).trust, 34.5))
	node.queue_free()
	_check("world.json rates and floor were read", m.ledger.rates.trust == 0.25 and m.ledger.familiarity_floor == 5.0 and int(m.tiers.promote_at) == 60)

func _test_significance():
	print("-- significance --")
	var m = _make_manager()
	var inst = m.get_instance("gen_farmer_2")
	_check("an unmet stranger with no layers has significance 0", m.compute_significance(inst) == 0.0)
	m.ledger.set_dims(inst.id, {"trust": 50, "affection": 50, "respect": 20, "fear": 0, "familiarity": 40}, m.test_now)
	m.note_contact(inst.id)
	var parts = m.get_significance_parts(inst)
	_check("relationship part = 40 * min(strength/50, 1) (strength 37 -> 29.6)", is_equal_approx(parts.relationship, 29.6))
	_check("recency is 15 right after contact", is_equal_approx(parts.recency, 15.0))
	m.record_interaction(inst.id, "life_saved", {})
	m.record_interaction(inst.id, "gift_given", {})
	parts = m.get_significance_parts(inst)
	_check("layers part from the strongest layers (10+7+2 -> 14.25)", is_equal_approx(parts.layers, 14.25))
	m.on_news_spread("fx_witness", "A cart burned.", "witnessed", [], "western_valley", "thornhaven_town_square")
	m.on_news_spread("fx_gossip", "A cart burned again.", "gossip", ["*"], "western_valley", "")
	parts = m.get_significance_parts(inst)
	_check("story involvement: 3 per witnessed + 2 per gossip", is_equal_approx(parts.story, 5.0))
	_check("total is the sum, clamped 0-100", is_equal_approx(parts.total, parts.relationship + parts.layers + parts.story + parts.recency) and parts.total <= 100.0)
	print("    gen_farmer_2: rel %.1f + layers %.1f + story %.1f + recency %.1f = %.1f" % [parts.relationship, parts.layers, parts.story, parts.recency, parts.total])
	m.test_now += 4 * DAY
	m.process_time()
	parts = m.get_significance_parts(inst)
	_check("4 days apart: recency 15/e, feelings and layers fade too", is_equal_approx(parts.recency, 15.0 * exp(-1.0)) and parts.total < 64.0)

func _test_promotion_hysteresis():
	print("-- promotion with hysteresis, generated soul --")
	var director = FakeDirector.new()
	var m = _make_manager("", -1, director)
	var id = "gen_farmer_1"
	var inst = m.get_instance(id)
	_make_significant(m, id)
	_check("significance at or above promote_at (%.1f)" % inst.significance, inst.significance >= 60.0)
	m.evaluate_round()
	m.evaluate_round()
	_check("2 rounds above the bar: still generic", inst.tier == "generic" and inst.rounds_at_threshold == 2)
	var saved = m.ledger.get_dims(id)
	m.ledger.set_dims(id, {"trust": 0, "affection": 0, "respect": 0, "fear": 0, "familiarity": 0}, m.test_now)
	m.evaluate_round()
	_check("one round below resets the count", inst.rounds_at_threshold == 0 and inst.tier == "generic")
	m.ledger.set_dims(id, saved, m.test_now)
	m.evaluate_round()
	m.evaluate_round()
	_check("rounds 1-2 again: still generic", inst.tier == "generic")
	var result = m.evaluate_round()
	_check("3rd sustained round promotes", inst.tier == "promoted" and id in result.promoted and inst.promotions == 1)
	_check("SOUL.md saved under user://souls/<id>/", FileAccess.file_exists(SOULS + "/" + id + "/SOUL.md") and inst.soul_path == SOULS + "/" + id + "/SOUL.md")
	var text = FileAccess.get_file_as_string(SOULS + "/" + id + "/SOUL.md")
	var check = SoulBuilder.validate_soul_text(text, id, true)
	_check("generated soul passes the Soul parser and strict §8 Life check", check.ok and check.arcs == 2)
	if not check.ok:
		print("    errors: %s" % [check.errors])
	var top = inst.wants_by_weight(m.get_archetype("farmer").want_order)[0]
	_check("a Life arc grown from the strongest want", text.contains("### Arc: `%s_grown` (serves `%s`)" % [top.to_lower(), top]))
	_check("its result flag starts with the instance id", text.contains("- result: `%s_%s_grown_begun`:" % [id, top.to_lower()]))
	_check("full personal-scope converse agency", check.soul.get_converse_grants() == ["agenda", "move_npc", "adjust_relationship", "shift_want", "spread_rumor"])
	_check("the layers are in its essence", text.contains("The stranger changed that:") and text.contains("saved my life"))
	_check("Director tier set to promoted", director.tier_of(id) == "promoted")
	_check("its own ChromaDB collection is enabled", inst.memory_mode == "chroma" and inst.memory_collection == "npc_gen_farmer_1_memories")
	_check("history records the promotion", inst.history.any(func(h): return h.event == "promoted"))
	print("    promoted soul: %d chars, %d Life arcs" % [text.length(), check.arcs])
	# personal turns once promoted (contract: only main and promoted souls get them)
	_check("joins the personal-turn pool", id in director.personal_turn_pool() and not ("gen_farmer_2" in director.personal_turn_pool()))
	_check("its personal turn works on its first Life step", director.personal_turn(id) == "save_pennies")

func _test_in_character_rewrite():
	print("-- Claude-mode soul rewrite (validated or fallback) --")
	var m = _make_manager()
	var id = "gen_farmer_2"
	m.promote(id, true)
	var inst = m.get_instance(id)
	var original = inst.soul_text
	m.soul_writer = func(text: String, _inst) -> String:
		return text.replace("- `keep_the_farm`", "- `keep_the_farm_forever`")
	var accepted = await m.rewrite_soul_in_character(id)
	_check("a rewrite that changes machine lines is rejected", not accepted and inst.soul_text == original)
	m.soul_writer = func(text: String, _inst) -> String:
		return text.replace("Plain words, weather and soil in every sentence.", "Talks like the soil talks: slow, and only when it must.")
	accepted = await m.rewrite_soul_in_character(id)
	_check("a prose-only rewrite that parses is accepted", accepted and inst.soul_text.contains("Talks like the soil talks"))
	m.soul_writer = func(_text: String, _inst) -> String:
		return "not a soul at all"
	var before = inst.soul_text
	accepted = await m.rewrite_soul_in_character(id)
	_check("garbage falls back to the current soul", not accepted and inst.soul_text == before)

func _test_demotion_residue():
	print("-- demotion with residue --")
	var director = FakeDirector.new()
	var m = _make_manager("", -1, director)
	var id = "gen_farmer_1"
	var inst = m.get_instance(id)
	_make_significant(m, id)
	for i in 3:
		m.evaluate_round()
	_check("promoted first", inst.tier == "promoted")
	var nudges_before = inst.trait_nudges.duplicate()
	var name_before = inst.name
	var history_before = inst.history.size()
	m.simulate_days_apart(3)
	_check("3 days apart, still significant: stays promoted", inst.tier == "promoted")
	m.ledger.set_dims(id, {"trust": 2, "affection": 2, "respect": 0, "fear": 0, "familiarity": 5}, m.test_now)
	m.simulate_days_apart(2)
	_check("significance <= 30 but only 5 days apart: stays promoted (dwell)", inst.tier == "promoted" and inst.significance <= 30.0)
	m.simulate_days_apart(3)
	_check("8 days apart and <= 30: demoted", inst.tier == "generic")
	var residue = inst.layers.filter(func(l): return l.kind == "residue")
	_check("residue: its 3 strongest memories as one-line layers", residue.size() == 3 and residue.all(func(l): return l.text.begins_with("Long ago:") and not "\n" in l.text and l.text.length() <= 110))
	_check("residue keeps the strongest (the life saved)", residue.any(func(l): return "saved my life" in l.text))
	_check("remembers the player like an old acquaintance", inst.layers.any(func(l): return l.kind == "acquaintance" and "old acquaintance" in l.text) and inst.layers.size() == 4)
	var halved = true
	for t in nudges_before:
		halved = halved and int(inst.trait_nudges[t]) == int(int(nudges_before[t]) / 2)
	_check("trait nudges halved", halved and not nudges_before.is_empty())
	_check("name and history kept", inst.name == name_before and inst.history.size() == history_before + 1 and inst.history[-1].event == "demoted")
	_check("Director tier back to generic: no personal turns", director.tier_of(id) == "generic" and not (id in director.personal_turn_pool()))
	_check("chroma retrieval stops (layers only)", inst.memory_mode == "layers" and not m.wants_chroma(id))
	var check = SoulBuilder.validate_soul_text(inst.soul_text, id)
	_check("generic soul again: valid, archetype arc only (generated arc gone)", check.ok and check.arcs == 1 and not inst.soul_text.contains("_grown"))
	_check("promoted SOUL.md retired", not FileAccess.file_exists(SOULS + "/" + id + "/SOUL.md") and FileAccess.file_exists(SOULS + "/" + id + "/SOUL.demoted.md"))
	_check("prompt shows the residue", m.get_prompt_block(id, false).contains("Long ago:"))

func _test_repromotion_bonus():
	print("-- re-promotion bonus --")
	var m = _make_manager()
	var inst = m.get_instance("gen_farmer_3")
	_check("first promotion needs 60", m.promote_threshold(inst) == 60.0)
	inst.promotions = 1
	_check("after one promotion: 50", m.promote_threshold(inst) == 50.0)
	inst.promotions = 2
	_check("after two: 40", m.promote_threshold(inst) == 40.0)
	inst.promotions = 5
	_check("never below the floor 40", m.promote_threshold(inst) == 40.0)
	inst.promotions = 1
	_make_significant(m, inst.id, 0.75)
	print("    re-promotion candidate significance %.1f" % inst.significance)
	_check("significance between 50 and 60", inst.significance >= 50.0 and inst.significance < 60.0)
	for i in 3:
		m.evaluate_round()
	_check("re-promoted at the lower bar after 3 rounds", inst.tier == "promoted" and inst.promotions == 2)

func _test_mains_never_demote():
	print("-- mains are anchored --")
	var m = _make_manager()
	_check("gregor is anchored", m.is_anchored("gregor_merchant_001"))
	_check("demote refuses a main", not m.demote("gregor_merchant_001").ok and "anchored" in m.demote("gregor_merchant_001").reason)
	_check("promote refuses a main", not m.promote("gregor_merchant_001").ok)
	m.ledger.set_dims("gregor_merchant_001", {"trust": 1}, m.test_now)
	m.ledger.note_contact("gregor_merchant_001", m.test_now)
	m.simulate_days_apart(60)
	_check("a long-neglected main is still not demoted (only generics are)", m.get_promoted_ids().is_empty() and not m.is_generic("gregor_merchant_001"))
	_check("generics are not anchored", not m.is_anchored("gen_farmer_1"))

func _test_generic_names_canon():
	print("-- generic names accepted by memory validation --")
	var world_events = root.get_node("WorldEvents")
	# Margaret is on the hallucination list; no fixture or roster NPC is called that
	var text = "Margaret Quillon sold me a sack of turnips."
	world_events.unregister_npc_names_from("test_margaret")
	_check("before registering, Margaret is a hallucination", not world_events.validate_memory(text, "gen_test").valid)
	world_events.register_npc_name("Margaret Quillon", "test_margaret")
	var v = world_events.validate_memory(text, "gen_test")
	_check("a registered generic name is valid canon", v.valid and v.issues.is_empty())
	world_events.unregister_npc_names_from("test_margaret")
	_check("unregistering makes it unknown again", not world_events.validate_memory(text, "gen_test").valid)
	var m = _make_manager()
	var inst = m.get_instance("gen_farmer_1")
	_check("instances register their names", world_events.is_registered_npc_name(inst.name))
	v = world_events.validate_memory("I traded words with %s at the well." % inst.name, "gregor_merchant_001")
	_check("memories naming a generic pass validation", v.valid and v.issues.is_empty())
	var rag = load("res://scripts/npcs/rag_memory.gd").new()
	root.add_child(rag)
	rag.initialize("test_generic_names", null, false)
	var stored = rag.store({"text": "%s told me the harvest was poor." % inst.name, "event_type": "conversation", "importance": 5})
	_check("in-memory RAG stores a memory that names a generic", stored and rag.memory_cache.size() == 1)
	rag.queue_free()

func _test_gossip_reaches_generics():
	print("-- gossip reaching generics --")
	var m = _make_manager()
	var propagator = root.get_node("EventPropagator")
	var pending_before = propagator.get_pending_count()
	propagator.spread_flag("gregor_exposed", ["*"], "talk in the square", 8, "western_valley")
	var inst = m.get_instance("gen_farmer_1")
	_check("EventPropagator gossip reaches generics in the region", inst.has_layer_tag("news:gregor_exposed") and inst.gossip_heard == 1)
	_check("every generic in the valley heard it", m.get_ids().all(func(id): return m.get_instance(id).has_layer_tag("news:gregor_exposed")))
	_check("generics never enter the roster's pending queue", propagator.get_pending_count("gen_farmer_1") == 0 and propagator.get_pending_count() >= pending_before)
	_check("they can repeat it (in their prompt, marked as passable)", m.get_prompt_block("gen_farmer_1", false).contains("you may pass it on"))
	var gossip = inst.layers.filter(func(l): return l.tag == "news:gregor_exposed")
	_check("the layer carries the flag for spread_rumor", gossip.size() == 1 and gossip[0].flag == "gregor_exposed")
	var reached = m.on_news_spread("fx_far", "News from the Kingsroad.", "gossip", ["*"], "kingsroad", "")
	_check("news in another region does not reach valley generics", reached.is_empty())
	reached = m.on_news_spread("fx_mira", "Mira's news.", "gossip", ["mira"], "western_valley", "")
	_check("targeted gossip reaches only generics sharing the listener's place", reached.is_empty())
	reached = m.on_news_spread("fx_elena", "Elena's news.", "gossip", ["elena"], "western_valley", "")
	_check("...a generic in the square overhears news meant for Elena there", "gen_farmer_1" in reached and not ("gen_farmer_3" in reached))
	reached = m.on_news_spread("fx_seen", "A fight broke out.", "witnessed", [], "western_valley", "old_mill")
	_check("witnesses: generics present where it happened", reached == ["gen_farmer_3"] and m.get_instance("gen_farmer_3").witnessed == 1)

func _test_save_load_roundtrip():
	print("-- save/load round-trip --")
	var m = _make_manager()
	_make_significant(m, "gen_farmer_1")
	for i in 3:
		m.evaluate_round()
	m.record_interaction("gen_gate_guard_1", "threat_made", {"player_message": "Move aside."})
	m.ledger.set_dims("gregor_merchant_001", {"trust": 12, "familiarity": 9}, m.test_now)
	var data = JSON.parse_string(JSON.stringify(m.save()))
	var director = FakeDirector.new()
	var m2 = _make_manager("", -1, director, false)
	m2.load_from_dict(data)
	var same = m2.get_ids() == m.get_ids()
	for id in m.get_ids():
		same = same and JSON.stringify(m2.get_instance(id).to_dict()) == JSON.stringify(m.get_instance(id).to_dict())
	_check("instances, layers, tiers, histories and soul texts survive JSON", same)
	_check("the ledger (every NPC's feelings and last contact) survives", JSON.stringify(m2.ledger.save()) == JSON.stringify(m.ledger.save()))
	_check("souls re-registered with their tiers on load", director.tier_of("gen_farmer_1") == "promoted" and director.tier_of("gen_farmer_2") == "generic" and director.souls.size() == 5)
	_check("names re-registered on load", root.get_node("WorldEvents").is_registered_npc_name(m2.get_instance("gen_gate_guard_1").name))
	var world_state = root.get_node("WorldState")
	_check("WorldState's save carries the generics block", world_state.save().has("generics") and world_state.save().generics.has("instances"))

func _test_spawner():
	print("-- spawner populates scenes --")
	var m = _make_manager()
	var registry = root.get_node("DynamicNPCRegistry")
	var saved = registry.generics
	registry.generics = m
	var scene = Node2D.new()
	var points = Node2D.new()
	points.name = "SpawnPoints"
	var default = Marker2D.new()
	default.name = "default"
	points.add_child(default)
	scene.add_child(points)
	root.add_child(scene)
	var spawner = Spawner.new()
	spawner.initialize_spawned = false
	spawner.instancer = func(key: String, scene_path: String) -> Node:
		return load(scene_path).instantiate() if key.begins_with("gen_") else null
	root.add_child(spawner)
	var report = spawner.reconcile("thornhaven_town_square", scene)
	_check("generics present in the square are spawned", report.generics_spawned == ["gen_farmer_1", "gen_farmer_2", "gen_gate_guard_1"])
	var body = scene.find_child("Generic_gen_farmer_1", true, false)
	_check("the body is a GenericNPC bound to its instance", body != null and body.npc_name == m.get_instance("gen_farmer_1").name and body.personality_resource is NPCPersonality)
	_check("it reuses a sprite by archetype", body != null and body.get_node("GeneratableCharacter").character_id == "villager_male" and body.get_node("NameLabel").text == body.npc_name)
	report = spawner.reconcile("thornhaven_town_square", scene)
	_check("reconciling again keeps them (no duplicates)", report.generics_spawned.is_empty() and report.generics_kept.size() == 3)
	var world_state = root.get_node("WorldState")
	world_state.start_npc_travel("gen_farmer_2", "old_mill", 30, "thornhaven_town_square")
	report = spawner.reconcile("thornhaven_town_square", scene)
	_check("a travelling generic is freed from the scene", report.generics_freed == ["gen_farmer_2"])
	_check("...and is at its destination afterwards", m.get_location("gen_farmer_2") == "old_mill")
	world_state.npc_states.erase("gen_farmer_2")
	m.test_now = 22 * 60
	report = spawner.reconcile("village_gate", scene)
	_check("outside its hours a generic is away", not ("gen_gate_guard_2" in report.generics_spawned))
	m.test_now = 10 * 60
	report = spawner.reconcile("village_gate", scene)
	_check("inside its hours it is there", "gen_gate_guard_2" in report.generics_spawned)
	registry.generics = saved
	spawner.queue_free()
	scene.queue_free()

func _test_generic_npc_body():
	print("-- GenericNPC: conversation layering, tier switch (in-memory RAG) --")
	var m = _make_manager()
	var registry = root.get_node("DynamicNPCRegistry")
	var saved = registry.generics
	registry.generics = m
	var body = load("res://scenes/npcs/generic_npc.tscn").instantiate()
	body.setup("gen_farmer_2", m)
	root.add_child(body)
	var ok = await body.initialize(true, false)
	_check("initialize in generic tier stays in-memory (no ChromaDB)", ok and body.rag_memory != null and not body.rag_memory.use_chromadb)
	await body.record_interaction("gift_received", {"description": "Player gave me bread.", "importance": 6, "player_message": "For your table.", "thoughtfulness": "high"})
	await body._store_learned_player_info({"name": "Rowan"})
	var inst = m.get_instance("gen_farmer_2")
	_check("a conversation through BaseNPC layers on the instance", inst.has_layer_tag("moment:gift_received") and inst.has_layer_tag("learned:name"))
	_check("BaseNPC's relationship change reached the ledger", m.ledger.get_dims("gen_farmer_2").affection == body.relationship_affection and body.relationship_affection > 0.0)
	m.promote("gen_farmer_2", true)
	await process_frame
	await process_frame
	_check("promotion re-seeds its memory from the layers", body.rag_memory.memory_cache.size() == inst.layers.size())
	m.demote("gen_farmer_2", true)
	await process_frame
	await process_frame
	_check("demotion leaves only the residue in memory", body.rag_memory.memory_cache.size() == inst.layers.size() and inst.layers.size() <= 4)
	registry.generics = saved
	body.queue_free()

## The real StorylineDirector, when the arcs engine's API has landed (skipped otherwise)
func _test_real_director_contract():
	print("-- real StorylineDirector contract --")
	var director = root.get_node_or_null("StorylineDirector")
	if director == null or not director.has_method("register_soul"):
		print("    (register_soul not available yet; contract covered by the fake)")
		return
	var m = _make_manager("", -1, director)
	var id = "gen_farmer_1"
	_check("real Director accepts the rolled generic soul", director.get_soul(id) != null)
	m.promote(id, true)
	_check("real Director accepts the promoted soul", director.get_soul(id) != null)
	if director.has_method("get_soul_tier"):
		_check("real Director reports tier promoted", str(director.get_soul_tier(id)) == "promoted")
	_check("a promoted generic's location is in WorldState", root.get_node("WorldState").get_npc_location(id) == "thornhaven_town_square")
	if director.has_method("run_personal_turns"):
		var saved_cap = director.personal_decisions_per_round
		var saved_override = director.player_location_override
		director.personal_decisions_per_round = 100
		director.player_location_override = "thornhaven_town_square"
		var entries = await director.run_personal_turns("test_generics")
		var mine = entries.filter(func(e): return str(e.npc) == id)
		print("    real personal turn: %s" % ("; ".join(mine.map(func(e): return "%s %s %s" % [e.npc, e.choice, e.get("hook", "")])) if not mine.is_empty() else "none"))
		_check("the promoted generic takes a personal turn with the real Director", not mine.is_empty())
		_check("generic-tier instances take none", entries.filter(func(e): return str(e.npc).begins_with("gen_") and str(e.npc) != id).is_empty())
		director.personal_decisions_per_round = saved_cap
		director.player_location_override = saved_override
	m.demote(id, true)
	if director.has_method("get_soul_tier"):
		_check("real Director reports tier generic after demotion", str(director.get_soul_tier(id)) == "generic")
	await process_frame  # the manager's deferred Director hookup re-registers once; undo after it
	if director.has_method("unregister_soul"):
		for gid in m.get_ids():
			director.unregister_soul(gid)

# =============================================================================
# HELPERS
# =============================================================================

func _make_manager(arch_dir: String = "", seed: int = -1, director: Node = null, do_populate: bool = true) -> Node:
	var m = Manager.new()
	m.auto_boot = false
	m.use_chromadb = false
	m.write_souls_in_character = false
	m.souls_dir = SOULS
	m.test_now = T0
	m.director_override = director if director != null else FakeDirector.new()
	if director is FakeDirector and director not in _fakes:
		_fakes.append(director)
	if seed >= 0:
		m.world_seed = seed
	root.add_child(m)
	m.load_content(arch_dir if arch_dir != "" else FIX + "/archetypes", FIX + "/names.json", FIX + "/population.json")
	if do_populate:
		m.populate()
	_managers.append(m)
	return m

## Feelings, contact and moments enough to clear the promotion bar (scale < 1 for less)
func _make_significant(m: Node, id: String, scale: float = 1.0) -> void:
	m.ledger.set_dims(id, {"trust": 60 * scale, "affection": 60 * scale, "respect": 30 * scale, "fear": 0, "familiarity": 50 * scale}, m.test_now)
	m.note_contact(id)
	m.record_learned(id, {"name": "Rowan"})
	if scale >= 1.0:
		m.record_interaction(id, "life_saved", {"player_message": "Hold on, I have you."})
		m.record_interaction(id, "secret_shared", {"player_message": "I am not who I say."})
		m.record_interaction(id, "gift_given", {"player_message": "Bread, for the winter."})
	else:
		m.record_interaction(id, "gift_given", {"player_message": "Bread."})
	m.get_instance(id).significance = m.compute_significance(m.get_instance(id))

func _has_error(arch, needle: String) -> bool:
	return arch.errors.any(func(e): return needle in e)

func _clean_souls_dir() -> void:
	var dir = DirAccess.open(SOULS)
	if dir == null:
		return
	for sub in dir.get_directories():
		var d2 = DirAccess.open(SOULS + "/" + sub)
		if d2:
			for f in d2.get_files():
				d2.remove(f)
		dir.remove(sub)
	DirAccess.remove_absolute(SOULS)

func _check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("  PASS %s" % label)
	else:
		failures += 1
		print("  FAIL %s" % label)
