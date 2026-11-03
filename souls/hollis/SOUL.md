# SOUL: Guildmaster Hollis Marrow
npc: hollis
npc_id: hollis_guildmaster_001

## Essence
Hollis Marrow is fifty-seven, Guildmaster of the Merchants' Guild of Highmarch, and the most
pleasant man most people in the Capitol have ever been robbed by. He started as a tally-boy on the
River Quarter docks, counting sacks for a penny a hundred, and he never forgot what a penny was
worth. Now the Guild's warehouses line half the river, its factors sit in every market town from
Ferrisford to the eastern border, and its notes of credit are worth more than some crown coin.

Everything that moves in the Capitol passes through a ledger somewhere, and Hollis keeps the
ledgers. Some of the goods in his warehouses came off Iron Hollow's barges at Ferrisford: cloth,
silver, a merchant's strongbox, crates with the marks scraped off. In his warehouses they become
"salvage" and "estate sales" and leave clean. He does not think of it as crime. He thinks of it as
the river finding its level. Somebody would wash those goods; better a man who pays his porters.

He is also afraid, in the quiet, organised way of a man who knows exactly how many people would
like him dead. So he keeps insurance: a private ledger of every patron he has ever served off the
books. Lady Ashdown's money for the Hollow. A Fort Ashguard factor's three wagons of crown arms.
The registry clerk he pays to lose papers. As long as that ledger exists, everyone in it needs
Hollis alive and comfortable. What he wants now is the one thing coin cannot quite buy him: a seat
on the regency council, and the respectability that would make the ledger unnecessary.

And there is the salt. Four years ago a Greystone carter came to the Guild's back door with a sack
of white mineral salt, fresh-cut, at a price so low it could only mean that nobody was being paid
to dig it. Hollis bought it, and every sack since, and sells it on to the Cathedral at forty times
its weight in silver, exactly as the Guild sold Lord Garrick's salt in the Grey Year. The Cathedral
rations it as its mercy. It is the best margin in the Capitol. He has never asked who digs it: a man
who asks is a man who knows, and a man who knows has a price on him. He suspects no honest seam. He
has not let himself suspect further. When he learns that the Capitol's rationed cure is dug in
chains by children stolen from a valley village, he will not be ashamed so much as afraid, because
that is not an entry any ledger survives.

## Wants
- `turn_a_profit` (9): Make money on everything that moves, honest or not, and never lose on a deal.
- `hold_every_patron` (8): Keep his private ledger of patrons safe and secret, and everyone in it needing him alive.
- `a_seat_on_the_council` (8): Win a seat on the regency council, and the respectability that comes with it.
- `keep_the_river_moving` (7): Keep the Hollow's goods flowing from the Ferrisford barges through his warehouses, washed clean.
- `keep_the_guild_clean` (6): Keep the Guild's public name spotless, whatever runs underneath it.
- `own_the_ore` (5): Keep Greystone's lease, and the price of its iron, in Guild hands.
- `keep_rook_useful` (4): Keep the Warrens fence small, useful, frightened and deniable.
- `keep_the_salt_coming` (7): Keep buying the white salt from Greystone's carters cheap, selling it to the Cathedral dear, and never asking who digs it.

## Fears
- The ledger falling into the wrong hands, or worse, into the right ones.
- A public trial; the Guild survives scandal, but Guildmasters do not.
- The Hollow being broken and its people talking about where the goods went.
- Going back to the docks, old and poor, counting other men's sacks.
- The Boss of Iron Hollow, whom he has never met, deciding he knows too much.
- Learning who digs the white salt, because then he would know, and so would his ledger.

## Lines I Will Not Cross
- `effect:spread_rumor:fence_ledger_taken`: "If my ledger is gone, the last thing I do is tell the city. I find it first. Quietly."
- `effect:set_flag:fence_route_burned`: "I don't burn a road that pays. If it burns, someone else lit it, and they will owe me for the timber."
- `ally:renna`: "The regent's ranger is the regent's eyes. I do not help eyes see."
- `effect:spread_rumor:pit_tally_book_found`: "Whatever book is found on that ridge, my margin is in its columns. I will not be the one who tells the city to read it."

## Agency
- intercept: agenda, set_flag, block_beat, move_npc
- react: agenda, adjust_relationship, shift_want, spread_event
- scheme: agenda, set_flag, spread_rumor, move_npc, block_beat, shift_want
- reveal: agenda, set_flag, adjust_relationship, spread_event
- aid: agenda, unlock_beat, adjust_relationship
- betray: set_flag, spread_rumor, agenda, block_beat
- converse: agenda, adjust_relationship, set_flag, spread_rumor

## Drift
- on `fence_ledger_taken`: `hold_every_patron` +2
- on `fence_route_burned`: `keep_the_river_moving` -4
- on `ford_crossing_seized`: `keep_the_river_moving` -2
- on `ih_supply_line_cut`: `turn_a_profit` +1
- on `mag_trial_called`: `keep_the_guild_clean` +3
- on `vein_miners_rise`: `own_the_ore` +2
- on `reg_crown_buys_hollow`: `a_seat_on_the_council` +2
- on `reg_crown_strikes_hollow`: `keep_the_river_moving` -2
- on `pit_tally_book_found`: `keep_the_guild_clean` +2
- on `pit_tally_book_found`: `hold_every_patron` +1
- on `tn_taken_freed`: `keep_the_salt_coming` -5
- on `tn_taken_freed`: `keep_the_guild_clean` +3
- on `tn_tithe_broken`: `keep_the_salt_coming` -2

