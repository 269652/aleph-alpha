extends RefCounted

## Per-species body proportions, so animals are built from real anatomy
## rather than from a handful of shared hand-drawn bitmaps.
##
## The generator used to key off four hand-authored 24x16 silhouettes
## ("boar_shape", "lynx_shape", "deer_shape", "wolf_shape") with several
## species pointing at each. `herbivore`, `horse`, `deer`, `camel`,
## `reindeer` and `goat` ALL shared "deer_shape" and differed only in coat
## colour -- reported as "herbivore, deer and horse look exactly the same".
##
## Hand-authoring a distinct bitmap per species doesn't scale (and would
## need redrawing at every art resolution), so a species is instead
## described by the proportions that actually distinguish real animals:
## how long the body is, how tall it stands, how long the neck is and where
## it points, what it carries on its head, what its tail does.
## ProceduralAnimalSprite assembles the parts from these.
##
## Every measurement is a FRACTION of the canvas, so one profile draws
## correctly at any art resolution (see docs/concept/art_resolution.md).

## Tail shapes.
const TAIL_NONE := "none"
const TAIL_TUFT := "tuft"        # short upright deer scut
const TAIL_FLOWING := "flowing"  # long horse tail
const TAIL_BUSHY := "bushy"      # wolf/fox brush
const TAIL_THIN := "thin"        # mouse/rat cord
const TAIL_STUB := "stub"        # bear/boar stub

## What the head carries.
const HEADGEAR_NONE := "none"
const HEADGEAR_ANTLERS := "antlers"  # branched, deer/reindeer
const HEADGEAR_HORNS := "horns"      # curved back, goat
const HEADGEAR_TUSKS := "tusks"      # boar

## How the neck is carried: upright grazers vs. head-down rooters vs.
## level-backed predators.
const NECK_UPRIGHT := "upright"
const NECK_LEVEL := "level"
const NECK_LOW := "low"


## Every species with a hand-tuned profile. Anything else falls back to the
## generic herbivore build (see profile_for).
const SPECIES := [
	"herbivore", "deer", "horse", "goat", "camel", "reindeer",
	"boar", "tapir", "bear",
	"wolf", "lynx", "jaguar", "predator",
	"mouse",
	"venomous_snake", "nonvenomous_snake",
]


## The proportions for `species`, or a safe generic build for an unknown
## one (matching this codebase's never-crash-on-an-odd-id convention).
static func profile_for(species: String) -> Dictionary:
	return _PROFILES.get(species, _PROFILES["herbivore"]).duplicate()


static func has_profile(species: String) -> bool:
	return _PROFILES.has(species)


