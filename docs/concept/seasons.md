# Seasons

A calendar season cycle that gives the world a slow yearly rhythm. This is the
seasonal-forcing layer that [weather.md](weather.md) assumes ("driven by the
existing climate/season/day-night clock") and that
[ecosystem_dynamics.md](ecosystem_dynamics.md) flagged as its missing input:
phenology, growth, and (later) weather all read the current season instead of a
flat constant.

## Design pillars

1. **A real yearly rhythm, deterministic.** Season is a pure function of elapsed
   game-time — spring → summer → autumn → winter → spring — so the same moment
   always yields the same season and any two systems that read it agree.
2. **Modulates, doesn't gate.** Season shifts *rates* (how fast trees fruit, how
   vigorously plants grow) smoothly rather than switching things fully on/off, so
   transitions read as a gradual warming/cooling, not a hard flip. Real ecosystems
   respond to a continuous photoperiod/temperature curve, not a step change.
3. **One clock, many readers.** Fruiting, vegetation growth, weather, survival
   exposure, and the player's own hunger and thirst
   (`SurvivalMeters.SECONDS_TO_STARVE`/`SECONDS_TO_DEHYDRATE`, derived from
   `SECONDS_PER_DAY`) all read the one season value, the same way loaded and
   unloaded chunks share one population model — "two fidelities, one truth"
   applied to time.

## The season cycle

Elapsed game-time is divided into a year of four equal seasons. From it we derive:

- **Season** (`spring`/`summer`/`autumn`/`winter`) — the discrete label, for UI
  ("Spring · Rain") and any season-gated logic.
- **Warmth modifier** `[0,1]` — a smooth (cosine) curve peaking mid-summer and
  troughing mid-winter, standing in for the seasonal temperature/photoperiod
  swing. Multiplies the local climate warmth that drives fruit ripening
  (`FruitingModel` warmth): trees ripen and drop fruit fast in summer, slowly or
  not at all in deep winter — a compressed real bearing season.
- **Growth modifier** `[0,1]` — how vigorously vegetation grows this season
  (high in spring/summer, low in autumn/winter), for the vegetation/tall-grass
  layer to scale its growth rate later.

The year length is a tuned constant (compressed so a play session spans multiple
seasons), pinned by tests, not eyeballed.

## A new world starts at a random point in the year

**New Game rolls a random starting moment in the year; Load Game resumes its
own.** The world clock (`EarthChunkManager._world_age_seconds`, what
`season_at`/`warmth_modifier` above are pure functions of) used to start at a
hardcoded `0.0` for every fresh save, with no persistence at all — and `0.0`
is not a neutral moment: `warmth_modifier`'s own phase formula puts it at
warmth ≈0.1465, just under [weather.md](weather.md)'s snow threshold
(`Snowfall.FREEZING_WARMTH`, 0.15). Every new game therefore began mid-
winter-adjacent and reliably snowed within the first few minutes (reported:
"it starts to snow deterministically") — one hardcoded starting instant
masquerading as "a fresh world," identical every single time.

A new world should be free to begin in any season, the way a real save
started "whenever" would. `EarthChunkManager.randomize_world_age()` rolls a
uniform offset in `[0, SeasonCycle.SECONDS_PER_YEAR)` — Godot's own default-
seeded `randf()`, not a fixed seed — **once**, at New Game/Host Game creation
(`World._wipe_persisted_world`), and immediately re-syncs every other mark
that measures itself against the clock (`_last_fruiting_time`,
`_snow_world_age` — see `set_world_age_seconds`) so the jump doesn't read as a
fake elapsed span the next time fruiting or snow steps. **Load Game never
re-rolls**: it restores the clock's own persisted value
(`EarthChunkManager.load_world_clock`, `WorldClockPersistence`, the same
`user://`-backed convention `PlayerSave`/`EventStorePersistence` already
established — see [persistence.md](persistence.md)) before its first chunk
load, so a resumed session picks up exactly where it stopped rather than
time-travelling on every launch.

## The ground carries the season too

