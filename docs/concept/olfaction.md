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

## The other edge: a predator that hunts you by nose

Added 2026-09-03. "The wind carries it" above made the player smellable and
gave prey a reason to flee earlier when the player is upwind — which made the
wind a **tool**, something the player manages in order to get close to a deer.
This is what it costs them.

A predator with a hunting nose that is **downwind of the player acquires them
as prey**, from well beyond anything it could see. Three things make it work,
and none of them are new machinery:

- **Who hunts by nose is read off the receptor table**, not a second list of
  hunters. What makes an animal a scent hunter is that it reads musk as a
  *meal* rather than as a warning — a real positive `MUSK` response — which
  `Olfaction` already knows for every species in the roster, including ones
  added later that inherit their diet's nose. A grazer still smells the player
  perfectly well; smelling and stalking are just different verbs.
- **The range is bracketed, not picked.** It has to beat the eyes or nothing
  changes at all (`CreatureMarker.SENSE_RADIUS`), and it must not reach across
  the map (`Olfaction.MAX_RANGE_TILES`). Both edges are pinned by test.
- **The wind is the same wind.** It reuses `WindScent.effective_distance_tiles`
  — the identical call the prey side makes — so the two halves of the mechanic
  cannot disagree about which way the wind blows. The same gap that is safe
  upwind of a wolf is not safe downwind of it, and that single sentence is the
  whole feature.

Predators had never hunted the player at all: `_nearby_prey_creatures` only
ever returned other *creatures*, so the player was something a predator bumped
into rather than something it came looking for. A tamed predator is exempt, the
same way `fears_players` already exempts one on the prey side.

## Blood: the trail a wounded animal leaves

Added 2026-09-03, and the counterpart to "The wind carries it" above: that
section made the **player** smellable, this one makes a **wounded animal**
smellable, and between them scent stops being only an input to foraging.

**The problem it solves.** A struck animal runs. `FlightDistance` makes it run
early and `AnimalAnatomy`'s own `world_scale` makes big animals fast, so a
single hit that does not kill outright usually means the animal is simply gone
— and the hunt ends not because the player failed but because the world stopped
representing what happened. There was no third state between "dead" and
"untouched".

**What blood adds.** A wound bleeds, and bleeding leaves marks on the ground:

- **`BLOOD` is a seventh molecule.** Real, and specifically the thing predators
  actually track — mammalian blood scent is dominated by
  *trans*-4,5-epoxy-(E)-2-decenal, a single aldehyde that carnivores respond to
  on its own, which is why "the smell of blood" is a real behavioural trigger
  rather than a figure of speech. It is nothing like `DECAY`: fresh blood and
  carrion are different signals with different meanings, and collapsing them
  would make a live wounded deer smell like a week-old carcass.
- **A bleeding creature drops marks along the path it actually ran.** Not a
  radius around where it was hit — the marks are where it *went*, which is what
  makes them a trail rather than a stain. They are visible (dark, small,
  ground-flush, bounded like guano) and they emit `BLOOD` into the same
  `smells_near` field baits and carried food already use, so nothing new has to
  be taught about them.
- **The trail fades.** Marks thin and stop as the wound clots, and the world
  drops the oldest once there are too many — so a trail is a *window*, not a
  permanent map annotation. Following it is a thing you do now.

**What it costs the animal.** A wounded animal moves slower, which is the
mechanism that makes tracking worth doing: the trail is only useful because the
thing at the end of it is catchable. Real — blood loss is a genuine
performance cost long before it is fatal, and it is why a hunted animal is
followed rather than outrun.

**Who else reads it.** Nothing yet, deliberately, but the field is shared: a
predator's receptors already have a `BLOOD` row, so a wolf drawn to another
hunter's wounded deer is a consumer away rather than a system away.

Cross-references [survival.md](survival.md)'s open-wound trigger, which is the
same wound model seen from the player's side — a gash on a deer and a gash on
the player are mechanically the same real thing.

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
- ✅ **And it carries the other way too** (`src/gameplay/predator_scent.gd`,
  `CreatureMarker.smells_a_player_to_hunt`): a predator downwind of the player
  acquires them as prey from beyond sight. Predators had never hunted the
  player at all before this.
- ✅ **`BLOOD` as a seventh molecule, and a wounded animal that leaves a trail
  of it** — see "Blood: the trail a wounded animal leaves" above. A struck
  animal bleeds, slows, and drops visible marks along the path it actually ran;
  the marks emit into the same `smells_near` field baits already use, and fade
  as the wound clots.
- ⬜ Predators reading that blood field — the receptor row exists and the marks
  are emitted; nothing hunts by them yet.
- ⬜ Carrion and smoke emitting into the same field (a campfire that actually
  pushes animals off a meadow; a carcass that draws hunters). Both molecules
  and both receptor rows exist; nothing in the world emits either yet.
