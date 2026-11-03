extends SceneTree

# Tests the emergent beats that let the player systems change NPCs (docs/PLAYER_SYSTEMS.md §7), with
# the real content: resources/emergence templates, the real souls and the generic population.
# Each deed is recorded through the real PlayerEvents with line-of-sight witnesses, as the systems do;
# the template must grow from it with sensible roles (real souls and generics), a story round must
# decide it, and every choice must be one the bound soul permits (nothing dropped by Agency or Lines)
# - rival_smith: a feat at a forge Bjorn saw; not one he did not see, nor one away from a forge
# - would_be_apprentice: a young recruit who saw a feat (never a main soul)
# - challenger: a Hollow man who saw a feat wants to try the stranger
# - debt_of_the_spared: the spared repays or resents; a harm: Line keeps Davin from mocking Bjorn
# - who_lit_it: the burned and the neighbour seek a culprit; Aldric's crowd Line refuses the street
# - the_watch_answers: Aldric answers a harm in Thornhaven; his harm:elena Line refuses siding against her
# - known_by_the_mark, a_wolf_at_the_fold, buyer_for_the_blades, the_healer_from_away (word heard later)
# - emergent beats apply no storyline effect; the validator's rules hold for every new template
# No API calls, nothing reaches ./chroma (no NPC nodes are loaded), no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_player_emergence.gd

const DAY = 24 * 60
const STORY_ONLY = ["set_flag", "block_beat", "unlock_beat"]
const NEW_TEMPLATES = ["rival_smith", "would_be_apprentice", "challenger", "debt_of_the_spared", "who_lit_it",
	"the_watch_answers", "known_by_the_mark", "a_wolf_at_the_fold", "buyer_for_the_blades", "the_healer_from_away"]

var director: Node
var world_state: Node
var pe: Node
var gm: Node
var propagator: Node
var em
var failures: int = 0
var saved_flags: Dictionary
var saved_states: Dictionary
var saved_minutes: int
var saved_pe: Dictionary
var saved_gm: Dictionary
var saved_propagation: Dictionary
var save_existed: bool
var real_pe_capture = null

func _init():
	await process_frame
	await process_frame
	director = root.get_node("StorylineDirector")
	world_state = root.get_node("WorldState")
	pe = root.get_node("PlayerEvents")
	propagator = root.get_node("EventPropagator")
	var dyn = root.get_node_or_null("DynamicNPCRegistry")
	gm = dyn.generics if dyn and "generics" in dyn else null
	saved_flags = world_state.world_flags.duplicate(true)
	saved_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	saved_pe = pe.save()
	saved_gm = gm.save() if gm else {}
	saved_propagation = propagator.save()
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	world_state.set_idle_clock_rate(0.0)
	if "capture_enabled" in pe:
		real_pe_capture = pe.capture_enabled
		pe.capture_enabled = false
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	director.set_agency_mode("offline")
	director.end_on_season_end = false
	director.set_player_events(null)  # the real PlayerEvents
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	if gm:
		gm.register_all_souls()
	director.load_emergence("res://resources/emergence")
	em = director.get_emergence()

	print("============================================================")
	print("🧪 PLAYER EMERGENCE TEST")
	print("============================================================\n")

	_test_templates_load()
	await _test_rival_smith()
	await _test_would_be_apprentice()
	await _test_challenger()
	await _test_debt_of_the_spared()
	await _test_who_lit_it()
	await _test_the_watch_answers()
	await _test_known_by_the_mark()
	await _test_a_wolf_at_the_fold()
	await _test_buyer_for_the_blades()
	await _test_the_healer_from_away()
	_test_validator()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================

func _test_templates_load():
	print("Templates")
	_check("The shipped templates load without errors", director.get_emergence_errors().is_empty())
	for err in director.get_emergence_errors():
		print("    ! %s" % err)
	for tid in NEW_TEMPLATES:
		_check("%s is loaded" % tid, not em.get_template(tid).is_empty())

