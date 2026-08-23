extends GutTest

## Food going off in your pack, and what that attracts (see
## docs/concept/flies.md).
##
## A player carrying rotten fruit should draw flies, which needs food to
## actually SPOIL while carried -- otherwise "rotten fruit in your inventory"
## is a state the game can never reach, because a windfall on the ground is
## removed the moment it turns.

const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Item = preload("res://src/gameplay/item.gd")
const FruitSpoilage = preload("res://src/gameplay/fruit_spoilage.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


func _apple(count: int = 1) -> ItemStack:
	return ItemStack.new(Item.new("apple", "Apple", "food", 20), count)


# -- food ages in the pack ---------------------------------------------------

func test_a_fresh_stack_starts_fresh():
	assert_eq(_apple().age_seconds, 0.0)
	assert_almost_eq(_apple().freshness("autumn"), 1.0, 0.001)


func test_carried_food_goes_off_over_time():
	var stack := _apple()
	stack.age(FruitSpoilage.edible_seconds("apple", "autumn") * 0.5)
	assert_lt(stack.freshness("autumn"), 1.0)
	assert_gt(stack.freshness("autumn"), 0.0)


func test_food_left_long_enough_is_rotten():
	var stack := _apple()
	stack.age(FruitSpoilage.edible_seconds("apple", "autumn") * 2.0)
	assert_almost_eq(stack.freshness("autumn"), 0.0, 0.001)
	assert_false(stack.is_edible("autumn"))


## Cold keeps it, the same way it keeps a windfall -- carrying food through
## winter is different from carrying it through summer.
func test_the_season_still_decides_how_fast():
	var summer := _apple()
	var winter := _apple()
	var elapsed := SeasonCycle.SECONDS_PER_DAY * 3.0
	summer.age(elapsed)
	winter.age(elapsed)
	assert_lt(summer.freshness("summer"), winter.freshness("winter"))


## Things that are not food do not rot, however long they are carried.
func test_a_rock_does_not_rot():
	var rock := ItemStack.new(Item.new("rock", "Rock", "material", 20))
	rock.age(SeasonCycle.SECONDS_PER_YEAR)
	assert_almost_eq(rock.freshness("summer"), 1.0, 0.001)
	assert_true(rock.is_edible("summer"), "a rock is not spoiled, it is just a rock")


# -- merging -----------------------------------------------------------------

## Adding fresh fruit to an old stack must not silently refresh it, or a player
## tops up a rotting pile and it becomes new.
func test_merging_fresh_into_old_does_not_reset_the_rot():
	var stack := _apple(1)
	stack.age(FruitSpoilage.edible_seconds("apple", "autumn") * 0.8)
	var was := stack.freshness("autumn")
	stack.merge(1)
	assert_lte(stack.freshness("autumn"), was + 0.001, "topping up should not refresh a stack")


# -- a pack of rot is a thing in the world -----------------------------------

## A player carrying something that has gone over smells of it, which is what
## lets flies follow them.
func test_a_pack_reports_its_worst_food():
	var Inventory := load("res://src/gameplay/inventory.gd")
	var pack = Inventory.new(10)
	pack.add(Item.new("apple", "Apple", "food", 20), 1)
	pack.add(Item.new("rock", "Rock", "material", 20), 1)
	assert_almost_eq(pack.rot_freshness("autumn"), 1.0, 0.001)
	pack.age_contents(FruitSpoilage.edible_seconds("apple", "autumn") * 2.0)
	assert_almost_eq(pack.rot_freshness("autumn"), 0.0, 0.001, "the apple should have gone")


## An empty pack, or one with nothing edible in it, smells of nothing.
func test_a_pack_with_no_food_smells_of_nothing():
	var Inventory := load("res://src/gameplay/inventory.gd")
	var pack = Inventory.new(10)
	pack.add(Item.new("rock", "Rock", "material", 20), 3)
	pack.age_contents(SeasonCycle.SECONDS_PER_YEAR)
	assert_almost_eq(pack.rot_freshness("autumn"), 1.0, 0.001)
