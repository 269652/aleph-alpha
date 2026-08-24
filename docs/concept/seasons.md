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
3. **One clock, many readers.** Fruiting, vegetation growth, weather, and survival
   exposure all read the one season value, the same way loaded and unloaded chunks
   share one population model — "two fidelities, one truth" applied to time.

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
- ⬜ Seasonal scaling of vegetation/tall-grass growth rate.
- ⬜ Seasonal crop viability for farming (see [farming.md](farming.md)).
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
