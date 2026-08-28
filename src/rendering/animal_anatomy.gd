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
	"herbivore", "deer", "horse", "goat", "camel", "reindeer", "sheep",
	"boar", "tapir", "bear",
	"wolf", "lynx", "jaguar", "predator",
	"jackal", "arctic_fox", "mountain_lion", "lion",
	"mouse", "squirrel",
	"venomous_snake", "nonvenomous_snake",
	"lindwurm", "rubezahl", "nyx", "krampus",
	"squallmaw", "coilnecca", "champ",
	"kraken",
]

## Legless species (see the "serpents" profiles below): zero leg_length, so
## ProceduralAnimalAnimation's generic leg-shift walk cycle has nothing to
## move and must give these a whole-body slither instead (see
## SERPENT_SPECIES's use in procedural_animal_animation.gd).
const SERPENT_SPECIES: Array[String] = [
	"venomous_snake", "nonvenomous_snake", "squallmaw", "coilnecca", "champ", "kraken"
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
##   barrel_squareness        0 = a plain oval, 1 = a deep slab-sided barrel
##                            with a level topline. Horses and cattle are
##                            slab-sided; an oval body reads as a dog
##                            (reported: "horses shouldn't have an oval
##                            body... looks more like a dog").
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
		"barrel_squareness": 0.45,
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
		"barrel_squareness": 0.4,
		# 0.8x the horse (see the horse profile's own world_scale) -- a deer
		# reads as clearly smaller than a horse but still a large grazer.
		# Expressed against the horse by test rather than as a free number,
		# so re-sizing the horse keeps the pair in proportion.
		"world_scale": 0.96,
		"body_length": 0.50, "body_height": 0.22, "body_y": 0.46, "shoulder_hump": 0.03,
		"neck_length": 0.20, "neck_thickness": 0.085, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.16, "head_height": 0.11, "muzzle": 0.6, "ear_size": 0.34,
		"leg_length": 0.32, "leg_thickness": 0.042,
		"tail": TAIL_TUFT, "tail_length": 0.07,
		"headgear": HEADGEAR_ANTLERS, "has_mane": false,
	},
	# The tall one: long neck, deep chest, long legs, mane and flowing tail.
	"horse": {
		"barrel_squareness": 0.8,
		# 1.6 * 0.75 -- reported "make the horse ~25% smaller" (it was
		# reading oversized next to everything else once the illustrated
		# sprite replaced the procedural one). world_scale is the single
		# point of control for BOTH the illustrated sprite's on-screen size
		# (IllustratedAnimalSprite.marker_scale multiplies it directly) and
		# the procedural fallback horse still uses for swim/drink/attack --
		# scaling it here keeps every one of a horse's actions the same
		# size as each other, rather than shrinking only what happens to be
		# illustrated and leaving the rest oversized by comparison.
		"world_scale": 1.2, "body_center_x": 0.36,
		# shoulder_hump 0.0 (not the small rise every other grazer gets):
		# unlike the humped rooters below, a horse's topline reads as
		# level -- reported "the horse should have a straighter back". So is
			# neck_attach_height (see ProceduralAnimalSprite._paint_animal):
			# attached near the very top of the back rather than the
			# 0.45-of-the-way-up every other species gets, since a horse's
			# long neck made that lower attachment read as a notch cut into
			# the topline instead of one continuous slope from withers to poll.
		"body_length": 0.52, "body_height": 0.31, "body_y": 0.46, "shoulder_hump": 0.0,
		"neck_length": 0.25, "neck_thickness": 0.13, "neck_carriage": NECK_UPRIGHT, "neck_attach_height": 0.70, "neck_attach_x": 0.90, "neck_direction_override": Vector2(0.72, -0.69),
		# head_length elongated and head_height pulled back in proportion
			# (was 0.20/0.15) for a real equine profile -- long and narrow,
			# not a short round blob -- while staying deeper than the other
		# grazers' (0.11-0.12) so it still has forehead-to-jaw depth, not a
		# flat plank with a muzzle tacked on -- reported "less flat head" /
			# "more horsish".
		"head_length": 0.24, "head_height": 0.13, "muzzle": 0.85, "muzzle_depth": 0.75, "ear_size": 0.18,
		# leg_length shortened (was 0.38, the tallest of any species by a wide
			# margin) -- reported "slightly smaller legs" and, on a first pass
			# that thinned leg_thickness instead, corrected to "shorter legs,
			# not thinner": thickness is unchanged (0.055, same as the
			# original), only the length comes down, and only modestly --
			# still above deer's 0.32, since a horse should still read as
			# leggy, just not to its former exaggerated degree.
			"leg_length": 0.33, "leg_thickness": 0.055, "has_hooves": true,
		"tail": TAIL_FLOWING, "tail_length": 0.26,
		"headgear": HEADGEAR_NONE, "has_mane": true,
	},
	# Compact and stocky, with backswept horns and a beard.
	"goat": {
		"barrel_squareness": 0.5,
		"world_scale": 0.85,
		"body_length": 0.46, "body_height": 0.24, "body_y": 0.50, "shoulder_hump": 0.02,
		"neck_length": 0.14, "neck_thickness": 0.10, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.16, "head_height": 0.12, "muzzle": 0.55, "ear_size": 0.32,
		"leg_length": 0.24, "leg_thickness": 0.05,
		"tail": TAIL_STUB, "tail_length": 0.05,
		"headgear": HEADGEAR_HORNS, "has_mane": false,
	},
	# Rendered with real illustrated art (see IllustratedAnimalSprite), not
	# this procedural body plan -- these fields exist only so profile_for
	# never falls through to the generic herbivore for it, and so
	# world_scale (the one field IllustratedAnimalSprite.marker_scale
	# actually reads) is set deliberately rather than defaulting to 1.0.
	# Compact and stocky like a goat, but hornless and a touch smaller/
	# rounder -- real sheep are shorter-legged and stockier than goats.
	"sheep": {
		"barrel_squareness": 0.55,
		"world_scale": 0.8,
		"body_length": 0.48, "body_height": 0.28, "body_y": 0.50, "shoulder_hump": 0.02,
		"neck_length": 0.10, "neck_thickness": 0.12, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.14, "head_height": 0.12, "muzzle": 0.4, "ear_size": 0.26,
		"leg_length": 0.18, "leg_thickness": 0.055,
		"tail": TAIL_STUB, "tail_length": 0.05,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	# Defined by the hump and a long neck on long legs.
	"camel": {
		"barrel_squareness": 0.6,
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
		"barrel_squareness": 0.55,
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
		"barrel_squareness": 0.55,
		"world_scale": 1.25,
		"body_length": 0.56, "body_height": 0.30, "body_y": 0.56, "shoulder_hump": 0.10,
		"neck_length": 0.07, "neck_thickness": 0.17, "neck_carriage": NECK_LOW,
		"head_length": 0.20, "head_height": 0.13, "muzzle": 0.9, "ear_size": 0.20,
		"leg_length": 0.16, "leg_thickness": 0.06,
		"tail": TAIL_STUB, "tail_length": 0.05,
		"headgear": HEADGEAR_TUSKS, "has_mane": false,
	},
	"tapir": {
		"barrel_squareness": 0.5,
		"world_scale": 1.2,
		"body_length": 0.58, "body_height": 0.29, "body_y": 0.54, "shoulder_hump": 0.05,
		"neck_length": 0.08, "neck_thickness": 0.15, "neck_carriage": NECK_LOW,
		"head_length": 0.19, "head_height": 0.12, "muzzle": 1.0, "ear_size": 0.22,
		"leg_length": 0.20, "leg_thickness": 0.058,
		"tail": TAIL_STUB, "tail_length": 0.04,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	"bear": {
		"barrel_squareness": 0.45,
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
		"barrel_squareness": 0.3,
		"world_scale": 1.0,
		"body_length": 0.54, "body_height": 0.22, "body_y": 0.50, "shoulder_hump": 0.04,
		"neck_length": 0.13, "neck_thickness": 0.115, "neck_carriage": NECK_LEVEL,
		"head_length": 0.18, "head_height": 0.11, "muzzle": 0.8, "ear_size": 0.34,
		"leg_length": 0.28, "leg_thickness": 0.05,
		"tail": TAIL_BUSHY, "tail_length": 0.20,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	"lynx": {
		"barrel_squareness": 0.25,
		"world_scale": 0.8,
		"body_length": 0.46, "body_height": 0.21, "body_y": 0.51, "shoulder_hump": 0.03,
		"neck_length": 0.09, "neck_thickness": 0.11, "neck_carriage": NECK_LEVEL,
		"head_length": 0.15, "head_height": 0.13, "muzzle": 0.3, "ear_size": 0.40,
		"leg_length": 0.26, "leg_thickness": 0.05,
		"tail": TAIL_STUB, "tail_length": 0.07,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	"jaguar": {
		"barrel_squareness": 0.3,
		"world_scale": 1.15,
		"body_length": 0.56, "body_height": 0.23, "body_y": 0.52, "shoulder_hump": 0.05,
		"neck_length": 0.10, "neck_thickness": 0.13, "neck_carriage": NECK_LEVEL,
		"head_length": 0.16, "head_height": 0.14, "muzzle": 0.35, "ear_size": 0.30,
		"leg_length": 0.24, "leg_thickness": 0.058,
		"tail": TAIL_FLOWING, "tail_length": 0.24,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	"predator": {
		"barrel_squareness": 0.3,
		"world_scale": 1.0,
		"body_length": 0.52, "body_height": 0.22, "body_y": 0.51, "shoulder_hump": 0.04,
		"neck_length": 0.11, "neck_thickness": 0.115, "neck_carriage": NECK_LEVEL,
		"head_length": 0.17, "head_height": 0.12, "muzzle": 0.6, "ear_size": 0.34,
		"leg_length": 0.26, "leg_thickness": 0.05,
		"tail": TAIL_BUSHY, "tail_length": 0.18,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	# A small, lean desert/savanna canid -- notably below the wolf's
	# world_scale, comparable to or a touch above the lynx's 0.8. Real
	# jackals carry oversized, pointed ears and long legs relative to their
	# small frame; the tail is a bushy brush, but shorter than a wolf's.
	"jackal": {
		"barrel_squareness": 0.25,
		"world_scale": 0.85,
		"body_length": 0.42, "body_height": 0.18, "body_y": 0.50, "shoulder_hump": 0.03,
		"neck_length": 0.12, "neck_thickness": 0.09, "neck_carriage": NECK_LEVEL,
		"head_length": 0.16, "head_height": 0.10, "muzzle": 0.8, "ear_size": 0.44,
		"leg_length": 0.30, "leg_thickness": 0.04,
		"tail": TAIL_BUSHY, "tail_length": 0.15,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	# The smallest, stockiest of the four -- a real arctic fox is a compact
	# cold-climate canid that minimizes surface area: short legs and a short
	# blunt muzzle (unlike the jackal/wolf's long snout), but a very long
	# bushy tail relative to its small body (wraps around the fox for
	# warmth). Lowest world_scale of the level-backed predators.
	"arctic_fox": {
		"barrel_squareness": 0.35,
		"world_scale": 0.55,
		"body_length": 0.38, "body_height": 0.19, "body_y": 0.50, "shoulder_hump": 0.02,
		"neck_length": 0.08, "neck_thickness": 0.10, "neck_carriage": NECK_LEVEL,
		"head_length": 0.13, "head_height": 0.10, "muzzle": 0.4, "ear_size": 0.26,
		"leg_length": 0.18, "leg_thickness": 0.045,
		"tail": TAIL_BUSHY, "tail_length": 0.22,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	# A large, LEAN big cat -- real cougars are long-bodied and lightly
	# built compared to the stockier, more muscular jaguar. Longer/equal
	# body_length to the jaguar's 0.56 but lower barrel_squareness and
	# shoulder_hump (leaner, less bulky), with the same long TAIL_FLOWING
	# tail.
	"mountain_lion": {
		"barrel_squareness": 0.22,
		"world_scale": 1.05,
		"body_length": 0.58, "body_height": 0.20, "body_y": 0.52, "shoulder_hump": 0.03,
		"neck_length": 0.10, "neck_thickness": 0.11, "neck_carriage": NECK_LEVEL,
		"head_length": 0.16, "head_height": 0.12, "muzzle": 0.35, "ear_size": 0.30,
		"leg_length": 0.25, "leg_thickness": 0.05,
		"tail": TAIL_FLOWING, "tail_length": 0.26,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	# The largest, most powerful predator in the roster (only the bear's
	# creature_info.gd stats outrank it) -- the highest world_scale of any
	# level-backed predator profile. Real male lions have manes; has_mane is
	# genuinely wired to a visual effect (see
	# ProceduralAnimalSprite._paint_animal / _paint_mane), so this actually
	# renders, not just a forward-correctness flag.
	"lion": {
		"barrel_squareness": 0.32,
		"world_scale": 1.3,
		"body_length": 0.60, "body_height": 0.27, "body_y": 0.51, "shoulder_hump": 0.05,
		"neck_length": 0.12, "neck_thickness": 0.16, "neck_carriage": NECK_LEVEL,
		"head_length": 0.18, "head_height": 0.15, "muzzle": 0.45, "ear_size": 0.26,
		"leg_length": 0.27, "leg_thickness": 0.065,
		"tail": TAIL_FLOWING, "tail_length": 0.22,
		"headgear": HEADGEAR_NONE, "has_mane": true,
	},

	# -- serpents -----------------------------------------------------------
	# No legs, no neck, no ears: a long low body and a very long tapering
	# tail. Nothing else in the roster shares this build.
	"venomous_snake": {
		"barrel_squareness": 0.15,
		"world_scale": 0.7,
		"body_length": 0.44, "body_height": 0.10, "body_y": 0.70, "shoulder_hump": 0.0,
		"neck_length": 0.0, "neck_thickness": 0.07, "neck_carriage": NECK_LEVEL,
		"head_length": 0.13, "head_height": 0.07, "muzzle": 0.4, "ear_size": 0.0,
		"leg_length": 0.0, "leg_thickness": 0.0,
		"tail": TAIL_THIN, "tail_length": 0.42,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	"nonvenomous_snake": {
		"barrel_squareness": 0.15,
		"world_scale": 0.7,
		"body_length": 0.42, "body_height": 0.09, "body_y": 0.72, "shoulder_hump": 0.0,
		"neck_length": 0.0, "neck_thickness": 0.065, "neck_carriage": NECK_LEVEL,
		"head_length": 0.12, "head_height": 0.065, "muzzle": 0.4, "ear_size": 0.0,
		"leg_length": 0.0, "leg_thickness": 0.0,
		"tail": TAIL_THIN, "tail_length": 0.40,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},

	# -- Germany-region world bosses (docs/concept/worldbosses.md) ----------
	# All fully-illustrated (see IllustratedAnimalSprite) -- these fields
	# only actually draw during the rare "eat" action, the one action
	# illustrated art has no walk-fallback for (see has_action's own doc
	# comment). world_scale is the field that matters everywhere else: it
	# multiplies the illustrated sprite's on-screen size directly (see
	# IllustratedAnimalSprite.marker_scale), so it's what makes a boss
	# actually read as bigger than an ordinary predator on screen, not just
	# in its health bar.
	# Legless serpentine dragon -- same "no legs, long tapering body" shape
	# as the two snake profiles, scaled up to dragon size.
	"lindwurm": {
		"barrel_squareness": 0.35,
		"world_scale": 2.4,
		"body_length": 0.52, "body_height": 0.16, "body_y": 0.62, "shoulder_hump": 0.0,
		"neck_length": 0.05, "neck_thickness": 0.12, "neck_carriage": NECK_LEVEL,
		"head_length": 0.16, "head_height": 0.11, "muzzle": 0.5, "ear_size": 0.0,
		"leg_length": 0.10, "leg_thickness": 0.06,
		"tail": TAIL_THIN, "tail_length": 0.34,
		"headgear": HEADGEAR_HORNS, "has_mane": false,
	},
	# Storm-boar -- a scaled-up boar build (low, humped, tusked), not a new
	# shape family.
	"rubezahl": {
		"barrel_squareness": 0.55,
		"world_scale": 2.0,
		"body_length": 0.58, "body_height": 0.32, "body_y": 0.56, "shoulder_hump": 0.14,
		"neck_length": 0.07, "neck_thickness": 0.19, "neck_carriage": NECK_LOW,
		"head_length": 0.21, "head_height": 0.14, "muzzle": 0.9, "ear_size": 0.20,
		"leg_length": 0.18, "leg_thickness": 0.07,
		"tail": TAIL_STUB, "tail_length": 0.06,
		"headgear": HEADGEAR_TUSKS, "has_mane": false,
	},
	# Upright torso tapering into a long tail (no legs) -- closest existing
	# shape is a level-backed predator's proportions with a snake-length tail.
	"nyx": {
		"barrel_squareness": 0.35,
		"world_scale": 1.9,
		"body_length": 0.40, "body_height": 0.24, "body_y": 0.48, "shoulder_hump": 0.0,
		"neck_length": 0.14, "neck_thickness": 0.09, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.14, "head_height": 0.12, "muzzle": 0.2, "ear_size": 0.10,
		"leg_length": 0.0, "leg_thickness": 0.0,
		"tail": TAIL_THIN, "tail_length": 0.36,
		"headgear": HEADGEAR_NONE, "has_mane": true,
	},
	# Tall bipedal goat-demon -- goat headgear, but noticeably taller/
	# heavier-necked and longer-legged than the quadruped goat profile to
	# read as an upright figure.
	"krampus": {
		"barrel_squareness": 0.4,
		"world_scale": 2.1,
		"body_length": 0.36, "body_height": 0.34, "body_y": 0.44, "shoulder_hump": 0.05,
		"neck_length": 0.14, "neck_thickness": 0.13, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.16, "head_height": 0.13, "muzzle": 0.5, "ear_size": 0.18,
		"leg_length": 0.34, "leg_thickness": 0.07,
		"tail": TAIL_THIN, "tail_length": 0.14,
		"headgear": HEADGEAR_HORNS, "has_mane": false,
	},

	# -- Easter-egg cameo creatures (docs/concept/easter_eggs.md) -----------
	# Real, procedurally-generated serpentine creatures (ProceduralAnimalSprite
	# -- no illustrated art, unlike the Germany bosses just above), so every
	# proportion here actually draws on screen, not just during a rare "eat"
	# fallback.
	#
	# Squallmaw: "a long, serpentine, furious-looking sea-dragon with a
	# white, mane-like fin crest" -- a scaled-up, low-slung horizontal body
	# plan adapted from lindwurm's legless dragon silhouette (NECK_LEVEL,
	# low body_y), with has_mane true for the fin crest. Strong-apex-
	# predator sized (world_scale above bear's 1.5, the roster's largest
	# ordinary species) but explicitly below every Germany world boss's
	# scale (1.9-2.4) -- see test_squallmaw_is_larger_than_a_bear_but_
	# smaller_than_every_germany_boss.
	"squallmaw": {
		"barrel_squareness": 0.3,
		"world_scale": 1.7,
		"body_length": 0.58, "body_height": 0.15, "body_y": 0.58, "shoulder_hump": 0.0,
		"neck_length": 0.10, "neck_thickness": 0.11, "neck_carriage": NECK_LEVEL,
		"head_length": 0.18, "head_height": 0.12, "muzzle": 0.6, "ear_size": 0.0,
		"leg_length": 0.0, "leg_thickness": 0.0,
		"tail": TAIL_THIN, "tail_length": 0.38,
		"headgear": HEADGEAR_NONE, "has_mane": true,
	},
	# Coilnecca: "gentle, long-necked, placid lake serpent" -- a compact
	# body (mostly submerged; only the neck reads above the waterline) with
	# a long upright neck, the opposite carriage from Squallmaw's low sea-
	# serpent build. No mane, no headgear -- Squallmaw's fin crest is
	# deliberately its own, not shared (see test_only_squallmaw_has_a_
	# mane_like_fin_crest).
	"coilnecca": {
		"barrel_squareness": 0.3,
		"world_scale": 1.1,
		"body_length": 0.34, "body_height": 0.17, "body_y": 0.58, "shoulder_hump": 0.0,
		"neck_length": 0.24, "neck_thickness": 0.09, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.14, "head_height": 0.10, "muzzle": 0.4, "ear_size": 0.0,
		"leg_length": 0.0, "leg_thickness": 0.0,
		"tail": TAIL_THIN, "tail_length": 0.20,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	# Champ: doc-explicit "family resemblance" to Coilnecca (same long-
	# necked lake-serpent premise, same upright carriage) but deliberately
	# NOT identical proportions -- a leaner, slightly smaller build (a
	# shyer, less substantial-looking animal) rather than a bare recolor.
	"champ": {
		"barrel_squareness": 0.25,
		"world_scale": 0.95,
		"body_length": 0.30, "body_height": 0.14, "body_y": 0.58, "shoulder_hump": 0.0,
		"neck_length": 0.20, "neck_thickness": 0.075, "neck_carriage": NECK_UPRIGHT,
		"head_length": 0.12, "head_height": 0.085, "muzzle": 0.4, "ear_size": 0.0,
		"leg_length": 0.0, "leg_thickness": 0.0,
		"tail": TAIL_THIN, "tail_length": 0.24,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},

	# -- Kraken (docs/concept/easter_eggs.md's condition-triggered, higher-
	# stakes entry) ----------------------------------------------------------
	# "Massive, many-tentacled" -- deliberately the single biggest creature
	# in the game (world_scale above every Germany-region world boss's
	# 1.9-2.4 range, see test_kraken_is_larger_than_every_germany_world_boss
	# in test_animal_anatomy.gd), matching the doc's one deliberately
	# higher-stakes entry. AnimalAnatomy has no per-tentacle limb primitive
	# (every profile here is one torso + at most one tail/neck/4 legs), so
	# "many-tentacled" is approximated rather than literally modeled: a
	# thick, heavily-tapered, far-longer-than-usual tail (the single longest
	# in the roster) for a trailing mass of limbs, plus has_mane -- reused
	# here as a writhing fringe around the head/neck rather than Squallmaw's
	# fin crest -- for a crown of shorter tentacles. A documented scope call
	# (no new anatomy field was added for this one creature), not a claim
	# this literally draws N separate tentacles.
	"kraken": {
		"barrel_squareness": 0.25,
		"world_scale": 3.2,
		"body_length": 0.62, "body_height": 0.20, "body_y": 0.56, "shoulder_hump": 0.0,
		"neck_length": 0.12, "neck_thickness": 0.16, "neck_carriage": NECK_LEVEL,
		"head_length": 0.20, "head_height": 0.15, "muzzle": 0.3, "ear_size": 0.0,
		"leg_length": 0.0, "leg_thickness": 0.0,
		"tail": TAIL_THIN, "tail_length": 0.46,
		"headgear": HEADGEAR_NONE, "has_mane": true,
	},

	# -- the small exception ------------------------------------------------
	# Tiny body, oversized ears, long bare tail -- nothing like the others.
	"mouse": {
		"barrel_squareness": 0.2,
		"world_scale": 0.35,
		"body_length": 0.30, "body_height": 0.16, "body_y": 0.62, "shoulder_hump": 0.01,
		"neck_length": 0.03, "neck_thickness": 0.09, "neck_carriage": NECK_LEVEL,
		"head_length": 0.11, "head_height": 0.10, "muzzle": 0.7, "ear_size": 0.62,
		"leg_length": 0.07, "leg_thickness": 0.028,
		"tail": TAIL_THIN, "tail_length": 0.30,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
	# A tree-nut forager (see docs/concept/flora.md's disperser-vs-predator
	# tension) -- a small, short-legged rodent build like mouse's, but
	# notably bigger (world_scale above mouse's 0.35), and defined above all
	# by a real squirrel's single most distinctive real-world feature: a
	# large, bushy tail that is proportionally LONGER relative to its own
	# body than any other profile in the roster, including mouse's own
	# already-long (but thin, cord-like) tail -- see
	# test_squirrel_has_a_bushy_tail_longer_relative_to_its_body_than_anything_else.
	"squirrel": {
		"barrel_squareness": 0.2,
		"world_scale": 0.45,
		"body_length": 0.24, "body_height": 0.15, "body_y": 0.58, "shoulder_hump": 0.01,
		"neck_length": 0.03, "neck_thickness": 0.08, "neck_carriage": NECK_LEVEL,
		"head_length": 0.11, "head_height": 0.10, "muzzle": 0.5, "ear_size": 0.36,
		"leg_length": 0.09, "leg_thickness": 0.032,
		"tail": TAIL_BUSHY, "tail_length": 0.30,
		"headgear": HEADGEAR_NONE, "has_mane": false,
	},
}
