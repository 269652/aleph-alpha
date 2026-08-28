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
- A **sick indicator**, the same shape as the hunger pip, when a kept animal
  is carrying a disease (see [disease.md](disease.md)) — an animal you've
  invested trust in reads as sick the instant it happens, not as a silent
  population-level stat.
- The break-free struggle as **animation**, not just a dice roll resolving
  silently.

## Any animal, the right tool

Reported directly: "any animal can be caught, it may need different tools —
anything with a neck can be caught with a lasso, small flyers with a
Käscher, mice with a trap, a dragon maybe with magically reinforced steel
ropes — you should be able to tame anything, however butterflies or so need
a spell you learn at high level because they are not smart enough to learn
commands."

The system above was built around one tool for one shape of animal: a
lasso loops over a head and neck, so it only ever made sense for a legged
creature with one to loop it over. That is not a design choice worth
keeping as a wall — it is the reason a mouse, a snake and a butterfly were
never catchable at all, not a statement that they shouldn't be. The fix is
not a second lasso with a different name; it is admitting the tool has to
match the animal's actual body, the same way a real trapper carries more
than one kind of gear.

### Design pillars (extending the ones above)

- **The tool follows the body plan, not a species allow-list.** Whether an
  animal needs a lasso, a snare, a net or a trap falls out of properties
  the simulation already tracks for every creature — legs, a neck to loop,
  size — not a hand-maintained table of which species goes with which
  tool. A new species dropped into `AnimalAnatomy` is automatically
  catchable with the right gear the moment it exists, the same
  derive-don't-enumerate discipline `taming.md`'s break-free rate and
  `wild_crops.md`'s phenology already hold themselves to.
- **Wild still means wild.** Extending capture to predators is not making
  them easy — a wolf fights a rope harder than a horse does, for the same
  real reason it fights everything harder: this is condition-driven
  difficulty wearing a different multiplier, not a new mechanic.
- **Not being able to talk to something is not the same as not being able
  to catch it.** A butterfly can be netted the moment you have a net. What
  it *can't* do is learn Follow/Stay, because nothing about a butterfly's
  simulation has ever given it the AI to learn anything — it forages,
  courts and ages, and that is the whole of it. So "tame" for a creature
  with no command AI has to mean something else: a bond, not an order.

### Real-world grounding

- A rope loop has a real minimum practical diameter — you cannot lasso
  something much smaller than the loop itself stays open. That is a fact
  about rope, not about skill, and it is the actual reason field biologists
  reach for a box trap on a mouse and a hoop net on an insect rather than a
  smaller rope.
- A snake has no limbs to hobble and nothing a rope loop settles around the
  way it does a horse's neck — real snake handling uses a hook or tongs
  that pin and lift rather than restrain-and-lead, which is a structurally
  different action from "the animal follows you at rope length."
- Wild predators are measurably harder to habituate to humans than
  domesticable prey species — a documented asymmetry in the real
  domestication-syndrome literature (flight/fight response strength, not
  raw physical strength), which is the real-world reason herding species
  were domesticated again and again independently across history while
  wolves/big cats essentially never were by the same route. The model
  reuses this as *harder*, never *impossible*.
- "Magically reinforced" rope for something the size of a lindwurm is
  flavor on top of a real engineering fact: restraining something that
  outweighs a horse by orders of magnitude needs a genuinely stronger
  cable, the same reason a real crane doesn't rig with garden twine.

### Mechanism spec

**Capture class is read off the same body-plan data `AnimalAnatomy`
already carries for drawing the creature** — nothing new is authored per
species:

| Capture class | Reads | Tool | Species today |
|---|---|---|---|
| Roped | has legs, not tiny, not world-boss scale | **Lasso** (existing) | every current herbivore *and*, newly, every non-boss predator — wolf, lynx, jaguar, bear, boar |
| Snared | `SERPENT_SPECIES` (legless) | **Snare** (new) | venomous_snake, nonvenomous_snake, and any other legless non-boss species |
| Netted | ambient-flyer roster (butterflies, bee, small birds) | **Butterfly net** (new) | monarch, swallowtail, blue_morpho, bee, sparrow, robin |
| Trapped | legged, at-or-below mouse's own `world_scale` | **Trap** (new) | mouse, and anything else authored that small later |
| Boss-scale | `WORLD_BOSS_SPECIES` | **Reinforced rope** (new item, craftable) | lindwurm, krampus, nyx, kraken, rubezahl |

Using the wrong tool on a creature simply does nothing — the same "nothing
in range" read the lasso already gives today, not a new failure state.

**Predators join the Roped class rather than getting a tool of their own**:
a wolf has a neck exactly like a horse does, so a lasso is the correct
tool. What changes is how hard it fights the rope — predator species carry
a real, derived multiplier on `Taming.break_free_chance`'s effective
condition (grounded in the domestication-asymmetry point above; the
multiplier is derived from an existing predator-vs-herbivore stat already
in `CreatureInfo`, not a new eyeballed number), so the loop the player
already knows — throw, hold, wear it down or lose it, come back and feed —
is exactly what catching a wolf feels like, just longer and riskier.

