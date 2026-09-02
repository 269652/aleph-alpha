# Animal Husbandry

How an animal stops being wildlife and becomes stock: approached rather than
chased, caught, kept somewhere that costs you something to maintain, bred on
purpose, and worked or milked for a living. [taming.md](taming.md) already
covers the middle of that — the rope, the struggle, the carrots. This doc
covers what comes before it (you cannot get near the animal) and everything
after it (you have an animal and nothing to do with it).

The complaint this exists to answer is that the player watches the simulation
instead of acting on it. So every mechanism below is written against one test:
**what does the player press, and what does the world do back?** A rule whose
answer is "it happens on its own" is only allowed here when the player chose
the conditions that made it happen — where they put the pen, which two animals
they paired, whether the trough was full.

## Which doc owns what

Three docs share this subject and they must not re-specify each other. The
boundaries below are decisions, not suggestions: where an earlier draft of any
of these docs specified something on this list that it does not own, the owner
named here wins.

| Subject | Owner | The other docs may |
|---|---|---|
| The lasso, the struggle, `Taming.trust`, feeding, orders, mounting | [taming.md](taming.md) | reference |
| What `trust` *means* behaviourally, and what neglect costs a **free** animal | [taming.md](taming.md) | reference |
| Retiring `pet_loyalty.gd` into tiered `Taming` order gates | [taming.md](taming.md) | reference |
| The genome, `DnaCrossover`, relatedness, phenotype derivation | [animal_genetics.md](animal_genetics.md) | reference |
| The complete `KeptAnimals` **FORMAT_VERSION 2** record and its byte budget | [animal_genetics.md](animal_genetics.md) | list only the fields they read |
| Flight distance: the function, its signature, its Schmitt-gap invariant | **this doc** | supply inputs |
| The **shy threshold** (approach speed that reads as a rush) | **this doc** | honour it |
| Target selection (`Player.selected_animal`) | **this doc** | reference |
| The pen, keeping costs, pairing gate, production, work, `record_death` | **this doc** | reference |
| Penned starvation | **this doc** | reference |

Nothing in this doc cites another doc by **line number**. Sibling docs move in
the same passes this one does, and a line citation across that boundary is
dangling before the ink dries. Section and function names only.

Adjacent: [pets.md](pets.md) is an older, status-less sketch of the same
subject and is superseded by these three — where it disagrees, this doc wins,
and the species table below is the corrected version of its.
[olfaction.md](olfaction.md) owns the smell model this doc's bait rides on.
[labor_skills.md](labor_skills.md) owns the `Skill` resource that Animal
Handling is an entry in.

## Design pillars

1. **The approach fails because the player is slower than the animal, and
   nothing says so.** This was the session's headline finding and the first
   explanation of it was wrong, so both are on the record here.

   The wrong one: that `Player.LASSO_RANGE` (72px, `scenes/player.gd:72`) sits
   inside `CreatureMarker.SENSE_RADIUS` (80px) "by construction", so a healthy
   wild animal could never be lassoed at all. **That is refuted by the code.**
   `CreatureMarker.FLEE_SPEED` is `40.0` against `Player.BASE_SPEED` `80.0` — a
   fleeing animal moves at *half* the player's walking pace, so an 8px gap
   closes in a fraction of a second, `FLEE_COMMIT_SECONDS` (1.1) holds the
   animal on one heading while it does, and
   `test_the_measured_catch_rate_matches_the_model`
   (`tests/unit/test_creature_marker.gd`) already measures sixty independent
   catch attempts resolving. Catching is possible. Widening the rope was never
   the answer, and neither was the arithmetic that said it had to be.

   The real one: **the player's speed is not `BASE_SPEED`.** It is
   `BASE_SPEED × current_speed_multiplier`, and that multiplier is the product
   of four independent penalties, composed once in `Player._authority_step`
   (`scenes/player.gd:1267`):

   ```gdscript
   current_speed_multiplier = (
       water_result.speed_multiplier
       * _weather_speed_multiplier()      # weather AND the freezing penalty
       * _terrain_speed_multiplier(tile)  # real slope, via TerrainPassability
       * ConditionPenalty.speed_multiplier(survival.fitness)
   )
   ```

   Each term is owned and already tested elsewhere:
   `WeatherModel.movement_speed_modifier` returns 0.85 in rain and 0.65 in a
   storm; `_weather_speed_multiplier` multiplies a further
   `ConditionPenalty.WORST_SPEED_MULTIPLIER` (0.75) on top while the player is
   freezing; `TerrainPassability.speed_multiplier` falls to
   `MIN_SPEED_MULTIPLIER` (0.3) on the steepest crossable ground; and
   `ConditionPenalty.speed_multiplier` interpolates down to 0.75 at rock-bottom
   `SurvivalMeters.fitness`. None of these is a husbandry number and none is
   changed by this doc.

   The consequence nobody wired together: the player stops being able to
   outrun a fleeing animal at a multiplier of exactly `FLEE_SPEED /
   BASE_SPEED`. **A storm while freezing is already past it** — 0.65 × 0.75 =
   0.4875, i.e. 39 px/s against a sheep's 40. In the live session
   (`docs/playtests/2026-08-26-taming-breeding-session.md`) the HUD read
   **`Speed: 47%`** through most of an autumn afternoon, and every approach
   failed; later the same session it rose to 75% and the approach immediately
   became viable.

   This is invisible. The HUD prints a percentage (`scenes/world.gd`'s status
   line, `"… Speed: %d%%"`); it never prints "you are now slower than a sheep."
   A player in rain, slightly cold, on a slope, concludes taming is broken —
   and for that afternoon, functionally, it is.

   **So chasing is the wrong verb to build the mechanic on at all.** That is
   the real argument for this doc's approach layer, and it is a much stronger
   one than the false arithmetic was: bait works *regardless* of the speed
   multiplier, because the animal comes to you; a stalk closes distance without
   a foot race, because the radius moves rather than the player. Both are
   immune to the exact failure that made the live session miserable. Pinned by
   `test_a_player_slowed_by_weather_and_terrain_cannot_outpace_a_fleeing_animal`
   — which composes the real multiplier terms and compares the product against
   `FLEE_SPEED / BASE_SPEED`, asserting neither number — with
   `test_an_unencumbered_player_outpaces_a_fleeing_animal` pinning the same
   relationship from the other side so a future retune of either constant fails
   loudly instead of quietly closing the game's entry verb.

2. **Keeping must cost something.** An animal you caught and forgot is
   currently free: `Taming.trust_after_neglect` and `Taming.NEGLECT_SECONDS`
   exist, are unit-tested, and have **zero production callers** — grep them and
   you find only `src/gameplay/taming.gd` and `tests/unit/test_taming.gd`. A
   permanently hungry tied horse loses nothing today. Husbandry *is* the
   ongoing cost; without it this is a collection minigame with animals as the
   collectibles.

3. **Every verb must name its animal.** `Player._throw_lasso`,
   `_nearest_tamed` and `_try_mount` all resolve to *nearest*. With four sheep
   in a pen there is no way to say which one you mean, so a herd is impossible
   by construction — not hard, impossible. Every multi-animal mechanic in this
   doc is downstream of fixing that one thing.

4. **The pen is made of the building system, not of a new one.** A fence loop
   contains animals because `EarthChunkManager.build_at_global` already calls
   `_sync_piece_collision`, and `CreatureMovementGate` already makes animals
   walk around solids. `RoomDetector`'s own doc comment already names the shape
   we want and deliberately throws it away: *"a walled ring with nothing in it
   is a fence, not a house"* (`src/gameplay/room_detector.gd:26`). The pen is
   that discarded case, promoted.

5. **Condition gates everything, and condition is visible.** Milk, wool,
   draught work and breeding are all functions of the animal's own energy,
   health, hunger and trust — values the simulation already holds. Precisely:
   energy is a **`CreatureMarker` field** (`var energy := 0.5`), advanced by
   `AnimalReproduction`'s pure `decay`/`feed` helpers — `AnimalReproduction`
   itself is a stateless static namespace and holds no per-animal state at all.
   Hunger and thirst live in `CreatureNeeds`, disease state on the marker via
   `DiseaseModel`, trust on the marker via `Taming`. A neglected animal does
   not "fail a roll", it simply gives less, then nothing. This keeps
   [labor_skills.md](labor_skills.md)'s "no failure state" rule and makes the
   readouts on the animal load-bearing instead of decorative.

6. **What you take out of the world has to come off the world's books.**
   `EcosystemSimulation` has `record_birth`, `record_catch` (fish) and
   `record_vegetation_harvest`. It has **no `record_death`** — verified, the
   symbol does not exist anywhere in the repo. Kill an animal and
   `_reconcile_chunk_creatures` (`src/world/earth_chunk_manager.gd`) quietly
   spawns another to match an aggregate that never heard about it. Hunting is
   mechanically weightless, and so, therefore, is choosing to farm instead.

## Real-world grounding

