# Leaf Litter: Fallen Leaves as Ground Forage

Reported: "ants should eat fallen fruits leaves and other stuff like
seeds... they should be a real gear in the ecosystem", followed later, once
fallen-fruit foraging alone had shipped, by "it seems that falling leaves
are still not implemented". Leaves were the one named food source that
genuinely didn't exist as a real ground object anywhere in this codebase --
only as art baked into the canopy sprite itself (the autumn canopy draws
leaves falling away beneath it, which `CompositeSheetSlicer` treats as
background debris to be excluded from a real drawing, never a separate game
object -- see its own doc comment). [soil_fauna.md](soil_fauna.md) names
the fuller version of this gap in its own scope choices: *"a real
detritivore population model (litter input -> worm biomass -> bird carrying
capacity) is the natural follow-up and is deferred."* This doc does not
build that model. It closes the narrower, concretely-requested gap: leaves
fall, they are real objects on the ground, and the ants/bugs that already
forage fallen fruit can find and eat them too.

## Design pillars

1. **A real event on the real clock, not a spawned decoration.** A leaf
   falls because a tree's canopy is actually turning autumn colour, read
   from the same `TreePhenology` clock every other seasonal quantity
   (canopy art, fruiting, snowfall) already reads -- not a second schedule
   computing its own answer (see [seasons.md](seasons.md)'s own warning
   about exactly that mistake).
2. **Reuse before invention.** This project already has a complete,
   production-proven pipeline for "a tree sheds something, it lands as a
   real ground item, foragers find and eat it": windfall fruit
   (`EarthChunkManager.step_fruiting`, `WorldItemBus`, `DroppedItem`,
   `DecomposerMarker`). A leaf is shed material falling from a tree exactly
   like a fruit is; it reuses that whole pipeline rather than growing a
   second one beside it. The art is reused too: every composite tree sheet
   already draws a small single-leaf closeup as part of a row
   `IllustratedTree` deliberately skips past when picking real on-tree
   fruit (see its own row-detection doc comments) -- sitting there, already
   authored, at zero extra asset cost.
3. **Bounded by construction, not by discipline.** This codebase has hit
   real, measured performance collapses from an "obvious" per-object
   approach twice before -- character compositing at 160ms/tree, and the
   original tile-painted `SnowLayer` at 40-50ms/sweep, both later replaced
   by shader/hash-driven approaches instead. Leaf litter avoids repeating
   that mistake not by adding new discipline on top of a risky shape, but
   by reusing a shape that was never risky in the first place: windfall
   fruit already spawns individually-simulated ground items, distance-gated
   to `FRUITING_DETAIL_RADIUS`, capped per step at `MAX_SEPARATE_WINDFALLS`,
   and self-despawning on a flat lifetime -- and it already runs at
   production scale, in forests, without being the thing that caused either
   of those two historical collapses. A leaf drops through the identical
   gate and cap, at a lower rate than fruit, so it inherits that same
   already-proven ceiling rather than needing a new one designed from
   scratch.
4. **A forage target, not a nutrient simulation.** The ask was "ants should
   eat fallen leaves... a real gear in the ecosystem" -- a decomposer that
   can find and eat a real object. It was not a request for leaf litter to
   feed back into soil fertility, worm population, or grass growth, and
   this pass does not build that feedback (see "Deliberately not modeled"
   below and soil_fauna.md's own deferred note, which this leaves exactly
   as deferred as it already was).

## Real-world grounding

- **Leaf fall (abscission) is seasonal and cued by day length and
  temperature, not a single event.** A few leaves come down from wind or
  petal-drop through spring and summer; the bulk falls in autumn as
  deciduous trees shut down chlorophyll production and cut their leaves
  loose before winter. Conifers are the exception that proves the rule:
  pine sheds needles year-round rather than in one autumn drop, which is
  why pine's own fallen litter item is needles, not a broadleaf, even
  though it fills the same forage role here.
- **Fallen leaves are real, findable food for ground-foraging
  invertebrates.** Ants and litter/carrion beetles -- the same two animals
  `DecomposerMarker` already models (see [carrion.md](carrion.md)) -- feed
  on leaf litter in addition to carrion and fallen fruit in real
  ecosystems; this is a third, distinct forage source for consumers this
  game already has, not a new animal.

## Mechanism spec

### When leaves fall

