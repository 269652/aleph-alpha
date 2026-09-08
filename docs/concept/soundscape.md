## Ambient nature soundscape

[world.md](world.md) and [weather.md](weather.md) already give the world a real
biome, a real season, a real day/night clock, and real simulated weather —
today none of it is audible. This specifies a real ambient audio system built
entirely on those existing, already-tested state sources rather than a second,
independent audio-only model of the world.

## Design pillars

1. **Reuse the world's own state, never re-derive it.** Biome, season,
   weather, day/night and "is it actually snowing" are already computed
   exactly once elsewhere ([biome_classifier.gd](../../src/world/biome_classifier.gd),
   `SeasonCycle`, `WeatherModel`, `SolarPosition`, `EarthChunkManager.is_snowing`).
   This system takes them as plain inputs — the same "caller does the
   real-world computation, this module only decides" split
   `KrakenTrigger`/`EasterEggSightings` already use for `is_night` — so audio
   can never disagree with what the player sees falling from the sky or the
   HUD's own season label.
2. **Layered composition, not a lookup table per combination.** 7 biomes ×
   4 seasons × 4 weather states × day/night is 224 combinations; there is no
   world where that many bespoke recordings exist. Independent layers — a
   biome bed, a night overlay, a weather overlay, an occasional accent
   one-shot — mix together, so every combination gets an appropriate sound
   from a small, real asset set (11 files today; see
   `assets/audio/soundscape/CREDITS.md`).
3. **Real-world grounding decides which combinations need a DIFFERENT layer
   and which don't**, rather than uniform coverage for its own sake — see
   below. Two biomes sounding the same in some season isn't a gap; it's
   correct when the real habitats actually do.
