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

**Autumn's own chance is constant, continuous, and increasing across the
WHOLE season -- not flat for two-thirds of it and then a late ramp.**
Reported directly, twice: first "leaf litter should happen constantly at a
low rate in normal gameplay ... in autumn all leaves should fall
eventually" (closed a real ~32-real-hour zero-chance gap, since
`canopy_turn_progress` reads exactly 0.0 for autumn's own settled first
two-thirds), then, once that first fix landed as `maxf(LEAF_AUTUMN_
BASELINE_CHANCE, canopy_turn_progress)`: "make leaf litter constant and
continuous and increasing in autumn" -- flat-then-ramp is continuous but
not *increasing* across the whole season, only across its final third.

`leaf_fall_chance_for` (a pure static function, directly unit tested
rather than only exercised through noisy per-tree roll sampling) now
drives autumn from `SeasonCycle.progress_through_season` instead --
**not** `canopy_turn_progress`, which stays pinned at 0.0 for the
season's entire settled span by construction (see that function's own
doc comment) and so can never rise smoothly across all of it.
`progress_through_season` is the raw fraction `[0,1)` through the
CALENDAR season, rising from a season's very first instant rather than
waiting for TreePhenology's own visual turn to begin. The chance is a
single linear interpolation from `LEAF_AUTUMN_BASELINE_CHANCE` at
autumn's first instant up to CERTAINTY (1.0) at its last: constant (never
zero), continuous (no jump at the old turn-progress boundary), and
increasing (strictly rises) the whole way -- linear because nothing in
either report asks for a particular curve shape beyond those three
properties, and it is the simplest one that has them. A tree at
`season_progress == 1.0` still sheds essentially every step, exactly as
the old formula's `canopy_turn_progress == 1.0` case did.

Read once per fruiting step (both `canopy_season` from
`_tree_renderer.canopy_state()` and `season_progress` from
`_season_cycle.progress_through_season`) -- the same values
`EarthChunkManager.step_fruiting` already reads once per step (not per
tree, see that function's own doc comment on why) for the windfall block
right beside this one.

A settled SUMMER tree also sheds an occasional leaf -- real wind and
petal damage, not the main fall (`LEAF_SUMMER_TRICKLE_CHANCE`, a flat 3%
per step, named rather than derived, the same "one real table beats an
invented formula" idiom `FruitingModel.RIPENING_BY_SPECIES` already
sets). Reported directly: "when they fall in summer they should be
green" -- which only means anything if a summer fall is real, not merely
implied by an autumn-only trigger. Flat across the whole season
deliberately, unlike autumn: real wind/petal damage does not build across
a season the way a deciduous canopy's own colour change does.

**A settled SPRING tree -- specifically while its canopy still visibly
carries blossom -- sheds an occasional BLOSSOM instead of a leaf.**
Reported directly: "there should always be an occasional falling leaf or
blossom." Before this, spring shed nothing at all, on the reasoning that
neither the autumn turn nor the summer trickle condition was true here --
true, but the real gap it left unfixed was that a falling LEAF makes no
botanical sense while a tree has no leaves yet, not that spring should
stay silent. `LEAF_SPRING_TRICKLE_CHANCE` reuses `LEAF_SUMMER_TRICKLE_
CHANCE`'s own value (the same real background-shedding rate, not a third
independently-tuned number), gated on `canopy_season == "spring"` --
which, per `TreePhenology`'s own canopy schedule, is narrower than the
calendar season: a tree's canopy finishes leafing out (and `canopy_season`
flips to `"summer"`, at which point the EXISTING summer trickle above
already takes over seamlessly) well before spring's own calendar quarter
ends. The fallen record's own `season` field reads `"spring"`, which
`LeafLitterAtlas` renders as a real blossom/petal closeup, not a leaf (see
"Rendering" below) -- distinguishing it from a leaf is not cosmetic, it is
the entire point of the report.

Winter alone drops nothing: a bare canopy has nothing left to shed. Pine,
which never really goes bare, is judged the same way as every other
species by the same canopy clock -- if a future pass gives conifers their
own non-deciduous phenology, this mechanic follows without changes, since
it never hard-codes a species list here.

### What falls: a data record, not an item

