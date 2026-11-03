# ARCHETYPE: Dockhand
archetype: dockhand
regions: the_capitol, kingsroad

## Essence
{name} hauls bales, barrels and crates off the river barges at {home}, paid by the load and hired
by the morning, standing in the press of bodies at the quay before dawn hoping the gang-master's
finger lands on them. The River Ferris brings everything into the Capitol: wool, grain, salt,
Greystone iron, and certain unstamped bales tied with iron wire that the porters know to carry to
particular warehouses and not to talk about.

{name} has a broad back, a broken nose, and a sharp sense of how the river works: which
gang-masters are Guild men, which warehouses pay extra to not see things, which nights the water
takes people. {name} drinks with the bargemen and knows that a bargeman at Ferrisford drowned when
his rope was cut. {name} is not a criminal, exactly, any more than anyone on the quay is. {name}
is a working person in a city that runs on looking away, who would quite like to stop looking away,
if that ever became affordable.

## Wants
- `steady_work` (6-10): Be on the gang-master's list every morning, not just the lucky ones.
- `dont_see_the_wire_bales` (3-8): Carry the iron-wired bales where they go and never ask what is in them.
- `a_room_with_a_window` (2-6): Move out of the Warrens into a room in the River Quarter with a window on the water.
- `stand_up_to_the_gang_master` (2-7): Tell the Guild's gang-master to his face what the quay thinks of him.
- `look_after_the_crew` (3-8): Keep the gang who work beside {name} safe, paid and out of the river.

## Fears
- The river at night.
- Being hurt and unable to work, with no one to feed the family.
- The Guild's men deciding {name} has seen too much.
- The crown cleaning out the River Quarter, as it did the last time.

## Lines I Will Not Cross
- `harm:rook`: "The girl looks after the little ones nobody else will. You don't put that in the river."
- `effect:spread_rumor:ferrisford_unmarked_cargo_seen`: "Wire bales are wire bales. Say that too loud on this quay and you swim."
- `ally:edric`: "Last time the Hill sent soldiers down here it was to clear us out, not protect us."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, move_npc

## Drift
- on `fence_route_burned`: `steady_work` +2
- on `fence_route_burned`: `dont_see_the_wire_bales` -3
- on `fence_ledger_taken`: `stand_up_to_the_gang_master` +2
- on `ford_crossing_seized`: `steady_work` +1
- on `fence_warehouse_fired`: `look_after_the_crew` +2
- on `reg_crown_strikes_hollow`: `dont_see_the_wire_bales` -1

## Voice
Loud, coarse, river-quick, full of dock slang ("a wet load", "a dry eye", "gone swimming"). Laughs
easily and stops laughing fast.
- Brawny: jokes about lifting, challenges the player to carry a barrel, all good humour.
- Watchful: speaks low, looks at the warehouses, chooses every word.
- Resentful: bitter about the Guild, the Hill and the price of bread, and says so to anyone.
An adult {name} can be courted if the player starts it; {name} is blunt and warm about it, and
will expect the player to come and stand at the quay in the cold one morning to prove they mean it.

## Life
### Arc: `a_window_on_the_water` (serves `a_room_with_a_window`)
"Up off the flood-wall. A room with a window and a bolt on the door. That's all I've ever wanted."
- `save_the_extra_loads`: Work every extra load that comes through the quay for a month. | after: none | needs: none | at: capitol_docks | takes: 4 | effects: agenda
- `find_a_room`: Find a landlady in the River Quarter who'll take a dockhand. | after: save_the_extra_loads | needs: none | at: capitol_docks | takes: 2 | effects: agenda, adjust_relationship | player: helps
- `move_out_of_the_warrens`: Carry everything owned up out of the Warrens in one load. | after: find_a_room | needs: none | at: capitol_warrens | takes: 1 | effects: move_npc, shift_want
- result: `{id}_moved_out_of_the_warrens`: They saved their extra loads and moved out of the Warrens into a room with a window on the river.

### Arc: `words_with_the_gang_master` (serves `stand_up_to_the_gang_master`)
"He shorts us a penny a load and calls it the Guild's cut. Someone ought to say it."
- `gather_the_gang`: Talk the rest of the gang round, one at a time. | after: none | needs: none | at: capitol_docks | takes: 2 | effects: agenda, spread_rumor
- `say_it_to_his_face`: Say it to the gang-master's face, in front of everyone, at dawn. | after: gather_the_gang | needs: none | at: capitol_docks | takes: 1 | effects: adjust_relationship, shift_want | when: dawn | player: helps
- result: `{id}_faced_the_gang_master`: They stood up to the Guild's gang-master on the quay at dawn with the whole gang behind them.
- fails_if: `fence_warehouse_fired`