**Flight initiation distance.** The distance at which a prey animal starts to
move away from an approaching threat is a real, measured ethological quantity,
and it is not one number: it scales with body size (larger prey flee earlier —
they are worth more to a predator and less able to hide), with how exposed the
ground is, and with whether the animal has been disturbed recently. Handlers
exploit it in both directions: a stockman keeps *inside* the flight zone to
move an animal and steps *out* of it to let it settle, which is essentially the
whole of low-stress livestock handling. Modelling flight distance per species,
and letting it grow when an animal is spooked and decay when it is left alone,
turns the thing that currently blocks taming into the thing that makes both
stalking and herding playable.

**Nobody outruns livestock, and that is the point.** Real stockmen do not
chase. A human sprints faster than a sheep over ten metres and loses over a
hundred, and every traditional handling technique — bait, a dog, a race, a
gate, pressure and release — exists because the foot race is unwinnable. The
game's own numbers land in exactly the same place the moment weather and
condition are taken into account (pillar 1). The design should stop treating
that as a bug.

**Domestication is not taming.** A tamed animal is one individual that
tolerates you. Domestication is a multi-generation change to a *population*,
driven by which individuals get to breed. Every real domesticate went through
the same funnel — a species that could tolerate captivity, a keeper who chose
the calmer and more productive animals, and enough generations for that choice
to show. That is why breeding in this design is gated on a structure the player
had to build and stock, and why the pedigree is recorded: the payoff for
husbandry is supposed to arrive over generations, not per animal.

**Stocking rate and overgrazing.** The oldest real constraint in pastoralism is
that a fixed area regrows a fixed amount of forage per season, and stock beyond
that number strips it. Overgrazing does not merely slow regrowth; it degrades
the sward and lowers what the land can carry afterwards. This project already
models exactly that: `TallGrass` regrows, `EarthChunkManager.graze_grass_at`
and `_graze_by_herbivores` already feed real bites into
`EcosystemSimulation.record_vegetation_harvest`, and sustained harvest above
the regrowth rate already depletes land health, which lowers herbivore carrying
capacity. A penned flock would be standing on that machinery already — see
"Consequence" below.

**A fence removes an animal's own solution.** A hungry animal that can walk
away does. A hungry animal behind a gate cannot, and dies where it stands.
Every real husbandry ethic — and every real animal-welfare law — starts from
that asymmetry: confinement transfers responsibility for the animal's needs
onto whoever built the fence. It is also the sharpest available answer to "why
should a pen cost me anything", and it is why the neglect outcome in this doc
differs from the one in [taming.md](taming.md) rather than contradicting it.

**Products are conditional on the animal, not the calendar.** A dairy animal in
poor body condition dries off. A sick one is not milked. Fleece is annual, and
shearing before winter kills sheep, which is why real shearing happens in
spring. Tying yield to condition and season is not a difficulty knob; it is the
actual biology, and it is what makes feeding the animal a decision rather than
a chore.

## Mechanism spec

### 1. The approach

Four layers, in the order the player meets them. All four reuse machinery that
is already in the tree, and all four exist because pillar 1's foot race cannot
be won on an ordinary rainy afternoon.

**Bait.** The player drops or throws a food item and steps back. This is very
nearly built already: `EarthChunkManager.smells_near` publishes every ground
item of `kind == "food"` as an olfaction source, `CreatureMarker._seek_by_smell`
already walks a creature up the gradient, and `HeldItemThrow` + `ChargeMeter`
already put an item on the ground at a chosen distance. A boar already walks to
a dropped apple. Four verified gaps stop it being a husbandry verb:

- `Olfaction.fruit_mixture(_item_id, freshness)` **ignores its item id**
  (`src/gameplay/olfaction.gd:49` — the parameter is literally named with a
  leading underscore) — every food emits the same fruit mixture, so a carrot is
  no better a lure for a horse than a walnut is. Replace it with a per-item
  mixture table (`bait_mixture`), keeping `fruit_mixture`'s ripe-to-rotten
  interpolation for actual fruit. Driven by
  `test_a_carrot_and_an_apple_do_not_smell_the_same` and
  `test_every_food_item_in_the_catalog_has_a_mixture`, which iterates
  `ItemCatalog` so a food added later cannot be silently scentless.
- `Olfaction.RECEPTORS` covers **boar, deer, horse, robin and fly only** —
  five entries, counted. Sheep, goat, reindeer, camel and tapir have no nose at
  all, so nothing you put on the ground exists for them. Driven by
  `test_every_keepable_species_has_a_nose`, iterating this doc's own roster
  against `RECEPTORS`.
- `CreatureMarker._seek_by_smell` returns false unless the species' forage
  kinds include `GrazerForaging.FOOD_FRUIT` — and
  `FORAGE_KINDS_BY_DIET["Grazer"]` is `[FOOD_GRASS]`, so every plain grazer
  (horse, sheep, goat, camel, reindeer) is excluded. Bait needs its own kind
  (`FOOD_BAIT`) that any species with a nose will walk to, independent of its
  ordinary diet: an animal crossing a field for something it would not normally
  forage for *is* what baiting means.
- `EarthChunkManager.take_fruit_at` only removes items whose id is in
  `TreeSpecies.IDS`, so a baited carrot can be walked to and never eaten — the
  animal would stand over it forever. Needs a `take_bait_at` sibling, the same
  shape as `take_worm_at`/`take_seed_at`.

The pull has to actually beat the animal's avoidance of the player, or bait is
decoration. Pinned by
`test_a_baited_animal_crosses_ground_it_would_otherwise_avoid_the_player_for` —
measured over simulated approaches, not asserted as a weight — and bounded by
`test_bait_beyond_smelling_range_draws_nothing` against
`Olfaction.MAX_RANGE_TILES` (20.0 tiles). Bait is also the layer that answers
pillar 1 directly, so it gets its own guard:
`test_bait_works_at_any_player_speed_multiplier`, which runs the same approach
at a multiplier below `FLEE_SPEED / BASE_SPEED` and asserts the animal still
arrives. That is the whole reason bait is first in this list.

**The stalk.** A hold-to-crouch action (a new `keybindings.gd` entry; `KEY_X`
and `KEY_Z` are both free in the current 26-action registry) that scales the
animal's effective flight distance down while the player moves slowly. Not a
new perception system — the marker's throttled threat scan already looks for
the player every `SENSE_INTERVAL`; crouch changes the radius that scan compares
against. It must cost movement speed, or it is a free permanent state: pinned
by `test_crouching_is_slower_than_walking` as a ratio against
`Player.BASE_SPEED`, the same relative-property shape
`test_riding_is_faster_than_walking` (`tests/unit/test_taming.gd:161`) already
uses for `Taming.MOUNTED_SPEED`.

**The shy threshold.** This doc owns it, because it belongs to the approach and
not to the rope. It is the approach speed above which the player reads as a
rush *regardless* of bait, crouch or trust — the animal's flight response is
not suppressed at all, and a hand-offered treat is refused. Not an eyeballed
number of pixels per second: it is pinned by ordering against constants that
already exist, `FlightDistance.SHY_SPEED` sitting strictly above the crouch
speed and at or below `Player.BASE_SPEED`. Driven by
`test_a_crouched_approach_is_never_a_rush` and
`test_a_mounted_approach_is_always_a_rush` (`Taming.MOUNTED_SPEED` is 150.0
against `BASE_SPEED` 80.0, so riding a horse up to a wild sheep should never
work and today silently might). [taming.md](taming.md)'s refused-offer test
honours this threshold rather than restating it.

**Flight distance, as one function.** `SENSE_RADIUS` is one constant for every
creature in the world, which is why a mouse and a horse currently react
identically. Replace the threat half of it with a single composed function —
**one owner, one signature**, so that no sibling doc defines a second:

```gdscript
FlightDistance.radius(species, wariness, trust, crouched) -> float
```

Species sets the base. Wariness multiplies it **up**. Trust multiplies it
**down** — that is the whole of [taming.md](taming.md)'s contribution here, and
that doc explains what earning trust *means* rather than redefining this
function. Crouch multiplies it down again. Do not pin the numbers; pin the
ordering and the outcome:

- `test_a_larger_prey_animal_flees_earlier_than_a_smaller_one` — mouse <
  sheep < goat < deer < horse, the real body-size relationship.
- `test_a_graded_flight_radius_never_dithers` — **the single owner of the
  Schmitt-gap invariant.** Every radius the composed function can return, over
  every legal combination of its four inputs, must stay below
  `FLEE_RELEASE_RADIUS` (120.0, `creature_marker.gd`), or the Schmitt trigger
  that fixed the measured flee-dithering bug inverts and the animal oscillates
  again — the file's own comment records the measurement that bug produced
  (16–23 facing flips per 30 simulated seconds). This test lives here and
  nowhere else; no sibling doc may define a second test for the same
  invariant.
- `test_a_higher_trust_animal_lets_you_closer` and
  `test_crouching_shrinks_the_radius_a_spooked_animal_widened` — the two
  composition directions, asserted as orderings so the multipliers can be
  retuned without rewriting the tests.