The canopies turned and nothing underneath them did. Forcing `/season winter`
gave bare trees standing on a bright, high-summer lawn, in tall grass that
was still lush, over crop tops that were still green — because the season was
something that happened to `IllustratedTree`'s four canopy frames and to
nothing else. `ProceduralTerrainSprite.BASE_COLORS` is a flat, year-round
table; `IllustratedGrassPatch`'s blade shader had no colour term at all.

`src/rendering/seasonal_foliage.gd` is the ground-cover analogue of
`IllustratedTree`'s canopy-frame table: **what a season multiplies living
green by**, blended across a turn by the very same
`SeasonTransition.state_at` the canopies turn on, so the lawn and the crown
above it can never disagree about what month it is.

**Why a tint and not four sets of art.** The ground cover is painted into a
disk-cached atlas (`TerrainAtlasCache`) keyed by ONE version string
(`TerrainRenderer.ATLAS_VERSION`), with no per-tile invalidation — it is
all-or-nothing for the whole image, measured at ~5MB on a real machine, and
`build_tile_set` hands the live `TileMapLayer` the `TileSet` built from it.
Baking the season into those pixels would mean folding the season into
`ATLAS_VERSION`: four separate atlases, a full `_build_atlas_pixels()` run
the first time each season is reached, and a whole `TileSet` rebuild landing
mid-session at the exact moment the season turned — precisely the boot cost
the cache exists to avoid, relocated to the worst possible instant. A
`uniform vec3 season_tint` on the `ShaderMaterial` the terrain layer already
wears costs one parameter write and invalidates nothing.

There are TWO caches between the painted pixels and the screen, and the season
has to stay out of both. The disk atlas is keyed by `ATLAS_VERSION`, pinned by
`test_the_season_never_enters_the_atlas_cache_key_so_a_cached_atlas_cannot_go_stale`
(`test_ground_tint.gd`). The built `TileSet` is then memoized for the whole
process by `TerrainRenderer._tile_set_cache_key`, which is a *separate* key —
a season folded into it would rebuild all 10,240 atlas cells mid-session
without ever touching `ATLAS_VERSION`, so the first guard cannot see it.
`test_a_season_turn_changes_the_material_and_not_one_pixel_of_the_atlas`
(`test_terrain_renderer.gd`) covers that second key, asserting behaviourally
that a turn to winter lands on the *material* while the memoized `TileSet` and
the baked grassland tile's pixels come back identical. Verified by mutation:
adding the live season to `_tile_set_cache_key` makes it fail immediately.

**Why it reads season NAMES and not `warmth_modifier`.** `warmth_modifier` is
a cosine: mid-spring and mid-autumn sit at exactly the same warmth. Warmth
alone cannot tell a greening year from a dying one, and those two must not
share a colour — so the tint is looked up by the season `SeasonTransition`
reports, not derived from the warmth curve.

**Why the numbers are colours, not gains.** Each season names what a
GRASSLAND TILE should look like then — new growth in spring, the shipped
`BASE_COLORS["grassland"]` itself in summer, a senescing olive-gold in
autumn, dead drab thatch in winter — and the multiplier is that target
divided by summer's, channel by channel. Summer therefore comes out as the
exact identity and high summer stays pixel-for-pixel the picture that already
shipped; every other season is "what it takes to turn the shipped grass into
that season's grass" rather than a tuned gain (CLAUDE.md).

**Why greenness gates it.** One material covers the WHOLE terrain layer,
water and sand included, so an unweighted multiply would turn the ocean and
the desert brown in autumn. `SeasonalFoliage.greenness_of` scores a pixel by
how far its green channel sits above its own red and blue; measured against
the real palette, every green biome scores ≥0.85 and every non-green one
scores exactly 0. The GLSL in `GroundTint` and `IllustratedGrassPatch` is
that same expression with `GREENNESS_GAIN` interpolated in, so the tested
GDScript and the running GLSL cannot drift apart.

## The canopy is on the clock, not on the simulation

