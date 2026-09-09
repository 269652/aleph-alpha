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

## `biome`/`snow_lying`/`underwater` are the exact same live inputs
## `EarthChunkManager.record_footstep` already computes every step for the
## visual footprint -- pass them straight through, never re-derive. Priority
## mirrors `footstep_surface_for`'s own exactly (snow checked first, then
## underwater, then the plain biome surface) so the two stay intuitively
## consistent even though their surface SETS differ.
static func surface_for(biome: String, snow_lying: bool, underwater: bool) -> String:
	if snow_lying:
		return "snow"
	if underwater:
		return "underwater"
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
