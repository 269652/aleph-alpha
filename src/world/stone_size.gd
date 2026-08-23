extends RefCounted

## How big a loose stone is, and what that means for taking it (see
## docs/concept/stone.md).
##
## Pure and engine-free like the rest of the world modules: this decides SIZE,
## whether a stone is lifted or broken, how much breaking it takes and what it
## yields. Spawning the node and moving the rock into an inventory is the
## caller's job.
##
## ## The pillar
##
## If you can lift it, you take it. If you can't, you break it. The divide is
## a physical question about the stone, not a tag on it -- so a player can
## look at a rock and know what to do with it without being told.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")

## ## The Wentworth grain-size scale
##
## The standard geological classification, used rather than invented tiers.
## Granule 2-4mm, pebble 4-64mm, cobble 64-256mm, boulder above that.
##
## The lift/smash line falls at the cobble-boulder boundary because that is
## roughly where a rock stops being liftable -- which is exactly why the scale
## puts a boundary there. The game rule and the real classification agree
## because they are answering the same question.
const CLASS_PEBBLE := "pebble"
const CLASS_COBBLE := "cobble"
const CLASS_BOULDER := "boulder"

const PEBBLE_MAX_CM := 6.4
const COBBLE_MAX_CM := 25.6

## The range that actually turns up on the ground. Granules (below 4mm) are
## too small to be worth a node, and a boulder above two metres would be
## terrain rather than a thing you interact with.
const SMALLEST_CM := 1.0
const LARGEST_CM := 200.0


static func class_for(diameter_cm: float) -> String:
	if diameter_cm <= PEBBLE_MAX_CM:
		return CLASS_PEBBLE
	if diameter_cm <= COBBLE_MAX_CM:
		return CLASS_COBBLE
	return CLASS_BOULDER


## Whether this stone goes straight into your hands.
static func is_liftable(diameter_cm: float) -> bool:
	return diameter_cm <= COBBLE_MAX_CM


## Whether this stone has to be broken into pieces you can carry. Exactly the
## complement of is_liftable -- every stone is one or the other, never both
## and never neither.
static func must_be_smashed(diameter_cm: float) -> bool:
	return not is_liftable(diameter_cm)


# -- what the ground is made of ----------------------------------------------

## How steeply small stone outnumbers large.
##
## Real scree follows a power law: the ground is mostly small stone with the
## occasional large one, and that distribution is what makes a landscape read
## as eroded rather than placed. A uniform roll would make boulders as common
## as pebbles, which is what a world made of props looks like.
##
## Raising this makes small stone commoner still. Pinned by
## test_small_stone_is_far_commoner_than_large and test_every_class_turns_up,
## which bracket it from both sides: too low and the ground is all boulders,
## too high and a boulder never appears at all.
const SIZE_DISTRIBUTION_POWER := 6.0


## This stone's diameter in centimetres, from its own seed. Fixed for the
## stone's life -- a rock does not change size while you look at it.
static func diameter_for(seed_value: int) -> float:
	var roll := float(PixelNoise.range_index(seed_value, 3, 0, 1000)) / 999.0
	# Biased toward the small end: a uniform roll raised to a power spends
	# most of its range near zero.
	var biased := pow(roll, SIZE_DISTRIBUTION_POWER)
	return SMALLEST_CM + biased * (LARGEST_CM - SMALLEST_CM)


## A flock member's own diameter (see StonePlacement.flock_size_at,
## docs/concept/stone.md), bounded to the PEBBLE range specifically rather
## than the whole scale diameter_for draws from.
##
## A flock is a cluster of PEBBLES: each member is independently seeded so
## the cluster doesn't read as one pebble cloned several times, but that
## independence must not be able to roll a cobble- or boulder-sized member by
## chance -- a flock member is always built as a LiftableStone with no
## boulder fallback, so anything above PEBBLE_MAX_CM here would silently
## break the lift/smash pillar for that member.
##
## Same biased-toward-small curve as diameter_for, on a different PixelNoise
## channel (4, not 3) so a member's own size doesn't just track diameter_for's
## roll for the same seed.
static func pebble_diameter_for(seed_value: int) -> float:
	var roll := float(PixelNoise.range_index(seed_value, 4, 0, 1000)) / 999.0
	var biased := pow(roll, SIZE_DISTRIBUTION_POWER)
	return SMALLEST_CM + biased * (PEBBLE_MAX_CM - SMALLEST_CM)


# -- size is worth something -------------------------------------------------

## The most swings any boulder can take. A rock that takes thirty swings is a
## chore rather than a decision, so the largest is real work and still worth
## starting.
const MAX_HITS := 6

## The fewest a boulder can take. A boulder you break in one tap is not a
## boulder -- which is what these were before size existed: one hit, one rock,
## regardless of being drawn as a rock the size of a person.
const MIN_HITS := 2


## How many strikes this stone takes to break. Liftable stone is not smashed
## at all and answers zero.
static func hits_to_smash(diameter_cm: float) -> int:
	if is_liftable(diameter_cm):
		return 0
	var across := clampf(
		(diameter_cm - COBBLE_MAX_CM) / (LARGEST_CM - COBBLE_MAX_CM), 0.0, 1.0
	)
	return MIN_HITS + int(floor(across * float(MAX_HITS - MIN_HITS) + 0.5))


