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
fall, they are real, individually-addressable data on the ground, and the
ants/bugs that already forage fallen fruit can find and eat them too.

**This is the second implementation of this feature.** The first shipped
leaf litter as one real `DroppedItem` node (`Sprite2D` + `Area2D` +
`CollisionShape2D`, ticking `_process()` every frame) per fallen leaf --
reusing the existing windfall-fruit pipeline exactly, per this doc's own
original "reuse before invention" pillar. That was the right call for
getting a real, visible mechanic shipped fast, and it worked: leaves fell,
coloured correctly, and decomposers ate them, with zero changes needed to
`DecomposerMarker`. It was reported too heavy on CPU/GPU once a forest
actually shed, and — the request that drove this rewrite — leaves were
asked to visibly scatter under wind, the player, and animals, which a
one-shot fall-and-settle animation has no mechanism for at all. This
revision replaces the per-node pipeline with cheap per-chunk plain data
(`LeafLitterField`) rendered by one GPU-instanced draw call per chunk
(`LeafLitterRenderer`, `LeafLitterAtlas`), and adds the three dispersal
triggers. See "History: why not the density-field shortcut" below for why
that specific alternative — tried twice, for two different reasons — was
rejected both times.

## Design pillars

1. **A real event on the real clock, not a spawned decoration.** A leaf
   falls because a tree's canopy is actually turning autumn colour, read
   from the same `TreePhenology` clock every other seasonal quantity
   (canopy art, fruiting, snowfall) already reads -- not a second schedule
   computing its own answer (see [seasons.md](seasons.md)'s own warning
   about exactly that mistake). Unchanged by this rewrite: `EarthChunkManager
   .step_fruiting`'s own leaf-fall block still reads exactly this clock, at
   the same rate, with the same angle/distance placement math -- only WHERE
   the result is written changed (see "What falls" below).
2. **A discrete position survives being fast, not just being cheap.** The
   first pass's whole architecture (real `DroppedItem` nodes) existed
   because it was the readily-available way to get "leaves are real,
   individually-forageable ground objects" at all. This rewrite keeps that
   SAME property -- a decomposer still finds and removes one real leaf at
   one real position -- while moving the data out of the scene tree
   entirely into `LeafLitterField`, and the rendering into a single
   GPU-instanced `LeafLitterRenderer` draw call per chunk. Reuse before
   invention still applies to the pieces that do not need to change: the
   fall-triggering math in `step_fruiting`, the real illustrated art per
   species/season, and `DecomposerMarker`'s own forage-and-eat behaviour
   shape (see "Consumption" below).
3. **Bounded by construction, not by discipline.** This codebase has hit
   real, measured performance collapses from an "obvious" per-object
   approach several times before -- character compositing at 160ms/tree, the
   original tile-painted `SnowLayer` at 40-50ms/sweep, and (see "History"
   below) leaf litter's own first pass, all later replaced by shader/
   hash-driven or GPU-instanced approaches instead. This pass follows that
   same replacement pattern directly: a chunk's litter is cheap plain data
   plus one `MultiMeshInstance2D`, not N nodes each paying their own
   `_process()`/`Area2D` overhead every frame regardless of whether anything
   about them changed.
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
  why pine's own fallen litter uses needles, not a broadleaf, even
  though it fills the same forage role here.
- **Fallen leaves are real, findable food for ground-foraging
  invertebrates.** Ants and litter/carrion beetles -- the same two animals
  `DecomposerMarker` already models (see [carrion.md](carrion.md)) -- feed
  on leaf litter in addition to carrion and fallen fruit in real
  ecosystems; this is a third, distinct forage source for consumers this
  game already has, not a new animal.
- **Real leaf litter is light and mobile.** A dry leaf's large surface-
  area-to-mass ratio is why it visibly tumbles and skitters across open
  ground in an ordinary breeze -- a familiar autumn scene, and the direct
  grounding for this pass's own wind/player/animal dispersal (see
  "Dispersal" below).

## Mechanism spec

### When leaves fall

Unchanged from the first pass. The real, main fall is gated on the exact
clock the canopy's own autumn colour already turns on: `TreePhenology`'s
TURNING season, specifically while it is turning INTO winter and has made
some real progress (`canopy_season == "autumn"`, `canopy_turning_into ==
"winter"`, `canopy_turn_progress > 0.0`), read once per fruiting step from
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

### What falls: a data record, not an item

A fallen leaf is a plain `{position, species, season, spawned_at,
transition_from, transition_start}` record in that chunk's own
`LeafLitterField` (`src/world/leaf_litter_field.gd`) -- NOT an `Item`/
`ItemStack` any more (the first pass's `"<species>_leaf"` item id,
`"material"` kind, and per-species display name table are gone; litter is
never inventoried, hover-named, or picked up by hand, so that data had no
remaining consumer). `species` is the plain `TreeSpecies` id (`"cherry"`,
`"acorn"`, ...); `season` is `"summer"` or `"autumn"`, whichever the leaf
actually fell in -- the only two seasons a leaf ever falls in at all.

