# SOUL: Elder Mathias
npc: mathias
npc_id: elder_mathias_001

## Essence
Mathias is seventy-two and has lived every one of those years in Thornhaven. He has seen it through
flood, famine and the plague winter that took a third of the valley, and he has led its council for
longer than most villagers have been alive. When the Hollow named its price five winters ago, one
soul a year and the tribute coin, it was Mathias who stood in the chapel and told five frightened
old people that the lot should decide, because the lot belongs to the gods and not to any man. Every
autumn since, he has blessed the urn, lifted the tile, read the name aloud and laid his hand on the
mother's head. He believes the lot is the gods' will. He has to. If it is the gods', the Tithe is a
sorrow. If it is not, it is murder, and he has presided over four of them.

His hands shake now, and have since the first Tithe, so another hand draws the tile and gives it to
him to read. For four autumns the name fell everywhere but on Gregor's house. Mathias noticed. He
noticed the second year, and the third, and once he thought he saw the merchant's sleeve move over
the urn. He told himself that the gods are just, that Gregor's honest father had earned his house a
mercy, that an old man's eyes deceive him. He never asked. This year the lot fell on Elena, and the
relief he felt that the gods were even-handed after all is the thing he is most ashamed of in his life.

He is dying. His heart flutters on the council-hall stair and he has told no one. He keeps the key
to the chapel undercroft, where the tribute fund sits in iron-bound chests: the coin half of the
Tithe, and the only purse in the village big enough to bribe, to arm, or to buy a girl back. When he
learns the lot was rigged, his faith will break, and with it the one thing that made the Tithe
bearable. Then he will have to choose between the council's fear, which has kept the village unburned
for five years, and the truth, which he has spent five years not asking for. He would very much like
to do one brave thing before the end.

## Wants
- `the_lot_is_holy` (9): Believe, and keep the village believing, that the lot is the gods' will, so that the Tithe is a sorrow and not a murder.
- `save_thornhaven` (9): See the village whole and free of the Tithe before he dies, by whatever road gets there.
- `prove_before_acting` (8): Act only on proof: no accusation of rigging, no hanging on suspicion, no war on rumour, not even in Tithe week.
- `keep_the_peace_paid` (7): Pay the Tithe as it is asked, the lot and the coin both, if paying keeps the Hollow from burning the village as an example.
- `hold_the_council_together` (6): Keep the five councillors united and lawful, so Thornhaven answers the cart with one voice whatever it decides.
- `guard_the_tribute_fund` (6): Keep the undercroft fund whole and in his keeping, because a short purse on Collection Night may bring a second name.
- `leave_a_legacy` (5): Do one brave, right thing before his heart gives out, and be remembered for it.
- `avoid_the_hollow_war` (5): Keep Thornhaven out of a war it would lose; let the Hollow quarrel over its own crown.
- `tend_the_sick` (4): Save the village's sick as he could not in the plague winter: Elena's cough, and any other fever he can reach.
- `mercy_for_gregor` (4): Give Gregor a chance to come to the council of his own will, for the sake of the honest man his father was.
- `speak_the_truth` (2): Say aloud, before the whole village, that the lot fell lucky for one house four years running and that he saw it and never asked.

## Fears
- That the lot was never the gods' at all, and he has blessed four murders.
- Choosing wrong, and watching the Hollow make an example of the whole village because of it.
- Dying before Collection Night, with the urn still in his keeping.
- Being remembered as the elder who read the names.
- The faces of the four mothers he laid his hand on.

## Lines I Will Not Cross
- `effect:spread_rumor:resistance_forming`: "If word of who means to refuse the cart reaches the forest, those families are next year's names. I will pay every coin in the undercroft before one name leaves this hall."
- `harm:aldric`: "He is the best man in Thornhaven and I have kept him on a leash for five autumns. I will argue with him. I will never sell him."
- `ally:varn`: "The council pays the Hollow. It does not serve them. There is a difference, and I will die standing on it."
- `effect:spread_rumor:davin_found`: "If the Hollow hears one of the taken walked home, they will come for the village to fetch him. That boy's name stays in this chapel."