## How much rock this stone is worth.
##
## Proportional to the stone's SIZE ACROSS, which is a deliberate compression
## of the truth: rock is volume, and volume goes as the cube, so at true scale
## a 2m boulder would be worth something like half a million pebbles. Nothing
## about that would be playable. Scaling with diameter instead keeps a big
## boulder clearly the better haul without making small stone pointless.
const ROCK_PER_LARGEST := 20


static func rock_yield(diameter_cm: float) -> int:
	var ratio := clampf(diameter_cm / LARGEST_CM, 0.0, 1.0)
	return maxi(1, int(floor(ratio * float(ROCK_PER_LARGEST) + 0.5)))


# -- how big it looks --------------------------------------------------------

## Read against the PLAYER, as everything else in this world is (see
## ProceduralFlowerSprite, where flowers are pinned to the player's hip). The
## character's own height comes from the rule CharacterView uses -- two thirds
## of a full-grown tree -- rather than a second copy of the number.
const PLAYER_HEIGHT_FRACTION_OF_TREE := 2.0 / 3.0
const PLAYER_WORLD_HEIGHT_PX := (
	PLAYER_HEIGHT_FRACTION_OF_TREE * float(ProceduralTreeSprite.WORLD_SIZE.y)
)

## A person is this tall, so a stone this wide stands as tall as the player.
## The largest boulder is deliberately set to it.
const PLAYER_HEIGHT_CM := 175.0

## A reasonable average adult total body mass, kilograms -- the reference an
## anthropometric FRACTION (see LEG_MASS_KG) is taken against, the same way
## PLAYER_HEIGHT_CM is a reasonable reference height rather than any specific
## measurement.
const AVERAGE_BODY_MASS_KG := 70.0

## What fraction of total body mass one leg (thigh+shank+foot) is, in real
## anthropometric mass-distribution tables (Winter's "Biomechanics and Motor
## Control of Human Movement" and similar segment-mass tables put a single
## leg at roughly 16-17% of total body mass). 0.165 splits the difference.
const LEG_MASS_FRACTION := 0.165

## One human leg's real mass, kilograms -- the "kicks a pebble far until it's
## too heavy" cutoff (see Kick/PebbleDispersion): a stone whose own mass
## exceeds roughly this is too heavy for a kick's delivered momentum to
## meaningfully move, the same momentum-vs-own-mass logic the rest of the
## shared damage model already uses (see docs/concept/materials.md).
const LEG_MASS_KG := AVERAGE_BODY_MASS_KG * LEG_MASS_FRACTION

## Small stone is exaggerated toward legibility, small ones most, exactly as
## small flowers are: a true-scale 1cm pebble is a twentieth of a pixel. The
## exponent below 1 lifts the small end while preserving the ordering (pinned
## by test_drawing_never_reorders_the_sizes).
const SIZE_EXAGGERATION := 0.45

## No stone draws below this, however small the real thing is.
const MINIMUM_READABLE_HEIGHT_PX := 1.0


## How tall a stone of this diameter stands in the world, in pixels.
static func world_height_px(diameter_cm: float) -> float:
	var ratio := clampf(diameter_cm / LARGEST_CM, 0.0, 1.0)
	# LARGEST_CM (200) is a little over a person (175), so the largest boulder
	# comes out a shade above player height; that is the intent -- it is the
	# landmark of the size range.
	var full_height := PLAYER_WORLD_HEIGHT_PX * (LARGEST_CM / PLAYER_HEIGHT_CM)
	return maxf(full_height * pow(ratio, SIZE_EXAGGERATION), MINIMUM_READABLE_HEIGHT_PX)


# -- real mass, for the shared momentum model --------------------------------
#
# docs/concept/materials.md's "one damage model for the whole world":
# momentum = mass * velocity (see impact_resolver.gd, throwable.gd). A stone
# needs a real mass to take part in that model at all -- kicking, throwing,
# and the leg-mass kick cutoff (see PebbleDispersion/Kick) all read from this.

## Granite's real density, grams per cubic centimetre. A standard geology
## reference value (granite: ~2.6-2.7 g/cm^3); 2.7 is the commonly cited
## figure and lines up with this project's own "stone" material density
## (2.5, see material_properties.gd) being a deliberately-rounded "8-bit"
## simplification of the same real rock.
const GRANITE_DENSITY_G_PER_CM3 := 2.7

## A loose stone's mass in kilograms, treating it as a sphere of the given
## diameter: mass = density * volume, volume = (4/3) * pi * r^3. Real physics,
## not an eyeballed number -- see test_mass_kg_for_matches_the_sphere_volume_formula
## for the exact formula this is pinned against, and
## test_mass_kg_for_a_small_pebble_is_a_plausible_fraction_of_a_kilogram /
## test_mass_kg_for_a_large_boulder_is_plausible_tonnes for sanity checks at
## both ends of the real size range.
static func mass_kg_for(diameter_cm: float) -> float:
	var radius_cm := diameter_cm / 2.0
	var volume_cm3 := (4.0 / 3.0) * PI * radius_cm * radius_cm * radius_cm
	var mass_g := volume_cm3 * GRANITE_DENSITY_G_PER_CM3
	return mass_g / 1000.0
