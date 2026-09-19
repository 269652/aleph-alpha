extends RefCounted

## Real per-surface footstep/interaction SFX (see docs/concept/
## creature_and_footstep_audio.md). Reported live: "we need footsteps;
## twigs cracking in forest wood; walking over a mushroom should produce a
## correct sound." Pure surface-classification + clip lookup, no
## AudioStreamPlayer/Node dependency -- the same "pure model, thin Node"
## split `nature_soundscape.gd` already uses for the ambient beds.
##
## Reuses the SAME real biome/snow/underwater inputs
## `EarthChunkManager.footstep_surface_for` already computes for the
## VISUAL footprint sprite (see docs/concept/snow_cover.md's "Footprints")
## -- never re-derives them -- but keeps its OWN, WIDER surface
## classification rather than sharing that function's return value
## directly. The footprint sprite only has real art for 4 surfaces
## (grass/forest/snow/underwater) and silently draws nothing for the other
## 3 biomes -- a correct, deliberate visual scope cut (see
## EarthChunkManager's own `_SURFACE_BY_FOOTSTEP_BIOME`) -- but that same
## cut would be the WRONG one for sound: every biome should make SOME
## footstep noise, not just the ones that already have a footprint sprite.

const _SURFACE_BY_BIOME := {
	"grassland": "grass",
	"forest": "forest",
	# Real-world-honestly close enough as a named simplification, not an
	# oversight: both a temperate forest floor and a rainforest floor are
	# leaf-litter/undergrowth underfoot. No dedicated rainforest recording
	# has been sourced (see CREDITS.md) -- worth a real upgrade later if a
	# genuinely distinct one turns up.
	"rainforest": "forest",
	"desert": "sand",
	"tundra": "rock",
	"mountain": "rock",
}

## What a cell is actually MADE OF, when that is something LAID rather
## than the biome's own ground -- the same materials `GroundImprint.
## material_underfoot` already resolves for the VISUAL footprint gate (see
## docs/concept/snow_cover.md's "Ground that is too hard to take a
## print"), read here for the other half of the same question. Reported
## live: "walking over cobblestone streets should not leave footprints",
## whose sibling gap was that the same street still SOUNDED like the grass
## beside it, because this file only ever asked the biome -- and a road
## never changes the biome under it (see `docs/concept/infrastructure.md`'s
## Road tier), exactly like a river never does.
##
## "soil" is deliberately ABSENT rather than mapped: untouched ground is
## the absence of anything laid on top of it, so it falls through to the
## biome exactly as before -- grassland still sounds like grass, desert
## still like sand. "snow" is absent for the same reason snow is handled
## first below.
##
## `wood` and `timber` share one "wood" surface: both are a built wooden
## floor underfoot, and the difference between sawn and hewn timber is a
## distinction this file has no recording to express. No distinct wooden-
## floor recording has been sourced either -- so "wood" shared the generic
## walking clip for a while, and has its own pool of nine real wooden-floor
## steps now (see `_STEP_POOL_SIZES`).
const _SURFACE_BY_GROUND_MATERIAL := {
	"stone": "rock",
	"timber": "wood",
	"wood": "wood",
}

## `biome`/`snow_lying`/`underwater`/`ground_material` are the exact same
## live facts `EarthChunkManager.record_footstep` already computes every
## step for the visual footprint -- pass them straight through, never
## re-derive. Priority mirrors `footstep_surface_for`'s own exactly (snow
## checked first, then underwater) so the two stay intuitively consistent
## even though their surface SETS differ; the laid material sits between
## those overrides and the plain biome, because snow and standing water
## lie ON TOP of a street while the street lies on top of the ground.
##
## `ground_material` defaults to "" -- no laid material known -- so every
## pre-existing 3-arg call site resolves to exactly its previous answer.
static func surface_for(
	biome: String, snow_lying: bool, underwater: bool, ground_material: String = ""
) -> String:
	if snow_lying:
		return "snow"
	if underwater:
		return "underwater"
	var laid := String(_SURFACE_BY_GROUND_MATERIAL.get(ground_material, ""))
	if not laid.is_empty():
		return laid
	return String(_SURFACE_BY_BIOME.get(biome, "default"))


