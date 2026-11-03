"""Herbcraft and cooking (docs/PLAYER_SYSTEMS.md §4): resources/crafting/ingredients.json.

Checks: every ingredient has a unique id, a known category, effect tags from the six the game applies,
strength 1-5 (0 only for untagged seasoning), locations from world.json and a season; every dish
herbcraft.gd can make is defined; the Grey Fever cure is fever_root + white_salt and its story flag is
declared by the grey_fever storyline; root alone is a remedy whose text says it only quiets the fever;
no forbidden concept and no wonder-working words in any name or text. Stdlib only.
"""
import json
import re

WHERE = "resources/crafting/ingredients.json"
TAGS = {"healing", "stamina", "warmth", "fever", "sleep", "poison"}
SEASONS = {"any", "spring", "summer", "autumn", "winter"}
KINDS = {"food", "remedy"}
# Every item_id herbcraft.gd can return
DISHES = {"grey_fever_cure", "fever_root_tea", "salt_draught", "healing_draught", "rousing_tonic", "warming_tonic",
          "sleeping_draught", "poison_draught", "meat_stew", "fish_stew", "pottage", "tainted_food", "dubious_food"}
REQUIRED_INGREDIENTS = {"fever_root", "white_salt"}
# Remedies, not wonders (world_rules: low magic, no spells)
WONDER_WORDS = ["potion", "magic", "magical", "spell", "elixir", "enchant", "enchanted", "sorcery", "mana", "wizard", "witchcraft"]


def _words(text, words):
    low = text.lower()
    return [w for w in words if re.search(r"\b" + re.escape(w) + r"s?\b", low)]


def validate(ctx):
    root, err, warn = ctx["root"], ctx["err"], ctx["warn"]
    path = root / WHERE
    if not path.exists():
        err(WHERE, "missing")
        return
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        err(WHERE, f"bad JSON: {e}")
        return
    categories = set(data.get("categories", {}))
    if set(data.get("effect_tags", {})) != TAGS:
        err(WHERE, f"effect_tags must document exactly {sorted(TAGS)}")

    ids = set()
    ingredients = data.get("ingredients", [])
    if not 20 <= len(ingredients) <= 30:
        err(WHERE, f"needs 20-30 ingredients, has {len(ingredients)}")
    for ing in ingredients:
        iid = ing.get("id", "")
        where = f"{WHERE} ingredient '{iid}'"
        if not re.fullmatch(r"[a-z][a-z0-9_]*", iid or ""):
            err(where, "id must be snake_case")
        if iid in ids:
            err(where, "duplicate id")
        ids.add(iid)
        if not ing.get("name") or not ing.get("text"):
            err(where, "needs name and text")
        if ing.get("category") not in categories:
            err(where, f"unknown category '{ing.get('category')}'")
        tags = ing.get("tags", [])
        bad = [t for t in tags if t not in TAGS]
        if bad:
            err(where, f"unknown tags {bad}")
        s = ing.get("strength")
        if not isinstance(s, int) or not (1 <= s <= 5 if tags else s == 0):
            err(where, "strength must be 1-5 (0 only with no tags)")
        if not tags and ing.get("category") != "seasoning":
            err(where, "only a seasoning may have no tags")
        found = ing.get("found_at", [])
        if not found:
            err(where, "needs found_at")
        for loc in found:
            if loc not in ctx["locations"]:
                err(where, f"unknown location '{loc}'")
        if ing.get("season") not in SEASONS:
            err(where, f"season must be one of {sorted(SEASONS)}")
    for req in REQUIRED_INGREDIENTS - ids:
        err(WHERE, f"canon ingredient '{req}' missing")

    dishes = {d.get("id"): d for d in data.get("dishes", [])}
    for missing in DISHES - set(dishes):
        err(WHERE, f"dish '{missing}' (made by herbcraft.gd) is not defined")
    for extra in set(dishes) - DISHES:
        warn(WHERE, f"dish '{extra}' is defined but herbcraft.gd never makes it")
    for did, d in dishes.items():
        if d.get("kind") not in KINDS or not d.get("name") or not d.get("text"):
            err(f"{WHERE} dish '{did}'", "needs name, text and kind food|remedy")

    # The Grey Fever: the cure sets the storyline's own flag; root alone says it only quiets
    grey_path = root / "resources/storylines/grey_fever.json"
    grey_flags = set(json.loads(grey_path.read_text()).get("flags", {})) if grey_path.exists() else set()
    cure = dishes.get("grey_fever_cure", {})
    flag = cure.get("story_flag", "")
    if not flag:
        err(WHERE, "grey_fever_cure needs a story_flag")
    elif flag not in grey_flags:
        err(WHERE, f"grey_fever_cure story_flag '{flag}' is not a grey_fever storyline flag")
    elif flag not in ctx["flags_known"]:
        err(WHERE, f"grey_fever_cure story_flag '{flag}' is not a known flag")
    if not cure.get("deed"):
        err(WHERE, "grey_fever_cure needs a deed (the feat summary)")
    for did in ("fever_root_tea", "salt_draught"):
        text = dishes.get(did, {}).get("text", "").lower()
        if ("quiet" not in text and "holds" not in text) or "cures nothing" not in text:
            err(f"{WHERE} dish '{did}'", "text must say it only quiets the fever and cures nothing")
        if dishes.get(did, {}).get("story_flag"):
            err(f"{WHERE} dish '{did}'", "only the true cure sets a story flag")

    text = json.dumps(data)
    for w in _words(text, ctx["forbidden"]):
        err(WHERE, f"forbidden concept '{w}'")
    for w in _words(text, WONDER_WORDS):
        err(WHERE, f"'{w}': these are remedies, not wonders")

    # Items (inventory slice): ingredients and dishes should be item definitions once both are merged
    item_ids = set()
    for p in sorted((root / "resources/items").glob("*.json")) if (root / "resources/items").exists() else []:
        try:
            raw = json.loads(p.read_text())
        except json.JSONDecodeError:
            continue
        rows = raw if isinstance(raw, list) else raw.get("items", list(raw.values()) if isinstance(raw, dict) else [])
        item_ids |= {r.get("id") for r in rows if isinstance(r, dict)}
    if item_ids:
        for missing in sorted((ids | set(dishes)) - item_ids):
            warn(WHERE, f"'{missing}' has no item definition in resources/items")
