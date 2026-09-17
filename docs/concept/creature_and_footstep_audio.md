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
   fabricated call. A genuinely unsourceable sound stays an honest, named
   gap rather than an UNASKED-FOR mismatched stand-in -- a real, named
   Foley substitute, requested directly by name, is a different case (see
   "Mushroom crush" below): the grounding this pillar cares about is
   never claiming a sound is the genuine article when it isn't, not a
   blanket ban on Foley technique.
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
  equally distinct one was found for sand/rock despite a real search
  effort -- see "Footsteps" below for how that gap is handled without
  inventing a fake recording. **Revised (2026-09-09): grass now has a
  real, distinct recording too** -- reported live: "it sounds like a
  drum, not like walking on grass" about the `default.ogg` it used to
  silently share. Wikimedia Commons and Freesound.org (login-gated
  downloads) and Pixabay (this download specifically hit a Cloudflare
  bot-check) were all real dead ends; OpenGameArt.org's plain, ungated
  static downloads turned up a genuine Freesound grass-footstep field
  recording, already rehosted there for a real shipped open-source game
  -- see `assets/audio/footsteps/CREDITS.md`'s own "Why `grass.ogg`
  breaks the Commons-only pattern" for the full sourcing trail. `underwater`
  is a real exception, not a gap: it reuses the ambient river-proximity
  layer's own genuine flowing-water recording (`river.ogg`) rather than
  needing a separately-licensed isolated Foley clip at all.
- **A mushroom crushed underfoot is a real, distinct event** (see
  `docs/concept/mushrooms.md`'s `CrushMechanic`). No genuine squish/splat
  recording ever turned up on Commons -- left honestly silent for a
  while (see "Mushroom crush" below) rather than reached for an
  unasked-for mismatched stand-in (a knife-chop, a door-chime). Now
  sourced: a crushed-styrofoam recording, requested directly by name, a
  real Foley substitute technique rather than an invented mismatch (see
  "Mushroom crush" below for the full reasoning).
- **Which animals get a call is a biology question, not a completeness
  checklist.** Every species that got a real recording here genuinely
  vocalizes; every species left out (insects, fish, butterflies) genuinely
  doesn't, at a range a nearby player would hear. **Cicadas are the
  deliberate exception among insects** (see "Cicadas" below): among the
  loudest insects on Earth, easily audible at real distance -- the same
  biology-first reasoning that excludes ants/decomposer bugs is what
  includes this one.
- **A real boar/pig substitution, named, not hidden.** Wild boar and
  domestic pig are the same species (*Sus scrofa*); a clean domestic pig
  grunt stands in for the wild boar call this project doesn't have an
  isolated recording of. See `assets/audio/creatures/CREDITS.md`.

## Mechanism

### Footsteps

`src/audio/footstep_sound.gd` (pure, no Node dependency) owns the surface
classification and clip lookup:

- `surface_for(biome, snow_lying, underwater, ground_material) -> String`
  -- reuses the SAME real inputs `EarthChunkManager.footstep_surface_for`
  already computes for the visual footprint, but with WIDER coverage:
  every biome maps to something (falling back to `"default"`), not just
  the 4 the footprint sprite has art for. Priority mirrors that
  function's own (snow, then underwater, then the laid material, then
  biome) for intuitive consistency even though the two functions' surface
  SETS differ on purpose. `ground_material` was added 2026-09-17 -- see
  "A laid surface sounds like what it is laid with" below.
- `step_variants_for(surface) -> Array[String]` and
  `step_clip_path_for(surface, roll) -> String` -- every surface has a
  POOL of real, isolated footstep one-shots (5 to 10 of them), and a step
  takes a different one each time. A surface with nothing sourced falls
  back to `FALLBACK_CLIP_PATH` (one shared, genuine walking recording,
  `default.ogg`) rather than silence -- the same "reuse where a distinct
  recording isn't available" shape `NatureSoundscape`'s own wind bed
  already established for desert/tundra/mountain. **Superseded
  (2026-09-17):** this replaced a single `clip_path_for(surface)`, which
  gave each surface exactly one recording -- see "A recording of walking
  is not a footstep" below for why that was the whole problem. The
  2026-09-09 revision that pointed `"underwater"` at the ambient
  `river.ogg` ("river wading should be used for 'underwater walks'",
  reported live) is superseded by the same pass: underwater now plays real
  recordings of feet going INTO water, which is what wading is, where
  `river.ogg` is a river heard from the bank. `river.ogg` keeps its
  ambient job untouched.

