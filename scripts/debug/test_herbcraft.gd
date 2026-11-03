extends SceneTree

# Tests Herbcraft (docs/PLAYER_SYSTEMS.md §4 "Herbcraft and cooking"):
# - ingredients load from resources/crafting/ingredients.json; ingredient() and the canon ones exist
# - cook() is deterministic and order-blind; skill raises potency and the effects with it
# - nonsense makes dubious food; poison spoils any remedy; bad input makes nothing
# - fever-root + white salt makes the Grey Fever cure; root alone (or salt alone) only quiets it, and says so
# - story_flag_for: the cure maps to a flag the real grey_fever storyline declares, and nothing else does
# - tools/validate_world.py (with tools/validators/herbcraft.py) reports 0 errors
# Pure static calls: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_herbcraft.gd

const Herbcraft = preload("res://scripts/crafting/herbcraft.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	print("============================================================")
	print("🧪 HERBCRAFT TEST")
	print("============================================================\n")

	print("Ingredients")
	var ids = Herbcraft.all_ingredient_ids()
	_check("20-30 ingredients load (%d)" % ids.size(), ids.size() >= 20 and ids.size() <= 30)
	var root = Herbcraft.ingredient("fever_root")
	_check("fever_root is defined, with the fever tag", "fever" in root.get("tags", []))
	_check("white_salt is defined and story-gated", Herbcraft.ingredient("white_salt").get("story_gated", false))
	_check("An unknown ingredient is {}", Herbcraft.ingredient("dragon_scale").is_empty())
	_check("ingredient() hands out a copy", _mutate_copy())
	_check("River herbs grow at Ferrisford", "watercress" in Herbcraft.ingredients_at("ferrisford"))
	_check("Seasons filter (no watercress in autumn)", not "watercress" in Herbcraft.ingredients_at("ferrisford", "autumn"))

	print("\nDeterminism")
	var a = Herbcraft.cook(["mutton", "garlic", "common_salt"], 40.0)
	var b = Herbcraft.cook(["common_salt", "mutton", "garlic"], 40.0)
	_check("Same inputs, any order, same result", JSON.stringify(a) == JSON.stringify(b))
	_check("...twice over", JSON.stringify(a) == JSON.stringify(Herbcraft.cook(["mutton", "garlic", "common_salt"], 40.0)))
	_check("Meat makes a stew", a.item_id == "meat_stew" and a.kind == "food" and not a.dubious)
	_check("A stew of mutton and garlic heals and warms", a.effects.get("healing", 0) > 0 and a.effects.get("warmth_minutes", 0) > 0)

	print("\nSkill and potency")
	var low = Herbcraft.cook(["comfrey", "yarrow"], 0.0)
	var high = Herbcraft.cook(["comfrey", "yarrow"], 100.0)
	_check("Herbs alone make a remedy", low.item_id == "healing_draught" and low.kind == "remedy")
	_check("Skill raises potency (%.2f -> %.2f)" % [low.potency, high.potency], high.potency > low.potency)
	_check("...and healing (%d -> %d)" % [low.effects.healing, high.effects.healing], high.effects.healing > low.effects.healing)
	_check("...and quality", high.quality > low.quality)
	_check("Skill is clamped to 0-100", JSON.stringify(Herbcraft.cook(["comfrey"], 500.0)) == JSON.stringify(Herbcraft.cook(["comfrey"], 100.0)))
	var plain = Herbcraft.cook(["mutton"], 50.0)
	var salted = Herbcraft.cook(["mutton", "common_salt"], 50.0)
	_check("Salt alone does nothing, but a seasoned meal does more", salted.effects.healing > plain.effects.healing)
	_check("Sleep, stamina, warmth remedies", Herbcraft.cook(["valerian_root"], 50.0).effects.get("sleep_minutes", 0) > 0 \
		and Herbcraft.cook(["watercress"], 50.0).item_id == "rousing_tonic" \
		and Herbcraft.cook(["ginger_root"], 50.0).effects.get("warmth_minutes", 0) > 0)

	print("\nDubious food and poison")
	var nothing = Herbcraft.cook(["common_salt"], 50.0)
	_check("Salt alone is dubious food", nothing.dubious and nothing.item_id == "dubious_food")
	var clash = Herbcraft.cook(["valerian_root", "watercress"], 80.0)
	_check("Sleep with stamina is dubious ('%s')" % clash.reason, clash.dubious and clash.item_id == "dubious_food")
	var muddle = Herbcraft.cook(["ginger_root", "hops", "fever_root"], 80.0)
	_check("Three effects pulling apart is dubious", muddle.dubious)
	_check("Dubious food heals a little, whatever the skill", nothing.effects.get("healing", 0) > 0 and JSON.stringify(nothing.effects) == JSON.stringify(Herbcraft.cook(["common_salt"], 0.0).effects))
	var poisoned = Herbcraft.cook(["eel", "deathcap"], 50.0)
	_check("Poison in a stew looks like stew and harms", poisoned.item_id == "tainted_food" and poisoned.effects.get("poison", 0) > 0 and not poisoned.effects.has("healing"))
	_check("Poison spoils a remedy", Herbcraft.cook(["comfrey", "nightshade_berries"], 50.0).item_id == "poison_draught")
	_check("No ingredients make nothing", Herbcraft.cook([], 50.0).item_id == "" and Herbcraft.cook([], 50.0).reason != "")
	_check("Six ingredients make nothing", Herbcraft.cook(["oats", "oats", "oats", "oats", "oats", "oats"], 50.0).item_id == "")
	_check("Five do", Herbcraft.cook(["oats", "oats", "oats", "oats", "oats"], 50.0).item_id == "pottage")
	_check("An unknown ingredient makes nothing", Herbcraft.cook(["oats", "dragon_scale"], 50.0).item_id == "")

	print("\nThe Grey Fever")
	var cure = Herbcraft.cook(["white_salt", "fever_root"], 30.0)
	_check("Fever-root + white salt is the cure", cure.item_id == "grey_fever_cure" and cure.effects.get("fever", "") == Herbcraft.FEVER_CURE and not cure.dubious)
	_check("...in either order", Herbcraft.cook(["fever_root", "white_salt"], 30.0).item_id == "grey_fever_cure")
	_check("...with honey to soften it", Herbcraft.cook(["fever_root", "white_salt", "honey"], 30.0).item_id == "grey_fever_cure")
	_check("...but poison spoils it", Herbcraft.cook(["fever_root", "white_salt", "nightshade_berries"], 30.0).item_id == "poison_draught" \
		and not Herbcraft.cook(["fever_root", "white_salt", "deathcap"], 30.0).effects.has("fever"))
	var tea = Herbcraft.cook(["fever_root"], 30.0)
	_check("Root alone only quiets the fever", tea.item_id == "fever_root_tea" and tea.effects.get("fever", "") == Herbcraft.FEVER_QUIET)
	_check("...for a few days (%d)" % tea.effects.get("fever_quiet_days", 0), tea.effects.get("fever_quiet_days", 0) >= 2 and tea.effects.get("fever_quiet_days", 0) <= 4)
	_check("...and the text says it cures nothing", "cures nothing" in tea.text.to_lower() and "quiet" in tea.text.to_lower())
	var salt = Herbcraft.cook(["white_salt"], 30.0)
	_check("Salt alone only holds it down too", salt.item_id == "salt_draught" and salt.effects.get("fever", "") == Herbcraft.FEVER_QUIET and "cures nothing" in salt.text.to_lower())
	_check("Two roots and skill quiet it longer", Herbcraft.cook(["fever_root", "fever_root"], 100.0).effects.fever_quiet_days > tea.effects.fever_quiet_days)

	print("\nStory flag")
	var flag = Herbcraft.story_flag_for("grey_fever_cure")
	var grey = JSON.parse_string(FileAccess.get_file_as_string("res://resources/storylines/grey_fever.json"))
	_check("The cure maps to a flag ('%s')" % flag, flag != "")
	_check("...that the real grey_fever storyline declares", grey is Dictionary and grey.get("flags", {}).has(flag))
	_check("...and that its beats react to", _referenced(grey, flag))
	_check("Root alone sets no flag", Herbcraft.story_flag_for("fever_root_tea") == "" and Herbcraft.story_flag_for("salt_draught") == "")
	_check("Ordinary food sets no flag", Herbcraft.story_flag_for("meat_stew") == "" and Herbcraft.story_flag_for("nonsense") == "")
	_check("The cure has a feat summary", Herbcraft.deed_for("grey_fever_cure") != "")
	_check("Every made item is defined", _all_defined())

	print("\nValidator")
	var output: Array = []
	var code = OS.execute("python3", [ProjectSettings.globalize_path("res://tools/validate_world.py")], output, true)
	if code == -1:
		print("  SKIP (python3 not found)")
	else:
		var text = "".join(output)
		_check("validate_world.py reports 0 errors", code == 0 and "\n0 error(s)" in text)
		_check("...with no herbcraft warnings", not "ingredients.json" in text)

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _mutate_copy() -> bool:
	var ing = Herbcraft.ingredient("honey")
	ing.name = "changed"
	return Herbcraft.ingredient("honey").name == "Honey"

func _all_defined() -> bool:
	var pots = [["fever_root", "white_salt"], ["fever_root"], ["white_salt"], ["comfrey"], ["watercress"], ["ginger_root"],
		["valerian_root"], ["deathcap"], ["mutton"], ["eel"], ["oats"], ["eel", "deathcap"], ["common_salt"]]
	for pot in pots:
		var r = Herbcraft.cook(pot, 50.0)
		if r.item_id == "" or Herbcraft.dish(r.item_id).is_empty():
			print("    undefined: %s -> %s" % [pot, r.item_id])
			return false
	return true

## A beat requires or resolves on the flag, or a hook/beat effect sets it
func _referenced(story, flag: String) -> bool:
	if not (story is Dictionary):
		return false
	for beat in story.get("beats", []):
		if flag in beat.get("requires", []) or flag in beat.get("resolves_on", []):
			return true
	return false

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
