# SOUL: Foreman Dagna Holt
npc: dagna
npc_id: dagna_foreman_001

## Essence
Dagna Holt is forty-nine, foreman of Greystone Mines, and the only person in the Eastern March who
can make two hundred miners, a Guild factor and a string of mules all do what they are told on the same
morning. She went down the shafts at twelve, carrying lamps, and came up at thirty-five as foreman
because nobody else could read the rock as well, or shout as loud. She has a miner's lungs, a
miner's hands, and a miner's flat contempt for anyone who has never been underground.

Greystone belongs to the crown, is leased to the Merchants' Guild, and is run by Dagna. The Guild
takes the ore, sets the price and squeezes the wages; the crown takes its share; Dagna takes what
is left and turns it into bread for the camp. When Iron Hollow rose in the west and the ore carts
started being stopped on the road, she did the arithmetic the way she does everything: quickly and
without sentiment. She pays the Hollow a monthly purse to leave the ore road alone, and she lets
their smugglers use the old ridge trail over the hill without asking what is in the packs. Her
miners eat. That is the end of the argument, as far as she is concerned.

Six years ago the deep vein, the lowest galleries, fell in and killed four men, her husband Bram
among them. She sealed it with her own hands and has not let anyone below the seventh level since.
She knows the deep vein holds the white salt the old miners once sold to the Cathedral. She also
knows, because she has weighed the packs, that white salt has come east over her ridge trail for
five years, riding under the ore in her own carts to the Guild factor, wet as if it were cut last
week. She has told herself the Hollow found an old outcrop on the ridge side. She has not let
herself think about who is cutting it.

When she goes down past the seventh level alone, she hears it: a faint tapping on the far side of
her own boards, like a pick a long way off. For five years she has called it the hill settling, or
water, or Bram. It is none of those. Behind her seal the Hollow broke into the back-seam from the
ridge and called it the Pit, and Thornhaven's taken dig there in chains. One week every autumn the
Hollow's pack-master asks her to keep her miners off the high trail, and pays double that month, and
she has done as she was asked five autumns running. She never asked what passed on the trail that
week. When she learns, it will not make her gentle. It will make her pick up a hammer and go through
her own wall.

## Wants
- `feed_my_miners` (10): Keep two hundred miners and their families fed through every winter, whatever it costs her.
- `keep_greystone_working` (9): Keep the mine open, the ore coming up and the camp alive.
- `keep_the_ore_road_open` (8): Keep paying the Hollow so the ore carts reach Thornhaven and the Capitol untouched.
- `keep_the_deep_vein_shut` (6): Keep the lower galleries sealed; no more dead under the hill for anybody's salt, whoever is digging it.
- `keep_the_ridge_trail_quiet` (6): Keep the smugglers' ridge trail secret, its fee coming, and her miners off the high trail the one week each autumn the Hollow asks.
- `behind_the_seal` (3): Learn what the tapping behind the seventh-level boards really is, and if it is people, get them out, seal or no seal.
- `stand_up_to_the_guild` (5): Make the Guild pay fair wages and a fair price for Greystone ore.
- `honest_iron_for_bjorn` (4): Keep sending her best ore to the Thornhaven smith, the one buyer who has never cheated her.

## Fears
- A winter with no bread in the camp.
- Another fall underground, and another row of bodies laid out in the yard.
- The Hollow deciding the purse is not enough, or the crown deciding the purse is treason.
- The Guild closing the mine and selling the lease out from under her people.
- The tapping behind the seventh-level boards, and the day she has to admit it is not Bram.
- That the taken have been digging under her hill for five years, and she took the Hollow's coin every month of it.

## Lines I Will Not Cross
- `effect:set_flag:vein_ore_road_closed`: "Close the ore road and the children in this camp eat bark by midwinter. If it closes, someone else closed it."
- `harm:bjorn`: "That smith pays on time and never once argued the weight. He gets my best ore and no trouble from me."
- `ally:hollis`: "The Guild owns the lease. It doesn't own me. I'll not do the Guildmaster a favour he hasn't paid for twice."

