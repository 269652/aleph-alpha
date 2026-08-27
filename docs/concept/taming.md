# Taming

How a wild animal becomes a working animal: caught with a rope, held while it
fights you, and then won over by feeding it — not clicked once and converted.

## Design pillars

- **Taming is a relationship over time, not a transaction.** The lasso only
  buys you the chance to start; trust is earned by turning up when the animal
  is hungry, repeatedly. An animal you caught an hour ago and ignored is still
  wild.
- **The animal fights back, and strength decides.** A healthy horse should
  usually break a first throw. Wearing an animal down is a real (if brutal)
  strategy, and so is picking a weaker individual — the same
  individual-variation the roster already models (`CreatureInfo` levels, health).
- **Nothing is instant and nothing is hidden.** Catching, holding, tying and
  feeding are all things the player watches happen, with the animal's state
  legible on the animal itself (see "What the player can see"). This follows
  `flora.md`'s "what is visible must be what is real": if the animal is hungry,
  that is a fact the simulation holds and the player can read.
- **A tied animal is a placed object in the world.** Tying the rope to a tree
  is what makes taming compatible with actually going away and doing something
  else — the world keeps simulating (see `ecosystem_dynamics.md`), so the
  animal gets hungry on its own schedule while you are gone.

## Real-world grounding

Traditional horse-breaking and modern natural horsemanship both work in the
order this models: **restrain → hold → habituate → reward**. The rope halter
comes first and does not itself tame anything; it prevents flight. Trust is
then built by being the source of food and by repetition over days, not by a
single feed. A well-fed, healthy animal resists restraint far more effectively
than a weak one, which is why the break-free chance is driven by condition.

Carrots are the canonical horse reward for good reason: high-sugar root
vegetables are strongly preferred by equines and are the traditional training
treat.

## Mechanism spec

### 1. The lasso

A craftable tool: **4 plant fibre → 1 lasso** (`CraftingRecipeBook`). Plant
fibre already comes from harvesting mature tall grass
(`EarthChunkManager.harvest_grass_near`), so the entry cost is a walk through a
meadow rather than a tech tree.

Held in hand, the lasso enables a **throw** at a creature within range. Range
is deliberately short — you have to close with the animal first, which is the
part that makes stalking a horse feel like something.

### 2. The catch, and breaking free

A throw that lands puts the animal in a **restrained** state. It immediately
begins trying to break out, and keeps trying at intervals for as long as it is
restrained.

Break-free chance is driven by the animal's **condition** — its health
fraction scaled down by how tired it already is. Each failed attempt costs
**stamina**, not health: fighting a rope winds an animal, it does not wound it,
and a successful catch should not hand the player a nearly-dead horse as its
prize.

An animal that has fought itself to a **standstill gives up** and stops
fighting. That is how breaking an animal actually works, and mechanically it is
what makes the rest of taming possible: an exhausted animal that went on
rolling its floor chance forever would mean a horse tied to a tree is certain
to be gone by the time the player gets back with carrots.

The number that matters is the chance of holding the animal across the **whole**
struggle, not on one attempt — attempts repeat, so a per-attempt figure
compounds into something quite different. Getting that backwards shipped a
version where a "healthy animals usually win" per-attempt chance of 0.85
compounded to ~99.9% escape and nothing could ever be caught. The rate is
therefore pinned by *measuring* sixty real captures
(`test_the_measured_catch_rate_matches_the_model`), not by a formula: about one
throw in three lands on a fresh, full-strength horse, and a worn-down one is
usually held.

An animal that breaks free flees (the existing `CreatureBehavior` flee intent)
and is **harder to catch again for a while** — it has learned what the rope
means.

### 3. Leading and tying

While restrained and held, the animal **follows the player** at rope length: it
is pulled along rather than choosing to come. This reuses the existing movement
gate (`CreatureMovementGate`) so a led animal still walks around trees rather
than through them.

The loose end can be **tied to a tree**, which anchors the animal to that spot:
it wanders only within rope length of the anchor and cannot flee past it. This
is what lets the player leave. Untying returns it to being led.

### 4. Trust, and what feeding does

A restrained animal has a **trust** value, 0 to fully tame. Trust rises **only
when the animal is fed while it is actually hungry** — feeding a full animal
does nothing, which is what stops taming being a matter of spamming carrots.
Since hunger rises on its own schedule (`CreatureNeeds`), taming is naturally
paced across real time: turn up, feed, come back later.

**Carrots** are the reward the system is tuned around. They come from the
meadow rather than from a farm: wild carrot is a real, visible plant that
grows and spreads among the grasses (see [wild_crops.md](wild_crops.md)) --
pulling a mature one is a swing-driven harvest, the same input as chopping a
tree or harvesting grass fibre. That deliberately puts the lasso and its
reward in the same place -- a walk through a meadow equips you for the whole
loop. It takes several successful feeds to reach full trust.

Trust **decays** if the animal is left restrained and hungry for a long
stretch — neglect is not neutral.

### 5. A tamed animal

At full trust the rope is no longer what is holding it, and the animal stops
being **afraid** of the player at all — worth stating explicitly because the
player is sensed as a threat by every wild creature, so a tamed animal that
kept that reflex would flee the person who tamed it.

A tamed animal accepts **orders**:

