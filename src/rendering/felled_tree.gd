extends RefCounted

## A tree lying where it fell (see docs/concept/woodworking.md).
##
## Felling used to delete the tree and spray items on the ground, which reads
## as the tree evaporating. A tree you cut down should be a THING lying there:
## the same trunk and crown, on its side, waiting to be worked. Worked up in
## real stages -- crown off first (sticks), then the bare trunk either bucked
## by hand into logs or sawn whole into construction lumber -- not one flat
## repeated cut.
##
## Pure numbers and decisions; ChoppableTree owns the node and the state.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## How far over a fallen tree lies, in radians. A quarter turn: on its side.
const FALLEN_ROTATION := PI * 0.5

## How many cuts a bare trunk takes to buck into logs.
##
## More than one, because the point is that a felled tree is WORK rather than a
## loot drop -- and few enough that clearing one is not a chore. Canopy
## removal is a separate step and does not count against this.
const CUTS_TO_CLEAR := 3

## What a full-grown trunk is worth in total timber, and the least any trunk
## gives -- the abstract quantity every per-stage yield below is derived
## from, not itself a drop.
##
## A sapling is not the same haul as an oak -- felling a seedling for a full
## load of timber is what makes a forest feel like scenery rather than a
## resource with a size. But nothing is worth nothing.
const TIMBER_PER_FULL_TREE := 12
const MIN_TIMBER := 2


## Which way this tree topples: left or right, from its own seed, so a cleared
## wood is not a row of trunks all pointing the same way.
static func fall_direction(seed_value: int) -> int:
	return 1 if PixelNoise.range_index(seed_value, 229, 0, 2) == 0 else -1


## How much timber a trunk of this growth holds in total.
static func timber_for(growth_scale: float) -> int:
	var grown := clampf(growth_scale, 0.0, 1.0)
	return maxi(MIN_TIMBER, int(round(float(TIMBER_PER_FULL_TREE) * grown)))


## How many logs one bare-trunk cut yields (the trunk's own timber spread
## evenly across CUTS_TO_CLEAR).
static func logs_per_cut(growth_scale: float) -> int:
	return maxi(1, int(ceil(float(timber_for(growth_scale)) / float(CUTS_TO_CLEAR))))


## Sticks from removing a felled tree's canopy -- a modest fraction of the
## whole tree's timber, not a full cut's worth: limbing the crown is a much
## smaller haul than bucking the trunk itself (see
## docs/concept/woodworking.md's "limbing before bucking").
const CANOPY_STICK_FRACTION := 0.2


static func sticks_from_canopy(growth_scale: float) -> int:
	return maxi(1, int(round(float(timber_for(growth_scale)) * CANOPY_STICK_FRACTION)))


## Sawing the entire remaining bare trunk (`cuts_remaining` rounds' worth) in
## one action, split evenly between beams and planks -- the same log, cut
## for two different purposes (see docs/concept/woodworking.md's "beam vs.
## plank is the same log, cut differently").
static func beams_from_trunk(growth_scale: float, cuts_remaining: int) -> int:
	var total := logs_per_cut(growth_scale) * cuts_remaining
	return maxi(1, total / 2)


static func planks_from_trunk(growth_scale: float, cuts_remaining: int) -> int:
	var total := logs_per_cut(growth_scale) * cuts_remaining
	return maxi(1, total - (total / 2))
