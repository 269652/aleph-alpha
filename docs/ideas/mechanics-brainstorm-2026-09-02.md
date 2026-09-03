# Mechanics brainstorm — 2026-09-02

Written after a live play session (see
[`docs/playtests/2026-09-02-approach-and-substrate-session.md`](../playtests/2026-09-02-approach-and-substrate-session.md))
and a full audit of `src/` for modules with no production callers.

**The rule this list follows.** Every idea here names the modules it would
actually ride on. This project's whole thesis is *compose small primitives, let
deterministic simulation resolve what they produce together* — so an idea that
needs a new parallel system is a worse idea than one that joins two things
already in the tree. Where an idea needs genuinely new code, that is said.

Ideas are grouped by how much is already built underneath them. Group A is
mostly wiring; group C is real design work.

---

## Group A — two live systems, one missing wire

These are cheap because both halves already exist, tested, and simply never
meet. The pattern that produced the approach layer this session.

### A1. Smoke pushes animals, and that is how you herd 🔥

`Olfaction.SMOKE` exists with a sensitivity *and* a response row for every
animal in the game — and every prey response to it is `-0.8` to `-1.0`, the
strongest negative in the whole table. **Nothing emits it.** Meanwhile
`campfire` is a real placeable item, `campfire_cooking.gd` exists, and torches
are craftable.

Wire a campfire (and a carried torch) into `EarthChunkManager.smells_near` as a
smoke source and you get, with no new rules:

- Animals give a lit fire a wide berth. Camping somewhere means the meadow
  empties, which is a real cost of a real choice.
- **Herding without a herding system.** Two fires and a gap is a funnel. Walk a
  torch along a line and the herd moves off it. This is how people have actually
  moved animals for ten thousand years, and it falls out of a repel response
  that is already authored.
- The `Apex Hunter` receptor row is the one with `SMOKE: 0.0` response —
  deliberately, in this pass. A world boss walks through your fire. That reads
  as terrifying and nobody had to write a special case.
- Smoke is directional the moment it enters the field, because `WindScent`
  already advects everything in it. Build your fire downwind of the herd and it
  does nothing; upwind and it clears the valley.

**Rides on:** `Olfaction.SMOKE`, `EarthChunkManager.smells_near`, `WindScent`,
the existing `campfire` placeable. **New:** a smoke source row, and a repel
term in `ScentForaging` (which today only ever *seeks* a best source — it has
no "walk away from" counterpart, so the negative half of `attraction_to` has
never been used by anything).

**Note the gap that reveals:** `attraction_to` has always returned negative
values and *nothing has ever consumed one*. Half of olfaction's design has been
dead code since it was written.

### A2. A carcass draws hunters, and that is a trap 🩸

Same shape. `Olfaction.DECAY` is emitted only by spoiling ground fruit today.
`Carcass` is a real node, `carrion.gd` and `carrion_forage_behavior.gd` exist,
and `corpse.gd` sits in the tree with **zero production callers**.

Publish a carcass as a `DECAY` + `MUSK` source and a kill becomes a place with
consequences: flies arrive (already implemented, `flies.gd` reads the same
field), then whatever hunts. Leaving a kill where you made it is different from
dragging it home. Baiting a wolf into a snare is the same verb as baiting a
sheep with a carrot — the bait table already distinguishes `meat` from `carrot`
by mixture, and the hunter's nose already prefers `MUSK`.

**Rides on:** `Olfaction.bait_mixture("meat", …)` (built this session),
`take_bait_at` (built this session), `Carcass`, `flies.gd`. **New:** carcasses
joining `smells_near`.

### A3. Wet fur, and why a rainy day is a good day to stalk 🌧

`WetnessTracker` exists. Rain is real. Real rain flattens scent — it knocks
volatiles out of the air and it masks sound.

One term: scale `WindScent.advection_strength` (or a new `scent_damping`) down
during rain, so a wet day is the day you can walk up to a deer. It costs the
player something too, because rain is also when the speed multiplier collapses
(measured this session: 36% in a storm) — so the weather offers a genuine
trade: *today you can get close, but you cannot chase.* That is exactly the
shape of decision this game is supposed to produce.

**Rides on:** `WeatherModel`, `WindScent`, `WetnessTracker`. **New:** one
multiplier and its test.

### A4. Pet loyalty, which is written and unreachable 🐕

