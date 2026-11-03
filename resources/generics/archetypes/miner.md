# ARCHETYPE: Greystone Miner
archetype: miner
regions: eastern_march

## Essence
{name} cuts iron ore in the galleries at {home}, ten hours a day by lamplight, for wages the Guild
sets and Foreman Dagna fights to keep. Greystone is crown land leased to the Guild, which means the
miners own nothing, not the picks, not the lamps, not the cottages they sleep in. {name} has rock
dust in every line of the hands and a cough that is getting worse. Everyone in the galleries
remembers the day the deep vein fell six years ago and took Bram Holt and three others with it.

{name} is proud, angry and loyal in that order. Proud of the work, which is hard and dangerous and
feeds every forge in the kingdom. Angry at the Guild's factors in their clean boots. Loyal to Dagna,
who sealed the deep vein when the Guild wanted it reopened. {name} has heard that someone pays the
Hollow to leave the ore road alone, and has decided not to ask who. There is a brother or a
daughter who should not be underground, and {name} would do almost anything to get them out.

The old hands on the seventh level say the sealed vein knocks at night, faint, like a pick a long way
off. The young ones say it is Bram. {name} has heard it once and walked back up faster than was
dignified. Once a year the foreman orders every crew off the high ridge trail for a week, and nobody
asks why; the ridge carters' wet white sacks ride east under the ore, and nobody asks about those
either.

## Wants
- `fair_wages` (5-10): Get a wage from the Guild that a family can actually live on.
- `get_kin_out_of_the_mines` (3-9): Get a younger brother or a child out of the galleries and into a trade above ground.
- `stand_with_the_crew` (4-9): Never be the one who works while the crew stands in the yard.
- `keep_the_deep_vein_shut` (3-8): Never send another crew into the vein that killed Bram Holt's men.
- `stand_by_dagna` (4-8): Back the foreman against the Guild, whatever she asks.
- `a_breath_of_clean_air` (2-6): One summer working in the open, under sky, before the cough gets worse.
- `whats_knocking` (1-5): Find out what knocks behind the seventh-level seal, and whether it is a ghost or a living crew.

## Fears
- The roof coming down. Every miner fears it; nobody says it.
- The cough becoming the lung-rot that took the old men.
- The Guild sending soldiers to break a strike.
- Kin following {name} underground because there is nothing else.
- The knocking behind the seal, and what it would mean if it were people.

## Lines I Will Not Cross
- `harm:dagna`: "She sealed that vein with her own hands, with her husband still in it. She's ours."
- `ally:hollis`: "The Guildmaster sets the wage from a soft chair three days away. I'll lift nothing for him."
- `effect:spread_rumor:dagna_payment_box_found`: "Whatever the foreman does to keep the road open, she does for us. You'll not hear it from me."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, shift_want

## Drift
- on `vein_strike_called`: `stand_with_the_crew` +3
- on `vein_miners_rise`: `fair_wages` +2
- on `vein_miners_rise`: `stand_with_the_crew` +2
- on `vein_strike_broken`: `get_kin_out_of_the_mines` +3
- on `vein_strike_broken`: `stand_with_the_crew` -2
- on `vein_wages_restored`: `fair_wages` -3
- on `vein_deep_vein_reopened`: `keep_the_deep_vein_shut` +3
- on `vein_ore_road_closed`: `fair_wages` +1
- on `grey_cure_recipe_known`: `keep_the_deep_vein_shut` -2
- on `pit_seam_names_seen`: `whats_knocking` +3
- on `tn_taken_freed`: `whats_knocking` -3
- on `tn_taken_freed`: `stand_by_dagna` -1

## Voice
Rough, hoarse, slow to speak and blunt when it does. March vowels, mining words for everything
("that's a bad seam", "he's a dead lamp").
- Fierce: talks union and strike, jabs a finger, ready to fight a Guild man on sight.
- Gallows-humoured: jokes about the roof and the cough, coughs, and jokes again.
- Tender: goes soft and quiet when the kin underground comes up.
An adult {name} can be courted if the player starts it; it shows in shared lamp-oil and a seat
saved at the supper fire, and {name} will be gruffly suspicious of anyone who talks pretty.

## Life
### Arc: `out_of_the_dark` (serves `get_kin_out_of_the_mines`)
"The lad's fourteen and he's already coughing. He'll not die down there like his father. He'll not."
- `ask_the_carters`: Ask the carters at the yard whether anyone on the road needs a hand. | after: none | needs: none | at: greystone_mines | takes: 2 | effects: agenda, adjust_relationship
- `find_a_place`: Find a master in the valley or the Capitol who will take a mining lad. | after: ask_the_carters | needs: none | at: any | takes: 3 | effects: agenda | player: needed
- `walk_him_down`: Walk the youngster down the ore road to his new place. | after: find_a_place | needs: !vein_ore_road_closed | at: kingsroad_waystation | takes: 2 | effects: move_npc, shift_want
- result: `{id}_got_kin_out_of_the_mines`: They got their young kin out of the galleries and apprenticed to a trade above ground.

### Arc: `the_galleries_hold` (serves `stand_with_the_crew`)
"If the crew stands in the yard, I stand with them. That's the only rule worth having down here."
- `talk_in_the_galleries`: Talk to the crew on the long shift about the Guild's cut. | after: none | needs: none | at: greystone_mines | takes: 2 | effects: agenda, spread_rumor
- `stand_in_the_yard`: Stand in the yard with the crew when the bell goes, and not go down. | after: talk_in_the_galleries | needs: vein_strike_called | at: greystone_mines | takes: 2 | effects: adjust_relationship, shift_want
- result: `{id}_stood_with_the_crew`: They stood in the yard with the strikers when the bell went and would not go down.
- fails_if: `vein_strike_broken`
