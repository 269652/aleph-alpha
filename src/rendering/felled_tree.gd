extends RefCounted

## A tree lying where it fell (see docs/concept/flora.md).
##
## Felling used to delete the tree and spray items on the ground, which reads
## as the tree evaporating. A tree you cut down should be a THING lying there:
## the same trunk and crown, on its side, waiting to be worked up.
##
## Pure numbers and decisions; ChoppableTree owns the node and the state.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## How far over a fallen tree lies, in radians. A quarter turn: on its side.
const FALLEN_ROTATION := PI * 0.5

## How many cuts a fallen trunk takes to work up into logs.
##
## More than one, because the point is that a felled tree is WORK rather than a
## loot drop -- and few enough that clearing one is not a chore.
const CUTS_TO_CLEAR := 3

## What a full-grown trunk is worth, and the least any trunk gives.
##
## A sapling is not the same haul as an oak -- felling a seedling for a full
## load of timber is what makes a forest feel like scenery rather than a
## resource with a size. But nothing is worth nothing.
const WOOD_PER_FULL_TREE := 12
const MIN_WOOD := 2


## Which way this tree topples: left or right, from its own seed, so a cleared
## wood is not a row of trunks all pointing the same way.
static func fall_direction(seed_value: int) -> int:
	return 1 if PixelNoise.range_index(seed_value, 229, 0, 2) == 0 else -1


## How much wood a trunk of this growth is worth.
static func wood_for(growth_scale: float) -> int:
	var grown := clampf(growth_scale, 0.0, 1.0)
	return maxi(MIN_WOOD, int(round(float(WOOD_PER_FULL_TREE) * grown)))


## How much of that comes out of one cut.
static func wood_per_cut(growth_scale: float) -> int:
	return maxi(1, int(ceil(float(wood_for(growth_scale)) / float(CUTS_TO_CLEAR))))
