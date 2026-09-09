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

### Proximity layer: `river` (2026-09-09)

Requested live, following straight on from "compose the sound from what's
actually around you": *"fully build the soundscape out of individual
nearby animals and environment please."* [creature_and_footstep_audio.md](creature_and_footstep_audio.md)
already made creature CALLS genuinely proximity-based; this is the
"environment" half of the same ask.

`layer_mix` gained an optional `water_distance_tiles` parameter
(defaulting to `INF` — every pre-existing 5-arg call site keeps its exact
prior behavior). `EarthChunkManager.nearest_water_distance_tiles(global_x,
global_y)` supplies the real fact: a ring-by-ring scan (pure geometry,
[water_proximity.gd](../../src/world/water_proximity.gd), tested against
synthetic coordinates rather than unpredictable real generated terrain)
out to `WATER_PROXIMITY_SCAN_RADIUS_TILES` (24 tiles, ~34 real metres —
the same order of magnitude as `CreatureCallSound.AUDIBLE_RADIUS_PX`'s own
~35m "nearby" scope for creature calls), reusing the exact
`is_river_at_global`/`is_lake_at_global` predicates `record_footstep`'s
own underwater check already calls — never a second, independently
invented water check.

`RIVER_LAYER` (`river.ogg`, a real flowing-stream field recording, see
`assets/audio/soundscape/CREDITS.md`) ramps linearly from
`RIVER_OVERLAY_MAX_VOLUME` at distance 0 to silent at
`RIVER_AUDIBLE_RADIUS_TILES`, additive on top of whatever biome bed/
weather overlay already apply — the same "never clobbers, only adds"
shape `_add_weather_overlay` already established. Deliberately NOT part
of `NatureSoundscapePlayer`'s "did a real input change?" immediate-
recompute comparison (see that file's own `update()` doc comment): unlike
biome/season/weather, a real distance to water changes continuously while
walking, and folding it into that comparison would defeat the throttle
entirely near any water. It still refreshes on the same regular cadence
as everything else, with `_advance_ramp`'s own per-frame (never
throttled) smoothing keeping the audible volume climbing/falling
continuously in between.

TDD throughout: `water_proximity.gd`'s ring-scan geometry (6 tests against
synthetic coordinates — standing on water, an adjacent tile, a real 3-4-5
Euclidean triangle not a taxicab count, several candidates picking the
nearest, nothing within radius, a hit exactly at the radius edge);
`EarthChunkManager.nearest_water_distance_tiles`'s wiring (cross-checked
against a manual scan using the same real predicates, since a river/lake
at any SPECIFIC coordinate isn't guaranteed by real generated terrain);
`layer_mix`'s own river-overlay math (6 new tests: omitted parameter adds
nothing, full volume at zero distance, half volume at half radius, gone
at/beyond the radius, coexists with bed+weather); `NatureSoundscapePlayer`
passthrough (3 tests using real `AudioStreamPlayer.playing`/`volume_db`);
and a new `test_world_nature_soundscape_fanout.gd` source-text assertion
that `_client_process` actually passes the real distance through.
`test_water_proximity.gd` 6/6, `test_earth_chunk_manager_water_proximity.gd`
2/2, `test_nature_soundscape.gd` 35/35, `test_nature_soundscape_player.gd`
18/18, `test_world_nature_soundscape_fanout.gd` 6/6.

