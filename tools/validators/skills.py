"""Skills, perks, teachers and respawn inns (docs/PLAYER_SYSTEMS.md §2): resources/player/*.json.

Checks: skill ids unique and well-formed with name, raised_by, effects and a feat line per feat
milestone; perks reference real skills and declared milestones, ids unique, every skill has a perk at
every milestone, smithing 50 is the maker's mark; teachers name real NPCs, real archetypes and real
skills, and minors teach no combat skill; inns are real locations; no forbidden concept in any text.
"""
import json
import re

COMBAT_SKILLS = {"blades", "blunt", "bows", "defence"}
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")


def _load(ctx, rel):
    path = ctx["root"] / rel
    if not path.exists():
        ctx["err"](rel, "missing")
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as e:
        ctx["err"](rel, f"invalid JSON: {e}")
        return None


def _forbidden(ctx, where, data):
    text = json.dumps(data).lower()
    for w in ctx["forbidden"]:
        if re.search(r"\b" + re.escape(w.lower()) + r"s?\b", text):
            ctx["err"](where, f"forbidden concept '{w}'")


def validate(ctx):
    err = ctx["err"]
    skills_doc = _load(ctx, "resources/player/skills.json")
    perks_doc = _load(ctx, "resources/player/perks.json")
    teachers_doc = _load(ctx, "resources/player/teachers.json")
    respawn_doc = _load(ctx, "resources/player/respawn.json")
    skill_ids = set()
    milestones = [25, 50, 75, 100]
    if skills_doc is not None:
        milestones = skills_doc.get("milestones", milestones)
        feat_ms = skills_doc.get("feat_milestones", [25, 50, 75])
        if not set(feat_ms) <= set(milestones):
            err("skills.json", "feat_milestones must be a subset of milestones")
        for s in skills_doc.get("skills", []):
            sid = s.get("id", "")
            where = f"skills.json:{sid or '?'}"
            if not ID_RE.match(str(sid)):
                err(where, "bad or missing id")
            if sid in skill_ids:
                err(where, "duplicate skill id")
            skill_ids.add(sid)
            for field in ("name", "raised_by"):
                if not str(s.get(field, "")).strip():
                    err(where, f"missing {field}")
            if not s.get("effects"):
                err(where, "missing effects")
            if not isinstance(s.get("base_xp", 1.0), (int, float)) or s.get("base_xp", 1.0) <= 0:
                err(where, "base_xp must be a positive number")
            for m in feat_ms:
                if not str(s.get("feat", {}).get(str(m), "")).strip():
                    err(where, f"no feat line for {m}")
        if len(skill_ids) != 12:
            err("skills.json", f"expected the 12 skills of spec §2, found {len(skill_ids)}")
        _forbidden(ctx, "skills.json", skills_doc)
    if perks_doc is not None:
        perk_ids = set()
        covered = set()
        for p in perks_doc.get("perks", []):
            pid = p.get("id", "")
            where = f"perks.json:{pid or '?'}"
            if not ID_RE.match(str(pid)):
                err(where, "bad or missing id")
            if pid in perk_ids:
                err(where, "duplicate perk id")
            perk_ids.add(pid)
            if p.get("skill") not in skill_ids:
                err(where, f"unknown skill '{p.get('skill')}'")
            if p.get("milestone") not in milestones:
                err(where, f"milestone {p.get('milestone')} is not one of {milestones}")
            if not str(p.get("name", "")).strip() or not str(p.get("description", "")).strip():
                err(where, "missing name or description")
            covered.add((p.get("skill"), p.get("milestone")))
        for sid in skill_ids:
            for m in milestones:
                if (sid, m) not in covered:
                    ctx["warn"]("perks.json", f"no perk for {sid} {m}")
        if not any(p.get("skill") == "smithing" and p.get("milestone") == 50 and "mark" in p.get("name", "").lower()
                   for p in perks_doc.get("perks", [])):
            err("perks.json", "smithing 50 must be the maker's mark (spec §2)")
        _forbidden(ctx, "perks.json", perks_doc)
    if teachers_doc is not None:
        npc_keys = set(ctx["npc_keys"])
        minors = {n.get("key") for n in ctx["world"].get("npcs", []) if n.get("minor")}
        archetypes = {a.stem for a in (ctx["root"] / "resources/generics/archetypes").glob("*.md")}
        for group, known in (("named", npc_keys), ("archetypes", archetypes)):
            for key, row in teachers_doc.get(group, {}).items():
                where = f"teachers.json:{group}.{key}"
                if key not in known:
                    err(where, f"unknown {'NPC' if group == 'named' else 'archetype'}")
                taught = row.get("skills", [])
                if not taught:
                    err(where, "teaches nothing")
                for sk in taught:
                    if sk not in skill_ids:
                        err(where, f"unknown skill '{sk}'")
                if key in minors and set(taught) & COMBAT_SKILLS:
                    err(where, "a minor never teaches a combat skill")
                up_to = row.get("up_to", 50)
                if not isinstance(up_to, (int, float)) or not 0 < up_to <= 100:
                    err(where, "up_to must be 1-100")
        _forbidden(ctx, "teachers.json", teachers_doc)
    if respawn_doc is not None:
        inns = respawn_doc.get("inns", [])
        if not inns:
            err("respawn.json", "no inns to wake at")
        for inn in inns:
            if inn.get("location") not in ctx["locations"]:
                err("respawn.json", f"unknown location '{inn.get('location')}'")