- **The one that matters:**
  `test_a_crouched_baited_approach_lands_within_lasso_range`, which runs sixty
  real approaches against a real marker and asserts a workable success rate —
  the same measured-not-derived discipline
  `test_the_measured_catch_rate_matches_the_model` already established for the
  catch itself, and for the same reason: the quantity the player experiences is
  the outcome of a compounding loop, not any single constant inside it.

**Wariness, and how a spooked animal recovers.** An animal that has just fled
should be harder to approach than one that never noticed you, and it should get
over it. A per-individual `wariness` in [0,1], raised on each flee onset and
decaying while nothing threatens, feeding `FlightDistance.radius` as its second
argument. It is a ramp, not a flag — the same "thresholds are ramps or
hysteresis, never hard switches" rule
[ecosystem_dynamics.md](ecosystem_dynamics.md) enforces everywhere else. Pinned
by `test_a_spooked_animal_flees_earlier_than_a_calm_one`,
`test_wariness_never_leaves_its_range`, and — for the recovery time, which must
not be an eyeballed number of seconds —
`test_a_spooked_grazer_is_approachable_again_within_a_few_grazing_bouts`,
expressed as a ratio against `GrazerForaging.GRAZE_SECONDS` /
`REGRAZE_SECONDS` so it stays correct if grazing is ever retuned.

**What the player presses for wariness is nothing, and that is deliberate.**
Wariness decays by *absence*: the input is leaving the animal alone. That is a
real verb in a game about patience — it is the only mechanic in this doc whose
correct play is to walk away — but it is the one place where the doc's own "what
does the player press" rule is answered with restraint rather than a key, so it
is called out here rather than hidden. The player still chose it: they chose to
spook the animal, and they choose when to come back.

This is also the herding mechanic, arriving early. Once flight distance is a
real per-animal quantity the player can see, standing inside it moves the
animal and stepping out of it lets the animal settle — see "Work" below.

### 2. Choosing an animal

The selection machinery already exists and is simply not wired to the verbs.
`CreatureMarker` already joins the shared `HoverTargetFinder.GROUP_NAME` and
already answers `get_display_name()`; `HoverTargetFinder.info_under` already
returns the closest candidate to the mouse. What is missing is a persistent
selection, and verbs that read it.

**The mechanism is a click-latched selection, not a hover.** Hovering is a
mouse position; a taming verb is a key press, and the two happen at different
moments. A player who clicks a sheep, then moves the mouse while reaching for
`R`, must still be throwing at the sheep they picked.

- `Player.selected_animal`, **set by clicking a creature**, cleared when it
  dies, is freed, or leaves range, and drawn with a **selection ring**. Every
  animal verb (`_throw_lasso`, `_cycle_order`, `_try_mount`, and everything
  this doc adds) reads the selection first.
- **Hover is the fallback, and so is nearest.** With nothing selected, the
  hovered animal is used; with nothing hovered, the existing nearest-animal
  behaviour is unchanged, so the tested single-animal loop in
  `tests/unit/test_creature_marker.gd` keeps passing rather than being
  rewritten.
- The single test name, used in this doc and referenced by the others with
  **this exact spelling and no other**:
  `test_a_verb_prefers_the_selected_animal_over_a_nearer_one`. Its regression
  guard is `test_with_nothing_selected_a_verb_still_takes_the_nearest`, and the
  latch itself is pinned by
  `test_a_selection_survives_the_mouse_moving_off_the_animal`.
- `CreatureMarker.get_hover_actions()` **does not exist** — verified. It is not
  the only hoverable without one: `fish_marker.gd`, `piscivore_bird_marker.gd`
  and `ambient_flyer_marker.gd` are also in the group without it (11 of the 15
  joiners implement it). It *is* the only **tameable** entity without one,
  which is the part that matters: the one thing in the world the player has a
  rich verb set for is the one thing that hovers with a name and no verbs.
  Adding it gives the animal a tooltip with live keybinding glyphs for free via
  `World._update_hover_tooltip`.
- The live session's other complaint belongs here too: nearby-creature panels
  read `"Sheep Lv.4 / HP 31/31"` and nothing else, so five animals are an
  anonymous stack of near-identical cards. A selected animal's panel should
  show what the marker already holds — trust, hunger, thirst, energy, disease
  state — gated by Animal Handling tier (see "Mastery").

### 3. The pen

A pen is a closed loop of fence with a gate, placed tile by tile through the
path that already exists.