The real, main fall is gated on the exact clock the canopy's own autumn
colour already turns on: `TreePhenology`'s TURNING season, specifically
while it is turning INTO winter and has made some real progress
(`canopy_season == "autumn"`, `canopy_turning_into == "winter"`,
`canopy_turn_progress > 0.0`), read once per fruiting step from
`_tree_renderer.canopy_state()` -- the same values
`EarthChunkManager.step_fruiting` already reads once per step (not per
tree, see that function's own doc comment on why) for the windfall block
right beside this one. Chance rises with how far into its own turn the
canopy is: a tree just beginning to turn sheds rarely, one nearly bare
sheds almost every step.

A settled SUMMER tree also sheds an occasional leaf -- real wind and
petal damage, not the main fall (`LEAF_SUMMER_TRICKLE_CHANCE`, a flat 3%
per step, named rather than derived, the same "one real table beats an
invented formula" idiom `FruitingModel.RIPENING_BY_SPECIES` already
sets). Reported directly: "when they fall in summer they should be
green" -- which only means anything if a summer fall is real, not merely
implied by an autumn-only trigger.

Spring and winter drop nothing: a tree that has not started turning yet,
or has cycled back to bare, is not shedding. Pine, which never really
goes bare, is judged the same way as every other species by the same
canopy clock -- if a future pass gives conifers their own non-deciduous
phenology, this mechanic follows without changes, since it never
hard-codes a species list here.

### What falls: the item, and its real colour

One new item per `TreeSpecies` id, alongside its existing fruit/nut item:
`"<species>_leaf"` uniformly (`cherry_leaf`, `apple_leaf`, `walnut_leaf`,
`acorn_leaf`, `hazelnut_leaf`, `pine_leaf`), kind `"material"` (it is not
food and never spoils -- see "Lifecycle" below). Display names read
naturally rather than mechanically: "Cherry Leaf", "Apple Leaf", "Walnut
Leaf", "Hazelnut Leaf", "Oak Leaf" (acorns come from oaks; "Acorn Leaf"
reads wrong), and "Pine Needles" (the real word for what a pine actually
sheds). The id stays uniform even where the name doesn't, so recognising
"is this a leaf item" stays a single suffix check rather than a
species-by-species list.

**The colour actually matters and is read from the real art, not
guessed.** Reported directly: "they don't have the correct color... when
they fall in summer they should be green, but when they fall in autumn
they should be orange". Every composite sheet draws a real single-leaf
(or, for walnut, compound-leaflet; for pine, needle-sprig) closeup in
EACH canopy column, coloured to that column's own season --
`IllustratedTree.foliage_leaf_for(species, season)` finds the right one
by canopy column and real measured hue, ruling out the bigger same-hued
leaf+fruit cluster sharing that column, the real on-tree fruit itself
when it is smaller than the closeup instead of bigger, and a solid round
nut/kernel/cone (see that function's own doc comment for the three
measured signals combined to do it). Which season's art a specific fallen
leaf uses is decided at the moment it falls and carried on the item's own
`sprite_id` (`"cherry_leaf_autumn"`), not re-derived later from whatever
the current season happens to be by the time a player looks at it. Only
summer and autumn are resolved -- the only two seasons a leaf falls in at
all -- so there is no guessing at art for a season nothing ever asks for.
A species/season pair whose sheet has no matching closeup falls back to
the ordinary generic procedural item sprite -- exactly the existing
`DroppedItem` fallback pattern already used for any item without
dedicated illustrated art. One real, named gap: pine's own autumn column
currently shows a winged seed-pair rather than a needle sprig (see
`foliage_leaf_for`'s own doc comment for why that one case cannot be told
apart by the signals this uses).

### Where it lands, and how it gets there

Scattered within the canopy's own rough radius around the trunk, using a
real random angle and distance rather than a fruit's "lands under exactly
where it hung" precision (`ProceduralTreeSprite.fruit_ground_offset`): a
leaf's position in the drawn canopy carries none of a fruit's per-index
hanging position to reuse, and a real falling leaf drifts on the wind
rather than dropping straight down from one fixed point anyway.

It does not simply appear there. Reported directly: "make them actually
fall down and sway in the wind". `DroppedItem` starts a leaf
`FALL_HEIGHT` world pixels above its own landing spot and animates it
down over `FALL_DURATION`, eased in and out, with a horizontal flutter
(`FALL_SWAY_WORLD`, `FALL_SWAY_CYCLES`) that tapers to zero exactly as it
lands -- however it wanders on the way down, it always settles at the
position `step_fruiting` actually chose. Once landed it keeps a small
ongoing rock (`GROUND_SWAY_RADIANS`/`GROUND_SWAY_PERIOD`, phase-offset
per instance so several landed leaves do not rock in unison) -- real
wind, not a one-shot animation that plays once and stops.

### Rate and cap

At most one leaf item per shedding tree per fruiting step, at the chance
"When leaves fall" above sets for whichever of the two triggers applies
(autumn's own progress-scaled chance, or summer's flat 3% trickle) --
gated behind the same `FRUITING_DETAIL_RADIUS` distance filter every
fruiting tree already pays for, so a stand of shedding trees at the edge
of view cannot spam the ground any more than a stand of fruiting trees
already could not. See "Bounded by construction" above for why this
specific shape -- discrete, capped, self-despawning items, not a
persisted density field or a per-frame spawn -- is the one already proven
safe at this scale.

