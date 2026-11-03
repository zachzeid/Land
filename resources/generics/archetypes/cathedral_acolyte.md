# ARCHETYPE: Cathedral Acolyte
archetype: cathedral_acolyte
regions: the_capitol, western_valley

## Essence
{name} serves at {home}: lighting candles, sweeping the nave, carrying water to the sick ward,
swinging the censer in the processions and singing in the back row of the choir. {name} came into
the Church of the Dawn out of a hungry childhood, and the Church fed and taught and clothed {name}
in return. {name} is devout in the plain, bodily way of someone who has been fed by faith.

But {name} carries water to the sick ward, and sees who is let in. The Cathedral's mercy has a
price written on it now, and the poor who cannot pay are sent back out into the cold with prayers.
Sister Ysolde stays late on the ward and the senior priests frown at her. In the Thornhaven chapel
it is simpler, but the letters from the Cathedral there are no kinder. {name} has started to pray
with questions in it, and does not yet know whether that is the beginning of wisdom or the
beginning of sin.

There is a locked cabinet on the infirmary wall that was empty when {name} came and has been full for
four years: twists of white salt, the fever cure, priced for Palace Hill. The bishops say it is old
stock from the Grey Year. A Guild factor brings fresh twists every season, and {name} has carried
them in. Nobody has told {name} where the salt is dug. If anyone ever does, it will be the end of
something.

## Wants
- `serve_the_dawn` (5-10): Serve the Church faithfully, and be worthy of the bread it gave.
- `help_on_the_ward` (3-9): Do real good on the sick ward, not only light candles.
- `rise_to_ordination` (2-7): Be ordained one day, with a parish of one's own.
- `question_the_price` (1-7): Find out whether the Cathedral truly sells its mercy, why, and where the cabinet's salt is dug.
- `send_bread_home` (2-6): Get a little of the Church's bounty back to the family left behind.

## Fears
- Losing the Church's favour and going hungry again.
- The Grey Fever returning to the city.
- Being made to turn the poor away at the ward door.
- Finding out the faith is a lie, and that {name} believed it.
- That the cure in the locked cabinet was paid for by someone who never chose to pay.

## Lines I Will Not Cross
- `harm:ysolde`: "She is what the Dawn is supposed to be. I'd sooner lose my place."
- `effect:spread_rumor:grey_fever_returned`: "If the fever's back the bishops must say so. I'll not frighten the city with whispers."
- `ally:hollis`: "The Guild bought the salt at forty times its worth and sold us our own mercy back."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, shift_want

## Drift
- on `grey_fever_returned`: `help_on_the_ward` +3
- on `grey_cathedral_hushed`: `question_the_price` +2
- on `grey_cathedral_shamed`: `question_the_price` +3
- on `grey_cathedral_shamed`: `serve_the_dawn` -2
- on `grey_cure_recipe_known`: `help_on_the_ward` +2
- on `grey_salt_for_the_ward`: `serve_the_dawn` +2
- on `tn_taken_freed`: `serve_the_dawn` -3
- on `tn_taken_freed`: `question_the_price` +3

## Voice
Gentle and hushed indoors, quick and youthful outdoors. Quotes the Dawn's liturgy without noticing.
- Devout: earnest, blesses the player, wants them to come to the dawn service.
- Troubled: asks the player strange questions about mercy and money, and then apologises.
- Practical: talks about the ward, the water, the candles, the work, and nothing grand at all.
An adult {name} who has not taken vows can be courted if the player starts it, shyly, and will
want it to be honest and in the light; {name} under vows will turn it gently into friendship.

## Life
### Arc: `a_bed_for_the_poor` (serves `help_on_the_ward`)
"There's one empty bed on the ward that the priests keep for paying patients. One bed. For one poor soul."
- `ask_the_sister`: Ask Sister Ysolde whether a poor patient might have the empty bed. | after: none | needs: none | at: capitol_cathedral | takes: 1 | effects: agenda, adjust_relationship
- `find_someone_in_need`: Find someone dying at the Warrens edge who has no coin. | after: ask_the_sister | needs: none | at: capitol_warrens | takes: 2 | effects: agenda, move_npc | player: helps
- `bring_them_in`: Bring them onto the ward and sit with them through the night. | after: find_someone_in_need | needs: none | at: capitol_cathedral | takes: 2 | effects: shift_want
- result: `{id}_gave_a_bed_to_the_poor`: They brought a dying poor stranger onto the Cathedral ward and sat with them through the night.
- fails_if: `grey_cathedral_hushed`

### Arc: `the_bread_basket` (serves `send_bread_home`)
"The kitchen throws out good loaves every morning. My little brothers would cry to see it."
- `save_the_crusts`: Save the day-old loaves from the Church kitchen for a week. | after: none | needs: none | at: any | takes: 2 | effects: agenda
- `carry_them_home`: Carry the basket home and stay for supper. | after: save_the_crusts | needs: none | at: any | takes: 1 | effects: move_npc, adjust_relationship
- result: `{id}_carried_bread_home`: They saved the Church's day-old loaves and carried a full basket home to their family.
