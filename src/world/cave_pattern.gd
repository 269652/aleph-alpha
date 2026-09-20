extends RefCounted

## Palmer's solutional cave morphology: which shape a cave system takes
## (see docs/concept/underground.md "Palmer: how the water gets in decides
## what the cave looks like").
##
## Arthur N. Palmer, "Origin and morphology of limestone caves", GSA
## Bulletin 103 (1991). His central finding is that cave PATTERN follows
## the mode of groundwater RECHARGE -- not rock type, not depth, not age --
## which is why this file is a lookup and CaveRecharge is where the real
## causal work happens. The one thing rock type decides here is whether
## there is a cave at all: no solubility, no solutional cave.

const Lithology = preload("res://src/world/lithology.gd")
const CaveRecharge = preload("res://src/world/cave_recharge.gd")

## No solutional cave forms here at all -- the honest majority answer for
## a planet whose bedrock is ~85% insoluble.
const PATTERN_NONE := "none"

## Dendritic tributaries joining downstream, like a river network in rock.
const PATTERN_BRANCHWORK := "branchwork"

## An angular grid of intersecting fissures on two joint sets.
const PATTERN_NETWORK_MAZE := "network_maze"

## Curvilinear braided loops, like a river's anabranches.
const PATTERN_ANASTOMOTIC := "anastomotic"

## Irregular rooms with branching side passages -- Carlsbad, Lechuguilla.
const PATTERN_RAMIFORM := "ramiform"

## Irregular interconnected cavities with no through-route.
const PATTERN_SPONGEWORK := "spongework"

const PATTERNS: Array[String] = [
	PATTERN_NONE, PATTERN_BRANCHWORK, PATTERN_NETWORK_MAZE,
	PATTERN_ANASTOMOTIC, PATTERN_RAMIFORM, PATTERN_SPONGEWORK,
]

## Branchwork accounts for roughly 57% of the solutional caves in Palmer's
## own survey, with the maze types making up most of the remainder.
##
## Deliberately NOT asserted as an output share of this classifier: what
## fraction of THIS world's caves come out branchwork depends on the real
## global distribution of recharge settings, which the planet's hydrology
## decides, not this mapping. Recorded here as the real figure to check a
## future world-scale survey against (see underground.md's open questions).
const PALMER_BRANCHWORK_SHARE := 0.57

const _PATTERN_BY_RECHARGE := {
	CaveRecharge.MODE_SINKHOLE: PATTERN_BRANCHWORK,
	CaveRecharge.MODE_DIFFUSE: PATTERN_NETWORK_MAZE,
	CaveRecharge.MODE_FLOODWATER: PATTERN_ANASTOMOTIC,
	CaveRecharge.MODE_HYPOGENIC: PATTERN_RAMIFORM,
	CaveRecharge.MODE_MIXING_ZONE: PATTERN_SPONGEWORK,
}

var _lithology := Lithology.new()


## The cave pattern in `rock` under `recharge_mode`, or PATTERN_NONE where
## the rock does not dissolve (or is not a rock this world knows).
func pattern_for(rock: String, recharge_mode: String) -> String:
	if _lithology.solubility_of(rock) <= 0.0:
		return PATTERN_NONE
	return _PATTERN_BY_RECHARGE.get(recharge_mode, PATTERN_NONE)