**Pieces.** Two new `BuildingPiece` rows beside the existing twelve in
`PIECE_IDS`: `wood_fence` (encloses, not walkable) and `wood_gate` (encloses
**and** walkable, exactly the trick the door row already uses and which that
file's own comment calls the row worth reading twice). Both take
`support_capacity` `0.0` — that field is a **categorical flag, not a tuned
number**: `building_piece.gd`'s own contract is `>0.0` for a load-bearing piece
(every `CATEGORY_WALL` piece) and `0.0` for everything else, and a fence
carries no load. Cost is pinned relatively, not absolutely:
`test_a_fence_costs_less_than_a_wall`, because a fence is deliberately the
cheap structure — the barrier to husbandry should be feeding the animals, not
felling the trees.

**Placement.** Unchanged from today: arm the item (`Player._arm_placeable`),
press build (`Player._build_step`), `EarthChunkManager.build_at_global` writes
the modification and calls `_sync_piece_collision`. Containment then falls out
of collision and `CreatureMovementGate` with no new rule at all. Driven by
`test_a_penned_animal_does_not_leave_through_a_closed_gate` and
`test_an_open_gate_lets_it_out` — the gate being a thing the player opens and
shuts is the pen's most-used verb, and the reason a pen is a place rather than
a container.

**Recognising an enclosure.** Extract `RoomDetector.enclosures(grid)` — the
existing `_flood` with the `_has_floor` filter lifted out — and redefine
`find_rooms` as `enclosures` filtered by `_has_floor`. `find_rooms` has exactly
two callers: `RoomDetector.room_containing` in the same file (which
`is_indoors` delegates to), and `EarthChunkManager`'s roofed-piece pass, which
already calls it once per chunk precisely to avoid re-flooding per piece. So:
one refactor, two callers, no second flood-fill. Driven by
`test_a_walled_ring_with_no_floor_is_an_enclosure_but_not_a_room`, with the
existing `tests/unit/test_room_detector.gd` cases as the regression guard.

**Stocking rate.** `PenCapacity.max_stock(cells, species)` — how many animals
an enclosure of a given area supports. Pinned by
`test_a_bigger_pen_holds_more`, `test_a_horse_needs_more_room_than_a_sheep`,
and the one that makes the number honest:
`test_stocking_at_capacity_does_not_outstrip_the_pasture`, which runs a pen at
its stated capacity against real `TallGrass` regrowth and
`record_vegetation_harvest` for a simulated season and asserts land health does
not fall. The capacity is thereby *derived from* the vegetation model rather
than chosen and commented.

**A pen consumes the chunk's marker budget, and the player must not be
punished for it.** This is not an open question; the code answers it. Kept
animals are appended to `_loaded_creatures[chunk_coord]` by
`_restore_kept_animals`, `_reconcile_chunk_creatures` counts everything in that
list as `alive` against a `target` derived from the *aggregate* population, and
`_thin_creatures` refuses to cull anything with `trust > 0.0` or
`is_restrained()`. Composed, that means **a pen of six sheep permanently
suppresses wild marker spawning in its chunk** — the reconcile sees six animals
already alive, spawns fewer wild ones to match the target, and cannot remove
the six to make room. The same holds at scene scale:
`World._step_reproduction` counts `CreatureMarker.GROUP_NAME`, which kept
animals join, against `MAX_LIVE_CREATURES` (60), so a barn also eats into the
world's global birth budget.

Left alone, the player's reward for building a pen is a valley that visibly
empties of wildlife. The fix is a **reserved budget**: kept animals are counted
separately from the wild target in `_reconcile_chunk_creatures`, matching the
intent `KeptAnimals`' own doc comment already states — *carrying capacity
governs wild animals, and kept ones are extra*. Driven by
`test_a_pen_does_not_suppress_wild_spawning_in_its_chunk` and
`test_kept_animals_still_count_against_the_scene_safety_cap` (the 60-marker cap
is a performance bound, not an ecological one, and must keep applying to
everything).

**Contents persist as individuals.** `KeptAnimals` is versioned and round-trip
tested and was built to be extended; `FORMAT_VERSION` goes to 2. **The complete
V2 record is defined in [animal_genetics.md](animal_genetics.md)**, which owns
the field union, the byte budget and the V1 upgrade path. The fields *this* doc
requires it to carry are: `wander_seed`, age, energy, hunger/thirst, disease
state, **pen id**, **player-given name**, **discovered food preferences**,
**kept-since time**, **escape memory**, and both parent ids — plus the rest of
the V2 record, defined in animal_genetics.md.

Persistence closes a verified bug, not just a nicety: `_restore_kept_animals`
rebuilds a saved animal through `CreatureRenderer.spawn_single`, which passes
**`randi()`** as the seed. A kept animal's level, `max_health` and
needs-stagger are therefore re-rolled on every chunk reload, and a bred
animal's genome would evaporate the moment the player walked away.
`spawn_single` itself is **not** changed — it is documented as deliberately
non-deterministic for the dev console's `/spawn`, and
`test_spawn_single_still_produces_unrelated_individuals` guards that. The
restore path instead calls the seed-carrying public sibling
`animal_genetics.md` adds (`spawn_offspring`), which routes to the same private
`_build_marker` with a real seed. Driven by
`test_a_kept_animal_keeps_its_identity_across_a_reload`.

**New Game leaks the previous world's livestock.** `KEPT_ANIMALS_DIR` and
`ECOLOGY_DIR` (`earth_chunk_manager.gd`) are absent from **both**
`World.backed_up_directories()` **and** `World._wipe_persisted_world` — so a
previous world's stock walks into the new one, unbacked-up and undestroyed.

The existing `tests/unit/test_world_backup_paths.gd` does **not** pin the wrong
set, and this is worth stating precisely because three earlier drafts got it
backwards. Its drift test asserts
`backed_up_directories().size() == body.count("_world_reset.wipe_directory(")`
against `_wipe_persisted_world`'s own source text, and today both sides are 4.
That test is *correct and internally consistent*; adding a directory to the
backup list alone would **break** it. Red-first here therefore means a **new**
test, mirroring the roof-directory test that already lives in that file
verbatim:
`test_the_kept_animal_and_ecology_directories_are_wiped_and_backed_up_like_their_siblings`,
asserting both the `wipe_directory(...)` substring and the backup-list
membership. The work is two `wipe_directory` calls plus two list entries,
landing together so the existing drift pin stays green throughout.

### 4. Keeping: feed, water, shelter, neglect

This is the section that makes the word "husbandry" honest. Four ongoing costs,
each of which the player can satisfy or fail to.

**Feed.** A trough placed inside the pen, holding fodder in a `StructureStock`
(`src/emergence/structure_stock.gd`, whose own doc comment says it is
deliberately generic — "one placed structure's stock" — so this needs no third
container design). A penned animal on bare or grazed-out ground eats from the
trough; an empty trough feeds nobody. Fodder is grass, wild carrot and, later,
[farming.md](farming.md)'s crops, so the pasture and the trough are two ways of
solving the same problem and the player picks. Drawdown is pinned as a ratio,
never as a rate: `test_a_full_trough_carries_a_penned_flock_across_a_night`,
measured against `CreatureNeeds.HUNGER_RATE_PER_SECOND`, plus
`test_an_empty_trough_feeds_nobody`.

**Water.** `CreatureNeeds.is_thirsty` and
`CreaturePerception.nearest_direction(..., "water")` already exist; today a
penned animal simply cannot reach the water tile it would walk to. Either site
the pen near water or place a water trough.
`test_a_penned_animal_with_no_water_in_reach_goes_thirsty` is the failing test;
the design consequence is that where the player puts the pen becomes a real
decision with a real cost.

**Shelter, and which predicate it reads.** `RoomDetector.is_indoors` does
**not** mean "under a roof". It means "inside an enclosed region that contains
at least one floor piece" — enclosure comes from `BuildingPiece.encloses`, and
`find_rooms` additionally requires `_has_floor`. Roofs are not consulted at
all. That collides head-on with this doc's own pen, which is deliberately the
*floorless* ring promoted to `enclosures()`: read naively, a floored pen would
be sheltered with no roof over it, and a roofed pen on bare earth would be
unsheltered.

So state it: **shelter reads `is_indoors`, unchanged, and a shed is therefore a
floored, walled structure — a building, not a pen.** The pen (`enclosures`)
keeps animals in; the shed (`find_rooms`/`is_indoors`) keeps weather off; a
player who wants both builds a shed inside the pen, which is what a real
steading looks like anyway. `is_indoors` has **zero production callers today**
(only comments reference it, and `EarthChunkManager` deliberately avoids it for
its per-piece roof pass on cost grounds), so shelter would be its first — which
makes `test_a_floorless_pen_is_an_enclosure_but_not_shelter` a genuinely
load-bearing test rather than a restatement.

An unsheltered animal loses condition in bad weather — the weather model,
`WetnessTracker` and the freezing meter are all live — which lowers its yield
through the same condition term everything else reads. Driven by
`test_an_unsheltered_animal_loses_condition_in_a_storm`.

**Crowding, and the term that does not exist yet.** Shelter has a cost of its
own: packing stock into a small shed should spread disease faster. This does
**not** fall out of `DiseaseModel` today, and the doc must not pretend it does.
`herd_transmission_chance(local_population, carrying_capacity, region_tier)` is
**regional density**, not proximity — `CreatureMarker._herd_disease_step` uses
distance only to pick which neighbour to try, and the chance itself comes from
`EarthChunkManager.herbivore_population_near` / `herbivore_capacity_near`,
which are chunk **aggregates**. Kept animals are deliberately excluded from
those aggregates ("Consequence" below), so six sheep in a shed move
`local_population` by exactly zero.

The new term is therefore explicit new code: `Husbandry.pen_crowding(stock,
capacity)` in [0,1] over the pen's *own* stock against its own
`PenCapacity.max_stock`, feeding a sixth transmission-chance function beside
`DiseaseModel`'s existing five (`herd_`, `predator_bite_`,
`carcass_contamination_`, `decomposer_carry_`, `carrion_graze_`):
`pen_transmission_chance(crowding, region_tier)`, built in
`herd_transmission_chance`'s exact density-ratio-times-region-pressure shape so
there is one transmission idiom in the file and not two. Note `DiseaseModel`'s
methods are instance methods on a `RefCounted`, not statics — `CreatureMarker`
already holds `var _disease_model := DiseaseModel.new()`, and the pen path uses
that same instance rather than calling the class. Driven by
`test_a_crowded_pen_spreads_disease_faster_than_a_roomy_one` and, guarding the
exclusion that made this necessary in the first place,
`test_a_pen_at_capacity_does_not_move_the_regional_herd_risk`. That tension
(warm and close vs. cold and spread out) is the design content of shelter; a
shed that was purely a bonus would not be worth building the system for.

**Neglect: trust first.** Wire `Taming.trust_after_neglect`. `CreatureMarker`
accumulates `_hungry_seconds`, reset by `feed_treat()` or a real graze, and
applies the already-written decay past `Taming.NEGLECT_SECONDS` (600s). Driven
by `test_a_tied_animal_left_hungry_loses_trust`, which fails today because
nothing calls the function.

**Neglect: the penned animal starves, and only the penned one.** This doc and
[taming.md](taming.md) specify different outcomes for the same neglect, on
purpose, resolved by context:

- An animal that is **free to leave** — following, staying, or tied where an
  untied option exists — **walks off and goes feral.** That is
  [taming.md](taming.md)'s, and its argument is correct: killing it is the
  cheaper implementation and the worse story. The animal solved its own
  problem, and the player lost it by not being worth staying for.
- An animal that is **penned cannot leave.** That is precisely what makes
  penning a responsibility rather than free storage. A penned animal that is
  never fed **starves**, through the existing `CreatureMarker._die()`. **The
  fence removed the animal's own option to solve the problem**, so the
  consequence lands on the player who built it. Driven by
  `test_a_penned_animal_left_long_enough_without_food_dies` and — the boundary
  that keeps the two docs from colliding —
  `test_an_unpenned_animal_left_hungry_leaves_instead_of_dying`.