`EarthChunkManager.record_footstep` returns `{"side", "biome",
"snow_lying", "underwater", "ground_material"}` (empty `Dictionary` when
no real step landed this call) instead of `void` -- the raw facts behind
a step, computed even when the biome has no VISUAL footprint art, so
audio's wider coverage isn't silently capped by the footprint sprite's
narrower one.
`World._client_process` feeds those facts through `FootstepSound.
surface_for` and triggers `InteractionSfxPlayer.play_footstep`.

**Revised (2026-09-10): grass plays quieter than every other surface.**
Reported live: *"The grass footsteps are way too loud... can you make
them fainter?"* `grass.ogg` (OpenGameArt/Freesound, see CREDITS.md) reads
noticeably hotter than every other sourced clip here (all Wikimedia
Commons or Pixabay) -- distinct sourced clips were never level-matched to
each other, the same "no audio-editing tooling in this environment"
constraint that already applies to trimming/codec fixes elsewhere in this
doc. New `FootstepSound.volume_db_for(surface) -> float` (a per-surface
dB adjustment dict, `0.0`/unchanged for anything not listed) supplies a
real, deliberate `-12.0` for grass -- roughly a perceived halving of
loudness (a well-established audio-engineering rule of thumb, not a
personal-preference number), matching how strongly this was reported.
`InteractionSfxPlayer._play_footstep_clip` gained a `volume_db`
parameter, defaulting to `0.0` and applied UNCONDITIONALLY on every
call -- the round-robin voice pool reuses the same `AudioStreamPlayer`
across different surfaces over time, so a voice left at grass's own
quieter volume must never bleed into whatever plays next on it (footstep
or mushroom crush alike). `play_footstep` passes the surface's own value
through; `play_mushroom_crush` deliberately relies on the `0.0` default
rather than passing it explicitly, so a crush always plays at full volume
regardless of which surface last used that voice.

TDD: `test_grass_footsteps_play_quieter_than_the_default_volume` /
`test_every_other_surface_plays_at_the_default_volume` in `test_
footstep_sound.gd` (now 15/15); `test_interaction_sfx_player.gd` gained
3 tests (now 15/15) -- applying the adjustment, and two reuse-guard tests
that deliberately cycle the FULL voice pool with grass first so the next
call is guaranteed to land on a voice actually left at `-12dB`, proving
neither a later footstep nor a mushroom crush inherits it by accident.

### A recording of walking is not a footstep (2026-09-17)

Reported live: *"Can you find better sounds for the footsteps on every
terrain? They sound weak and not natural"*. Nobody in this environment can
hear the game, so the measurable half got measured first -- and it was the
whole explanation. Every clip the game reached for was a recording of
somebody WALKING rather than a footstep, and the levels were 35 dB apart end
to end:

| clip | length | RMS | peak |
|---|---|---|---|
| `grass.ogg` | 0.25s | -12.59 dBFS | -0.74 dBFS |
| `default.ogg` | 3.64s | -47.63 dBFS | -17.86 dBFS |
| `snow.mp3` | 13.72s | -38.42 dBFS | -10.34 dBFS |
| `forest_twigs.ogg` | 41.67s | -41.26 dBFS | -15.93 dBFS |

Three things followed from that, and they are the three complaints:

- **Weak.** Every step played its clip from `0.0`, so a forest step was
  always the same fraction of the same run-in -- quiet, because the
  recording had not reached a real impact yet. And a 35 dB spread means the
  eyeballed `-12 dB` that answered *"the grass footsteps are way too loud"*
  (2026-09-10, above) closed barely a third of it while leaving every other
  surface where it was.
- **Not natural.** One recording per surface means every step on that
  surface is literally the same sample, at the same pitch.
- **Cut off.** The 4-voice pool's own round-robin then truncated each step
  mid-ring a second and a half later, when four more steps had gone by.

**The pools.** Every surface now has several real, isolated footstep
one-shots, built by `tools/prepare_footstep_oneshots.py` (see
`assets/audio/footsteps/CREDITS.md` for every source and licence):