- **Follow** — travels with the player, using the same led-movement path.
- **Stay** — holds position, wandering only locally, without needing a tie.
- **Mount** — the player rides it, moving at the animal's speed rather than
  their own. Only species that can plausibly carry a person (horses) offer
  this; a tamed boar follows and stays but is not a mount. The **rider stays
  the thing the player controls** and the mount is carried along underneath
  them, rather than handing control over to the animal — which keeps
  inventory, combat, survival and everything else working unchanged while
  mounted. A horse travels at a working trot, not a gallop: this is a world
  of real geography to travel *through* (see `exploration.md`), not to blur
  past.

A tamed animal still eats, still gets hungry, and still dies if neglected — it
is a creature in the ecosystem, not a vehicle.

## What the player can see

- The **rope** itself, drawn between the player (or the anchor tree) and the
  animal, so "this animal is on a line" is never ambiguous.
- A **hunger indicator** above a restrained or tamed animal when it is hungry —
  the cue that it is time to feed it. Hunger already exists in the simulation
  (`CreatureNeeds.is_hungry`); this only surfaces it.
- A **trust indicator** showing progress toward tame, so the player can tell
  that feeding is doing something.
- The break-free struggle as **animation**, not just a dice roll resolving
  silently.

## Status / mechanisms

- ✅ `Lasso` item + 4× plant fibre recipe, and the `Carrot` item, both with
  their own art
- ✅ Throw/catch interaction from the held lasso (`Player._throw_lasso`, one
  key that throws / ties / unties / releases depending on what you are holding)
- ✅ Break-free model driven by condition, with per-attempt stamina cost
  (`Taming.break_free_chance` / `condition_after_struggle`)
- ✅ Restrained state on `CreatureMarker` — a caught animal stops making its
  own decisions, cannot flee, and fights the rope on its own clock
- ✅ Leading at rope length, through the existing movement gate (`RopeTether`),
  so a led animal walks around a tree rather than through it
- ✅ Tying the loose end to a tree; the anchor simply stops moving with the
  player, so the animal grazes around its tree instead of following
- ✅ Trust model: rises only on feeding a HUNGRY animal, decays on neglect
- ✅ Hunger + trust indicators on the animal, and a state line in the HUD
- ✅ Tamed orders: follow / stay, cycled with the lasso key once the animal is
  tame (the rope has nothing left to do at that point, so the key changes
  meaning). A tamed animal also **stops treating the player as a threat** --
  players are sensed as threats, so without that a horse you spent five
  carrots taming would have spent the rest of its life fleeing from you
- ✅ Mounting (horses only): the rider stays the node the player controls and
  the mount is carried along with them, so inventory, combat and survival all
  keep working unchanged while riding
- ✅ **Fitness-driven mounted speed and a coat-quality tell (2026-08-26):**
  pets.md's own design pillar -- "the same fitness dimension that makes a
  wild animal strong in the ecosystem sim is what makes it good to keep" --
  now has its first real wiring. `Taming.mounted_speed_for` scales a ridden
  horse's speed by *that specific individual's own* `AnimalFitness.
  fitness_score` (read from its `wander_seed`), lerped between 0.8x and 1.2x
  the old flat `MOUNTED_SPEED`; the population median fitness (0.5) still
  rides at exactly 150, so an "ordinary" horse is unchanged, and only a
  genuinely fitter/less-fit individual pulls away from that baseline in
  either direction. Separately, `coat_vibrancy` alone (not the combined
  score) drives a visible pre-taming tell: `CreatureMarker` tints every land
  creature's own sprite by a warm, bounded, squared curve -- an ordinary
  coat reads as visually unmodified, a truly vibrant one clearly stands out
  -- so a player can judge a wild horse's coat quality before ever throwing
  the lasso, the real-world "prize animals are visibly judged before anyone
  commits to keeping them" pattern. See `docs/concept/pets.md`'s "Fitness →
  in-role performance" table for the exact mapping and what is still
  unmapped (`strength`/`agility` individually).
- ✅ Carrots have a source: **wild carrot** (Daucus carota) is a real,
  visible meadow plant that grows, spreads, and is pulled directly --
  `WildCropPatch`/`WildCropMarker`, see [wild_crops.md](wild_crops.md) --
  superseding the earlier grass-harvest freebie. The same meadow that
  supplies the lasso also supplies the reward
- ✅ Persistence: a tamed, part-tamed or tied animal is kept as an INDIVIDUAL
  across chunk unload and across sessions (`KeptAnimals`), re-spawned where it
  was left with its trust, its order and whatever it was tied to. Deliberately
  stored outside the region's aggregate population: a herd is a number and one
  deer is much like another, but the horse the player spent an evening winning
  over is a particular animal in a particular place -- and the aggregate is
  capped at carrying capacity, so rolling it in there could see it culled to
  make room for wild deer. Kept animals are therefore EXTRA: carrying capacity
  governs wild animals, not the ones the player is looking after.
  **Fixed (2026-08-26): "a particular animal" is now actually true, not just
  its trust/position/tied state.** `_restore_kept_animals` respawned a kept
  animal via `CreatureRenderer.spawn_single`, which always rolled a fresh
  `randi()` seed -- silently re-rolling the individual's own
  `AnimalFitness`-derived phenotype (strength/agility/coat_vibrancy, all
  deterministic from that one seed) on every reload, even though everything
  else about it was faithfully restored. `KeptAnimals` now persists
  `wander_seed` too (format version bumped to 2; an old save is simply
  dropped, the same "better nothing than nonsense" rule the file already used
  for a version mismatch), and `spawn_single` takes an optional explicit seed
  for exactly this restore path, leaving every other caller (a wild spawn, a
  courtship offspring) rolling a fresh individual as before.
- ⬜ The struggle is resolved silently; it has no animation of its own
