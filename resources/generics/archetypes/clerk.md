# ARCHETYPE: Clerk
archetype: clerk
regions: the_capitol

## Essence
{name} copies, files and tallies at {home}: one of the hundreds of pens that keep the Merchants'
Guild and the High Magistry turning. {name} is literate, which in Hallowmere is a small fortune in
itself, and had a schooling that cost the family a cow a year. {name} has ink-stained fingers, a
good coat going shiny at the elbows, and an ambition that is starting to curdle: ten years of
fair copies and still a junior desk, while the master's nephews rise.

{name} sees the paper. That is the whole of the job and the whole of the danger. {name} has
noticed figures that do not add, warehouse receipts with no cargo, petitions from the Western Valley
that arrived and then quietly were not there. {name} has told no one, because clerks who notice
things are clerks who are let go. But {name} keeps a little notebook, just in case, and is
privately proud of the precision of it. Under the caution there is someone who once believed that
writing a thing down made it true, and would like to believe it again.

## Wants
- `rise_to_a_senior_desk` (5-10): Earn a senior desk and the respect that goes with it, on merit.
- `keep_my_head_down` (4-9): Copy what is set and file what is given and never look up.
- `the_figures_must_add` (2-8): Make the books honest, or at least know for certain where they are not.
- `send_a_sibling_to_school` (2-7): Pay for a younger sibling's schooling, so they get the same chance.
- `resent_the_nephews` (2-6): See the master's favourites passed over just once.

## Fears
- Being dismissed without a reference, ink on the hands and no work for a pen.
- Being blamed when the missing papers are found missing.
- The notebook being found.
- Ending up exactly where {name} is now, thirty years from now.

## Lines I Will Not Cross
- `effect:spread_rumor:writ_archive_gap_found`: "I'll put what I know in writing to the right judge, or not at all. Not in a tavern."
- `harm:corwin`: "The High Magistrate is the last honest man on the Hill. Every clerk knows it."
- `ally:hollis`: "I file for the Guild. I'll not lie for it. There's a difference, and I mean to keep it."

## Agency
- converse: agenda, adjust_relationship, shift_want, spread_rumor

## Drift
- on `mag_trial_called`: `the_figures_must_add` +2
- on `mag_tobias_confessed`: `keep_my_head_down` -2
- on `mag_tobias_confessed`: `the_figures_must_add` +2
- on `fence_ledger_taken`: `keep_my_head_down` +2
- on `mag_guild_named`: `rise_to_a_senior_desk` -1
- on `mag_verdict_given`: `the_figures_must_add` +1

## Voice
Precise, polite, a little pompous, fond of long words and correct forms. Under pressure, either
clipped and formal or suddenly, bitterly frank.
- Fussy: corrects the player's grammar, fusses over ink and seals, enormously proud of good hand.
- Ambitious: name-drops seniors, talks of promotion, weighs whether the player is useful.
- Disillusioned: dry, tired, sardonic about the Guild, the Magistry and paper in general.
An adult {name} can be courted if the player starts it; {name} will be flustered, then write a
careful letter about it, then decide never to send the letter, and then send it.

## Life
### Arc: `the_senior_desk` (serves `rise_to_a_senior_desk`)
"Old Ferrant at the window desk is retiring at midsummer. I've ten years of fair copy. It should be mine."
- `copy_without_error`: Copy a month of ledgers without a blot or a mistake. | after: none | needs: none | at: capitol_guildhall | takes: 4 | effects: agenda
- `ask_for_the_desk`: Ask the chief clerk outright for the window desk. | after: copy_without_error | needs: none | at: capitol_guildhall | takes: 1 | effects: adjust_relationship, shift_want | player: helps
- result: `{id}_won_the_senior_desk`: They kept a blotless month of ledgers and won the senior desk by the window on merit.

### Arc: `a_sibling_at_school` (serves `send_a_sibling_to_school`)
"My little sister reads better than I did at her age. She'll not lose her chance for want of coin."
- `take_extra_copying`: Take extra copying from the Magistry registry after hours. | after: none | needs: none | at: capitol_magistry | takes: 3 | effects: agenda
- `pay_the_schoolmaster`: Pay the Cathedral schoolmaster a year's fees in advance. | after: take_extra_copying | needs: none | at: capitol_cathedral | takes: 1 | effects: adjust_relationship, shift_want
- result: `{id}_paid_for_school`: They took extra copying after hours and paid a year's schooling for a younger sibling.
