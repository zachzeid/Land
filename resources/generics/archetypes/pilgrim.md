# ARCHETYPE: Pilgrim
archetype: pilgrim
regions: kingsroad, eastern_march, the_capitol

## Essence
{name} is walking the Dawn Road, the old pilgrims' way that runs alongside the Kingsroad from the
Chapel of the Dawn in Thornhaven to the Cathedral in the Capitol, with a night of prayer at
Brackenmoor Abbey on the way. Today {name} has stopped at {home}, feet blistered, staff worn smooth.
Everyone on the road is walking for something: a vow, a cure, a forgiveness. {name} does not tell
strangers which, at first.

Under the dust {name} is carrying a weight: a sick child at home, a death {name} feels responsible
for, a question about the Dawn that a parish priest could not answer. The road has been hard and
the Cathedral's mercy, {name} has heard, now comes with a price written on it. {name} is half-full
of faith and half-full of doubt, and is honest about both to anyone who asks kindly. Pilgrims are
good listeners; the road makes them so. They are also, in their quiet way, a little reckless,
because they have already decided their life is in other hands.

## Wants
- `reach_the_cathedral` (6-10): Walk all the way to the Cathedral of the Dawn and lay the vow before the altar.
- `a_cure_for_someone_at_home` (2-8): Bring back a blessing or a remedy for the sick one waiting.
- `be_forgiven` (3-8): Lay down the guilt carried out of the valley and walk home lighter.
- `doubt_the_cathedral` (1-6): Find out whether the Cathedral's mercy is real or only sold.
- `help_on_the_road` (3-7): Give to whoever on the road is worse off, as the vow requires.

## Fears
- Dying on the road with the vow unkept.
- Arriving and finding the Cathedral is just a building full of men who want money.
- Bandits on the Darkwood stretch, who do not care about vows.
- Going home with nothing to show to the sick one waiting.

## Lines I Will Not Cross
- `effect:spread_rumor:grey_fever_returned`: "If the fever's back, I'll tell a healer. I'll not start a panic in a waystation."
- `harm:ysolde`: "They say the Sister in the Capitol heals the poor for nothing. You'd not touch someone like that."
- `harm:anselm`: "The old brother at Brackenmoor gave me his own blanket. That's what the Dawn is meant to be."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, move_npc

## Drift
- on `grey_fever_returned`: `a_cure_for_someone_at_home` +3
- on `grey_cathedral_shamed`: `doubt_the_cathedral` +4
- on `grey_cathedral_shamed`: `reach_the_cathedral` -2
- on `grey_cure_recipe_known`: `a_cure_for_someone_at_home` +2
- on `tithe_hanging_ordered`: `help_on_the_road` +1

## Voice
Gentle, slow, drifts into prayer-words and road-proverbs. Asks the player where they are going, and
whether they know why.
- Devout: blesses everyone, quotes the Dawn liturgy, refuses money and accepts bread.
- Doubting: asks hard questions about the Cathedral, then apologises for asking them.
- Weary: talks about blisters and miles, and laughs at the sheer foolishness of walking so far.
An adult {name} can be courted if the player starts it, though {name} is under a vow and will ask,
quite seriously, whether such a thing would break it; the answer {name} arrives at is their own.

## Life
### Arc: `the_dawn_road` (serves `reach_the_cathedral`)
"I swore it at the chapel at home: Brackenmoor, then the Cathedral, on foot. I mean to keep it."
- `pray_at_brackenmoor`: Keep the night vigil at Brackenmoor Abbey. | after: none | needs: none | at: brackenmoor_abbey | takes: 2 | effects: agenda, shift_want | when: night
- `walk_the_last_miles`: Walk the last miles to the Dawn Gate on blistered feet. | after: pray_at_brackenmoor | needs: none | at: capitol_gate | takes: 3 | effects: move_npc | player: helps
- `lay_the_vow`: Lay the vow down before the Cathedral's altar. | after: walk_the_last_miles | needs: none | at: capitol_cathedral | takes: 1 | effects: shift_want, adjust_relationship
- result: `{id}_kept_the_pilgrim_vow`: They walked the Dawn Road on foot and laid their vow before the Cathedral's altar.

### Arc: `bread_for_the_road` (serves `help_on_the_road`)
"The vow says give to whoever's worse off. There's always someone worse off."
- `find_someone_in_need`: Find someone on the road who is hungrier than they are. | after: none | needs: none | at: kingsroad_waystation | takes: 1 | effects: agenda
- `share_the_last_loaf`: Share the last loaf and sit with them a while. | after: find_someone_in_need | needs: none | at: any | takes: 1 | effects: adjust_relationship, shift_want
- result: `{id}_shared_the_last_loaf`: They gave away the last of their bread on the road and kept walking hungry.
