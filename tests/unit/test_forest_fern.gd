extends GutTest

## ForestFern: the fourth of this world's ground-cover simulations, and the
## first one a wood ever had (docs/concept/ferns.md). Asked for directly:
## *"can you wire it and make it grow in forest biome"*.
##
## Shaped like DesertScrub and TundraLichen, which are shaped like TallGrass
## -- deliberately, per this project's "three similar things beats a
## premature abstraction" convention. What is pinned here is what is
## genuinely the FERN's: the biome it seeds on, and every flavour ordering
## against the grass it is modelled on, so a tuning change that quietly made
## ferns carpet a wood faster than grass carpets a meadow fails here rather
## than on screen.

const ForestFern = preload("res://src/world/forest_fern.gd")
const TallGrass = preload("res://src/world/tall_grass.gd")

const WIDTH := 8
const HEIGHT := 8


func _biome_all(name: String) -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	biome.fill(name)
	return biome


func _biome_half_forest() -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			biome[y * WIDTH + x] = "forest" if x < WIDTH / 2 else "grassland"
	return biome


# -- where a fern grows ------------------------------------------------------

func test_no_ferns_grow_where_there_is_no_wood():
	var ferns := ForestFern.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	assert_eq(ferns.get_patch_cells().size(), 0, "a meadow is not a fern's ground")


func test_ferns_grow_only_on_forest_cells():
	var ferns := ForestFern.new(1, WIDTH, HEIGHT, _biome_half_forest())
	assert_gt(ferns.get_patch_cells().size(), 0, "a wood must carry some")
	for cell in ferns.get_patch_cells():
		assert_lt(cell.x, WIDTH / 2, "%s is out in the open" % str(cell))


func test_the_same_wood_grows_the_same_ferns_every_time():
	var a := ForestFern.new(7, WIDTH, HEIGHT, _biome_all("forest"))
	var b := ForestFern.new(7, WIDTH, HEIGHT, _biome_all("forest"))
	assert_eq(a.get_patch_cells(), b.get_patch_cells())


func test_two_different_woods_grow_different_ferns():
	var a := ForestFern.new(1, WIDTH, HEIGHT, _biome_all("forest"))
	var b := ForestFern.new(2, WIDTH, HEIGHT, _biome_all("forest"))
	assert_ne(a.get_patch_cells(), b.get_patch_cells())


# -- the flavour, pinned against the grass it is modelled on -----------------

## An understorey is shaded and broken by trunks; a meadow is wall to wall.
func test_a_wood_floor_is_sparser_than_a_meadow():
	assert_lt(ForestFern.SEED_CHANCE, TallGrass.SEED_CHANCE)


## A frond takes a season where a blade takes days.
func test_a_frond_grows_more_slowly_than_a_blade():
	assert_lt(ForestFern.GROWTH_RATE, TallGrass.GROWTH_RATE)


## A fern creeps by rhizome; grass casts seed.
func test_ferns_creep_where_grass_spreads():
	assert_gt(ForestFern.SPREAD_INTERVAL, TallGrass.SPREAD_INTERVAL)


## The cap has to be able to hold the density the seed chance asks for on a
## real full chunk, or spreading is dead on arrival in a wood -- the exact
## trap TallGrass.MAX_PATCHES' own doc comment records paying for once.
func test_the_cap_can_hold_the_density_it_asks_for_on_a_real_chunk():
	var chunk := 32
	assert_gte(
		ForestFern.MAX_PATCHES, int(ceil(chunk * chunk * ForestFern.SEED_CHANCE)),
		"seeding alone would hit the cap, leaving plant() and spread permanently unable to succeed"
	)


# -- growing, spreading, cropping --------------------------------------------

## A YOUNG clump, deliberately: the stands a wood is seeded with start
## mature, exactly as map-generated trees and grass do, so asking one of
## those to grow is asking it to exceed 1.0. What grows is what has just
## taken root.
func test_a_young_fern_grows_toward_maturity():
	var ferns := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"))
	var cell := _a_bare_cell(ferns)
	assert_true(ferns.plant(cell), "precondition: there is bare wood floor to plant on")
	var before: float = ferns.get_growth(cell)
	ferns.advance(1.0, 1.0)
	assert_gt(ferns.get_growth(cell), before)


## And the stands a wood starts with ARE mature, which is the reason above.
func test_the_stands_a_wood_is_seeded_with_are_already_grown():
	var ferns := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"))
	for cell in ferns.get_patch_cells():
		assert_almost_eq(ferns.get_growth(cell), 1.0, 0.0001, str(cell))


