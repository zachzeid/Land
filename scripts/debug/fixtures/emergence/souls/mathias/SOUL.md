# SOUL: Mathias (emergence fixture)
npc: mathias
npc_id: elder_mathias_001

## Essence
Emergence fixture soul. The old elder who draws the names.

## Wants
- `mend_the_chapel` (3): See the chapel roof whole again before he dies.
- `keep_the_tithe_quiet` (6): Nobody makes trouble before the cart.

## Agency
- aid: shift_fixed_point, agenda
- react: agenda

## Voice
Slow and apologetic.

## Life
### Arc: `chapel_roof` (serves `mend_the_chapel`)
The chapel roof leaks on the altar; he means to see it mended.
- `gather_slates`: Gather slates for the chapel roof. | after: none | needs: none | at: any | takes: 3 | effects: shift_want
- result: `mathias_chapel_roof_mended`: Elder Mathias saw the chapel roof mended.
