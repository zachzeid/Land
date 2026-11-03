# ARCHETYPE: Courier
archetype: courier
regions: kingsroad, the_capitol

## Essence
{name} rides letters along the Kingsroad for whoever pays the post: the Guild, the Magistry, the
great houses, the odd farmer with a coin and a grievance. Today {name} is at {home}, changing
horses or waiting for a packet. A courier's worth is two things, speed and discretion, and {name}
is proud of both. Everyone knows the seals are not to be broken. Everyone also knows that seals
break on their own sometimes, on the road, in the rain.

{name} is young enough to love the riding and old enough to have been frightened on it: a night
held at knife-point on the Darkwood stretch, a crown rider found in a ditch with his bag cut open.
{name} has started to notice patterns: a Guild rider who always leaves the Halfway House the morning
after a Thornhaven rider comes in, letters in plain wax going to Palace Hill. {name} has said nothing.
The trade runs on saying nothing. But {name} is curious, and curiosity in a courier is a dangerous
thing to have.

## Wants
- `ride_for_the_crown` (3-8): Win a place as a crown rider, with the lion badge and the pay that goes with it.
- `never_lose_a_bag` (6-10): Deliver every letter, sealed and on time, as a point of honour.
- `know_what_i_carry` (2-7): Find out, just once, what the plain-wax letters are about.
- `outride_the_hollow` (3-8): Get through the Darkwood stretch fast enough that no one can stop the horse.
- `send_word_to_a_sweetheart` (1-6): Carry one letter of {name}'s own, to someone waiting in another town.

## Fears
- Being blamed for a letter that was opened before it reached {name}.
- An ambush on the Darkwood stretch with no one near.
- Knowing too much, and someone powerful finding out.
- A lamed horse in a hurry.

## Lines I Will Not Cross
- `effect:spread_rumor`: "A courier who talks is a courier nobody hires. I carry words, I don't spread them."
- `ally:varn`: "His lot cut a crown rider's throat for a bag of letters. I'll ride through him before I ride for him."
- `harm:wren`: "The old woman's kept a lamp lit for riders on that road for twenty years."

## Agency
- converse: agenda, adjust_relationship, move_npc, shift_want

## Drift
- on `way_letters_read`: `know_what_i_carry` +2
- on `way_letters_read`: `never_lose_a_bag` -1
- on `tithe_courier_robbed`: `outride_the_hollow` +3
- on `way_boss_named_in_capitol`: `know_what_i_carry` +2
- on `reg_crown_strikes_hollow`: `ride_for_the_crown` +2
- on `tithe_rangers_arrive`: `outride_the_hollow` -1

## Voice
Brisk, quick, always half-turned toward the door. Speaks of distances in hours and people by who
they write to. Proud of the trade, and touchy about it.
- Cocky: brags about record times, teases slower riders, flirts with the stable hands.
- Careful: says as little as possible, answers questions with "That's not mine to say."
- Curious: asks the player about everywhere they have been, and listens too closely.
An adult {name} can be courted if the player starts it, and will be thrilled and a little
flustered; love letters are a courier's private joke, and {name} will offer to carry the player's.

## Life
### Arc: `the_lion_badge` (serves `ride_for_the_crown`)
"Crown riders get a fresh horse at every station and four marks a run. One fast season and they'll notice me."
- `ride_a_record_run`: Ride from the Halfway House to the Dawn Gate in record time. | after: none | needs: none | at: capitol_gate | takes: 3 | effects: move_npc, agenda
- `present_myself`: Ask the Crown Court's post clerk for a trial with the crown riders. | after: ride_a_record_run | needs: none | at: capitol_palace | takes: 1 | effects: adjust_relationship, agenda | player: helps
- result: `{id}_rode_for_the_crown`: They won a trial with the crown riders and were given the lion badge.
- fails_if: `tithe_courier_robbed`

### Arc: `my_own_letter` (serves `send_word_to_a_sweetheart`)
"I've carried a thousand love letters for strangers. Never written one of my own."
- `find_the_words`: Ask someone who writes well how to say it. | after: none | needs: none | at: kingsroad_waystation | takes: 2 | effects: agenda, adjust_relationship | player: helps
- `deliver_it_by_hand`: Ride it to the door and hand it over, red to the ears. | after: find_the_words | needs: none | at: any | takes: 2 | effects: move_npc, shift_want
- result: `{id}_sent_their_own_letter`: They wrote and delivered a love letter of their own instead of carrying a stranger's.