func _a_bare_cell(ferns) -> Vector2i:
	for y in HEIGHT:
		for x in WIDTH:
			if not ferns.has_fern(Vector2i(x, y)):
				return Vector2i(x, y)
	fail_test("this wood is entirely ferns")
	return Vector2i.ZERO


func test_a_fern_never_grows_past_full():
	var ferns := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"))
	for _tick in 500:
		ferns.advance(10.0, 1.0)
	for cell in ferns.get_patch_cells():
		assert_lte(ferns.get_growth(cell), 1.0, str(cell))


func test_mature_ferns_creep_into_the_wood_beside_them():
	var ferns := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"))
	for _tick in 200:
		ferns.advance(ForestFern.SPREAD_INTERVAL, 1.0)
	assert_gt(ferns.get_patch_cells().size(), 0)


func test_a_wood_never_holds_more_ferns_than_its_cap():
	var ferns := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"))
	for _tick in 400:
		ferns.advance(ForestFern.SPREAD_INTERVAL, 1.0)
	assert_lte(ferns.get_patch_cells().size(), ForestFern.MAX_PATCHES)


func test_cropping_a_fern_takes_it():
	var ferns := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"))
	var cell: Vector2i = ferns.get_patch_cells()[0]
	assert_true(ferns.graze(cell))
	assert_false(ferns.has_fern(cell))
	assert_false(ferns.graze(cell), "there is nothing left to crop")


# -- the floor of a building grows nothing ----------------------------------
#
# The same rule every other ground cover has (docs/concept/building.md's
# "Placement rules"; reported directly: "grass must be cut before and can't
# grow back inside a house"), through the same seam.

func test_a_blocked_cell_loses_its_fern_and_never_takes_another():
	var ferns := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"))
	var cell: Vector2i = ferns.get_patch_cells()[0]
	ferns.block_cells([cell])
	assert_false(ferns.has_fern(cell))
	assert_false(ferns.plant(cell), "nothing roots through a floor")


func test_unblocking_gives_the_ground_back():
	var ferns := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"))
	var cell: Vector2i = ferns.get_patch_cells()[0]
	ferns.block_cells([cell])
	ferns.unblock_cells([cell])
	assert_true(ferns.plant(cell), "bare wood floor again")


func test_nothing_plants_outside_the_wood():
	var ferns := ForestFern.new(3, WIDTH, HEIGHT, _biome_half_forest())
	assert_false(ferns.plant(Vector2i(WIDTH - 1, 0)), "that cell is grassland")


func test_a_planted_fern_starts_as_a_shoot_and_must_grow():
	var ferns := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"))
	var bare := _a_bare_cell(ferns)
	assert_true(ferns.plant(bare))
	assert_almost_eq(ferns.get_growth(bare), 0.0, 0.0001)


# -- ground nothing may grow on, handed in at construction -------------------
#
# The same mask TallGrass takes as `is_river` and for the same reason: a
# river never changes the biome array (docs/concept/rivers.md), and neither
# does a building already standing on a reloaded chunk. Without it a fresh
# sim seeds ferns into water and through floors on every chunk load, before
# anything has a chance to block them.

func test_ferns_never_seed_on_blocked_ground():
	var blocked := PackedByteArray()
	blocked.resize(WIDTH * HEIGHT)
	blocked.fill(1)
	var ferns := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"), blocked)
	assert_eq(ferns.get_patch_cells().size(), 0, "every cell of this wood is water or floor")


func test_ferns_never_creep_onto_blocked_ground():
	var blocked := PackedByteArray()
	blocked.resize(WIDTH * HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			blocked[y * WIDTH + x] = 1 if x >= WIDTH / 2 else 0
	var ferns := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"), blocked)
	for _tick in 400:
		ferns.advance(ForestFern.SPREAD_INTERVAL, 1.0)
	for cell in ferns.get_patch_cells():
		assert_lt((cell as Vector2i).x, WIDTH / 2, "a fern crept into %s" % str(cell))


## And a caller that never passes one behaves exactly as before -- the same
## optional-trailing-parameter shape TallGrass's own is_river addition used.
func test_a_sim_given_no_mask_grows_the_way_it_always_did():
	var with_none := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"))
	var with_empty := ForestFern.new(3, WIDTH, HEIGHT, _biome_all("forest"), PackedByteArray())
	assert_eq(with_none.get_patch_cells(), with_empty.get_patch_cells())
