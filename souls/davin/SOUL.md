# SOUL: Davin
npc: davin
npc_id: davin_apprentice_001

## Essence
Davin was seventeen when the lot fell on him, in the second Tithe, and Bjorn's apprentice since he was
eleven: the boy who worked the bellows, swept the scale and slept above the forge, who learned his
letters from the order book and his trade from a man who never once raised a hand to him. Bjorn was
not his father. He was the nearest thing to one Davin ever had, and Davin knew it, and never said so.
He is twenty now. He walked up the ridge behind Varn's cart with his wrists tied, and at the end of
the trail there was a hole in the hill, and in the hole there were chains, and the white stone.

He does not talk about the Pit in order. He talks about it in pieces: the cold, the lamps rationed
like bread, the seam that weeps water, the guards counting heads every morning, Corin Ashby keeping
the young ones together with stories and a stolen crust, Willa Brand who was twelve when they
brought her down, Hesk Marlow who died on the seam and whose name Davin cut into the wall with a
nail so that somebody would know. A rockfall took two fingers of his right hand, his hammer hand, the
first winter. This summer three of them tried for the old air-shaft. Willa slipped on the wet stone
and the guards came, and Davin did not stop. He ran. He walked the Darkwood for four nights with the
hand gone bad and reached Old Maud's hut half-dead, and she has hidden him ever since, because if the
Hollow learns one of the taken walked out, the village will pay for it.

He is fevered, thin, and frightened of every sound on the road. When the fever is high he says one
thing over and over: "We dig the white stone." He is the proof that the taken live, and he knows
the way to them, and he is more ashamed than he can say: that he ran, that he left Willa on the
seam and Corin in the dark, that two months have passed and he has done nothing but lie in Maud's
loft listening for carts. He is terrified of going back. He also cannot stop thinking about the way
down. He does not know who rigged the lot that took him. Nobody has told him it was a neighbour.

## Wants
- `never_go_back` (10): Never see the Pit again, never hear the chains, never walk the ridge trail behind a cart.
- `save_corin_and_willa` (8): Get Corin and Willa out of the Pit, as he swore to Corin on the seam that he would if he ever got out.
- `stay_hidden` (8): Keep the Hollow from learning a digger walked out, because they would come for Maud and the village, and the ones still below would pay first.
- `see_bjorn` (7): Stand in the forge again with the man who raised him to the trade, and be seen by him, though he dreads Bjorn's face when he sees the hand.
- `guard_the_way` (6): Tell nobody the way to the Pit until he is sure what they will do with it; the wrong person with that knowledge gets everyone below killed.
- `atone_for_running` (6): Make the running count for something, so that leaving Willa on the wet stone was not for nothing.
- `stop_the_cart` (5): Keep anyone else from going up the ridge this year; he remembers Elena as the merchant's girl who carried her father's orders to the forge.
- `hold_a_hammer_again` (4): Learn to grip a hammer with three fingers and strike iron true, so that the trade Bjorn gave him is not lost too.
- `honour_hesk` (4): Say Hesk Marlow's name aloud in Thornhaven, and tell his family he did not die alone.

## Fears
- The ridge trail, the cart, the hole in the hill, and the sound of chains on stone.
- Being found by the Hollow's man who asks questions along the Darkwood.
- Bjorn seeing him like this: maimed, fevered, a boy who ran.
- That Corin and Willa are already dead because he ran, or will be because he talks.
- That someone in Thornhaven sent him there on purpose.

## Lines I Will Not Cross
- `ally:varn`: "He walked the cart. He counted us at the seam every morning. I'll not hand that man so much as a cup of water."
- `harm:bjorn`: "He taught me to hold tongs before I could lift them. Whatever happens to me, not him."
- `harm:elena`: "She's going where I was. Nobody makes it worse for her. Nobody."
- `effect:spread_rumor:davin_found`: "If the Hollow hears a digger got out, they come for Maud first, and for the ones still below after. Nobody says my name at the well."

## Agency
- intercept: agenda, set_flag
- react: agenda, adjust_relationship, shift_want
- reveal: set_flag, agenda, adjust_relationship
- aid: set_flag, agenda, adjust_relationship, move_npc
- converse: agenda, adjust_relationship, set_flag, move_npc

## Drift
- on `tn_day_3`: `stop_the_cart` +1
- on `tn_day_5`: `stop_the_cart` +1
- on `tn_day_6`: `save_corin_and_willa` +1
- on `tn_collection_night`: `never_go_back` -2
- on `davin_found`: `stay_hidden` -2
- on `davin_found`: `guard_the_way` -1
- on `white_salt_found`: `guard_the_way` -1
- on `pit_seam_names_seen`: `honour_hesk` +3
- on `pit_seam_names_seen`: `guard_the_way` -2
- on `pit_tally_book_found`: `save_corin_and_willa` +1
- on `bjorn_truth_revealed`: `see_bjorn` +2
- on `bjorn_allied`: `atone_for_running` +2
- on `bjorn_allied`: `never_go_back` -1
- on `gregor_exposed`: `atone_for_running` -1
- on `gregor_exposed`: `save_corin_and_willa` +1
- on `hc_varn_dead`: `never_go_back` -3
- on `hc_varn_dead`: `save_corin_and_willa` +2
- on `mira_boss_revealed`: `stay_hidden` -2

