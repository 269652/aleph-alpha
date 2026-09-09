# Footstep, Mushroom-Crush, and Creature-Call SFX

Reported live: *"The soundscape needs great improvement we need footsteps;
twigs cracking in forest wood; walking over a mushroom should produce a
correct sound... each animal should have an individual sound.. (horse,
robin, boar, sparrow) etc... can you download more sounds and make it
better?"* This is the sibling system to [soundscape.md](soundscape.md)'s
ambient beds: discrete, event-triggered ONE-SHOT SFX (a footstep, a crush,
a call) rather than a continuous looping mix.

## Design pillars

1. **Reuse the world's own real events, never re-derive them.** A footstep
   sound rides the exact same per-step event `FootstepGait`/
   `EarthChunkManager.record_footstep` already fire for the visual
   footprint sprite -- not a second, parallel gait/distance accumulator.
   Same "caller does the real-world computation, this module only
   decides" split every other system in this codebase already uses.
2. **Real-world grounding decides who gets a sound, not uniform
   coverage.** The same pillar [soundscape.md](soundscape.md) already
   states for ambient layers applies here: ants, decomposer bugs,
   millipedes, caterpillars, earthworms, fish, and butterflies are all
   inaudible to a nearby human in reality, so none of them get a
   fabricated call. A genuinely unsourceable sound (see "Mushroom crush"
   below) stays an honest, named gap rather than a mismatched stand-in.
3. **Ship what's actually sourced and licensed, flag the rest.** Mirrors
   `soundscape.md`'s own status-list honesty: partial species/surface
   coverage is the norm for a first pass, not a defect to hide. A species
   or surface with nothing sourced yet is silent, not broken.
4. **Audio depends on world state; world state never depends on audio.**
   `EarthChunkManager`/`CreatureMarker`/`AmbientFlyerMarker` (world
   simulation) must never import or call into `FootstepSound`/
   `CreatureCallSound`/`InteractionSfxPlayer` (audio) -- that dependency
   only ever runs the other way, exactly how `NatureSoundscapePlayer`
   already reads real world state rather than the world reading audio
   state. `EarthChunkManager.record_footstep` returns plain biome/snow/
   underwater facts, not an audio surface key, specifically to hold this
   line.

## Real-world grounding

- **A footstep sounds different on different ground**, and Wikimedia
  Commons (this project's established audio source, see
  `assets/audio/soundscape/CREDITS.md`) turned out to be rich in longer
  nature/wildlife field recordings but thin on isolated Foley-style
  "footstep on X" clips. Real, licensed recordings exist for snow and for
  a real forest-floor walk (audibly including twigs/undergrowth); no
  equally distinct one was found for grass/sand/rock/underwater despite a
  real search effort -- see "Footsteps" below for how that gap is handled
  without inventing a fake recording.
