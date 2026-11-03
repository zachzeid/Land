# SOUL: Gregor (fixture)
npc: gregor
npc_id: gregor_merchant_001

## Essence
Test fixture soul. A frightened merchant who would do anything to keep his daughter safe.

## Wants
- `safety` (9): Keep himself and Elena out of danger.
- `coin` (4): Keep the shop solvent.

## Lines I Will Not Cross
- `effect:spread_rumor`: He never spreads talk.
- `hook:betray`: He cannot bring himself to betray anyone.
- `harm:elena`: He will never let Elena be hurt.

## Agency
- scheme: spread_rumor, agenda, move_npc, set_flag
- react: move_npc, agenda
- betray: set_flag
- aid: agenda, unlock_beat

## Drift
- on `fx_drift`: `coin` +1

## Voice
Nervous, apologetic, quick to change the subject.

## Secrets
He supplies the bandits.