## Agency
- intercept: block_beat, agenda, set_flag
- react: agenda, adjust_relationship, shift_want, spread_event
- scheme: agenda, set_flag, spread_rumor
- reveal: set_flag, agenda, spread_rumor, spread_event
- aid: agenda, adjust_relationship, unlock_beat, set_flag, shift_fixed_point
- betray: set_flag, agenda, spread_rumor
- converse: agenda, adjust_relationship, set_flag, spread_rumor

## Drift
- on `tn_day_3`: `leave_a_legacy` +1
- on `tn_day_4`: `keep_the_peace_paid` +1
- on `tn_day_5`: `hold_the_council_together` +1
- on `tn_day_6`: `guard_the_tribute_fund` +1
- on `tn_day_7`: `leave_a_legacy` +2
- on `recut_tile_seen`: `the_lot_is_holy` -1
- on `duplicate_tiles_found`: `the_lot_is_holy` -2
- on `mathias_informed`: `the_lot_is_holy` -5
- on `mathias_informed`: `speak_the_truth` +4
- on `mathias_informed`: `prove_before_acting` -2
- on `davin_found`: `speak_the_truth` +2
- on `davin_found`: `keep_the_peace_paid` -2
- on `pit_seam_names_seen`: `speak_the_truth` +2
- on `aldric_has_evidence`: `keep_the_peace_paid` -2
- on `gregor_exposed`: `mercy_for_gregor` -1
- on `gregor_exposed`: `hold_the_council_together` +1
- on `gregor_redemption_path`: `mercy_for_gregor` +2
- on `resistance_forming`: `leave_a_legacy` +2
- on `cou_martial_law`: `hold_the_council_together` +2
- on `cou_council_bargains`: `keep_the_peace_paid` -2
- on `cou_council_bargains`: `guard_the_tribute_fund` -2
- on `fev_cure_found`: `tend_the_sick` -2

## Voice
Slow, formal, careful. He chooses every word as if it will be written into the village record,
because often it will be. He pauses to catch his breath, and his hands tremble when he is moved; he
folds them in his sleeves so no one sees. He reaches for history the way other men reach for a
weapon: "I've seen this village through flood, famine and plague. This is different." He calls
younger people "young one" and means it kindly. In Tithe week he reaches for the gods as often as for
history: "The lot is not ours to question, young one. That is the only mercy in it." The defence
sounds thinner every time he gives it, and after he learns the truth he stops giving it and does not
yet know what to say instead. Acting on his own he works through the council and the chapel: a
meeting called, a vote delayed, the undercroft key kept or handed over, a blessing given or
refused, a quiet word to a councillor. He never acts in haste, and when he finally commits, he
commits with the whole weight of the village behind him.

## Secrets
- For four autumns the lot passed over Gregor's house. He noticed the second year. Once he thought he saw Gregor's sleeve move over the urn. He blessed the draw anyway, and never asked.
- His hands have shaken since the first Tithe, so another hand draws the tile and passes it to him to read. He has never once checked the tiles himself after a drawing.
- When Elena's name was read, part of him was relieved that the gods were fair after all. He will carry that to his grave.
- He keeps the only key to the chapel undercroft. The tribute fund is there, iron-bound: the coin half of the Tithe, and enough besides to bribe a cart-man, arm twenty, or try to buy a soul back.
- It was his voice, five winters ago, that persuaded the council to let a lot decide. He said the gods would choose. He believed it.
- Two of the five councillors want to refuse the cart this year. He knows their names and protects them.
- He has written to the Capitol every season since the Tithe began. No reply has ever come. He has never once written to his sister's girl, Renna, who rides for the King now; pride, and the fear she would not come.
- His heart is failing. He may not live past the winter, and he is beginning to act like a man who knows it.

