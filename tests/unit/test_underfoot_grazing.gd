extends GutTest

## The underfoot bite, which used to be a free lunch (see
## docs/concept/ground_cover.md, "The grazing lawn is food").
##
## `_take_forage_bite`'s FOOD_UNDERFOOT branch read, in full: "it is standing
## in its food; there is nothing to remove". So a hungry animal on grassland
## was fed, the world lost nothing, and a meadow had no carrying capacity --
## the one bite in the game that could never fail.

const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const GrazerForaging = preload("res://src/gameplay/grazer_foraging.gd")


## A world that either has sward underfoot or does not, and counts the bites.
class SwardStubWorld:
	extends Node2D
	var has_sward := true
	var crops := 0

	func crop_sward_at(_pixel: Vector2) -> bool:
		crops += 1
		return has_sward


var marker: CreatureMarker
var world: SwardStubWorld


func before_each():
	world = SwardStubWorld.new()
	add_child(world)
	marker = CreatureMarker.new()
	marker.info = CreatureInfo.new("horse")
	marker.info.health = 100.0
	marker.info.max_health = 100.0
	marker._world = world
	marker._has_forage_target = true
	marker._forage_kind = GrazerForaging.FOOD_UNDERFOOT
	marker._forage_target = Vector2.ZERO


func after_each():
	marker.free()
	remove_child(world)
	world.free()


func test_an_underfoot_bite_actually_crops_the_sward():
	marker._take_forage_bite()
	assert_eq(world.crops, 1, "the animal ate without the ground losing anything")


func test_a_fed_animal_is_no_longer_hungry():
	marker._needs.hunger = 1.0
	marker._take_forage_bite()
	assert_lt(marker._needs.hunger, 1.0)


## The loop: on ground that has been eaten bare, the bite FAILS -- so the
## animal stays hungry and has to move on. This is where carrying capacity
## comes from, and it is the assertion the old branch could not have passed.
func test_a_bite_of_bare_ground_does_not_feed():
	world.has_sward = false
	marker._needs.hunger = 1.0
	marker._take_forage_bite()
	assert_eq(marker._needs.hunger, 1.0, "the animal fed on ground with nothing on it")
