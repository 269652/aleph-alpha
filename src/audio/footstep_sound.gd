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
## floor recording has been sourced either, so "wood" falls back to the
## generic step clip (see `_CLIP_BY_SURFACE`) -- still a better answer
## than the grass clip a wooden floor used to inherit from the ground
## outside it, and a real recording is a welcome upgrade whenever one
## turns up, not a gap in this mapping.
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


const _DEFAULT_CLIP_PATH := "res://assets/audio/footsteps/default.ogg"

## Real, distinct recordings exist (see CREDITS.md) for exactly 4 surfaces
## beyond the generic default: snow (a real snow-walking field recording),
## forest (a real footsteps-in-forest recording -- "twigs cracking in
## forest wood", reported live, is genuinely audible in it), grass (a real
## footstep-on-grass field recording -- "it sounds like a drum, not like
## walking on grass", reported live about the default it used to silently
## share), and underwater (see below). Wikimedia Commons -- this project's
## established sourcing convention (see assets/audio/soundscape/CREDITS.md)
## -- turned out to have very little isolated Foley-style "footstep on X"
## material for the remaining surfaces (sand/rock), and neither did
## Freesound.org (login-gated downloads) or Pixabay (this particular
## grass search hit a bot-check on the actual download, see CREDITS.md);
## rather than force a mismatched clip onto sand/rock just to fill the
## dict, they honestly share the one general walking recording below. A
## real, distinct recording for either is a welcome upgrade whenever one
## turns up -- not a gap in the mixing logic itself, the same "reuse where
## a distinct recording isn't available" shape `NatureSoundscape`'s own
## wind bed already established for desert/tundra/mountain.
##
## `underwater` reuses `river.ogg` from the AMBIENT soundscape's own asset
## directory rather than a second, separately-licensed file -- reported
## live: "river wading should be used for 'underwater walks'". The same
## real flowing-water recording backs both the continuous river-proximity
## bed (NatureSoundscape.RIVER_LAYER, heard nearby) and this one-shot
## footstep (heard when actually standing in it) -- one real asset, two
## real reasons to be heard, not a duplicated file/license entry for the
## same water. A cross-directory reference by design, not an accident.
const _CLIP_BY_SURFACE := {
	"grass": "res://assets/audio/footsteps/grass.ogg",
	"forest": "res://assets/audio/footsteps/forest_twigs.ogg",
	"snow": "res://assets/audio/footsteps/snow.mp3",
	"underwater": "res://assets/audio/soundscape/river.ogg",
}

## An unrecognized surface (or one with no distinct recording sourced yet)
## falls back to one plain, generic step sound rather than staying silent
## -- "we need footsteps", reported live as a general ask, not just for
## the surfaces named specifically.
static func clip_path_for(surface: String) -> String:
	return String(_CLIP_BY_SURFACE.get(surface, _DEFAULT_CLIP_PATH))


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

## Every clip's REAL length, measured off the files with
## tools/probe_footstep_levels.gd. Re-measured against those files on every
## run by test_the_pinned_clip_lengths_are_the_real_files_own, because the
## offsets below are derived from them: a swapped clip nobody re-measured
## would start reading steps off the end of itself.
const CLIP_LENGTH_SECONDS := {
	"grass": 0.25,
	"default": 3.64,
	"snow": 13.72,
	"forest": 41.67,
}


## Whether this surface's clip is a recording of somebody WALKING, which one
## step is a window into -- rather than a single recorded step, which is
## played whole.
##
## Twice the step window is the line: a clip that cannot hold two
## non-overlapping steps has no second step to offer, so there is nothing to
## vary and reading it from anywhere but its own beginning would only clip
## the one step it has.
static func is_walking_bed(surface: String) -> bool:
	return float(CLIP_LENGTH_SECONDS.get(surface, 0.0)) > STEP_WINDOW_SECONDS * 2.0


## Where in the clip this step starts. `roll` is [0, 1] -- the caller's own
## randomness, kept out of here so this stays pure and testable.
##
## Zero for a real one-shot: it is already the step. For a bed, anywhere
## that still leaves a whole window of recording ahead of it, so a step
## never fades out because it ran off the end.
static func offset_for(surface: String, roll: float) -> float:
	if not is_walking_bed(surface):
		return 0.0
	var length: float = float(CLIP_LENGTH_SECONDS.get(surface, 0.0))
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
## see `_CLIP_BY_SURFACE`'s own doc comment above), and this project's own
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


## Per-surface volume ADJUSTMENT in dB, relative to the plain default
## (0dB, i.e. unchanged) -- distinct sourced clips were never level-
## matched to each other (the same "no audio-editing tooling in this
## environment" constraint that already applies to trimming/codec fixes
## elsewhere in this file applies to loudness normalization too), so one
## clip can read noticeably louder or quieter than its neighbours purely
## because of where it happened to be sourced from, not anything about
## the surface itself. Missing from this dict means "play at the default
## volume," not silence -- see volume_db_for's own fallback.
##
## Reported live: "The grass footsteps are way too loud... can you make
## them fainter?" `grass.ogg` (OpenGameArt/Freesound, see CREDITS.md)
## reads noticeably hotter than every other sourced clip here (all from
## Wikimedia Commons or Pixabay). -12dB is a real, deliberate correction,
## not an eyeballed guess: roughly a perceived halving of loudness (a
## well-established audio-engineering rule of thumb -- every -10dB is
## roughly "half as loud" to human hearing -- not a personal preference
## number), a large, clearly-audible cut matching how strongly this was
## reported ("way too loud"). A real re-normalized recording, or a
## measured dB difference against the other clips, would be a genuine
## upgrade over this if either ever turns up -- not a gap in the mixing
## logic itself.
const _VOLUME_DB_BY_SURFACE := {
	"grass": -12.0,
}

## An unrecognized surface (or one with nothing special set) plays at the
## plain default (0dB) rather than silently drifting quieter/louder too.
static func volume_db_for(surface: String) -> float:
	return float(_VOLUME_DB_BY_SURFACE.get(surface, 0.0))