The ground learned the season off the world clock (above) while the canopy
above it learned it off the *simulation*, and that is a category error with
two real symptoms.

`TreeRenderer.season` was an empty string, written in exactly one place:
`EarthChunkManager._sync_tree_season`, reachable only from `step_fruiting`,
reachable only from `World._process` behind `_owns_ecosystem_simulation()`
and a ~1s accumulator. So:

- **A fresh world flashes green trees.** The initial awaited chunk load spawns
  trees before that ever fires, so the first chunks are built with no season
  at all. In single-player the next fruiting tick corrects them a moment
  later, which is exactly the kind of "it fixes itself, so it must be fine"
  that hides the second symptom.
- **A joined client's forest is summer-green forever.** On a client the
  ownership gate is false, `step_fruiting` never runs at all, and every tree
  in the world wears leaf in every season for the whole session.

**Which picture a tree wears is a pure function of the world clock**, exactly
like the tint on the lawn beside it — a rendering concern, not a
simulation-ownership one. `TreeRenderer` therefore holds the *clock*, not a
season string: `set_world_age_seconds` is the only way to move it, and
`canopy_state()` derives `{season, turning_into, turn_progress}` from it —
through `TreePhenology`, the canopy's own schedule (see "Winter stays bare"
below), off the same `SeasonCycle` year fraction and the same quantiser
everything else reads. **One derivation**, so nothing can drift: the trees
about to be built, the trees already loaded, and the ones inside the fruiting
radius are all dressed from that single call. `step_fruiting` used to compute
its own answer — the calendar name plus a `SeasonTransition` call, per tree —
which was harmless only while the canopy still turned on the ground's curve;
the moment it got its own, that second schedule would have put blossom on the
handful of trees beside the player on the first day of spring and left bare
branches everywhere else.

`season` in that dictionary is a canopy KEY — which of `IllustratedTree`'s
four frames — and not a claim about the month: the first instant of spring is
still bare wood. `EarthChunkManager.current_season()` remains the calendar,
for the HUD.

**There is no unset state to fall back from.** `IllustratedTree`'s
`_FALLBACK_SEASON` ("summer") is the right answer for a genuinely
unrecognised season id — this codebase does not crash on an odd id, and an
unexpectedly green tree is a tree where an unexpectedly bare one reads as
dead. But `""` was never an unknown season; it was *nobody has said yet*, and
drawing that as high summer is precisely what let a wiring bug pass for a
healthy forest. A renderer nobody has told anything now reads the clock's own
zero — the first instant of spring, which for a canopy is full blossom, and for
the ground beside it is `SeasonalFoliage.tint_for_world_age(0.0)`: the same
moment, each read the way its own schedule reads it. The empty case is gone
upstream: `TreeRenderer` cannot be in it.

**Every path that establishes or moves the clock dresses the trees**:
`set_world_age_seconds` (so both `randomize_world_age` and `load_world_clock`
land *before* the first chunk load), `advance_world_age`, `jump_to_season`
(`/season`), and `World._client_process` once a frame beside the existing
ground-tint push — the ungated path every peer runs, host and client alike.
It is cheap: `EarthChunkManager.sync_tree_season` keeps the quantised
season/turn signature guard it already had, so a rebuild costs a handful of
canopy textures per in-game year, not one per frame.

**Known gap, named honestly:** a joining client's world clock is never
replicated in the first place — nothing calls `set_world_age_seconds` or
`advance_world_age` on a client, so its clock sits at 0 and its ground tint,
snow and canopy all read the start of spring. That is one bug in the clock
rather than four in its readers, and the canopy now shares the ground's fate
instead of having a second, worse one of its own.

