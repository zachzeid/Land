# World Schema: Souls, Storylines, Hooks

> **Document Purpose:** The contract between authored story content and the agentic NPC runtime.
> Every storyline file and every `SOUL.md` must follow it. `python3 tools/validate_world.py` enforces it.

## The idea in one paragraph

Storylines are authored as **beats** (story states) gated by **flags**. Each beat exposes **hooks**:
named moments where an NPC agent may step in and change what happens next. Which NPCs may act at a
hook, and what they are allowed to change, is decided by two things together: the hook's authored
options and the NPC's `SOUL.md` (its wants, its lines it will not cross, and its **Agency** grants).
The runtime (`StorylineDirector`) offers the hook to each eligible NPC, the NPC's agent chooses an
option (Claude when available, a deterministic soul-weighted choice otherwise), and the chosen
option's **effects** are applied, but only effects from the fixed vocabulary below, and only those
that both the hook and the soul permit. NPCs therefore change the world, and the world cannot be
changed in ways no author anticipated.

---

## 1. NPC keys, locations

**NPC keys** (the short name found inside every `npc_id`):

| key | npc_id | home |
|-----|--------|------|
| gregor | gregor_merchant_001 | thornhaven_gregor_shop |
| elena | elena_daughter_001 | thornhaven_gregor_shop |
| mira | mira_tavern_keeper_001 | thornhaven_tavern |
| bjorn | bjorn_blacksmith_001 | thornhaven_blacksmith |
| aldric | aldric_peacekeeper_001 | thornhaven_town_square |
| mathias | elder_mathias_001 | thornhaven_town_square |
| varn | varn_bandit_001 | iron_hollow_camp |

**Locations.** Built: `thornhaven_town_square`, `thornhaven_gregor_shop`, `thornhaven_tavern`,
`thornhaven_blacksmith`, `iron_hollow_camp`. Planned (may be referenced; scenes come later):
`old_mill`, `forest_path`, `council_hall`, `village_gate`, `healer_hut`, `thornhaven_chapel`.

---

## 2. SOUL.md

Path: `souls/<npc_key>/SOUL.md`. One per NPC. Prose is welcome everywhere, but the lines below
marked **machine** must use the exact shape shown, because the game parses them.

```markdown
# SOUL: Gregor Stoneheart
npc: gregor
npc_id: gregor_merchant_001

## Essence
Prose. Who this person is beneath the dialogue. 1-3 paragraphs.

## Wants
- `protect_elena` (10): Keep Elena safe, whatever it costs.        <- machine: `id` (weight 1-10): text
- `escape_the_deal` (6): Get free of the Iron Hand without dying.

## Fears
- Elena learning what he did.                                      <- prose bullets

## Lines I Will Not Cross
- `harm:elena`: He will never let Elena be hurt.                   <- machine: `rule`: reason
- `effect:spread_rumor:gregor_exposed`: He will not spread his own exposure.

## Agency
- intercept: set_flag, agenda, spread_rumor                        <- machine: hook_type: effect, effect
- scheme: agenda, move_npc
- betray: set_flag, adjust_relationship

## Drift
- on `ledger_found`: `escape_the_deal` +2                         <- machine: on `flag`: `want_id` +N / -N
- on `elena_knows_about_father`: `protect_elena` -1

## Voice
Prose notes on how this soul speaks when acting on its own.

## Secrets
Prose. What only this soul knows. Never shown to the player directly.
```

**Lines I Will Not Cross rule forms** (machine): `harm:<npc_key>`, `effect:<effect_type>` (never
uses that effect at all), `effect:<effect_type>:<flag>` (never applies that effect to that flag),
`hook:<hook_type>` (never acts at that hook type), `ally:<npc_key>` (never helps that NPC: refuses any
option tagged `aids: <npc_key>`). `harm:<npc_key>` refuses any option whose `harms` list names that NPC.

**Agency** grants which hook types the soul engages with and the effect types it may cause there.
A soul with no Agency line for a hook type always passes at that hook type.

**Drift** changes want weights at runtime when flags become true (clamped 1-10). This is how a soul
grows across a playthrough. The file itself is never rewritten.