`src/gameplay/pet_loyalty.gd` — tested, zero production callers.
`BondedCompanionMarker` exists. `docs/concept/pets.md` exists. The taming loop
ends at `trust` and `order` and never reaches loyalty at all.

The interesting version is not a loyalty bar. It is: **a loyal animal reacts to
things the player has not noticed yet.** The marker already senses threats on a
throttled scan; a bonded companion that *orients* toward a threat before the
player can see it turns the pet into an instrument — the dog that stares at the
treeline is the game telling you something without a UI element.

**Rides on:** `pet_loyalty.gd`, `BondedCompanionMarker`,
`CreatureMarker._cached_threats`. **New:** the orient-and-alert behaviour.

---

## Group B — one live system, a real design question

### B1. Trails: the world remembers where things walk 🥾

`PathScarring` is live for the player. Progress notes it is deliberately not
wired to creatures ("to avoid an O(creatures × nearby stones) scan").

The missing half is that **animals make trails too**, and a trail is the single
most information-dense thing in a real landscape. A game trail through long
grass tells you: something uses this, roughly how big, roughly how often, and
which way to the water. None of that needs a tracking skill or a UI — it needs
scarring to accumulate from creature movement and to decay, and for the player
to be able to look at it.

The reason this is group B and not group A is the cost. Doing it per-creature
per-frame is the scan the progress notes rejected. Doing it *per chunk, as a
scalar field the ecosystem sim already updates on its slow cadence* is cheap and
is probably the right answer: a chunk knows its own herbivore population; a
trail is that population integrated over time along the paths between its water
and its forage.

**Rides on:** `PathScarring`, `EarthChunkManager`'s slow ecology cadence, the
existing water/forage direction queries. **New:** a per-chunk trail field, and
its decay.

**The payoff that makes it worth it:** tracking becomes a real verb with no new
systems. Follow the trail, find the herd. And it composes with A1 — a herd you
pushed with smoke leaves a *new* trail, so the world visibly records what you
did to it.

### B2. Scent memory: an animal that has been baited comes back 🥕

`taming.md` already names the contract: *"an animal that has eaten from a spot
the player left food at is calmer at that spot next time."* Nothing implements
it, and it is the other half of `Wariness` — which currently only ever measures
the player's *mistakes*.

The mechanism is symmetric with wariness and should reuse its shape: a
per-individual, per-place value that rises when the animal eats bait at a
location and decays by absence. It buys the player something wariness cannot:
**a place worth returning to.** A meadow where you have fed sheep for three
days is a meadow where sheep let you close. That is domestication, arriving
from below, without a domestication system.

**Rides on:** `Wariness` (same ramp shape), `take_bait_at`, `KeptAnimals`
persistence. **New:** a place-keyed value, and where it is stored.

**The hard question:** per-individual-per-place is a lot of state. The cheap
version is per-*place* only — a "feeding station" the chunk remembers, which
every animal reads. Less personal, far cheaper, and probably better play,
because it makes the *place* the thing the player invests in.

### B3. Being downwind of a predator 🐺

The wind now carries the player's musk. It should carry every animal's — the
`MUSK` row exists for all of them, and `attraction_to` already says a deer is
repelled by musk (`-0.5`) while a wolf is drawn to it (`+0.9`).

Publish creatures as `MUSK` sources and the wind starts driving predation:
a wolf downwind of a deer hunts; upwind, it does not know. Prey herds drift
upwind. Suddenly the wind is not a stalking mechanic bolted onto the player, it
is a thing the whole ecosystem sits in.

**Rides on:** everything built this session. **New:** creatures in
`smells_near`, and — the real cost — this is an O(creatures²) query unless it
rides the existing chunk-level scan.

**The reason this is exciting and also risky:** it would make animal
distribution genuinely wind-dependent, which is real and which no amount of
tuning can preview. It wants a measured soak test, not a guess.

---

## Group C — new design, grounded in what exists

### C1. Sound, as the third channel

Sight is a radius. Smell is a plume. **Noise is a radius that the player
controls by how they move**, and it is the one channel with no representation
at all.

The whole design is one function and one field: what the player emits is a
function of their speed and the ground they are on — long grass rustles,
gravel scrapes, water splashes, snow squeaks — and every animal has a hearing
sensitivity the way it has an olfactory one. `FlightDistance` already has the
exact shape to take it: a second detection channel feeding `Wariness`.