**Boss-scale creatures get their tool now; actually holding one stays a
follow-up.** `Taming.can_be_tamed` keeps `WORLD_BOSS_SPECIES` excluded
regardless of tool — not because the game doesn't want a tamed lindwurm
(`worldbosses.md` explicitly does: "a tempting, high-risk taming target...
since a world boss's DNA is by definition exceptional"), but because
actually resolving a capture attempt against something with its own aggro
state and a fitness-driven promotion score is a real design question
`worldbosses.md` leaves open, not a number this doc should invent in
passing. The reinforced rope is real and craftable today; what it is *for*
is written down and waiting.

**Netting a flyer is instant, not a struggle.** Nothing in `flyer_diet.gd`/
`ambient_flyer_marker.gd` models a butterfly fighting for its life against
a rope the way a horse does — that would be inventing a mechanic the
creature has no simulated basis for. A landed net throw simply catches it;
the interesting choice happens after, in what you do with it.

### A bond, not an order: the Kinship path

A netted creature has no order AI to learn — it forages, courts and ages,
full stop, the same as it did in the wild (see `docs/concept/ecosystem_dynamics.md`).
By default a netted creature becomes a kept curiosity: released, or kept,
but never given Follow/Stay the way a tamed horse is, because there is no
command loop on the other end to receive them.

**The `menagerie` keystone** (Beastmaster, ring 4 — see
[skills.md](skills.md)) already exists, already grants `taming_affinity`,
and its name already means exactly this: a collection of creatures ordinary
handling can't reach. It gains a second effect, in the same
`stat_name`-plus-`description` shape `land_sense` already established for
"this keystone's real payoff is a capability, not a number": unlocking it
lets a netted creature be **bonded** instead of merely kept — a real,
persisted decorative companion (`docs/concept/pets.md`'s existing "Birds:
decorative" role, generalized to whichever species were netted) that
travels loosely with the player. It never takes an order, because nothing
about what it is has changed; what changed is that the player now has the
patience and skill — a Beastmaster's whole late-game specialty — to keep
something around that was never going to learn Stay.

**`taming_affinity` becomes a live stat for the first time** doing this: it
has been declared and summed by `handler_1/2`/`beast_whisperer`/`menagerie`
since the skill web shipped without a single system reading it
(`skills.md`'s own Status admits as much). It reduces the break-free chance
the player faces across every Roped/Snared capture — an experienced
handler holds a struggling animal better — which gives the whole Beastmaster
minor/notable chain leading up to `menagerie` a real payoff the moment a
player starts walking it, not just at the keystone.

This is deliberately **not** built on `magic.md`'s spellcrafting DSL, even
though the report that prompted it said "a spell": that DSL is designed but
has no live executor anywhere in the game yet (no system casts a real spell
today), and standing one up as a side effect of a taming feature would be
a second, much larger feature riding on the first. A skill-gated capability
is the real, playable version of the same idea today; when the DSL gets an
executor, `menagerie`'s grant is the natural first thing to re-express
through it.

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
- ✅ A third sick pip beside them, shown while a kept animal is `INFECTED`
  (see [disease.md](disease.md), `CreatureMarker._sick_pip`) — same
  "already in the loop with the player" gating as the other two
- ✅ Tamed orders: follow / stay, cycled with the lasso key once the animal is
  tame (the rope has nothing left to do at that point, so the key changes
  meaning). A tamed animal also **stops treating the player as a threat** --
  players are sensed as threats, so without that a horse you spent five
  carrots taming would have spent the rest of its life fleeing from you
- ✅ Mounting (horses only): the rider stays the node the player controls and
  the mount is carried along with them, so inventory, combat and survival all
  keep working unchanged while riding
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
- ⬜ The struggle is resolved silently; it has no animation of its own
- 🚧 **Any animal, the right tool** — capture-class read directly off
  `AnimalAnatomy` body-plan data (legs/neck, `SERPENT_SPECIES`, ambient-flyer
  roster, mouse-scale `world_scale`), 4 new craftable tools (snare, butterfly
  net, trap, reinforced rope), predators moved into the Roped class with a
  real derived break-free harshness instead of a blanket exclusion, instant
  (no-struggle) netting for flyers, `taming_affinity` wired live for the
  first time, `menagerie` keystone gains a capability grant (bonding a netted
  creature into a real decorative companion) alongside its existing stat, the
  same `stat_name`-plus-`description` shape `land_sense` uses. ⬜ Boss-scale
  creatures (`WORLD_BOSS_SPECIES`) get the reinforced-rope tool and stay
  excluded from `can_be_tamed` on purpose — resolving a capture attempt
  against a creature with its own aggro/promotion state is `worldbosses.md`'s
  own open question, not one this pass should answer in passing.