**This principle is about the SEASON dimension specifically, and does not
extend to canopy snow.** Which of the four season frames a tree wears has to
be a pure function of the clock, for exactly the reasons argued above — but
*how much* of that canopy is under snow is legitimately a live SIMULATION
fact, the same way the ground's own lying snow already is (see "The ground
carries the season too" above: ground tint is clock-driven, ground snow is
simulation-driven, `SnowLayer`/`EarthChunkManager._snow_depth`, accumulated
from real weather via `Snowfall.accumulate` and forceable with `/weather`).
Canopy snow is a second overlay of that same kind, layered on the canopy
instead of the ground beneath it, pushed through the same forwarding shape
`set_wind_strength` already uses (`TreeRenderer.set_snow_coverage`) — not a
fifth phenology stage `TreePhenology` needs to know about. Full spec, with
the measured sheet facts, in [flora.md](flora.md)'s "A fifth frame: snow is
not a season".

## Winter stays bare: the canopy has its own phenology

Reported from a world that started in **winter**: pink cherry blossom and
green leafy crowns standing in a frozen world — *"not all trees render their
winter sprites???"*.

Nothing was mis-mapped and nothing had regressed. `IllustratedTree`'s table is
right (bare is winter, blossom is spring, leaf is summer, turning is autumn),
and every file on the season-to-canopy path was blob-identical from before the
session that reported it. What the player was seeing was `SeasonTransition`
working exactly as written: `TURN_FRACTION` is 0.34, so **the last third of
every season already reports `{from: winter, to: spring}`** while
`SeasonCycle.season_at` — and therefore the HUD — still says *Winter*. A third
of winter was, by design, spent turning into spring.

**Why it read even earlier than the progress number says.** The ground
expresses a turn as a **colour lerp**; a canopy expresses it as **pixel
replacement** between frames of very different density. Measured off the
shipped sheets (pixels with alpha > 0.5):

| cherry canopy frame | opaque px | mean RGB |
| --- | --- | --- |
| bare | 62,512 | (114, 47, 15) — brown |
| blossom | 157,928 | (165, 92, 85) — **pink** |
| leaf | 176,097 | (71, 86, 9) |
| turning | 130,762 | (156, 52, 8) |

Blossom carries **2.5×** the pixels of bare, so at one step of six a cherry has
already had a sixth of a much denser, much pinker picture painted over it and
reads as *in blossom* long before the number reaches half. A lawn one step of
six toward spring is imperceptible. The same progress does not mean the same
thing to the two, which is why they can no longer share one schedule.

**The fix is phenology, not blend rate.** A real cherry does not fade from bare
to pink across the back third of winter. It stands bare all winter, flowers on
bare branches for about a fortnight in early spring, and leafs out after.
`src/world/tree_phenology.gd` is that schedule, and it is the only thing that
decides which canopy a tree wears.

**The canopy walks four stages in a fixed order and never skips one:**
bare → blossom → leaf → turning → bare. `TreePhenology.canopy_position_at`
places a moment in the year on that cycle as ONE monotone number in `[0, 4)`
— the integer part is the stage a tree is on, the fraction is how far into the
change to the next. `canopy_state_at` splits it back into the
`{from, to, progress}` shape the renderer already consumes, with progress put
through **`SeasonTransition.quantise`** — the same six steps the ground turns
on, so a wood still turns branch by branch and nothing new can snap.

The stage order is deliberately the SHEET order (`IllustratedTree.CANOPY_BARE`
= 0 … `CANOPY_TURNING` = 3), so a stage index and a canopy frame index are the
same number. Pinned by test, since it is otherwise exactly the kind of
coincidence that silently rots.

The schedule, season by season:

- **Winter — bare, until its last hours.** Position pinned at 0 for all but
  the final `OPENING_FRACTION` of the season; that last sliver runs the
  bud-break ramp out of bare and into blossom, finishing exactly *on* the
  winter/spring boundary. *(This bullet formerly read "bare, end to end", with
  winter's pre-turn **suppressed** outright — see "Spring has to start in
  spring" below for the live report that reversed it, and for why the ramp is
  the short measured one rather than `TURN_FRACTION`.)*
- **Early spring — full bloom, held, then leaf.** The opening ramp already
  finished, so spring *opens* in full blossom and holds it for
  `FULL_BLOOM_FRACTION`. The winter/spring boundary is still a gradual
  quantised six-step change and not a hard swap; it now completes on the
  boundary instead of starting there.