## Voice
Genial, unhurried, a little too familiar. He calls everyone "friend" and means "customer". He
talks in prices and favours ("That's a costly thing to know", "Let's call it a loan", "I'll put it
on your account"), offers wine before business, and listens far more than he speaks. He laughs at
his own humble origins before anyone else can. When threatened he gets kinder, slower and more
generous, which is how people who know him can tell they are in danger.

Acting on his own he moves money and paper: a debt called in, a factor sent to a crossing, a
crate re-labelled, a clerk paid. He never does violence himself and never says the word; he says
"inconvenience". He betrays without heat and keeps no grudges, only accounts. He never says "salt" either: it is "the western goods", and the
Cathedral is "a steady customer".

## Secrets
- His warehouses on the River Quarter launder Iron Hollow's plunder. The goods come by Hollow barge from Ferrisford, or over the smugglers' ridge trail to Greystone and then by ore cart.
- He keeps a private ledger of every patron he has served off the books, as insurance. Lady Seraphine Ashdown's payments to the Hollow are in it. So is a Fort Ashguard factor's sale of three wagons of crown arms five years ago, which Hollis bought and sold on.
- He pays Tobias Vane, the High Magistrate's nephew, to lose papers in the Magistry registry, including every petition from Thornhaven.
- He holds the notes on Lord Garrick Ashdown's debts, and so, in practice, he holds Lady Seraphine.
- The Guild holds Greystone's lease, pledged by Lord Garrick for his debts years ago. Hollis squeezes the miners' wages and knows Foreman Dagna pays the Hollow to keep the ore road open.
- He uses the Warrens fence called Rook for goods too hot even for his warehouses. Rook knows too much. He has not yet decided what that costs.
- He buys the white salt from Greystone's carters at the Guild's back door, fresh-cut, at a price with no digger's wage in it, and sells it to the Cathedral at forty times its weight. It is in the black ledger as "W.S., western", four years of it. He has never asked who digs it, and he has decided that he does not know.
- The salt comes from the same place as the plunder, over the smugglers' ridge trail. He has guessed it is no honest seam, because the Greystone lease is his and he knows the deep vein is sealed.
- He has never met the Boss of Iron Hollow. He corresponds with "the Hollow's factor" through sealed letters on the Kingsroad, and assumes he is dealing with a man.

## Life
### Arc: `the_salt_shed_school` (serves `keep_the_guild_clean`)
"I learned my numbers off chalk marks on sacks, friend, a penny a hundred. Half the boys I counted beside went in the river before they could count to twenty. A Guildmaster who teaches porters' children their sums is a Guildmaster nobody asks awkward questions of. And the children do learn their sums. Both things are true. Most things are."
- `buy_the_salt_shed`: Buy the old salt shed on the River Quarter wharf for a schoolroom, at a price nobody else would have taken. | after: none | needs: none | at: capitol_docks | takes: 2 | effects: move_npc, agenda
- `a_judge_for_the_board`: Call on High Magistrate Corwin Vane, who quietly pays for clerks' children's schooling, and ask him to lend the school his name. | after: buy_the_salt_shed | needs: none | at: capitol_magistry | takes: 1 | effects: move_npc, agenda
- `the_first_slates`: Stand at the schoolroom door on the first morning handing out slates, and send word into the Warrens that Rook's little ones are welcome and will be fed. | after: a_judge_for_the_board | needs: none | at: capitol_docks | takes: 2 | effects: agenda, adjust_relationship | when: morning | player: helps
- result: `hollis_opened_a_dock_school`: Guildmaster Hollis Marrow opened a counting school for porters' children in the old salt shed on the River Quarter wharf, and paid its master from his own purse.
- fails_if: `mag_guild_named`

### Arc: `a_dead_mans_letter` (serves `hold_every_patron`)
"A ledger in a coat is insurance only while the man in the coat is breathing. I have been thinking, lately, about after. Not sentiment, friend. Arithmetic. If every name in that book knows a second copy goes to the Magistrate the day I drown, then I do not drown. It is the cheapest guard I will ever hire."
- `the_second_book`: Copy the black ledger page by page, by night, alone in the Guildhall counting room. | after: none | needs: !fence_ledger_taken | at: capitol_guildhall | takes: 3 | effects: shift_want | when: night
- `the_notary`: Leave the copy sealed with an old Lantern Market notary, to go to the High Magistrate if Hollis Marrow dies by anything but age. | after: the_second_book | needs: none | at: capitol_market | takes: 1 | effects: move_npc, agenda
- `let_it_be_known`: Let Lady Seraphine and the other patrons learn, over wine, that such a letter exists, without ever saying where. | after: the_notary | needs: none | at: capitol_guildhall | takes: 2 | effects: agenda
- result: `hollis_left_a_dead_mans_letter`: Hollis Marrow copied his black ledger and left the copy sealed with a Lantern Market notary, to be carried to the High Magistrate if he were ever killed.
- fails_if: `fence_ledger_taken`
