# World Bible: Hallowmere

> **Document Purpose:** Canon for the broader world. Read with `docs/STORY_NARRATIVE.md` (Thornhaven
> canon, which wins on any conflict), `docs/WORLD_SCHEMA.md` (formats), and
> `resources/world/world.json` (the authoritative list of regions, locations, routes, NPCs and world
> rules; code and validators read it).

## The realm

The **Kingdom of Hallowmere** is late-medieval and low-magic. King Aubren is nine years old. His
uncle, **Lord Protector Edric Hale**, has ruled as regent for four years. The treasury is thin after a
border war in the east, and the Lord Protector's hold on the regency council depends on revenue,
victories and the support of the great houses.

**Coin** is copper, silver, gold and crowns: 100 copper a silver, 100 silver a gold, 100 gold a
crown (the coin, not the throne). Ale is 2 copper, a labourer's day about 9, a season's wage about 7
silver. Valley folk count in copper and silver; a gold is a fortune, and a crown is a treasury sum
almost no one holds.

**The Capitol** is the city of Highmarch, which everyone simply calls the Capitol. It sits on the
River Ferris, three days' ride east of Thornhaven along the Kingsroad, or two days by road and barge
from Ferrisford. Its districts:
- **Palace Hill:** the Crown Court, the High Magistry and the great houses, Ashdown House among them.
- **The Lantern Market**, the **Cathedral of the Dawn** and the **Merchants' Guildhall.**
- **The River Quarter docks** and **the Warrens,** a slum built into the old flood-walls, where
  anything can be bought.

**Between the valley and the Capitol** lies the hill country of the **Eastern March**:
- **Greystone Mines,** the iron ore that becomes Bjorn's steel. Below its sealed seventh level lies
  the deep vein, and beyond the seal, reached only from the ridge, **the Pit**.
- **Fort Ashguard,** the crown garrison that Varn deserted.
- **Brackenmoor Abbey,** whose archive remembers the Grey Fever.

## How Iron Hollow connects to the wider world (secret canon)

1. **The Tithe and the salt.** Iron Hollow takes one Thornhaven villager a year by lot, and coin from
   the council's tribute fund in the chapel undercroft. For five years Gregor rigged the lot, for the
   white salt that keeps Elena's Grey Fever down; this year Elena rigged it against herself. The taken
   are alive, digging that salt in chains in **the Pit**, a back-seam of Greystone's deep vein that the
   Hollow broke into from the ridge side after Foreman Dagna sealed her own side. The salt is the
   Hollow's real fortune (see "The Tithe and the wider world" below).
2. **Mira's money has to go somewhere.** Tithe coin, stolen cargo, Gregor's supplies and above all the
   salt have to become coin and safety. The salt goes down the far half of the ridge trail to
   Greystone's carters; plunder goes east by Hollow barge from Ferrisford. In the Capitol,
   **Guildmaster Hollis Marrow's** warehouses buy the salt and launder the plunder, and **Rook** in the
   Warrens fences the rest.
3. **Lady Seraphine Ashdown** holds the ancient deed to the Western Valley. A valley that gives up a
   child a year is a valley whose freeholders sell cheap and leave. Through Hollis, she has quietly
   invested in the Hollow's "protection" so that she can buy Thornhaven acre by acre. She has never
   met the Boss, does not know it is a woman, and has not asked what the Tithe does with the people
   it takes.
4. **Varn** was a sergeant at **Fort Ashguard** who deserted with a wagon of crown arms five years
   ago, after the border war. He now walks the Tithe carts up the ridge and keeps the Pit. **Commander
   Lucan Ferrow** has a warrant and a grudge, and still has uses for a man like Varn.
5. **The Grey Fever** that killed Elena's mother swept the Capitol twenty years ago, and it is back.
   **Sister Ysolde** of the Cathedral and **Brother Anselm** of Brackenmoor hold the records of the
   true cure: fever-root steeped with the white salt of Greystone's deep vein. Root alone only quiets
   the fever for a few days; root and salt break it for good. The Cathedral sells the salt as a mercy
   that can be bought, and it is reluctant to admit the fever has returned. It has never asked how
   fresh salt keeps coming out of a vein the crown's records call sealed.
