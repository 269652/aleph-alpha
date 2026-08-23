extends RefCounted

## The rope between a lassoed animal and whatever holds the other end -- the
## player leading it, or the tree it is tied to (see docs/concept/taming.md).
##
## One model serves both, because "led" and "tied" differ only in where the
## anchor is: a moving player, or a fixed point in the world. The animal is
## free while the rope is slack and pulled back once it is taut, which is what
## makes a led horse trail behind rather than being welded to the player, and
## a tied one graze around its tree rather than standing rigid at the trunk.
##
## Pure and engine-free, like the rest of the taming logic.

## How much rope there is, in world pixels. Longer than a tile, or the animal
## reads as being on a short collar leash pinned to the player; short enough
## that a led animal stays on screen with them.
const ROPE_LENGTH := 44.0


## Which way the rope is pulling the animal, or ZERO while it is slack.
##
## Returns a DIRECTION, never a displacement: the caller moves the animal at
## its own speed through the usual movement gate, so a led animal still walks
## around a tree instead of being dragged through it.
##
## ZERO when the animal is exactly on its anchor rather than normalising a
## zero-length vector -- normalising the residue of two near-equal vectors is
## precisely the ill-conditioned step that produced this project's
## flee-jitter bugs, and it is not going to be reintroduced here.
static func pull_direction(animal: Vector2, anchor: Vector2, length: float) -> Vector2:
	var to_anchor := anchor - animal
	var distance := to_anchor.length()
	if distance <= length or distance < 0.001:
		return Vector2.ZERO
	return to_anchor / distance


static func is_taut(animal: Vector2, anchor: Vector2, length: float) -> bool:
	var distance := animal.distance_to(anchor)
	return distance > length and distance >= 0.001


## The hard limit, applied after the animal has moved: a rope is a rope, and
## whatever the AI wanted, the animal cannot end a frame further from its
## anchor than the rope is long. The pull above is what makes it *walk* back;
## this is what stops a bolting horse simply outrunning its tether in the
## meantime.
##
## Held AT rope length rather than snapped to the anchor, and on the side it
## ran to -- it hit the end of the rope, it was not reeled in.
static func clamped_position(animal: Vector2, anchor: Vector2, length: float) -> Vector2:
	var from_anchor := animal - anchor
	var distance := from_anchor.length()
	if distance <= length or distance < 0.001:
		return animal
	return anchor + from_anchor / distance * length