- **A mushroom crushed underfoot is a real, distinct event** (see
  `docs/concept/mushrooms.md`'s `CrushMechanic`), but no genuine squish/
  splat recording turned up on Commons either -- left honestly silent
  (see "Mushroom crush" below) rather than reached for a mismatched
  stand-in (a knife-chop, a door-chime).
- **Which animals get a call is a biology question, not a completeness
  checklist.** Every species that got a real recording here genuinely
  vocalizes; every species left out (insects, fish, butterflies) genuinely
  doesn't, at a range a nearby player would hear.
- **A real boar/pig substitution, named, not hidden.** Wild boar and
  domestic pig are the same species (*Sus scrofa*); a clean domestic pig
  grunt stands in for the wild boar call this project doesn't have an
  isolated recording of. See `assets/audio/creatures/CREDITS.md`.

## Mechanism

### Footsteps

`src/audio/footstep_sound.gd` (pure, no Node dependency) owns the surface
classification and clip lookup:

- `surface_for(biome, snow_lying, underwater) -> String` -- reuses the
  SAME real inputs `EarthChunkManager.footstep_surface_for` already
  computes for the visual footprint, but with WIDER coverage: every biome
  maps to something (falling back to `"default"`), not just the 4 the
  footprint sprite has art for. Priority mirrors that function's own
  (snow, then underwater, then biome) for intuitive consistency even
  though the two functions' surface SETS differ on purpose.
- `clip_path_for(surface) -> String` -- `"snow"` and `"forest"` get their
  own real recordings; everything else (including an unrecognized
  surface) falls back to one shared, genuine walking recording
  (`default.ogg`) rather than silence -- the same "reuse where a distinct
  recording isn't available" shape `NatureSoundscape`'s own wind bed
  already established for desert/tundra/mountain.

`EarthChunkManager.record_footstep` returns `{"side", "biome",
"snow_lying", "underwater"}` (empty `Dictionary` when no real step landed
this call) instead of `void` -- the raw facts behind a step, computed even
when the biome has no VISUAL footprint art, so audio's wider coverage
isn't silently capped by the footprint sprite's narrower one.
`World._client_process` feeds those facts through `FootstepSound.
surface_for` and triggers `InteractionSfxPlayer.play_footstep`.

### Mushroom crush

`FootstepSound.MUSHROOM_CRUSH_CLIP_PATH` is an honest empty string today
-- no genuine recording sourced (see "Real-world grounding" above).
`World._client_process` still calls `InteractionSfxPlayer.
play_mushroom_crush()` in the same branch that already applies the Karma
penalty for `_chunk_manager.crush_mushroom_at(...)`, so the wiring is
real and complete; it is simply a silent no-op (`InteractionSfxPlayer`
skips an empty clip path cleanly) until a real recording -- or a session
with real audio-editing tooling to cut one down from a longer source --
turns up.

### Creature calls

`src/audio/creature_call_sound.gd` (pure) owns a flat `species -> clip
path` table and a chance-per-check gate:

- `has_call`/`clip_path_for` -- a species with nothing sourced yet
  returns `false`/`""`; never an error.
- `check_call(species, roll) -> bool` -- `roll < CALL_CHANCE_PER_CHECK`
  (0.01), but only for a species that has_call at all -- the same
  `is_eligible`/`check` split `KrakenTrigger`/`NatureSoundscape`'s own
  hawk-call cameo already use.

`World._maybe_play_creature_calls` (throttled by
`CREATURE_CALL_REFRESH_INTERVAL`, 1s) scans the two real populations that
carry a `species` string today: every `CreatureMarker` (land mammals/
reptiles, `.info.species`) and every `AmbientFlyerMarker` (birds, plus the
true-butterfly species sharing that class, plain `.species`), rolling
`CreatureCallSound.check_call` for each and triggering
`InteractionSfxPlayer.play_creature_call(species, position)` on a hit.
No distance pre-filter: the call voices are real `AudioStreamPlayer2D`
instances, so a distant creature already reads quieter via Godot's own
positional falloff, and the low `CALL_CHANCE_PER_CHECK` already keeps
this rare regardless of how many creatures are loaded.

### Playback

`src/audio/interaction_sfx_player.gd` (mirrors `NatureSoundscapePlayer`'s
own "`RefCounted` controller, `build()` once in `World._ready`, driven
every frame" shape) owns two small round-robin voice pools:

- 4 plain `AudioStreamPlayer` voices for footstep/mushroom-crush one-shots
  -- always at the listener (the local player's own feet), never
  positional.
- 4 `AudioStreamPlayer2D` voices for creature calls -- positioned at the
  calling creature's own world position each time, so distance/panning
  read correctly.

Both pools round-robin (not always voice 0) so rapid alternating
left/right footsteps, or two nearby creatures calling close together,
get room to overlap instead of cutting each other off.

## A real, separate ambient-audio responsiveness fix (same pass)

Reported live alongside the ask above: *"When I walk into the water it
takes a while before the river wading sound is played then it fades out
and takes a while again before it loops."* Investigated rather than
assumed: there is no dedicated river/water-proximity ambient layer at all
(`soundscape.md`'s own Status list already names this as a real,
not-yet-built gap) -- what's actually audible near/in water is whatever
biome bed the surrounding land classifies as (e.g. a coastal "ocean" biome
tile), and the REAL, confirmed bug was `NatureSoundscapePlayer.update`
throttling its target-mix recompute UNCONDITIONALLY behind a flat 5-second
`REFRESH_INTERVAL_SECONDS`, on top of `VOLUME_RAMP_PER_SECOND`'s own
several real seconds to fully cross-fade -- meaning ANY discrete biome/
weather transition (not water-specific) could take up to ~10 real seconds
to be heard at all, and as long again to fade out.

**The fix:** `update()` now recomputes immediately whenever any of its 5
real inputs (biome/season/weather/is_night/is_snowing) actually differ
from the last call, while still respecting the normal throttle when
nothing changed -- the original rationale ("ambient audio doesn't need
sub-second reaction") stays true for state that isn't moving; it was
never true for a state that just changed. A small, accepted looseness:
the hawk-call cameo's own roll rides the same recompute path, so it can
re-roll a little early on a rapid biome change at a mountain edge -- not
a real balance concern for ordinary play.

**Not attempted here:** a genuine river/lake-proximity ambient layer
(still the same named, not-yet-built gap `soundscape.md` already
documents) and any fix to `ocean.ogg`'s own loop seam (a raw field
recording, not mastered for seamless looping -- would need real audio-
editing tooling this environment doesn't have, the same constraint
`soundscape.md`'s own `rainforest_day.wav` note already names).

## "Compose the sound from what's actually around you"

Reported live alongside the responsiveness bug: *"you hear a lot of birds
even though there aren't any... make it so that the sound is composed
from what's actually around you."* This is a real, larger architectural
direction, not a one-line fix: the ambient beds (`forest_day.mp3`, etc.)
are decorative field recordings with birds baked into the audio itself,
entirely independent of the real simulated `robin`/`sparrow` population
nearby -- there is no way to selectively mute "the birds" inside an
existing monolithic recording without re-recording or real audio-editing
tooling, neither available here.

The creature-call system this doc specifies **is** a direct, real step in
that exact direction: `robin`/`sparrow` calls now come from REAL, live
`AmbientFlyerMarker` instances at their REAL positions, not a decorative
backing track -- if the doc's Status list below shows creature calls
shipped, walking through an area with genuinely zero real birds nearby now
means genuinely zero robin/sparrow CALLS (the ambient bed's own baked-in
chorus is a separate, unchanged layer, not eliminated by this pass).
Fully re-architecting the ambient beds themselves to scale with real
nearby population counts (e.g. muting/thinning the bird-heavy portion of
a forest bed when the real simulated bird count nearby is low) is a real,
substantially larger follow-up, not attempted in this pass.

## Status

- ✅ **Footstep SFX wired end to end**, one real distinct recording each
  for snow and forest (audibly including twigs/undergrowth), every other
  biome sharing one real generic walking recording rather than silence.
- ⬜ **No dedicated grass/sand/rock/underwater footstep recording** --
  a real search effort on Wikimedia Commons did not turn up usable,
  correctly-licensed isolated candidates; they share the default clip
  for now (see `assets/audio/footsteps/CREDITS.md`). A real upgrade if
  sourced later, not a gap in the mixing logic itself.
- ⬜ **No mushroom-crush recording** -- wiring is real and complete
  (`InteractionSfxPlayer.play_mushroom_crush()` fires on every real
  crush), but the clip path is honestly empty; a real, silent no-op today.
- ✅ **12 real, licensed creature calls sourced and wired**: horse, boar
  (domestic pig standing in, named above), sheep, wolf, bear, squirrel,
  deer, robin, sparrow, kingfisher, honeybee, wild_bee (the last two share
  one bumblebee recording).
- ⬜ **Remaining implemented-but-unsourced species**: camel, reindeer,
  tapir, goat, lynx, jackal, arctic_fox, jaguar, mountain_lion, lion,
  alpaca, nonvenomous_snake, venomous_snake -- real, live species in the
  world today with no call sourced yet; `CreatureCallSound.has_call`
  already gates them to silent, not broken, so this list can grow
  incrementally without touching the trigger/playback wiring again.
- ✅ **A real, separate ambient-audio responsiveness fix**: any biome/
  weather transition now starts ramping immediately instead of waiting
  out a flat 5-second throttle -- see its own section above.
- ⬜ **No river/lake-proximity ambient layer, no `ocean.ogg` loop-seam
  fix, no "ambient beds scale with real nearby population" rearchitecture**
  -- all real, named, deliberately-deferred follow-ups (see their own
  sections above), not silently decided.
