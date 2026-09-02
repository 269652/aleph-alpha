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

## The wind carries it

Dilution by straight-line distance is the still-air case, and still air is the
one case the world never contains.

`WeatherModel.wind_direction_for` had existed — written, documented, tested —
since the weather model was written, and had **no production caller at all**
(verified across every `.gd` in `src/` and `scenes/`). The world had a wind
direction that nothing in the running game ever asked for. Seeds dispersed,
grass swayed and flowers advertised without one.

**Mechanism.** `WindScent` converts a geometric distance into the distance the
smell *behaves* as if it had: divided by a reach factor that rises downwind and
falls upwind.

```
alignment    = normalize(nose - source) · normalize(wind)      # +1 downwind, -1 upwind
reach_factor = max(MIN_REACH_FACTOR, 1 + ADVECTION_GAIN · strength · alignment)
effective    = geometric / reach_factor
```

Hand that one number to `Olfaction.dilution` in place of the real distance and
every judgement the module already makes keeps working — which is the whole
reason the wind is expressed as a *distance* rather than as a new term inside
each of `dilution`, `perceived_strength`, `attraction_to` and
`ScentForaging.best_source`.

`MIN_REACH_FACTOR` is not zero, on purpose: a real plume is turbulent, so
approaching from upwind makes you quiet, never invisible.

**Strength comes from the weather.** `WeatherModel.wind_strength_for` is a
visual energy multiplier (1.0 clear → 1.8 storm), not a 0..1 fraction.
`WindScent.advection_strength` normalises it once, in one place, rather than
every caller inventing its own conversion — and it deliberately leaves a clear
day at a real breeze (~0.56) rather than at nothing, because clear is half of
all weather rolls and a scent-wind that only existed in bad weather would be
off for most of a session.

**The player emits.** `Olfaction.PLAYER_MIXTURE` is musk — the molecule that
was defined from the first day of this doc and that nothing ever emitted.
Without a player emission there is nothing for the wind to carry, and therefore
no difference between stalking upwind and downwind.

**What it does to an animal is wariness, not flight.** A whiff does not make an
animal bolt; it makes it jumpy. `FlightDistance.smells_player` feeds
`Wariness.after_scent`, which widens that individual's own flight radius (see
[animal_husbandry.md](animal_husbandry.md)'s "The approach"). Routing the wind
through wariness rather than through a second flee trigger keeps
`FlightDistance` the single owner of *when does this animal run* — and it is
the truer behaviour anyway: a deer that catches your scent across a meadow does
not sprint, it stops trusting the meadow.

**What the player sees.** The status line names the wind
(`World.status_line_wind` → `WindScent.wind_name`), and it is named for where
it comes *from* — a wind blowing east is a **westerly** — because that is the
one piece of real-world convention a player brings with them. The wind turns
day to day (`WeatherModel.WIND_TURN_PER_DAY`), so the right line of approach to
the same meadow is different tomorrow.

**Honest scope note.** This is steady-state advection, not a simulated plume.
Real odour plumes meander, pool in hollows and sink on cold nights. This models
the one thing that decides the player's line — which side of the animal the
wind is on — at the same fidelity `ScentField` chose for floral scent, and for
the same reason.

## Status

- ✅ Molecules, mixtures, and fruit's ripe-to-rotten shift
- ✅ Per-species receptors: sensitivity and response, separately
- ✅ Perceived strength and attraction, diluted by distance
- ✅ Animals following the gradient: boars and deer by smell rather than sight,
  birds preferring ripe fruit and leaving the rot
- ✅ Flies: how many a thing draws, and how a swarm hangs over it
- ✅ **A nose for every land species**, not just the five hand-authored ones.
  A species without its own entry inherits its DIET's receptors
  (`Olfaction.receptors_for`, `RECEPTORS_BY_DIET`), which is the honest answer
  anyway — what an animal's nose is *for* is what it eats — and means a species
  added later is born smelling like its diet rather than born noseless.
  `test_every_keepable_species_has_a_nose` iterates the real
  `AnimalAnatomy.SPECIES` roster so an addition cannot slip through.
- ✅ **`OIL` as a sixth molecule**: nuts, seeds and oily kernels. Real — a nut
  smells of the aldehydes its fats throw off as they oxidise, nothing to do
  with sugar or foliage — and it is what lets a squirrel and a horse genuinely
  disagree about a walnut. Without it every food on the ground reduced to
  "sweet or rotten".
- ✅ **Per-item mixtures** (`Olfaction.bait_mixture`). `fruit_mixture` ignores
  its item id, which is right for fruit and wrong for everything else: a carrot
  was no better a lure for a horse than a walnut was. Roots, mast, flesh and
  cooked food each emit their own mixture, and cooking really does change what
  a thing emits — a cooked bait carries `SMOKE`, which every prey animal reads
  as fire, so **cooking your bait makes it worse bait** and nothing had to be
  told that.
- ✅ **Musk: the player emits it** (`PLAYER_MIXTURE`), and the wind carries it
  (`WindScent`) — see "The wind carries it" above.
- ⬜ Carrion and smoke emitting into the same field (a campfire that actually
  pushes animals off a meadow; a carcass that draws hunters). Both molecules
  and both receptor rows exist; nothing in the world emits either yet.
