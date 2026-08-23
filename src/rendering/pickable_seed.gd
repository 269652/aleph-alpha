extends Sprite2D

## A seed lying on the ground that the player can pick up.
##
## Seeds were already real things in the world -- drawn, and eaten by birds --
## but the player could only watch them. A seed you can take is what makes
## deliberate planting possible: gather seed from a meadow, carry it, and sow
## it where you want the flowers.
##
## It joins the group DroppedItem uses and answers `pick_up`, so the existing
## pickup sweep (Player.pickup_nearby, default E) collects it with no special
## case of its own -- the same trick LiftableStone uses. A seed on the ground
## IS a ground item; the only difference is that the world grew it rather than
## a player dropping it.

const Item = preload("res://src/gameplay/item.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")

## Which flower this seed came from, and where it lies, so the world can be
## told to remove it when someone takes it.
var species := ""
var cell := Vector2i.ZERO

## The patch this seed belongs to. Duck-typed for take_seed_at_cell, the same
## way the flyers' worm_world and fruit_world are.
var seed_world = null


func _ready() -> void:
	add_to_group(DroppedItem.GROUP_NAME)


## Takes this seed into `picker`'s inventory.
##
## Returns whether anything was collected -- a seed that does not fit stays on
## the ground rather than being silently destroyed, which is the same contract
## DroppedItem and LiftableStone both keep.
func pick_up(picker) -> bool:
	if picker == null or picker.inventory == null or species == "":
		return false
	var item := Item.new("%s_seed" % species, "%s Seed" % species.capitalize(), "seed", 40)
	if picker.inventory.add(item, 1) > 0:
		return false
	# Taken from the patch as well as from the screen: a seed picked up must
	# not still be lying there for a bird to eat, or for the rain to root.
	if seed_world != null and seed_world.has_method("take_seed_at_cell"):
		seed_world.take_seed_at_cell(cell)
	queue_free()
	return true
