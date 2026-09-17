extends RefCounted

## Where one underground layer connects to the next, and what it takes to
## go down (see docs/concept/underground.md "Descent: a pitch, not a
## staircase").
##
## Layers connect through a real aven/pitch: a place where the deeper
## layer's own void geometry happens to open directly under a cell you can
## stand on in the layer above. Nothing is placed and nothing is spawned,
## so finding a way down is a genuine exploration result rather than
## walking onto a staircase -- and in a sparse branchwork region it is
## properly hard, which is the point.
##
## This is geology.md's "reveal-on-entry, reused recursively" taken the
## rest of the way: the same threshold mechanism, applied one layer down,
## with the threshold now supplied by the cave system itself.

const Strata = preload("res://src/world/strata.gd")

## The standing caving safety rule is three independent light sources per
## person, because a cave with no light is not "dark", it is a place you
## cannot leave.
const RECOMMENDED_LIGHT_SOURCES := 3

## What descent actually requires. A deliberate, documented divergence
## from the real standard above: demanding three torches to step down a
## pitch would be tedium rather than tension. The real number is kept so a
## warning can use it, and so the divergence is visible rather than
## silently rounded away.
const MINIMUM_LIGHT_SOURCES := 1


## Whether these two vertically-stacked cells form a pitch: somewhere to
## stand in the upper layer, and a natural passage opening beneath it.
##
## The cell below must be natural VOID specifically, not a mined tunnel.
## Somebody else's working underneath is a real connection too, but it is
## not this mechanism -- a pitch is geology, not construction -- and
## keeping them apart is what lets a worked shaft be gated and claimed
## while a natural aven cannot be.
func is_pitch(upper_kind: String, lower_kind: String) -> bool:
	return Strata.is_walkable(upper_kind) and lower_kind == Strata.KIND_VOID


## Whether the player can actually go down here.
func can_descend(upper_kind: String, lower_kind: String, light_sources: int) -> bool:
	return is_pitch(upper_kind, lower_kind) and light_sources >= MINIMUM_LIGHT_SOURCES


## Whether the player is carrying what real caving practice asks for --
## for a warning, not a gate.
func is_adequately_equipped(light_sources: int) -> bool:
	return light_sources >= RECOMMENDED_LIGHT_SOURCES


## The layer directly beneath this one, or "" at the bottom of the stack
## (or for a layer this world does not have).
func layer_below(layer: String) -> String:
	var index := Strata.LAYERS.find(layer)
	if index < 0 or index >= Strata.LAYERS.size() - 1:
		return ""
	return Strata.LAYERS[index + 1]


## The layer directly above this one, or "" at the top of the stack.
func layer_above(layer: String) -> String:
	var index := Strata.LAYERS.find(layer)
	if index <= 0:
		return ""
	return Strata.LAYERS[index - 1]
