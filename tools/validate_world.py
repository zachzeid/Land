#!/usr/bin/env python3
"""Validate souls/*/SOUL.md and resources/storylines/*.json against docs/WORLD_SCHEMA.md.

Usage:
  python3 tools/validate_world.py                 # everything
  python3 tools/validate_world.py --storyline iron_hand
  python3 tools/validate_world.py --souls-only
  python3 tools/validate_world.py --strict-crossovers   # crossover flags must exist in another storyline

Exit 0 = clean, 1 = errors. Warnings never fail the run.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORLD = json.loads((ROOT / "resources/world/world.json").read_text())
NPC_KEYS = [n["key"] for n in WORLD["npcs"]]
LOCATIONS = {loc["id"] for loc in WORLD["locations"]}
HOOK_TYPES = {"intercept", "react", "scheme", "reveal", "aid", "betray"}
SOUL_AGENCY_TYPES = HOOK_TYPES | {"converse"}  # converse: actions taken in free-form dialogue
DIMENSIONS = {"trust", "respect", "affection", "fear", "familiarity"}
EFFECT_PARAMS = {
    "set_flag": {"flag", "value"},
    "adjust_relationship": {"npc", "dimension", "delta"},
    "spread_rumor": {"flag", "to"},
    "agenda": {"npc", "text"},
    "move_npc": {"npc", "location"},
    "block_beat": {"storyline", "beat"},
    "unlock_beat": {"storyline", "beat"},
    "shift_want": {"npc", "want", "delta"},
}
OPTIONAL_PARAMS = {"spread_rumor": {"via"}}
# Endings deliberately reachable through the player's absence (neglect has consequences)
NEGLECT_ENDINGS = {"the_locked_room", "tn_the_cart_rolled"}
ALL_PLAYER_FLAGS = set()

SOUL_SECTIONS = ["Essence", "Wants", "Fears", "Lines I Will Not Cross", "Agency", "Drift", "Voice", "Secrets"]

errors, warnings = [], []


def err(where, msg):
    errors.append(f"ERROR {where}: {msg}")


def warn(where, msg):
    warnings.append(f"warn  {where}: {msg}")


def base_flags():
    text = (ROOT / "scripts/world_state/story_flags.gd").read_text()
    return set(WORLD.get("discovery_flags", {})) | set(WORLD.get("calendar", {}).get("flags", {})) | set(re.findall(r'^const [A-Z_]+ = "([a-z_]+)"', text, re.M))


# =============================================================================
# SOULS
# =============================================================================

WANT_RE = re.compile(r"^- `([a-z][a-z0-9_]*)` \((\d+)\):\s*\S")
LINE_RE = re.compile(r"^- `([^`]+)`:\s*\S")
AGENCY_RE = re.compile(r"^- ([a-z]+):\s*([a-z_, ]+)$")
DRIFT_RE = re.compile(r"^- on `([!a-z0-9_]+)`: `([a-z][a-z0-9_]*)` ([+-]\d+)$")


def parse_soul(path):
    text = path.read_text()
    soul = {"path": str(path.relative_to(ROOT)), "sections": {}, "wants": {}, "lines": [], "agency": {}, "drift": []}
    m = re.search(r"^npc: *(\S+)", text, re.M)
    soul["npc"] = m.group(1) if m else None
    current = None
    for line in text.splitlines():
        h = re.match(r"^## (.+?)\s*$", line)
        if h:
            current = h.group(1)
            soul["sections"][current] = []
            continue
        if current:
            soul["sections"][current].append(line)
    return soul


def validate_soul(path, flags_known):
    soul = parse_soul(path)
    where = soul["path"]
    key = path.parent.name
    if key not in NPC_KEYS:
        err(where, f"directory '{key}' is not an NPC key")
    if soul["npc"] != key:
        err(where, f"'npc: {soul['npc']}' does not match directory '{key}'")
    for s in SOUL_SECTIONS:
        if s not in soul["sections"]:
            err(where, f"missing section '## {s}'")
    for line in soul["sections"].get("Wants", []):
        if line.startswith("- "):
            m = WANT_RE.match(line)
            if not m:
                err(where, f"Wants line not machine-shaped: {line[:70]}")
                continue
            w = int(m.group(2))
            if not 1 <= w <= 10:
                err(where, f"want '{m.group(1)}' weight {w} outside 1-10")
            soul["wants"][m.group(1)] = w
    if len(soul["wants"]) < 3:
        err(where, "needs at least 3 wants")
    for line in soul["sections"].get("Lines I Will Not Cross", []):
        if line.startswith("- "):
            m = LINE_RE.match(line)
            if not m:
                err(where, f"Lines rule not machine-shaped: {line[:70]}")
                continue
            rule = m.group(1)
            parts = rule.split(":")
            kind = parts[0]
            ok = (
                (kind in ("harm", "ally") and len(parts) == 2 and parts[1] in NPC_KEYS)
                or (kind == "hook" and len(parts) == 2 and parts[1] in SOUL_AGENCY_TYPES)
                or (kind == "effect" and len(parts) in (2, 3) and parts[1] in EFFECT_PARAMS)
            )
            if not ok:
                err(where, f"unknown rule form `{rule}`")
            soul["lines"].append(rule)
    for line in soul["sections"].get("Agency", []):
        if line.startswith("- "):
            m = AGENCY_RE.match(line.strip())
            if not m:
                err(where, f"Agency line not machine-shaped: {line[:70]}")
                continue
            ht = m.group(1)
            effs = [e.strip() for e in m.group(2).split(",") if e.strip()]
            if ht not in SOUL_AGENCY_TYPES:
                err(where, f"Agency hook type '{ht}' unknown")
            for e in effs:
                if e not in EFFECT_PARAMS:
                    err(where, f"Agency effect '{e}' unknown")
            soul["agency"][ht] = set(effs)
    if not soul["agency"]:
        err(where, "Agency grants nothing; this NPC could never act")
    for line in soul["sections"].get("Drift", []):
        if line.startswith("- "):
            m = DRIFT_RE.match(line.strip())
            if not m:
                err(where, f"Drift line not machine-shaped: {line[:70]}")
                continue
            if m.group(2) not in soul["wants"]:
                err(where, f"Drift references unknown want '{m.group(2)}'")
            soul["drift"].append((m.group(1).lstrip("!"), m.group(2)))
    if "Life" in soul["sections"] or REQUIRE_LIFE:
        validate_life(where, soul, key, 2, 3)
    return key, soul


PERSONAL_EFFECTS = {"agenda", "move_npc", "adjust_relationship", "shift_want", "spread_rumor"}
ARC_RE = re.compile(r"^### Arc: `([a-z][a-z0-9_]*)` \(serves `([a-z][a-z0-9_]*)`\)\s*$")
STEP_RE = re.compile(r"^- `([a-z][a-z0-9_]*)`: (.+?) \| after: ([a-z0-9_]+) \| needs: ([!a-z0-9_, ]+) \| at: ([a-z0-9_]+) \| takes: (\d+) \| effects: ([a-z_, ]+?)(?: \| player: (helps|needed))?\s*$")
RESULT_RE = re.compile(r"^- result: `([a-z0-9_{}]+)`: \S.{15,}$")
FAILS_RE = re.compile(r"^- fails_if: (`[!a-z0-9_]+`(?:, `[!a-z0-9_]+`)*)\s*$")
RANGE_WANT_RE = re.compile(r"^- `([a-z][a-z0-9_]*)` \((\d+)-(\d+)\):\s*\S")
PERSONAL_FLAGS = {}  # flag -> description, gathered from every Life section
REQUIRE_LIFE = False  # --require-life: every main soul must have a ## Life section


def validate_life(where, soul, key_prefix, min_arcs, max_arcs):
    """Validate a ## Life section. key_prefix is the NPC key, or '{id}' for archetypes."""
    lines = soul["sections"].get("Life")
    if lines is None:
        err(where, "missing section '## Life'")
        return
    arcs, cur = [], None
    for raw in lines:
        line = raw.rstrip()
        if line.startswith("### "):
            m = ARC_RE.match(line)
            if not m:
                err(where, f"Arc header not machine-shaped: {line[:70]}")
                cur = None
                continue
            if m.group(2) not in soul["wants"]:
                err(where, f"arc '{m.group(1)}' serves unknown want '{m.group(2)}'")
            cur = {"id": m.group(1), "steps": [], "result": None}
            arcs.append(cur)
        elif line.startswith("- ") and cur is not None:
            if line.startswith("- result:"):
                m = RESULT_RE.match(line)
                if not m:
                    err(where, f"arc '{cur['id']}' result not machine-shaped: {line[:70]}")
                    continue
                if not m.group(1).startswith(key_prefix + "_"):
                    err(where, f"result flag '{m.group(1)}' must start with '{key_prefix}_'")
                cur["result"] = m.group(1)
                PERSONAL_FLAGS[m.group(1)] = line.split(":", 2)[-1].strip()
            elif line.startswith("- fails_if:"):
                if not FAILS_RE.match(line):
                    err(where, f"fails_if not machine-shaped: {line[:70]}")
            else:
                m = STEP_RE.match(line)
                if not m:
                    err(where, f"step not machine-shaped: {line[:90]}")
                    continue
                sid, _text, after, _needs, at, takes, effs, _player = m.groups()
                if after != "none" and after not in cur["steps"]:
                    err(where, f"step '{sid}' after '{after}' is not an earlier step of arc '{cur['id']}'")
                if at != "any" and at not in LOCATIONS:
                    err(where, f"step '{sid}' at unknown location '{at}'")
                if not 1 <= int(takes) <= 6:
                    err(where, f"step '{sid}' takes {takes} outside 1-6")
                for e in [x.strip() for x in effs.split(",") if x.strip()]:
                    if e not in PERSONAL_EFFECTS:
                        err(where, f"step '{sid}' effect '{e}' is not personal-scope")
                cur["steps"].append(sid)
                PERSONAL_FLAGS[f"{key_prefix}_{cur['id']}_{sid}"] = f"step {sid} of arc {cur['id']}"
    if not min_arcs <= len(arcs) <= max_arcs:
        err(where, f"needs {min_arcs}-{max_arcs} arcs, has {len(arcs)}")
    for a in arcs:
        if not a["steps"]:
            err(where, f"arc '{a['id']}' has no steps")
        if not a["result"]:
            err(where, f"arc '{a['id']}' has no result line")