func _test_rival_smith():
	print("\nrival_smith: Bjorn sees true work at a forge")
	_reset({"bjorn": {"respect": 60}})
	var id = _record("feat", "forged a blade that rang true at the first quench", [], ["bjorn", "gen_woodcutter_2"], "thornhaven_blacksmith")
	var inst = _instance("rival_smith", id)
	_check("It grows, Bjorn the smith, a generic witness to carry the tale", inst.get("roles", {}).get("smith", "") == "bjorn" and inst.roles.get("talker", "") == "gen_woodcutter_2")
	_check("...at the smithy", inst.get("location", "") == "thornhaven_blacksmith")
	var made = await _decide(inst)
	_check("Bjorn, who respects the stranger, gives the work its due", made.get("bjorn", {}).get("choice", "") == "give_it_its_due")
	_check("The witness decides too (%s)" % made.get("gen_woodcutter_2", {}).get("choice", "-"), made.has("gen_woodcutter_2"))
	_clean(made)

	_reset({"bjorn": {"respect": -60, "affection": -60, "fear": -40}})
	id = _record("feat", "hammered out a sword in an afternoon", [], ["bjorn"], "thornhaven_blacksmith")
	inst = _instance("rival_smith", id)
	made = await _decide(inst)
	_check("A Bjorn who thinks little of them makes it a rivalry (his own want, honest_steel)", made.get("bjorn", {}).get("choice", "") == "show_whose_forge" and made.bjorn.applied.size() == 3)
	_clean(made)

	_reset({"bjorn": {"respect": 60}})
	id = _record("feat", "forged a blade at the smithy", [], ["gen_woodcutter_2"], "thornhaven_blacksmith")
	_check("No rival_smith when Bjorn did not see it", _instance("rival_smith", id).is_empty())
	id = _record("feat", "held the square against two men", [], ["bjorn"], "thornhaven_town_square")
	_check("...nor for a feat away from any forge", _instance("rival_smith", id).is_empty())

func _test_would_be_apprentice():
	print("\nwould_be_apprentice: a young recruit saw it")
	_reset({"gen_peacekeeper_recruit_3": {"respect": 50}})
	var id = _record("feat", "disarmed a Hollow rider at the gate with a staff", [], ["gen_peacekeeper_recruit_3", "aldric"], "village_gate")
	var inst = _instance("would_be_apprentice", id)
	_check("It grows: the recruit who saw it, not Captain Aldric (generics only)", inst.get("roles", {}).get("recruit", "") == "gen_peacekeeper_recruit_3" and not "aldric" in inst.roles.values())
	_check("...and no courier, since none of them knows of it", not inst.get("roles", {}).has("courier"))
	var made = await _decide(inst)
	_check("A recruit who respects the stranger asks to learn", made.get("gen_peacekeeper_recruit_3", {}).get("choice", "") == "ask_to_learn")
	_check("...and the agenda is theirs", director.get_agendas("gen_peacekeeper_recruit_3").any(func(a): return "teach you" in a.text))
	_clean(made)

	_reset({"gen_peacekeeper_recruit_3": {"fear": 70}})
	id = _record("feat", "broke a man's arm with one blow", [], ["gen_peacekeeper_recruit_3"], "village_gate")
	made = await _decide(_instance("would_be_apprentice", id))
	_check("A frightened one never dares ask", made.get("gen_peacekeeper_recruit_3", {}).get("choice", "") == "never_dare")
	_clean(made)
	_reset({})
	id = _record("feat", "climbed the mill wheel", [], [], "old_mill")
	_check("A feat nobody young knows of grows no apprentice", _instance("would_be_apprentice", id).is_empty())