---

## 3. Storyline files

Path: `resources/storylines/<storyline_id>.json`. One storyline per file.

```json
{
  "id": "iron_hand",
  "title": "The Iron Hand",
  "summary": "Who in Thornhaven is feeding the bandits?",
  "prefix": "ih_",
  "act_span": [1, 3],
  "flags": {
    "ih_mill_meeting_seen": "The player saw Gregor meet a bandit at the old mill at night"
  },
  "crossovers": ["succ_varn_ascendant", "succ_varn_dead"],
  "beats": [
    {
      "id": "night_meeting",
      "title": "A Meeting at the Mill",
      "summary": "Gregor slips out after dark to meet Varn's runner at the old mill.",
      "location": "old_mill",
      "requires": ["ledger_found", "!gregor_exposed"],
      "resolves_on": ["ih_mill_meeting_seen"],
      "on_resolve": [ {"type": "set_flag", "flag": "gregor_bandit_meeting_known", "value": true} ],
      "hooks": [
        {
          "id": "mira_warns_varn",
          "type": "intercept",
          "trigger": "on_open",
          "eligible": ["mira"],
          "situation": "You know the stranger has the ledger. Varn's runner meets Gregor tonight.",
          "options": [
            {
              "id": "warn",
              "label": "Send word to Varn to skip the meeting",
              "serves": ["keep_the_hand_hidden"],
              "effects": [
                {"type": "block_beat", "storyline": "iron_hand", "beat": "night_meeting"},
                {"type": "agenda", "npc": "mira", "text": "Steer the stranger away from the old mill tonight."}
              ]
            },
            {
              "id": "let_it_happen",
              "label": "Let Gregor take the risk; he is expendable",
              "serves": ["power"],
              "effects": []
            }
          ]
        }
      ]
    }
  ],
  "endings": [
    {"id": "hand_broken", "title": "The Hand Broken", "requires": ["gregor_exposed", "succ_varn_dead"],
     "summary": "The supply line is cut and the camp scatters."}
  ]
}
```

### Field rules