6. **The crown's tithe** (the tax, not the Hollow's Tithe) from the Western Valley has been short for
   three years: the coin that should have gone east went up the forest path in the tribute chest. The
   Lord Protector needs it, and he needs a victory. He sends **Captain Renna Thorne** and her rangers
   west, while **High Magistrate Corwin Vane** asks why nobody ever reported the losses, or the
   children.
7. **Old Wren,** keeper of the Halfway House on the Kingsroad, was once the crown's best
   intelligencer. Every letter between the valley and the Capitol passes under her roof, and she
   reads them.
8. **Oskar,** the Ferrisford ferryman, takes the Hollow's barges across for a toll. His brother
   drowned refusing them.

## The Tithe and the wider world

The Pit's salt is the thread that ties a village lottery to the throne.

```
Thornhaven chapel ──lot──> Tithe cart ──ridge trail──> the Pit (chained diggers)
                                                           │ salt
                    Gregor <── one measure a year, name slip folded inside
                                                           │
                       far half of the ridge trail ──> Greystone's back road
                                                           │ sacks among the ore carts
                                    Kingsroad, past the Halfway House
                                                           │
                         Guildhall warehouses (Hollis, "the Hollow's factor")
                                                           │ forty times its worth
                       Cathedral infirmary's locked cabinet ──> Palace Hill
```

- **The diggers.** Corin Ashby, Willa Brand and the others dig in chains beyond Dagna's seal. Hesk
  Marlow died there; his name is cut into the seam wall. Davin walked out this summer. The Pit's tally
  book, salt and names together, is in Mira's own hand.
- **The road.** There is no direct road from Iron Hollow to Greystone. The ridge trail runs Iron
  Hollow, then the Pit (five hours), then down to Greystone's back road (five more). The Tithe carts
  walk the first half; the salt walks the second.
- **Greystone.** Dagna takes the smugglers' fee and pays the Hollow to leave the ore road alone. Her
  carters carry the Hollow's sacks east among the ore and are not paid to look inside. For five years
  she has heard picks through her seal below the seventh level and told herself it was water or
  scavengers. She has never gone to look.
- **The Guild.** Hollis buys the salt from "the Hollow's factor" and sells it to the Cathedral, as the
  Guild sold Lord Garrick Ashdown's salt in the Grey Year. He asks no questions. The day he learns who
  digs it, it becomes the entry in his patron ledger that could hang him.
- **The Cathedral.** The chapter rations the cure to the houses that can pay, as it did twenty years
  ago. Its mercy is dug by Thornhaven's stolen children. That is the shame at the heart of
  `grey_fever`.
- **The Crown.** Greystone is crown land leased to the Guild. Mathias's petitions begged the crown for
  help against a bandit who takes a child a year; Tobias Vane lost them. When the Lord Protector learns
  the Capitol's cure is slave-dug on his own land, he must choose: break the Pit and free the taken for
  his victory, or buy the Hollow quietly and keep the salt flowing. That choice is part of
  `regents_gambit`'s hinge.
- **Money and letters.** For the Tithe's first two autumns the council paid both the crown's tithe and
  the Hollow's coin; for the last three the crown's share went up the forest path in the cart's coin
  chest. Mira's monthly tallow letters to the Guild factor carry the Pit's reckoning, salt by weight and
  a count of hands one more each autumn, in the same neat hand as the tally book. When Greystone's ore
  road runs slow, a few double-wrapped white sacks cross on the Hollow's night barges at Ferrisford; the
  wire-tied bales there are plunder.
- **Lies ready to hand.** Hollis's fallback is that the Guild's salt is "old stock from the Grey Year".
  The crown's secret terms to the Hollow never mention the Tithe or the Pit, so a bought Hollow keeps
  taking a person a year. When the Hollow is struck, it falls back up the ridge to the Pit.
