# SOUL: Elena (life fixture)
npc: elena
npc_id: elena_daughter_001

## Essence
Life fixture soul. A daughter who wants to choose her own life.

## Wants
- `choose_my_life` (9): Decide her own road.
- `heal` (6): Get well.

## Agency
- converse: agenda

## Life
### Arc: `own_way` (serves `choose_my_life`)
She will not be kept in a back room for the rest of her life.
- `ask_the_healer`: Ask the healer what the fever really is. | after: none | needs: none | at: any | takes: 2 | effects: agenda | player: needed
- result: `elena_own_way_chosen`: Elena chose her own road, fever or no fever.
- fails_if: `lf_elena_locked_in`
