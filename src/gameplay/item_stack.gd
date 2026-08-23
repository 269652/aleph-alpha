extends RefCounted

## A count of one item, respecting that item's max_stack. Stacks of the same
## item id can be merged; a merge that would exceed max_stack keeps what fits
## and reports the overflow so the caller can place it elsewhere.

const Item = preload("res://src/gameplay/item.gd")
const FruitSpoilage = preload("res://src/gameplay/fruit_spoilage.gd")

var item: Item
var count: int

## How long this stack has been in existence, in world seconds.
##
## Food goes off in your pack, not just on the ground. Without it "rotten fruit
## in your inventory" is a state the game can never reach -- a windfall is
## removed the moment it turns, so nothing rotten could ever be picked up, and
## a player could never carry something that draws flies.
var age_seconds := 0.0


func _init(an_item: Item, a_count: int = 1) -> void:
	item = an_item
	count = a_count


## Ages this stack. Only food notices.
func age(delta_seconds: float) -> void:
	age_seconds += maxf(delta_seconds, 0.0)


## How sound this stack still is, 1 fresh to 0 rotten. Anything that is not
## food is always 1 -- a rock is not spoiled, it is just a rock.
func freshness(season: String) -> float:
	if item.kind != "food":
		return 1.0
	return FruitSpoilage.freshness(item.id, age_seconds, season)


func is_edible(season: String) -> bool:
	return item.kind != "food" or FruitSpoilage.is_edible(item.id, age_seconds, season)


func can_stack_with(other) -> bool:
	return item.id == other.item.id


func remaining_capacity() -> int:
	return item.max_stack - count


## Adds up to remaining_capacity of `amount` into this stack; returns the
## amount that did not fit.
func merge(amount: int) -> int:
	var space := remaining_capacity()
	var moved := mini(space, amount)
	count += moved
	return amount - moved
