# Flies

The creature that wants what everything else avoids, and the only one in the
world whose population is driven by decay.

## Design pillars

**Rot breeds.** A single rotting apple should end up with a swarm over it, and
that swarm should be the apple's own offspring rather than flies teleported in
because the game decided a swarm was due. The loop -- rot draws a fly, the fly
lays, the maggots eat the rot, the maggots become flies, those flies lay -- is
the whole feature. It is the one population in the world that a player can
create on purpose by leaving food out.

**A fly is an individual.** Like a bee: a real entity flying around, not a
particle effect. That is what lets one follow a player carrying rotten fruit,
and what makes the swarm over a windfall the same kind of thing as the swarm
in a player's inventory shadow.

**The loop must be bounded, or it eats the world.** A breeding population with
no ceiling is the tree-spread bug again, and worse, because flies breed on a
timescale of days rather than years. Every stage is capped: eggs per clutch,
clutches per female, flies per source, and a global ceiling. A pile of rotten
apples gets a swarm; it does not get a plague that takes the frame rate with
it.

## Real-world grounding

A housefly's life is egg, larva (the maggot), pupa, adult. Real durations at
summer temperatures:

| stage | real | why it matters |
|---|---|---|
| egg | ~1 day | laid in a batch on rotting matter |
| maggot | ~4 days | the stage that actually EATS the rot |
| pupa | ~4 days | motionless; does not eat |
| adult | ~3 weeks | flies, mates, lays |

The pupa is included even though it is invisible and does nothing, because
leaving it out would make maggots turn into flies where they stand and lose
the several days that keep a swarm's growth in check. It is the stage that
makes the feedback loop slow enough to watch rather than explosive.

A female lays batches of around a hundred eggs and lays several times in her
life. Those numbers are scaled down hard here -- a hundred entities per clutch
would be a hundred nodes -- but the SHAPE is kept: many eggs, several clutches,
and most of the young dying before they fly.

## Mechanism

**Attraction.** Flies find rot through the same nose everything else uses (see
`olfaction.md`) -- they are not a special case, they simply have receptors that
make decay the best smell in the world.

**Laying.** A mated female lays on a source rotten enough to feed maggots. She
cannot lay on fresh fruit: there is nothing there for a maggot to eat.

**Feeding.** Maggots eat the source they hatched on, which HASTENS its decay --
so a swarm makes its own food run out. That is what stops one apple supporting
flies forever.

**Following.** A fly with nothing better nearby follows the strongest smell it
can find, which is how one ends up trailing a player carrying rotten fruit.

## Status

- ✅ The four stages, their durations, and what each one does
- ✅ Laying: who can, on what, how many, how often
- ✅ Population ceilings at every level
- ⬜ Flies, eggs and maggots as rendered entities in the world
- ⬜ Maggots hastening the decay of what they eat
- ⬜ Flies following a player's carried rot
