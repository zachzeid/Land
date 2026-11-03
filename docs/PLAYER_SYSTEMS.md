# Player Systems: skills, levels, combat, crafting, puzzles

Status: **signed off 2026-11-03**, being built. Decisions taken with the lead: use-based skills with
a derived level (Valheim); real-time stamina combat (Valheim / Breath of the Wild); all three puzzle
kinds (systemic physics, lore and evidence, authored rooms); one spec, then all five systems built
in parallel. §10 records the rest.

Inspiration, and what is taken from each:
- **Valheim**: skills that rise by use and fall a little on death; stations that gate recipes;
  materials that gate progress (ore, a forge); stamina as the currency of every action.
- **Minecraft**: gathering, materials becoming tools becoming better materials; a world that is
  built from things you can take apart.
- **Breath of the Wild**: chemistry, not scripts. Fire, wind, water, weight and metal follow rules,
  and puzzles and fights fall out of how the rules combine. Cooking by combining ingredients.
  Weapons that wear out. Every problem has more than one answer.

What Land adds: **every one of these actions is a deed in a world that watches.** Nobody gives the
player XP for fighting; people see them fight, tell others, and change how they act. That is the
point of the five systems and the test of every design choice below.

---

## 1. Rules every system follows

1. **One door into the world: `PlayerEvents.record()`.** A system never writes NPC memories,
   reputation or relationships itself. It records a deed (kind, summary, about, opts); the existing
   machinery does the rest: witnesses from who is present, memories, regional gossip that loses
   detail at each retelling, reputation per NPC, faction and region, emergent beats, crowds. New
   deed kinds are added to `PlayerEvents.KINDS` (§7).
2. **NPCs only know what they could plausibly know.** A fight in the forest with no witnesses is a
   rumour at most, and only if someone finds the body or the wounds. Skill is known from what was
   seen or heard, never from the player's sheet. **Physical deeds** (deaths, fights, theft, fire,
   feats, crafting) are witnessed by line of sight (`Witnesses.in_sight()`, §8), not by being at the
   same location; spoken deeds stay with whoever was in the conversation.
3. **Canon** (world.json `world_rules`, WORLD_BIBLE): late-medieval, low magic. No spells. The
   "magic" is herbcraft, faith and fraud. Power is muscle, water and wind; light is fire. Forbidden
   concepts stay forbidden in item names, recipe text and puzzle text (the validator checks).
4. **Harming a child is the worst thing the player can do.** (Changed 2026-11-03.) The player can
   strike or kill anyone, children included (Rook, Ada Fenn, Pip, the Warrens' little ones, any
   generic archetype marked `minor`). It is recorded as `harm` / `murder` with `victim_minor: true`
   and carries the heaviest reputation cost in the game wherever it is known: seen in line of sight,
   told by the child who survived it, or found out later (a body found, a wound seen, a witness's
   gossip). NPCs and creatures still never target children, and no crowd forms against one.
5. **Opening hours apply to NPCs, not the player.** The player may fight, craft or climb at 03:00;
   NPCs answer at 06:00 (crowds, story rounds and scheduled effects already wait).
6. **Everything saves.** Each system adds a block to `WorldState.save()` the way StorylineDirector,
   PlayerEvents and InnerVoice do, and restores it on load.
7. **Data, not code, for content.** Skills, perks, items, recipes, creatures, puzzles and rooms are
   JSON under `resources/`, checked by `tools/validate_world.py`.
8. **Headless tests for every system**, in the style of the existing suites (`scripts/debug/test_*.gd`),
   with no API calls and no writes to the real save or ChromaDB.

---

## 2. Skills and level

### Skills (resources/player/skills.json)
Each skill is 0-100, rises by use, and decays a little on a bad death.

