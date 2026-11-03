"""Crafting content (docs/PLAYER_SYSTEMS.md §4): resources/crafting/{recipes,stations,nodes}.json.

Checks: ids unique and snake_case; stations at known locations, owned by a known npc key (or nobody),
of a known kind; recipes made at a known station kind, with positive inputs, a skill from the skill
list, a level 0-100, game minutes, an output, quality weights summing to 1, a learn mode (found
recipes name a known flag; taught ones need a teacher who has the skill), repairs at a known kind;
nodes at known locations, with a gathering skill, charges, regrow time, grade 0-100, owners that are
npc keys and gate flags that exist; no forbidden concept in any name or text. Item ids are checked
against resources/items/*.json when that exists (agent 2), else only for shape. Stdlib only.
"""
import json
import re

SEASONS = {"any", "spring", "summer", "autumn", "winter"}

SKILLS = {"blades", "blunt", "bows", "defence", "athletics", "stealth", "smithing", "woodcraft", "herbcraft",
          "mining", "speech", "lore"}
GATHER_SKILLS = {"woodcraft", "mining", "herbcraft", ""}
NODE_KINDS = {"tree", "stone", "ore", "herb", "flax", "stores", "hide"}
LEARN = {"discover", "taught", "found"}
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")


def _load(ctx, rel):
    path = ctx["root"] / rel
    if not path.exists():
        ctx["err"](rel, "missing")
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as e:
        ctx["err"](rel, f"bad JSON: {e}")
        return None


def _item_ids(ctx):
    d = ctx["root"] / "resources/items"
    if not d.exists():
        return None
    ids = set()
    for p in sorted(d.glob("*.json")):
        try:
            data = json.loads(p.read_text())
        except json.JSONDecodeError:
            continue
        rows = data if isinstance(data, list) else data.get("items", None) if isinstance(data, dict) else None
        if rows is None and isinstance(data, dict):
            rows = [dict(v, id=k) for k, v in data.items() if isinstance(v, dict)]
        for r in rows or []:
            if isinstance(r, dict) and r.get("id"):
                ids.add(r["id"])
    return ids or None