- **Spring, after that — leaf.** Blossom gives way to leaf across
  `LEAF_OUT_FRACTION`, measured from the end of the hold, (again six quantised steps), and the rest of spring is
  settled leaf. Spring's own last third, which used to be the blossom→leaf
  turn, is now leaf→leaf and does nothing.
- **Summer and autumn — unchanged.** Both ride `SeasonTransition.TURN_FRACTION`
  exactly as before: settled for two thirds, turning across the last. In those
  two seasons `TreePhenology` and `SeasonTransition` report the same progress,
  pinned by test.

**How long "brief" is, and where the number comes from.** Not chosen. Real
*Prunus* bloom records, in real days: bud break to full bloom ≈ **5**, full
bloom held to petal fall ≈ **7**, petal fall to full leaf ≈ **14**, against an
astronomical spring (equinox to solstice) of ≈ **92**. Those four figures are
the constants; every fraction in the module is derived from them, so the
schedule cannot be nudged without changing a claim about a real tree. A
`SeasonCycle` year is 48 in-game days, so a season is 12, and blossom is
visible at all (opening + hold = 12 of 92 real days) for **1.57 in-game days —
13% of a season**, against the 34% an ordinary season turn occupies. (It now
straddles the winter/spring boundary rather than sitting wholly inside spring
— see "Spring has to start in spring" — but the span itself is unchanged,
which is the property that matters here.) Blossom is
the briefest seasonal change in the game, which is what makes it an event
rather than a wallpaper.

**The lawn and the crown may now disagree about the month, and that is the
point.** "The ground carries the season too" above argues they must never
disagree — that argument was about the *clock*, and they still share it: one
`year_fraction`, one quantiser, one set of season names. What they no longer
share is the *curve*, because a colour lerp and a frame replacement do not
express the same progress the same way (see the density table). Grass greens
smoothly through late winter; the trees hold off until winter's last hours and
then open onto spring, which is close to what both actually do.

**What the other species do.** The blossom slot is only a flowering event for
cherry. Measured the same way, the nut and orchard sheets draw it as the
yellow-green flush of a bursting bud — walnut goes bare (31,867 px, brown)
→ blossom slot (68,026 px, olive (119, 107, 15)) → leaf (91,372 px, green);
apple and acorn and hazelnut do the same. Read as *new leaf* rather than as
flowers, an early-spring window is if anything more correct for them than the
whole-of-spring window they had before.

**Pine is unaffected, and it is unaffected because of its art.** Pine is an
evergreen (`TreeSpecies`: "its canopy never goes bare") and its sheet honours
that: its bare-slot frame is 84,752 opaque px against 101,514 in leaf — 84% of
its foliage still there — in a grey-green (95, 105, 102) rather than brown
branches. It walks the same four stages, but for pine those stages are four
tones of conifer, so moving *when* they happen changes nothing visible about
it. Pinned by test in `test_illustrated_tree.gd` so a re-drawn pine sheet that
went genuinely bare would be caught.

### Spring has to start in spring

Reported live, from a world where `/season spring` had just been typed: the HUD
read **Spring · Cloudy** over bare brown branches and snow-capped pines —
*"the trees show a winter sprite when I do /season spring"*.

Not a regression, and not a mis-mapping: it was the **suppressed pre-turn**
above, working as written. `/season` skips the clock to the *first instant* of
the season it names (`World._handle_season_command` →
`EarthChunkManager.jump_to_season`), and with winter pinned at stage 0 for its
whole length, spring's first instant selected the bare frame. The tree would
not open for another `OPENING_FRACTION` of spring.

That made the winter→spring seam **the one season start in the year that
arrived unsaturated**, breaking the rule `SeasonTransition` states in its own
header — a wood should *"be fully turned by the time the season it is turning
into actually starts"*. Every other seam already obeyed it: autumn's last third
turns the canopy bare, so winter begins bare; summer's turns it to autumn.