One verified gap this exposes, which no draft caught: `_die()` calls
`_spawn_carcass_if_eligible`, which returns immediately when
`LootTable.drops_for(species)` is empty — and `LootTable._DROPS` covers only
`herbivore`, `boar`, `predator` and `lynx`. **A dead sheep, goat, horse, deer,
camel or reindeer leaves no carcass at all today**, it simply vanishes. So a
starved animal does not join [carrion.md](carrion.md)'s loop until the keepable
roster has loot rows (hide + meat, following the `herbivore` row's shape).
Driven by `test_every_keepable_species_leaves_a_carcass`, iterating this doc's
roster against `LootTable.drops_for`. Losing stock to your own negligence,
visibly, on the ground, is the consequence that makes the trough worth filling
— and right now the "on the ground" half does not happen.

### 5. Breeding: the player's half

[animal_genetics.md](animal_genetics.md) owns what the child inherits. This doc
owns who is allowed to breed, how the player says so, and what is written down
afterwards.

**The pairing gate.** `Husbandry.can_pair(a, b)` — a pure predicate over two
animals' state:

- same species;
- both adult. `LifeCycle.can_court_at` exists and — correcting an earlier claim
  in this doc — it **does** have production callers: `AmbientFlyerMarker` calls
  it, along with `LifeCycle.size_scale_at` and `MATURE_SECONDS`. Only
  `LifeCycle.stage_at` is uncalled. What is true, and is the thing that matters
  here, is that **`CreatureMarker` never calls `LifeCycle` at all**, so there
  is no existing age composition point on the mammal path; this is a new seam,
  not a reused one;
- both in condition (`AnimalReproduction.REPRO_ENERGY_THRESHOLD` /
  `REPRO_HEALTH_THRESHOLD` and the marker's own `energy` field, reused rather
  than re-derived);
- both tame (`Taming.is_tame`) — a half-trusting animal is one you are holding
  by a rope, not one you are breeding;
- both inside the **same enclosure**;
- not close relatives, per the pedigree below.

Driven by `test_two_animals_in_different_pens_cannot_be_paired`,
`test_a_hungry_animal_will_not_breed`,
`test_a_wild_animal_standing_in_a_pen_is_not_a_breeding_candidate`, and
`test_full_siblings_cannot_be_paired`.

**The player's act.** Select two animals (section 2), open the pen panel, and
confirm the pair. The panel is the existing card-grid-with-live-requirements
pattern `scenes/crafting_window.gd` already proves — green/red on each gate
above, so a refused pairing tells you *which* condition failed. That is the
whole difference between a breeding system and a breeding button.

**Gestation, and why it does not use the wild clock.**
`AnimalReproduction.REPRO_COOLDOWN` is 24 real hours,
`_seconds_since_birth` is not persisted and resets on chunk unload, and
`/ecotest` does not advance it — so the wild individual-birth gate essentially
never opens. That constant is *correct for wild animals* and should stay:
[ecosystem_dynamics.md](ecosystem_dynamics.md) and `LifeCycle`'s own doc
comment are right that a player parked in a meadow must not get to farm
wildlife. A deliberate pairing in a pen the player built, fenced, stocked and
watered is a different event with a different price already paid, so it gets
its own `Husbandry.GESTATION_SECONDS`, pinned as a fraction of
`LifeCycle.SECONDS_PER_REAL_DAY` (86400.0) by
`test_a_deliberate_pairing_resolves_within_a_single_evening_of_play` — and,
unlike the wild clock, **persisted**:
`test_gestation_survives_a_chunk_reload`. This is the doc's answer to "you can
only watch": the wild population stays slow and unfarmable, and the pen is the
one place the player bought the right to see a result.

**The pedigree.** Each kept animal records its two parents' ids (carried by the
V2 record `animal_genetics.md` defines). This doc owns the record and the "not
close relatives" refusal; [animal_genetics.md](animal_genetics.md) owns what
relatedness does to the resulting traits. A lineage line in the pen panel is
what turns a bloodline from a number into something the player is visibly
building.

### 6. Production