| surface | steps | where from |
|---|---|---|
| `grass` | 9 | the OpenGameArt pack whose first variation was already in use -- the other 8 were sitting in the same archive |
| `wood` | 9 | same pack; retires the generic clip a wooden floor inherited |
| `rock` | 10 | same pack's gravel |
| `underwater` | 5 | same pack's water: feet going into water |
| `default` | 9 | same pack's boots |
| `sand` | 6 | Fantozzi's Footsteps (CC0) |
| `snow` | 8 | Corsica_S's 42 real snow steps (CC0) |
| `forest` | 8 | cut out of this repository's OWN 41-second forest recording, at its real footfalls |

The forest cut is worth its own note: same file, same licence, same real
forest at 3am. The recording holds 62 real footfalls, and its quiet floor
measures -51.6 dBFS against footfalls around -24 dBFS, so the crickets
audible in the full recording sit 27 dB under a step and do not ride along.
Footfalls are found by tracking the recording's OWN floor -- a step is a
9 dB rise over the lower quartile of the preceding 0.4s, which in a
recording of walking IS the gap between steps -- rather than by a fixed
threshold that would need retuning per recording.

**The levels are measured, not chosen.** Each pool gets ONE gain, so its
MEAN lands on a common target: one gain per pool rather than per clip on
purpose, because that equalizes between surfaces while leaving a soft step
softer than a hard one WITHIN a surface, which is the variation the
recordings were made for. The target is **-24.59 dBFS RMS**, and that is
not a taste call either: `grass.ogg` measures -12.59 dBFS RMS and was
reported as finally right at `-12.0 dB`, so it is the one footstep level
already signed off on. Solving for grass's nine clips from scratch landed on
`-12.0` for it independently -- the by-ear number and the measured one
agree. A pool's gain is pulled back if it would push that pool's loudest
peak past -1 dBFS, which is why `sand` and `snow` sit ~1-2 dB under target
(crunchy surfaces have a high crest factor; physical, not a defect). The
whole spread is now **2.4 dB**, down from 35.

`FootstepSound._VOLUME_DB_BY_SURFACE` holds those gains, and
`test_every_surfaces_volume_is_the_gain_the_pipeline_measured` pins it
against `assets/audio/footsteps/steps/levels.json`, which the pipeline
writes -- so the constants cannot drift from the files they describe. Godot
cannot hand raw samples back from a compressed stream, so the decode-level
measurement genuinely has to live in the manifest; what the test suite
re-measures for itself every run is every clip's real LENGTH
(`stream.get_length()`), which is what catches a swapped clip.

**Per-step variation on top.** `pitch_scale_for(roll)` nudges each step by
up to ±6% (`PITCH_VARIATION`) -- small on purpose: a footstep that swings a
whole semitone reads as a different person's boot rather than the same boot
on a different patch of ground. It is applied UNCONDITIONALLY, for exactly
the reason `volume_db` already was: the pool reuses voices, so a pitch left
behind by a previous step must never ride along on whatever plays next (a
mushroom crush included).

**Windowing, for the fallback only.** Whether a clip has to be read one step
at a time is a fact about the CLIP, not about the ground, so
`is_walking_bed(clip_path)` / `offset_for(clip_path, roll)` are keyed by
path. A real one-shot is played whole from its own beginning; a long
recording is started somewhere else in itself each step (never so late that
the window runs off the end) and closed again after `STEP_WINDOW_SECONDS`
(0.45s), instead of leaving the rest of a stranger's walk playing under the
next step. Every surface the game can put underfoot has real one-shots now,
so this is what the fallback recording gets -- and what the next surface
somebody adds to `_SURFACE_BY_BIOME` inherits before anyone records it.

Closing a window closes THAT step's window and only its own. The real
cadence was measured rather than assumed: `FootstepGait.STRIDE_LENGTH_PX`
8.415 at `Player.BASE_SPEED` 40 px/s is a step every **0.210s**, and
**0.105s** sprinting -- so with a 4-voice pool the fifth step lands back on
voice 0 while voice 0's own window is still counting down. A timer that just
called `stop()` would cut the new step off after a fraction of a step, which
is the very mid-ring truncation the window exists to remove; it checks a
per-voice token instead.

