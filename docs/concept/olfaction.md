# Smell: molecules, receptors, and what an animal does about it

How a thing in the world advertises itself, and how an animal decides whether
that is good news.

## Design pillars

**A smell is not a label, it is a mixture.** A ripe apple and a rotting one are
not two entries in a table of scents; they are the same fruit emitting
different proportions of the same handful of molecules. Modelling the molecules
rather than the verdict is what lets a new thing smell like something without
anyone deciding in advance what it smells *of* — a carcass and a rotten fruit
share their decay molecule and therefore share their audience, without either
being told about the other.

**The animal decides, not the smell.** Nothing in the world is inherently
attractive or repellent. A boar and a fly meet the same rotting apple and
disagree, because they carry different receptors and weigh them differently.
Putting the verdict in the ANIMAL is what makes an ecosystem out of a set of
props: the same object means different things to different creatures, which is
what "niche" actually is.

**Distance dilutes.** Smell falls off with range, so an animal follows a
gradient rather than teleporting to a known point. That gradient is the thing
the player watches — a boar casting about and closing in reads as an animal
smelling something; a boar walking a straight line to a fruit reads as a
lookup.

## Real-world grounding

Olfaction really does work this way. An odorant is a mixture of volatile
molecules; a nose carries a repertoire of receptor types, each responding to
some molecules more than others; and the brain reads the pattern across
receptors rather than any single one. Two species with different repertoires
genuinely smell different worlds from the same air.

The molecules modelled are the ones that actually matter for foraging:

| molecule | what emits it |
|---|---|
| **sugar** | ripe fruit, nectar |
| **decay** | rotting fruit, carrion |
| **green** | leaves, cut grass, foliage |
| **musk** | animals themselves |
| **smoke** | fire |

A source emits a mixture. A ripening apple is mostly sugar; as it goes over,
sugar falls and decay rises. Nothing has to describe "rotten apple smell" as
its own thing -- it simply is what an apple emits late.

**Receptors and response.** An animal has a sensitivity per molecule (how well
it detects it at all) and a response per molecule (whether detecting it draws
it in or drives it off). A fly is exquisitely sensitive to decay and likes it;
a deer detects it and does not. The two numbers are separate on purpose: an
animal can be very aware of something it wants nothing to do with, which is
what makes a repellent work.

## Mechanism

**Emission.** A source publishes a mixture: molecule to strength. Fruit
interpolates between its ripe mixture and its rotten one as it spoils, so its
audience changes over its life rather than at a threshold.

**Perception.** What an animal perceives from a source is its sensitivity to
each molecule times the strength of that molecule, summed — diluted by
distance. Perception is a magnitude: how loud, not how good.

**Judgement.** What it does about it is the same sum weighted by RESPONSE
instead of sensitivity: positive draws, negative drives off, near-zero is
noise. So a rotting fruit can be extremely loud to a deer and still repel it.

**Where the receptors live.** Since [ethogram.md](ethogram.md) the receptor
tables are the species records in `Ethogram.SPECIES` (response is the
ethogram's `valence`), and this model's perception and judgement read them
through `Ethogram.express` — the same expression step that applies an
individual's receptor genes, so a boar born without a decay receptor is drawn
less by rot than its species is. This doc keeps what smell *is*: the
molecules, what emits them, and how a smell thins with range.

## Status

- ✅ Molecules, mixtures, and fruit's ripe-to-rotten shift
- ✅ Per-species receptors: sensitivity and response, separately — held in
  `Ethogram.SPECIES` and read through `Ethogram.express` since
  [ethogram.md](ethogram.md); an optional genome on `perceived_strength`/
  `attraction_to` expresses an individual's receptor genes
- ✅ Perceived strength and attraction, diluted by distance
- ✅ Animals following the gradient: boars and deer by smell rather than sight,
  birds preferring ripe fruit and leaving the rot
- ✅ Flies: how many a thing draws, and how a swarm hangs over it
- ⬜ Carrion, smoke and musk emitting into the same field