Grounded in the roster that actually exists. **There is no cow and no chicken
in `CreatureInfo`** — `MAX_HEALTH_BY_SPECIES` has no such entries, so
[pets.md](pets.md)'s "cows are farmed for milk" names a species the game does
not have. Adding one is a known, documented path (stats in `creature_info.gd`'s
five tables, a shape family in `ProceduralAnimalSprite`, an `AnimalAnatomy`
profile, a biome-pool entry in `CreatureRenderer` — exactly what wolf and sheep
went through, recorded in `ecosystem_dynamics.md`'s status list), but the first
production loop should ship against species that are already in the world.
There is likewise **no egg**, because there is no bird to lay one; egg is not
in this doc's product list and is not in its status list.

| species | product | act | cadence | why (real) |
|---|---|---|---|---|
| sheep | wool | shear | fleece regrows over real time; seasonal | fleece is annual, and shearing before winter kills sheep |
| goat | milk | milk | while in condition | the smallholder's dairy animal, and it browses woody scrub nothing else eats |
| camel | milk, pack | milk / load | while in condition | camel milk is a real staple; the camel is a pack animal before it is anything else |
| horse | draught, mount | hitch / mount | on demand | mounting already exists (`Taming.RIDABLE_SPECIES`) |
| reindeer | draught, milk | hitch / milk | while in condition | the only widely domesticated deer, used for draught and milk in Sápmi |
| dog (new) | guard, herding | order | on demand | see "Work" — the roster has no domesticable guard animal today |
| deer, boar, tapir, mouse | none | — | — | deliberate: not everything you can catch is stock |

That last row is content, not a gap. The difference between an animal worth
keeping and one that is merely tameable is the first real thing husbandry
teaches the player.

**Yield is a function of condition — and of the animal.**

```gdscript
Husbandry.yield_fraction(energy, health_fraction, trust, is_sick, heritable_yield) -> float
```

in [0,1], multiplying whatever the product's base amount is. The first four
arguments are the condition term; the fifth is the **only place in this design
where breeding pays off in a number the player can weigh**, and without it a
champion bred over six generations gives exactly as much milk as a sheep caught
this morning. This doc owns the reader; [animal_genetics.md](animal_genetics.md)
owns which gene supplies the value and how it is inherited — this signature is
the interface contract between them, and the value is a plain [0,1] fraction so
that either a dedicated productivity gene or an existing one can fill it.
Pinned by properties, never magnitudes:
`test_a_hungry_animal_gives_less_than_a_well_fed_one`,
`test_a_sick_animal_gives_nothing`,
`test_an_untrusting_animal_will_not_stand_to_be_milked`,
`test_yield_never_leaves_its_range`, and the one that makes husbandry a
project rather than a chore,
`test_a_bred_ewe_out_yields_a_wild_caught_one_at_equal_condition`.

**The act is a player act.** Milking and shearing are hold-to-perform, resolved
through the world-space charge meter `World._build_charge_meter` already draws
for the held-item throw. Explicitly not a timer that deposits milk into a chest:
the entire complaint this doc answers is that things happen without the player.
Shearing additionally checks the season —
`test_shearing_before_winter_costs_the_animal_condition` — and cannot be
repeated on a bare sheep:
`test_a_sheep_shorn_today_cannot_be_shorn_again_tomorrow`, against a
per-individual fleece fraction that regrows on world time (the same clock
`DroppedItem.ages_on_world_time` already uses, so `/ecotest` moves it).

**The items do not exist yet.** There is no `milk` and no `wool` item anywhere
in `src/` — the only `wool` string in the codebase is `coziness_score.gd`'s
`"wool_rug"` furniture entry, which has no producer. Each needs a catalog
entry, a `ProceduralItemSprite` case, and — the part worth planning rather than
discovering — a *consumer*: milk into [cooking.md](cooking.md)'s recipes, wool
into a cloth armour tier beside the existing leather one, and into the
`wool_rug` that is already sitting there waiting for a source. A product with no
consumer is a number in a bag.

### 7. Work: guard, draught, herding, pack

**Guard, and the dog problem.** The roster's only plausible guard animals are
predators, and `Taming.can_be_tamed` refuses predators outright — correctly:
being hunted by the thing you tied up is not taming. But a dog is not a wolf,
and pretending it is would be worse design than adding the species. Add `dog`
using the precedent `creature_info.gd` already documents at length for the
boar: **aggressive temperament, but not in `PREDATOR_SPECIES`** — that file's
own comment says it outright, *"a boar is aggressive but not a predator"* — so
`CreatureBehavior._will_fight` makes it stand and fight while nothing marks it
a hunter. No new mechanism, one roster entry across the five stat tables.
Driven by `test_a_dog_can_be_tamed_but_a_wolf_cannot`.

**What guarding actually is, and what the player presses.** A third value in
the `ORDER_*` cycle `Taming.next_order` already rotates (today a two-state
flip between `ORDER_FOLLOW` and `ORDER_STAY`). The player selects the dog and
presses the order key until it reads Guard; the dog holds the position it was
standing on and `_will_fight` does the rest against anything that comes near.
Guard is a *higher trust tier* than follow — see below — so it is something
earned rather than toggled. Driven by
`test_a_guarding_dog_holds_its_post_while_a_following_one_leaves_it`,
`test_a_guarding_dog_engages_what_a_staying_sheep_ignores`, and the regression
guard the widened cycle needs,
`test_the_order_cycle_returns_to_follow_after_guard`.

**One loyalty scale, not two.** `src/gameplay/pet_loyalty.gd` is complete,
tested, and has zero callers; it defines its own [0,1] scale with
`FOLLOW_THRESHOLD` 0.4 and `GUARD_THRESHOLD` 0.75, while `Taming.accepts_orders`
has exactly one flat gate at `TAME_TRUST`. Wiring `pet_loyalty` would give kept
animals two independent relationship numbers, which is precisely the parallel
system this project's process rules forbid. **Taking its idea into `Taming` and
retiring the file is [taming.md](taming.md)'s to specify** — it is a trust
concern, and trust is that doc's. This doc only depends on the outcome: a
tiered order gate exists, and Guard sits above Follow on it.

**Draught.** Hitch a horse or reindeer to a `FelledTree`
(`src/rendering/felled_tree.gd`, already a real world entity) and it drags what
the player cannot carry. Real grounding: skidding logs is the oldest job
draught animals do, and it predates the cart. Driven by
`test_a_hitched_horse_moves_a_log_a_player_cannot`.

**Herding — the best reuse in this doc.** Do not build a herding AI. Flight
distance (section 1) already is one: the animal moves directly away from the
player via `CreatureBehavior._away_from`, so walking into a flock's flight zone
pushes it and stepping out lets it settle. That is real pressure-and-release
stockmanship, and it is the same code that currently frustrates the lasso.
Note the honest limit: at a speed multiplier below `FLEE_SPEED / BASE_SPEED`
the player cannot push a flock *forward* any faster than it retreats, which is
why herding wants the flight zone visible — a handler who can see the ring
works the edge of it instead of chasing. On top of that, one call/whistle action
(a `keybindings.gd` entry) applies the player's current order to every tame
animal in earshot — half-plumbed already, since
`Player._step_mount_and_orders` already pushes `follow_target` to *every* tame
animal while `_cycle_order` commands exactly one. Driven by
`test_a_flock_moves_away_from_a_handler_inside_its_flight_zone`,
`test_backing_off_lets_the_flock_settle`, and
`test_the_call_orders_every_tame_animal_in_earshot`.

**Pack.** A camel or reindeer carries a second `Inventory`
(`Inventory.new(slot_count)` — no new container type), opened through the
selection. Driven by `test_a_pack_animals_load_survives_a_reload`, which is
also a V2-record test.

### 8. Mastery: Animal Handling

[labor_skills.md](labor_skills.md) already lists **Animal Handling** in its
roster (feeding "taming odds, bond-rate"); everything in that doc, this skill
included, is ⬜. This doc names what the skill actually changes, and it is
deliberately not a damage number.

**Mastery is an information axis.** A novice sees `"Sheep Lv.4 / HP 31/31"` —
which is what the game shows today, and which is exactly why the player feels
like a spectator. Tiers unlock *readouts the simulation already computes*:

- **Novice** — name, level, health. Can catch a worn-down animal, keep one.
- **Apprentice** — hunger, thirst and trust on a selected animal; can shear and
  milk.
- **Journeyman** — energy/body condition and disease state; can hitch and drive
  a flock. **Also the flight-zone ring** — judging distance by eye is the
  literal skill being modelled.
- **Expert** — a candidate's **phenotype**, read through
  [animal_genetics.md](animal_genetics.md)'s `AnimalGenome`. Explicitly **not**
  `AnimalFitness.phenotype_for`: that function's only argument is
  `seed_value: int`, so it derives traits from a seed and would return the
  wrong answer for any bred animal, whose genome is a crossover result and by
  construction not a function of one seed. (It is also an instance method on a
  `RefCounted`, not a static, so any caller instantiates it first — the same
  shape `EarthChunkManager` already uses for `RoomDetector`.) Judging an animal
  by eye is real stockmanship, and it has to read the animal's real genome.
- **Master** — the predicted-offspring preview in the pen's pairing panel.

Driven by `test_a_novice_cannot_read_a_candidates_condition`,
`test_an_expert_reads_a_phenotype_a_novice_cannot`, and the correctness guard
that keeps the Expert tier honest,
`test_an_experts_read_of_a_bred_animal_matches_its_real_genome`. This keeps
[labor_skills.md](labor_skills.md)'s pillar 5 (no failure state) intact — a
novice still tames, still shears, just blind — while making the answer to "what
does an expert do differently" something other than a bigger number.

**XP is value-weighted**, per that doc's own pillar: a fresh, full-condition
animal teaches more than one you exhausted first
(`test_taming_a_fresh_animal_teaches_more_than_taming_a_spent_one`), and
trivial repetition at high skill yields less. The tier thresholds and the
`ceiling_realization` curve applied to product yield are
[labor_skills.md](labor_skills.md)'s to define; this doc only supplies the
actions that feed them.

### 9. Consequence

**✅ BUILT (2026-08-27), with one divergence from what this section first
specified.** The signature below said `record_death(chunk_coord, count)`,
mirroring `record_birth`, which only ever touches the herbivore pool. That
turned out to be wrong for deaths: the aggregate keeps **two** pools, and the
predator model's own carrying capacity is *derived* from the live herbivore
population, so booking a wolf against the herbivore pool would both
under-count the wolves and quietly shrink what the land is said to support.
The shipped signature therefore takes a third argument,
`is_predator: bool = false`, and the marker passes its species' real predator
status. Pinned by `test_a_predator_death_lowers_the_predator_population`,
`test_a_herbivore_death_leaves_the_predator_population_alone` and its mirror.

One consequence worth stating plainly, because it is a genuinely new drain the
aggregate never had: predation runs through `_die()` too (a predator's kill
resolves through `take_damage`), so wolves hunting near the player now draw
the herbivore aggregate down where before nothing did. That is consistent —
the deer really died — and there is no double-count, because the aggregate
model has no predation consumption term of its own. But it does mean the
region behaves differently while the player is watching it than while they are
not, which is the same two-fidelity asymmetry `record_birth` already has.

The rest of this section describes what was built, and remains accurate.

---

**`record_death` did not exist.** `EcosystemSimulation` has `record_catch`,
`record_vegetation_harvest` and `record_birth`, and nothing for land mortality
— verified by grep across the repo. Add it as `record_birth`'s exact mirror,
with `record_catch`'s flooring:

```gdscript
func record_death(chunk_coord: Vector2i, count: float) -> void
```

Floored at 0.0, a silent no-op for an unknown region. Note the deliberate
asymmetry with `record_birth`, which is *capped at carrying capacity* because
the land decides the ceiling: deaths need no such cap, because nothing stops a
region being emptied. Driven by `test_a_death_lowers_the_regions_population`,
`test_a_population_never_goes_negative`, and
`test_a_death_in_an_unknown_region_is_a_no_op`.

Wiring point: `CreatureMarker._die()` → an
`EarthChunkManager.record_death_at(position)` mirroring the existing
`record_birth_at`. `_die()` is already the single choke point every death goes
through — combat, disease and (per section 4) starvation alike, which its own
doc comment insists on — so there is exactly one place to wire. The payoff is
immediate and visible: today `_reconcile_chunk_creatures` sizes the markers in
a chunk to an aggregate that never heard about the animal you killed, so
hunting a valley bare restocks it. With this, the valley thins and stays thin
until the logistic term grows it back — which is the first moment "farm your
own instead" becomes a real choice rather than a flavour preference.

**Kept animals stay off the wild books.** `KeptAnimals`' own doc comment is
explicit that carrying capacity governs wild animals and kept ones are extra,
and `_thin_creatures` already refuses to cull anything the player has a stake
in. So a pen birth must **not** call `record_birth` — a barn full of sheep is
not a wild herd the land has to support. Driven by
`test_a_pen_birth_does_not_inflate_the_wild_population`. This exclusion is also
exactly why crowding needed its own disease term (section 4) and why the pen
needs a reserved marker budget (section 3): three consequences of one decision,
which is worth stating once rather than rediscovering three times.

**But grazing is on the books, and that is the feedback loop.** Kept animals
are appended to `_loaded_creatures` by `_restore_kept_animals`, and
`_graze_by_herbivores` already walks that same list and already feeds every
real bite into `record_vegetation_harvest` — with no tamed-animal exemption
anywhere in that path — which already depletes land health, which already
lowers herbivore carrying capacity. So an overstocked pasture already starves
the wild deer around it: the mechanism is live and merely has no livestock
standing on it yet. Driven by
`test_an_overstocked_pasture_lowers_the_regions_herbivore_capacity`. This is
the doc's strongest claim to "mature": the player's husbandry decision has an
ecological consequence out of code that already runs, not out of a rule written
to punish them.

**Domestication pressure** — that taking the best individuals out of the wild
changes what breeds there — is [evolution.md](evolution.md)'s pillar and
[animal_genetics.md](animal_genetics.md)'s mechanism. This doc supplies the
hook (the player choosing *which* animal to remove, via section 2's selection)
and nothing else.

## What the player can see

- A **selection ring** on the chosen animal, and its verbs in the hover tooltip
  with live keybinding glyphs (`World._update_hover_tooltip`) — animals are the
  only *tameable* entity in the game with no `get_hover_actions()`.
- The **flight zone** as a ring while crouched or holding the lasso. This is
  the single most important new readout in the doc: it is simultaneously the
  stalking UI and the herding UI, and without it both mechanics are guesswork.
- **"You are slower than that animal."** The HUD already prints `Speed: %d%%`
  and that percentage is, on a rainy afternoon, the difference between a
  workable approach and an impossible one (pillar 1). The player needs to be
  told what it means at the moment it matters — the flight ring turning a
  warning colour while `BASE_SPEED × current_speed_multiplier < FLEE_SPEED` is
  the cheapest honest answer, and it costs no new state. Pinned by the same
  relationship test as pillar 1, so the readout and the mechanic cannot drift
  apart.
- **Wariness** on the animal itself, beside the existing trust bar, hunger pip
  and sick pip (`CreatureMarker._update_taming_readouts`) — with the same "only
  once it is in the loop with the player" gating, so the world does not fill
  with meters.
- **Pen state** on the gate: stock vs capacity, trough level, water, shelter.
- A **roster window** listing what the player owns, because `CreaturePanel`
  cards are proximity-driven and vanish when you walk away — there is currently
  no list of your animals anywhere in the game.
- A **lineage line** in the pen panel: this animal's parents, and what a
  proposed pairing would produce (Master tier).

New windows pay the existing plumbing tax: registration in
`World._any_gameplay_window_open`, `World._close_gameplay_windows` and
`World._unhandled_input`. `scenes/world.gd` is already 4,345 lines, which is an
argument for the pen panel being its own scene script.

## Iterating on this at all

None of the above is testable by hand at a sane speed: the only route to a
tamed animal today is a real 72px throw at roughly one-in-three odds followed
by five hunger-gated feeds — and, per pillar 1, on the wrong afternoon there is
no route at all. Before implementing any mechanism here, add the dev-console
commands — `/tame <trust>`, `/kept`, `/pen`, `/breed` — to the dispatch in
`World._on_console_command` (cited by function name, not line: the `match` sits
a few lines into it and both have moved before). Note that
`ConsoleCommandParser.parse` splits on whitespace with no quoting, so no
argument may contain a space. The dispatch currently has no test of its own;
give the new commands one.

## Test coverage caveat

**No test named in this document has been executed.** Godot is not on `PATH` in
the environment these docs were written in, so every test name here is a
specification of what must be written, not a report of what passes.

Worse, `tests/` contains only `unit/`. Several headline mechanisms in this doc
are inherently cross-node — crouch → flight radius → lasso → measured catch
rate; pen → grazing → land health → wild carrying capacity; `_die()` →
`record_death` → `_reconcile_chunk_creatures` — and the existing precedent for
testing that shape is a marker-level test driving `_process` in a loop
(`test_the_measured_catch_rate_matches_the_model` is the model to copy). An
implementer should expect the composition tests, not the pure-function ones, to
be where the real work is.

## Status

**Section 1, "The approach", is now built** (2026-09-02). The rest of this doc
— pens, keeping, breeding, production, work, mastery, consequence — is still
unbuilt. The ✅ entries in the second list are foundations already in the tree
that this design *reuses*; they belong to other docs and are listed only so an
implementer knows what not to rewrite.

**This doc's mechanisms**

- ✅ `FlightDistance.radius(species, wariness, trust, crouched)` — one composed
  function replacing the single flat `CreatureMarker.SENSE_RADIUS` for the
  PLAYER half of the threat scan (creature-vs-creature sensing is deliberately
  untouched: a wolf does not care whether the deer trusts anyone). The species
  term is read from `AnimalAnatomy.profile_for(species)["world_scale"]` — the
  same number that decides how big the animal is *drawn* — rather than from a
  second hand-authored size table that could drift away from the art, which is
  what makes `test_a_larger_prey_animal_flees_earlier_than_a_smaller_one`
  (mouse < sheep < goat < deer < horse) true by construction rather than by
  tuning. `test_a_graded_flight_radius_never_dithers` is the sole owner of the
  `FLEE_RELEASE_RADIUS` invariant and sweeps every legal combination of the
  four inputs across the whole roster.
  - **Calibration, recorded so it is not mistaken for coincidence:**
    `SCALE_SATURATION` is set so a HORSE lands just *above* the flat 80 px it
    replaces (`test_a_horse_is_no_warier_than_the_flat_radius_it_replaces`).
    The big animals keep behaving as they always did; what the player feels is
    small animals letting them much closer
    (`test_a_mouse_lets_the_player_much_closer_than_the_flat_radius_did`).
    The change opens play up rather than taking it away.
  - **Known limit:** `CAUTION_RADIUS` (160 px, the "should I even consider
    wandering toward them" band) is deliberately left flat and is NOT shrunk by
    a crouch. So a crouched player is still edged away from at wander pace —
    the stalk shortens the *break*, not the unease. That is a real difference
    the player can feel and work with (they close faster than the animal
    drifts), but it is a divergence from a naive reading of this section and is
    recorded rather than hidden.
- ✅ Wariness (`Wariness`, `CreatureMarker.wariness`,
  `CreatureMarker._step_wariness`): a per-individual 0..1 ramp raised on the
  LEADING EDGE of a flee episode (one flushing costs one spook, however long
  the run lasts), raised more slowly while the player's scent is on the animal,
  and decaying by absence with a half-life of exactly one grazing bout
  (`GrazerForaging.GRAZE_SECONDS + REGRAZE_SECONDS`) — so the recovery time is
  a ratio against the grazing cycle rather than an eyeballed number of seconds,
  and stays correct if grazing is retuned.
- ✅ Crouch/stalk (`Player.is_crouching`, `Keybindings` `crouch` on Ctrl,
  `FlightDistance.CROUCH_MULTIPLIER` / `CROUCH_SPEED_MULTIPLIER`) with a real
  speed cost, and `FlightDistance.SHY_SPEED` pinned by ordering against
  `Player.BASE_SPEED` and `Taming.MOUNTED_SPEED` rather than as a number
  (`test_a_crouched_approach_is_never_a_rush`,
  `test_a_mounted_approach_is_always_a_rush`). The HUD mode line reads
  `crouching`, with swimming/drowning outranking it
  (`Player.movement_mode_for`).
  - **Divergence from this section as written:** it named `KEY_X`/`KEY_Z` as
    free. Both have since been taken (`secondary_action`, `cast`), so crouch is
    on `KEY_CTRL` — where a player's hand already goes for it, and the only
    unclaimed modifier left in the registry.
- ✅ Bait, all four verified gaps closed:
  `Olfaction.bait_mixture` gives each food its own mixture (and adds an `OIL`
  molecule so a nut is not a fruit); `Olfaction.receptors_for` gives every
  species in `AnimalAnatomy.SPECIES` a nose by inheriting its diet's receptors;
  `CreatureMarker._seek_by_smell` no longer requires a fruit diet and tags a
  non-fruit-eater's find as the new `GrazerForaging.FOOD_BAIT`; and
  `EarthChunkManager.take_bait_at` removes any ground item of kind `food`, so
  an animal that walked to a carrot can actually eat it instead of standing
  over it. Pinned by
  `test_a_baited_grazer_walks_to_a_carrot_it_would_never_forage_for` and
  `test_bait_beyond_smelling_range_draws_nothing`.
  - **A fruit-eater still takes fruit AS fruit**
    (`test_a_fruit_eater_still_takes_fruit_as_fruit`), so the seed inside a
    windfall still travels the way endozoochory expects rather than being
    swallowed by the generic bait path.
  - **A fifth gap, found in play rather than by reading: bait had no gesture.**
    `inventory_window.gd`'s own header claims an item can be dropped "onto the
    world to throw it away"; it cannot — verified twice in a live session with
    a slow drag whose payload was visibly attached to the cursor, and the
    window's on-screen label says only "drag to move". A player therefore had
    no way to put food on the ground at all, which would have left this whole
    layer unreachable. Closed by giving the **stash key a second, contextual
    meaning**, exactly the way `E` already has one (see
    [stone.md](stone.md)'s held-item concept): with something in hand it still
    stashes, and with an EMPTY hand it puts one bait down at the player's feet.
    `Player.bait_item_id_from` decides which food — the taming treat if carried,
    otherwise the first food — pure, static and tested.
    - **Known limit, and why it is a rule rather than a choice:** there is no
      selected-item concept yet (§2 of this doc specs the click-latched
      selection it should read once it exists), so a player carrying carrots
      and apples cannot yet choose to bait with the apples.
    - One unit per press, not the stack: a bait is a considered act, and one
      carrot is exactly what the hand-fed `feed_treat` costs too.
- ✅ **The wind** — not specified in this doc when it was written, and the
  piece that makes the stalk a decision rather than a stat. Owned by
  [olfaction.md](olfaction.md)'s "The wind carries it": the player emits musk,
  `WindScent` stretches its reach downwind and compresses it upwind, and what
  the animal does about it is `Wariness.after_scent` — so approaching from
  upwind costs you the animal's patience before you are anywhere near its
  flight radius. `World.status_line_wind` puts the wind's name in the HUD,
  because a mechanic the player cannot read is one they cannot play around.
- 🚧 The speed-truth pin. The relationship test
  (`test_a_player_slowed_by_weather_and_terrain_cannot_outpace_a_fleeing_animal`)
  is still unwritten, and the HUD still shows a bare `Speed: %d%%` that never
  says *you are now slower than a sheep*. The 2026-09-02 session re-measured
  the problem in play (36% in a spring storm, 56% in forest, 23-24% swimming,
  75% at noon in the clear — against a fleeing animal's effective 50%) and
  could not close on a sheep in a long deliberate session. **Downgraded from
  "highest-value item" to 🚧 rather than closed**: bait and the stalk now make
  the loop playable *without* winning the foot race, which was the real fix, but
  the HUD still does not tell the player why chasing fails.
- ⬜ Click-latched `Player.selected_animal` + selection ring;
  `CreatureMarker.get_hover_actions()`.
- ⬜ `wood_fence` / `wood_gate` building pieces; the gate as an openable.
- ⬜ `RoomDetector.enclosures()` extracted from `find_rooms`.
- ⬜ `PenCapacity.max_stock`, derived from the vegetation model.
- ⬜ Reserved marker budget so a pen does not suppress wild spawning in its
  chunk (verified today: it does, via `_reconcile_chunk_creatures` +
  `_thin_creatures`).
- ⬜ Trough (`StructureStock`), water trough, shelter via `is_indoors` (which
  would be its **first production caller**).
- ⬜ `Husbandry.pen_crowding` + `DiseaseModel.pen_transmission_chance` — **new
  code**, because `herd_transmission_chance` is regional density and kept
  animals are deliberately absent from the regional aggregates.
- ⬜ Neglect wired: `Taming.trust_after_neglect` has **zero production
  callers** today. [taming.md](taming.md)'s Status list marks the trust model
  ✅ including "decays on neglect"; that entry is overstated and should be
  corrected to 🚧 when this lands.
- ⬜ Starvation death **for penned animals only**, through the existing
  `_die()` path — with `LootTable` rows for the keepable roster, without which
  a dead sheep leaves no carcass at all (verified: `_DROPS` covers only
  `herbivore`/`boar`/`predator`/`lynx`).
- ⬜ `KeptAnimals` FORMAT_VERSION 2 — record owned by
  [animal_genetics.md](animal_genetics.md); this doc requires pen id, name,
  discovered preferences, kept-since, escape memory, needs, disease, seed and
  parents. Fixes the verified `randi()` re-roll by routing
  `_restore_kept_animals` through the seed-carrying spawn sibling;
  `spawn_single` itself is **unchanged**.
- ⬜ `KEPT_ANIMALS_DIR`/`ECOLOGY_DIR` added to **both**
  `World.backed_up_directories()` **and** `_wipe_persisted_world`, driven by a
  **new** test — the existing `test_world_backup_paths.gd` drift pin is correct
  today and must stay green.
- ⬜ `Husbandry.can_pair`, the pen pairing panel, `GESTATION_SECONDS`
  (persisted), the pedigree record.
- ⬜ Products: `milk` and `wool` items, `Husbandry.yield_fraction` **including
  its heritable term**, the hold-to-milk/shear act, fleece regrowth, the season
  gate.
- ⬜ `dog` species entry; `ORDER_GUARD` as a third order. (Tiered trust gates
  and retiring `pet_loyalty.gd` are [taming.md](taming.md)'s.)
- ⬜ Draught hitching to `FelledTree`; pack `Inventory`; the call/whistle
  action.
- ⬜ Animal Handling tiers as an information ladder, with Expert reading
  `AnimalGenome` rather than `AnimalFitness.phenotype_for`.
- ✅ `EcosystemSimulation.record_death` + `EarthChunkManager.record_death_at`,
  wired at `CreatureMarker._die()` — the one place every death goes through.
  Takes `is_predator` so the two aggregate pools stay separate (see
  "Consequence" above for that divergence). Kept animals are exempt via the new
  `CreatureMarker.is_player_invested()`, which `_thin_creatures` now shares so
  the two cannot drift. 16 tests across the pure model, the middle layer and
  the marker, plus `test_a_hunted_out_region_stops_showing_creature_markers` for
  the composition that is the point of the whole thing: a valley hunted bare
  now stays bare instead of restocking on the next refresh.
- ⬜ Penned grazing counted against the pasture (the sim side already works;
  nothing is standing on it).
- ⬜ Dev-console `/tame`, `/kept`, `/pen`, `/breed`, and a test for
  `World._on_console_command`.

**Foundations reused (owned elsewhere)**

- ✅ The catch-and-trust loop — [taming.md](taming.md): lasso, struggle, trust,
  orders, mounting, per-chunk persistence.
- ✅ The four-term movement multiplier — [survival.md](survival.md),
  [weather.md](weather.md), [terrain_relief.md](terrain_relief.md):
  `ConditionPenalty`, `WeatherModel.movement_speed_modifier`,
  `TerrainPassability.speed_multiplier`. This doc changes none of them; it only
  pins their *product* against `FLEE_SPEED`.
- ✅ Smell as molecules and receptors — [olfaction.md](olfaction.md):
  `Olfaction`, `ScentForaging`, `EarthChunkManager.smells_near`.
- ✅ Grazing as a real act that removes real tufts and books the harvest —
  [ecosystem_dynamics.md](ecosystem_dynamics.md): `GrazerForaging`,
  `graze_grass_at`, `record_vegetation_harvest`, land health.
- ✅ Enclosure detection and piece collision — [building.md](building.md),
  [timber_construction.md](timber_construction.md): `RoomDetector`,
  `BuildingPiece`, `build_at_global`/`_sync_piece_collision`.
- ✅ Needs, bioenergetics and disease — `CreatureNeeds`, `AnimalReproduction`
  (a stateless static namespace; the per-animal `energy` lives on
  `CreatureMarker`), `DiseaseModel` ([disease.md](disease.md)).
- ✅ Hover targeting infrastructure — `HoverTargetFinder`, the shared
  `"hoverable"` group, `World._update_hover_tooltip`.
- 🚧 `LifeCycle` — real and tested, and genuinely called by
  `AmbientFlyerMarker` (`can_court_at`, `size_scale_at`, `MATURE_SECONDS`).
  Only `stage_at` is uncalled, and `CreatureMarker` calls none of it, so the
  mammal age gate is a new seam.
- ⬜ The genome itself — [animal_genetics.md](animal_genetics.md).
  `DnaCrossover` and `AnimalFitness` are complete and unit-tested with **zero
  production callers**; offspring inherit nothing today.
- ⬜ The `Skill` resource Animal Handling is an entry in —
  [labor_skills.md](labor_skills.md), all ⬜.

## Open questions

- **Where does the first breeding pair come from?** Catching two adults of the
  same species and getting both to full trust is a long chain. A village stock
  market ([economy.md](economy.md)'s `Market`) selling a bred animal would
  shortcut it — at the cost of making the wild catch optional. Worth deciding
  before the pen ships, not after.
- **Cow and chicken, or not?** Adding them is a known path but a real one (five
  stat tables, a shape family, an anatomy profile, biome pools, art). Shipping
  production against sheep/goat/horse/reindeer first is cheaper and proves the
  loop; the risk is that "no cow" reads as an omission rather than a choice.
- **How visible should the flight zone be by default?** Always-on rings over
  every animal would clutter the world the way the old dropped-item name labels
  did (`dropped_item.gd`'s own comment records why those were removed).
  Crouch-and-lasso-only is the conservative default; herding may need it more
  often than that, which is why it is a Journeyman unlock above rather than a
  setting.
- **Does wariness persist across a chunk reload?** The V2 record could carry it
  for kept animals, but wild ones have nowhere to put it, so a spooked wild
  herd forgets the moment the player walks away. Re-deriving it fresh matches
  this project's existing precedent for ephemeral per-chunk sim state;
  remembering it would make a hunted valley feel genuinely hunted. The same
  question [evolution.md](evolution.md) leaves open for dominance rank.
- **Is hunting a system?** `record_death` makes killing an animal
  *consequential* for the first time, which raises the obvious next question —
  tracking, traps, blinds — and this doc answers none of it. Hunting is
  explicitly deferred, not forgotten; naming it here is better than letting
  `record_death` imply a spec that does not exist.

## Editor's note

Corrections made against the code, beyond the arbitrated items:

1. **`LootTable` has no row for any keepable species.** `_DROPS` covers only
   `herbivore`, `boar`, `predator` and `lynx`, and `_spawn_carcass_if_eligible`
   returns early when `drops_for` is empty — so a dead sheep, goat, horse,
   deer, camel or reindeer leaves **no carcass**, despite all of them being
   real spawnable species (`CreatureRenderer`'s biome pools list sheep and goat
   directly). No draft and no audit finding caught this. It is now a named
   prerequisite of the penned-starvation mechanic, with
   `test_every_keepable_species_leaves_a_carcass`, because "leaves a real
   carcass and joins carrion.md's loop" was otherwise false as written.

2. **The audit is slightly wrong about
   `test_the_measured_catch_rate_matches_the_model`.** It says the test
   "measures 60 real captures". It does not measure the *approach* at all — it
   calls `restrain_to()` directly and measures how often a healthy horse is
   still held after the struggle resolves (`assert_between(rate, 0.2, 0.55)`).
   The conclusion the arbitration draws from it is nonetheless correct and
   stronger than stated: the test proves the *catch* resolves in the player's
   favour a real fraction of the time, so the loop's failure is entirely
   upstream, in getting within 72px. This doc describes it accordingly.

3. **`RoomDetector.is_indoors` has zero production callers**, not merely a
   misleading name. `EarthChunkManager` deliberately avoids it (its own comment
   explains the per-piece cost), and every other reference in `src/` is a
   comment. Shelter would be its first real consumer, which makes the
   floored/floorless collision the audit flagged a live design decision rather
   than a documentation nit.

4. **The audit's P1.3 count is right but for a different reason than stated.**
   `find_rooms` has two callers — `room_containing` in-file and
   `EarthChunkManager`'s roofed-piece pass — and `is_indoors` reaches it only
   through `room_containing`. The doc now says which two.

5. **The live session's "over vegetated ground" is not what the terrain term
   models.** `Player._terrain_speed_multiplier` reads
   `TerrainPassability.speed_multiplier(slope_at_global(...))` — real slope, not
   vegetation. The 47% reading is fully accounted for by weather × freezing ×
   slope × condition without any vegetation term, and the arithmetic is stated
   here in those terms. The finding itself stands unchanged.