func _test_challenger():
	print("\nchallenger: a Hollow man wants to try the stranger")
	_reset({"gen_hollow_grunt_1": {"respect": -50, "fear": -50}})
	var id = _record("feat", "held off three Hollow men with a blacksmith's hammer", [], ["gen_hollow_grunt_1"], "forest_path")
	var inst = _instance("challenger", id)
	_check("It grows with the Hollow man who saw it", inst.get("roles", {}).get("hollow", "") == "gen_hollow_grunt_1" and not inst.roles.has("soldier"))
	var made = await _decide(inst)
	_check("Unafraid and unimpressed, he calls them out", made.get("gen_hollow_grunt_1", {}).get("choice", "") == "call_them_out")
	_clean(made)
	_reset({"gen_hollow_grunt_1": {"fear": 80}})
	id = _record("feat", "cut down a Hollow rider in one stroke", [], ["gen_hollow_grunt_1"], "forest_path")
	made = await _decide(_instance("challenger", id))
	_check("A frightened one lets it lie", made.get("gen_hollow_grunt_1", {}).get("choice", "") == "let_it_lie")
	_clean(made)

func _test_debt_of_the_spared():
	print("\ndebt_of_the_spared: repays, or resents")
	_reset({"varn": {"trust": 40, "affection": 30}})
	var id = _record("spared", "had Varn on his back in the mud and let him walk away", ["varn"], ["varn", "gen_hollow_grunt_1"], "forest_path")
	var inst = _instance("debt_of_the_spared", id)
	_check("It grows: Varn the spared, a Hollow man who saw it", inst.get("roles", {}).get("spared", "") == "varn" and inst.roles.get("onlooker", "") == "gen_hollow_grunt_1")
	var made = await _decide(inst)
	_check("Varn, who has come to trust them, pays it back", made.get("varn", {}).get("choice", "") == "pay_it_back")
	_clean(made)

	_reset({"bjorn": {"respect": -60, "affection": -60}, "davin": {"respect": -80}})
	id = _record("spared", "beat Bjorn to his knees and lowered the hammer", ["bjorn"], ["bjorn", "davin"], "thornhaven_blacksmith")
	inst = _instance("debt_of_the_spared", id)
	_check("Davin saw it", inst.get("roles", {}).get("onlooker", "") == "davin")
	var hook = em.resolved_hook(inst, "how_it_is_told")
	_check("Mocking Bjorn appeals most to a Davin who scorns the stranger...", em.appeal_score(hook.options[1].appeal, director.get_relationship_dims("davin")) > em.appeal_score(hook.options[0].appeal, director.get_relationship_dims("davin")))
	made = await _decide(inst)
	_check("...but his harm:bjorn Line refuses it", made.has("davin") and made.davin.choice != "call_them_a_coward")
	_check("A Bjorn who resents it says so", made.get("bjorn", {}).get("choice", "") == "resent_it")
	_clean(made)

func _test_who_lit_it():
	print("\nwho_lit_it: the burned and the neighbours seek a culprit")
	_reset({"gen_valley_farmer_6": {"trust": -60}, "gen_woodcutter_3": {"trust": -50, "affection": -40}})
	var id = _record("fire", "set the old mill's barn alight", ["gen_valley_farmer_6"], ["gen_woodcutter_3"], "old_mill")
	var inst = _instance("who_lit_it", id)
	_check("It grows: the farmer who lost by it, the woodcutter who saw it", inst.get("roles", {}).get("victim", "") == "gen_valley_farmer_6" and inst.roles.get("neighbour", "") == "gen_woodcutter_3")
	var made = await _decide(inst)
	_check("The farmer names the stranger", made.get("gen_valley_farmer_6", {}).get("choice", "") == "name_the_stranger")
	_check("The woodcutter rouses the street (a crowd option)", made.get("gen_woodcutter_3", {}).get("choice", "") == "rouse_the_street")
	_clean(made)

	_reset({"gen_valley_farmer_1": {"trust": 10}, "aldric": {"trust": -50, "affection": -40}})
	id = _record("fire", "let a torch fall into the hay by the square", ["gen_valley_farmer_1"], ["aldric"], "thornhaven_town_square")
	inst = _instance("who_lit_it", id)
	_check("Aldric saw this one", inst.get("roles", {}).get("neighbour", "") == "aldric")
	made = await _decide(inst)
	_check("...and his crowd Line keeps him from rousing the street (%s)" % made.get("aldric", {}).get("choice", "-"), made.has("aldric") and made.aldric.choice not in ["rouse_the_street", "pass"])
	_clean(made)
	_reset({})
	id = _record("fire", "lit a fire in the forest", [], ["gen_woodcutter_4"], "forest_path")
	_check("A fire that cost nobody anything grows nothing", _instance("who_lit_it", id).is_empty())