- **The other door.** The Pit's back-seam ends at the old fall below Greystone's seventh level.
  Breaking it from Greystone's side opens an unguarded second way in (`deep_vein`).
- **The land.** Seraphine's agent bought eleven freeholds over two autumns, mostly in the week after a
  drawing. The Ashbys sold after Corin, the Brands after Willa. Seraphine knows of "the valley's autumn
  drawing" only vaguely, and nothing of the Pit.
- **What freeing the Pit does.** If the taken come home (`tn_taken_freed`), the salt stops. The
  Cathedral's cabinet empties, the Guild loses its trade and the crown learns what was dug on its land.
  The Open Pit is the Thornhaven ending that the wider world feels most.

## New cast (key: soul summary)

| key | who | wants, in a line | secret |
|-----|-----|------------------|--------|
| edric | Lord Protector Edric Hale, 51 | Keep the regency until the boy comes of age, and keep himself indispensable after | He has considered making Iron Hollow his secret instrument, not his enemy; he does not know the Cathedral's cure is dug on his land |
| corwin | High Magistrate Corwin Vane, 63 | The law applied evenly, at last, before he dies | His own nephew clerks for Hollis Marrow and has been paid to lose papers |
| seraphine | Lady Seraphine Ashdown, 38 | Restore House Ashdown's fortunes by owning the valley outright | She funds the Hollow through Hollis; her late father's debts are to the Guild |
| hollis | Guildmaster Hollis Marrow, 57 | Profit, and a seat on the regency council | His warehouses launder the Hollow's plunder and buy the Pit's salt for the Cathedral; he keeps a ledger of every patron as insurance |
| ysolde | Sister Ysolde, 44 | Heal the sick, even against the Cathedral | She knows the Cathedral sells the Grey Fever cure to the rich and lets the poor die; she does not yet know who digs its salt |
| renna | Captain Renna Thorne, 33 | Prove the King's Rangers are more than the regent's dogs | She was born in Thornhaven and left; Mathias is her uncle |
| rook | Rook, ~17 | Get out of the Warrens alive and rich | Rook fences the Hollow's goods and knows the Hollow's buyer is "a lady on the hill" |
| wren | Old Wren, 70 | Peace, a fire, and one last game worth playing | She reads every letter. She has guessed the Boss is a woman in Thornhaven |
| oskar | Oskar the ferryman, 46 | Keep the crossing and his family; avenge his brother | He keeps a tally of every Hollow barge he has carried |
| dagna | Foreman Dagna Holt, 49 | Keep Greystone working and her miners fed | She pays the Hollow to leave the ore road alone, lets its salt ride east among her ore, and has heard picks through her seal for five years |
| lucan | Commander Lucan Ferrow, 55 | Restore Ashguard's honour and his own | Varn's desertion covered Lucan's own sale of crown arms; Varn could ruin him |
| anselm | Brother Anselm, 68 | Preserve the truth in the archive | Brackenmoor's records name the Ashdown family as profiting from the last fever |

These ten storylines open the map. Thornhaven's six storylines (the spine tithe_night, plus iron_hand,
elenas_fever, hollow_crown, council_of_ash and smiths_oath) remain the heart of the game. These ten carry their consequences outward
and bring the outside world's consequences back to Iron Hollow.

## The ten new storylines