| Skill | Raised by | What it changes |
|---|---|---|
| `blades` | hitting with swords, knives, axes used as weapons | damage, stamina per swing, parry window |
| `blunt` | hammers, clubs, staves | damage, stagger (poise damage) |
| `bows` | hitting with a bow or sling | draw speed, sway, damage at range |
| `defence` | blocking and parrying | stamina per block, parry window |
| `athletics` | sprinting, dodging, climbing, swimming | stamina pool regen, climb speed |
| `stealth` | moving unseen near people, picking locks | noise, how far witnesses see (§1.2) |
| `smithing` | forging, repairing | item quality, recipes unlocked |
| `woodcraft` | felling, carpentry, fletching | quality, yield |
| `herbcraft` | gathering herbs, cooking, brewing remedies | potency, recipes the player can work out |
| `mining` | breaking ore and stone | yield, speed |
| `speech` | persuading, bargaining, calming a crowd | prices, how often talk ends a fight (§3.6) |
| `lore` | reading, solving lore puzzles, studying evidence | clues shown, puzzle hints |

**Gain (Valheim's rule):** `gain = base_xp × difficulty × (1 - level/110)`, so early levels come
fast and mastery is slow. `difficulty` comes from the target: hitting a practice post gives a
tenth of hitting a soldier; smelting easy ore gives less than forging a blade. A skill only rises
when the action could fail (no gain for hitting a sleeping man).

**Teachers:** an NPC with the trade (Bjorn smithing, Ysolde herbcraft, Aldric blades and defence,
Rook stealth, Wren lore, any generic whose archetype has the trade) can train the player. Training
is a conversation agency action (`teach`): it costs coin or a favour, takes game time, and multiplies
gain for a while. Whether they teach is the soul's choice: trust, respect, wants and Lines decide.

**Death** (lead's ruling):
- **Skill loss grows with each death.** Normal: the first death costs 1% of every skill's level,
  each later death one point more, capped at 25%. Hard mode: the loss doubles each death (1, 2, 4,
  8, 16, 32...), capped at 50%. Difficulty (`normal` / `hard`) is chosen at a new game and saved.
- **Every death drops the whole inventory** where the player fell, as a pack in the world (Valheim).
  It stays until taken. NPCs who come upon it decide by their souls: take it, keep it safe for the
  player, hand it to the watch, or leave it (an emergent template, `a_pack_by_the_road`).
- **Only NPCs with line of sight remember it.** A `fell` deed with the witnesses found by
  `Witnesses.in_sight()` (§8); walls and darkness block sight. The player wakes where they last
  slept, or at the nearest inn.

### Level (derived, never spent)
`level = floor(sum of the top six skills / 30)`, 0-20. It raises maximum health and stamina
and nothing else. Milestones (every skill at 25, 50, 75, 100) unlock **perks**
(resources/player/perks.json), e.g. `smithing 50: maker's mark` (items you forge carry your mark;
NPCs who see the mark know the maker), `herbcraft 25: know a root by its leaf`, `blades 75: disarm`.

### How the world sees skill
- **Feats.** A skill used where people can see, at a level that stands out, records a `feat`
  deed (`"held off three Hollow men with a blacksmith's hammer"`, `"mended the mill wheel in an
  afternoon"`). Feats spread like other loud deeds. Thresholds: the first time each skill passes
  25/50/75 while witnessed, and any single act far above an onlooker's own skill.
- **Respect.** Witnessed feats in an NPC's own trade move their `respect` (Bjorn watching a true
  weld; Aldric watching a clean parry). This uses the existing relationship effects, so the
  conversation prompt already reflects it ("You deeply respect their abilities").
- **Prompts.** The "what it heard" section (PlayerEvents) already includes the top known deeds;
  feats appear there with fidelity, so a far-off rumour says "a stranger handy with a blade".
- **Emergent beats** (§7): rivals, apprentices, people asking for help with a skill they heard of.

---

## 3. Combat

Real-time, top-down, stamina-based. Every action spends stamina; out of stamina you cannot block
or dodge. Fights are dangerous, short and avoidable.

### Stats (PlayerStats)
- **Health**: base 100, + level × 5. Regenerates slowly out of combat; food and remedies help.
- **Stamina**: base 100, + level × 5, + athletics. Regenerates quickly when not spending it.
- **Poise**: hidden. Heavy hits drain it; at zero you stagger (Valheim / BotW).

### Actions
| Action | Stamina | Notes |
|---|---|---|
| light attack | 10 | fast; chains |
| heavy attack | 25 | slow; high poise damage |
| block | 5 per hit, scaled by damage | weapon or shield |
| parry | 10 | block in the first 0.25 s (wider with `defence`); staggers the attacker |
| dodge | 15 | short invulnerable roll |
| sprint | 8/s | |
| draw/shoot | 12 | bows and slings |

**Damage types:** cut, pierce, blunt, fire. Armour resists by type (leather vs cut, mail vs cut and
pierce, padding vs blunt). Creatures and people have resistances in data.

**Durability (BotW):** weapons and tools wear out with use and break. Quality (§4) sets how many
uses. Smiths repair; a broken blade can be re-forged.

### Who fights, and how they decide
- **Creatures** (resources/combat/creatures.json): wolves and boar in the Darkwood, adders on the
  ridge, rats in the Pit. **These are new canon** (WORLD_BIBLE names no wildlife); listed for
  approval in §10. They fight by simple behaviour (stalk, charge, flee when hurt).
- **People.** Any NPC with a soul can fight, but **whether they do is their soul's choice**, using
  the existing decision machinery: a combat decision is a `react` hook on that NPC with options
  fight / yield / flee / call for help / talk, chosen by their Agency, Lines and feelings toward the
  player (offline appeal, or Claude). Lines apply: a soul with `harm:<x>` will not attack x, and
  defends them. A `crowd` Line refuses mob violence.
- **Morale.** People do not fight to the death. Each has a morale value (fear toward the player,
  wounds, allies down, the soul's wants) and yields or flees when it breaks. Yielding is the
  common end of a fight between people.

### Endings, and what the world does with them
| Ending | Deed recorded | Who reacts |
|---|---|---|
| player kills a person | `kill` (about: the dead; witnesses) | `register_npc_death`; storylines already treat dead NPCs; mourners, kin, factions, crowds |
| player wounds a person | `harm` | relationships, reputation, crowds (trust/affection fall) |
| person yields; player lets them go | `spared` | respect and fear rise; the spared may become a debtor (emergent) |
| player yields or flees | `fled` (new) | respect falls for those who saw |
| player defends someone | `help` (about: the defended) | the defended and their friends |
| a fight is talked down (`speech`) | `feat` (speech) | |
| a creature is killed | none unless it mattered (a wolf taking sheep: `help` for the farmer) | |

Peacekeepers (Aldric's watch, the rangers, Capitol guards) respond to witnessed violence in their
area through an emergent template, by their souls: arrest, warn, look away, or join in.

### Combat and the existing systems
- **Crowds** become real: a crowd that gathers against the player (§12 of WORLD_SCHEMA) can turn
  into a fight if its ringleader chooses to, and a protector can stand in the way.
- **Fights cost time** on the game clock and happen at a place, so NPC opening hours, travel and
  presence all apply.

---

## 4. Crafting, gathering and herbcraft

### Gathering (Minecraft / Valheim)
Resource nodes in scenes (resources/crafting/nodes.json): trees (wood), stone and ore outcrops
(Greystone: iron ore; the deep vein: white salt, story-gated), herbs by region and season
(fever-root in the Darkwood, river herbs at Ferrisford), flax, hides from creatures. Nodes deplete
and regrow on the game clock. **Taking from someone's land or stores is theft** if seen (a `theft`
deed about the owner): a Greystone ore cart, Gregor's stock, the abbey herb garden.

### Stations (Valheim)
| Station | Where | Unlocks |
|---|---|---|
| campfire | anywhere outdoors | cooking, simple remedies |
| workbench | carpenter's, the player's camp | wood tools, bows, arrows, repairs |
| forge + anvil | Bjorn's forge (by his leave), Greystone, Fort Ashguard | smelting, steel, blades, armour, tiles |
| herb table / still | Maud's healer hut, the abbey, the Cathedral infirmary | remedies, the cure |
| loom | farmhouses, the Capitol market | cloth, padding |

**Using someone else's station is a request,** decided by its owner's soul (Bjorn may refuse a
stranger his forge until he respects them; his Lines refuse forging for Varn's men). A station used
without leave is trespass and theft of fuel, witnessed or not.

### Recipes (resources/crafting/recipes.json)
Each recipe: inputs, station, skill + minimum level, time (game minutes), output, quality formula.
Recipes are **discovered** (Valheim): holding the inputs at the station shows them; some are
**taught** (a teacher, §2) and some are **found** (a ledger page, the abbey receipt for the cure).

**Quality** = skill, station, material grade. Quality sets durability and damage. A `maker's mark`
(perk) stamps the maker: anyone who examines the item knows who made it, which is how Bjorn knew his
own lot tiles. A mark can be evidence (lore puzzles, §5).

### Herbcraft and cooking (BotW)
Free combination at a campfire or herb table: 1-5 ingredients, effects from tags (healing, stamina,
warmth, fever, sleep, poison). Combinations that make no sense make "dubious food". Remedies are
real in the world:
- **The Grey Fever cure** (canon): fever-root steeped with the white salt of Greystone's deep vein.
  Making it is a story act: it records a `feat` and sets the existing cure flag through the
  StoryItem / discovery-flag path, so the Grey Fever storyline reacts exactly as if it were found.
- Root alone only quiets the fever (canon), and the game says so.

### Crafting and the world
- **Gifts** of things you made record a `gift` with the item's quality: a fine blade for Aldric's
  six moves more than coin.
- **Selling** at market moves prices a little (supply) and competes with makers: undercutting
  Bjorn is noticed by Bjorn.
- **Commissions:** NPCs ask for things their wants need (Aldric: steel for the gate; Elena: boots for
  the ridge) as conversation agendas; delivering is `help`, failing a promised commission is a broken
  `promise` (PlayerEvents already tracks promises).
- **Arming a side** (selling blades to the Hollow, giving Aldric's farmers steel) records the deed
  about the faction: reputation with both sides moves.

---

## 5. Puzzles

### 5.1 Systemic physics (WorldPhysics)
A small set of rules on any object that has the matching component. Puzzles are scenes where the
rules combine; nothing is scripted per puzzle.

| Element | Rule |
|---|---|
| fire | spreads to `flammable` things in reach (dry grass, hay, wood, rope, cloth) on a timer; wind carries it; burns out; lights `lamp`s and `torch`es |
| water | douses fire; rain wets everything outdoors (no spread while wet); fills `basin`s |
| wind | the region's wind direction and strength (weather); carries fire, smoke, light objects, arrows drift |
| weight | `plate`s press under enough weight (player, crates, stones, NPCs); counterweights; `rope` holds weight until cut or burnt |
| metal | sinks; conducts heat (a hot blade lights tinder); rusts if left wet; a lodestone pulls iron |
| light | lamps reveal and blind; shadows hide (stealth); sunlight by the game clock |

**The world reacts to physics as deeds.** A fire that burns Mira's barn is `harm` about Mira if
anyone saw who lit it, and a rumour about a fire if nobody did; the crowd machinery can find a
culprit (fairly or not). Saving a burning house is `help`. Physics never silently changes story
flags; a puzzle that matters to a story sets its flag through the puzzle contract (§5.2).

### 5.2 Lore and evidence puzzles (resources/puzzles/*.json)
Grown from the storylines, solved by the player's own reasoning, checked by the game:
- **Weigh the tiles:** the lot urn's tiles on Bjorn's scale; the recut one is light (canon).
- **The maker's marks:** match the spare tiles' casting to Bjorn's moulds and Davin's hand.
- **Gregor's ledger:** a simple substitution of names for sums; the decoded lines name the five years.
- **The tally sticks:** Oskar's notches against the barge dates.
- **The abbey receipt:** find the cure's page among Anselm's shelves by its index.
Each puzzle: clues (StoryItems and examinable objects), an answer the player gives (choose, arrange,
name), and on success a `discovery_flag` (world.json) and a `feat` (lore). Wrong answers can be
deeds too (accusing the wrong man aloud is an `accusation` that turns out false). The validator
checks every puzzle's flags are declared discovery flags and every clue exists.

### 5.3 Authored rooms (scenes/puzzles/*)
Shrine-style spaces built from the physics components, each grown from canon places: the old mine
workings above Greystone's seventh level, the abbey undercroft, the Pit's flooded gallery, the
Capitol's Warrens cisterns, Fort Ashguard's armoury. Each has a reward that matters in the world (a
way into the Pit the Hollow does not watch; the second set of salt letters; a lodestone), never a
floating chest.

---

## 6. The player's tools in the world

- **Inventory** (Inventory autoload): slots, weight limit (Valheim), stacks, equipment (main hand,
  off hand, armour, tool), items with quality, durability, maker and provenance (where it came from,
  stolen or not). NPCs who see a stolen item they know (Gregor's file, a ranger's sword) recognise it:
  a `theft` deed found out later, through the existing truth machinery.
- **Coin** (changed 2026-11-03) is copper, silver, gold and crowns: 100 copper a silver, 100 silver a
  gold, 100 gold a crown, held as copper internally. A copper buys what the old penny bought (ale 2
  copper, a labourer's day about 9, a season about 7 silver), so gold is a fortune and a crown is a
  treasury sum almost no one holds.
- **Camp:** a bedroll and campfire anywhere outdoors give a respawn point and a cooking station.

---

## 7. New deeds and emergent beats

New `PlayerEvents.KINDS`: `feat` (a skill shown), `crafted` (a thing made, for its maker and
whoever sees it), `fled`, `fire` (a fire started, by whoever is known to have started it),
`trespass`, `solved` (a puzzle with witnesses or consequences). Each gets importance and reputation
weights in `reputation.gd`, and the validator learns them.

New emergence templates (resources/emergence/), all bound by souls like the existing thirty:
| Template | Trigger | What can happen |
|---|---|---|
| `rival_smith` | feat smithing, witnessed by a smith | the smith's soul chooses: respect, rivalry, an offer to work together |
| `would_be_apprentice` | feat in any trade, a young generic hears it | asks to learn; teaching them is `help` |
| `challenger` | feat blades/blunt heard by a fighter | a duel, refused or fought; losing is `fled`, winning a `feat` |
| `debt_of_the_spared` | `spared` | the spared repays, or resents |
| `who_lit_it` | `fire` with a victim | the victim and neighbours seek a culprit; crowds can form |
| `the_watch_answers` | `harm`/`kill` in a peacekept area | peacekeepers arrest, warn, look away, by soul |
| `known_by_the_mark` | an item with the player's mark seen | the maker's name travels with the item |
| `a_wolf_at_the_fold` | creature harms a farmer's stock | the farmer asks for help |
| `buyer_for_the_blades` | the player sells weapons | a faction's buyer comes back for more, or a rival notices |
| `the_healer_from_away` | a remedy given that worked | others with the fever come to ask |

---

## 8. Architecture

New autoloads (after InnerVoice in project.godot), each one owner, each with `save()` /
`load_from_dict()` wired into WorldState like the existing ones:

| Autoload | Script | Owns |
|---|---|---|
| `PlayerStats` | scripts/player/player_stats.gd | health, stamina, poise, skills, level, perks, death |
| `Inventory` | scripts/player/inventory.gd | items, equipment, coin, weight |
| `Crafting` | scripts/crafting/crafting.gd | recipes, stations, quality, gathering nodes, herbcraft |
| `Combat` | scripts/combat/combat.gd | hits, damage, morale, NPC combat decisions, creatures |
| `WorldPhysics` | scripts/world/physics/world_physics.gd | elements, spreading fire, weight plates, wind |
| `Puzzles` | scripts/puzzles/puzzles.gd | lore puzzles, answers, rooms' state |

Shared helper (Phase 0): `Witnesses.in_sight(scene_root, at, opts) -> Array` of NPC ids whose
bodies have line of sight to a point (a ray to it not blocked by walls; range shrinks in darkness and
with the doer's `stealth`). Every physical deed passes these as `witnesses` to `PlayerEvents.record`.

Contracts between them (the only calls across ownership lines):
- `PlayerStats.use_skill(skill, difficulty, context) -> {gained, level, milestone}`;
  `spend_stamina(n) -> bool`; `damage(amount, type, source) -> {health, staggered, dead}`.
- `Inventory.add(item_id, qty, props) / remove / has / equip / get_equipped(slot)`; item records are
  `{id, qty, quality, durability, maker, provenance}`.
- `Crafting.can_craft(recipe_id, station_id) / craft(recipe_id, station_id) -> {ok, item, reason}`.
- `Combat.attack(attacker, target, action) / resolve_hit(...)`; `Combat.decide_npc(npc_key, situation)`
  goes through StorylineDirector's soul decisions.
- `WorldPhysics.ignite(node) / douse(node) / weight_on(plate)`, signals `fire_started`, `burned(node, owner)`.
- `Puzzles.answer(puzzle_id, answer) -> {ok, flag}`.
- Everything that is a deed calls `PlayerEvents.record()`. Nothing else writes NPC state.

Content: resources/player/{skills,perks}.json, resources/items/*.json, resources/crafting/
{recipes,stations,nodes,ingredients}.json, resources/combat/{weapons,armour,creatures}.json,
resources/puzzles/*.json; scenes/puzzles/*.tscn.

UI (minimal, playable): health/stamina bars, an inventory and equipment panel, a crafting panel at a
station, a skills page in the journal, hit feedback, a puzzle answer card. Input actions added to
project.godot: attack, heavy, block, dodge, use, inventory, craft.

---

## 9. Build plan (parallel, up to 10 agents)

Phase 0 (me, before the agents): this spec signed off; new deed kinds, reputation weights and the
validator's knowledge of them; autoload stubs with the contract signatures; save wiring; test
harness helpers. Everything the agents share exists before they start, so they never edit the same
file.

| Agent | Owns | Delivers |
|---|---|---|
| 1 Skills | player_stats.gd, skills/perks json | skills, gain, level, perks, death, feats, teachers (conversation `teach`) |
| 2 Inventory | inventory.gd, items json | items, equipment, coin, weight, provenance, stolen-item recognition |
| 3 Combat core | combat.gd, weapons/armour json | actions, stamina, damage types, poise, durability, hit resolution |
| 4 Combat world | combat NPC decisions, creatures json | soul-driven fight/yield/flee, morale, creatures, endings → deeds, minors rule |
| 5 Crafting | crafting.gd, recipes/stations/nodes json | gathering, stations (owner's leave), recipes, quality, maker's mark, commissions |
| 6 Herbcraft | ingredients json, cooking | BotW-style combination, remedies, the Grey Fever cure as a story act |
| 7 Physics | world_physics.gd, components | fire, water, wind, weight, rope, metal, light; deeds from physics |
| 8 Puzzles | puzzles.gd, puzzles json, rooms | five lore puzzles, two authored rooms, validator rules |
| 9 Emergence + world | resources/emergence new templates | the ten templates of §7, wired to the new deeds |
| 10 UI + input | scripts/ui/*, scenes/ui/* | HUD, inventory, crafting, skills page, puzzle card, input map |

Each agent works in its own git worktree of Land (no .env, no ./chroma), writes headless tests,
and runs the full suite before handing back. I merge in dependency order (Phase 0, 1-2, 3-8, 9-10),
run everything, then a windowed playthrough recorded with --write-movie.

---

## 10. Decisions (lead, 2026-11-03)

1. **Creatures** (new canon, accepted): wolves and wild boar in the Darkwood, adders on the ridge,
   rats in the Pit and the Warrens, a rare bear high on the ridge.
2. **Death**: growing skill loss (normal 1% +1 per death to 25%; hard doubling to 50%), the whole
   inventory dropped as a pack every death, line-of-sight witnesses only (§2). The +1 step on normal
   and doubling on hard are this spec's reading of "increasing" and "exponential".
3. **Killing**: anyone can be killed, with full consequences. Harming a child carries the heaviest
   reputation cost wherever anyone sees it or comes to know it (§1.4, changed 2026-11-03).
5. **Coin** (2026-11-03): copper, silver, gold, crowns at 100 each (§6).
6. **Story flags** (confirmed 2026-11-03): making the Grey Fever cure sets `grey_cure_recipe_known`,
   and solving the abbey receipt sets the same flag.
4. **Durability**: weapons and tools wear out and break, and can be repaired or re-forged.