def validate_archetype(path):
    text = path.read_text()
    where = str(path.relative_to(ROOT))
    soul = parse_soul(path)
    m = re.search(r"^archetype: *(\S+)", text, re.M)
    if not m or m.group(1) != path.stem:
        err(where, f"'archetype:' must equal filename '{path.stem}'")
    m = re.search(r"^regions: *(.+)$", text, re.M)
    region_ids = {r["id"] for r in WORLD["regions"]}
    if not m or any(r.strip() not in region_ids for r in m.group(1).split(",")):
        err(where, "regions: must list world.json region ids")
    for sname in ("Essence", "Wants", "Lines I Will Not Cross", "Agency", "Voice", "Life"):
        if sname not in soul["sections"]:
            err(where, f"missing section '## {sname}'")
    for line in soul["sections"].get("Wants", []):
        if line.startswith("- "):
            m = RANGE_WANT_RE.match(line)
            if not m:
                err(where, f"Wants line must be `id` (lo-hi): {line[:70]}")
                continue
            lo, hi = int(m.group(2)), int(m.group(3))
            if not 1 <= lo <= hi <= 10:
                err(where, f"want '{m.group(1)}' range {lo}-{hi} invalid")
            soul["wants"][m.group(1)] = hi
    if len(soul["wants"]) < 3:
        err(where, "needs at least 3 wants")
    for line in soul["sections"].get("Agency", []):
        if line.startswith("- "):
            m = AGENCY_RE.match(line.strip())
            if not m or m.group(1) != "converse":
                err(where, f"archetype Agency may only have a converse: line: {line[:60]}")
                continue
            for e in [x.strip() for x in m.group(2).split(",") if x.strip()]:
                if e not in PERSONAL_EFFECTS:
                    err(where, f"archetype converse effect '{e}' is not personal-scope")
    validate_life(where, soul, "{id}", 1, 2)