func _test_the_watch_answers():
	print("\nthe_watch_answers: Aldric's watch, by soul")
	_reset({"aldric": {"trust": -50}})
	var id = _record("harm", "struck Gregor across the face in his own shop", ["gregor"], ["aldric", "gregor"], "thornhaven_gregor_shop")
	var inst = _instance("the_watch_answers", id)
	_check("It grows: Aldric keeps the peace, Gregor the hurt", inst.get("roles", {}).get("keeper", "") == "aldric" and inst.roles.get("victim", "") == "gregor")
	var made = await _decide(inst)
	_check("A distrustful Aldric brings the stranger in", made.get("aldric", {}).get("choice", "") == "bring_them_in")
	_clean(made)

	_reset({"aldric": {"trust": 60, "affection": 80}})
	id = _record("harm", "shoved Elena into the well trough", ["elena"], ["aldric"], "thornhaven_town_square")
	inst = _instance("the_watch_answers", id)
	var hook = em.resolved_hook(inst, "keeping_the_peace")
	var dims = director.get_relationship_dims("aldric")
	var side = em.appeal_score(hook.options[3].appeal, dims)
	_check("Siding with a fond stranger against Elena appeals most to him...", hook.options.slice(0, 3).all(func(o): return em.appeal_score(o.appeal, dims) < side))
	_check("...and is tagged as harming her", hook.options[3].get("harms", []) == ["elena"] and director.get_soul("aldric").get_option_denial_reason(hook.options[3]) != "")
	made = await _decide(inst)
	_check("...but Aldric's harm:elena Line refuses it (%s)" % made.get("aldric", {}).get("choice", "-"), made.has("aldric") and made.aldric.choice not in ["take_their_side", "pass"])
	_clean(made)

	_reset({})
	id = _record("harm", "knocked a recruit down in the square", ["gen_peacekeeper_recruit_1"], ["gen_valley_farmer_1"], "thornhaven_town_square")
	_check("Nobody of the watch knows of it yet: no beat", _instance("the_watch_answers", id).is_empty())
	id = _record("harm", "cut a Hollow man at the camp", ["gen_hollow_grunt_2"], ["aldric"], "iron_hollow_camp")
	_check("Iron Hollow's camp is not the watch's to keep", _instance("the_watch_answers", id).is_empty())

func _test_known_by_the_mark():
	print("\nknown_by_the_mark: the maker's name travels")
	_reset({"gen_valley_farmer_1": {"respect": 50}})
	var id = _record("crafted", "made Elena a pair of ridge boots, stitched true", ["elena"], ["gen_valley_farmer_1"], "thornhaven_town_square")
	var inst = _instance("known_by_the_mark", id)
	_check("It grows: a farmer who saw it, Elena who wears it", inst.get("roles", {}).get("seer", "") == "gen_valley_farmer_1" and inst.roles.get("bearer", "") == "elena")
	var made = await _decide(inst)
	_check("The farmer passes the maker's name on", made.get("gen_valley_farmer_1", {}).get("choice", "") == "pass_the_name_on")
	_check("Elena decides as herself (%s)" % made.get("elena", {}).get("choice", "-"), made.has("elena"))
	_clean(made)