**Tooling note.** `assets/audio/footsteps/CREDITS.md` long recorded that
"real audio-editing tooling to trim the FILE itself isn't available in this
environment", and several decisions in this doc were shaped by that. It is
no longer true: `pip install imageio-ffmpeg py7zr` brings a real ffmpeg and
a 7z reader as plain wheels, no system packages. Trimming, cutting,
transcoding and loudness measurement are all available to a future pass.

`play_footstep` returns the voice it started, like `play_mushroom_crush`.
That is not cosmetic: which clip a step took is otherwise unanswerable from
outside, because several voices are legitimately mid-step at any moment and
none of them is "the current one". The first version of the pool-coverage
test searched for a playing voice instead and failed consistently on the
last clip of a pool -- correctly, since that search reports the
lowest-indexed clip still sounding rather than the one this step chose.

TDD: `test_footstep_sound.gd` 40/40 (13 new, covering pool depth, every
variant really loading, every variant really being one step long, the roll
reaching the whole pool at both extremes, the measured gains matching the
manifest, the between-surface spread, peak headroom, and no shipped clip
being unreachable); `test_interaction_sfx_player.gd` 25/25 (consecutive
steps not repeating one recording, enough steps reaching the whole pool,
plus the offset/pitch/window wiring, each re-verified by mutating it back
out and watching its own test fail).

### A laid surface sounds like what it is laid with (2026-09-17)