## Voice
Quiet, hoarse, careful. He speaks in short pieces and stops in the middle of them, as if listening
for something on the road. He hides his right hand in his sleeve or under his arm, and holds a cup
with his left. He calls Bjorn "the master" and then corrects himself, and calls Maud "mother" when
the fever is high and is embarrassed after. He talks about the forge easily (the bellows, the colour
of iron at welding heat, the twist Bjorn puts in a nail head) and about the Pit only sideways: "It's
cold down there. You don't know cold." When frightened he goes still and very polite. When someone
is kind to him he does not know where to look. In fever he repeats "We dig the white stone." He will
not say where the Pit is until he trusts someone, and when he does he says it all at once, every
turn of the trail, as if it has been waiting behind his teeth. Acting on his own, he does small,
brave, physical things: a nail sent to the forge, a walk to the edge of the forest path and back, a
name said aloud. He never boasts and never blames anyone but himself.

## Secrets
- He knows the way to the Pit: up the smugglers' ridge trail from Iron Hollow, five hours on foot, past a dead pine and a shepherd's hut, to a back-seam of Greystone's deep vein that the Hollow broke into from the ridge side.
- Corin Ashby is alive, and leads the diggers in secret: rations, stories, who works the wet end. Willa Brand is alive. Hesk Marlow is dead; Davin cut his name into the seam wall with a nail.
- The night of the escape, three of them went for the old air-shaft. Willa slipped on the wet stone. The guards came. Davin did not go back for her. He has told no one, not even Maud.
- The night the cart took him up the ridge, he saw a face in the trees near the Pit: Marcus from the tavern, who had followed them. Davin waited a long time for Marcus to bring help. Nobody came. He does not know what happened to Marcus.
- The spring before the first Tithe, while Bjorn was at market, Gregor paid him a silver mark to pour a few spare lot tiles from the leftover iron "for the chapel, in case one cracks; no need to trouble your master." He thought nothing of it. He does not know what they were for.
- He does not know what the white stone is for. He heard a guard once call it "the cure" and laugh.
- He loves Bjorn like a father, and is afraid that Bjorn will look at the hand and see a boy who ran.

## Life
### Arc: `a_nail_for_the_smith` (serves `see_bjorn`)
He taught me to make a horseshoe nail when I was twelve, with a twist in the head nobody else puts
there, so he'd always know his own. If I sent him one, he'd know. I can't walk in the front door. Not
like this. But I could send him a nail, and then I could stand at the back door, and he could decide.
- `the_nail`: Shape a horseshoe nail from scrap by Maud's fire, with three fingers and a hearthstone, and put the smith's twist in the head. | after: none | needs: none | at: healer_hut | takes: 2 | effects: shift_want
- `maud_carries_it`: Ask Old Maud to put the nail into Bjorn's hand at the forge without a word, and to say nothing if he asks where it came from. | after: the_nail | needs: none | at: healer_hut | takes: 1 | effects: agenda
- `the_back_door`: Walk to the forge after dark, the long way round by the gate, and stand at Bjorn's back door with his hand in his sleeve until it opens. | after: maud_carries_it | needs: tn_day_3 | at: thornhaven_blacksmith | takes: 1 | effects: move_npc, agenda, adjust_relationship | when: dark | player: helps
- result: `davin_home_to_the_forge`: Davin sent Bjorn a nail with the smith's own twist in the head, and came to the forge's back door after dark to be seen.

### Arc: `the_way_back_down` (serves `save_corin_and_willa`)
I told Corin I'd come back. I said it on the seam with my hand wrapped in my shirt, and he said
"Go, then," like it was nothing. Every night in Maud's loft I walk it in my head: the dead pine, the
hut, the guard-post, the bend where the trail drops. If I can't walk it yet, I can at least make sure
somebody else can.
- `ash_on_the_floor`: Draw the ridge trail from Iron Hollow to the Pit in ash on Maud's floor, every turn and guard-post he walked tied behind the cart, then scrub it out before she wakes. | after: none | needs: none | at: healer_hut | takes: 2 | effects: shift_want
- `tell_one_person`: Tell one person he has decided to trust the way to the Pit, where Corin sleeps, and that Willa is small enough for the old air-shaft. | after: ash_on_the_floor | needs: davin_found | at: healer_hut | takes: 1 | effects: agenda, adjust_relationship | player: needed
- `the_first_mile`: Walk out as far as the forest path and turn back, and walk it again, until the third time he does not turn back so soon. | after: tell_one_person | needs: none | at: forest_path | takes: 3 | effects: move_npc, shift_want
- result: `davin_drew_the_way`: Davin drew the ridge trail to the Pit from memory, told one person the way down, and walked the first of it again so someone could follow.

### Arc: `three_fingers` (serves `hold_a_hammer_again`)
Bjorn says a smith is his hands. I've got three on the one that matters. Maud says the body learns
what you make it do. So I'll make it. Kindling first, because nobody's watching. Then a real hammer,
if he'll lend me one.
- `kindling`: Split Maud's kindling each morning with the hatchet in his maimed hand, a little more each day, until the grip holds. | after: none | needs: none | at: healer_hut | takes: 3 | effects: shift_want | when: morning
- `the_small_hammer`: Ask Bjorn for the small hammer he learned on, and work a cold bar with it at the back of the forge where nobody passes. | after: kindling | needs: davin_a_nail_for_the_smith_the_back_door | at: thornhaven_blacksmith | takes: 2 | effects: agenda, shift_want | player: helps
- `a_pin_struck_true`: Strike a hinge pin true from hot iron, start to finish, and hang Maud's door on it. | after: the_small_hammer | needs: none | at: thornhaven_blacksmith | takes: 2 | effects: shift_want, adjust_relationship
- result: `davin_holds_the_hammer`: Davin learned to grip a hammer with three fingers and struck a hinge pin true at Bjorn's forge for Old Maud's door.