def _texts(obj):
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for k, v in obj.items():
            if not k.startswith("_"):
                yield from _texts(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _texts(v)


def _forbidden(ctx, where, obj):
    words = [w.lower() for w in ctx["forbidden"]]
    for text in _texts(obj):
        for token in re.findall(r"[a-z]+", text.lower()):
            if token in words:
                ctx["err"](where, f"forbidden concept '{token}' in \"{text[:60]}\"")


def _item(ctx, where, item_id, items):
    if not isinstance(item_id, str) or not ID_RE.match(item_id):
        ctx["err"](where, f"item id '{item_id}' is not snake_case")
    elif items is not None and item_id not in items:
        ctx["warn"](where, f"item '{item_id}' is not in resources/items")


def _teachers(ctx):
    """Skills a teacher exists for (spec §2: Bjorn smithing, Ysolde herbcraft, Aldric blades/defence, ...)"""
    return {"smithing", "herbcraft", "blades", "defence", "stealth", "lore", "woodcraft", "mining"}


def validate(ctx):
    err, warn = ctx["err"], ctx["warn"]
    npcs, locations, flags = set(ctx["npc_keys"]), ctx["locations"], ctx["flags_known"]
    items = _item_ids(ctx)

    sdata = _load(ctx, "resources/crafting/stations.json")
    rdata = _load(ctx, "resources/crafting/recipes.json")
    ndata = _load(ctx, "resources/crafting/nodes.json")
    if sdata is None or rdata is None or ndata is None:
        return

    where = "resources/crafting/stations.json"
    kinds = sdata.get("kinds", {})
    for k, v in kinds.items():
        if v.get("buildable"):
            if not v.get("build"):
                err(where, f"buildable kind '{k}' has no build cost")
            for i, n in v.get("build", {}).items():
                _item(ctx, f"{where} kind {k}", i, items)
                if not isinstance(n, int) or n < 1:
                    err(where, f"kind '{k}' build {i} needs a positive count")
    seen = set()
    for s in sdata.get("stations", []):
        sid = s.get("id", "")
        w = f"{where} {sid or '?'}"
        if not ID_RE.match(sid or ""):
            err(w, "station id must be snake_case")
        if sid in seen:
            err(w, "duplicate station id")
        seen.add(sid)
        if s.get("kind") not in kinds:
            err(w, f"unknown kind '{s.get('kind')}'")
        if s.get("location") not in locations:
            err(w, f"unknown location '{s.get('location')}'")
        owner = s.get("owner", "")
        if owner and owner not in npcs:
            err(w, f"owner '{owner}' is not an npc key")
        if owner and owner not in ctx["souls"]:
            warn(w, f"owner '{owner}' has no soul to decide leave")
        g = s.get("grade")
        if not isinstance(g, (int, float)) or not 0 <= g <= 100:
            err(w, "grade must be 0-100")
        if s.get("fuel"):
            _item(ctx, w, s["fuel"], items)
        _forbidden(ctx, w, s)
    if not any(s.get("owner") == "bjorn" and s.get("kind") == "forge" for s in sdata.get("stations", [])):
        err(where, "Bjorn's forge must be a forge owned by bjorn (spec §4)")

    where = "resources/crafting/recipes.json"
    seen = set()
    for r in rdata.get("recipes", []):
        rid = r.get("id", "")
        w = f"{where} {rid or '?'}"
        if not ID_RE.match(rid or ""):
            err(w, "recipe id must be snake_case")
        if rid in seen:
            err(w, "duplicate recipe id")
        seen.add(rid)
        if r.get("station") not in kinds:
            err(w, f"unknown station kind '{r.get('station')}'")
        inputs = r.get("inputs", {})
        if not inputs:
            err(w, "needs inputs")
        for i, n in inputs.items():
            _item(ctx, w, i, items)
            if not isinstance(n, int) or n < 1:
                err(w, f"input {i} needs a positive count")
        skill = r.get("skill", "")
        if skill and skill not in SKILLS:
            err(w, f"unknown skill '{skill}'")
        lvl = r.get("min_level", 0)
        if not isinstance(lvl, (int, float)) or not 0 <= lvl <= 100:
            err(w, "min_level must be 0-100")
        if not isinstance(r.get("minutes"), int) or r["minutes"] <= 0:
            err(w, "minutes must be a positive whole number of game minutes")
        out = r.get("output", {})
        _item(ctx, w, out.get("id"), items)
        if not isinstance(out.get("qty", 1), int) or out.get("qty", 1) < 1:
            err(w, "output qty must be positive")
        if "durability" in out and (not isinstance(out["durability"], (int, float)) or out["durability"] <= 0):
            err(w, "output durability must be positive")
        q = r.get("quality", {})
        if set(q) - {"skill", "station", "material"} or abs(sum(q.values()) - 1.0) > 0.001:
            err(w, "quality weights are skill/station/material and sum to 1")
        learn = r.get("learn", "discover")
        if learn not in LEARN:
            err(w, f"learn must be one of {sorted(LEARN)}")
        if learn == "found" and r.get("found_flag") not in flags:
            err(w, f"found_flag '{r.get('found_flag')}' is not a known flag")
        if learn == "taught" and skill not in _teachers(ctx):
            err(w, f"taught recipe but nobody teaches '{skill}'")
        rep = r.get("repair")
        if rep is not None:
            if rep.get("station") not in kinds:
                err(w, f"repair at unknown kind '{rep.get('station')}'")
            for part in ("inputs", "reforge"):
                for i, n in rep.get(part, {}).items():
                    _item(ctx, w, i, items)
                    if not isinstance(n, int) or n < 1:
                        err(w, f"repair {part} {i} needs a positive count")
        _forbidden(ctx, w, r)
    outputs = {r.get("output", {}).get("id") for r in rdata.get("recipes", [])}
    if "steel_bar" not in outputs:
        err(where, "nothing smelts steel (Greystone ore becomes Bjorn's steel)")

    where = "resources/crafting/nodes.json"
    seen = set()
    for n in ndata.get("nodes", []):
        nid = n.get("id", "")
        w = f"{where} {nid or '?'}"
        if not ID_RE.match(nid or ""):
            err(w, "node id must be snake_case")
        if nid in seen:
            err(w, "duplicate node id")
        seen.add(nid)
        if n.get("kind") not in NODE_KINDS:
            err(w, f"unknown kind '{n.get('kind')}'")
        if n.get("location") not in locations:
            err(w, f"unknown location '{n.get('location')}'")
        _item(ctx, w, n.get("item"), items)
        if n.get("skill", "") not in GATHER_SKILLS:
            err(w, f"gathering skill must be one of {sorted(GATHER_SKILLS - {''})} or none")
        if n.get("tool"):
            _item(ctx, w, n["tool"], items)
        for key in ("charges", "regrow_minutes", "base_yield"):
            if not isinstance(n.get(key), int) or n[key] < 1:
                err(w, f"{key} must be a positive whole number")
        g = n.get("grade")
        if not isinstance(g, (int, float)) or not 0 <= g <= 100:
            err(w, "grade must be 0-100")
        owner = n.get("owner", "")
        if owner and owner not in npcs:
            err(w, f"owner '{owner}' is not an npc key")
        if n.get("stores") and not owner:
            err(w, "stores belong to someone")
        for f in n.get("requires_any_flag", []):
            if f not in flags:
                err(w, f"gate flag '{f}' is not a known flag")
        if "season" in n:
            season = n["season"]
            listed = season if isinstance(season, list) else [season]
            if not listed or any(x not in SEASONS for x in listed):
                err(w, f"season must be one of {sorted(SEASONS)} or a list of them")
        _forbidden(ctx, w, n)
    nodes = ndata.get("nodes", [])
    if not any(n.get("item") == "iron_ore" and n.get("location") == "greystone_mines" for n in nodes):
        err(where, "Greystone must yield iron ore (canon)")
    salt = [n for n in nodes if n.get("item") == "white_salt"]
    if not salt or any(not n.get("requires_any_flag") for n in salt):
        err(where, "the deep-vein white salt must exist and be story-gated (requires_any_flag)")
    if not any(n.get("item") == "fever_root" and n.get("location") == "forest_path" for n in nodes):
        err(where, "fever-root grows in the Darkwood (forest_path)")
    # The Grey Fever cure is made on the story's clock, which runs in the opening season: its root
    # and salt must be there to take then, whatever season the other herbs keep
    story_season = ctx["world"].get("calendar", {}).get("seasons", {}).get("first", "autumn")
    ingredients = {}
    ipath = ctx["root"] / "resources/crafting/ingredients.json"
    if ipath.exists():
        try:
            ingredients = {i.get("id"): i for i in json.loads(ipath.read_text()).get("ingredients", [])}
        except ValueError:
            pass
    for item in ("fever_root", "white_salt"):
        grows = []
        for n in nodes:
            if n.get("item") != item:
                continue
            season = n.get("season", ingredients.get(item, {}).get("season", "any") if n.get("kind") == "herb" else "any")
            listed = season if isinstance(season, list) else [season]
            grows.append("any" in listed or story_season in listed)
        if grows and not any(grows):
            err(where, f"the Grey Fever cure needs {item} in {story_season}, the story's season, and no node gives it then")