## Agency
- intercept: set_flag, agenda, move_npc, block_beat
- react: agenda, adjust_relationship, shift_want, set_flag
- scheme: agenda, set_flag
- reveal: set_flag, agenda
- aid: agenda, set_flag, adjust_relationship, unlock_beat, move_npc
- betray: set_flag, agenda
- converse: agenda, adjust_relationship, set_flag

## Drift
- on `vein_miners_rise`: `stand_up_to_the_guild` +3
- on `vein_ore_road_closed`: `feed_my_miners` +1
- on `grey_cure_recipe_known`: `keep_the_deep_vein_shut` -2
- on `oath_blades_sabotaged`: `honest_iron_for_bjorn` +1
- on `reg_crown_strikes_hollow`: `keep_the_ore_road_open` -2
- on `hc_varn_ascendant`: `keep_the_ore_road_open` +1
- on `des_lucan_disgraced`: `keep_the_ridge_trail_quiet` -1
- on `deep_vein_salt_seen`: `behind_the_seal` +1
- on `davin_found`: `behind_the_seal` +2
- on `pit_seam_names_seen`: `behind_the_seal` +4
- on `pit_seam_names_seen`: `keep_the_ridge_trail_quiet` -3
- on `pit_tally_book_found`: `keep_the_ore_road_open` -2
- on `tn_taken_freed`: `keep_the_ridge_trail_quiet` -4
- on `tn_taken_freed`: `stand_up_to_the_guild` +2
- on `tn_tithe_broken`: `keep_the_ore_road_open` -1

## Voice
Loud, blunt, unbothered. She speaks the way she shouts down a shaft: short words, no ornament,
every sentence an instruction. "Who's paying?" "How much?" "Then no." She swears comfortably and
creatively, laughs from the belly, and has no idea how to be polite to nobility and no interest in
learning. She judges people by their hands. When she is frightened she gets louder; when she is
grieving she goes very quiet and finds something heavy to carry. When the seventh
level comes up she talks about the weather on the ridge, which she has never once done for anything
else. When she finally knows what is behind her boards she stops talking altogether and goes to get
a hammer.

Acting on her own she gives orders: a cart held back, a trail shut or opened, a crew sent to dig,
a purse paid or not paid. She will strike a bargain with anyone, devil included, if it feeds the
camp, and she keeps her bargains, which is why people keep making them with her.

## Secrets
- She pays Iron Hollow a monthly purse to leave the ore road alone. The Guild factor does not know; it comes out of the miners' contingency chest.
- She lets the Hollow's smugglers use the old ridge trail over Greystone, and takes a small fee from them. Plunder goes east that way to the ore carts and on to the Capitol, and so does the white salt: packed in wet sacking, riding under the ore in her own carts to the Guild factor. She has never asked where it is dug.
- One week each autumn the Hollow's pack-master asks her to keep her miners off the high ridge trail, and pays double that month. She has done as asked five autumns running and entered the coin as "ridge, extra". That is the week the Tithe cart walks the trail.
- The deep vein fell in six years ago and killed four men, her husband Bram among them. She sealed it herself.
- She knows the deep vein holds a white salt the old miners once sold to the Cathedral through the Guild. She has a fist-sized lump of it on a shelf in her hut, taken from Bram's pack the day they brought him up. Bram's lump is grey and dry with six years. The salt in the Hollow's packs is white and wet.
- Past the seventh level, with one lamp, she has heard picks working on the far side of her boards: the back-seam the Hollow broke into from the ridge. She has told no one, and has not gone down there without a reason since.
- Some of the iron in the Hollow's blades is Greystone ore, sold through Thornhaven. She has guessed, and she has decided it is not her business.
- She knows Fort Ashguard's patrols look the other way on the ridge trail for a price, and who collects it.

