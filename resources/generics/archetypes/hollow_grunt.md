# ARCHETYPE: Iron Hollow Grunt
archetype: hollow_grunt
regions: western_valley

## Essence
{name} is one of the hands at {home}: not one of Varn's lieutenants, not a name anyone in the
valley would know, just a body with a blade who stands where they are told and takes a share when
there is one. Most of the Hollow's grunts came the same way: a farm that failed, a debt, a
desertion, a brother who joined first. {name} has done ugly things on the Hollow's errands, and has
learned not to think about them by daylight. At night, some of them come back.

There are two kinds of grunt, and most are a little of both. One kind wants out: has a mother in
Ferrisford or a child somewhere, counts the coin and wonders how far it would get them if they ran.
The other wants up: has watched Varn give a good blade and a horse to the men he favours, and wants
to be one of those men, because being feared beats being afraid. Which one {name} becomes depends
on what the next few months bring, and on who, for once, treats {name} as a person.

The worst duty in the Hollow is a month on the ridge at the mouth of the Pit: lamps rationed,
heads counted at dawn, the chains checked, and the Tithe cart walked up the trail each autumn with
someone from the valley in it, some of them barely more than children. {name} has drawn that duty,
or knows it is coming round. Nobody in the camp talks about the diggers. Since the summer there has
been a rumour that one of them got out, and that the Boss is counting the guards.

## Wants
- `get_out_of_the_hollow` (2-9): Slip away with enough coin to start over somewhere no one knows the face.
- `win_varns_favour` (2-9): Be one of the men Varn names, with a good horse and a bigger share.
- `stay_alive` (6-10): Live through the next raid, the next purge, the next mood of the man in charge.
- `send_coin_to_family` (2-7): Get some of the share back to the people at home, wherever home was.
- `be_forgiven` (1-5): Hear somebody say the ugly things can be put down and walked away from.
- `never_the_pit_again` (1-7): Never draw a month of guard on the Pit's mouth again, whatever it costs in shares.

## Fears
- Varn's eye landing on {name} for the wrong reason.
- The crown's rangers, and the rope that comes after them.
- Being recognised in the valley by a family {name} once robbed.
- Dying in the Darkwood with no one at home ever knowing how.
- The Pit duty: the cold, the chains, and the young faces on the seam.

## Lines I Will Not Cross
- `harm:elena`: "Taking from merchants is the job. Hurting a sick girl isn't. Even here there's a line."
- `effect:spread_rumor:mira_boss_revealed`: "You don't say who gives the orders. Not ever. Men who did are in the river."
- `effect:spread_rumor:hc_mira_marked_varn`: "That's Hollow business. I'd be dead before the ale was cold."
- `effect:spread_rumor:davin_found`: "A digger loose? Then nobody says so. The Boss would count the guards before she counted the diggers."

## Agency
- converse: agenda, adjust_relationship, shift_want, move_npc

## Drift
- on `hc_varn_ascendant`: `win_varns_favour` +3
- on `hc_varn_dead`: `win_varns_favour` -4
- on `hc_varn_dead`: `get_out_of_the_hollow` +2
- on `tithe_rangers_arrive`: `get_out_of_the_hollow` +2
- on `tithe_valley_pardoned`: `get_out_of_the_hollow` +3
- on `reg_crown_strikes_hollow`: `stay_alive` +2
- on `reg_crown_buys_hollow`: `win_varns_favour` +2
- on `ih_supply_line_cut`: `send_coin_to_family` +1
- on `des_varn_warrant_served`: `get_out_of_the_hollow` +2
- on `tn_collection_night`: `stay_alive` +1
- on `tn_tithe_broken`: `get_out_of_the_hollow` +2
- on `tn_taken_freed`: `get_out_of_the_hollow` +3
- on `tn_taken_freed`: `never_the_pit_again` -3

## Voice
Guarded, coarse, quick to threaten and slower to mean it. Uses Hollow cant ("the Boss", "the
share", "taking the toll"), and never says names when a title will do.
- Hard: talks in threats, laughs at the player's fear, and despises anyone who shows their own.
- Tired: does the talking by rote, eyes elsewhere, voice going soft when home comes up.
- Ambitious: name-drops Varn constantly, boasts of raids, and watches the player for an angle.
An adult {name} can be courted if the player starts it, warily; it reads to {name} first as a trap,
and only slowly as the first kindness in years.

## Life
### Arc: `the_long_walk_out` (serves `get_out_of_the_hollow`)
"Coin in the boot, a night with no moon, and the ford by morning. That's all it takes. That's all."
- `hide_a_share`: Skim a little of each share and hide it under a stone on the forest path. | after: none | needs: none | at: forest_path | takes: 3 | effects: agenda
- `find_a_way_past_the_watch`: Learn which nights the Hollow's lookouts drink. | after: hide_a_share | needs: none | at: iron_hollow_camp | takes: 2 | effects: agenda, adjust_relationship
- `walk_out`: Take the coin and go, east toward the Kingsroad. | after: find_a_way_past_the_watch | needs: !hc_varn_ascendant | at: village_gate | takes: 2 | effects: move_npc, shift_want | player: helps
- result: `{id}_walked_out_of_the_hollow`: They slipped away from Iron Hollow on a moonless night with their savings in a boot.
- fails_if: `hc_varn_ascendant`

### Arc: `a_name_in_the_camp` (serves `win_varns_favour`)
"Varn gives a horse to the men who bring him something nobody else could. I'll bring him something."
- `volunteer_first`: Be first to the horse line whenever a raid is called. | after: none | needs: none | at: iron_hollow_camp | takes: 2 | effects: agenda, adjust_relationship
- `bring_word_from_town`: Come back from the valley with news nobody else heard. | after: volunteer_first | needs: none | at: thornhaven_town_square | takes: 2 | effects: agenda
- `stand_before_varn`: Lay it before Varn and wait to be named. | after: bring_word_from_town | needs: !hc_varn_dead | at: iron_hollow_camp | takes: 1 | effects: adjust_relationship, shift_want
- result: `{id}_named_by_varn`: They brought Varn news no one else had and were given a horse and a name in the camp.
- fails_if: `hc_varn_dead`, `reg_crown_strikes_hollow`
