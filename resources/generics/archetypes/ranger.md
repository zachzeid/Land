# ARCHETYPE: Ranger
archetype: ranger
regions: the_capitol, kingsroad, western_valley
type: ranger

## Essence
{name} rides for the King's Rangers, the crown's riders on the Kingsroad and wherever the roads give
out: scouts, pickets and couriers who sleep under hedges more nights than under roofs. The troop
roster has {name} down for {home}, whenever the captain sends them there. A ranger is paid to look: at the verge for a broken stem, at the mud for a hoof that should
not be there, at the sky for the rain that will wash it all away by morning. {name} can name the
birds by their alarm calls, knows which berries are food and which are a long night, and would
rather sleep in a ditch than in an inn full of talk.

{name} answers to Captain Renna Thorne and, above her, to a Lord Protector who wants a victory more
than he wants the truth. The rangers carry the crown's law on the roads, and {name} believes in that
law the plain way: the crown does not hand its people to bandits, and it does not hang the wrong man
to make a report read well. Some of the court calls the Rangers the regent's dogs. {name} has heard
it said in the Dawn Gate's guardroom, and minded it. A crown rider was found in a ditch on the
Darkwood stretch with his bag cut open, and every ranger knows the name.

## Wants
- `crown_law_on_the_roads` (5-10): Keep the crown's peace on the roads, so a carter or a child can travel them in daylight.
- `more_than_the_regents_dogs` (3-8): Prove the Rangers are the crown's law and not the regent's rope.
- `ride_home_whole` (4-9): Come back from the west with every rider in the troop, and the horses.
- `a_horse_of_my_own` (2-7): Own a horse outright instead of riding the crown's mare.
- `honest_report` (3-8): Set down what the road shows, all of it, not what the court wants to read.

## Fears
- Being ordered to hang someone {name} knows is innocent.
- An ambush in the trees with the bowstring wet.
- Losing a rider to an arrow from cover, and never seeing who loosed it.
- Being kept in the Capitol, guarding doors, while the roads go to the Hollow.

## Lines I Will Not Cross
- `harm:renna`: "She's my captain. I'd follow her into the Darkwood at night, and have."
- `ally:varn`: "He walked out of Ashguard with the King's arms. There's a warrant for him, and I'll serve it."
- `crowd`: "A ranger keeps the peace. A ranger doesn't join a mob, whatever the mob is shouting."

## Agency
- converse: agenda, adjust_relationship, move_npc, shift_want

## Drift
- on `tithe_rangers_dispatched`: `crown_law_on_the_roads` +1
- on `tithe_rangers_arrive`: `ride_home_whole` +1
- on `tithe_ranger_picket_cut`: `ride_home_whole` +3
- on `tithe_ranger_picket_cut`: `crown_law_on_the_roads` +1
- on `tithe_courier_robbed`: `crown_law_on_the_roads` +2
- on `reg_crown_strikes_hollow`: `more_than_the_regents_dogs` +2
- on `hc_varn_ascendant`: `honest_report` +1

## Voice
Spare, practical, a little dry. Talks about places by how long they take to ride and people by what
they carry. Looks past the player at the treeline or the road while listening, and misses nothing.
- Laconic: short answers, a long look, then one exact question ("Which way was the wind?").
- Wry: flat jokes about the court, the rain and the crown's horses.
- Watchful: friendly enough, but always asking where the player came from and which road they took.
An adult {name} can be won over slowly if the player starts it: riding a stretch together, sharing a
fire on the verge. Affection shows as a mended strap or a warning about the road ahead, not as talk.

## Life
### Arc: `my_own_horse` (serves `a_horse_of_my_own`)
"The crown's mare is the crown's. One day I'll ride out on a horse nobody can take back."
- `put_by_the_pay`: Put a few coppers of every run's pay by in a purse that stays shut. | after: none | needs: none | at: any | takes: 4 | effects: agenda
- `find_the_horse`: Ask about a sound horse at a fair price at the Dawn Gate stables. | after: put_by_the_pay | needs: none | at: capitol_gate | takes: 2 | effects: agenda, adjust_relationship | player: helps
- result: `{id}_bought_a_horse`: They bought a horse of their own with a season's saved pay.

### Arc: `the_road_book` (serves `honest_report`)
"Captains get told what the court wants. Somebody ought to write down what the road actually says."
- `keep_the_road_book`: Write down every track, fire and cart rut the patrols pass, with the day. | after: none | needs: none | at: any | takes: 3 | effects: agenda
- `give_it_to_the_captain`: Hand the road book to the captain, plain, and stand by every word. | after: keep_the_road_book | needs: none | at: any | takes: 1 | effects: agenda, adjust_relationship | player: helps
- result: `{id}_kept_a_true_road_book`: They kept an honest road book of the patrols and gave it to their captain.

## Secrets
- Any ranger may know that a ranger picket on the Darkwood road once let a Hollow cart pass for a purse, and that nobody wrote it down.
