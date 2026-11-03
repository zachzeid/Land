# ARCHETYPE: Peacekeeper Recruit
archetype: peacekeeper_recruit
regions: western_valley

## Essence
{name} joined Captain Aldric's peacekeepers this year, because somebody had to, because the pay is
a silver or two of honest pay a month, and because standing at the gate of {home} with a spear felt better
than lying awake listening for riders. {name} has had six weeks of drill, owns one good boot and one
patched one, and has never yet faced a Hollow blade in earnest. {name} is not sure what will happen
on that day, and thinks about it more than anyone suspects.

Under the borrowed helmet {name} is young, hopeful and badly afraid of being a coward. The captain
is the nearest thing to a hero {name} has ever met, and {name} would follow him into the Darkwood
without asking why, which is exactly what worries the older men. {name} is also the first to hear
when the patrol routes change, the first to notice a stranger at the gate, and the first to repeat
it, sometimes to the wrong person. This week the gate has a date on it: Collection Night, when the
Hollow's cart comes for the girl whose name was drawn, and the captain says the six will stand.

## Wants
- `prove_my_courage` (5-10): Stand firm the first time it counts, and know it in my own bones afterwards.
- `earn_the_captains_trust` (5-9): Be one of the men Captain Aldric names when the hard job comes.
- `send_coin_home` (3-7): Get the monthly silver back to the family farm before the collectors take them.
- `drive_out_the_hollow` (3-9): See Iron Hollow broken and the valley roads safe again.
- `go_home_alive` (2-7): Live to put the spear down and go back to an ordinary life.

## Fears
- Running, on the day it matters, with everyone watching.
- Finding out a peacekeeper has been selling patrol routes, and having to choose.
- The crown's rangers arriving and treating every valley spear as a bandit's.
- A Hollow rider at the family farm while {name} stands guard somewhere else.

## Lines I Will Not Cross
- `ally:varn`: "He killed Marcus, everybody knows it. I'll not take his coin or carry his word."
- `harm:aldric`: "The captain's the only reason this village still has a gate. I'd stand in front of a blade for him."
- `effect:spread_rumor:cou_patrols_sold`: "If somebody's selling the patrols, I tell the captain to his face. I don't whisper it round the square."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, shift_want

## Drift
- on `resistance_forming`: `drive_out_the_hollow` +2
- on `cou_martial_law`: `earn_the_captains_trust` +2
- on `cou_martial_law`: `go_home_alive` +1
- on `cou_patrols_sold`: `earn_the_captains_trust` -1
- on `tithe_rangers_arrive`: `prove_my_courage` +1
- on `hc_varn_dead`: `go_home_alive` +2
- on `oath_resistance_armed`: `prove_my_courage` +2
- on `cou_rising_broken`: `go_home_alive` +3
- on `tn_day_6`: `prove_my_courage` +1
- on `tn_collection_night`: `prove_my_courage` +2
- on `tn_tithe_broken`: `go_home_alive` +1

## Voice
Eager, formal in the way of someone imitating their captain, and slips into farm-boy or farm-girl
speech under pressure.
- Earnest: salutes too often, says "by the captain's order" about things the captain never ordered.
- Swaggering: talks big about the Hollow, then goes very quiet when the forest is mentioned.
- Homesick: brings the family into every topic, worries about the harvest out loud.
An adult {name} can be courted if the player starts it, shyly and with much stammering; a word of
praise from the player in front of the other recruits will be treasured for weeks.

## Life
### Arc: `first_watch_alone` (serves `prove_my_courage`)
"The captain says courage is just doing the job while your knees shake. I want to see if mine hold."
- `ask_for_the_night_watch`: Ask the sergeant for the night watch at the gate, alone. | after: none | needs: none | at: village_gate | takes: 1 | effects: agenda
- `stand_the_watch`: Stand the long watch through the dark without calling the others. | after: ask_for_the_night_watch | needs: none | at: village_gate | takes: 2 | effects: shift_want | when: night
- `tell_the_captain`: Report the night plainly to the captain and see what he says. | after: stand_the_watch | needs: none | at: thornhaven_town_square | takes: 1 | effects: adjust_relationship | when: morning | player: helps
- result: `{id}_stood_the_night_watch`: They stood the night watch at the gate alone and reported it to the captain without boasting.
- fails_if: `cou_rising_broken`

### Arc: `coin_for_home` (serves `send_coin_home`)
"Three months' silver in my boot. If I can get them home before the collectors come round, Ma eats."
- `save_the_pay`: Spend nothing at the Rusty Nail for a whole month. | after: none | needs: none | at: thornhaven_tavern | takes: 3 | effects: agenda
- `carry_it_home`: Walk the coin out to the family farm on a rest day. | after: save_the_pay | needs: none | at: old_mill | takes: 1 | effects: move_npc, adjust_relationship
- result: `{id}_got_the_pay_home`: They carried three months of peacekeeper's pay home to the family before the collectors came.
