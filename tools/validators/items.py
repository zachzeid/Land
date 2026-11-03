"""Item definitions (resources/items/*.json) for the Inventory (docs/PLAYER_SYSTEMS.md §6).

Each file is {"items": [...]}; each item {id, name, kind, weight, stack, value (pennies), tags, ...}.
Checks: unique snake_case ids, known kinds, sane weight/stack/value, equipment slots and the kinds that
may use them, durability only on unstackable things, ammunition that exists, known_by keys and
factions that exist, no forbidden concepts in any text. Stdlib only.
"""
import json
import re

KINDS = {"weapon", "armour", "tool", "material", "food", "remedy", "misc"}
SLOTS = {"main_hand", "off_hand", "body", "head", "tool"}
SLOT_KINDS = {"main_hand": {"weapon", "tool"}, "off_hand": {"weapon", "tool", "armour"},
              "body": {"armour"}, "head": {"armour"}, "tool": {"tool"}}
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
REQUIRED = ("id", "name", "kind", "weight", "stack", "value", "tags")


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def validate(ctx):
    root, err, warn = ctx["root"], ctx["err"], ctx["warn"]
    folder = root / "resources/items"
    if not folder.exists():
        err("resources/items", "missing (Inventory item definitions)")
        return
    factions = {f["id"] for f in ctx["world"].get("factions", [])}
    npcs = set(ctx["npc_keys"])
    seen = {}
    ammo_refs = []
    for path in sorted(folder.glob("*.json")):
        where = str(path.relative_to(root))
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError as e:
            err(where, f"invalid JSON: {e}")
            continue
        if not isinstance(data, dict) or not isinstance(data.get("items"), list):
            err(where, "needs an 'items' array")
            continue
        for item in data["items"]:
            iw = f"{where}:{item.get('id') if isinstance(item, dict) else '?'}"
            if not isinstance(item, dict):
                err(iw, "an item must be an object")
                continue
            missing = [f for f in REQUIRED if f not in item]
            if missing:
                err(iw, f"missing {', '.join(missing)}")
                continue
            iid = item["id"]
            if not isinstance(iid, str) or not ID_RE.match(iid):
                err(iw, "id must be snake_case")
            elif iid in seen:
                err(iw, f"duplicate id (also in {seen[iid]})")
            else:
                seen[iid] = where
            if not isinstance(item["name"], str) or not item["name"].strip():
                err(iw, "name must be a non-empty string")
            if item["kind"] not in KINDS:
                err(iw, f"kind '{item['kind']}' not one of {sorted(KINDS)}")
            if not _num(item["weight"]) or not 0 <= item["weight"] <= 40:
                err(iw, "weight must be a number 0-40")
            if not isinstance(item["stack"], int) or isinstance(item["stack"], bool) or not 1 <= item["stack"] <= 100:
                err(iw, "stack must be an int 1-100")
            if not isinstance(item["value"], int) or isinstance(item["value"], bool) or not 0 <= item["value"] <= 24000:
                err(iw, "value must be whole pennies 0-24000 (100 crowns)")
            if not isinstance(item["tags"], list) or any(not isinstance(t, str) or not ID_RE.match(t) for t in item["tags"]):
                err(iw, "tags must be a list of snake_case strings")
            slots = item.get("slots", [])
            if not isinstance(slots, list) or any(s not in SLOTS for s in slots):
                err(iw, f"slots must be a list of {sorted(SLOTS)}")
                slots = []
            for s in slots:
                if item["kind"] not in SLOT_KINDS[s]:
                    err(iw, f"a {item['kind']} cannot go in the {s} slot")
            if slots and item.get("stack", 1) != 1:
                err(iw, "equipment must not stack (stack 1)")
            dur = item.get("max_durability", 0)
            if not _num(dur) or dur < 0:
                err(iw, "max_durability must be a number >= 0")
            elif dur > 0 and item.get("stack", 1) != 1:
                err(iw, "only unstackable items wear out (max_durability with stack > 1)")
            elif item["kind"] in ("weapon", "armour", "tool") and slots and dur <= 0:
                warn(iw, "equipment without max_durability never wears out")
            if "two_handed" in item.get("tags", []) and slots != ["main_hand"]:
                err(iw, "a two_handed item goes only in main_hand")
            if "ammunition" in item:
                ammo_refs.append((iw, item["ammunition"]))
            for k in item.get("known_by", []):
                if k not in npcs:
                    err(iw, f"known_by '{k}' is not an npc key")
            for f in item.get("known_by_faction", []):
                if f not in factions:
                    err(iw, f"known_by_faction '{f}' is not a faction")
            effects = item.get("effects", {})
            if not isinstance(effects, dict) or any(not _num(v) for v in effects.values()):
                err(iw, "effects must map names to numbers")
            elif effects and item["kind"] not in ("food", "remedy"):
                warn(iw, "only food and remedies have effects")
            text = json.dumps(item).lower()
            for w in ctx["forbidden"]:
                if re.search(r"\b" + re.escape(w) + r"s?\b", text):
                    err(iw, f"forbidden concept '{w}'")
    for iw, ammo in ammo_refs:
        if ammo not in seen:
            err(iw, f"ammunition '{ammo}' is not an item")
    for need in ("iron_ore", "steel_bar", "wood", "fever_root", "white_salt", "bread", "spare_lot_tile"):
        if need not in seen:
            err("resources/items", f"the starting world needs item '{need}'")