- `prefix`: every flag this storyline **declares** in `flags` starts with it. Prefixes are unique.
- Flags you may **reference** (in `requires`, `resolves_on`, effects, endings): the 26 existing
  flags in `scripts/world_state/story_flags.gd`, your own `flags`, and flags listed in `crossovers`
  (another storyline's flags; validated once all storylines exist). Prefix a flag with `!` in
  `requires` to mean "must be false".
- Every declared flag's description is NPC-facing canon: a plain past-tense sentence of what
  happened. NPCs will remember it verbatim, so no meta language ("the quest", "the player chose
  option B").
- `requires`: all must hold for the beat to **open**. `resolves_on`: any one becoming true
  **resolves** the beat. A beat blocked by `block_beat` stays closed until an `unlock_beat`.
- Beat ids are unique within a storyline; hook ids unique within a storyline.
- `act` (optional int 1-3) on a beat: which act it belongs to. Informational; shown in debug tools.
- **Endings:** evaluated in file order; the first ending whose `requires` all hold is the one a
  storyline reaches. Order endings from most specific to least.
- **Agendas** may target any NPC, not only the acting one (an NPC can put words in another's mouth,
  e.g. Mira coaching Gregor). Most should still belong to the actor.
- **Player choices:** flags only the player can set (pledges, decisions) are declared like any other
  and set through `StorylineDirector.player_choice(flag)`; list them in `resolves_on`, not in NPC options.
- **Rumors carry only truth:** `spread_rumor` of a flag that is currently false is dropped. To
  frame someone, an NPC must `set_flag` (if its Agency allows), not spread a falsehood.
- **Ordering:** when one flag change both triggers a beat's `on_flag:<f>` hooks and resolves it,
  the `on_flag` hooks fire first, then `on_resolve` effects, then `on_resolve` hooks. Beats are
  processed in file order, hooks in array order; flag changes caused by effects are queued and
  processed afterwards (cascade depth limit 32).
- `on_resolve` effects run however the beat resolved. Put outcome-specific results in option effects.
- **Blocked beats:** a blocked beat's hooks do not fire, **except** hooks with an option containing
  `unlock_beat` for that same beat. That is how an NPC breaks a block.
- `endings[].requires` uses the same flag rules.

### Hooks

| field | meaning |
|-------|---------|
| `type` | one of `intercept`, `react`, `scheme`, `reveal`, `aid`, `betray` |
| `trigger` | `on_open` (beat opens), `on_resolve` (beat resolved), `on_flag:<flag>` (flag turns true while beat open), `idle` (offered periodically while the beat is open) |
| `eligible` | NPC keys who may act here. More than one = they compete; first to act wins unless `stack: true` |
| `situation` | What the NPC perceives, in second person, in-world. This is the agent's prompt |
| `options` | 2-4 authored choices. Each has `id`, `label`, `serves` (want ids it advances, used by the offline chooser), `effects`, optional `aids`: npc key (refused by souls with `ally:` against them), and optional `harms`: [npc keys] (refused by souls with a matching `harm:` line), and optional `when`: a time-of-day window (§8: `dawn`, `morning`, `evening`, `dark`, `night`, `tonight` 18-04, `HH-HH`...). An option with `when` is decided at once but carried out when the window next opens: its effects are scheduled (saved, re-validated when they land) and the chronicle lists them under `scheduled`. Give it only when the label says when the act happens ("after dark", "at dawn", "tonight"); not for deadlines ("before dawn"), standing policies ("from tonight") or refusals |
| `allow_freeform` | optional bool. If true a Claude-driven NPC may compose its own effect list instead of picking an option, limited to `freeform_effects` (array of effect types) and its soul's Agency |
| `once` | optional, default true |

**Hook types, intent:** `intercept`, change course before the beat resolves. `react`, respond after
it resolves. `scheme`, NPC-initiated plotting while a beat is open. `reveal`, decide whether to
tell what they know. `aid`, help someone (player or NPC). `betray`, turn on someone.

### Effect vocabulary (fixed; nothing else is accepted)

| type | params | does |
|------|--------|------|
| `set_flag` | `flag`, `value` (bool) | WorldState flag; drives every other system |
| `adjust_relationship` | `npc`, `dimension` (`trust`/`respect`/`affection`/`fear`/`familiarity`), `delta` (-20..20) | That NPC's feeling toward the player |
| `spread_rumor` | `flag`, `to` (npc keys or `["*"]`), optional `via` (text) | EventPropagator gossip of that flag's canonical text |
| `agenda` | `npc`, `text` (≤160 chars) | Something the NPC will raise or pursue in its next conversation with the player |
| `move_npc` | `npc`, `location` | NPC relocates (schedules/scenes honour it later) |
| `block_beat` | `storyline`, `beat` | Beat cannot open or resolve until unlocked |
| `unlock_beat` | `storyline`, `beat` | Reverses `block_beat` |
| `shift_want` | `npc`, `want`, `delta` (-3..3) | Runtime soul drift for that NPC |

An NPC may apply an effect only if (a) the effect appears in the chosen option (or in
`freeform_effects`), (b) its soul's Agency grants that effect type for this hook type, and (c) no
Lines-I-Will-Not-Cross rule forbids it. Effects failing any check are dropped and logged.

---

## 4. Authoring guidance (what makes a good hook)

- **Every beat should have at least one hook**; the strongest beats have hooks for two NPCs who want
  opposite things. That is where the world feels alive.
- Options should each be something this character would genuinely consider. One option should
  usually be "do nothing", so that inaction is a choice the soul makes.
- `serves` should cite real want ids from that NPC's SOUL.md. The offline chooser picks the option
  whose `serves` wants have the highest total weight.
- Prefer flags and agendas over hard blocks. Blocking a beat should be rare and dramatic.
- Storylines intersect: reference the shared flags in `story_flags.gd` freely, so that an NPC acting in
  one storyline ripples into another.

---

## 5. The world registry

`resources/world/world.json` is authoritative for NPC keys, locations (built and planned), the
travel graph (`routes`: minutes plus modes `foot`/`horse`/`cart`/`barge`), the realm's
`world_rules`, and `forbidden_concepts`. The tables in section 1 are a convenience copy; when they
disagree, world.json wins. The validator and the runtime both read world.json.

## 6. Free-form conversation and NPC actions

Dialogue is not scripted. When the player talks to an NPC (Claude mode), the NPC answers in
character from its soul, memories, relationship and world knowledge, and **may also act** on what was
said. Those actions are the same effect vocabulary as hooks, held to the same soul rules, plus
**plausibility** rules that keep the story and the world coherent.

**Soul grants.** A soul's `## Agency` may include a `converse:` line listing the effect types it may
use in conversation. Without one, `converse` falls back to the union of its `react`, `reveal` and
`aid` grants.

**What the NPC is told it can do,** each turn:
- its soul block (essence, current top wants, lines, voice) and current location;
- the world rules from world.json;
- the **open beats** this NPC has hooks in, with those hooks' options as *suggested* moves (not
  a menu it must pick from);
- the flags currently **in reach** (see below), and the player flags it may recognise;
- places it can go next, with travel time, from the routes graph.

**Plausibility rules** (runtime-enforced; failing actions are dropped and chronicled with a reason):
1. **Vocabulary and soul.** Only the 8 effect types, only those the soul grants for `converse`, and no
   Lines-I-Will-Not-Cross violations.
2. **Flags in reach.** An NPC may `set_flag` only flags that appear in an **open** beat's
   `resolves_on`, or in an effect of an option on a hook the NPC is eligible for in an open beat.
   No skipping ahead in a story.
3. **Truth.** `spread_rumor` only spreads flags that are currently true (unchanged).
4. **Place and time.** `move_npc` targets must be reachable from the NPC's current location on the
   routes graph. The move takes effect when the conversation ends, and the NPC is unavailable for
   the route's travel time. Nothing happens instantly at a distance: an action aimed at a far
   location becomes an `agenda` or a delayed effect, never an immediate change.
5. **Player commitments.** The NPC may report that the player made a genuine commitment
   (`"commitments": ["<flag>"]`), but only for flags in a storyline's `player_flags` whose beat is
   open. Those go through `StorylineDirector.player_choice`. The NPC judges whether the player meant
   it; a joke or a lie it saw through is not a commitment.
6. **World rules in speech.** Dialogue and action text containing a `forbidden_concepts` word (whole
   word, case-insensitive) is regenerated once with a correction note, then sanitised if it fails
   again.
7. **Budget.** At most 3 actions per NPC reply, and at most one `set_flag` that resolves a beat.

## 7. Player flags

A storyline lists the flags only the player can set in `"player_flags": [...]` (each must also be
declared in `flags`). They are set either by the debug command `choose <flag>`, by StoryItems, or by
an NPC recognising a commitment in conversation (rule 5 above). Endings should need at least one
player flag, so that the world never finishes a story without the player.

### Player-centrality (validator-enforced)

The world advances Acts I-II on its own; it never finishes a story without the player.
- Every beat declares `"act"` (1-3).
- Every **Act III** beat either `requires` a player flag (from any storyline's `player_flags`) or
  resolves **only** on this storyline's player flags. NPCs still have hooks there to shape *what*
  happens; the player decides *when*.
- Every ending requires at least one of its storyline's `player_flags`. The single deliberate
  exception is `elenas_fever:the_locked_room` (neglect has consequences).
- Acceptance test: `godot --headless --path . -s res://scripts/debug/idle_world_sim.gd` runs
  200 story rounds with no player and must print `SIM PASS`.

---

## 8. Personal arcs (`## Life` in SOUL.md)

The third tier of free will. Storylines are the region's plot; **Life** is what an NPC pursues for
itself when no storyline asks anything of it. Personal arcs act only at **personal scope**: they
never set a storyline flag, and they can't finish anything but the NPC's own life goals. Storylines
may *read* personal flags (in `requires`, `on_flag:` triggers, endings), so private lives feed the
plot without being able to override it.

```markdown
## Life
### Arc: `true_blade` (serves `honest_steel`)
Prose: why this matters to him, in his voice. One short paragraph.
- `clean_iron`: Find ore the Hollow never touched. | after: none | needs: !vein_ore_road_closed | at: greystone_mines | takes: 2 | effects: agenda, move_npc
- `the_first_fold`: Fold the iron by lamplight, alone. | after: clean_iron | needs: none | at: thornhaven_blacksmith | takes: 3 | effects: shift_want
- `show_someone`: Put the blade in a hand he trusts. | after: the_first_fold | needs: none | at: any | takes: 1 | effects: agenda, adjust_relationship | player: helps
- result: `bjorn_true_blade_forged`: Bjorn forged a blade he was proud to put his mark on.
- fails_if: `bjorn_left_the_forge`, `hc_varn_dead`
```

Machine lines (exact shape):
- `### Arc: \`<arc_id>\` (serves \`<want_id>\`)`. The want must be one of this soul's Wants. Its
  current weight sets how hard the NPC pursues the arc.
- Step: `- \`<step_id>\`: <text> | after: <step_id|none> | needs: <flags, comma-separated, ! allowed | none> | at: <location id|any> | takes: <rounds 1-6> | effects: <types>`, optionally followed by
  `| when: <window>` and then `| player: helps|needed`.
  - **Opening hours** (world.json `opening_hours`, game clock, 06:00-24:00): every place, for every
    NPC. Outside them nobody acts or arrives anywhere: story rounds take no decisions (queued hooks
    wait), personal steps wait, scheduled effects wait, a timed option's effects land at the first
    minute inside both its window and the hours, and a journey that would arrive while the world is
    closed leaves later so it arrives at opening. Night windows therefore end at midnight. Calendar
    points still fire on time; the player is not held to the hours.
  - **`when`** is the hour the step can be taken, checked at the hour the NPC would arrive:
    `dawn` (05-08), `morning` (06-12), `day` (08-18), `afternoon` (12-17), `evening` (17-22),
    `dark` (19-05), `night` (21-05), `tonight` (18-04), `any`, or `HH-HH` (wraps past midnight when the end is
    earlier). Without it a step happens in waking hours (06-22): people sleep, so a step done
    by night, by candle or after dark must say so. Scripts: `scripts/storyline/time_window.gd`.
  - **`effects`** may only use the personal-scope types `agenda`, `move_npc`, `adjust_relationship`,
    `shift_want` and `spread_rumor` (true flags only). Never `set_flag`, `block_beat` or `unlock_beat`.
  - **`player: needed`** means the step completes only after the player commits to helping, through
    conversation. **`helps`** means the player can halve `takes`.
- `- result: \`<npckey>_<flag>\`: <past-tense canon description>` is the personal flag set when
  the arc completes. It must start with the NPC's key.
- `- fails_if: \`<flag>\`[, \`<flag>\`...]`: optional. The arc is abandoned if any of these becomes
  true. Abandonment is remembered and may drift wants.
- Each completed step also sets the derived personal flag `<npckey>_<arc_id>_<step_id>`.

Each main NPC has **2-3 arcs**, at least one of which crosses into another NPC's life (an
`adjust_relationship` or `agenda` aimed at them).

**Runtime.** Each story round, the Director gives up to `personal_decisions_per_round` (default 4)
NPCs a personal turn. NPCs near the player and those with high-weight active arcs go first. The NPC
works on its first available step: its `after` is met, its `needs` hold, and it is at `at` or can
reach it. The step's effects go through the same soul and plausibility checks as everything else.

**Offline step effects** (what a personal turn does when no Claude agent phrases it):
- `agenda` goes to the NPC the step text names, otherwise to the actor itself.
- `adjust_relationship` is trust +5, and only applies when the player helped with that step.
- `shift_want` is +1 to the served want.
- `spread_rumor` spreads the step flag, or the result flag on the final step, to the actor's region.
- `move_npc` has no extra effect, because travel to `at` already happened as part of the turn.

**Helping.** The player promises help in conversation. The NPC reports it as the commitment
`help:<key>_<arc>_<step>`, which counts toward the per-reply commitment budget.

**Opting out.** A soul may forbid all personal acts with the Lines rule `hook:personal`.

## 9. Generic NPCs, layering, promotion and demotion

Everyone who isn't one of the 19 authored NPCs is a **generic**: a farmer, a dockhand, a gate guard,
a pilgrim. Generics are cheap until they matter.

**Archetypes.** Each lives at `resources/generics/archetypes/<archetype_id>.md` and uses the SOUL.md
format with these differences:
- the header has `archetype: <id>` plus `regions: <region ids>` instead of `npc:`
- want weights are ranges, written `` `id` (3-7) ``, and each instance rolls its own
- Essence and Voice may use the slots `{name}`, `{home}` and `{region}`
- Agency is limited to `converse:` with personal-scope effects only
- a `## Life` section holds 1-2 small generic arcs (saving for a cow, a sick mother). Their result
  flags use the literal prefix `{id}_`, which is replaced with the instance id.

`resources/generics/names.json` holds name pools per region. `resources/generics/population.json`
lists generics per location as `{archetype, count}`.

**Instances and layers.**
- Each generic is an instance (`gen_<archetype>_<n>`) with a seed. The seed fixes its name, its want
  weights within their ranges, and its voice variant.
- Every interaction adds **layers** on top of the archetype:
  - things the generic learned about the player
  - notable moments (gifts, threats, secrets, help)
  - trait and want nudges
  - relationship dimensions
  - news it heard as gossip
- Its prompt is the archetype base, then the instance seed, then its most important and recent
  layers. This is compact by design.

**Significance and decay.** Every NPC, main or generic, has relationships that **fade without
contact**. Per game day apart, they move toward a baseline (rates in `world.json`
`relationship_decay`): familiarity fastest, fear and affection slower, trust slowest. A generic's
**significance** (0-100) combines its relationship strength, the importance of its layers, how
involved it is in the story (witnessed events, carried gossip), and recency.

**Promotion** (generic → main). When significance holds at or above 60 across 3 story rounds:
- The generic becomes **individual**. A full SOUL.md is assembled from its archetype plus its layers.
  In Claude mode it is written in character, then validated by the soul parser. It is saved under
  `user://souls/<id>/SOUL.md`.
- It gets a ChromaDB memory collection, full conversation agency (personal-scope effects only), and a
  personal arc grown from its strongest want.
- It joins the Director's personal-turn pool.
- It can't be named in authored storyline hooks, but it can witness events and spread gossip like
  anyone else.

**Demotion** (promoted → generic, "friends become acquaintances"). When significance falls to 30 or
below and the player hasn't spoken with the NPC for 7 game days:
- The NPC keeps its name, a **residue** (its 3 strongest memories as one-line layers, trait nudges
  halved) and its history.
- It loses its personal arc, its chroma retrieval beyond the residue, and its personal turns.
- It remembers the player like an old acquaintance. Re-promotion is easier: the threshold drops by 10
  for each previous promotion, down to 40.

The 60/30 gap and the dwell times are hysteresis, so nobody flickers between tiers.

**Optional extensions.**
- `sprite: <character_id>` in an archetype header picks the reused sprite set.
- `"hours": [start, end]` on a population entry limits when that generic is present: game hours,
  wrapping past midnight (a tavern regular is there from 18 to 2).

The 19 authored NPCs are **anchored**: their relationships fade like anyone's, but they never demote.

---

# Part II: A world that answers the player (non-linear rules)

> **Principle:** Nothing about Land is linear. The world changes because of what the player
> does, says, decides, intends, and who they spend time with. Authored storylines are sources of
> pressure, not tracks to follow. Fixed points are defaults the player can move. Endings describe the
> world the player made.

## 10. Player events and reputation

Everything the player does that someone could plausibly notice becomes a **player event**. These
are the world's memory of the player.

```json
{"id": "pe_000123", "kind": "promise", "summary": "promised Gregor to get Elena out before the cart",
 "about": ["gregor", "elena"], "flag": null, "truth": "unknown", "status": "open",
 "location": "thornhaven_gregor_shop", "minute": 1460,
 "witnesses": ["gregor_merchant_001"], "heard_by": {}, "fidelity": 1.0}
```

- **`kind`** (fixed vocabulary): `claim`, `promise`, `threat`, `lie`, `insult`, `gift`, `help`,
  `harm`, `theft`, `kill`, `spared`, `confession`, `accusation`, `refusal`, `seen_at`, `kept_company`.
- **Sources:**
  - **Conversation.** The NPC's analysis gains `"utterances": [{kind, about, summary, believed}]`,
    meaning what the player claimed, promised, threatened or confessed, from that NPC's point of
    view.
  - **Deeds.** StoryItems, theft or gifts once items exist, travel arrivals (`seen_at` by anyone
    present), and time spent near an NPC (`kept_company`).
  - **Commitments.** Player-flag commitments also log a `promise` event.
- **Truth.** A claim that maps to a flag is checked against the world. The first time the world
  contradicts a `claim` or `promise` (a known false flag, a missed deadline), it turns into a `lie`
  or a broken promise, and that change is itself an event that can spread.
- **Promises** carry `due` (`{"day": n}` or `{"flag": f}`). The status runs `open` → `kept` |
  `broken`. Breaking a promise is one of the strongest reputation events.
- **Spread.** Witnesses remember an event at fidelity 1.0. Each retelling over the routes graph
  costs time (route minutes) and fidelity, and the summary drifts toward the teller's attitude.
  Someone who fears you tells it darker; a friend softens it. Below fidelity 0.3 it is "a rumour
  about a stranger". NPCs store what they *heard*, not what happened, and only what they could
  plausibly have heard.
- **Reputation.** Reputation is computed per NPC, per **faction** (`world.json` `factions`) and per
  **region**, only from the events each party knows about, weighted by fidelity and recency. Nobody
  is omniscient. It is injected into NPC prompts as "what you have heard of the stranger" and read by
  the director.

## 11. Movable fixed points

Each calendar entry may declare `"movable": true` and `"shift_rules"`:

```json
"tn_collection_night": {"day": 7, "hour": 22, "movable": true,
  "shift_rules": [
    {"when": "hc_varn_dead", "action": "delay", "days": 2, "reason": "The Hollow is leaderless; the cart waits."},
    {"when": "cou_council_refuses", "action": "delay", "days": -1, "reason": "The Hollow answers defiance early."},
    {"when": "tn_taken_freed", "action": "cancel", "reason": "There is no Pit left to fill."}]}
```

- Every movable point also has a derived, world-caused **`<point>_eve`** flag, set 24 game hours before the
  point's *current* time; it moves with the point. Gate "the night before" content on it, not on a day flag.
- **NPC-only advances are capped:** advances with no player in their causal chain total at most −1 day per
  point. Player-caused shifts are only clamped per shift (−3..3).
- Shift rule actions are `delay` (negative `days` brings a point earlier) and `cancel`.
- New effect type **`shift_fixed_point`** `{point, days (-3..3) | cancel: true, reason}`. It is
  granted through soul Agency like any other effect. Mira, Varn and Mathias plausibly have it, and
  the player moves points through choices that trigger it.
- Shifts are chronicled and canonical, and they become a world event that the people affected hear
  about. A point that has already fired can't be moved. A cancelled point never fires; the flag
  `<point>_cancelled` becomes true instead.

## 12. Emergent beats

`resources/emergence/<id>.json` holds **templates** the director instantiates whenever the world
matches them. They are not authored storylines. They are stories that grow out of what the player
did.

```json
{"id": "broken_promise_surfaces", "title": "The Promise You Didn't Keep",
 "trigger": {"event": {"kind": "promise", "status": "broken"}},
 "roles": {"wronged": {"from": "event_witness", "prefer": "affection_desc"}},
 "cooldown_days": 2, "max_active": 2, "expires_days": 3,
 "location": "{wronged.home}",
 "hooks": [{"id": "confront", "type": "react", "eligible_role": "wronged", "trigger": "on_open",
   "situation": "The stranger swore to {event.summary}. They didn't.",
   "options": [
     {"id": "demand", "label": "Find them and demand an answer", "appeal": {"trust": -0.5, "fear": -0.3, "respect": 0.2},
      "effects": [{"type": "agenda", "npc": "{wronged}", "text": "Ask the stranger why their word was worth nothing."},
                  {"type": "adjust_relationship", "npc": "{wronged}", "dimension": "trust", "delta": -10}]},
     {"id": "tell_others", "label": "Make sure the village knows", "appeal": {"affection": -0.5},
      "effects": [{"type": "spread_event", "event": "{event.id}", "to": ["*"]}]},
     {"id": "let_it_go", "label": "Say nothing; remember it", "appeal": {"affection": 0.6}, "effects": []}]}],
 "resolves_on": ["talked_to:{wronged}", "expired"]}
```

- **Triggers** match player events (`kind`, `status`, `about`), reputation thresholds
  (`{"reputation": {"faction": "iron_hollow", "below": -40}}`), relationship thresholds and flags.
- **Roles** bind to real NPCs at instantiation:
  - `from` is one of `event_witness`, `event_about`, `heard_event`, `faction:<id>`,
    `near_player` or `npc:<key>`;
  - `prefer` is a dimension with `_asc`/`_desc`, or `nearest`.
  - Generics are eligible too.
- **The offline chooser** uses `appeal`: the dot product of the coefficients with the bound NPC's
  relationship dimensions toward the player (−100…100), plus their soul's Lines and Agency as usual.
- **Generics in emergent beats** (tier `generic`) may use every emergent effect except
  `shift_fixed_point`, whatever their `converse:` line says, because gossip is what generics do.
  Main and promoted souls use their normal Agency for the hook type. Lines rules apply to everyone.
- **Extra fields.**
  - Event match: `location` (a list), `region`, `tone`, `min_count`, `first`, and
    `about: ["archetype:<id>"]`.
  - Role filters: `faction`, `region`, `knows_of_player`.
  - Agenda `npc` may be a literal key, and `spread_event` `to` may be role slots, NPC keys or `["*"]`.
- **Allowed effects** are personal-scope plus `spread_event` (new: it spreads a player event) and
  `shift_fixed_point`, if the bound soul grants it. Emergent beats never set storyline flags.
- **`resolves_on`** accepts `talked_to:<role>`, `expired`, `days:<n>` and flags.
- Every instantiation is chronicled, and it becomes the bound NPCs' memory.

## 13. Inner voice (the player's thoughts)

The player can voice private thoughts at any time. A thought is parsed into an **intention**
`{goal, about[], stance, strength}`.

- **NPCs never see it.** It never enters an NPC prompt, memory or gossip. A test enforces this.
- **The director reads it.** Matching storyline hooks, Life steps and emergent templates get a
  priority boost, so the people and opportunities relevant to what you intend surface sooner. The
  pressure against your plan also rises: those with opposing wants get turns sooner.
- **The epilogue remembers it.** Intentions are compared with deeds, so a plan you kept, abandoned
  or betrayed is part of how the world remembers you.

## 14. A playable opening

The drawing is a scene you are in, not a cutscene.
- At 20:00 you stand in the chapel with the village around you.
- The drawing itself is a movable fixed point (`tn_drawing`, Day 1 at 20:10).
- You can talk to anyone, speak up, try to stop it, slip out, or watch. Whatever you do is the first
  player event.
- Disrupting it shifts the drawing to the next morning, with consequences.
- A short skippable narration sets the scene and nothing more.

## 15. Epilogues, not endings

When the player ends the game (any time, or at a season's end, `season_end`, a fixed point on day
30), the epilogue is **generated from the world state**:
- one passage per main NPC (and any promoted generic) the player touched: their state, what they
  know and believe of you, their Life arcs, how they ended;
- one per settlement and region: storyline state, reputation, the fixed points that moved;
- the player's intentions set against their deeds.

Authored storyline endings that were reached are **named highlights** inside the epilogue, not the
destination. The prose is assembled offline from templates; in Claude or local-LLM mode it is
written in the world's voice and validated against the facts.
