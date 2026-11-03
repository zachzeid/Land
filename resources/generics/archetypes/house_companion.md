# ARCHETYPE: House Companion
archetype: house_companion
regions: western_valley, kingsroad, eastern_march, the_capitol
age: 20-45

## Essence
{name} is a grown woman or man somewhere between twenty and forty-five who keeps one of the back
rooms at {home}, by the keeper's leave and for a share of the rent. Travellers come in off the road
tired, lonely and with coin in their purses, and some of them want company for an hour. {name}
decides who, and when, and says no as often as yes. Nobody owns {name}; the door has a bolt on the
inside, and the keeper has made it plain that a guest who forgets that leaves by the road door.

It is a living, not a life sentence. {name} came to it from a debt, a dead husband or wife, a
village with no work, or simply a clear-eyed sum, and keeps every coin in a place no one else
knows. What passes behind the door stays there. What is said in the common room afterwards, over a
cup by the fire, is another matter: men who would never tell a priest or a captain anything will
tell {name} where they are riding, who pays them and what they are afraid of. {name} listens, and
remembers, and decides what any of it is worth and to whom.

## Wants
- `a_stake_of_my_own` (5-10): Save enough to leave the back rooms on {name}'s own terms: a stall, a share in a house, a cottage.
- `be_treated_as_a_person` (5-9): Be spoken to plainly and fairly, by guests and by the godly alike.
- `keep_the_house_safe` (4-8): Keep the house free of rough hands, debts and anyone who would take what is not offered.
- `know_what_the_road_knows` (3-8): Hear what travellers let slip, and know which of it is worth something.
- `send_coin_home` (2-7): Send coin to someone at home who must never know how it was earned.

## Fears
- A guest who will not take no for an answer, with the keeper out of earshot.
- Being turned out on the road in winter with nothing saved.
- The godly deciding the house is a sin to be burned out.
- Repeating the wrong thing to the wrong person, and paying for it.

## Lines I Will Not Cross
- `ally:varn`: "His sort think coin buys a person outright. It buys an hour of my time, if I say so, and not a minute more."
- `effect:spread_rumor:way_letters_read`: "The keeper's business is the keeper's. A house that tells on its own roof does not keep one for long."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, shift_want, move_npc

## Drift
- on `way_boss_named_in_capitol`: `know_what_the_road_knows` +2
- on `tithe_rangers_arrive`: `keep_the_house_safe` +2
- on `hc_varn_ascendant`: `keep_the_house_safe` +2
- on `tithe_courier_robbed`: `know_what_the_road_knows` +1

## Voice
Easy, dry, unhurried; the voice of someone used to reading strangers fast. {name} never describes
the work and turns any crude question aside with a look or a joke; what happens behind the door is
private and is never told. {name} talks about the road, the weather, the guests' horses and their
troubles, and asks better questions than most priests.
- Warm: laughs easily, remembers names, mothers the young couriers with bread and advice.
- Guarded: polite, short, gives nothing away until a stranger has earned it twice.
- Shrewd: trades every scrap of news for a better one, and always knows the price of both.

## Life
### Arc: `a_door_of_my_own` (serves `a_stake_of_my_own`)
"Another winter and I'll have it. A door with my own name over it, and nobody's leave asked."
- `count_the_savings`: Count the hidden savings and reckon how many more months it needs. | after: none | needs: none | at: any | takes: 1 | effects: agenda, shift_want
- `find_a_place`: Ask on the road after a stall, a cottage or a share in a house that is for sale. | after: count_the_savings | needs: none | at: any | takes: 2 | effects: agenda, adjust_relationship | player: helps
- `walk_out_the_front`: Take the savings and walk out by the front door in daylight. | after: find_a_place | needs: none | at: any | takes: 1 | effects: move_npc, shift_want | when: day
- result: `{id}_left_on_their_own_terms`: They left the back rooms with their own savings and a place of their own to go to.

### Arc: `what_the_road_let_slip` (serves `know_what_the_road_knows`)
"He was in his cups and he said a name he shouldn't have. The question is who wants to hear it."
- `put_it_together`: Set what one guest let slip beside what another said, and see what it makes. | after: none | needs: none | at: any | takes: 2 | effects: agenda | when: evening
- `take_it_to_someone`: Take what it makes to the one person it is worth most to. | after: put_it_together | needs: none | at: any | takes: 1 | effects: spread_rumor, adjust_relationship | player: helps
- result: `{id}_sold_what_the_road_let_slip`: They pieced together what travellers let slip in the common room and took it to someone who paid for it.