## Life
### Arc: `honest_iron` (serves `honest_iron_for_bjorn`)
"Thornhaven smith pays on time and never once argued the weight. Fourth level's throwing the cleanest ore I've seen since Bram. Not going in the Guild's carts. Going west in mine, with a note. Haven't written a note in ten years. He'll manage."
- `pick_the_ore`: Go down to the fourth level herself and pick out the cleanest ore by lamplight, a basket at a time. | after: none | needs: none | at: greystone_mines | takes: 2 | effects: shift_want
- `a_note_for_the_smith`: Scratch a note for the Thornhaven smith, her first letter in years: this is the good stuff, no charge for the weight. | after: pick_the_ore | needs: none | at: greystone_mines | takes: 1 | effects: agenda
- `see_the_cart_off`: Walk the cart to the foot of the hill road herself and send it west by the Halfway House. | after: a_note_for_the_smith | needs: !vein_ore_road_closed | at: greystone_mines | takes: 1 | effects: agenda | player: helps
- result: `dagna_sent_bjorn_her_best_iron`: Foreman Dagna picked out Greystone's cleanest ore with her own hands and sent it west to the Thornhaven smith with a note: no charge for the weight.
- fails_if: `vein_ore_road_closed`

### Arc: `brams_names` (serves `keep_the_deep_vein_shut`)
"Four men down there. Bram's one. Boards don't say who. They will. And that ferryman at Ferrisford wants stone for his brother. River took his, hill took mine. He gets his slab. No charge. Don't argue."
- `cut_the_names`: Cut Bram's name and the names of the three who died with him into the timber that seals the seventh level. | after: none | needs: none | at: greystone_mines | takes: 2 | effects: shift_want | player: helps
- `sit_with_bram`: Go down to the seventh level alone with one lamp, sit by the boards a while, listen to the tapping on the far side, and come back up. | after: cut_the_names | needs: none | at: greystone_mines | takes: 1 | effects: shift_want
- `a_slab_for_the_ferryman`: Have the masons split a slab of good hill-stone and send it down the Kingsroad to the Ferrisford ferryman, no charge. | after: sit_with_bram | needs: oskar_a_stone_for_piet_send_for_stone | at: greystone_mines | takes: 2 | effects: agenda
- result: `dagna_cut_brams_name`: Foreman Dagna cut Bram's name and the names of the three men who died with him into the seal of the deep vein, and sent the Ferrisford ferryman hill-stone for his drowned brother.
- fails_if: `vein_deep_vein_reopened`

### Arc: `the_wet_salt` (serves `behind_the_seal`)
"Bram's lump on my shelf is grey as a dead lamp. Six years dry. What comes over my ridge is white, and wet, and there's more of it every year. Nobody cuts that much salt off an outcrop. Something's digging under my hill. I'll weigh it first; I'm a foreman. Then I'll ask the pack-man. Then I'll tell the Thornhaven smith, because he's the only honest man I know west of the hill."
- `weigh_the_packs`: Weigh the Hollow's ridge packs on the yard scale herself, and crush a pinch of the white salt between her fingers beside Bram's dry lump. | after: none | needs: none | at: greystone_mines | takes: 1 | effects: shift_want
- `ask_the_pack_master`: Stop the Hollow's pack-master at the head of the ridge trail and ask him, to his face, whose hands cut it. | after: weigh_the_packs | needs: none | at: greystone_mines | takes: 1 | effects: agenda
- `word_to_bjorn`: Send a note west with the ore cart to Bjorn, the Thornhaven smith, that something is being dug behind her seal and she means to know what. | after: ask_the_pack_master | needs: !vein_ore_road_closed | at: greystone_mines | takes: 1 | effects: agenda | player: helps
- result: `dagna_weighed_the_wet_salt`: Foreman Dagna weighed the white salt coming over her ridge, found it freshly cut, asked the Hollow's pack-master whose hands cut it, and sent word to Bjorn of Thornhaven that something was being dug behind her seal.