**Not attempted here:** the linear volume ramp is a real, deliberate
compromise (see `_add_river_overlay`'s own doc comment), not a genuine
perceptual-loudness curve; the ring-scan's own known, accepted Euclidean
imprecision at certain ring boundaries (see `water_proximity.gd`'s own doc
comment — never matters for a smooth ambient ramp over dozens of tiles);
and `ocean.ogg`'s own rough loop seam (a raw field recording, would need
real audio-editing tooling this environment doesn't have) is unrelated
and still unfixed.

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

- ✅ **The pure `layer_mix` mixing logic, the layer registry, and 11 real
  licensed recordings** (`assets/audio/soundscape/`, see `CREDITS.md` for
  attribution) covering all 7 biomes, day/night, all 4 weather states, and one
  genuine seasonal variant (forest winter). Season for the other 6 biomes is
  mixing-rule modulation, not 24 additional bespoke recordings (see pillar 2).
- ✅ **`NatureSoundscapePlayer` wired into `scenes/world.gd`** — built once in
  `_ready()` (`add_child(_nature_soundscape.build())`), fed real state every
  `_client_process` frame (the player's own real `biome_at_global` tile, the
  same real sun-elevation `is_night` and `raw_weather`/`snowing` every other
  system this frame already reacts to — see `test_world_nature_soundscape_
  fanout.gd`). Ambient sound now actually plays while the game runs, not just
  in `test_nature_soundscape_player.gd`.
- ✅ **A master volume slider, Settings > Audio** — `AudioSettings.
  sanitize_volume`/`volume_to_bus_db` (TDD), applied to the whole game's
  `Master` bus (`AudioServer.set_bus_volume_db`) rather than scaled per-layer,
  since the control belongs to the player's ears, not to any one system that
  happens to make noise. Persists alongside key bindings/graphics.
- **"I can't hear any sounds" (2026-09-08), investigated and root-caused: not
  a code bug.** A real `--solo` session, instrumented with a temporary
  flushed-file diagnostic (removed after use), showed `forest_day` correctly
  detected, ramped to `volume_db: 0.0` (full unity gain) and `playing: true`
  within the first refresh cycle, and staying that way for the rest of the
  session — a real WASAPI driver connected to the "Default" output device,
  `Master` bus at `0.0`dB, not muted. Every layer of this system, from biome
  detection through the actual `AudioStreamPlayer` state, is provably correct.
  If sound still isn't audible, the remaining candidates are outside this
  system's control: Windows' actual default playback device (is it the
  speakers/headphones actually in use?), the per-application entry for this
  game's `.exe` in the Windows Volume Mixer (a persisted, per-executable
  setting independent of the game's own bus), or the system volume itself.
- ✅ **Revised (2026-09-09): a real river/lake-proximity layer.** A new
  `river` overlay ramps in as the player nears real water (`EarthChunkManager.
  nearest_water_distance_tiles`, a ring-scan out to ~34 real metres), fading
  linearly to silent beyond that — see "Proximity layer: `river`" above for
  the full mechanism and TDD coverage.
- ⬜ **Dedicated desert/tundra recordings** — both currently share one `wind`
  bed at different volumes (see grounding above); a real desert-specific
  recording (sand hiss, distinct insect) would be a genuine upgrade if
  sourced later, not a gap in the mixing logic itself.
- ⬜ **A settings volume slider / mute** — `AudioServer` bus wiring for this
  system specifically; today the only volume control is per-layer inside
  `layer_mix`'s own constants.
- ✅ **Revised (2026-09-09): a real transition (biome, weather, season,
  day/night) now refreshes the target mix immediately** instead of
  waiting out the full `REFRESH_INTERVAL_SECONDS` throttle first —
  reported live as "it takes a while before the sound is played... then
  it fades out and takes a while again," up to ~10 real seconds of
  latency on ANY discrete transition. Water specifically also got its own
  dedicated proximity layer in a later pass — see "Proximity layer:
  `river`" above. See [creature_and_footstep_audio.md](creature_and_footstep_audio.md#a-real-separate-ambient-audio-responsiveness-fix-same-pass)
  for the full diagnosis and fix behind this bullet.
- **"Compose the sound from what's actually around you"** — reported
  live: ambient beds are decorative field recordings with birds baked in,
  independent of the real simulated bird population nearby. Real, direct
  progress since: proximity-gated creature calls (see
  [creature_and_footstep_audio.md](creature_and_footstep_audio.md#compose-the-sound-from-whats-actually-around-you))
  and the `river` proximity layer above both compose real, live nearby
  state into what's heard. ⬜ Still not attempted: re-architecting the
  BEDS themselves (`forest_day.mp3` etc.) to scale with real nearby
  population counts — would need re-recording or real audio-editing
  tooling neither available here — see
  [creature_and_footstep_audio.md](creature_and_footstep_audio.md#compose-the-sound-from-whats-actually-around-you)
  for the real, if partial, step taken instead (real per-creature calls,
  a separate system from this file's own ambient beds).