func _test_a_wolf_at_the_fold():
	print("\na_wolf_at_the_fold: the valley asks for help")
	_reset({"gen_valley_farmer_2": {"trust": 50}})
	var id = _record("feat", "drove a boar off the road with a spear", [], ["gen_valley_farmer_2"], "thornhaven_town_square")
	var inst = _instance("a_wolf_at_the_fold", id)
	_check("It grows with the valley farmer who saw it", inst.get("roles", {}).get("keeper", "") == "gen_valley_farmer_2")
	var made = await _decide(inst)
	_check("A farmer who trusts the stranger asks them to sit up at the fold", made.get("gen_valley_farmer_2", {}).get("choice", "") == "ask_the_stranger")
	_clean(made)
	_reset({})
	id = _record("feat", "won a wrestling bout", [], ["gen_garrison_soldier_1"], "fort_ashguard")
	_check("Not for a feat outside the valley", _instance("a_wolf_at_the_fold", id).is_empty())

func _test_buyer_for_the_blades():
	print("\nbuyer_for_the_blades: arming the Hollow is noticed")
	_reset({"gen_hollow_grunt_2": {"trust": 50}, "gen_peacekeeper_recruit_1": {"trust": -50}, "bjorn": {"trust": -50, "affection": -30}})
	var id = _record("help", "sold three good blades to a Hollow man", ["gen_hollow_grunt_2"], ["gen_hollow_grunt_2", "gen_peacekeeper_recruit_1", "bjorn"], "thornhaven_tavern")
	var inst = _instance("buyer_for_the_blades", id)
	_check("It grows: the Hollow buyer, the recruit and Bjorn who saw it", inst.get("roles", {}).get("buyer", "") == "gen_hollow_grunt_2" and inst.roles.get("watch", "") == "gen_peacekeeper_recruit_1" and inst.roles.get("smith", "") == "bjorn")
	var made = await _decide(inst)
	_check("The buyer comes back for more", made.get("gen_hollow_grunt_2", {}).get("choice", "") == "come_back_for_more")
	_check("The recruit has it out with the stranger", made.get("gen_peacekeeper_recruit_1", {}).get("choice", "") == "have_it_out")
	_check("Bjorn says it to their face (and his own want, atone_for_the_steel, moves)", made.get("bjorn", {}).get("choice", "") == "say_it_to_their_face" and made.bjorn.applied.size() == 3)
	_clean(made)
	_reset({})
	id = _record("help", "carried Elena's basket", ["elena"], ["gen_valley_farmer_1"], "thornhaven_town_square")
	_check("Helping someone outside the Hollow is no sale of blades", _instance("buyer_for_the_blades", id).is_empty())

func _test_the_healer_from_away():
	print("\nthe_healer_from_away: those who hear come to ask")
	_reset({"gen_valley_widow_1": {"trust": 50}})
	var id = _record("help", "sat up with a fevered farmer and brought him through the night", ["gen_valley_farmer_5"], ["gen_valley_farmer_5"], "healer_hut")
	_check("Nobody has heard of it yet: nobody comes", _instance("the_healer_from_away", id).is_empty())
	var sent = pe.spread(id, ["gen_valley_widow_1"], "test")
	_check("(word is on its way to the widow)", not sent.get("scheduled", []).is_empty())
	world_state.advance_time(180, "test")
	_check("(she has heard it)", pe.fidelity_for(id, "gen_valley_widow_1") > 0.0)
	var inst = _instance("the_healer_from_away", id)
	_check("Once she hears, it grows: the widow asks, the farmer was the patient", inst.get("roles", {}).get("asker", "") == "gen_valley_widow_1" and inst.roles.get("patient", "") == "gen_valley_farmer_5")
	var made = await _decide(inst)
	_check("She asks the stranger for a remedy", made.get("gen_valley_widow_1", {}).get("choice", "") == "ask_for_a_remedy")
	_clean(made)

