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

- `surface_for(biome, snow_lying, underwater) -> String` -- reuses the
  SAME real inputs `EarthChunkManager.footstep_surface_for` already
  computes for the visual footprint, but with WIDER coverage: every biome
  maps to something (falling back to `"default"`), not just the 4 the
  footprint sprite has art for. Priority mirrors that function's own
  (snow, then underwater, then biome) for intuitive consistency even
  though the two functions' surface SETS differ on purpose.
- `clip_path_for(surface) -> String` -- `"snow"`, `"forest"`, `"grass"`,
  and `"underwater"` get their own real recordings; everything else
  (sand/rock, or an unrecognized surface) falls back to one shared,
  genuine walking recording (`default.ogg`) rather than silence -- the
  same "reuse where a distinct recording isn't available" shape
  `NatureSoundscape`'s own wind bed already established for desert/
  tundra/mountain. **Revised (2026-09-09):** `"underwater"` reuses
  `river.ogg` from `NatureSoundscape`'s own asset directory rather than a
  fourth, separately-licensed file -- reported live: "river wading should
  be used for 'underwater walks'". The same real flowing-water recording
  now backs both the continuous ambient river-proximity bed (heard
  nearby) and this one-shot footstep (heard when actually standing in
  it) -- one real asset, two real reasons to be heard.

`EarthChunkManager.record_footstep` returns `{"side", "biome",
"snow_lying", "underwater"}` (empty `Dictionary` when no real step landed
this call) instead of `void` -- the raw facts behind a step, computed even
when the biome has no VISUAL footprint art, so audio's wider coverage
isn't silently capped by the footprint sprite's narrower one.
`World._client_process` feeds those facts through `FootstepSound.
surface_for` and triggers `InteractionSfxPlayer.play_footstep`.

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

- ✅ **Footstep SFX wired end to end**, one real distinct recording each
  for snow, forest (audibly including twigs/undergrowth), and grass,
  every other biome sharing one real generic walking recording rather
  than silence.
- ✅ **Revised (2026-09-09): grass now has a real, distinct footstep
  recording**, not the shared default. Reported live: "it sounds like a
  drum, not like walking on grass." Wikimedia Commons, Freesound.org
  (login-gated), and Pixabay (Cloudflare-bot-check-gated on the actual
  download) were all real dead ends; sourced instead from
  OpenGameArt.org's ungated static downloads, a genuine Freesound field
  recording rehosted there for a real shipped open-source game -- see
  `assets/audio/footsteps/CREDITS.md`'s own "Why `grass.ogg` breaks the
  Commons-only pattern" for the full trail, including a caught-before-use
  mismatch (a differently-named CC0 pack titled itself "grass" but its
  real archive held none).
- ⬜ **No dedicated sand/rock footstep recording** -- a real search
  effort did not turn up usable, correctly-licensed isolated candidates;
  they share the default clip for now (see
  `assets/audio/footsteps/CREDITS.md`). A real upgrade if sourced later,
  not a gap in the mixing logic itself.
- ✅ **Revised (2026-09-09): `underwater` now has a real, distinct water
  clip.** Reported live: "river wading should be used for 'underwater
  walks'." Reuses `river.ogg` (the ambient river-proximity layer's own
  genuine flowing-water recording, see "Proximity layer: `river`" in
  `soundscape.md`) rather than a fourth, separately-licensed file --
  walking through water no longer sounds identical to walking on dry
  land.
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