**The fix moves the ramp rather than lengthening it.** Bud break now runs
against the **end of winter** instead of the start of spring, so it finishes
exactly on the boundary and spring opens in full bloom. Nothing about how long
a tree carries blossom changed: it is still `OPENING_FRACTION +
FULL_BLOOM_FRACTION`, the same measured 5 + 7 real days, still a little over an
in-game day and a half — the window merely sits early enough to *peak* at the
boundary rather than starting there.

**Why not simply give the canopy `TURN_FRACTION` back**, the way summer and
autumn have it? Because that is the version this whole section exists to
prevent. A third of winter ramping toward blossom is ~4 in-game days of
visibly pink trees standing in snow — the original report — and, since blossom
carries 2.5× the opaque pixels of bare wood, it reads as arrived long before
its progress number does. It would also stretch total blossom to roughly 5
in-game days, three times the real bloom record the constants are derived from,
which stops it being an event. The short ramp buys the saturated season start
at ~0.65 in-game days of early pink, and costs no extra cached images.

## Status / mechanisms

- ✅ Season cycle model (season + warmth/growth modifiers) — `src/world/season_cycle.gd`, tested.
- ✅ Canopy phenology — winter bare but for its last hours, blossom a brief
  event straddling the winter/spring boundary that gives way to leaf — `src/world/tree_phenology.gd`, tested
  (`tests/unit/test_tree_phenology.gd`). Pure; shares `SeasonTransition`'s
  quantiser and its summer/autumn turn window, and replaces
  `SeasonTransition.state_at` **for canopies only** — the ground tint still
  reads `SeasonTransition` directly. See "Winter stays bare: the canopy has
  its own phenology".
- ✅ Seasonal forcing of fruit phenology (season warmth scales `FruitingModel`) —
  wired in `EarthChunkManager._warmth_at_pixel`/`step_fruiting`.
