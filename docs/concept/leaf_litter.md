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
- **Litter left lying darkens and dulls as it weathers.** A freshly fallen
  leaf's vivid fall colour fades toward a duller brown-grey within days as
  it dries out and starts to break down -- the direct grounding for the
  terminal "winter" decay stage (see "Lifecycle" below), and for deriving
  that stage's colour from the leaf's own fallen art rather than drawing
  new, separately-coloured decayed art per species: real decayed litter of
  any species converges toward roughly the same dulled tone, not a
  species-distinct one.

## Mechanism spec

### When leaves fall

**A low, constant baseline runs for the whole of autumn, with the
turn-driven ramp rising on top of it.** Reported directly: "leaf litter
should happen constantly at a low rate in normal gameplay ... in autumn
all leaves should fall eventually." Before this, the chance was driven
only by `canopy_turn_progress`, gated on `canopy_turning_into ==
"winter"` -- but per `TreePhenology.canopy_state_at`, that reads "winter"
for the entirety of autumn, not merely its final visible-turn slice, so
the gate was never actually doing anything; `canopy_turn_progress` alone
reads exactly 0.0 for roughly the first two-thirds of autumn (`TreePhenology
.TURN_FRACTION` is 0.34 of a full season), which meant a real autumn tree
shed nothing at all for ~32 real hours of ordinary, non-accelerated play
before its final visible turn began. A real deciduous tree does not wait
for its colour to fully turn before its first leaves come down -- ordinary
wind and early individual-leaf senescence pull a few down all autumn long
(see "Real-world grounding" above), the same real phenomenon the summer
trickle below already models for wind/petal damage. `leaf_fall_chance` is
now `maxf(LEAF_AUTUMN_BASELINE_CHANCE, canopy_turn_progress)` for the whole
of autumn: the existing turn-progress ramp still rises on top of the
baseline once the canopy's own final turn actually begins (a tree at
`canopy_turn_progress == 1.0` still sheds essentially every step, exactly
as before), and "in autumn all leaves should fall eventually" now actually
holds well before that final turn, not only once it starts.

Read once per fruiting step from `_tree_renderer.canopy_state()` -- the
same values `EarthChunkManager.step_fruiting` already reads once per step
(not per tree, see that function's own doc comment on why) for the
windfall block right beside this one.

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
`"acorn"`, ...); `season` starts as `"summer"` or `"autumn"`, whichever the
leaf actually fell in -- the only two seasons a leaf ever falls in at all
-- and later decays one-way to the terminal `"winter"` stage once it has
sat undisturbed long enough (see "Lifecycle" below); never any other
value, and never reverts once `"winter"`.

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
directly while building this atlas: every one of the 6 species x 2 FALLING
seasons this project ships today actually HAS real illustrated art -- the
first pass's own doc comment named pine's autumn column as a gap; that is
not (or is no longer) true. The fallback path still exists, tested against
a synthetic species, for whenever a real gap does show up.

