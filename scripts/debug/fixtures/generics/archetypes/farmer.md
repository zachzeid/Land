# ARCHETYPE: Farmer
archetype: farmer
regions: western_valley

## Essence
{name} works a strip of land outside {home}, in the {region}, and has buried two harvests' worth
of hope in it. The bandits take a share, the weather takes the rest.

## Wants
- `keep_the_farm` (6-9): Keep the farm through the winter.
- `a_cow_of_her_own` (2-6): Save enough for a milk cow of her own.
- `quiet_life` (3-7): Be left alone by bandits and lords alike.

## Fears
- Losing the land to debt.

## Lines I Will Not Cross
- `effect:move_npc`: A farmer does not leave the land in sowing season.

## Agency
- converse: agenda, adjust_relationship, spread_rumor

## Voice
Plain words, weather and soil in every sentence.
- Slow and wry; answers a question with a proverb.
- Quick and anxious; counts coins out loud.
- Gruff, short sentences, softens with children.

## Life
### Arc: `milk_cow` (serves `a_cow_of_her_own`)
A cow means milk, cheese, a little coin of {name}'s own.
- `save_pennies`: Put aside a copper from every market day. | after: none | needs: none | at: any | takes: 3 | effects: shift_want
- `buy_the_cow`: Buy a cow at the square. | after: save_pennies | needs: none | at: thornhaven_town_square | takes: 1 | effects: agenda | player: helps
- result: `{id}_bought_a_cow`: {name} bought a milk cow at last.