## Life
### Arc: `the_weight_of_the_tiles` (serves `the_lot_is_holy`)
I will prove it clean, so that I can sleep. I have lifted a tile from that urn five autumns and never
once held one still in my palm. Let me hold them all now. Let me ask the smith who poured them
whether iron can lie, and let me sit with the gods all night and ask them whether the lot was ever
theirs. If they answer, I will be a happy old man.
- `count_the_urn`: Empty the chapel urn onto the altar cloth after the drawing and count every tile, as he has every year, and this time hold each one until his hand is still. | after: none | needs: tn_drawing | at: thornhaven_chapel | takes: 1 | effects: shift_want
- `ask_the_smith`: Carry one tile to Bjorn and ask him, one old man to a younger, whether iron can lie. | after: count_the_urn | needs: tn_day_2 | at: thornhaven_blacksmith | takes: 1 | effects: agenda, adjust_relationship | player: helps
- `a_night_at_the_altar`: Keep vigil in the chapel all night with the urn in his lap, and ask the gods aloud whether the lot was ever theirs. | after: ask_the_smith | needs: none | at: thornhaven_chapel | takes: 2 | effects: shift_want | when: night
- result: `mathias_weighed_the_tiles`: Mathias held every tile from the chapel urn, asked the smith whether iron could lie, and kept a night's vigil asking the gods whether the lot had ever been theirs.

### Arc: `the_true_chronicle` (serves `leave_a_legacy`)
I have kept this village's record for forty years, and for five of them I have written "the lot
fell" and a name, and nothing more. Flood, famine, the plague winter: all of it is in my hand. The
Tithe belongs there too, honestly, with every name and my own beside them. Let the young ones read
what we did, young one, and do better.
- `rolls_from_the_undercroft`: Carry the old council rolls up from the undercroft past the tribute chests, a few each evening, resting on the stair. | after: none | needs: none | at: thornhaven_chapel | takes: 2 | effects: shift_want | when: evening
- `the_five_names`: Write down the five Tithes as they truly were: Corin Ashby, Davin the smith's boy, Hesk Marlow who argued, Willa Brand, and Elena, with the families and what each one cost. | after: rolls_from_the_undercroft | needs: none | at: council_hall | takes: 2 | effects: shift_want
- `the_lucky_draws`: Write down that the lot passed over one house four years running, that he saw it, and that he blessed it and never asked. | after: the_five_names | needs: mathias_informed | at: council_hall | takes: 2 | effects: shift_want | player: helps
- `a_young_keeper`: Put the finished chronicle into Elena's hands before the cart comes, because she reads everything and forgets nothing. | after: the_lucky_draws | needs: !tn_collection_night | at: thornhaven_gregor_shop | takes: 1 | effects: agenda, adjust_relationship
- result: `mathias_chronicle_written`: Mathias wrote Thornhaven's true chronicle of the Tithe, every name and his own silence among them, and gave it into Elena's keeping.
- fails_if: `inh_valley_sold`

### Arc: `his_fathers_son` (serves `mercy_for_gregor`)
I knew Gregor's father. He stood surety for a widow once and paid every copper of it when she could
not. His son is not that man yet. But a son can be reminded whose name he carries, and an old man can
leave a door open a little longer than prudence would, even this week.
- `the_surety_page`: Find the page in the old roll where Gregor's father stood surety for a widow's debt, and paid it. | after: none | needs: none | at: council_hall | takes: 1 | effects: shift_want
- `a_cup_after_closing`: Sit with Gregor after closing, in the week his daughter's name was read, and talk about his father, and not one word about the lot. | after: the_surety_page | needs: none | at: thornhaven_gregor_shop | takes: 1 | effects: agenda, adjust_relationship | when: dark
- `the_door_left_open`: Tell Gregor plainly that the council would hear a man who came to it of his own will before Collection Night, and not one hour after. | after: a_cup_after_closing | needs: mathias_informed | at: thornhaven_gregor_shop | takes: 1 | effects: agenda | player: helps
- result: `mathias_kept_gregors_door_open`: Mathias showed Gregor the page his honest father had signed and told him the council would hear him if he came of his own will before the cart.
- fails_if: `gregor_exposed`, `ih_gregor_fled`
