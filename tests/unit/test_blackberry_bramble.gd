extends GutTest

## BlackberryBramble: the forest edge, and what it gives back (docs/concept/
## brambles.md). Sibling to ForestFern -- bracken is what a wood's floor IS,
## a bramble is what it GIVES.
##
## Asked for with the art dropped in, *"And I added blackberry.png"*, and
## then directly: *"Forageable, bearing with the seasons"*.

const BlackberryBramble = preload("res://src/world/blackberry_bramble.gd")
const ForestFern = preload("res://src/world/forest_fern.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

const WIDTH := 16
const HEIGHT := 16


func _biome_all(name: String) -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	biome.fill(name)
	return biome


func _year(season: String) -> float:
	# the middle of the named season, on SeasonCycle's own four-way split
	return (float(SeasonCycle.SEASONS.find(season)) + 0.5) / float(SeasonCycle.SEASONS.size())


func _a_bramble() -> BlackberryBramble:
	return BlackberryBramble.new(11, WIDTH, HEIGHT, _biome_all("forest"))


# -- where it grows ---------------------------------------------------------

func test_brambles_grow_in_woods_and_nowhere_else():
	var none := BlackberryBramble.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	assert_eq(none.get_patch_cells().size(), 0, "a bramble is a woodland plant")
	assert_gt(_a_bramble().get_patch_cells().size(), 0, "a wood has brambles in it")


## Bracken carpets a wood's floor; brambles are scattered through it. The
## ORDERING is the decision, not either literal.
func test_brambles_are_scattered_where_bracken_carpets():
	assert_lt(BlackberryBramble.SEED_CHANCE, ForestFern.SEED_CHANCE)


func test_the_same_seed_grows_the_same_brambles():
	var once := BlackberryBramble.new(42, WIDTH, HEIGHT, _biome_all("forest"))
	var twice := BlackberryBramble.new(42, WIDTH, HEIGHT, _biome_all("forest"))
	assert_eq(once.get_patch_cells(), twice.get_patch_cells())


func test_building_on_a_bramble_clears_it():
	var bramble := _a_bramble()
	var cell: Vector2i = bramble.get_patch_cells()[0]
	bramble.block_cells([cell])
	assert_false(bramble.has_bramble(cell), "a floor is not a thicket")


# -- bearing follows the calendar -------------------------------------------

## The pillar, and the reason this is a pure function of the year: a crop on
## its own unaligned clock is what once put apples under snow.
func test_a_bramble_is_bare_in_winter():
	assert_almost_eq(BlackberryBramble.ripeness_at(_year("winter")), 0.0, 0.001)


func test_a_bramble_carries_no_fruit_in_spring_when_it_is_flowering():
	assert_almost_eq(BlackberryBramble.ripeness_at(_year("spring")), 0.0, 0.001)


func test_fruit_swells_but_is_not_ripe_in_summer():
	var summer := BlackberryBramble.ripeness_at(_year("summer"))
	assert_gt(summer, 0.0, "green fruit is on the cane by midsummer")
	assert_lt(summer, BlackberryBramble.MIN_PICKABLE_RIPENESS, "...but it is not food yet")


func test_fruit_is_ripe_in_autumn():
	assert_gte(BlackberryBramble.ripeness_at(_year("autumn")), BlackberryBramble.MIN_PICKABLE_RIPENESS)


## Ripeness is a NUMBER, not a flag: the sheet draws green, reddening and
## black fruit, and a boolean would make most of those clumps unreachable.
func test_ripeness_climbs_rather_than_flipping():
	var summer := BlackberryBramble.ripeness_at(_year("summer"))
	var autumn := BlackberryBramble.ripeness_at(_year("autumn"))
	assert_gt(autumn, summer, "it ripens through the year rather than switching on")
	assert_between(summer, 0.01, 0.99, "a half-ripe state really exists")


# -- picking ----------------------------------------------------------------

func test_ripe_fruit_can_be_picked():
	var bramble := _a_bramble()
	var cell: Vector2i = bramble.get_patch_cells()[0]
	assert_gt(bramble.pick(cell, _year("autumn"), 0), 0, "autumn brambles feed you")


## Green fruit is not food -- the small lie that would make the world feel
## unserious.
func test_unripe_fruit_cannot_be_picked():
	var bramble := _a_bramble()
	var cell: Vector2i = bramble.get_patch_cells()[0]
	assert_eq(bramble.pick(cell, _year("summer"), 0), 0, "you cannot eat a green one")


func test_nothing_can_be_picked_off_bare_ground():
	var bramble := _a_bramble()
	var bare := Vector2i(WIDTH - 1, HEIGHT - 1)
	bramble.block_cells([bare])
	assert_eq(bramble.pick(bare, _year("autumn"), 0), 0)


## Foraging that refills the moment you walk away is the permanent larder
## flora.md already refuses.
func test_a_patch_picked_this_autumn_gives_nothing_more_this_autumn():
	var bramble := _a_bramble()
	var cell: Vector2i = bramble.get_patch_cells()[0]
	assert_gt(bramble.pick(cell, _year("autumn"), 0), 0, "precondition")
	assert_eq(bramble.pick(cell, _year("autumn"), 0), 0, "the cane is stripped")


## ...but the cane survives, because a bramble is not an annual. The
## calendar is the regrowth timer; there is no second one to tune.
func test_the_same_patch_bears_again_next_year():
	var bramble := _a_bramble()
	var cell: Vector2i = bramble.get_patch_cells()[0]
	assert_gt(bramble.pick(cell, _year("autumn"), 0), 0, "this year")
	assert_gt(bramble.pick(cell, _year("autumn"), 1), 0, "and again the next")


func test_picking_never_kills_the_patch():
	var bramble := _a_bramble()
	var cell: Vector2i = bramble.get_patch_cells()[0]
	bramble.pick(cell, _year("autumn"), 0)
	assert_true(bramble.has_bramble(cell), "the cane is still standing")


# -- and what you come away with is a real item -----------------------------

## A yield that is not in the catalog is a number, not food. Declared beside
## the other wild fruit and stacking like them, so everything that already
## knows what to do with a cherry knows what to do with this.
func test_a_blackberry_is_a_real_food_item():
	const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
	var catalog := ItemCatalog.new()
	assert_true(catalog.has("blackberry"), "picking yields something the game knows")
	var berry = catalog.make("blackberry")
	assert_eq(berry.kind, "food", "a blackberry is food")
	var cherry = catalog.make("cherry")
	assert_eq(berry.max_stack, cherry.max_stack, "it stacks like the other wild fruit")