## Field meanings (all canvas fractions unless noted):
##   body_length/body_height  the torso barrel
##   body_y                   how far down the canvas the torso sits
##   shoulder_hump            extra rise over the shoulders (boar, camel, bear)
##   neck_length/neck_thickness/neck_carriage
##   head_length/head_height/muzzle  muzzle 0 = blunt, 1 = long tapering
##   ear_size                 relative to the head
##   leg_length/leg_thickness
##   tail/tail_length, headgear, has_mane
##   world_scale              how big this species is in the WORLD, relative
##                            to a mid-sized grazer at 1.0. Every species is
##                            drawn on one shared canvas, so without this a
##                            mouse, a boar and a horse all came out the same
##                            size on screen -- reported as "a fish is the
##                            size of a boar" and "horses are too small".
const _PROFILES := {
	# -- upright grazers ----------------------------------------------------
	# The generic herbivore: a compact, unremarkable grazer. Deliberately
	# plainer than the named species so they read as distinct FROM it.
	"herbivore": {
		"world_scale": 1.0,
		"body_length": 0.52, "body_height": 0.26, "body_y": 0.50, "shoulder_hump": 0.02,
		"neck_length": 0.16, "neck_thickness": 0.10, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.17, "head_height": 0.13, "muzzle": 0.5, "ear_size": 0.30,
		"leg_length": 0.26, "leg_thickness": 0.055,
		"tail": TAIL_TUFT, "tail_length": 0.08,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	# Slender, fine-boned, antlered, with a short upright scut.
	"deer": {
		"world_scale": 1.15,
		"body_length": 0.50, "body_height": 0.22, "body_y": 0.46, "shoulder_hump": 0.03,
		"neck_length": 0.20, "neck_thickness": 0.085, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.16, "head_height": 0.11, "muzzle": 0.6, "ear_size": 0.34,
		"leg_length": 0.32, "leg_thickness": 0.042,
		"tail": TAIL_TUFT, "tail_length": 0.07,
		"headgear": HEADGEAR_ANTLERS, "has_mane": false,
	},
	# The tall one: long neck, deep chest, long legs, mane and flowing tail.
	"horse": {
		"world_scale": 1.6,
		"body_length": 0.58, "body_height": 0.27, "body_y": 0.42, "shoulder_hump": 0.04,
		"neck_length": 0.26, "neck_thickness": 0.12, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.20, "head_height": 0.11, "muzzle": 0.85, "ear_size": 0.22,
		"leg_length": 0.38, "leg_thickness": 0.055,
		"tail": TAIL_FLOWING, "tail_length": 0.26,
		"headgear": HEADGEAR_NONE, "has_mane": true,
	},
	# Compact and stocky, with backswept horns and a beard.
	"goat": {
		"world_scale": 0.85,
		"body_length": 0.46, "body_height": 0.24, "body_y": 0.50, "shoulder_hump": 0.02,
		"neck_length": 0.14, "neck_thickness": 0.10, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.16, "head_height": 0.12, "muzzle": 0.55, "ear_size": 0.32,
		"leg_length": 0.24, "leg_thickness": 0.05,
		"tail": TAIL_STUB, "tail_length": 0.05,
		"headgear": HEADGEAR_HORNS, "has_mane": false,
	},
	# Defined by the hump and a long neck on long legs.
	"camel": {
		"world_scale": 1.5,
		"body_length": 0.54, "body_height": 0.26, "body_y": 0.44, "shoulder_hump": 0.16,
		"neck_length": 0.28, "neck_thickness": 0.10, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.16, "head_height": 0.10, "muzzle": 0.7, "ear_size": 0.20,
		"leg_length": 0.36, "leg_thickness": 0.05,
		"tail": TAIL_TUFT, "tail_length": 0.09,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	# A heavier deer with a fuller neck and bigger antlers.
	"reindeer": {
		"world_scale": 1.25,
		"body_length": 0.54, "body_height": 0.25, "body_y": 0.47, "shoulder_hump": 0.06,
		"neck_length": 0.18, "neck_thickness": 0.115, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.17, "head_height": 0.12, "muzzle": 0.6, "ear_size": 0.28,
		"leg_length": 0.30, "leg_thickness": 0.052,
		"tail": TAIL_TUFT, "tail_length": 0.06,
		"headgear": HEADGEAR_ANTLERS, "has_mane": false,
	},

	# -- low, bulky rooters -------------------------------------------------
	# Wedge-shaped: massive humped shoulders, head carried low, short legs.
	"boar": {
		"world_scale": 1.25,
		"body_length": 0.56, "body_height": 0.30, "body_y": 0.56, "shoulder_hump": 0.10,
		"neck_length": 0.07, "neck_thickness": 0.17, "neck_carriage": NECK_LOW,
		"head_length": 0.20, "head_height": 0.13, "muzzle": 0.9, "ear_size": 0.20,
		"leg_length": 0.16, "leg_thickness": 0.06,
		"tail": TAIL_STUB, "tail_length": 0.05,
		"headgear": HEADGEAR_TUSKS, "has_mane": false,
	},
	"tapir": {
		"world_scale": 1.2,
		"body_length": 0.58, "body_height": 0.29, "body_y": 0.54, "shoulder_hump": 0.05,
		"neck_length": 0.08, "neck_thickness": 0.15, "neck_carriage": NECK_LOW,
		"head_length": 0.19, "head_height": 0.12, "muzzle": 1.0, "ear_size": 0.22,
		"leg_length": 0.20, "leg_thickness": 0.058,
		"tail": TAIL_STUB, "tail_length": 0.04,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	"bear": {
		"world_scale": 1.5,
		"body_length": 0.58, "body_height": 0.32, "body_y": 0.52, "shoulder_hump": 0.09,
		"neck_length": 0.08, "neck_thickness": 0.18, "neck_carriage": NECK_LOW,
		"head_length": 0.18, "head_height": 0.15, "muzzle": 0.5, "ear_size": 0.24,
		"leg_length": 0.20, "leg_thickness": 0.075,
		"tail": TAIL_STUB, "tail_length": 0.04,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},

	# -- level-backed predators ---------------------------------------------
	"wolf": {
		"world_scale": 1.0,
		"body_length": 0.54, "body_height": 0.22, "body_y": 0.50, "shoulder_hump": 0.04,
		"neck_length": 0.13, "neck_thickness": 0.115, "neck_carriage": NECK_LEVEL,
		"head_length": 0.18, "head_height": 0.11, "muzzle": 0.8, "ear_size": 0.34,
		"leg_length": 0.28, "leg_thickness": 0.05,
		"tail": TAIL_BUSHY, "tail_length": 0.20,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	"lynx": {
		"world_scale": 0.8,
		"body_length": 0.46, "body_height": 0.21, "body_y": 0.51, "shoulder_hump": 0.03,
		"neck_length": 0.09, "neck_thickness": 0.11, "neck_carriage": NECK_LEVEL,
		"head_length": 0.15, "head_height": 0.13, "muzzle": 0.3, "ear_size": 0.40,
		"leg_length": 0.26, "leg_thickness": 0.05,
		"tail": TAIL_STUB, "tail_length": 0.07,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	"jaguar": {
		"world_scale": 1.15,
		"body_length": 0.56, "body_height": 0.23, "body_y": 0.52, "shoulder_hump": 0.05,
		"neck_length": 0.10, "neck_thickness": 0.13, "neck_carriage": NECK_LEVEL,
		"head_length": 0.16, "head_height": 0.14, "muzzle": 0.35, "ear_size": 0.30,
		"leg_length": 0.24, "leg_thickness": 0.058,
		"tail": TAIL_FLOWING, "tail_length": 0.24,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	"predator": {
		"world_scale": 1.0,
		"body_length": 0.52, "body_height": 0.22, "body_y": 0.51, "shoulder_hump": 0.04,
		"neck_length": 0.11, "neck_thickness": 0.115, "neck_carriage": NECK_LEVEL,
		"head_length": 0.17, "head_height": 0.12, "muzzle": 0.6, "ear_size": 0.34,
		"leg_length": 0.26, "leg_thickness": 0.05,
		"tail": TAIL_BUSHY, "tail_length": 0.18,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},

	# -- serpents -----------------------------------------------------------
	# No legs, no neck, no ears: a long low body and a very long tapering
	# tail. Nothing else in the roster shares this build.
	"venomous_snake": {
		"world_scale": 0.7,
		"body_length": 0.44, "body_height": 0.10, "body_y": 0.70, "shoulder_hump": 0.0,
		"neck_length": 0.0, "neck_thickness": 0.07, "neck_carriage": NECK_LEVEL,
		"head_length": 0.13, "head_height": 0.07, "muzzle": 0.4, "ear_size": 0.0,
		"leg_length": 0.0, "leg_thickness": 0.0,
		"tail": TAIL_THIN, "tail_length": 0.42,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	"nonvenomous_snake": {
		"world_scale": 0.7,
		"body_length": 0.42, "body_height": 0.09, "body_y": 0.72, "shoulder_hump": 0.0,
		"neck_length": 0.0, "neck_thickness": 0.065, "neck_carriage": NECK_LEVEL,
		"head_length": 0.12, "head_height": 0.065, "muzzle": 0.4, "ear_size": 0.0,
		"leg_length": 0.0, "leg_thickness": 0.0,
		"tail": TAIL_THIN, "tail_length": 0.40,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},

	# -- the small exception ------------------------------------------------
	# Tiny body, oversized ears, long bare tail -- nothing like the others.
	"mouse": {
		"world_scale": 0.35,
		"body_length": 0.30, "body_height": 0.16, "body_y": 0.62, "shoulder_hump": 0.01,
		"neck_length": 0.03, "neck_thickness": 0.09, "neck_carriage": NECK_LEVEL,
		"head_length": 0.11, "head_height": 0.10, "muzzle": 0.7, "ear_size": 0.62,
		"leg_length": 0.07, "leg_thickness": 0.028,
		"tail": TAIL_THIN, "tail_length": 0.30,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
}