Every storyline must **declare and set** its two exports. It must consume **at least two** flags
from the Thornhaven exports (including the spine's `tn_` exports) and **at least two** from the new exports, and **Iron Hollow
or its people must matter in it.**

| file | prefix | premise | centre NPCs | exports |
|------|--------|---------|-------------|---------|
| `crowns_tithe.json` | `tithe_` | The crown's tithe from the valley has been short for three years, because the coin went up the forest path with the Tithe cart. The Lord Protector sends Renna's rangers west: to restore order, to find a scapegoat, or to strike a quiet deal with whoever really runs the valley. Renna may find the Pit and write it into her report. | renna, edric, aldric, mathias, mira | `tithe_rangers_arrive`, `tithe_valley_pardoned` |
| `fence_of_highmarch.json` | `fence_` | Where do the Hollow's plunder and salt go? Follow them from Ferrisford barges and Greystone's ore carts to Hollis's warehouses and Rook's back rooms. Whoever holds the fence's ledger, with its salt page, holds half the Capitol. | hollis, rook, mira, varn, oskar | `fence_ledger_taken`, `fence_route_burned` |
| `ashdown_inheritance.json` | `inh_` | Lady Seraphine holds the deed to the valley and is buying it cheap with the Tithe's terror; the families of the taken sold first. Thornhaven's freeholders, the council and the Magistry each discover a different piece. | seraphine, mathias, corwin, gregor, hollis | `inh_deed_challenged`, `inh_valley_sold` |
| `grey_fever.json` | `grey_` | Elena's illness is the Grey Fever, held down five years by the Hollow's salt. The true cure needs that salt, the Cathedral rations it, and it is dug in the Pit by the Tithe's taken. Ysolde, Anselm and the archive's truth set the Church against its own mercy. | ysolde, anselm, elena, dagna, mathias | `grey_cure_recipe_known`, `grey_cathedral_shamed` |
| `deserters_road.json` | `des_` | Varn deserted Ashguard with crown arms. Commander Lucan wants him hanged, or silenced, or back in harness. Varn's past rides west in Tithe week, and Lucan's ridge patrols took their fee from the Tithe carts. | lucan, varn, renna, aldric, wren | `des_varn_warrant_served`, `des_lucan_disgraced` |
| `deep_vein.json` | `vein_` | Greystone's iron feeds Bjorn's forge and the Hollow's blades. Dagna's purse to the Hollow, the picks she hears through her seal, and the old fall that opens onto the Pit from Greystone's side put the valley's steel, and the taken, in play. | dagna, bjorn, varn, hollis, lucan | `vein_ore_road_closed`, `vein_miners_rise` |
| `ferrisford_toll.json` | `ford_` | The crossing where the Hollow's barges go east, with white sacks among them when the ore road runs slow. Oskar's toll, his drowned brother, his tally sticks, and the rangers who want them. | oskar, rook, renna, varn, mira | `ford_tally_given`, `ford_crossing_seized` |
| `magistrates_ledger.json` | `mag_` | Gregor's ledger of rigged draws could reach the Capitol. Corwin wants an open trial over the people sold into the Pit; the Lord Protector wants a quiet one, because the Pit is on crown land; Elena wants her father alive. | corwin, gregor, elena, edric, aldric | `mag_trial_called`, `mag_verdict_given` |
| `waystation_whispers.json` | `way_` | Every letter on the Kingsroad passes under Old Wren's roof: the Boss's tallow letters with the Pit's reckoning of salt and hands, Mathias's lost petitions against the Tithe, the regent's to his captain. Who reads, who forges, who burns. | wren, mira, seraphine, renna, rook | `way_letters_read`, `way_boss_named_in_capitol` |
| `regents_gambit.json` | `reg_` | The Act III hinge between valley and throne. The Lord Protector learns the Cathedral's cure is dug in chains on crown land, and must choose: crush Iron Hollow and open the seam for a victory, or make the Boss his secret instrument and keep the salt flowing. The great houses and the Magistry choose too. | edric, seraphine, corwin, mira, renna | `reg_crown_strikes_hollow`, `reg_crown_buys_hollow` |

## Tone

Grounded, morally grey, intimate. Big events are rumours until they arrive in your village. Capitol
people talk like people with a lot to lose, not like court-drama villains. Nobody is purely evil;
everybody is protecting something.

## Cast canon (decided in the souls; binding for storylines)

- **Petitions.** Mathias's petitions *did* reach the Capitol; Old Wren read and resealed them. Every
  autumn for five years they begged the crown for help against the Tithe, and named each one taken. Corwin's
  nephew **Tobias Vane**, a Magistry registry clerk who also keeps books for Hollis, was paid to lose
  them, along with the tithe reeve's loss reports (`writ_archive_gap_found`). Renna never knew her
  uncle wrote. Piet's widow sent an unsigned complaint to the Magistry; it is the thread Corwin is
  pulling. Corwin's lungs are failing (two winters left), which is why he is in a hurry.
- **Ashdown and the salt.** Seraphine's late father, **Lord Garrick Ashdown**, held the Greystone salt
  charter in the Grey Year; the Cathedral bought the salt through the Guild at forty times its worth,
  then endowed Brackenmoor to "keep its counsel". Anselm holds copies, and a hidden second set.
  Seraphine doesn't know. Greystone is crown land leased to the Guild; Hollis holds Garrick's debt
  notes. Seraphine's land agent has already bought 11 freeholds. She writes west via the Halfway House
  under plain wax.
- **Lucan and Varn.** Lucan sold three wagons of crown arms through the Guild (Hollis) to pay his
  unpaid garrison. When Varn deserted with a fourth, Lucan reported all four stolen. Varn saw the
  first three go. The warrant is worded so that "killed resisting" satisfies it. Lucan's patrols take
  fees on the ridge trail. Every autumn they took the Hollow's fee and waved through a covered cart;
  Lucan never asked what was under the canvas (`des_ridge_fees_known`). Lucan served with Aldric, who carried him off the field at Harrow Ridge.
- **The throne.** The late king was **Ostric**, Edric's elder brother. Edric retired Wren for fear she
  knew how Ostric died (it was in fact an honest wound). Edric gave Renna sealed instructions to open
  if she finds "whoever really governs the valley"; she hasn't opened them. Edric and Hollis both
  assume the Boss is a man.
- **Renna** is the daughter of Mathias's sister. She left Thornhaven at 16, seventeen years ago; Wren
  fed her the night she ran.
- **Wren's clue to the Boss:** monthly letters in a woman's hand, sealed with tavern tallow and
  smelling of smoke, to a Guild factor.
- **Rook** is a girl, about 17, real name unspoken. She saw an Ashdown-grey footman collect a parcel at
  the Guild's back door. Her crew includes **Pip**, 9, possibly Oskar's missing nephew. Oskar's drowned
  brother is **Piet**; his rope was cut, and Oskar believes Varn ordered it.
- **Dagna's** husband **Bram** died when the deep vein fell six years ago; she sealed it and keeps a
  lump of the salt. The Hollow later broke into the vein's back-seam from the ridge side: that is the
  Pit, and the picks Dagna hears through her seal are the Tithe's taken. **Ysolde** has one patient's
  worth of the salt sewn into her habit, old salt saved from the wards twenty years ago.
- **Bjorn's maker's mark** is a hammer over a pine tree (scenes and soul agree).
- **Thornhaven canon the wider world must respect** (from `STORY_NARRATIVE.md`, which wins):
  - Gregor's ledger (`ledger_found`) is five years of rigged draws: the year, the tile palmed, the name
    it fell to, beside his deliveries to the Hollow. It is not a book of payments to bandits. His deal
    is the lot and the salt; his supplies and Bjorn's steel are the salt's other price.
  - Each year's name came to Gregor folded in the salt packet from Mira, "the messenger". In Year 3 the
    slip said only *choose*, and Gregor chose Hesk Marlow.
  - The taken: Corin Ashby (alive, leads the diggers), Davin (escaped this summer, hiding at Old Maud's),
    Hesk Marlow (died in the Pit), Willa Brand (alive), and this year Elena, in Ada Fenn's place.
  - Elena's fever is not a hidden secret quieted by root: root only quiets it for days; the Hollow's
    salt has kept her alive for five years, and a full measure with fresh root would cure her.
  - Collection Night is day 7 at 22:00. The wider world hears of it as rumour, a day or more late.