Reported live: *"walking over cobblestone streets should not leave
footprints."* The visual half of that is
[snow_cover.md's "Ground that is too hard to take a
print"](snow_cover.md#ground-that-is-too-hard-to-take-a-print-2026-09-17);
this is its sibling gap, named there and closed here. The print gate
knew a street was stone, but this file only ever asked the **biome** —
and a road never changes the biome under it, exactly as a river doesn't
(see [infrastructure.md](infrastructure.md)'s Road tier) — so walking a
cobbled street played `grass.ogg`.

**One ground per step, read by both consumers.** `record_footstep` now
resolves `GroundImprint.material_underfoot(modification, snow_lying)`
**once** and uses it twice: the print gate asks whether that material
can be indented at all, and the returned facts carry it out to
`FootstepSound.surface_for`. Resolving it once is the point, not an
optimisation — two separate lookups would let the print and the sound
disagree about what was underfoot.

**`_SURFACE_BY_GROUND_MATERIAL`**: `stone` → `"rock"`, `wood`/`timber` →
`"wood"`. Three deliberate absences:

- **`"soil"` is not mapped**, so untouched ground still falls through to
  the biome — grassland still sounds like grass, desert still like sand.
  Soil is the *absence* of anything laid on top, not a surface of its
  own.
- **`"snow"` is not mapped** because snow is already checked first, for
  the same real reason it wins in `material_underfoot`: it lies on top
  of a street, while a street lies on top of the ground. Standing water
  keeps its place above the laid material too.
- **`wood` and `timber` share one surface.** The difference between sawn
  and hewn timber underfoot is a distinction this file has no recording
  to express.

**What this bought, and what it did not.** At the time: no distinct stone
or wooden-floor recording had been sourced — Wikimedia Commons' Foley
coverage is thin generally (see `CREDITS.md`'s own note, and the same gap
then standing for sand and rock) — so `"rock"` and `"wood"` both resolved
to the generic `default.ogg`. **The win was that a street stopped sounding
like grass, not that it sounded like cobbles.** Both have real pools as of
2026-09-17 (see "A recording of walking is not a footstep" above); a street
sounds like gravel rather than like cobbles, which is the remaining step. A real
recording for either is a welcome upgrade whenever one turns up, not a
gap in this mapping.

TDD: 6 new tests in `test_footstep_sound.gd` (the paved cell, a built
wooden floor, plain soil still deferring to the biome, snow and water
still winning, and the 3-arg default leaving every pre-existing caller
identical); 3 in `test_earth_chunk_manager_footprints.gd` for the new
fact, including one proving it is reported even where no print is drawn
at all; 1 source-contract test in `test_world_footstep_wiring.gd` that
the material reaches `surface_for` from `record_footstep`'s own facts
rather than a second lookup.

### Mushroom crush

Left an honest empty string for a while (see "Real-world grounding"
above) -- `World._client_process` already called `InteractionSfxPlayer.
play_mushroom_crush()` in the same branch that applies the Karma penalty
for `_chunk_manager.crush_mushroom_at(...)`, so the wiring was real and
complete from the start; it was simply a silent no-op
(`InteractionSfxPlayer` skips an empty clip path cleanly) until a real
recording turned up.

Requested directly (2026-09-09): *"can you find a styrofoam crushing
sound and use it for the mushroom crushing sound?"* `FootstepSound.
MUSHROOM_CRUSH_CLIP_PATH` now points at `assets/audio/footsteps/
mushroom_crush.mp3` -- "Crinkling styrofoam; close" (TylerAM, via
Freesound, rehosted on Pixabay under the Pixabay Content License; see
`assets/audio/footsteps/CREDITS.md` for the full citation and why this
is the one file in that directory NOT sourced from Wikimedia Commons).
Crushed styrofoam is a real, established Foley substitute for a
crunchy/organic crush -- the technique itself is real-world-grounded
(pillar 2 above), even though the recorded material isn't literally a
mushroom; a genuinely unsourceable sound stays an honest gap by default,
but a specific requested stand-in is a deliberate choice, not an
invented mismatch. No code change beyond the constant's own value and
the `InteractionSfxPlayer`/`World` wiring already in place -- the
no-op-when-empty guard in `InteractionSfxPlayer._play_footstep_clip`
simply stops triggering now that the path is real.

**Revised (2026-09-10): capped at 0.3s, not the source recording's full
native length.** Reported live: *"Can you make the mushroom crush sound
only 0.3s long? It plays long after you stepped on it."* Real audio-
editing tooling to trim the FILE itself isn't available in this
environment (the same constraint `assets/audio/footsteps/CREDITS.md`
already names elsewhere), so this caps PLAYBACK instead:
`InteractionSfxPlayer.play_mushroom_crush()` now schedules a one-shot
`SceneTreeTimer` (`MUSHROOM_CRUSH_MAX_DURATION_SECONDS`, 0.3) that stops
the specific voice that started playing. Footsteps are unaffected and
deliberately not capped the same way -- they naturally cut themselves
short every stride (the very next step restarts the same round-robin
voice pool), so only a rare, one-off event like a mushroom crush ever
plays its source recording out to the end uninterrupted.
`_play_footstep_clip` now returns the `AudioStreamPlayer` it started
(`null` for the empty-path no-op) so `play_mushroom_crush` has the exact
voice instance to attach the stop-timer to -- `play_footstep` ignores the
return value, unaffected. TDD:
`test_mushroom_crush_stops_itself_after_its_own_max_duration` (a real
wall-clock `await wait_seconds`, not a simulated delta) confirmed red
against the uncapped code first, green after. `test_interaction_sfx_
player.gd` 12/12.

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

### Cicadas

Reported live: *"you can hear cicadas in the environment which don't
exist... add them please as real ecosystem member and produce cicada
sounds for each individual."* Investigated rather than assumed: what was
actually audible was `grassland_day.mp3`, honestly credited in
`assets/audio/soundscape/CREDITS.md` as "Atmo -- Grillen mit Hummeln"
(German: crickets with bumblebees) -- a real, correctly-working ambient
recording doing exactly its documented job, not a bug and not a fake
cicada sound. But the underlying ask stands on its own real merits: a
genuine cicada is a real, distinct, famously loud insect this game didn't
have at all, and `CreatureCallSound`'s own pillar 2 (real vocalizing
species get a call) applies to it directly -- cicadas are among the
loudest insects on Earth, the deliberate exception to "insects are
inaudible to a nearby human" among this doc's own excluded species.

**Real-world grounding decided the shape, not just whether it exists.**
Nymphs spend years underground; adults emerge for only a few summer weeks
specifically to cling to one spot on a tree trunk/branch and call loudly
for a mate, then die -- a real adult cicada never leaves its tree and has
no other behavior worth simulating. This is genuinely different from
every other species in this doc: it needed a NEW real population, not
just a new row in `CreatureCallSound`'s existing table, since no existing
population (`CreatureMarker` land creatures, `AmbientFlyerMarker` birds/
butterflies) is stationary/tree-anchored the way a cicada actually is.

**`src/world/cicada_population.gd`** (pure) decides which of a chunk's
real trees host a calling cicada right now:

- `is_active_in(season) -> bool` -- summer only, the real definitive
  cicada season.
- `cicada_tree_indices(tree_count, season, roll_per_tree) -> Array[int]`
  -- one caller-supplied roll per tree (the same "caller rolls, this pure
  function decides" split `CreatureCallSound.check_call` already uses),
  gated first by season then by `TREE_DENSITY` (0.15 -- deliberately
  sparse: a chorus of dozens of trees at once would be a wall of noise,
  not the real "your ear picks out an individual cicada or two nearby"
  experience).

Deliberately NO growth/starvation/persistence economy the way
`AntColony`/`BeeColony` get: a real adult cicada's whole calling window
is short enough, and this game's own chunk load/unload cycle frequent
enough, that a FRESH roll every time a chunk loads is an honest
simplification of that same short-windowed real presence, not a missing
feature or a corner cut.

**`src/rendering/cicada_marker.gd`** (`CicadaMarker`, a plain `Node2D`) is
the real per-individual presence -- `species := "cicada"`, joins the
`"cicadas"` group on `_ready()`, exactly the shape `World._maybe_play_
creature_calls` already scans `CreatureMarker.GROUP_NAME`/
`AmbientFlyerMarker.FLOCK_GROUP` through. No movement, no behavior state
machine at all -- mirrors `AntQueenMarker`'s own precedent for "a real
creature that genuinely never moves gets no state machine", rather than
inheriting `AmbientFlyerMarker`'s flight/foraging machinery a cicada would
never use. **No dedicated visual art in this pass** -- a real, named,
deliberately scoped gap: real adult cicadas are famously heard far more
than seen (excellent bark camouflage), so an audio-only presence this
pass is an honest match for the real thing, not merely a corner cut. A
visible cicada (or its real, well-known molted exoskeleton shell) would
be a welcome, separate visual follow-up.

`EarthChunkManager._dispatch_cicadas(chunk_coord)` rolls once per real
tree in `_loaded_trees[chunk_coord]` right after that chunk's trees
finish spawning, and `_spawn_cicadas_for_indices` (split out so a test can
drive it with a deterministic index list, bypassing the roll --
mirroring `test_earth_chunk_manager_bees.gd`'s own direct-injection
precedent for hive/nest placement's identical real-probabilism problem)
spawns one `CicadaMarker` per qualifying tree, tracked in a new
`_cicada_markers` dict keyed by chunk coordinate exactly like
`_loaded_trees`/`_loaded_stones` already are. `_unload_chunk` frees every
cicada marker for that chunk the identical `for marker in ...get(
chunk_coord, []): marker.free()` / `...erase(chunk_coord)` discipline
every other per-chunk marker collection already gets.

`World._maybe_play_creature_calls` gained a third scan loop, over
`CicadaMarker.GROUP_NAME`, identical in shape to the two that already
exist -- a real third population, not a decorative loop bolted on
separately. `CreatureCallSound._CLIP_BY_SPECIES` gained a `"cicada"` entry
(`assets/audio/creatures/cicada.ogg`, a real *Cicada orni* field recording
from Southern France, CC BY-SA 2.5 -- see that directory's own
CREDITS.md), so calling a cicada individual reuses the exact same
`check_call`/`play_creature_call` proximity-gated mechanism every other
species already does, not a parallel one invented for this species.

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

**Second pass (same day): the call scan itself wasn't actually "nearby."**
Reported live a second time, more pointedly: "you hear a lot of birds even
though there aren't any... compose the sound from what's actually around
you." The first pass's own reasoning -- that `AudioStreamPlayer2D`'s
positional falloff alone would make a distance check redundant -- was
wrong on inspection: `_maybe_play_creature_calls` scanned EVERY
`CreatureMarker`/`AmbientFlyerMarker` in the entire loaded world (every
loaded chunk, not just ones near the player) and only relied on the mix to
quiet the far ones. Two real bugs compounded that: (1) nothing bounded
WHICH creatures were even eligible to be picked from in the first place,
so a creature many chunks away could still roll a hit; (2) `max_distance`
on the call voices was left at Godot's own default (2000px, ~178 real
metres at this project's scale) -- far too wide to meaningfully quiet
anything within a sane "nearby" range even when a distant creature did
roll a hit.

**The fix:** `CreatureCallSound.check_call` now takes the real distance
from the player and rejects anything beyond `AUDIBLE_RADIUS_PX` (35 real
metres -- see that constant's own doc comment for why: further than
`World.CREATURE_PANELS_RADIUS`'s own ~20m "visibly on screen" range, since
sound carries a little further than sight, but still a real, bounded
scope, not the whole loaded chunk radius) BEFORE spending the roll on the
chance-per-check compare. `InteractionSfxPlayer`'s call voices now set
`max_distance` to that same radius, so a call that does fire attenuates to
near-silence right around the same distance it stops being eligible at
all, rather than staying at full volume most of the way to a cutoff eight
times further out. `_maybe_play_creature_calls` now takes `local_player`
and measures `local_player.position.distance_to(...)` per creature/flyer
-- the one real fact the whole fix hinges on.

No new species/asset work needed -- this is a pure eligibility/attenuation
fix over the exact same sourced calls the first pass shipped. TDD:
`check_call`'s signature grew a `distance_px` parameter (confirmed red
against the old 2-argument call sites first), new tests pin "fires right
at the radius edge" and "never fires one px beyond it";
`test_world_creature_and_footstep_audio_wiring.gd` gained a source-text
assertion that the scan actually measures and forwards a real distance,
not just that `check_call` is called at all (the pre-fix code would have
passed that weaker assertion already).

Fully re-architecting the ambient BEDS themselves to scale with real
nearby population counts (e.g. muting/thinning the bird-heavy portion of
a forest bed when the real simulated bird count nearby is low) is a real,
substantially larger follow-up, not attempted in this pass -- the fix
above makes the discrete CALL layer honestly proximity-based; the
continuous bed underneath it is still the same decorative, population-
independent recording described above.

## Status

- ✅ **Footstep SFX wired end to end**, and **every surface now has a pool
  of 5-10 real, isolated, level-matched footstep one-shots** (2026-09-17)
  -- see "A recording of walking is not a footstep" above. Reported live:
  "Can you find better sounds for the footsteps on every terrain? They
  sound weak and not natural." Measured first: the clips were recordings
  of somebody WALKING (up to 41.67s) played from 0.0 every step, 35 dB
  apart end to end. Now: real steps per surface, a different one each
  step, ±6% pitch, and one MEASURED gain per surface landing every pool
  within 2.4 dB of the level already signed off on. **Not verified: whether
  it sounds better** -- nothing here can hear it, so lengths, levels,
  variation and windowing are what is tested.
- ✅ **Revised (2026-09-09): grass now has a real, distinct footstep
  recording**, not the shared default. Reported live: "it sounds like a
  drum, not like walking on grass." Wikimedia Commons, Freesound.org
  (login-gated), and Pixabay (Cloudflare-bot-check-gated on the actual
  download) were all real dead ends; sourced instead from
  OpenGameArt.org's ungated static downloads, a genuine Freesound field
  recording rehosted there for a real shipped open-source game -- see
  `assets/audio/footsteps/CREDITS.md`'s own "Why the grass recording
  breaks the Commons-only pattern" for the full trail, including a caught-before-use
  mismatch (a differently-named CC0 pack titled itself "grass" but its
  real archive held none). **All nine of that pack's grass variations ship
  now** (2026-09-17); `CREDITS.md` had recorded that only the first was
  copied in "if per-step variation is ever added later", and it has been.
  `steps/grass_00.ogg` is byte-for-byte the file this row described.
- ✅ **A laid surface sounds like what it is laid with** (2026-09-17) --
  see "A laid surface sounds like what it is laid with" above. Walking a
  cobbled street played `grass.ogg`, because this file only ever asked
  the BIOME and a road never changes the biome under it. The step facts
  now carry a `ground_material`, resolved ONCE per step by
  `GroundImprint.material_underfoot` and read by both the visual print
  gate and `surface_for`, so the two cannot disagree about what is
  underfoot. `stone` -> `"rock"`, `wood`/`timber` -> `"wood"`; `"soil"`
  deliberately unmapped, so ordinary ground still takes its sound from
  the biome.
- ✅ **Sand, rock and wooden floors have their own recordings now**
  (2026-09-17), closing the gap this row stood for since 2026-09-09.
  Sand: Fantozzi's Footsteps (CC0) -- the same pack an earlier session had
  already found and correctly rejected for grass, which it genuinely does
  not contain. Rock: the gravel folder of the pack grass came from, which
  nobody had looked inside. Wood: that pack's wooden-floor steps. All
  ungated static downloads, all credited.
- 🚧 **A laid cobbled street still sounds like the rock underfoot, not
  like cobbles.** `rock` covers tundra, mountain AND laid stone, and its
  pool is gravel -- right for two of those three. Splitting a `stone`
  surface out of `rock` is the remaining step; the same pack's `tile/` (9
  clips) and Fantozzi's `Stone` (6) are already cached for it by
  `tools/prepare_footstep_oneshots.py`. A real, named scope cut, not an
  oversight.
- ✅ **`underwater` has real water footsteps** (2026-09-17). Reported live
  (2026-09-09): "river wading should be used for 'underwater walks'",
  answered at the time by pointing underwater at `river.ogg`, the ambient
  river-proximity layer's own flowing-water recording -- the only water in
  the project then. It now plays 5 real recordings of feet going INTO
  water, which is what wading is, where `river.ogg` is a river heard from
  the bank. `river.ogg` keeps its ambient job untouched. Flagged as a
  deliberate change to a live request, not a silent one.
- ✅ **Mushroom-crush sound** (`assets/audio/footsteps/mushroom_crush.mp3`,
  2026-09-09) -- a crushed-styrofoam Foley stand-in, requested directly by
  name; see "Mushroom crush" above for the full reasoning and
  `assets/audio/footsteps/CREDITS.md` for the citation.
- ✅ **13 real, licensed creature calls sourced and wired**: horse, boar
  (domestic pig standing in, named above), sheep, wolf, bear, squirrel,
  deer, robin, sparrow, kingfisher, honeybee, wild_bee (the last two share
  one bumblebee recording), cicada.
- ✅ **Cicadas are a real, new tree-anchored population, not just a
  `CreatureCallSound` table row** (see "Cicadas" above) -- reported live:
  "you can hear cicadas in the environment which don't exist... add them
  please as real ecosystem member and produce cicada sounds for each
  individual." `CicadaPopulation` (pure, season+density-gated) +
  `CicadaMarker` (a real, minimal, per-individual presence, no movement/
  behavior) + `EarthChunkManager._dispatch_cicadas`/`_spawn_cicadas_for_
  indices`, scanned by `World._maybe_play_creature_calls`'s new third
  loop exactly like the two existing populations. **No dedicated visual
  art in this pass** -- a real, named, deliberately scoped gap (real
  adult cicadas are famously heard far more than seen), not silently
  decided.
- ⬜ **Remaining implemented-but-unsourced species**: camel, reindeer,
  tapir, goat, lynx, jackal, arctic_fox, jaguar, mountain_lion, lion,
  alpaca, nonvenomous_snake, venomous_snake -- real, live species in the
  world today with no call sourced yet; `CreatureCallSound.has_call`
  already gates them to silent, not broken, so this list can grow
  incrementally without touching the trigger/playback wiring again.
- ✅ **A real, separate ambient-audio responsiveness fix**: any biome/
  weather transition now starts ramping immediately instead of waiting
  out a flat 5-second throttle -- see its own section above.
- ✅ **Creature calls are now genuinely proximity-gated, not "anywhere in
  the loaded world."** Reported live: "you hear a lot of birds even
  though there aren't any... compose the sound from what's actually
  around you." `check_call` rejects anything beyond
  `CreatureCallSound.AUDIBLE_RADIUS_PX` (35 real metres) before rolling at
  all, and the call voices' own `max_distance` now matches that radius
  instead of Godot's much wider (~178m) default -- see "Second pass"
  above.
- ⬜ **No river/lake-proximity ambient layer, no `ocean.ogg` loop-seam
  fix, no "ambient beds scale with real nearby population" rearchitecture**
  -- all real, named, deliberately-deferred follow-ups (see their own
  sections above), not silently decided.
