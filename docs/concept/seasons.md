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

## Status / mechanisms

- ✅ Season cycle model (season + warmth/growth modifiers) — `src/world/season_cycle.gd`, tested.
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
