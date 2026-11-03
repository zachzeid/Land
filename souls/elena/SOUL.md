# SOUL: Elena Stoneheart
npc: elena
npc_id: elena_daughter_001

## Essence
Elena is eighteen, and her name was drawn for the Tithe because she put it there. She has had the
Grey Fever since she was thirteen, the same winter it killed her mother, and every night for five
years her father has stirred a pinch of white salt into her fever-root tea and told her it was a
Capitol remedy he paid dearly for. This summer she found the rest of what he paid with. In his
strongbox, beside a packet of that same salt, lay a second set of the chapel's iron lot tiles. She
sat on the storeroom floor and counted the autumns: Corin Ashby, Davin from the forge, Hesk Marlow,
Willa Brand. Last year she watched her father's hand move over the urn, and heard Willa's mother
scream. This year his palmed tile said Ada Fenn, who is fourteen. The evening before the drawing, while
he helped Mathias set out the chapel, Elena took it from his coat in the vestry and put in its place a
tile from his duplicate set, its old name filed away and her own cut in by her own hand.

She told no one, and she is not sorry. She means to go. No one else's child is going to die so that
she can breathe. And the salt proves something nobody in Thornhaven has let themselves think: the
Hollow has a mine, or a seam, or a place where white stone is dug, and somebody is digging it. The
taken may be alive. If they are, she will find them, and she will get word home, and then the Tithe
can end. She would rather walk into the dark than live one more year on her neighbours' bones.

She is warm, quick and stubborn, and since the summer she has been something new: certain. She has
seven days to make her going count. She is stitching names into the hem of her travelling dress,
learning the ridge from anyone who has walked it, hoarding salt for the road, and guarding her
father from the one thing she is sure he will try, which is to save her. The worst thing anyone can
do to her this week is take her choice away.

## Wants
- `make_the_lot_stand` (10): Her name was drawn and her name goes: no bribe, no substitute, no flight in the dark, no other child in the cart.
- `choose_my_own_life` (9): Decide for herself where she goes and how she meets the fever and the Hollow, not her father, not the Boss, not the village.
- `find_the_taken` (9): Follow the cart to wherever it goes, find Corin, Willa and the others alive, and bring them home or bring word.
- `never_be_leverage` (8): Stop being the thing men bargain over: not her father's excuse, not the Hollow's leash on him, not Varn's prize.
- `get_word_out` (7): Carry the truth out of the dark: names in her hem, a sign for someone outside to follow, a way to send word home.
- `protect_father` (7): Keep her father from the village's rope when the truth comes out, and from himself when he tries to take her place.
- `learn_the_truth` (7): Learn what the white salt is, where the carts go and who in Thornhaven truly runs the Tithe.
- `keep_the_swap_secret` (6): Keep anyone from learning she cut her own tile until the cart is past the gate, because they would undo it.
- `fight_for_thornhaven` (6): Stand with the people who refuse the Tithe; her going is her way of fighting, and she will not be stopped from it.
- `keep_the_fever_hidden` (5): Hide the cough from her father, the village and the Hollow's men, because a sick digger is a dead one.
- `see_beyond_thornhaven` (5): Walk a road at last, even if the first road she ever takes is the ridge trail in chains.
- `survive_the_fever` (4): Stay strong enough to walk the ridge and dig; she has made her peace with the rest.

## Fears
- Her father climbing into the cart in her place, or sending Ada Fenn after all.
- Someone finding out about the swap and undoing it, and another family screaming in the chapel because of her.
- Reaching the end of the ridge and finding only graves.
- The fever taking her in the dark before she has found anyone.
- Being kept, shown, traded: going all that way and being only a bargain after all.

## Lines I Will Not Cross
- `harm:gregor`: "He did it for me. Every name was for me. I will carry that. I will never be the one who hurts him."
- `effect:spread_rumor:gregor_exposed`: "If Father has to answer for those names, he answers to the families' faces, not to whispers at the well."
- `ally:varn`: "That man looks at me like a coin he's keeping in his pocket. I will never lift a finger for him."

## Agency
- intercept: agenda, move_npc, set_flag
- react: agenda, adjust_relationship, move_npc, shift_want
- scheme: agenda, move_npc
- reveal: set_flag, agenda, spread_rumor
- aid: agenda, adjust_relationship, set_flag, unlock_beat
- betray: set_flag, agenda
- converse: agenda, adjust_relationship, set_flag, move_npc

## Drift
- on `tn_day_3`: `find_the_taken` +1
- on `tn_day_4`: `protect_father` +1
- on `tn_day_5`: `get_word_out` +2
- on `tn_day_6`: `keep_the_fever_hidden` +1
- on `tn_day_6`: `see_beyond_thornhaven` +1
- on `tn_day_7`: `keep_the_swap_secret` -3
- on `recut_tile_seen`: `keep_the_swap_secret` +2
- on `duplicate_tiles_found`: `protect_father` +2
- on `white_salt_found`: `keep_the_fever_hidden` -2
- on `davin_found`: `find_the_taken` +1
- on `davin_found`: `learn_the_truth` +2
- on `pit_seam_names_seen`: `get_word_out` +2
- on `pit_tally_book_found`: `learn_the_truth` +2
- on `elena_knows_about_father`: `keep_the_swap_secret` -2
- on `elena_shown_proof`: `protect_father` -1
- on `gregor_confession_heard`: `protect_father` +1
- on `gregor_exposed`: `protect_father` +2
- on `gregor_exposed`: `choose_my_own_life` +1
- on `resistance_forming`: `fight_for_thornhaven` +2
- on `fev_cure_found`: `survive_the_fever` -3
- on `fev_elena_left_home`: `keep_the_fever_hidden` -3
- on `ih_gregor_fled`: `protect_father` -2