## The one recording left for a surface that has no real steps of its own
## (see _STEP_POOL_SIZES below) -- a general walking recording, read one
## window at a time (see "one step out of a recording of many"). Every
## surface the game can actually put underfoot has a pool now, so nothing
## reaches this today; it stays because the honest answer to an
## unrecognized surface is still SOME footstep noise rather than silence
## ("we need footsteps", reported live as a general ask), and because the
## next surface somebody adds to _SURFACE_BY_BIOME will land here before
## anyone records it.
const FALLBACK_CLIP_PATH := "res://assets/audio/footsteps/default.ogg"

## Where a surface's real, isolated footstep one-shots live, and how many
## of them there are -- built by tools/prepare_footstep_oneshots.py, which
## also writes down what it measured in the same directory's levels.json.
##
## Reported live: *"Can you find better sounds for the footsteps on every
## terrain? They sound weak and not natural"*. Both halves of that were
## measurable. Every clip this file used to reach for was a recording of
## somebody WALKING rather than a footstep -- forest 41.67s, snow 13.72s,
## the generic 3.64s -- and the only real one-shot among them, grass, sat
## 35dB louder than the quietest of them. One recording per surface also
## meant every step on a surface was the same sample.
##
## So: several real steps per surface, from real recordings of that real
## surface, level-matched to each other by measurement (see
## _VOLUME_DB_BY_SURFACE). A pool is never fewer than 5 deep --
## test_every_surface_has_a_pool_of_real_steps_not_one_recording pins that
## -- because a pool small enough to notice repeating is the problem it was
## built to solve. Paths are DERIVED from the count rather than listed, so
## the two cannot disagree; that the files behind them really exist, really
## load and are really one step long is re-checked against the files
## themselves on every test run.
const _STEPS_DIRECTORY := "res://assets/audio/footsteps/steps"
const _STEP_POOL_SIZES := {
	"default": 9,
	"forest": 8,
	"grass": 9,
	"rock": 10,
	"sand": 6,
	"snow": 8,
	"underwater": 5,
	"wood": 9,
}


## Every real footstep one-shot this surface can play, or an empty array
## for a surface with none sourced yet.
static func step_variants_for(surface: String) -> Array[String]:
	var paths: Array[String] = []
	for index in int(_STEP_POOL_SIZES.get(surface, 0)):
		paths.append("%s/%s_%02d.ogg" % [_STEPS_DIRECTORY, surface, index])
	return paths


## Which of this surface's real steps to take. `roll` is [0, 1] -- the
## caller's own randomness, kept out of here so this stays pure and
## testable, the same split offset_for/pitch_scale_for already use.
##
## Falls back to the one general walking recording for a surface with no
## pool (see FALLBACK_CLIP_PATH), which is then windowed rather than played
## whole -- an unrecognized surface still makes a footstep noise.
static func step_clip_path_for(surface: String, roll: float) -> String:
	var pool := step_variants_for(surface)
	if pool.is_empty():
		return FALLBACK_CLIP_PATH
	# 0.999999, not 1.0: a roll of exactly 1.0 would index one past the end.
	return pool[int(clampf(roll, 0.0, 0.999999) * pool.size())]


# -- one step out of a recording of many ------------------------------------
#
# Reported live: *"Can you find better sounds for the footsteps on every
# terrain? They sound weak and not natural"*.
#
# Measured before touching anything (tools/probe_footstep_levels.gd), and the
# LENGTHS were the whole explanation. A footstep one-shot is ~0.2-0.5s, and
# only grass.ogg is one:
#
#     grass.ogg            0.25s   a real one-shot
#     default.ogg          3.64s   somebody walking
#     snow.mp3            13.72s   somebody walking
#     forest_twigs.ogg    41.67s   somebody walking, for three quarters of a minute
#
# Every step played its clip from 0.0. So a forest step was the same
# fraction of the same run-in, at the same pitch, every single time --
# quiet where the recording had not reached a real impact yet, which is
# "weak", and mechanically identical where it had, which is "not natural".
# The pool's own round-robin then cut each one off mid-ring a second and a
# half later, when four more steps had gone by.
#
# None of that wants better recordings. A 41-second recording of walking is
# already full of real, varied footsteps, recorded on the real surface; it
# just has to be READ one step at a time. So: a window into the bed, a
# different place in it every step, and a few percent of pitch either way.