def validate_population():
    p = ROOT / "resources/generics/population.json"
    if not p.exists():
        return
    where = str(p.relative_to(ROOT))
    archetypes = {a.stem for a in (ROOT / "resources/generics/archetypes").glob("*.md")}
    data = json.loads(p.read_text())
    for loc, entries in data.get("locations", {}).items():
        if loc not in LOCATIONS:
            err(where, f"unknown location '{loc}'")
        for e in entries:
            if e.get("archetype") not in archetypes:
                err(where, f"{loc}: unknown archetype '{e.get('archetype')}'")
            if not isinstance(e.get("count"), int) or not 1 <= e["count"] <= 6:
                err(where, f"{loc}: count must be 1-6")
    names = ROOT / "resources/generics/names.json"
    if names.exists():
        nd = json.loads(names.read_text())
        for r in WORLD["regions"]:
            if len(nd.get(r["id"], [])) < 20:
                err(str(names.relative_to(ROOT)), f"region '{r['id']}' needs at least 20 names")


# =============================================================================
# STORYLINES
# =============================================================================

def check_flag_ref(where, flag, allowed, crossovers):
    name = flag.lstrip("!")
    if name in allowed:
        return
    if name in crossovers:
        return
    err(where, f"flag '{name}' is not a base flag, not declared here, and not listed in crossovers")