**An aggregate, shader-bombed density field (the same GPU technique
`SnowBombShader` uses for snow) was tried and deliberately reverted
during this same pass.** It would have solved the performance question
by construction, the same way it does for snow -- but it also removes
the one thing a discrete `DroppedItem` gives for free: a real position a
decomposer can walk to and eat from (see "Consumption" below, and
"Bounded by construction" above for why the ORIGINAL aggregate-scalar
attempt at this feature never finished that same problem either). Given
the choice between the two, discrete items -- already proven safe at
this scale by windfall fruit -- won on that basis, not on a performance
concern this pass ever actually measured.

### Consumption

A fallen leaf joins `DroppedItem.FORAGEABLE_GROUP_NAME` exactly like a
fallen fruit does. `DecomposerMarker`'s existing forage-and-eat behaviour
needs no changes at all to pick it up: its feeding step already frees any
non-`Carcass`/`CarcassGuts` forage target unconditionally on contact,
regardless of item kind or id, so a decomposer that finds a leaf just eats
the whole thing in one visit, the same as a dropped cherry -- closing the
"real gear in the ecosystem" loop the original report asked for.

**Scoped to the visible decomposer path only, this pass.** The invisible
`AntColony` simulation's own windfall foraging (`_forage_windfall_near_mound`)
queries the fruiting model's abstract per-tree fruit stock directly
(`fruit_near`/`take_fruit_at`), not `DroppedItem` nodes in the scene tree --
a structurally different integration than the group-scan
`DecomposerMarker` uses, and there is no equivalent abstract per-tree leaf
stock to query it against without building the kind of persisted
aggregate this doc's "Bounded by construction" pillar deliberately avoids.
Extending the invisible colony simulation to forage leaves too is a
reasonable, separable follow-up, not required here: this codebase already
has precedent for splitting "the visible ants" and "the invisible colony
simulation" across passes for this exact feature area (the original
fallen-fruit work named ground-seed foraging by visible ants as
deliberately deferred for the identical reason -- the invisible colony
already had its own way of doing it). The report's complaint -- "it seems
that falling leaves are still not implemented" -- is about the mechanic
existing and being visible at all, which the `DecomposerMarker` path
delivers in full.

### Lifecycle

Ordinary flat `DroppedItem.LIFETIME` despawn, not food-spoilage-timed (a
leaf is not `item.kind == "food"`) -- ground litter that lingers a while
and then tidies itself away, the same tidiness rule every other non-food
dropped item already follows. No new persistence: exactly like windfall
fruit today, a fallen leaf that nobody ate or that a chunk unload swept
away is not remembered as a specific missing instance -- the next fruiting
step simply evaluates the current canopy state fresh, the same "catch-up
from a pure function of elapsed time, not a re-simulated history" property
`FruitingModel` already has.

### Deliberately not modeled

Any feedback from leaf litter onto soil fertility, worm population, or
grass growth, and any persisted per-chunk litter density. `soil_fauna.md`
already names the real version of this ("a real detritivore population
model: litter input -> worm biomass -> bird carrying capacity") as an
explicit, deferred follow-up -- this pass gives ants and bugs something
real to forage, and leaves it exactly as deferred as it already was rather
than half-building it. A visible, ground-covering litter-density effect (the
forest floor actually looking blanketed in autumn) is also out of scope --
a genuinely different, larger-N rendering problem than a handful of
individually-forageable leaves near the player, and one this codebase
should design deliberately rather than back into as a side effect of a
forage mechanic.

**No third, "rotten/black" colour stage for a leaf still on the ground
once winter arrives**, despite being asked for directly alongside the
green/orange request. `DroppedItem.LIFETIME` (90 seconds) despawns an
ordinary leaf long before any real season boundary could pass under it
in normal play -- the one time it would ever matter is a deliberately
accelerated clock (`/ecotest`), not the game this mechanic is actually
tuned for. Tracking a specific leaf's own age against the calendar
(rather than the flat wall-clock lifetime every other non-food dropped
item already uses) to serve a state that ordinary play can never reach
is real, avoidable complexity for a case this pass does not build --
named here rather than silently dropped, in case a future pass changes
how long litter is meant to persist.

## Status

✅ A real leaf falls (autumn's main fall and a light summer trickle),
lands as a real `DroppedItem`, visibly drops and settles with an ongoing
sway, reads the correct season's colour
(`IllustratedTree.foliage_leaf_for`), and is real forage a decomposer
finds and eats with no changes needed to `DecomposerMarker` at all.

⬜ Invisible `AntColony` windfall foraging extended to leaves (see
"Consumption" above).

⬜ Any litter-density/soil-fertility feedback, any ground-covering
litter visual effect, and a third rotten/black colour stage for litter
that outlives `DroppedItem.LIFETIME` (see "Deliberately not modeled"
above and soil_fauna.md's own deferred detritivore-population note).