## How long ONE step is allowed to sound. A real footstep's impact and decay
## is a couple of hundred milliseconds; much beyond that and the tails of
## four voices pile up into a crowd walking behind you, which is the overlap
## the pool's recycling used to cut off mid-ring.
const STEP_WINDOW_SECONDS := 0.45

## How far a step's pitch may swing either way. Small on purpose: a footstep
## that swings a whole semitone reads as a different person's boot rather
## than the same boot on a different patch of ground. Pinned between
## audible and absurd by test_the_pitch_swing_stays_subtle.
const PITCH_VARIATION := 0.06

## The REAL length of every clip long enough to hold more than one step,
## measured off the file with tools/prepare_footstep_oneshots.py. Keyed by
## clip PATH, not by surface: whether a step has to be windowed is a fact
## about the recording being played, not about the ground -- so a pool's own
## one-shots are correctly left alone no matter which surface reaches for
## them, and a surface added to _SURFACE_BY_BIOME tomorrow inherits the
## right answer for the fallback without anybody remembering to list it.
##
## Only the fallback is left in here. The four long recordings this used to
## hold are the four surfaces that now have real steps of their own; the
## forest recording is still in the repository, because the forest pool is
## cut out of it.
##
## Re-measured against the real file on every run by
## test_the_pinned_clip_lengths_are_the_real_files_own, because the offsets
## below are derived from it: a swapped clip nobody re-measured would start
## reading steps off the end of itself.
const CLIP_LENGTH_SECONDS := {
	FALLBACK_CLIP_PATH: 3.64,
}


## Whether this clip is a recording of somebody WALKING, which one step is a
## window into -- rather than a single recorded step, which is played whole.
##
## Twice the step window is the line: a clip that cannot hold two
## non-overlapping steps has no second step to offer, so there is nothing to
## vary and reading it from anywhere but its own beginning would only clip
## the one step it has.
static func is_walking_bed(clip_path: String) -> bool:
	return float(CLIP_LENGTH_SECONDS.get(clip_path, 0.0)) > STEP_WINDOW_SECONDS * 2.0


## Where in the clip this step starts. `roll` is [0, 1] -- the caller's own
## randomness, kept out of here so this stays pure and testable.
##
## Zero for a real one-shot: it is already the step. For a bed, anywhere
## that still leaves a whole window of recording ahead of it, so a step
## never fades out because it ran off the end.
static func offset_for(clip_path: String, roll: float) -> float:
	if not is_walking_bed(clip_path):
		return 0.0
	var length: float = float(CLIP_LENGTH_SECONDS.get(clip_path, 0.0))
	return clampf(roll, 0.0, 1.0) * maxf(length - STEP_WINDOW_SECONDS, 0.0)


## This step's pitch. `roll` is [0, 1]; 0.5 is the clip's own pitch.
static func pitch_scale_for(roll: float) -> float:
	return 1.0 + (clampf(roll, 0.0, 1.0) - 0.5) * 2.0 * PITCH_VARIATION