**A third atlas column, `"winter"`, holds every species' own terminal-decay
stamp -- derived, not illustrated.** No species has real illustrated
"winter" litter art (there is no such thing as a freshly-fallen leaf that
already looks decayed), so `build_stamp_image` special-cases `season ==
"winter"` to recolour that species' own already-built `"autumn"` stamp
rather than falling through to the generic procedural fallback the way a
genuinely-missing pair would. The recolour is the same luminance-preserving
technique `ProceduralFlowerSprite._paint_illustrated_head` already
established for repainting illustrated art a different colour without
losing its own shading (`docs/concept/flora.md`'s "Recolouring illustrated
blooms"): read each opaque pixel's own Rec. 709 luminance as `shade`
(relative to the stamp's own peak), and paint a dulled, deliberately
low-saturation brown-grey (`WINTER_TINT`) at that same brightness. The
result keeps the exact same silhouette and real shading/vein variation as
the autumn art it derives from, just duller -- verified both by test
(silhouette match, reduced saturation, preserved shading variation, all in
`test_leaf_litter_atlas.gd`) and by rendering every species' autumn/winter
stamp pair side by side and inspecting the image directly (`tools/probe_
leaf_winter_stamp.gd`), since a numeric saturation check alone cannot
confirm the result reads as a believable decayed leaf rather than a flat
smear. Deriving from autumn specifically (rather than needing a second
derivation from summer) mirrors a real simplification: by the time any
fallen leaf has weathered long enough to look wintry, its original fall
colour has already faded toward the same dulled tone regardless of what it
started as (see "Real-world grounding" above).

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

**Tumbling: a real spin, not just a wobble.** Reported directly: "the
leaves blowing in the wind animation... they should twirl more and have
more realistic / natural motion paths" -- this doc's own "Real-world
grounding" section above already named the target ("visibly tumbles and
skitters across open ground"), but the first cut of this rewrite only
carried over `DroppedItem`'s original vertical-fall wobble
(`transition_rotation`: oscillates within a small fixed arc, always
decaying back toward zero) unchanged onto every kind of transition,
including a leaf genuinely carried across open ground by real wind --
which never actually spins through, just rocks in place. `tumble_rotation`
adds a second, ACCUMULATING rotation on top (summed with the existing
wobble, not replacing it) that grows monotonically with progress and
reaches its own full turn count exactly once the transition completes,
continuing in one consistent direction for that leaf
(`spin_direction_for_phase`, reusing the same position-derived phase hash
`transition_flutter_world`'s own per-leaf variety already relies on, so
two leaves tumbling side by side do not all spin the same way). How many
turns scales with how FAR this transition actually carries the leaf
(`tumble_turns_for_distance`, 0.5 turns near zero distance up to 3.0 turns
at `MAX_TRANSITION_OFFSET`, the longest real wind-blown journey this game
models) -- since `TRANSITION_DURATION` is the same fixed span regardless
of distance, a longer journey is also a faster one, so scaling turns by
distance is equivalently scaling them by how hard the wind is actually
moving this particular leaf, the same real thing that makes a tumbling
leaf spin harder. A footstep settle-back-into-place barely turns; a real
wind-blown journey visibly cartwheels several times -- verified directly
against the real GPU (`test_a_farther_traveling_leaf_tumbles_more_than_a_
nearby_one`) and by rendering an actual transition frame by frame, not
only reasoned about from the numeric mirror.

`transition_flutter_world`'s own sideways path also gained a second,
smaller, non-harmonic wave (a non-integer frequency ratio against the
first, so the two never realign into one simple repeating shape within a
single transition) -- a lone clean sine reads as too mechanically regular
for something as irregular as a leaf actually tumbling through real
turbulent air; the added wave shares the same taper-to-zero-at-completion
guarantee the original already had.

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

**A settled leaf decays to a terminal `"winter"` stage before it despawns.**
Reported directly: "fallen leaves should change the season from autumn to
winter if they keep lying on the ground ... winter is last stage for a
leaf." `LeafLitterField.DECAY_TO_WINTER_SECONDS`, pinned at exactly half of
`LIFETIME` (45 seconds), advances a SETTLED leaf's own `season` from
`"autumn"`/`"summer"` to `"winter"` one-way in `advance()` -- never reverts,
never advances past `"winter"` to anything else. Gated on the leaf actually
being settled (`transition_from == position`), the same "only a SETTLED
leaf is eligible" rule the wind-dispersal roll right beside it already
applies, for the identical reason: "keep LYING on the ground" implies
actually at rest, not still easing into a relocation. A standalone,
`LIFETIME`-relative timer rather than one tied to the real in-game
calendar season: a real season's own turning window alone runs ~16 real
hours in normal, non-accelerated play, and `LIFETIME`'s whole 90 seconds
would elapse and prune the leaf long before the actual calendar ever
reached winter -- so this is deliberately its own clock, grounded against
the one timer that already exists (see that constant's own doc comment)
rather than against the real calendar `LEAF_LITTER_ENABLED`'s own fall
trigger uses. See "Rendering" above for how the terminal stage's own
colour is produced without any new art.

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

~~No third, "rotten/black" colour stage for a leaf still on the ground~~
-- **reversed 2026-09-05.** The first pass's reasoning above (`LIFETIME`
despawns a leaf long before any real season boundary could reach it) is
still true of the CALENDAR season, but the follow-up report asked for a
stage keyed to how long the leaf itself has been lying there, not to the
calendar -- see "Lifecycle" above for the terminal `"winter"` decay stage
this became, timed against `LIFETIME` itself rather than against the
calendar for exactly that reason.

## Status

**Back on by default (2026-09-05).** Was briefly off (requested directly:
"deactivate leaf littering", right after the GPU rewrite below shipped),
then reported live as the real cost of that: "ants and beetles just walk
back and forth and there's no real foraging" -- with the flag off,
carrion and fresh windfall fruit are the only things left for a
decomposer to find, and neither is reliably near a wandering ant/bug
early in a game, so this was the missing, common, ambient food source.
`EarthChunkManager.LEAF_LITTER_ENABLED` gates the leaf-fall block that
everything below depends on; with it off, no leaf is ever added to a
field, so nothing downstream (rendering, forage, dispersal) has anything
to act on.

**Live-verified before flipping it back on**, closing the exact gap this
Status section used to name ("not a played session in the actual game
window"): launched via `--solo --rendering-driver opengl3` and read
`Engine.get_frames_per_second()` directly (this project's own established
"instrument, launch, read the log" method for anything a unit test
structurally cannot see), rather than assuming the GPU rewrite fixed the
original per-node report just because the architecture changed.
- **First attempt was a false alarm, not a real finding.** Using `/ecotest`
  to fast-forward to autumn (needed since a real year is far longer than
  any diagnostic window) pinned FPS at 1-3 -- but a controlled comparison
  with `LEAF_LITTER_ENABLED` forced off, identical otherwise, measured the
  *same* 1-3fps with zero leaves ever present. That ruled leaf litter out
  as the cause: `/ecotest`'s own per-frame catch-up slicing (see
  `TimeLapse.slices`) appears to carry a real, separate performance cost
  of its own, present at ANY acceleration tested (both the default 45s/
  year and a more aggressive 5s/year) -- a pre-existing dev-tool
  characteristic unrelated to this feature, seemingly never measured
  before either (no existing probe ties FPS to ecology timing). Left
  unfixed here as clearly out of this pass's scope; worth its own
  separate look.
- **The real test**: normal (1x, unaccelerated) speed, which is how the
  game is actually played almost all the time, recovers to a healthy
  15-27fps on modest Intel integrated graphics once chunks finish loading
  -- confirmed both with leaf litter's own systems idle (spring, nothing
  shed yet) and, decisively, with 30 loaded chunks directly seeded ~750-
  960 real simultaneous leaves each (`LeafLitterField.add_leaf`, well
  above what a natural autumn would ever produce across a normal play
  session at once) and left rendering/aging under `step_leaf_litter` for
  30+ real seconds: FPS held steady at 14-25 throughout, no degradation
  from the leaf-free baseline. The GPU rewrite's whole premise -- one
  `MultiMeshInstance2D` draw call per chunk plus cheap plain-data leaf
  records, replacing a live scene node per leaf -- holds up under real
  measurement, not just architecturally plausible reasoning.

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

✅ **A real accumulating tumble, not just a wobble** (see "Tumbling: a
real spin, not just a wobble" above) -- reported directly ("they should
twirl more and have more realistic / natural motion paths"), scaled by
how far each transition actually carries the leaf so a footstep settle
barely turns where a real wind-blown journey visibly cartwheels several
times. Verified both on the real GPU and by rendering an actual
transition frame by frame, not only reasoned about from the mirror.

✅ Live in-game performance re-confirmation of the GPU rewrite (see
above) -- closes the gap this section used to name. The pre-existing
real-GPU render-smoke test (`test_leaf_litter_renderer_smoke.gd`) still
covers shader-compiles/samples-real-content/moves-a-transitioning-
instance correctness at 1-leaf scale; this closes the separate,
previously-missing "does it hold up at real volume, at real speed"
question.

✅ **A low, constant autumn baseline shed rate, on top of the existing
turn-driven ramp** (see "When leaves fall" above) -- reported directly
("leaf litter should happen constantly at a low rate in normal gameplay
... in autumn all leaves should fall eventually"), closing a real ~32-real-
hour zero-chance gap across the first two-thirds of every autumn.

✅ **A settled leaf decays to a terminal `"winter"` stage** (see
"Lifecycle" above) -- reported directly ("fallen leaves should change the
season from autumn to winter if they keep lying on the ground ... winter
is last stage for a leaf"), timed against `LeafLitterField.LIFETIME`
itself and rendered via a derived recolour of each species' own autumn
stamp (see "Rendering" above), verified both by test and by direct visual
inspection of the rendered stamps.

⬜ Invisible `AntColony` windfall foraging extended to leaves (see
"Consumption" above) -- unchanged gap from the first pass.

A reported hang in `test_step_fruiting_drops_a_leaf_from_a_turning_tree`
(400+ CPU-seconds observed on one run) was investigated 2026-09-05 and
traced to shared-machine contention, not a bug in the fall-triggering
mechanism above -- see `docs/progress.md`'s own matching entry for the
full call-chain trace and reproduction data.

⬜ Any litter-density/soil-fertility feedback and any ground-covering
litter visual effect (see "Deliberately not modeled" above and
soil_fauna.md's own deferred detritivore-population note).

⬜ **`/ecotest`'s own accelerated-time performance cost, independent of
leaf litter** (see the live-verification note above) -- measured as a
real, severe FPS drop present at any tested acceleration with LEAF
LITTER OFF and zero leaves, so it lives in the ecology time-lapse/
catch-up-slicing mechanism itself (`scenes/world.gd`, `TimeLapse`), not
here. Named rather than silently left for whoever next reaches for
`/ecotest` and is confused by it.