This is what makes the crouch a full stance rather than a flight-radius
multiplier: crouching is *quiet*, and quiet is what lets you cross open ground.

**Grounded in:** the game already knows the terrain under the player
(`_terrain_speed_multiplier`, `TerrainPassability`, the tall-grass and snow
layers). **New:** an emission function, a per-species hearing row, and the
`FlightDistance` channel.

**Why it is group C:** it needs a decision about whether NPCs and combat read
it too, and that is a much bigger blast radius than the animal loop.

### C2. The animal that decides you are worth following

Everything in the approach layer is about the player reducing an animal's fear.
The inverse has no representation: **an animal deciding, on its own, that the
player is a resource.**

A wild animal that has eaten bait from a player repeatedly, and has never been
harmed by one, should start *closing the distance itself*. Not tame — no rope,
no trust, no orders. Just an animal that follows you at fifty pixels because
you are, statistically, where food happens.

That is real (it is how commensal domestication is now thought to have actually
worked — the wolves came to us), and it is the single most evocative thing this
codebase could produce with what it already has: `Wariness` inverted below zero,
or a sibling `Familiarity` on the same ramp, feeding a follow bias into
`CreatureBehavior.decide` above `wander` and below every survival need.

The payoff is a story the player tells: *"I never tamed it. It just started
showing up."*

**Rides on:** `Wariness`'s ramp, `CreatureBehavior.decide`'s existing priority
ladder, `take_bait_at`. **New:** the familiarity value, its persistence, and one
branch in `decide`.

### C3. Weather as a plan, not a mood

`WeatherForecast` exists and the weather glass reads it. The player can know
what is coming and has no reason to care.

Every mechanic in this brainstorm gives them one: rain flattens scent (A3),
wind decides your line of approach (built), storms halve your speed (measured),
smoke needs the wind on your side (A1). Once four systems read the weather,
*checking the forecast before setting out* becomes a real habit rather than a
flavour text.

The design work is not new systems — it is making the weather glass say the
things that now matter. `"Westerly, freshening"` is a plan. `"Rain later"` is
trivia.

**Rides on:** `WeatherForecast`, `WindScent.wind_name`, everything above.
**New:** the readout, and the decision about how vague an instrument should be.

### C4. Butchering that respects the animal you actually killed

`butchering.gd`, `animal_anatomy.gd` (with real per-species proportions),
`AnimalFitness` (`phenotype_for`, `coat_vibrancy`) and `LootTable` all exist.
`_DROPS` covers exactly four species — `herbivore`, `boar`, `predator`, `lynx`
— so **a dead sheep, goat, horse, deer, camel or reindeer leaves no carcass at
all**, it simply vanishes (recorded in `animal_husbandry.md`, verified).

The fix is not a bigger drop table. It is that the yield should be **read from
the individual**: `AnimalAnatomy`'s `world_scale` and body proportions give
mass; `AnimalFitness.coat_vibrancy` already drives a visible pre-taming tell and
should drive hide quality; condition (`energy`, `_needs`) gives fat. A
well-kept animal butchers better than a starved one, and the player can *see*
which is which before they commit — which is the same "prize animals are
visibly judged before anyone commits" pattern the coat tint already established.

**Rides on:** `AnimalAnatomy`, `AnimalFitness`, `butchering.gd`, `Carcass`.
**New:** the yield function, and rows for the missing species.

---

## The meta-observation

The audit found **38 tested modules with zero production callers**. That is not
a failure — most are honest scaffolding ahead of a feature. But the two that
mattered most this session (`wind_direction_for`, and the `MUSK`/`SMOKE`
molecules) had been sitting *finished* for a long time, and joining them took
less work than either of them originally took to write.

It is worth running that audit periodically. The highest-value work in a
codebase built this way is often not the next new system — it is the wire
between two systems that were each built correctly and never introduced.

Candidates from this audit, in rough order of how ready they look:
`pet_loyalty.gd`, `corpse.gd`, `wounds.gd`, `crafting_station.gd`,
`cooking_recipe_book.gd`, `farm_plot.gd`, `crop_breeding.gd`, `smelting.gd`,
`coziness_score.gd`, `faction_reputation.gd`, `npc_recognition.gd`,
`npc_voice.gd`, `dialogue_move.gd`, `waypoint_network.gd`, `sunlight_model.gd`.