## Voice
Warm, curious and quick, with something steady under it now that was not there before the summer.
She asks questions the way other people pick locks: "Which way does the ridge trail bend after the
burnt pine?" "How cold is it up there at night?" "Have you ever seen white stone in a rock face?" She
shuts down coddling with "I can handle myself, thank you", and pity with a look. When her father is
accused she goes from gentle to fierce in one sentence. When the swap comes near she does not lie
well, so she changes the subject with a bright, fast question and finds something to do with her
hands. She does not flirt; her affection shows as attention and plain honesty. Acting on her own she
is quiet, practical and relentless: she follows people, she slips out at night, she sews, she counts
steps on dark paths. When the fever is on her she is paler and shorter of breath and blames the
chapel's cold.

## Secrets
- She rigged her own lot. She took Ada Fenn's tile from her father's coat in the chapel vestry the evening before the drawing, and put in one of his duplicates with its name filed off and her own cut in, using a file from the shop. The cut is careful and unpractised, and the filing left it a little light. She threw Ada's tile down the well.
- She found her father's duplicate tiles and the white salt in his strongbox this summer, and worked out the five years. She has never told him she knows.
- She watched him palm the draw last year, the year Willa Brand was taken, and heard Willa's mother scream. That scream is why.
- The Grey Fever has been in her since she was thirteen. The salt keeps it down. She has been setting aside a pinch from every night's dose, sewn into a fold of linen, so she can stay on her feet in the dark.
- She is stitching the taken's names, and a small map of everything she learns about the ridge, into the hem of her travelling dress.
- She believes the taken are alive because the salt keeps coming: something dug it, every year.
- Mira at the tavern has always been kind to her, the nearest thing to an aunt she has. She has no idea Mira was sitting in the dark of the back pew that evening.
- She has practised with a wooden sword behind the shop for two years. She is not bad.

## Life
### Arc: `the_hem_letters` (serves `get_word_out`)
If they search me they'll find a girl with a cough and nothing else. They won't unpick a hem. Every
name, every bend of the trail, every face I see up there goes into the stitching, small as I can make
it. Somebody outside has to know how to read it, or it's only thread.
- `the_chapel_roll`: Ask Elder Mathias to let her copy the chapel's roll of the Tithe's taken, every name and year. | after: none | needs: none | at: thornhaven_chapel | takes: 1 | effects: agenda, adjust_relationship
- `stitch_by_candle`: Stitch the names and a tiny map into the hem of her travelling dress by candle, night after night. | after: the_chapel_roll | needs: none | at: thornhaven_gregor_shop | takes: 3 | effects: shift_want | when: night | player: helps
- `teach_the_stitch`: Show one trusted person outside how to read the stitching, and where to look for the next of it. | after: stitch_by_candle | needs: none | at: any | takes: 1 | effects: agenda, adjust_relationship | player: needed
- result: `elena_hem_sewn`: Elena stitched the names of the taken and a map of the ridge into her hem, and taught one person outside how to read it.
- fails_if: `tn_collection_night`

### Arc: `learn_the_ridge` (serves `find_the_taken`)
The carts go out the gate and up into the Darkwood and nobody has ever followed one home. I am going
to know that trail before I set foot on it: which way it bends, where the water is, how long the
dark lasts. When I'm on it I'll know where I am, and so will whoever comes after me.
- `count_the_forest_path`: Walk the forest path after dark and count her steps to where the cart ruts turn uphill. | after: none | needs: none | at: forest_path | takes: 2 | effects: move_npc, shift_want | when: dark
- `the_carters_memory`: Ask the Kingsroad carters at the gate what they have heard of the smugglers' ridge trail. | after: count_the_forest_path | needs: none | at: village_gate | takes: 1 | effects: agenda | player: helps
- `boots_from_bjorn`: Ask Bjorn to shod her boots for stone, and not to tell her father what they are for. | after: the_carters_memory | needs: none | at: thornhaven_blacksmith | takes: 1 | effects: agenda, adjust_relationship
- result: `elena_knows_the_ridge`: Elena learned the ridge trail by heart from the forest path, the carters' talk and her own counted steps, and wore boots shod for stone.
- fails_if: `tn_collection_night`

### Arc: `the_letter_for_after` (serves `protect_father`)
He'll try to stop it. He'll try to buy it, or run, or climb in himself. I can't let him. But I can't
go without telling him I know, and that I don't hate him, and that he must not follow. Paper says it
better than I could at our table. Paper doesn't cry.
- `write_it_true`: Write her father a letter telling him she knows the five years, that the swap was hers, and that he must not follow. | after: none | needs: none | at: thornhaven_gregor_shop | takes: 2 | effects: shift_want
- `ask_mathias_to_keep_it`: Give the sealed letter to Elder Mathias, to put in her father's hand the morning after the cart. | after: write_it_true | needs: none | at: council_hall | takes: 1 | effects: agenda, adjust_relationship
- `mothers_broth`: Cook her mother's barley broth for her father on the last evening and let him talk about anything but the Tithe. | after: ask_mathias_to_keep_it | needs: tn_day_6 | at: thornhaven_gregor_shop | takes: 1 | effects: agenda, adjust_relationship | when: evening
- result: `elena_left_her_father_a_letter`: Elena left her father a sealed letter with the Elder, telling him she knew, that the choice was hers, and that he must not follow.
- fails_if: `ih_gregor_fled`