## The validator's own rules hold for the new templates (0 errors is checked by the suite's run of validate_world.py)
func _test_validator():
	print("\nEvery new template applies only emergent effects")
	for tid in NEW_TEMPLATES:
		var t: Dictionary = em.get_template(tid)
		var bad: Array = []
		for hook in t.get("hooks", []):
			for option in hook.options:
				for e in option.get("effects", []):
					if str(e.get("type", "")) in STORY_ONLY or str(e.get("type", "")) not in em.PERSONAL_EFFECTS + em.EXTRA_EFFECTS:
						bad.append(e.type)
		_check("%s: personal effects and spread_event only" % tid, bad.is_empty())

# =============================================================================

## A clean world: flags, NPC states, calendar (20:00, open), no instances, no player events, these feelings
func _reset(dims: Dictionary) -> void:
	world_state.world_flags = {}
	world_state.npc_states = {}
	world_state.load_calendar()
	world_state.reset_calendar(world_state.start_minute)
	director.reset_state()
	em.reset()
	pe.reset()
	director.player_location_override = ""
	var all: Dictionary = {}
	for key in director.get_soul_keys():
		all[key] = {}
	for key in dims:
		all[key] = dims[key]
	director.relationship_dims_override = all

## A physical deed as the systems record it: line-of-sight witnesses, no regional gossip (tested separately)
func _record(kind: String, summary: String, about: Array, witnesses: Array, location: String) -> String:
	director.player_location_override = location
	var ids: Array = witnesses.map(func(w): return director._npc_id(w))
	var id = pe.record(kind, summary, about.map(func(a): return director._npc_id(a)), {"witnesses": ids, "location": location, "spread": false})
	_check("(%s recorded with %d witness(es))" % [kind, witnesses.size()], id != "" and pe.get_event(id).witnesses.size() == witnesses.size())
	return id

func _instance(tid: String, event_id: String) -> Dictionary:
	for inst in director.get_emergent_instances():
		if inst.template == tid and inst.event_id == event_id:
			return inst
	return {}

## Run story rounds until every hook of the instance has been offered; npc -> its decision entry
func _decide(inst: Dictionary) -> Dictionary:
	var made: Dictionary = {}
	if inst.is_empty():
		_check("(no instance to decide)", false)
		return made
	for r in 4:
		await director.advance_round("test")
	for e in director.get_chronicle(0):
		if e.get("mode", "") == "emergent" and e.get("emergent", "") == inst.id and e.choice not in ["instantiated", "resolved", "expired"]:
			made[e.npc] = e
			print("    %s/%s: %s (%s)" % [e.npc, e.hook, e.choice, e.reason])
	var bound: Array = []
	var t: Dictionary = em.get_template(inst.template)
	for hook in t.hooks:
		var who = str(inst.roles.get(str(hook.eligible_role), ""))
		if who != "":
			bound.append(who)
	_check("A round decides it: every bound role with a hook chose (%d of %d)" % [made.size(), bound.size()], bound.all(func(k): return made.has(k) and made[k].choice != "pass"))
	return made

## Every choice is one the soul permits: nothing dropped, no storyline effect applied
func _clean(made: Dictionary) -> void:
	var dropped: Array = []
	var story: Array = []
	for k in made:
		for d in made[k].get("dropped", []):
			dropped.append("%s: %s" % [k, d.get("reason", "")])
		for e in made[k].get("applied", []):
			if str(e.get("type", "")) in STORY_ONLY:
				story.append(e.type)
	_check("...nothing dropped by Agency or Lines%s" % ("" if dropped.is_empty() else " %s" % [dropped]), dropped.is_empty())
	_check("...and no storyline flag or beat touched", story.is_empty())

func _restore() -> void:
	director.relationship_dims_override = {}
	director.player_location_override = ""
	director.end_on_season_end = true
	director.reset_state()
	em.reset()
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	pe.load_from_dict(saved_pe)
	propagator.load_from_dict(saved_propagation)
	if gm:
		gm.load_from_dict(saved_gm)
		gm.register_all_souls()
	if real_pe_capture != null:
		pe.capture_enabled = real_pe_capture
	world_state.world_flags = saved_flags
	world_state.npc_states = saved_states
	world_state.game_minutes = saved_minutes
	world_state.reset_calendar()
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1