`step_fruiting`'s own leaf-fall block is otherwise untouched: the same
per-(tree, step) deterministic `PixelNoise` roll, the same canopy-turn-
scaled chance, the same random angle/distance scatter within the canopy's
own rough radius (`LEAF_SCATTER_RADIUS`) around the trunk. Only the last
step changed -- instead of building an `Item`/`ItemStack` and emitting it
through `WorldItemBus` (which `World` would turn into a real `DroppedItem`
node), it calls `LeafLitterField.add_leaf(position, species, season, now)`
directly on the tree's own chunk's field.

**The colour still matters and is still read from the real art, not
guessed** -- that part of the first pass carries over unchanged in spirit,
just moved from a per-instance runtime lookup into a prebuilt atlas (see
"Rendering" below). `LeafLitterAtlas` (`src/rendering/leaf_litter_atlas.gd`)
packs every species/season pair's own real illustrated closeup
(`IllustratedTree.foliage_leaf_for`) into a fixed-cell-grid runtime atlas at
process start, falling back to the same generic procedural sprite
`DroppedItem` always used for any pair lacking dedicated art. Checked
directly while building this atlas: every one of the 6 species x 2 seasons
this project ships today actually HAS real illustrated art -- the first
pass's own doc comment named pine's autumn column as a gap; that is not
(or is no longer) true. The fallback path still exists, tested against a
synthetic species, for whenever a real gap does show up.

### Rendering: one GPU-instanced draw call per chunk

`LeafLitterRenderer` (`src/rendering/leaf_litter_renderer.gd`) mirrors
`IllustratedGrassPatch`'s own GPU-instanced-cards shape, minus Y-sort
banding (flat ground litter has no vertical extent to misorder -- it is
parented under `_ground_decor_parent`, which never Y-sorts, the same as
every other ground decoration). One `MultiMeshInstance2D` per chunk, filled
from that chunk's `LeafLitterField.leaves()` every `step_leaf_litter` tick
(bounded to chunks actually in decoration range, the same `_decorates`
radius gate every other per-chunk decoration sync already uses) -- cheap,
deliberately, unlike the periodic multi-second `GRASS_REFRESH_INTERVAL`
cadence flowers/grass/worms use: a leaf's whole fall is over in under a
second (`LeafLitterField.TRANSITION_DURATION`), so any real sync lag would
hide the fall animation entirely rather than merely delay it the way a
slow-growing flower can tolerate.