## A mushroom crushed underfoot (see `World`'s own `crush_mushroom_at`
## call site) asks for its own distinct one-shot, not the ordinary surface
## step sound -- "walking over a mushroom should produce a correct sound",
## reported live as its own explicit case. Left an honest empty gap for a
## while: no genuine squish/crush recording turned up on Wikimedia Commons
## despite a real search effort (its Foley/SFX coverage is thin generally --
## see `_STEP_POOL_SIZES`'s own doc comment above), and this project's own
## real-world-grounding discipline (see docs/concept/soundscape.md's
## pillar 3) argues against forcing an UNASKED-FOR mismatched stand-in (a
## knife-chop, a door-chime) just to fill the slot.
##
## A deliberate Foley stand-in, requested directly by name ("find a
## styrofoam crushing sound and use it for the mushroom crushing sound"),
## is a different case -- crushed styrofoam's crunchy, slightly-compressible
## quality is a real, established Foley substitute technique (the same
## reasoning Foley artists reach for it in film for snow-crunch/bone-break/
## organic-crush sounds), not an arbitrary invented mismatch. Sourced from
## Pixabay (Pixabay Content License -- free to embed in a commercial
## project, no attribution legally required; credited anyway in
## assets/audio/footsteps/CREDITS.md matching this project's own
## convention), not Wikimedia Commons -- Commons genuinely had nothing
## for this, checked directly, not assumed.
const MUSHROOM_CRUSH_CLIP_PATH := "res://assets/audio/footsteps/mushroom_crush.mp3"


## Per-surface volume in dB, MEASURED rather than chosen. Every number in
## here is written down by tools/prepare_footstep_oneshots.py, which decodes
## the real files, and test_every_surfaces_volume_is_the_gain_the_pipeline_
## measured pins this dict against the levels.json it leaves beside the
## clips -- so these cannot drift from the files they describe.
##
## Reported live: *"Can you find better sounds for the footsteps on every
## terrain? They sound weak and not natural"*, and before it *"The grass
## footsteps are way too loud... can you make them fainter?"* Those were one
## problem. The sourced recordings were never level-matched to each other,
## and the spread was 35dB end to end -- grass at -12.59 dBFS RMS against
## the generic walking clip at -47.63. So grass was genuinely too loud and
## everything else was genuinely weak, and no single playback tweak could
## fix both.
##
## Each pool gets ONE gain, so that its MEAN lands on a common target. One
## gain per pool rather than one per clip on purpose: it equalizes between
## surfaces while leaving a soft step softer than a hard one WITHIN a
## surface, which is the variation the recordings were made for.
##
## **The target is loudness, not RMS (corrected 2026-09-19).** Reported
## live: *"pavement footsteps are way too loud ..."* -- and the pools were
## already level-matched, every one within 2.5 dB of a common RMS. The
## complaint was still right, because **RMS is not loudness for an
## impulsive sound.** A footstep is a transient and a hard surface packs
## its energy into a far sharper one: at equal RMS, rock's peaks sat 8.4 dB
## above grass's (crest factor 20.64 dB against 12.28 dB). Measured in
## ITU-R BS.1770 K-weighted loudness -- what EBU R128 normalises broadcast
## audio by, and the standard answer to exactly this failure of RMS -- the
## RMS-matched gains put grass at -33.65 LUFS and rock at -23.80. Pavement
## was running 9.85 dB hot, and sand 13.5.
##
## So the pipeline now matches on K-weighted loudness. The anchor is
## unchanged and is still not a taste call: grass measures what it measures
## and was reported as finally right at -12.0 dB, so the target is DERIVED
## as grass's own loudness plus that -12.0 rather than written down. That
## derivation is what guarantees the one level a person actually signed off
## on cannot drift -- a hardcoded target rounded grass to -12.5 on the
## first run of this switch, moving the only number nobody was entitled to
## move.
##
## Achieved (LUFS): default -33.12, forest -33.16, grass -33.13, rock
## -33.17, sand -33.13, snow -33.09, underwater -33.10, wood -33.15 --
## a spread of 0.08 dB, against 13.5 dB of real loudness difference before.
## Nothing is capped and the loudest peak of any pool is -7.48 dBFS, so
## there is room left for the per-step pitch and volume applied on top.
const _VOLUME_DB_BY_SURFACE := {
	"default": -14.0,
	"forest": -0.9,
	"grass": -12.0,
	"rock": -12.8,
	"sand": -11.1,
	"snow": 1.1,
	"underwater": -14.1,
	"wood": -11.1,
}

## An unrecognized surface (or one with nothing special set) plays at the
## plain default (0dB) rather than silently drifting quieter/louder too.
static func volume_db_for(surface: String) -> float:
	return float(_VOLUME_DB_BY_SURFACE.get(surface, 0.0))