A fallen leaf is a plain `{position, species, season, spawned_at,
transition_from, transition_start}` record in that chunk's own
`LeafLitterField` (`src/world/leaf_litter_field.gd`) -- NOT an `Item`/
`ItemStack` any more (the first pass's `"<species>_leaf"` item id,
`"material"` kind, and per-species display name table are gone; litter is
never inventoried, hover-named, or picked up by hand, so that data had no
remaining consumer). `species` is the plain `TreeSpecies` id (`"cherry"`,
`"acorn"`, ...); `season` starts as `"spring"`, `"summer"`, or `"autumn"`
-- whichever the leaf/blossom actually fell in, the only three seasons
anything ever falls in at all -- and later decays one-way to the terminal
`"winter"` stage once it has sat undisturbed long enough (see "Lifecycle"
below); never any other value, and never reverts once `"winter"`. A
`"spring"` record is a fallen BLOSSOM, not a leaf -- same record shape,
same field, same renderer, just different sourced art (see "Rendering"
below); this class stays named `LeafLitterField`/`LeafLitterAtlas`/
`LeafLitterRenderer` regardless, the same "generalise the mechanism,
don't rename the class for one more case" choice `"winter"` already made.

`step_fruiting`'s own leaf-fall block otherwise keeps the same per-(tree,
step) deterministic `PixelNoise` roll and the same random angle/distance
scatter within the canopy's own rough radius (`LEAF_SCATTER_RADIUS`)
around the trunk it always had -- only the chance computation (see "When
leaves fall" above) and the final step changed: instead of building an
`Item`/`ItemStack` and emitting it through `WorldItemBus` (which `World`
would turn into a real `DroppedItem` node), it calls `LeafLitterField
.add_leaf(position, species, season, now)` directly on the tree's own
chunk's field.

**The colour still matters and is still read from the real art, not
guessed** -- that part of the first pass carries over unchanged in spirit,
just moved from a per-instance runtime lookup into a prebuilt atlas (see
"Rendering" below). `LeafLitterAtlas` (`src/rendering/leaf_litter_atlas.gd`)
packs every species/season pair's own real illustrated closeup
(`IllustratedTree.foliage_leaf_for`) into a fixed-cell-grid runtime atlas at
process start, falling back to the same generic procedural sprite
`DroppedItem` always used for any pair lacking dedicated art. Checked
directly while building this atlas: every one of the 6 species x 3 FALLING
seasons this project ships today actually HAS real illustrated art -- the
first pass's own doc comment named pine's autumn column as a gap; that is
not (or is no longer) true. The fallback path still exists, tested against
a synthetic species, for whenever a real gap does show up.

**A `"spring"` column holds every species' own real BLOSSOM closeup, not a
leaf.** `IllustratedTree.foliage_leaf_for` resolves it the same way it
already resolves summer/autumn, just without a fixed hue band: real
blossom colour is not one universal hue across species the way leaf
colour is (a real cherry/apple bears showy pink/white petals; a real
oak/hazelnut/walnut bears small, inconspicuous, wind-pollinated
yellow-green catkins), so the selection accepts any real, non-neutral
colour rather than requiring one specific hue. Verified visually
(`tools/probe_blossom_foliage.gd`), not just by the numeric non-blank/
differs-from-other-seasons tests: **cherry's own spring closeup is a
genuinely recognisable pink blossom flower** -- the best case, and the
species players are likeliest to notice given the real-world cultural
association. Acorn/hazelnut/walnut/apple land on a green, leaf-toned crop
instead of a distinct floral image (not blank or broken, just less floral
than hoped -- their sheets' own blossom-column art reads closer to an
early leaf than a distinct petal at the fill/colour signals this
detection uses); pine lands on the same winged-seed-pair crop its own
already-documented autumn imperfection uses (see `_foliage_closeups`' own
doc comment in `illustrated_tree.gd`). Named here rather than hidden,
the same as that existing pine/autumn gap always has been -- the feature
this report asked for (an occasional falling blossom, distinct from a
leaf, in every species) is genuinely delivered for all six species; only
the FLORAL FIDELITY of five of them falls short of cherry's.

**A `"winter"` column holds every species' own terminal-decay stamp --
derived, not illustrated.** No species has real illustrated
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

**A `"fading"` column holds every species' own halfway-decayed stamp --
derived from two stamps this atlas has already built, not a fresh
recolour pass.** Reported directly: "leaf decay should be 3 seasons" (see
"Lifecycle" below for the timing this grounds against). No species has
real half-decayed litter art either, so `build_stamp_image` special-cases
`season == "fading"` to blend that species' own already-built `"autumn"`
stamp with its already-derived `"winter"` stamp -- a straight per-pixel
`Color.lerp` at `FADING_BLEND` (pinned at exactly 0.5, the same midpoint
the decay TIMING's own even three-way split already lands on), needing no
new shading logic at all: both source stamps already carry real,
correctly-shaded content, so their midpoint is itself a believable colour
at the same brightness. Verified both by test (silhouette match,
saturation strictly between the two endpoints -- not indistinguishable
from either, which would collapse the report's own "3 seasons" back to 2
apparent stages -- the exact pinned blend checked per channel against real
sampled pixels, preserved shading variation) and by rendering every
species' autumn/fading/winter stamp trio side by side and inspecting the
image directly (`tools/probe_fading_stamp.gd`): every species shows a
clear, visually distinct 3-step progression, vivid to duller to fully
decayed.

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
  leaf_ground_drift`, using a `WindDispersal.WEIGHT_LEAF` class (sitting
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

  **`leaf_ground_drift`, not `WindDispersal.landing_offset` -- reported
  directly: "make the wind blowing through leaves make the tumble and
  swirl more smoothly? it's a hard back forth motion atm."**
  `landing_offset`'s own scatter term is a fully independent 0-360 degree
  random angle -- right for a SEED falling once (it really does scatter
  near its parent on a still day regardless of which way any breeze
  blows), wrong for a leaf ALREADY on the ground being nudged by the SAME
  ambient wind repeatedly: measured directly, of 30 samples under a
  strong steady wind, only 57% landed within 30 degrees of the wind's own
  heading and 30% landed more than 90 degrees off -- genuinely backwards,
  several nearly exactly opposite the wind -- so a single leaf's own
  consecutive nudges could easily alternate between "blown downwind" and
  "blown upwind" purely by chance. `leaf_ground_drift` reuses the exact
  same heavy-tailed reach/buoyant-scatter DISTANCE distribution
  `landing_offset` already establishes (so every existing distance-driven
  consumer, e.g. the tumble-turn scaling below, still sees the same range
  of journeys), but bounds the ANGLE to `LEAF_DRIFT_WOBBLE_DEGREES` (45,
  half the 90-degree structural ceiling that guarantees positive forward
  progress along the wind) around the wind's own heading instead of an
  independent full-circle roll. `landing_offset` itself is untouched --
  seed/flower dispersal already depends on its current scatter shape.
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

**`LeafLitterField.LIFETIME` is a real ~270-real-world-day lifespan, not an
arbitrary tidiness cutoff.** Reported directly: "leafs should take roughly
270 days to rot / decay / vanish". 270 real-world days is ~3 of the 4 real
seasons a year actually has (~91 days each) -- the genuine real-world
timescale leaf litter actually takes to fully decompose -- expressed as
exactly 3/4 of a real year and translated through the SAME real-year ->
compressed-game-year ratio every other real-world-grounded timing constant
in this codebase already uses (`SeasonCycle.SECONDS_PER_YEAR`), the same
idiom `TreePhenology`'s own blossom timing already established for turning
a real biological duration into game-playable time. Was a flat, arbitrary
90-SECOND despawn (the first pass's own `DroppedItem.LIFETIME`, an ordinary
non-food tidiness rule) with no real-world grounding at all, before this.
A relocated (wind/player/animal-nudged) leaf does NOT get a fresh lease on
life: only `spawned_at` (set once, at the original fall) drives pruning;
`relocate_leaf_near`/`try_disperse_near` update the leaf's position and its
CURRENT transition timing only. No new persistence: exactly like windfall
fruit today, a fallen leaf that nobody ate or that a chunk unload swept away
is not remembered as a specific missing instance.

**A settled leaf decays through exactly 3 stages before it despawns, not
2.** Reported across two rounds: first "fallen leaves should change the
season from autumn to winter if they keep lying on the ground ... winter
is last stage for a leaf" (shipped as a single jump straight to `"winter"`
at half of `LIFETIME`), then "leaf decay should be 3 seasons" -- the same
270-day/3-real-season figure `LIFETIME` itself is now grounded in.
`LeafLitterField.DECAY_TO_FADING_SECONDS`/`DECAY_TO_WINTER_SECONDS`, pinned
at an even three-way split of the new `LIFETIME` (one third and two
thirds), advance a SETTLED leaf's own `season` one-way from its own fall
colour (`"spring"`/`"summer"`/`"autumn"`) through `"fading"` to the
terminal `"winter"` in `advance()` -- never reverts, never advances past
`"winter"` to anything else, matching the report's own framing exactly:
one real season fresh, one fading, one fully decayed before vanishing.
Gated on the leaf actually being settled (`transition_from == position`),
the same "only a SETTLED leaf is eligible" rule the wind-dispersal roll
right beside it already applies, for the identical reason: "keep LYING on
the ground" implies actually at rest, not still easing into a relocation.
See "Rendering" above for how "fading"'s own colour is produced without
any new art (a plain blend of the already-derived autumn and winter
stamps, at exactly the same midpoint the timing split already uses).

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

✅ **Autumn's own leaf-fall chance is constant, continuous, and increasing
across the WHOLE season** (see "When leaves fall" above) -- reported
directly, twice: first closing a real ~32-real-hour zero-chance gap
across the first two-thirds of every autumn (a flat baseline), then,
once that first fix's own flat-then-ramp shape turned out not to be
"increasing" across the whole season either, replaced with a single
smooth interpolation driven by `SeasonCycle.progress_through_season`
(not `canopy_turn_progress`, which cannot rise across a season's whole
settled span by construction). Extracted into a pure, directly unit
tested `leaf_fall_chance_for` rather than only exercised through noisy
per-tree roll sampling -- retroactively confirmed those tests actually
catch a regression by temporarily stubbing the function and watching
5 of 6 fail for the right reason.

✅ **A settled SPRING tree sheds an occasional BLOSSOM, not a leaf** (see
"When leaves fall"/"Rendering" above) -- reported directly ("there should
always be an occasional falling leaf or blossom"). Reuses the exact same
record shape, field, and renderer a fallen leaf always has; only the
`season` value (`"spring"`) and the art `LeafLitterAtlas` resolves for it
differ. `IllustratedTree.foliage_leaf_for` now resolves real blossom art
for every species -- cherry's is a genuinely recognisable pink flower,
verified visually, not just by a non-blank/differs-from-other-seasons
test; acorn/hazelnut/walnut/apple land on a leaf-toned crop instead of a
distinct floral image, and pine reuses its own already-documented
autumn-imperfection crop -- named, not hidden, the same as that existing
gap always has been.

✅ **A settled leaf decays through exactly 3 stages -- fresh, `"fading"`,
terminal `"winter"` -- across a real ~270-real-world-day lifespan, not a
single jump across an arbitrary 90-second one** (see "Lifecycle"/
"Rendering" above). Reported across two rounds: first "fallen leaves
should change the season from autumn to winter if they keep lying on the
ground ... winter is last stage for a leaf" (shipped as a single jump),
then "leaf decay should be 3 seasons" (clarified: "leafs should take
roughly 270 days to rot / decay / vanish") -- `LeafLitterField.LIFETIME`
is now that real ~270-day/3-real-season figure, translated through the
compressed game calendar the same way every other real-world-grounded
timing constant in this codebase already is, with the decay thresholds an
even three-way split of it. `"fading"`'s own colour is a plain blend of
the already-derived autumn/winter stamps at the same midpoint the timing
split lands on -- verified both by test and by rendering every species'
autumn/fading/winter trio side by side and inspecting the image directly.

✅ **Wind-blown leaves drift smoothly instead of reversing direction**
(see "Dispersal" above) -- reported directly ("make the wind blowing
through leaves make the tumble and swirl more smoothly? it's a hard back
forth motion atm"), root-caused with a direct measurement rather than
guessed at: `WindDispersal.landing_offset`'s own independent 0-360 degree
scatter term (correct for a seed falling once) landed more than 90 degrees
off the wind's own heading 30% of the time for `WEIGHT_LEAF`, letting a
single settled leaf's consecutive nudges swing wildly between downwind
and upwind. New `WindDispersal.leaf_ground_drift` bounds the angle to a
wobble around the wind's own heading instead, verified both by test
(200-seed sweeps: never past the bound, never reverses) and by
re-simulating the exact scenario that first exposed the bug.

⬜ Invisible `AntColony` windfall foraging extended to leaves (see
"Consumption" above) -- unchanged gap from the first pass.

⬜ **Standing leaf-litter population at the new, much longer `LIFETIME`
has not been live-performance-verified.** The existing 750-960-leaves-
per-chunk burst test above predates this change: it seeded a fixed count
directly and watched FPS over a short (30 real second) window that never
actually depended on `LIFETIME`'s own value, so it does not by itself
confirm safety at whatever STANDING population a much longer real
accumulation window (up to the new ~270-real-world-day-equivalent
lifespan, vs. the old 90 seconds) could permit during an actual long play
session, especially combined with autumn's own now constantly-increasing
shed rate. Named rather than assumed safe purely because the architecture
did not change -- the exact mistake this file's own "Back on by default"
note above was already careful not to repeat for the original GPU
rewrite.

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