**Falling and swaying are computed continuously in a shared vertex shader**,
ported by hand from the first pass's own already-tested `DroppedItem._step_
fall`/`_step_ground_sway` formulas -- the same "GDScript mirror kept in sync
with the GLSL by hand" convention `SnowBombShader` already established in
this codebase, and for the same reason: a vertex shader cannot be asserted
headless. `LeafLitterRenderer`'s own static functions mirror the shader
line for line (see that file's doc comment); a real-GPU render-smoke test
(`test_leaf_litter_renderer_smoke.gd`, mirroring `test_river_flow_render_
smoke.gd`'s own established pattern) proves the shader actually compiles,
samples real atlas content, and moves a transitioning instance away from its
settled position -- not merely that the GDScript mirror's own math is
internally consistent.

Each `MultiMesh` instance packs 4 float channels of per-instance custom
data (`INSTANCE_CUSTOM`): a fixed-grid atlas cell index (the whole reason
`LeafLitterAtlas` is a fixed grid rather than grass's own irregular-UV-pair
sheet -- addressing a cell this way costs one channel instead of four,
freeing the rest for motion), a packed transition offset (x, y), and a
packed, WRAPPED transition-start time (the same "8-bit custom data cannot
hold a raw growing timer" packing trick `rain_overlay.gd` already uses,
since a channel here is only 8 bits wide). The wrapped clock's one real risk
-- aliasing back to "just starting" once real elapsed time exceeds a full
wrap period -- is closed structurally rather than merely bounded: once a
transition's own duration has elapsed, `LeafLitterField.advance` snaps its
`transition_from` to exactly equal its current position, so the packed
offset reads as a real, CPU-confirmed zero from then on regardless of
anything the wrapped time math computes afterward.

### Dispersal: one mechanism, three triggers

The request this rewrite exists to answer: "leaves should visibly fall from
the canopy and be dispersed by wind, animals, and the player walking over
them". A push that springs back would not disperse anything, so this is a
single **persisted relocation** (`LeafLitterField.relocate_leaf_near`) --
mirroring `PebbleDispersion`'s own shape (a nudge that stays, not a wake
that recovers) -- reusing the EXACT SAME GPU transition machinery the
initial fall needs (packed `transition_from`/`transition_start`): one
transition mechanism, multiple triggers, not a second animation system.
Relocation stays within the leaf's own originating chunk's field -- no
cross-chunk hand-off bookkeeping; a leaf nudged near a chunk edge just
stops a little short of it, not worth the complexity for a cosmetic
scatter.

- **Wind.** `LeafLitterField.advance`'s own throttled cadence
  (`WIND_DISPERSAL_INTERVAL`) gives each SETTLED leaf a small per-check
  chance (`WIND_DISPERSAL_CHANCE`) to be nudged via `WindDispersal.
  landing_offset`, using a new `WindDispersal.WEIGHT_LEAF` class (sitting
  between `WEIGHT_FLOWER_SEED` and `WEIGHT_BERRY_PIP` -- a leaf's flat
  blade is not a real wind-dispersal adaptation like a dandelion's own
  plume, but its surface-area-to-mass ratio still makes it far more
  wind-mobile than a small solid pip). This is the SAME continuous
  per-chunk wind direction/strength already computed every frame for
  flower/seed dispersal (`WeatherModel.wind_direction_for`/
  `dispersal_strength_for`, read the identical way `EarthChunkManager.
  step_flowers` already reads it) -- no new weather state. Dead calm (wind
  strength 0) never rolls at all: litter must not spontaneously scatter
  with nothing to blame it on.
- **Player.** `World._step_leaf_litter_dispersion`, the same host-gated
  call site as `_step_pebble_dispersion` (inside
  `_owns_ecosystem_simulation()`), delegating to `EarthChunkManager.
  disperse_leaf_litter_near` -> `LeafLitterField.try_disperse_near`. Same
  mass/contact-probability-roll SHAPE as `PebbleDispersion.dispersion_
  chance`/`LiftableStone.try_disperse` (a footstep's momentum vs. the
  target's own mass, rolled fresh every contact): a real dry leaf's mass
  (`LeafLitterField.LEAF_EFFECTIVE_MASS_KG`, 2g, kept generous) is light
  enough that this clamps to `PebbleDispersion.MAX_DISPERSION_CHANCE_PER_
  CONTACT` in practice, matching how easily real litter disturbs
  underfoot.
- **Animals.** "Walk over" already means grounded contact, so this
  naturally only ever applies to creatures actually standing on the
  ground -- nothing further to filter, unlike `_step_water_ripple`'s own
  `_current_action == "swim"` gate. To avoid the exact `O(creatures x
  instances)` cost `PebbleDispersion` stays player-only to dodge, each
  creature calls a cheap, self-throttled entrypoint itself
  (`CreatureMarker._step_leaf_litter_dispersal`, mirroring that same
  marker's existing `_world.record_water_disturbance(...)` call for water
  ripples) rather than one central scan over every creature.

### Consumption

A fallen leaf is no longer a scene node at all, so it cannot join
`DroppedItem.FORAGEABLE_GROUP_NAME` the way the first pass's leaves did.
`DecomposerMarker` takes an OPTIONAL injected `_world` reference for this
one case -- mirroring `CreatureMarker`'s own identical `_world` pattern
(defaults `null`, guarded everywhere it is used) -- narrowing, not
breaking, this marker's own "no chunk-specific dependency" principle the
same way it already special-cases worms. A new branch in `_nearest_food()`
queries `_world.nearest_leaf_litter_near(position, radius)`; the forage
target becomes a tiny never-added `LeafForageHandle` (a plain `Node2D`
standing in for a real scene node) whose `consume_leaf_litter()` delegates
to `_world.consume_leaf_litter_at(position)`. A decomposer with no `_world`
set (most of this file's own tests, and any decomposer built standalone)
simply never finds leaf litter and keeps foraging carrion/fruit exactly as
before -- not a crash from an assumed-present dependency.

**Scoped to the visible decomposer path only, this pass** -- unchanged from
the first pass's own scope note. The invisible `AntColony` simulation's own
windfall foraging (`_forage_windfall_near_mound`) queries `fruit_near`/
`take_fruit_at`, which (correcting a factual error in this doc's own first
version) scan REAL `DroppedItem` ground nodes filtered by `TreeSpecies.IDS`
-- not, as previously claimed here, "the fruiting model's abstract per-tree
fruit stock" directly; there is no such abstract stock these two functions
read at all. Extending the invisible colony simulation to forage leaf
litter too is a reasonable, separable follow-up, not required here: this
codebase already has precedent for splitting "the visible ants" and "the
invisible colony simulation" across passes for this exact feature area.

### Lifecycle

`LeafLitterField.LIFETIME` (90 seconds, unchanged from the first pass's own
`DroppedItem.LIFETIME`) -- ordinary flat despawn, not food-spoilage-timed,
the same tidiness rule every other non-food dropped item already follows.
A relocated (wind/player/animal-nudged) leaf does NOT get a fresh lease on
life: only `spawned_at` (set once, at the original fall) drives pruning;
`relocate_leaf_near`/`try_disperse_near` update the leaf's position and its
CURRENT transition timing only. No new persistence: exactly like windfall
fruit today, a fallen leaf that nobody ate or that a chunk unload swept away
is not remembered as a specific missing instance.

### History: why not the density-field shortcut

**A pure GPU density-field aggregate (the same technique `SnowBombShader`
uses for snow) was tried and abandoned for this feature TWICE -- once
before the first `DroppedItem`-based pass shipped, and once again as this
rewrite's own first instinct before landing on `LeafLitterField` instead.**
Both times, for the same reason: a density field has no discrete position
left for a decomposer to forage from at all, which is the entire reason
this feature exists in the first place (see this doc's own opening report).
This rewrite is NOT a rejection of GPU rendering for leaf litter -- it uses
exactly that, via `LeafLitterRenderer`'s own `MultiMeshInstance2D` -- it is
specifically a rejection of collapsing many leaves into one scalar/field
with no way back to an individual leaf's own position. Keeping cheap plain
DATA (`LeafLitterField`) separate from cheap GPU RENDERING (`LeafLitterRenderer`)
is what lets this pass have both: real per-leaf positions a decomposer can
query and remove, and a single draw call per chunk regardless of how many
leaves are on the ground.

This time the choice was also directly informed by a REPORTED performance
cost (the first pass's own per-node `_process()`/`Area2D` overhead), unlike
the first pass's own doc, which noted only that discrete items won "not on
a performance concern this pass ever measured." This rewrite succeeds where
a pure density field could not specifically because `LeafLitterField` keeps
that real per-leaf position while STILL removing the per-node cost that was
actually reported -- the node/script/collision overhead was never inherent
to "a leaf is a discrete, addressable thing," only to representing that
thing as a live scene node.

### Deliberately not modeled

Any feedback from leaf litter onto soil fertility, worm population, or
grass growth. `soil_fauna.md` already names the real version of this ("a
real detritivore population model: litter input -> worm biomass -> bird
carrying capacity") as an explicit, deferred follow-up -- this pass gives
ants and bugs something real to forage, and leaves it exactly as deferred
as it already was rather than half-building it.

**A visible, ground-covering litter-density effect (the forest floor
actually looking blanketed in autumn) is also still out of scope** -- a
genuinely different, larger-N rendering problem than a bounded, per-chunk
set of individually-forageable, individually-despawning leaf instances, and
one this codebase should design deliberately rather than back into as a
side effect of a forage mechanic. Discrete `MultiMesh` instances -- however
GPU-instanced their rendering is -- are not that: each one is still a real,
addressable, lifetime-bounded record, not an aggregate coverage value with
no leaf-shaped thing behind it.

**No third, "rotten/black" colour stage for a leaf still on the ground
once winter arrives**, despite being asked for directly alongside the
green/orange request -- unchanged from the first pass's own reasoning:
`LeafLitterField.LIFETIME` (90 seconds) despawns an ordinary leaf long
before any real season boundary could pass under it in normal play.

## Status

✅ A real leaf falls (autumn's main fall and a light summer trickle) as
cheap per-chunk data (`LeafLitterField`), rendered by one GPU-instanced
draw call per chunk (`LeafLitterRenderer`) that visibly drops and settles
with an ongoing sway, reads the correct season's colour
(`LeafLitterAtlas`/`IllustratedTree.foliage_leaf_for`), and is real forage
a decomposer finds and eats via an injected `_world` reference
(`DecomposerMarker`).

✅ Wind, player, and animal dispersal (see "Dispersal" above) -- all three
triggers share one persisted-relocation mechanism and the same GPU
transition machinery the initial fall uses.

⬜ Invisible `AntColony` windfall foraging extended to leaves (see
"Consumption" above) -- unchanged gap from the first pass.

⬜ Any litter-density/soil-fertility feedback, any ground-covering
litter visual effect, and a third rotten/black colour stage for litter
that outlives `LeafLitterField.LIFETIME` (see "Deliberately not modeled"
above and soil_fauna.md's own deferred detritivore-population note).

⬜ A live in-game visual re-confirmation of this rewrite specifically (fall
animation, wind/player/animal scatter, decomposer forage) -- this pass's
own automated coverage includes a real-GPU render-smoke test
(`test_leaf_litter_renderer_smoke.gd`) proving the shader compiles, samples
real content, and moves a transitioning instance, but not a played session
in the actual game window.