- ✅ Season + current weather shown in the HUD (reuses the existing
  `weather_model.gd`; `EarthChunkManager.current_season`/`current_weather`,
  rendered in `World`'s debug readout as "Season · Weather").
- ✅ A new world starts at a random point in the year, a loaded one resumes
  its own — `EarthChunkManager.randomize_world_age`/`set_world_age_seconds`/
  `save_world_clock`/`load_world_clock`/`wipe_world_clock`,
  `WorldClockPersistence`, tested; wired at `World._wipe_persisted_world`
  (New Game) and `_spawn_local_singleplayer_from_save` (Load Game). See "A
  new world starts at a random point in the year" above.
- ✅ Seasonal tint on living green — the terrain ground cover and the
  illustrated tall grass — `src/rendering/seasonal_foliage.gd`, applied via
  `GroundTint.set_season_tint` / `IllustratedGrassPatch.set_season_tint`,
  tested. Appearance only: no growth RATE changed with it (see below), and
  no terrain art is per-season. See "The ground carries the season too".
  The SENDING half now exists too, which is what makes it visible while
  playing: `EarthChunkManager.set_season_tint` fans the live value onto
  every green thing the manager owns (the same shape as its
  `set_wind_strength`/`set_sun_position` setters), and
  `World._client_process` pushes
  `SeasonalFoliage.tint_for_world_age(world_age_seconds())` into both the
  ground material and that fan-out once a frame, beside the existing
  `set_sun_position` call — so the lawn and the canopy read the same world
  clock and cannot disagree about the month. The wiring, not the tint, is
  pinned by `tests/unit/test_world_season_fanout.gd`; it was recorded as 🚧
  for as long as the setters had no caller, because green unit tests on a
  setter nothing invokes are the same class of bug as `step_wild_crops`
  below.
- ✅ Seasonal scaling of WILD CROP growth and spread —
  `WildCropPatch.advance(delta, season_growth)` reads
  `SeasonCycle.growth_modifier`, and `WildCropMarker.season_tint` puts the
  same foliage tint on a crop's leaves (never on the pulled root). See
  [wild_crops.md](wild_crops.md)'s "The season". `EarthChunkManager
  .step_wild_crops` now computes `growth_modifier(_world_age_seconds)` once
  per batched tick and passes it into `advance`, and hands its stored
  `_season_tint` to both `sync_markers` and `spawn_markers` — so a chunk
  streamed in during winter arrives dead-topped rather than popping in
  summer-green. `step_wild_crops` itself is called from
  `World._step_ecology_batch` now, which is what made any of it observable
  (see [wild_crops.md](wild_crops.md)'s Status). Pinned by the
  `wild_crops_in_season` tests in `test_earth_chunk_manager.gd`.
- ✅ The canopy season reaches the trees off the world clock, not off the
  simulation tick, and through exactly one derivation
  (`TreePhenology`, consumed in `TreeRenderer.canopy_state` and handed on
  from there to the loaded trees and to `step_fruiting`'s redraw) —
  `TreeRenderer.set_world_age_seconds`/`canopy_state`,
  `EarthChunkManager.sync_tree_season` called from `set_world_age_seconds`/
  `advance_world_age`/`jump_to_season`, plus `World._client_process`'s
  once-a-frame push beside the ground tint. Pinned by
  `tests/unit/test_tree_renderer.gd` (the derivation, and that an un-pushed
  renderer is not summer) and `tests/unit/test_world_season_fanout.gd` (the
  wiring, as the running game gets it). See "The canopy is on the clock, not
  on the simulation".
- 🚧 The world clock itself is not replicated to joining clients — no path
  calls `set_world_age_seconds`/`advance_world_age` on a client, so every
  clock reader there (canopy, ground tint, snow, weather) reads world age 0.
  Single-player and the hosting peer are correct; a joined client is
  consistently wrong rather than inconsistently wrong. See the "Known gap"
  paragraph above.
- ⬜ Seasonal scaling of vegetation/tall-grass growth rate — still
  season-independent (`TallGrass.GROWTH_RATE` is a flat per-second
  constant). Deliberately left: the tall-grass work in this pass was a
  rendering fix, and a rendering fix must not smuggle a sim change in with
  it.
- ⬜ Seasonal crop viability for player-tilled FARMING (see
  [farming.md](farming.md)) — entirely unbuilt. The WILD crop population is
  done (above); the two are separate systems.
- ⬜ Disaster events (drought/flood/wildfire) perturbing the season baseline
  (see [weather.md](weather.md)).

## Skipping to a season (`/season`)

**A season jump moves the clock FORWARD, never back.** Season is a pure
function of elapsed world time, so the obvious way to honour `/season winter`
is to set the clock to winter. But every other system measures itself against
that same clock: a tree records the age it was planted at, fruiting records the
time it last ran. Winding the clock back gives a tree a negative age and hands
the fruit model a span that runs backwards. Forward is the only move that
leaves every other clock consistent — so asking for the season you are already
in waits for it to come round again rather than doing nothing. You asked to
watch it start.

**The skipped time is not replayed.** The jump is up to a whole year, and
fruiting counts what fell between the last time it ran and now. Moving the
clock without moving that mark would empty every nearby canopy onto the ground
in a single step — a year's windfall at once. The fruiting mark moves with the
clock. Trees are deliberately *not* caught up the same way: a sapling really
has aged while you skipped past, and seeing it older is the point of the
command.

**An optional second argument, `/season <name> <progress>`, lands partway
through the named season instead of always at its very start.** `progress` is
a fraction from `0.0` (the default — identical to omitting it) to `1.0`,
which by construction lands at exactly the same instant as `<next season>`'s
own `0.0` — the two boundaries share a point. `/season autumn 0.5`, for
example, lands at autumn's midpoint. Console input is validated rather than
silently reinterpreted: a non-numeric second argument, or a number outside
`[0, 1]` (someone typing `50` meaning "50%" where a `0-1` fraction was
wanted), is refused with a reason instead of quietly landing somewhere other
than what was asked for. `SeasonCycle.seconds_until_season` itself clamps any
out-of-range float defensively underneath — a second, pure-model line of
defense for any caller other than the console — but the command layer's own
refusal is what a player actually sees.
