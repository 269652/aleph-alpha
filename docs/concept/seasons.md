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

## Status / mechanisms

- ✅ Season cycle model (season + warmth/growth modifiers) — `src/world/season_cycle.gd`, tested.
- ✅ Seasonal forcing of fruit phenology (season warmth scales `FruitingModel`) —
  wired in `EarthChunkManager._warmth_at_pixel`/`step_fruiting`.
- ✅ Season + current weather shown in the HUD (reuses the existing
  `weather_model.gd`; `EarthChunkManager.current_season`/`current_weather`,
  rendered in `World`'s debug readout as "Season · Weather").
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