4. **Smooth, never a hard cut.** A layer's volume ramps toward its target
   rather than snapping — the same "nothing here pops or snaps" discipline
   [flora.md](flora.md#a-fifth-frame-snow-is-not-a-season)'s canopy-snow
   crossfade and the river-drift wrap-crossfade already hold visuals to,
   just applied to loudness instead of pixels.

## Real-world grounding for the layer rules

- **Tropical forests are not strongly seasonal.** Near the equator, day
  length and temperature barely swing across the year, so the insect/frog
  chorus that defines a rainforest's soundscape runs year-round rather than
  falling silent in "winter" the way a temperate forest's breeding-season
  bird chorus does. Rainforest deliberately does **not** get a winter-specific
  bed; forest (temperate) does.
- **A temperate forest's bird chorus is a breeding-season phenomenon.**
  Loudest in spring/summer, tapering through autumn, largely silent in
  winter (most songbirds stop territorial singing once breeding is over) —
  real basis for swapping to a dedicated winter recording rather than just
  a quieter version of the same one.
- **Raptors are diurnal.** A hawk cry at night would be wrong, not
  atmospheric — `mountain_hawk_call` is gated to daytime only, mirroring how
  [ecosystem_dynamics.md](ecosystem_dynamics.md)'s own nocturnal/diurnal
  splits (e.g. owls vs. songbirds) already work.
- **"It snows when it is cold, not when the calendar says winter"**
  ([weather.md](weather.md#snow)) — audio follows the exact same rule
  `RainOverlay` already does: a storm that is actually cold gets the wind/
  blizzard read, not rain-and-thunder, using the same `is_snowing()` this
  project already computes once per step.
- **Open, sparse biomes (desert, tundra, high mountain) are defined more by
  the ABSENCE of a bird/insect bed than by a unique wind recording** — the
  real acoustic difference between a windy desert and a windy mountainside
  is context (what ISN'T there), not the wind itself. One wind recording,
  scaled by biome, real-world-honestly stands in for all three rather than
  three separately-sourced "wind but slightly different" files.

## Mechanism

### Layer registry

`src/audio/nature_soundscape.gd` (`extends RefCounted`, no scene/node
dependency — unit-testable the same way as `KrakenTrigger`) owns a flat
`LAYERS: Dictionary` of `layer_name -> res://assets/audio/soundscape/*` paths,
one entry per file in `CREDITS.md`.

### `layer_mix(biome, season, weather, is_night, is_snowing) -> Dictionary`

Pure function: given today's real world state (all plain `String`/`bool`
inputs, no coupling to `EarthChunkManager`), returns `{layer_name: volume}`
for every layer that should currently be audible — omitted entirely rather
than listed at `0.0` for anything that shouldn't play, so a caller can
crossfade toward exactly this set and stop everything else.

**Biome bed** (exactly one, always present unless overridden below):

| Biome | Day | Night | Season effect |
|---|---|---|---|
| ocean | `ocean` | `ocean` (unchanged) | none — waves don't follow the calendar |
| forest | `forest_day` | `temperate_night` replaces it | `forest_winter` replaces `forest_day` in winter (real dedicated recording) |
| grassland | `grassland_day` | `temperate_night` replaces it | winter multiplies its volume by `GRASSLAND_WINTER_VOLUME` (0.2) rather than swapping files — real crickets/bumblebees, no dedicated winter recording sourced yet |
| rainforest | `rainforest_day` | `rainforest_night` replaces it | none (see grounding above) |
| desert | `wind` × `DESERT_WIND_VOLUME` (0.7) | same | none |
| tundra | `wind` × `TUNDRA_WIND_VOLUME` (1.0) | same | none |
| mountain | `wind` × `MOUNTAIN_WIND_VOLUME` (0.85) | same | none (see hawk accent below) |

**Weather overlay** (additive on top of the biome bed, independent of it):

| Weather | Overlay | Volume |
|---|---|---|
| clear | none | — |
| cloudy | none | — |
| rain | `rain` | `RAIN_OVERLAY_VOLUME` (0.7) |
| storm, not `is_snowing` | `storm` | `STORM_OVERLAY_VOLUME` (0.9) |
| storm, `is_snowing` | `wind` (blizzard read) | `STORM_OVERLAY_VOLUME` (0.9) — reuses the wind bed rather than a 12th file, since a blizzard IS wind |

### `hawk_call_eligible(biome, is_night) -> bool` / `check_hawk_call(biome, is_night, roll) -> bool`

Same `is_eligible`/`check` split as `KrakenTrigger`: `mountain_hawk_call` is
an occasional one-shot, not a bed, gated to `biome == "mountain" and not
is_night` (see grounding above), then a `roll < HAWK_CALL_CHANCE_PER_CHECK`
draw exactly like every other `chance_per_check`-gated cameo in this project
family.

### Playback (`src/rendering/nature_soundscape_player.gd`)

A `Node` owning one `AudioStreamPlayer` per `LAYERS` entry (looping for beds/
overlays, one-shot for the hawk call), refreshed on the same periodic cadence
as other world-scale ambient state (not per-frame — nothing here needs
sub-second reaction). Each step:

1. Compute `dominant_biome`, `current_season()`, `current_weather(player_pixel)`,
   `is_night` (`SolarPosition.elevation_degrees(...) <= 0.0`, the exact
   existing convention), `is_snowing()` — all already-live `EarthChunkManager`/
   `World` state, none re-derived.
2. Call `layer_mix(...)` for the target mix.
3. Ramp every active `AudioStreamPlayer`'s volume toward its target and every
   inactive one toward silence (then stop it), rather than snapping — pillar 4.
4. Roll `check_hawk_call` once per refresh and fire the one-shot player if it
   hits.

## Status

- 🚧 **v1: the pure `layer_mix` mixing logic, the layer registry, and 11 real
  licensed recordings** (`assets/audio/soundscape/`, see `CREDITS.md` for
  attribution) covering all 7 biomes, day/night, all 4 weather states, and one
  genuine seasonal variant (forest winter). Season for the other 6 biomes is
  mixing-rule modulation, not 24 additional bespoke recordings (see pillar 2).
- ⬜ **`NatureSoundscapePlayer` wired into `scenes/world.gd`** — the pure logic
  above is designed for this from day one, but instancing it into the actual
  running scene, hooking the periodic refresh cadence, and an audio bus /
  master-volume-slider settings hook are separate, deliberately not bundled
  into the same pass as the design + asset research.
- ⬜ **Proximity layers** (running water near a river/lake, per
  [hydrology_field.gd](../../src/world/hydrology_field.gd)) — a real, already-
  named future extension, not built here to keep this pass's asset list from
  growing past what was actually researched and licensed.
- ⬜ **Dedicated desert/tundra recordings** — both currently share one `wind`
  bed at different volumes (see grounding above); a real desert-specific
  recording (sand hiss, distinct insect) would be a genuine upgrade if
  sourced later, not a gap in the mixing logic itself.
- ⬜ **A settings volume slider / mute** — `AudioServer` bus wiring for this
  system specifically; today the only volume control is per-layer inside
  `layer_mix`'s own constants.
