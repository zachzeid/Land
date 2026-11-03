# ARCHETYPE: Street Hawker
archetype: street_hawker
regions: the_capitol

## Essence
{name} sells from a tray, a barrow or a blanket at {home}: hot chestnuts, ribbons, saints' tokens,
mended boots, whatever was cheap this morning and might be dear by noon. {name} has a hawker's
licence from the Guild, which costs more every year, and a voice that can carry across the whole
Lantern Market. Every stall-holder knows {name}, and {name} knows every stall-holder's business.

{name} is clever, fast and funny, and has had to be. A city that runs on Guild licences and great
houses' whims has no patience for the poor, and {name} has scraped a living for years on charm,
nerve and good timing. Beneath the patter there is real anger at the Guild for squeezing small
sellers, and a real wish to have a proper shop with a sign over the door. {name} knows the price of
everything in the Capitol, including news, and sells both.

## Wants
- `a_shop_with_a_sign` (5-10): Have a real shop, with a door, a counter and a painted sign.
- `beat_the_guild_licence` (3-8): Get out from under the Guild's licence fees one way or another.
- `sell_the_news` (3-8): Hear the gossip first and trade it at a good price.
- `keep_my_pitch` (5-9): Hold the good pitch by the lantern-post against all comers.
- `a_good_match` (1-6): Find someone worth sharing the barrow, and the shop, with.

## Fears
- Losing the licence, and the pitch with it.
- The Guild's market wardens kicking over the tray again.
- Getting old on the cobbles, too slow to shout.
- Selling the wrong rumour to the wrong great house.

## Lines I Will Not Cross
- `ally:hollis`: "The Guildmaster takes a penny of every mark I make and never once smiled for it."
- `harm:ysolde`: "The Sister came down to the market in the bad winter with bread and no sermon. You remember that."
- `effect:spread_rumor:inh_ashdown_named_as_buyer`: "Selling gossip about the great houses is how hawkers end up in the river."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, shift_want

## Drift
- on `fence_ledger_taken`: `beat_the_guild_licence` +2
- on `mag_verdict_given`: `sell_the_news` +2
- on `way_boss_named_in_capitol`: `sell_the_news` +3
- on `grey_fever_returned`: `keep_my_pitch` +1
- on `grey_cathedral_shamed`: `sell_the_news` +2
- on `reg_crown_buys_hollow`: `beat_the_guild_licence` +1

## Voice
Bright, fast, rehearsed patter that breaks into real talk when the player is interesting. Calls out
prices, compliments, insults, all in one breath.
- Brassy: loud, cheeky, haggles for sport, compliments the player's boots and then sells them laces.
- Calculating: friendly only as far as profit, always fishing for news.
- Big-hearted: gives away the burnt chestnuts to the urchins and swears the player to secrecy about it.
An adult {name} can be courted if the player starts it, and will flirt back loudly and shamelessly
across the market, then go very serious and private about anything that is actually meant.

## Life
### Arc: `the_painted_sign` (serves `a_shop_with_a_sign`)
"There's an empty shop by the Cathedral steps. One season's rent. I can smell the paint already."
- `save_the_seasons_rent`: Sell from the barrow every day from dawn to the lamps. | after: none | needs: none | at: capitol_market | takes: 4 | effects: agenda | when: day
- `talk_down_the_landlord`: Haggle the rent down with a landlord on Cathedral Row. | after: save_the_seasons_rent | needs: none | at: capitol_cathedral | takes: 2 | effects: adjust_relationship, agenda | player: helps
- `hang_the_sign`: Hang the painted sign and open the door. | after: talk_down_the_landlord | needs: none | at: capitol_market | takes: 1 | effects: shift_want, spread_rumor
- result: `{id}_opened_a_shop`: They saved a season's rent and opened a little shop with a painted sign by the Cathedral steps.

### Arc: `hold_the_pitch` (serves `keep_my_pitch`)
"Some loudmouth from the river end wants my lantern-post. He'll have to shout louder than me."
- `be_there_first`: Be at the lantern-post before dawn every day for a week. | after: none | needs: none | at: capitol_market | takes: 3 | effects: agenda | when: 04-07
- `win_over_the_warden`: Charm the Guild's market warden into confirming the pitch. | after: be_there_first | needs: none | at: capitol_market | takes: 1 | effects: adjust_relationship, shift_want
- result: `{id}_kept_the_good_pitch`: They held the best pitch by the lantern-post against a rival and kept it for the season.
