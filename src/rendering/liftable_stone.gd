extends Node2D

## A stone small enough to pick up (see docs/concept/stone.md).
##
## The other half of the pillar: if you can lift it, you take it. A pebble or
## a cobble goes straight into your hands -- no swing, no tool, no cooldown --
## while anything above the cobble/boulder line is a SmashableStone instead.
##
## It joins the group DroppedItem uses and answers `pick_up`, so the existing
## pickup sweep (Player.pickup_nearby, default E) collects it with no special
## case of its own. Loose stone on the ground IS a ground item; the only thing
## that makes it different is that the world placed it rather than a player
## dropping it.
##
## Deliberately NOT a StaticBody2D: you walk over a pebble rather than around
## it. Only boulders block.

const Item = preload("res://src/gameplay/item.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## How big this stone is, in centimetres -- decides how much rock it is worth
## (see StoneSize.rock_yield). Set by StoneRenderer from the stone's own seed.
var diameter_cm := 3.0

## Deterministic per-stone seed, kept for parity with SmashableStone so the
## two can be swapped without the caller caring which it built.
var stone_seed := 0

## Which PixelNoise "channel" the per-contact dispersion roll reads from --
## distinct from every other channel this seed is used on elsewhere (e.g.
## StoneRenderer's flock-member wobble uses channel 12), so the roll doesn't
## just replay a value already spent on something else for the same seed.
const DISPERSE_ROLL_CHANNEL := 20

## How many times try_disperse has actually rolled a contact for this stone
## (see try_disperse). NOT a one-shot "has this ever kicked" flag -- every
## contact rolls again, so a stone can keep drifting further across many
## walkovers (see PebbleDispersion's own doc comment on the corrected
## design). Advances on every contact within trigger range, whether or not
## that particular roll actually nudges it, so the SAME contact is never
## rolled twice.
var _disperse_contact_count := 0


func _ready() -> void:
	add_to_group(DroppedItem.GROUP_NAME)


## Rolls whether THIS contact nudges the stone a small distance away from
## `walker_position` (see PebbleDispersion.dispersion_chance,
## docs/concept/stone.md) -- mass-weighted, and rolled fresh every time
## something stands close enough, not gated behind a one-time lifetime flag.
## Applies uniformly to every liftable stone, flock member or solitary
## pebble alike -- a lone pebble underfoot is exactly as real as one sitting
## in a cluster, and singling out flock membership would need tracking a
## property nothing else needs. The roll is hash-derived from this stone's
## own seed and its own advancing contact count (PixelNoise, not Godot's
## global RNG) -- deterministic and reproducible like every other seeded
## pick in this codebase, while still varying contact to contact. Returns
## whether it actually moved this call.
func try_disperse(walker_position: Vector2) -> bool:
	if not PebbleDispersion.is_within_trigger(walker_position, position):
		return false
	var roll := PixelNoise.unit(stone_seed, _disperse_contact_count, DISPERSE_ROLL_CHANNEL)
	_disperse_contact_count += 1
	var chance := PebbleDispersion.dispersion_chance(StoneSize.mass_kg_for(diameter_cm))
	if roll >= chance:
		return false
	position = PebbleDispersion.nudge(walker_position, position)
	return true


## Takes this stone into `picker`'s inventory. Returns whether anything was
## collected -- a stone that does not fit stays on the ground rather than
## being silently destroyed.
func pick_up(picker) -> bool:
	if picker == null or picker.inventory == null:
		return false
	var count := StoneSize.rock_yield(diameter_cm)
	var overflow: int = picker.inventory.add(Item.new("rock", "Rock", "material", 20), count)
	if overflow >= count:
		return false
	queue_free()
	return true