def validate_effect(where, eff, sl, allowed_flags, crossovers, beat_ids, souls):
    t = eff.get("type")
    if t not in EFFECT_PARAMS:
        err(where, f"unknown effect type '{t}'")
        return
    keys = set(eff) - {"type"}
    missing = EFFECT_PARAMS[t] - keys
    extra = keys - EFFECT_PARAMS[t] - OPTIONAL_PARAMS.get(t, set())
    if missing:
        err(where, f"{t} missing {sorted(missing)}")
    if extra:
        err(where, f"{t} has unknown params {sorted(extra)}")
    if "flag" in eff:
        check_flag_ref(where, eff["flag"], allowed_flags, crossovers)
    if "npc" in eff and eff["npc"] not in NPC_KEYS:
        err(where, f"{t} npc '{eff['npc']}' unknown")
    if t == "set_flag" and eff.get("flag") in WORLD.get("calendar", {}).get("flags", {}):
        err(where, f"set_flag cannot set calendar flag '{eff.get('flag')}' (world fixed point)")
    if t == "set_flag" and not isinstance(eff.get("value"), bool):
        err(where, "set_flag value must be true/false")
    if t == "adjust_relationship":
        if eff.get("dimension") not in DIMENSIONS:
            err(where, f"dimension '{eff.get('dimension')}' unknown")
        if not isinstance(eff.get("delta"), int) or not -20 <= eff["delta"] <= 20:
            err(where, "adjust_relationship delta must be an int in -20..20")
    if t == "spread_rumor":
        to = eff.get("to", [])
        if not isinstance(to, list) or not to or any(k != "*" and k not in NPC_KEYS for k in to):
            err(where, f"spread_rumor 'to' must be NPC keys or ['*'], got {to}")
    if t == "agenda" and len(str(eff.get("text", ""))) > 160:
        err(where, "agenda text over 160 chars")
    if t == "move_npc" and eff.get("location") not in LOCATIONS:
        err(where, f"location '{eff.get('location')}' unknown")
    if t in ("block_beat", "unlock_beat"):
        if eff.get("storyline") == sl and eff.get("beat") not in beat_ids:
            err(where, f"{t} beat '{eff.get('beat')}' not in this storyline")
        elif eff.get("storyline") != sl:
            warn(where, f"{t} targets another storyline '{eff.get('storyline')}' (checked only by runtime)")
    if t == "shift_want":
        if not isinstance(eff.get("delta"), int) or not -3 <= eff["delta"] <= 3:
            err(where, "shift_want delta must be an int in -3..3")
        soul = souls.get(eff.get("npc"))
        if soul and eff.get("want") not in soul["wants"]:
            err(where, f"shift_want: '{eff.get('want')}' is not a want of {eff.get('npc')}")


