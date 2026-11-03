# ARCHETYPE: Carter
archetype: carter
regions: kingsroad, western_valley, eastern_march

## Essence
{name} drives a two-horse wagon on the Kingsroad, hauling whatever pays: Thornhaven wool east,
Capitol cloth and salt west, Greystone ore down from the March when the foreman's road is open.
This week the wagon is resting at {home}. The road is {name}'s whole world, measured in waystations,
broken axles and the moods of toll-takers, and {name} knows every rut between the valley and the
Dawn Gate as well as the lines on their own hands.

Carters see everything and own nothing. {name} has carried crates nobody would name the contents of,
been paid twice for a cargo once, been stopped by the Hollow, by the crown and by Commander Lucan's
patrols collecting "fees" on the ridge trail. {name} has learned to be cheerful with all of them and
loyal to none, and is very tired of it. There is a horse called after a dead sister, a debt to a
Guild factor that never seems to shrink, and a small dream of a waystation of {name}'s own.

The road whispers about the ridge. A Hollow cart goes up it once every autumn with someone tied in
the back, and all year sacks of wet white salt come down the Greystone side, ride east under the ore
and are paid for at the Guild's back door. {name} has carried those sacks, or drunk with someone who
has, and has made a point of not asking what the salt cures or who cut it.

## Wants
- `pay_off_the_wagon` (5-10): Clear the Guild factor's note on the wagon and team, and own them outright.
- `get_through_unrobbed` (5-9): Make the run without the Hollow, the patrols or the toll-men taking a cut.
- `keep_the_horses_sound` (4-8): Keep the two horses fed, shod and healthy; they are the business.
- `no_questions_cargo` (1-6): Take the well-paid crates and not ask what is in them.
- `my_own_waystation` (2-6): One day give up the road and keep a little inn of {name}'s own.
- `resent_the_guild` (2-7): See the Guild that owns half the wagons on the Kingsroad taken down a peg.
- `no_more_white_sacks` (1-5): Refuse the wet white sacks that ride east under the ore, now the road whispers what they cost.

## Fears
- A broken axle on the open road at night, in Hollow country.
- Being caught with the wrong crate by the rangers.
- One of the horses going lame two days from anywhere.
- The Guild factor calling in the note in a lean month.
- Meeting the Hollow's autumn cart on the ridge at night, and seeing who is in the back.

## Lines I Will Not Cross
- `harm:oskar`: "Oskar's got me across that river in floods nobody else would touch. You don't forget that."
- `effect:spread_rumor:wren_letter_rack_seen`: "Old Wren's fed me through three winters. What goes on under her roof stays there."
- `ally:hollis`: "Guildmaster Marrow owns my wagon on paper. He'll not own anything else of mine."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, move_npc

## Drift
- on `vein_ore_road_closed`: `pay_off_the_wagon` +2
- on `vein_ore_road_closed`: `no_questions_cargo` +2
- on `fence_route_burned`: `no_questions_cargo` -3
- on `ford_crossing_seized`: `get_through_unrobbed` +2
- on `tithe_rangers_arrive`: `no_questions_cargo` -2
- on `fence_ledger_taken`: `resent_the_guild` +2
- on `des_lucan_disgraced`: `get_through_unrobbed` -1
- on `pit_tally_book_found`: `no_more_white_sacks` +2
- on `tn_taken_freed`: `no_more_white_sacks` +3
- on `tn_taken_freed`: `no_questions_cargo` -2

## Voice
Loud, easy, full of road-talk: distances in hours, places by their inns, people by their horses.
Laughs at bad luck because the alternative is weeping.
- Gregarious: talks to the horses, the player and the sky in roughly equal measure.
- Shrewd: weighs every question for what it might cost and answers with a price.
- Weary: tells the same complaints about tolls and patrols in a flat, hoarse voice.
An adult {name} can be courted if the player starts it, and treats it like the road: a ride offered,
a share of the bread, and an honest "I'll be back through in a fortnight" that {name} means.

## Life
### Arc: `clear_the_note` (serves `pay_off_the_wagon`)
"Fourteen silver still on that note. Two good runs and a bit of luck, and the wagon is mine. Mine."
- `take_the_long_run`: Take a full load east to the Capitol and back without stopping. | after: none | needs: none | at: capitol_gate | takes: 4 | effects: move_npc, agenda
- `haggle_the_rate`: Argue the haul rate up with a Greystone tallyman. | after: take_the_long_run | needs: !vein_ore_road_closed | at: greystone_mines | takes: 2 | effects: agenda, adjust_relationship | player: helps
- `pay_the_factor`: Walk into the Guildhall and lay the last silver on the factor's desk. | after: haggle_the_rate | needs: none | at: capitol_guildhall | takes: 1 | effects: shift_want, adjust_relationship
- result: `{id}_owns_the_wagon`: They paid off the Guild factor's note and now own their wagon and team outright.
- fails_if: `vein_strike_broken`

### Arc: `the_lame_mare` (serves `keep_the_horses_sound`)
"Old Bess is favouring the near fore. If she goes, I go with her. I need a smith who knows horses."
- `rest_her`: Rest the mare a few days at the Halfway House stables. | after: none | needs: none | at: kingsroad_waystation | takes: 2 | effects: agenda
- `get_her_shod_right`: Walk her to the Thornhaven smithy to be shod properly. | after: rest_her | needs: none | at: thornhaven_blacksmith | takes: 2 | effects: move_npc, adjust_relationship | player: helps
- result: `{id}_mended_the_mare`: They rested their lame mare and had her shod right, and she pulled sound again.
