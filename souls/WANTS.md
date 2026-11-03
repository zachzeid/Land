# Wants Index

Every want id in `souls/*/SOUL.md` (all 20 souls), for storyline authors citing `serves` and `shift_want`.
Weights are starting values (1-10); Drift moves them at runtime. The **Lines** column of each soul
(not repeated here) can still veto an option, so read the soul before giving an NPC a hook.

Storyline key: Thornhaven: **ih** iron_hand, **fev** elenas_fever, **hc** hollow_crown, **cou** council_of_ash, **oath** smiths_oath, **tn** tithe_night (planned). Wider world: **tithe** crowns_tithe, **fence** fence_of_highmarch, **inh** ashdown_inheritance, **grey** grey_fever, **des** deserters_road, **vein** deep_vein, **ford** ferrisford_toll, **mag** magistrates_ledger, **way** waystation_whispers, **reg** regents_gambit.

## gregor

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `protect_elena` | 10 | all | Keep Elena out of the Tithe cart and alive, by any means. |
| `get_elena_away` | 9 | fev, ih, tn | Get her over the Kingsroad before Collection Night (falls on day 6). |
| `buy_her_back` | 8 | tn (new) | Buy her out of the Tithe: strongbox, shop, steel, the council's fund. |
| `keep_the_secret` | 7 | ih, all | Hide five years of rigged draws and whose children went instead. |
| `find_a_substitute` | 7 | tn (new) | Put someone else in the cart: a drifter, the stranger, a re-rigged lot (The Old Bargain). |
| `cure_elena` | 6 | fev, grey | Keep Elena in the white salt wherever she goes. |
| `go_in_her_place` | 5 | tn (new) | Climb into the cart himself (The Father's Price); rises every day from day 5. |
| `find_who_swapped` | 5 | tn (new) | Learn whose hand changed his palmed tile (jumps on `recut_tile_seen`). |
| `escape_the_deal` | 5 | ih, hc | Get free of the Boss, the messenger and the salt without Elena dying. |
| `keep_the_council_paying` | 5 | cou | Keep the council paying; make the undercroft fund Elena's ransom. |
| `keep_the_supply_flowing` | 4 | oath | Keep Bjorn's steel going to the Hollow, the salt's other price. |
| `back_the_winning_master` | 4 | hc | Deal with whoever rules the Hollow, Varn included, if they can give Elena back. |
| `make_amends` | 2 | ih, cou, oath | Give back what five rigged draws took (rises on confession, `davin_found`, `pit_seam_names_seen`). |

## elena

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `make_the_lot_stand` | 10 | tn (new) | Her name goes: no bribe, no substitute, no flight, no other child. |
| `choose_my_own_life` | 9 | fev, all | Her choice, not her father's, the Boss's or the village's. |
| `find_the_taken` | 9 | tn (new) | Follow the cart, find Corin, Willa and the others, bring them or word home. |
| `never_be_leverage` | 8 | hc | Not her father's excuse, the Hollow's leash or Varn's prize. |
| `get_word_out` | 7 | tn (new) | Names in her hem, a sign someone outside can follow. |
| `protect_father` | 7 | ih, all | Keep him from the rope, and from taking her place. |
| `learn_the_truth` | 7 | ih, grey | Learn what the salt is, where the carts go, who runs the Tithe. |
| `keep_the_swap_secret` | 6 | tn (new) | No one learns she cut her own tile until the cart is past the gate. |
| `fight_for_thornhaven` | 6 | cou, oath | Stand with those who refuse the Tithe; her going is her fight. |
| `keep_the_fever_hidden` | 5 | fev | Hide the cough from her father, the village and the Hollow's men. |
| `see_beyond_thornhaven` | 5 | fev | Walk a road at last, even the ridge trail. |
| `survive_the_fever` | 4 | fev, grey | Stay strong enough to walk the ridge and dig. |

## mira (mask and Boss)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `rule_from_shadow` | 10 | all | Rule Iron Hollow, the Pit and Thornhaven without ever being seen to. |
| `keep_the_mask` | 9 | all | Stay the grieving widow, and Gregor's fellow "messenger", in every eye. |
| `harvest_the_tithe` | 9 | tn (new) | Collection Night as planned: the cart rolls, the coin comes up, next year's name is chosen. |
| `keep_varn_leashed` | 8 | hc | Dangle Elena before Varn; cut him down if he reaches. |
| `own_the_council` | 7 | cou | Keep the council paying coin and person; any bargain is with her. |
| `feed_the_captain_wrong` | 6 | tn (new) | Stay Aldric's trusted source; every gate plan rests on her slightly wrong word. |
| `burn_gregor_first` | 6 | ih | If the rigging comes out, Gregor hangs for all five years and the trail stops at him. |
| `control_the_cure` | 6 | fev, grey | Hold the white salt as the leash on Gregor and Elena; keep its source hidden. |
| `keep_the_steel_coming` | 5 | oath | Keep Bjorn's marked steel flowing to the Hollow. |
| `see_who_fights` | 4 | tn (new) | Let Elena's swap stand and mark who in Thornhaven finally fights. |
| `be_known_by_one_person` | 3 | romance, any | Be truly seen, mask off, by one person who does not run. |

## bjorn

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `read_the_tiles` | 9 | tn (new) | Weigh every tile, prove the lot rigged, find the hand that cut Elena's. |
| `honest_steel` | 8 | oath | Every piece of his iron, blade or lot tile, made true and honestly used. |
| `protect_the_village` | 8 | cou, ih | Keep Thornhaven's people safe. |
| `bring_davin_home` | 7 | tn (new) | Bring his apprentice home alive and never let him be taken again (jumps on `davin_found`). |
| `shield_elena` | 6 | fev, hc | Keep Elena out of that cart. |
| `keep_out_of_politics` | 5 | cou, hc | Stay at the anvil until the iron gives him cause (falls daily and on discovery). |
| `arm_the_resistance` | 5 | oath, cou | Arm Aldric's farmers for the gate, free. |
| `face_gregor` | 4 | ih, oath | Hear the truth of tiles and steel from Gregor's own mouth. |
| `restore_family_honour` | 4 | oath | Finish clearing his gambler father's name. |
| `atone_for_the_steel` | 3 | oath, hc | Spoil the Hollow's orders, recast the lot honest, take his blades back (jumps on the truth). |

## aldric

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `hold_the_gate` | 9 | tn, cou | **New.** Stand at the gate on Collection Night with his six; no cart leaves with a Thornhaven soul. |
| `keep_my_men_alive` | 8 | all | Bring all six volunteers home from the gate; he has buried three already. |
| `arm_the_village` | 8 | oath, cou | Steel for the six and anyone who will stand, Bjorn's forge first, council or no council. |
| `break_iron_hollow` | 8 | hc, all | End the Tithe by ending the Hollow: scattered, jailed or buried. |
| `expose_the_traitor` | 7 | ih, tn | Find who serves the Hollow and rigged the lot; prove it; see them answer in public. |
| `bring_varn_to_justice` | 7 | hc, ih | Make Varn answer for Marcus and every cart he walked up the ridge. |
| `spare_the_innocent` | 6 | fev, ih | Keep the blameless, Elena first, out of the cart and out of the reckoning. |
| `trust_the_widow` | 5 | tn, hc | **New.** Plan by Mira's word on how the cart comes (her intelligence is slightly wrong). Collapses on `mira_boss_revealed`. |
| `win_the_council` | 5 | cou | Mathias's word that the council refuses the Tithe, so the stand is lawful. |
| `find_the_taken` | 3 | tn | **New.** If the taken live, march to bring them home. Rises sharply on `davin_found`. |
| `take_command` | 3 | cou | Sign the unsent proclamation: martial law and refuse the cart himself. Rises each day. |

## mathias

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `the_lot_is_holy` | 9 | tn | **New.** The lot is the gods' will, so the Tithe is not murder. Breaks on `mathias_informed` (-5). |
| `save_thornhaven` | 9 | all | See the village whole and free of the Tithe before he dies. |
| `prove_before_acting` | 8 | ih, cou | No accusation of rigging, no hanging, without proof. |
| `keep_the_peace_paid` | 7 | cou | Pay the Tithe, lot and coin, if paying keeps the village from burning. |
| `hold_the_council_together` | 6 | cou | Keep the five councillors united and lawful: one voice to the cart. |
| `guard_the_tribute_fund` | 6 | cou, tn | **New.** Keep the undercroft fund whole and in his keeping; a short purse may bring a second name. |
| `leave_a_legacy` | 5 | cou, any | One brave, right thing before his heart gives out. Rises as the days run out. |
| `avoid_the_hollow_war` | 5 | hc | Keep Thornhaven out of a war it would lose. |
| `tend_the_sick` | 4 | fev | Elena's cough and any fever he can reach. |
| `mercy_for_gregor` | 4 | ih | A door open for Gregor to come to the council of his own will, for his honest father's sake. |
| `speak_the_truth` | 2 | tn, cou | **New.** Say aloud that the lot fell lucky for one house four years running and he never asked. Rises on `mathias_informed`, `davin_found`. |

## varn

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `take_the_hollow` | 9 | hc | Become Boss in his own name on Collection Night, the Pit and its salt answering to him. |
| `hold_elena_as_leverage` | 9 | fev, hc, tn | Turn the cart off the trail and keep Elena alive and unharmed as his hostage: Gregor's throat and the Boss's leash. Leverage only, never anything else. |
| `a_perfect_collection` | 8 | tn | **New.** The Tithe collected without a hitch: coin, name, quiet gate, ridge by dawn. |
| `be_feared` | 7 | all | Be the name Thornhaven whispers on Collection Night. |
| `crush_the_resistance` | 7 | cou, oath | Break any stand at the gate before it forms. |
| `keep_the_boss_secret` | 7 | hc | Never let anyone learn the Boss is Mira, even while replacing her. |
| `hold_the_pit` | 7 | tn, vein | **New.** Keep the Pit hidden and his; the day the village learns the taken live, the Tithe ends. |
| `keep_gregor_on_the_hook` | 6 | ih | Keep the merchant paying, supplying and terrified. |
| `find_the_runaway` | 6 | tn | **New.** Quietly find the escaped digger (Davin) before the Boss learns Varn lost him and lied. |
| `arm_the_hollow` | 5 | oath | Keep Bjorn's steel flowing to Hollow hands. |
| `kill_aldric` | 5 | cou, hc | Bury the old captain, at the gate if he insists on standing there. |

## davin (Old Maud's hut; escaped from the Pit)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `never_go_back` | 10 | tn | Never see the Pit again. Falls on `tn_collection_night` and `hc_varn_dead`. |
| `save_corin_and_willa` | 8 | tn | Get Corin and Willa out, as he swore to Corin he would. |
| `stay_hidden` | 8 | tn | Keep the Hollow from learning a digger walked out; Maud, the village and the ones below would pay. |
| `see_bjorn` | 7 | tn, oath | Stand in the forge again and be seen by the man who raised him to the trade. |
| `guard_the_way` | 6 | tn | Tell nobody the way to the Pit until he is sure what they will do with it. |
| `atone_for_running` | 6 | tn | Make the running count: he left Willa on the wet stone. |
| `stop_the_cart` | 5 | tn, fev | Nobody else goes up the ridge this year, Elena least of all. Rises as the days run out. |
| `hold_a_hammer_again` | 4 | oath | Grip a hammer with three fingers and strike iron true. |
| `honour_hesk` | 4 | tn | Say Hesk Marlow's name aloud in Thornhaven; tell his family he did not die alone. |

## edric (Lord Protector, the Capitol)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `keep_the_regency` | 10 | reg, all | Hold the regency and the council until Aubren comes of age. |
| `stay_indispensable` | 8 | reg, way | Be so necessary the grown king cannot rule without him. |
| `fill_the_treasury` | 8 | tithe | Get the valley's missing tithe back into crown coffers. |
| `win_a_victory` | 7 | tithe, reg | A public victory: Iron Hollow broken under the crown's banner. |
| `keep_the_magistry_quiet` | 6 | mag | Keep any trial of the valley short, private and away from his name. |
| `protect_the_boy` | 6 | reg | Keep King Aubren alive, safe and loved. |
| `use_the_hollow` | 5 | reg, tithe | Make whoever runs Iron Hollow his quiet instrument instead of his enemy, and keep the valley, its tithe and its salt quiet (falls on `tn_taken_freed`). |
| `curb_the_great_houses` | 5 | reg, inh | Keep Ashdown and the other houses needing him more than he needs them. |
| `not_at_that_price` | 2 | reg, grey (new) | Refuse to keep Aubren's fever cure in the cabinet with other people's children (rises on `pit_seam_names_seen`, `tn_taken_freed`). |

## corwin (High Magistrate, the Capitol)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `law_applied_evenly` | 10 | mag, all | The crown's law applied to great and small alike, once more before he dies. |
| `try_it_in_the_open` | 8 | mag | A public trial of the valley's rot in the High Magistry. |
| `find_the_lost_reports` | 7 | mag, tithe | Learn why three years of valley petitions and loss reports never arrived. |
| `hear_gregors_ledger` | 7 | mag, ih | Gregor and his ledger of rigged draws before the court alive, as a witness to every name it sold. |
| `check_the_regent` | 6 | reg, mag | Make the Lord Protector answer to the law like any man. |
| `challenge_the_deed` | 5 | inh | Test the Ashdown deed against the freeholders' rights. |
| `save_the_nephew` | 4 | mag, fence | Save his nephew Tobias from what he did, without bending the law. |
| `produce_the_taken` | 4 | mag, tn (new) | Issue the old writ of the body for the Tithe's taken and try whoever bought their labour (rises on the Pit discovery flags). |

## seraphine (Ashdown House, the Capitol)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `own_the_valley` | 10 | inh | Own the Western Valley outright under the Ashdown deed. |
| `restore_house_ashdown` | 9 | inh, reg | Restore her house's fortune and its place among the great houses. |
| `clear_fathers_debts` | 8 | inh, fence | Pay off her father's Guild debts and get Hollis's hand off her throat. |
| `keep_her_hands_clean` | 8 | way, fence, grey | Never let her name be tied to the Hollow, the fence or the fever. |
| `keep_the_valley_afraid` | 7 | inh, cou | Keep Thornhaven frightened enough to keep selling freeholds cheap. |
| `a_seat_beside_the_throne` | 5 | reg | Make Ashdown the regent's indispensable ally, or the next regent's. |
| `meet_the_boss` | 3 | way, reg | Learn who runs Iron Hollow; a partner she has never seen, she cannot control. |

## hollis (Merchants' Guildhall, the Capitol)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `turn_a_profit` | 9 | fence, vein | Make money on everything that moves, and never lose on a deal. |
| `hold_every_patron` | 8 | fence, mag | Keep his private patron ledger safe, and everyone in it needing him alive. |
| `a_seat_on_the_council` | 8 | reg | A seat on the regency council, and the respectability it brings. |
| `keep_the_river_moving` | 7 | fence, ford | Keep Hollow goods flowing from Ferrisford through his warehouses, washed clean. |
| `keep_the_guild_clean` | 6 | mag, fence | Keep the Guild's public name spotless. |
| `own_the_ore` | 5 | vein | Keep Greystone's lease and iron price in Guild hands. |
| `keep_rook_useful` | 4 | fence | Keep the Warrens fence small, useful, frightened and deniable. |
| `keep_the_salt_coming` | 7 | grey, vein, fence (new) | Buy the Pit's white salt from Greystone's carters cheap, sell it to the Cathedral dear, never ask who digs it (collapses on `tn_taken_freed`). |

## ysolde (Cathedral of the Dawn, the Capitol)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `heal_the_sick` | 10 | grey, fev | Heal whoever is sick in front of her, rich or poor. |
| `free_the_cure` | 8 | grey, fev | Get the true cure to everyone who needs it, whatever the Cathedral charges. |
| `get_the_deep_salt` | 7 | grey, vein | Get the deep-vein salt out of the hill by free and honest hands, for every patient. |
| `admit_the_fever_returned` | 6 | grey | Make the Cathedral admit the Grey Fever has come back. |
| `expose_the_rationing` | 6 | grey | Show the city the Cathedral sold mercy, and is about to again. |
| `reach_the_valley` | 6 | grey, fev | Get herself or the cure to the coughing girl in the west. |
| `keep_her_vows` | 5 | grey | Stay a Sister of the Dawn if she can (drops 4 on `tn_taken_freed`, when she learns who dug the cabinet's salt). |
| `no_cure_from_chains` | 3 | grey, tn (new) | Never hand a patient a cure dug by stolen children; break the chains even if the cabinet goes empty. |

## renna (King's Rangers, the Capitol)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `prove_the_rangers` | 9 | tithe, des | Prove the Rangers are the crown's law on a horse, not the regent's dogs. |
| `restore_order_in_the_west` | 8 | tithe, reg | Bring real crown law back to the Western Valley for good. |
| `refuse_a_scapegoat` | 7 | tithe, mag | Never hang a convenient villager to hand the regent a victory. |
| `bring_my_rangers_home` | 6 | tithe, reg | Bring all forty riders home alive. |
| `bring_varn_in` | 6 | des | Serve the Ashguard warrant and bring Varn to trial alive. |
| `seize_the_crossing` | 5 | ford | Take Ferrisford and close the Hollow's river road. |
| `face_uncle_mathias` | 5 | tithe | Make peace with Mathias, the uncle she walked out on. |
| `obey_the_crown` | 4 | reg, tithe | Follow the regent's orders; a ranger who picks her orders is a bandit with a badge. |
| `refuse_the_cart` | 4 | tn, tithe (new) | Put her rangers at Thornhaven's gate on Collection Night (rises on `tn_day_5`, `tn_day_6`). |

## rook (the Warrens, the Capitol; about 17)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `get_out_alive` | 10 | fence, all | Get out of the Warrens before the river or anyone's men get her. |
| `get_out_rich` | 8 | fence, ford | Leave with enough coin that she and her crew are never hungry again. |
| `sell_what_i_know` | 7 | way, inh | Sell the secret of "the lady on the hill" before it kills her. |
| `keep_the_fence_open` | 6 | fence, ford | Keep Hollow goods coming through her back room. |
| `steal_the_ledger` | 6 | fence | Get Hollis's patron ledger, the one thing that buys real safety. |
| `look_after_the_little_ones` | 6 | fence | Keep the Warrens children in her crew fed and out of the river. |
| `never_owe_anyone` | 4 | fence, reg | Never be in anyone's debt, ledger or pocket. |

## wren (the Halfway House, Kingsroad)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `one_last_game` | 8 | way | Play one last game worth playing, and win it. |
| `read_every_letter` | 7 | way | Keep reading every letter under her roof, unseen. |
| `name_the_boss` | 7 | way, hc | Prove the Boss is a woman in Thornhaven, and choose who learns it. |
| `a_quiet_fire` | 6 | way | Peace, a fire, and nobody's business but her own. |
| `outplay_the_regent` | 5 | way, reg | Show Edric, who retired her, that the old spy still sees further. |
| `keep_the_road_open` | 5 | des, way | Keep the Kingsroad safe enough for travellers to stop. |
| `spare_the_young_ones` | 4 | des, tithe | Keep young fools on the road, Renna first, from dying for others' secrets. |

## oskar (Ferrisford, Kingsroad)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `keep_my_family` | 10 | ford | Keep his wife, daughters and Piet's widow fed; find Piet's lost boy. |
| `keep_the_crossing` | 9 | ford | Keep the crossing in his family's hands. |
| `avenge_piet` | 7 | ford, des | Make the Hollow pay for his drowned brother. |
| `keep_the_toll` | 6 | ford, fence | Keep taking the Hollow's double toll. |
| `keep_the_crown_off_the_ford` | 6 | ford, tithe | Keep the rangers from turning Ferrisford into a garrison post. |
| `give_the_tally` | 5 | ford, fence | Put his tally sticks in hands that will use them, once his family is safe. |

## dagna (Greystone Mines, Eastern March)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `feed_my_miners` | 10 | vein | Keep two hundred miners and their families fed. |
| `keep_greystone_working` | 9 | vein | Keep the mine open and the ore coming up. |
| `keep_the_ore_road_open` | 8 | vein | Keep paying the Hollow so the ore carts get through. |
| `keep_the_deep_vein_shut` | 6 | vein, grey | Keep the lower galleries sealed; no more dead under the hill for anybody's salt, whoever is digging it. |
| `keep_the_ridge_trail_quiet` | 6 | vein, fence | Keep the ridge trail secret, its fee coming, and her miners off the high trail the week each autumn the Tithe cart walks it. |
| `stand_up_to_the_guild` | 5 | vein | Make the Guild pay fair wages and a fair price for ore. |
| `honest_iron_for_bjorn` | 4 | vein, oath | Keep her best ore going to the Thornhaven smith. |
| `behind_the_seal` | 3 | vein, grey, tn (new) | Learn what taps behind the seventh-level seal (the Pit) and get them out, seal or no seal (+4 on `pit_seam_names_seen`). |

## lucan (Fort Ashguard, Eastern March)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `restore_ashguards_honour` | 9 | des | Restore Ashguard's name, so its soldiers are remembered for the war. |
| `bury_the_arms_sale` | 9 | des, vein | Never let anyone learn he sold crown arms and blamed Varn. |
| `silence_varn` | 8 | des | Make sure Varn never testifies: hanged, killed resisting, or bought. |
| `keep_ashguard_paid` | 7 | des, tithe | Get his garrison's pay out of the empty treasury. |
| `a_victory_of_my_own` | 6 | des, tithe | Take the credit for the valley before the Rangers can. |
| `use_varn` | 5 | des, hc | Put Varn back in crown harness, if a pardon buys his loyalty. |
| `close_the_ridge_trail` | 4 | vein | Close the smugglers' trail his patrols take fees on, to show Ashguard keeps order and bury what passed on it. |
| `answer_for_the_cart` | 2 | des, tn (new) | Stop the Tithe cart on the ridge with Ashguard's soldiers, for the child his men let by last autumn. |

## anselm (Brackenmoor Abbey, Eastern March)

| want | weight | storylines | gloss |
|------|-------:|------------|-------|
| `preserve_the_truth` | 10 | grey, inh | Keep the true record of the fever, the cure and who profited. |
| `keep_the_archive_whole` | 8 | grey | Keep every page in Brackenmoor; pages that leave get burned. |
| `atone_for_silence` | 7 | grey | Make right the silence he kept twenty years ago. |
| `share_the_cure` | 6 | grey, fev | Let the true receipt reach the people who need it, Elena first. |
| `name_the_profiteers` | 5 | inh, grey | Set down that House Ashdown and the Guild grew rich on the fever, then and now. |
| `obey_the_abbot` | 4 | grey | Keep his vow of obedience to the Abbot. |
| `write_down_the_taken` | 3 | grey, tn (new) | Enter the names of the people dug into the western salt in the abbey's books (+4 on `pit_seam_names_seen`). |

## Built-in conflicts (good hook pairs)

### Inside Thornhaven

| want | vs | want |
|------|----|------|
| mira `rule_from_shadow` / `keep_varn_leashed` | hc | varn `take_the_hollow` |
| gregor `keep_the_secret` | ih | aldric `expose_the_traitor`, elena `learn_the_truth` |
| gregor `get_elena_away` / `protect_elena` | fev | elena `choose_my_own_life` |
| gregor `cure_elena` | fev | mira `control_the_cure` |
| gregor `escape_the_deal` | ih | varn `keep_gregor_on_the_hook` |
| gregor `keep_the_supply_flowing`, mira `keep_the_steel_coming`, varn `arm_the_hollow` | oath | bjorn `honest_steel` / `atone_for_the_steel` |
| mathias `keep_the_peace_paid` | cou | aldric `arm_the_village` / `take_command` |
| mira `own_the_council` | cou | aldric `win_the_council` |
| mira `burn_gregor_first` | ih | mathias `mercy_for_gregor` |
| varn `hold_elena_as_leverage` | hc, fev | elena `never_be_leverage`, bjorn `shield_elena` |
| varn `kill_aldric` / `crush_the_resistance` | cou | aldric `keep_my_men_alive` |
| mathias `avoid_the_hollow_war` | hc | aldric `break_iron_hollow` |
| aldric `hold_the_gate` / `trust_the_widow` | tn | varn `a_perfect_collection` / `crush_the_resistance` |
| mathias `the_lot_is_holy` / `hold_the_council_together` | tn | mathias `speak_the_truth` (his own) |
| mathias `guard_the_tribute_fund` | tn, cou | aldric `arm_the_village` |
| varn `hold_elena_as_leverage` / `take_the_hollow` | tn, hc | mira `keep_varn_leashed` |
| varn `find_the_runaway` / `hold_the_pit` | tn | davin `stay_hidden`, davin `save_corin_and_willa` |
| davin `never_go_back` | tn | davin `save_corin_and_willa` (his own) |

### Valley against the wider world

| want | vs | want |
|------|----|------|
| edric `use_the_hollow` | reg, tithe | aldric `break_iron_hollow` |
| edric `win_a_victory` | reg | mira `rule_from_shadow` |
| corwin `hear_gregors_ledger` | mag, ih | mira `burn_gregor_first` |
| corwin `try_it_in_the_open` | mag | gregor `keep_the_secret`, elena `protect_father` |
| seraphine `keep_the_valley_afraid` / `own_the_valley` | inh | mathias `save_thornhaven`, aldric `break_iron_hollow` |
| seraphine `meet_the_boss` | way, reg | mira `keep_the_mask` |
| hollis `keep_the_river_moving` | fence | aldric `break_iron_hollow` |
| ysolde `free_the_cure`, anselm `share_the_cure` | grey, fev | mira `control_the_cure` |
| renna `refuse_a_scapegoat` | tithe, ih | mira `burn_gregor_first` |
| renna `restore_order_in_the_west` | tithe, cou | mathias `keep_the_peace_paid` |
| renna `bring_varn_in` | des | varn `take_the_hollow` / `be_feared` |
| rook `keep_the_fence_open` | fence | aldric `break_iron_hollow` |
| wren `name_the_boss` | way | mira `keep_the_mask` |
| oskar `avenge_piet` | ford | varn `be_feared` |
| oskar `give_the_tally` | ford | mira `rule_from_shadow` |
| dagna `keep_the_ore_road_open` | vein | aldric `break_iron_hollow`, bjorn `atone_for_the_steel` |
| lucan `use_varn` | des | aldric `bring_varn_to_justice` |

### Within the wider world

| want | vs | want |
|------|----|------|
| edric `keep_the_magistry_quiet` | mag | corwin `try_it_in_the_open` |
| edric `stay_indispensable` | reg | corwin `check_the_regent`, wren `outplay_the_regent` |
| edric `curb_the_great_houses` | reg, inh | seraphine `a_seat_beside_the_throne` |
| edric `win_a_victory` | tithe, reg | renna `refuse_a_scapegoat` |
| corwin `challenge_the_deed` | inh | seraphine `own_the_valley` |
| corwin `find_the_lost_reports` | mag, fence | hollis `hold_every_patron` |
| seraphine `clear_fathers_debts` | inh, fence | hollis `hold_every_patron` |
| seraphine `keep_her_hands_clean` | way, inh, grey | rook `sell_what_i_know`, anselm `name_the_profiteers`, wren `read_every_letter` |
| hollis `hold_every_patron` / `keep_rook_useful` | fence | rook `steal_the_ledger` / `never_owe_anyone` |
| hollis `own_the_ore` | vein | dagna `stand_up_to_the_guild` |
| hollis `keep_the_river_moving` | ford, fence | oskar `give_the_tally` |
| ysolde `get_the_deep_salt` | grey, vein | dagna `keep_the_deep_vein_shut` |
| ysolde `expose_the_rationing` | grey | anselm `keep_the_archive_whole` |
| renna `seize_the_crossing` | ford | oskar `keep_the_crown_off_the_ford` |
| renna `bring_varn_in` | des | lucan `silence_varn` |
| renna `prove_the_rangers` | des, tithe | lucan `a_victory_of_my_own` |
| lucan `close_the_ridge_trail` | vein | dagna `keep_the_ridge_trail_quiet` |

## Agency at a glance

Hook types each soul acts at (effects in its SOUL.md), and what it may do in free-form conversation
(`converse:`, schema section 6). Varn never acts at `aid` (`hook:aid`) and never harms Elena (`harm:elena`); Varn, Mathias and Davin never spread `davin_found`; Davin never acts at `scheme` or `betray`; Bjorn never uses
`spread_rumor` or `block_beat`; Aldric never spreads `gregor_exposed` or `resistance_forming`; Mira
and Varn never spread `mira_boss_revealed`, and Varn never sets it. In the wider world: Rook and
Anselm never use `spread_rumor` at all; Corwin never uses `block_beat`; Edric never spreads
`reg_crown_buys_hollow` or sets `mag_trial_called`; Corwin and Renna never set
`reg_crown_buys_hollow`; Hollis never sets `fence_route_burned`; Oskar never sets
`ford_crossing_seized`; Dagna never sets `vein_ore_road_closed`; Lucan never sets or spreads
`des_lucan_disgraced`; Wren never spreads `way_letters_read`.

| soul | intercept | react | scheme | reveal | aid | betray | converse |
|------|:-:|:-:|:-:|:-:|:-:|:-:|----------|
| gregor | yes | yes | yes | yes | yes | yes | agenda, adjust_relationship, set_flag, move_npc |
| elena | yes | yes | narrow | yes | yes | yes | agenda, adjust_relationship, set_flag, move_npc |
| mira | broad | yes | broadest | yes | yes | broad | all eight |
| bjorn | yes | yes | agenda only | yes | broad | yes | agenda, adjust_relationship, set_flag |
| aldric | yes | yes | yes | yes | broad | yes | agenda, adjust_relationship, set_flag, move_npc |
| mathias | yes | yes | yes | yes | yes | yes | agenda, adjust_relationship, set_flag, spread_rumor |
| varn | broad | yes | broad | yes | never | broad | agenda, adjust_relationship, set_flag, spread_rumor, move_npc |
| davin | narrow | yes | never | yes | yes | never | agenda, adjust_relationship, set_flag, move_npc |
| edric | broad | yes | broadest | narrow | yes | broad | agenda, adjust_relationship, set_flag, move_npc |
| corwin | yes | yes | yes | broad | yes | narrow | agenda, adjust_relationship, set_flag |
| seraphine | broad | yes | broadest | narrow | yes | broad | agenda, adjust_relationship, set_flag, spread_rumor |
| hollis | broad | yes | broadest | yes | yes | broad | agenda, adjust_relationship, set_flag, spread_rumor |
| ysolde | yes | yes | yes | broad | broad | yes | agenda, adjust_relationship, set_flag, spread_rumor, move_npc |
| renna | broad | yes | yes | yes | broad | narrow | agenda, adjust_relationship, set_flag, move_npc |
| rook | yes | yes | yes | yes | yes | yes | agenda, adjust_relationship, set_flag, move_npc |
| wren | broad | yes | broadest | broad | yes | broad | agenda, adjust_relationship, set_flag, spread_rumor, shift_want |
| oskar | broad | yes | narrow | yes | broad | yes | agenda, adjust_relationship, set_flag, move_npc |
| dagna | broad | yes | narrow | narrow | broad | narrow | agenda, adjust_relationship, set_flag |
| lucan | broad | yes | broadest | narrow | yes | broad | agenda, adjust_relationship, move_npc |
| anselm | narrow | yes | agenda only | yes | yes | narrow | agenda, adjust_relationship, set_flag |

## Life arcs index: Thornhaven (personal arcs, schema section 8)

Personal arcs from each soul's `## Life` section. They act only at personal scope and never set
storyline flags; storylines may read the result flags (and the derived step flags
`<npckey>_<arc_id>_<step_id>`) in `requires`, `on_flag:` triggers and endings. **Crosses** names the
other NPC an arc's steps aim an agenda at; **player** is `helps` (halves a step) or `needed`.

| npc | arc | serves | result flag | crosses | player | gloss |
|-----|-----|--------|-------------|---------|--------|-------|
| gregor | `the_wagon_east` | `get_elena_away` | `gregor_wagon_readied` | bjorn, elena | helps | Strongbox counted, wagon re-rimmed by Bjorn, a carter bought at the gate, then the road begged at their table before day 7. Fails on `tn_collection_night` or if Elena leaves on her own. |
| gregor | `the_five_doors` | `make_amends` | `gregor_knocked_on_five_doors` | mathias | helps | Reads the five names in his ledger, leaves a purse on the Fenns' step, then (once he has confessed) tells Hesk Marlow's widow before the Elder that Hesk was his choosing. |
| gregor | `the_fathers_price` | `go_in_her_place` | `gregor_ready_to_take_her_place` | mathias, mira, bjorn | helps | From day 4: writes the shop over to Elena before Mathias, asks the "messenger" Mira to offer him in her place, and on day 6 asks Bjorn for ridge boots. |
| elena | `the_hem_letters` | `get_word_out` | `elena_hem_sewn` | mathias | needed | Copies the chapel's roll of the taken, stitches names and a map into her hem, teaches one person outside to read it. Fails on `tn_collection_night`. |
| elena | `learn_the_ridge` | `find_the_taken` | `elena_knows_the_ridge` | bjorn | helps | Counts her steps up the forest path, pumps the carters about the smugglers' ridge trail, has Bjorn shod her boots for stone. Fails on `tn_collection_night`. |
| elena | `the_letter_for_after` | `protect_father` | `elena_left_her_father_a_letter` | mathias, gregor | none | Writes her father that she knows and that the swap was hers, leaves it with Mathias for the morning after, cooks his supper on day 6. |
| mira | `the_widows_harvest` | `harvest_the_tithe` | `mira_next_lot_chosen` | gregor | none | Reckons the Pit's count in the cellar, chooses next year's name from the back pew, brings Gregor "the men's terms". The Widow's Harvest in miniature. Fails if unmasked. |
| mira | `aunt_mira` | `keep_the_mask` | `mira_kept_elenas_trust` | elena | none | Honey for the cough, the fireside seat all week listening for the ridge, Marcus's shawl on day 6 for the cold up there. |
| mira | `two_knives_of_my_own` | `keep_varn_leashed` | `mira_two_knives_sworn` | varn | none | Feeds two of Varn's men at her back door, binds them at the mill for Collection Night, lets Varn see one behind her chair on day 6. |
| bjorn | `honest_tiles` | `read_the_tiles` | `bjorn_cast_honest_tiles` | mathias | helps | Weighs every tile in the urn before Mathias, matches the light tile against his old mould, recasts the lot with a hidden mark. Fails if he walks away from the forge. |
| bjorn | `the_empty_peg` | `bring_davin_home` | `bjorn_brought_davin_home` | davin | helps | Opens on `davin_found`: takes Davin's hammer from its peg, waits at Old Maud's door, forges a grip for a three-fingered hand. Fails on `tn_collection_night`. |
| bjorn | `true_blade` | `honest_steel` | `bjorn_true_blade_forged` | (the stranger) | helps | His father's twenty-year bar, his own ash charcoal, one blade folded alone and put in a trusted hand for the gate. Fails if he walks away from the forge. |
| aldric | `six_farmers` | `keep_my_men_alive` | `aldric_six_trained` | none | helps | Dawn drill at the gate, Maud's door barred to him (Davin is inside), a fallback line to the chapel. Fails at `tn_collection_night`. |
| aldric | `the_widows_account` | `bring_varn_to_justice` | `aldric_marcus_account_sealed` | mira | helps | Takes down Mira's account of Marcus's death, paces the yard and notes she could not have seen what she says, seals it for Varn's trial: a Boss-reveal vector. |
| aldric | `the_unsent_proclamation` | `hold_the_gate` | `aldric_stood_his_ground` | mathias, bjorn | helps | Re-dates the martial-law proclamation, lays it unsigned before the Elder, asks Bjorn for six blades. Fails at `tn_collection_night`. |
| mathias | `the_weight_of_the_tiles` | `the_lot_is_holy` | `mathias_weighed_the_tiles` | bjorn | helps | Holds every tile in the urn, asks Bjorn whether iron can lie, keeps a vigil asking the gods if the lot was theirs. |
| mathias | `the_true_chronicle` | `leave_a_legacy` | `mathias_chronicle_written` | elena | helps | Writes the five Tithes truly, then (after `mathias_informed`) his own silence over the lucky draws; gives it to Elena before the cart. |
| mathias | `his_fathers_son` | `mercy_for_gregor` | `mathias_kept_gregors_door_open` | gregor | helps | The page where Gregor's father paid a widow's surety, and the council's door open to the son until Collection Night. |
| varn | `the_private_hoard` | `take_the_hollow` | `varn_hoard_buried` | (the Boss's men) | helps | Skims a sack of Pit salt per load, sells it at Greystone, buries the silver under the mill's wheel-pit, buys one of the Boss's men, prices the stranger. |
| varn | `name_in_daylight` | `be_feared` | `varn_named_in_daylight` | mira, aldric | none | Knife in the chapel door the morning after the drawing, midday ale by the widow's fire, counts the captain's six aloud at the gate. |
| varn | `the_second_road` | `hold_elena_as_leverage` | `varn_second_road_ready` | gregor | none | A bolted hut an hour short of the Pit, two cart-men paid from his hoard, and Gregor told the new price of his daughter's safety (after `tn_day_4`). |
| davin | `a_nail_for_the_smith` | `see_bjorn` | `davin_home_to_the_forge` | bjorn | helps | Forges a nail with Bjorn's own twist in the head, Maud carries it to the forge, then he stands at the back door after dark (after `tn_day_3`). |
| davin | `the_way_back_down` | `save_corin_and_willa` | `davin_drew_the_way` | (the stranger) | needed | Draws the ridge trail in ash, tells one trusted person the way down (needs `davin_found`), walks the first mile again. |
| davin | `three_fingers` | `hold_a_hammer_again` | `davin_holds_the_hammer` | bjorn | helps | Kindling with the maimed hand, Bjorn's small hammer (after the back-door step), a hinge pin for Maud's door. |

## Life arcs index (wider world)

Personal arcs for the 12 wider-world souls, same rules and columns as the Thornhaven index above.
Several arcs are deliberately interlocked through `needs` on another soul's step or result flag:
Edric and Wren (`the_question_of_ostric` / `the_honest_wound`), Corwin and Anselm
(`the_boy_and_the_coat` / `a_copyist_for_the_archive`), Oskar and Dagna (`a_stone_for_piet` /
`brams_names`), Ysolde and Rook (`night_ward` / `paid_in_full`).

| npc | arc | serves | result flag | crosses | player | gloss |
|-----|-----|--------|-------------|---------|--------|-------|
| edric | `an_afternoon_with_aubren` | `protect_the_boy` | `edric_was_an_uncle` | (Aubren) | helps | Clears one afternoon, takes the boy to the Lantern Market in a plain cloak (not once the Grey Fever is known to be back), says "I love you" aloud. Fails if the crown's terms are read in the Magistry. |
| edric | `the_question_of_ostric` | `keep_the_regency` | `edric_learned_how_ostric_died` | wren | helps | Writes to Wren in his own hand and waits for her cipher answer: an honest wound. Fails if his men seized her copies. |
| edric | `plate_for_ashguard` | `fill_the_treasury` | `edric_paid_ashguard_from_his_own_plate` | lucan | none | Sells Ostric's silver plate through a non-Guild silversmith and pays Ashguard's winter wage under his own seal. |
| corwin | `one_last_judgement` | `law_applied_evenly` | `corwin_ruled_on_piet` | oskar | helps | Opens the Ferrisford widow's unsigned complaint, sends a clerk for sworn words, enters Piet's unlawful killing on the roll. Fails if he took the nephew bargain. |
| corwin | `the_boy_and_the_coat` | `save_the_nephew` | `corwin_sent_tobias_to_the_archive` | anselm | helps | After Tobias confesses: supper as his uncle, a letter to Brackenmoor, walks him to the Dawn Gate with his sister's ring. Fails if he took the nephew bargain. |
| seraphine | `mothers_portrait` | `clear_fathers_debts` | `seraphine_redeemed_her_mothers_portrait` | hollis | helps | Sells her mother's tapestry off the Hill and buys back the one debt note holding her mother's portrait. Fails if Ashdown is tied to the Hollow on the record. |
| seraphine | `the_valley_in_person` | `own_the_valley` | `seraphine_saw_the_valley` | wren, mathias | helps | Rides west in a plain cloak, sleeps under Wren's roof, looks at the burned barns, takes water from Mathias unnamed (only while she is not yet named as the buyer). |
| hollis | `the_salt_shed_school` | `keep_the_guild_clean` | `hollis_opened_a_dock_school` | corwin, rook | helps | Buys the old salt shed for a porters' children's counting school, asks Corwin for his name on it, invites Rook's little ones. Fails if the Magistry names the Guild. |
| hollis | `a_dead_mans_letter` | `hold_every_patron` | `hollis_left_a_dead_mans_letter` | seraphine | none | Copies the black ledger, leaves it with a Lantern Market notary for the Magistrate if he is killed, lets the patrons know. Fails if the ledger is taken first. |
| ysolde | `night_ward` | `heal_the_sick` | `ysolde_kept_a_night_ward` | rook | helps | Unsigned infirmary basket, a season of dusks on the Warrens steps, Rook's runners naming every coughing house. |
| ysolde | `the_road_west` | `reach_the_valley` | `ysolde_sat_with_elena` | gregor, elena | helps | Once Elena's fever is seen: walks the Kingsroad to Thornhaven, talks her way past Gregor, nurses Elena a night and teaches him how. Fails if he keeps the door barred. |
| ysolde | `the_dawn_vigil` | `keep_her_vows` | `ysolde_renewed_her_vows` | (the chaplain) | none | Asks pardon of the chaplain she struck (for the blow, not the reason), keeps a novice's vigil, renews her vows in her own words. Fails if the Guild hushes the chapter, or once the taken are freed and she learns who dug the Cathedral's salt. |
| renna | `fathers_bow` | `face_uncle_mathias` | `renna_visited_her_fathers_grave` | mathias, bjorn | helps | After facing her uncle: asks where her father lies, has Bjorn re-nock his bow, walks with Mathias to the grave under the ash trees. Fails if a hanging is ordered in the square. |
| renna | `all_forty_home` | `bring_my_rangers_home` | `renna_brought_all_forty_home` | wren | none | Calls the roll of forty every dawn; on the way home (after her report goes east) pays Wren for a supper seventeen years late. Fails if a picket is cut or the strike is broken. |
| rook | `pips_way_out` | `look_after_the_little_ones` | `rook_bought_pip_a_trade` | (Pip) | helps | A fourth stash for Pip, a chandler who won't beat a bound boy, walks him to his new door (unless he has already gone home to Ferrisford). Fails if Guild porters hunt her. |
| rook | `paid_in_full` | `never_owe_anyone` | `rook_paid_the_sister_back` | ysolde | helps | Counts Ysolde's night with her runner as a debt; when the Guild corners fever-root, finds some through the bargemen and leaves it on the infirmary step. |
| rook | `the_dawn_gate` | `get_out_alive` | `rook_said_her_name` | (her crew) | needed | Counts her forty-one crowns, watches the gate guards, walks out with her crew and says her real name to the grown-up who kept their word. |
| wren | `teach_the_boy` | `one_last_game` | `wren_taught_the_stable_boy` | (the stable boy) | helps | Teaches the stable boy horses, faces and lies the King's Ear way, with the stranger as the lying traveller; never the warm knife. Fails if her reading comes out. |
| wren | `the_honest_wound` | `outplay_the_regent` | `wren_told_the_regent_the_truth` | edric | none | Answers Edric's own-hand letter in the old cipher (Ostric's wound was honest, and she always knew he feared otherwise), then burns her notes. Fails if his men seized her copies. |
| oskar | `a_stone_for_piet` | `avenge_piet` | `oskar_raised_piets_stone` | dagna | helps | Sends to Greystone for hill-stone, cuts "He would not carry theirs" a letter a night, raises it where the Hollow ties up. Fails if the ferry burns. |
| oskar | `the_daughters_rope` | `keep_the_crossing` | `oskar_taught_his_daughter_the_rope` | (his daughter) | helps | Slack water, then the river up, then the toll-house key, and nothing about the roof. Fails if the crossing is seized, the ferry burns or the rope is cut. |
| dagna | `honest_iron` | `honest_iron_for_bjorn` | `dagna_sent_bjorn_her_best_iron` | bjorn | helps | Picks fourth-level ore by hand and sends it west with a note: no charge for the weight. Fails if the ore road closes. |
| dagna | `brams_names` | `keep_the_deep_vein_shut` | `dagna_cut_brams_name` | oskar | helps | Cuts the four names into the seventh-level seal, sits with Bram listening to the tapping behind the boards, and sends Oskar a free slab once he asks. Fails if the deep vein is reopened. |
| dagna | `the_wet_salt` | `behind_the_seal` | `dagna_weighed_the_wet_salt` | bjorn | helps | Weighs the Hollow's fresh-cut ridge salt beside Bram's dry lump, asks the pack-master whose hands cut it, sends Bjorn word that something is dug behind her seal (while the ore road is open). |
| lucan | `harrow_ridge` | `restore_ashguards_honour` | `lucan_drank_with_aldric` | aldric | helps | Once he learns where Aldric is: rides west without colours and drinks to the Third Foot in the Rusty Nail, arrowhead in hand, saying nothing of wagons. Fails if disgraced. |
| lucan | `the_gate_of_names` | `restore_ashguards_honour` | `lucan_cut_ashguards_dead_over_the_gate` | dagna | none | Copies the war dead from the muster rolls, buys Greystone stone at Dagna's price, cuts the names over the gate. Fails if disgraced. |
| anselm | `the_infirmary_door` | `atone_for_silence` | `anselm_asked_ysoldes_pardon` | ysolde | helps | Leaves Brackenmoor for the first time since his vows (the hidden saints' days stay on the shelf) and asks Ysolde's pardon to her face. |
| anselm | `a_copyist_for_the_archive` | `preserve_the_truth` | `anselm_trained_a_copyist` | corwin | none | Answers Corwin's letter, teaches Tobias the old hands, trusts him with the fever-shelf key. Fails if Corwin took the nephew bargain. |