def soul_permits(soul, hook_type, effects):
    """Return the subset of effects the soul could apply at this hook type."""
    granted = soul["agency"].get(hook_type, set())
    if f"hook:{hook_type}" in soul["lines"]:
        return []
    ok = []
    for e in effects:
        t = e.get("type")
        if t not in granted or f"effect:{t}" in soul["lines"]:
            continue
        if "flag" in e and f"effect:{t}:{e['flag']}" in soul["lines"]:
            continue
        ok.append(e)
    return ok


def option_refused(soul, option):
    """aids/harms tags against ally:/harm: Lines."""
    aid = option.get("aids")
    if aid and f"ally:{aid}" in soul["lines"]:
        return True
    return any(f"harm:{h}" in soul["lines"] for h in option.get("harms", []))


def validate_storyline(path, flags_base, souls, all_declared, strict_crossovers):
    where0 = str(path.relative_to(ROOT))
    try:
        sl = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        err(where0, f"invalid JSON: {e}")
        return None
    sid = sl.get("id")
    if sid != path.stem:
        err(where0, f"id '{sid}' must equal filename '{path.stem}'")
    for f in ("title", "summary", "prefix", "flags", "beats", "endings"):
        if f not in sl:
            err(where0, f"missing '{f}'")
    prefix = sl.get("prefix", "")
    declared = sl.get("flags", {})
    for name, desc in declared.items():
        if not name.startswith(prefix):
            err(where0, f"flag '{name}' does not start with prefix '{prefix}'")
        if name in flags_base:
            err(where0, f"flag '{name}' redeclares a base flag")
        if not desc or len(desc) < 20:
            err(where0, f"flag '{name}' needs a real canonical description")
        if re.search(r"\b(quest|option|beat|storyline|player chose)\b", desc, re.I):
            warn(where0, f"flag '{name}' description has meta language: {desc[:60]}")
    crossovers = set(sl.get("crossovers", []))
    for pf in sl.get("player_flags", []):
        if pf not in declared:
            err(where0, f"player_flags entry '{pf}' is not declared in flags")
    allowed = flags_base | set(declared)
    beats = sl.get("beats", [])
    beat_ids = [b.get("id") for b in beats]
    if len(set(beat_ids)) != len(beat_ids):
        err(where0, "duplicate beat ids")
    if len(beats) < 4:
        warn(where0, f"only {len(beats)} beats; aim for 5-8")
    hook_ids, hook_count, npcs_with_hooks = set(), 0, set()
    settable = set()
    for b in beats:
        for e in b.get("on_resolve", []):
            if e.get("type") == "set_flag" and e.get("value") is True:
                settable.add(e.get("flag"))
        for h in b.get("hooks", []):
            for o in h.get("options", []):
                for e in o.get("effects", []):
                    if e.get("type") == "set_flag" and e.get("value") is True:
                        settable.add(e.get("flag"))
    for b in beats:
        bw = f"{where0}:{b.get('id')}"
        for f in ("id", "title", "summary", "location", "requires", "resolves_on", "hooks"):
            if f not in b:
                err(bw, f"missing '{f}'")
        if "act" in b and b["act"] not in (1, 2, 3):
            err(bw, f"act must be 1, 2 or 3, got {b['act']}")
        if b.get("location") not in LOCATIONS:
            err(bw, f"location '{b.get('location')}' unknown")
        for f in b.get("requires", []):
            check_flag_ref(bw, f, allowed, crossovers)
        if not b.get("resolves_on"):
            err(bw, "resolves_on is empty; beat can never resolve")
        for f in b.get("resolves_on", []):
            check_flag_ref(bw, f, allowed, crossovers)
        for e in b.get("on_resolve", []):
            validate_effect(bw + ":on_resolve", e, sid, allowed, crossovers, beat_ids, souls)
        if not b.get("hooks"):
            warn(bw, "beat has no hooks; NPCs cannot act here")
        for h in b.get("hooks", []):
            hook_count += 1
            hw = f"{bw}:{h.get('id')}"
            if h.get("id") in hook_ids:
                err(hw, "duplicate hook id")
            hook_ids.add(h.get("id"))
            ht = h.get("type")
            if ht not in HOOK_TYPES:
                err(hw, f"hook type '{ht}' unknown")
            trig = h.get("trigger", "")
            if trig.startswith("on_flag:"):
                check_flag_ref(hw, trig.split(":", 1)[1], allowed, crossovers)
            elif trig not in ("on_open", "on_resolve", "idle"):
                err(hw, f"trigger '{trig}' unknown")
            elig = h.get("eligible", [])
            if not elig or any(k not in NPC_KEYS for k in elig):
                err(hw, f"eligible must be NPC keys, got {elig}")
            npcs_with_hooks.update(elig)
            if not h.get("situation"):
                err(hw, "missing situation")
            opts = h.get("options", [])
            if not 2 <= len(opts) <= 4:
                err(hw, f"needs 2-4 options, has {len(opts)}")
            for o in opts:
                ow = f"{hw}:{o.get('id')}"
                for f in ("id", "label", "serves", "effects"):
                    if f not in o:
                        err(ow, f"missing '{f}'")
                if o.get("aids") is not None and o["aids"] not in NPC_KEYS + ["player"]:
                    err(ow, f"aids '{o['aids']}' unknown")
                harms = o.get("harms", [])
                if not isinstance(harms, list) or any(k not in NPC_KEYS + ["player"] for k in harms):
                    err(ow, f"harms must be a list of NPC keys, got {harms}")
                for e in o.get("effects", []):
                    validate_effect(ow, e, sid, allowed, crossovers, beat_ids, souls)
            for f in h.get("freeform_effects", []):
                if f not in EFFECT_PARAMS:
                    err(hw, f"freeform effect '{f}' unknown")
            # Soul cross-checks (only for souls that exist)
            actors = 0
            for k in elig:
                soul = souls.get(k)
                if not soul:
                    continue
                for o in opts:
                    for w in o.get("serves", []):
                        if w not in soul["wants"] and not any(w in s2["wants"] for s2 in souls.values()):
                            warn(f"{hw}:{o.get('id')}", f"serves '{w}', which is not a want of any eligible soul")
                if any(soul_permits(soul, ht, o.get("effects", [])) or not o.get("effects") for o in opts) and ht in soul["agency"]:
                    actors += 1
            # Every option with effects must be fully applicable by at least one eligible soul;
            # otherwise its effects are silently dropped at runtime
            for o in opts:
                effs = o.get("effects", [])
                if not effs:
                    continue
                granted, willing = [], []
                for k in elig:
                    soul = souls.get(k)
                    if soul is None:
                        continue
                    if len(soul_permits(soul, ht, effs)) == len(effs):
                        granted.append(k)
                        if not option_refused(soul, o):
                            willing.append(k)
                if elig and all(k in souls for k in elig):
                    if not granted:
                        err(f"{hw}:{o.get('id')}", f"no eligible soul ({elig}) has Agency for all of this option's effects at a '{ht}' hook")
                    elif not willing:
                        warn(f"{hw}:{o.get('id')}", f"every eligible soul refuses this option by its Lines (harm:/ally:); intended as a road not taken?")
            present = [k for k in elig if k in souls]
            if present and actors == 0:
                err(hw, f"no eligible soul ({present}) has Agency to act at a '{ht}' hook with these effects")
    for e in sl.get("endings", []):
        for f in e.get("requires", []):
            check_flag_ref(f"{where0}:ending:{e.get('id')}", f, allowed, crossovers)
    for f in declared:
        if f not in settable and not any(f in b.get("resolves_on", []) for b in beats):
            warn(where0, f"declared flag '{f}' is never set by any effect nor resolves a beat")
    # Player-centrality: the world may advance Acts I-II on its own, but never finish a story
    player_flags = set(sl.get("player_flags", []))
    all_player_flags = player_flags | ALL_PLAYER_FLAGS
    for b in beats:
        if b.get("act") == 3:
            bw = f"{where0}:{b.get('id')}"
            req_pf = any(r.lstrip("!") in all_player_flags for r in b.get("requires", []) if not r.startswith("!"))
            only_pf = bool(b.get("resolves_on")) and all(f in player_flags for f in b.get("resolves_on", []))
            if not (req_pf or only_pf):
                err(bw, "Act III beat must require a player flag, or resolve only on player flags")
        elif "act" not in b:
            err(f"{where0}:{b.get('id')}", "beat has no 'act' (1-3)")
    for e in sl.get("endings", []):
        if e.get("id") in NEGLECT_ENDINGS:
            continue
        if not any(r in player_flags for r in e.get("requires", []) if not r.startswith("!")):
            err(f"{where0}:ending:{e.get('id')}", "ending must require at least one of this storyline's player_flags")
    if strict_crossovers:
        for c in crossovers:
            if c not in all_declared:
                err(where0, f"crossover '{c}' is not declared by any storyline")
    if hook_count < len(beats):
        warn(where0, f"{hook_count} hooks for {len(beats)} beats; aim for 2+ per beat")
    missing_npcs = set(NPC_KEYS) - npcs_with_hooks
    return {"id": sid, "beats": len(beats), "hooks": hook_count, "npcs": sorted(npcs_with_hooks),
            "flags": len(declared), "missing_npcs": sorted(missing_npcs)}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--storyline")
    ap.add_argument("--souls-only", action="store_true")
    ap.add_argument("--strict-crossovers", action="store_true")
    ap.add_argument("--require-life", action="store_true", help="every main soul must have a ## Life section")
    args = ap.parse_args()

    flags_base = base_flags()
    global REQUIRE_LIFE
    REQUIRE_LIFE = args.require_life
    souls = {}
    for p in sorted((ROOT / "souls").glob("*/SOUL.md")):
        k, s = validate_soul(p, flags_base)
        souls[k] = s
    for p in sorted((ROOT / "resources/generics/archetypes").glob("*.md")):
        validate_archetype(p)
    validate_population()
    # Godot's .tres parser drops the property after a '#' comment line, so comments silently lose data
    for t in sorted((ROOT / "resources").rglob("*.tres")):
        if any(line.startswith("#") for line in t.read_text().splitlines()):
            err(str(t.relative_to(ROOT)), "'#' comment line in .tres: Godot drops the next property")
    # Storylines may read personal flags (never set them)
    flags_base = flags_base | {f for f in PERSONAL_FLAGS if "{" not in f}
    summaries = []
    if not args.souls_only:
        files = sorted((ROOT / "resources/storylines").glob("*.json"))
        all_declared = set()
        prefixes = {}
        for p in files:
            try:
                d = json.loads(p.read_text())
                all_declared |= set(d.get("flags", {}))
                prefixes.setdefault(d.get("prefix"), []).append(p.stem)
            except json.JSONDecodeError:
                pass
        for p in files:
            try:
                ALL_PLAYER_FLAGS.update(json.loads(p.read_text()).get("player_flags", []))
            except json.JSONDecodeError:
                pass
        for pre, owners in prefixes.items():
            if len(owners) > 1:
                err("storylines", f"prefix '{pre}' used by {owners}")
        for p in files:
            if args.storyline and p.stem != args.storyline:
                continue
            s = validate_storyline(p, flags_base, souls, all_declared, args.strict_crossovers)
            if s:
                summaries.append(s)

    for w in warnings:
        print(w)
    for e in errors:
        print(e)
    print(f"\nSouls: {len(souls)} ({', '.join(sorted(souls)) or 'none'})")
    arche = sorted(x.stem for x in (ROOT / "resources/generics/archetypes").glob("*.md"))
    print(f"Archetypes: {len(arche)}; personal flags: {len([f for f in PERSONAL_FLAGS if '{' not in f])}")
    for s in summaries:
        print(f"Storyline {s['id']}: {s['beats']} beats, {s['hooks']} hooks, {s['flags']} flags, NPCs {s['npcs']}")
    print(f"\n{len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
