extends GutTest

## MeadowSpread: the meadow a player walks into is what the wind already did
## (see concept/flora.md#the-meadow-you-arrive-to-is-what-the-wind-already-did).
##
## The baked meadow used to be an independent coin flip per grassland cell --
## a uniform speckle at a density set by one constant, which produced adjacent
## pairs and triples constantly and had no relationship whatever to the wind.
## A world whose entire dispersal model is "light seed goes downwind"
## nevertheless STARTED isotropic. This runs the same kernel the live world
## runs (WindDispersal), from sparse founders, under the region's prevailing
## wind, through the same establishment gate live seed passes.

const MeadowSpread = preload("res://src/world/meadow_spread.gd")
const FlowerEstablishment = preload("res://src/world/flower_establishment.gd")
const FlowerSpecies = preload("res://src/world/flower_species.gd")

const BIG_CAP := 100000


func _grassland(width: int, height: int) -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(width * height)
	biome.fill("grassland")
	return biome


func _colonise(
	world_seed: int,
	origin: Vector2i,
	size: int,
	direction := Vector2.RIGHT,
	strength := 0.6,
	cap := BIG_CAP
) -> Dictionary:
	return MeadowSpread.colonise(
		world_seed, origin, size, size, _grassland(size, size), direction, strength, cap
	)




# -- there is a meadow -------------------------------------------------------

func test_a_grassland_chunk_grows_a_meadow():
	for world_seed in [1, 77, 4242, -18]:
		assert_gt(
			_colonise(world_seed, Vector2i.ZERO, 32).size(), 0,
			"seed %d grew nothing at all" % world_seed
		)


func test_every_plant_is_a_real_species():
	var meadow := _colonise(9, Vector2i.ZERO, 32)
	for cell in meadow:
		assert_true(
			FlowerSpecies.IDS.has(meadow[cell]), "grew a '%s'" % meadow[cell]
		)


func test_every_plant_is_inside_the_chunk_it_was_asked_for():
	var meadow := _colonise(3, Vector2i(-64, 96), 32)
	for cell in meadow:
		assert_true(
			cell.x >= 0 and cell.x < 32 and cell.y >= 0 and cell.y < 32,
			"%s is outside the chunk" % cell
		)


func test_cells_are_chunk_local_not_world_tiles():
	# Same ground, asked for at a far-flung origin: the KEYS must still be
	# 0..31, because that is what FlowerPatch indexes its biome array with.
	var meadow := _colonise(5, Vector2i(4096, -8192), 32)
	assert_gt(meadow.size(), 0, "precondition: something grew")
	for cell in meadow:
		assert_between(cell.x, 0, 31)
		assert_between(cell.y, 0, 31)


# -- how it is spaced --------------------------------------------------------

## The report, directly: "more space between individual flowers".
func test_no_two_plants_stand_closer_than_the_gate_allows():
	for world_seed in [1, 77, 4242, -18, 900]:
		var meadow := _colonise(world_seed, Vector2i.ZERO, 48)
		var cells := meadow.keys()
		for i in cells.size():
			for j in range(i + 1, cells.size()):
				var a: Vector2i = cells[i]
				var b: Vector2i = cells[j]
				var gap := Vector2(a - b).length()
				assert_gte(
					gap, FlowerEstablishment.MIN_SPACING_TILES,
					"seed %d put %s and %s %.2f tiles apart" % [world_seed, a, b, gap]
				)


## The other half of the report: "way too dense". The old rule flipped a 3.5%
## coin per grassland cell, so a full-grassland chunk came out at ~36 plants
## and regularly hit its own 40 cap. Pinned as a band rather than a number:
## sparse enough to read as accents in a meadow, and NOT so sparse that a
## pollinator has nothing to work a circuit through (see
## concept/flora.md#trap-lining -- the measurement that cleared the
## "butterflies get stuck on one flower" report was taken against a meadow of
## roughly this many blooms).
func test_a_chunk_grows_accents_rather_than_ground_cover():
	var counts: Array[int] = []
	var total := 0
	for world_seed in [1, 2, 3, 4, 5, 6, 7, 8]:
		var count := _colonise(world_seed, Vector2i.ZERO, 32).size()
		counts.append(count)
		total += count
		assert_lt(count, 32, "seed %d grew %d plants -- as dense as the old speckle" % [world_seed, count])
	var mean := float(total) / float(counts.size())
	assert_between(
		mean, 8.0, 24.0,
		"a full-grassland chunk averaged %.1f plants (counts %s)" % [mean, counts]
	)


## A meadow that stopped short of its own chunk edges would draw a visible
## grid across the world. Founders live in WORLD space precisely so a meadow
## crosses a chunk boundary.
func test_the_meadow_reaches_its_own_edges():
	var edges := {"left": false, "right": false, "top": false, "bottom": false}
	for world_seed in range(20):
		for cell in _colonise(world_seed, Vector2i.ZERO, 32):
			if cell.x <= 2:
				edges["left"] = true
			if cell.x >= 29:
				edges["right"] = true
			if cell.y <= 2:
				edges["top"] = true
			if cell.y >= 29:
				edges["bottom"] = true
	for edge in edges:
		assert_true(edges[edge], "nothing ever grew against the %s edge" % edge)


## Two chunks sharing a boundary must space their flowers against EACH OTHER,
## not just internally -- otherwise the gate opens gaps everywhere except
## along the seams, which is where they would be most obvious.
func test_neighbouring_chunks_space_their_flowers_against_each_other():
	for world_seed in [1, 77, 4242, -18, 900, 31337]:
		var left := _colonise(world_seed, Vector2i.ZERO, 32)
		var right := _colonise(world_seed, Vector2i(32, 0), 32)
		for cell in left:
			for other in right:
				var world_other: Vector2i = other + Vector2i(32, 0)
				var gap := Vector2(cell - world_other).length()
				assert_gte(
					gap, FlowerEstablishment.MIN_SPACING_TILES,
					"seed %d: %s and %s straddle the seam %.2f tiles apart"
					% [world_seed, cell, world_other, gap]
				)


# -- the wind decides where it went ------------------------------------------
#
# Measured on a single founder's LINEAGE rather than on a whole field's mean
# position. The field's mean is not a wind measurement at all: founders are
# statistically homogeneous, so shifting every lineage downwind leaves the mean
# inside a fixed window where it was, and the "test" reads sampling noise. What
# the wind actually does is displace offspring from their parent, so that is
# what gets measured.

## Offsets from the founder across MANY lineages, not one. A single lineage is
## about a dozen grains, which is far too few for the wind-independent scatter
## (WindDispersal's calm term, a random bearing per grain) to cancel out -- one
## lineage genuinely can lean across the wind by chance, and a test that read
## one would be reading that chance rather than the wind.
func _lineage_offsets(direction: Vector2, strength: float) -> Array:
	var out: Array = []
	for i in 30:
		var founder := Vector2i(1000 + i * 97, 1000 - i * 61)
		for grain in MeadowSpread.lineage(founder, "rose", 5 + i, direction, strength):
			var cell: Vector2i = grain["cell"]
			out.append(Vector2(cell - founder))
	return out


func _mean_offset(direction: Vector2, strength: float) -> Vector2:
	var offsets := _lineage_offsets(direction, strength)
	var total := Vector2.ZERO
	for offset in offsets:
		total += offset
	return total / float(maxi(offsets.size(), 1))


## A lineage creeps DOWNWIND rather than expanding as a circle. That is the
## fingerprint of wind actually being simulated rather than a random offset
## wearing wind's name.
func test_a_lineage_spreads_downwind():
	var mean := _mean_offset(Vector2.RIGHT, 0.8)
	assert_gt(mean.x, 0.0, "the lineage did not go downwind at all")
	assert_gt(absf(mean.x), absf(mean.y) * 2.0, "it went across the wind, not along it")


func test_turning_the_wind_around_mirrors_a_lineage():
	var east := _mean_offset(Vector2.RIGHT, 0.8)
	var west := _mean_offset(Vector2.LEFT, 0.8)
	assert_gt(east.x, 0.0)
	assert_lt(west.x, 0.0)


func test_a_stronger_wind_spreads_a_lineage_further():
	var breeze := _mean_offset(Vector2.RIGHT, 0.15)
	var gale := _mean_offset(Vector2.RIGHT, 1.0)
	assert_gt(gale.x, breeze.x, "the wind's strength changed nothing (%.2f vs %.2f)" % [gale.x, breeze.x])


## Two generations, not one, is what makes this a spread rather than a
## scatter: a plant that already travelled downwind sheds from further
## downwind again, so the lineage is drawn out ALONG the wind rather than
## sitting in a round halo about its founder.
func test_a_lineage_is_drawn_out_along_the_wind_rather_than_round():
	var offsets := _lineage_offsets(Vector2.RIGHT, 0.8)
	var along := 0.0
	var across := 0.0
	for offset in offsets:
		along += absf(offset.x)
		across += absf(offset.y)
	assert_gt(along, across * 1.3, "the lineage is round (%.1f along, %.1f across)" % [along, across])


## Different wind, different meadow -- the whole-field statement of the tests
## above, kept as a coarse guard that the wind actually reaches worldgen.
func test_the_wind_changes_which_meadow_grows():
	assert_ne(
		_colonise(11, Vector2i.ZERO, 48, Vector2.RIGHT, 1.0).keys(),
		_colonise(11, Vector2i.ZERO, 48, Vector2.LEFT, 1.0).keys()
	)


## A calm region is not a barren one -- seed still scatters around its parent
## (WindDispersal.CALM_SCATTER_TILES), it just does not go anywhere in
## particular.
func test_a_dead_calm_region_still_grows_a_meadow():
	for world_seed in [11, 12, 13, 14]:
		assert_gt(
			_colonise(world_seed, Vector2i.ZERO, 32, Vector2.RIGHT, 0.0).size(), 0,
			"seed %d grew nothing on a still day" % world_seed
		)


# -- housekeeping ------------------------------------------------------------

func test_the_same_ground_grows_the_same_meadow_every_time():
	assert_eq(
		_colonise(1234, Vector2i(7, -3), 32), _colonise(1234, Vector2i(7, -3), 32)
	)


func test_a_different_world_grows_a_different_meadow():
	assert_ne(
		_colonise(1, Vector2i.ZERO, 32).keys(), _colonise(2, Vector2i.ZERO, 32).keys()
	)


## Flowers are meadow plants. A seed landing in the sea or on bare rock is
## lost, which is itself a real check on spread.
func test_nothing_grows_off_the_grassland():
	var size := 32
	var biome := PackedStringArray()
	biome.resize(size * size)
	biome.fill("ocean")
	# One grassland stripe down the middle.
	for y in size:
		for x in range(14, 18):
			biome[y * size + x] = "grassland"
	var meadow := MeadowSpread.colonise(
		77, Vector2i.ZERO, size, size, biome, Vector2.RIGHT, 0.6, BIG_CAP
	)
	assert_gt(meadow.size(), 0, "precondition: the stripe grew something")
	for cell in meadow:
		assert_between(cell.x, 14, 17, "%s grew in the sea" % cell)


func test_the_meadow_respects_the_chunks_ceiling():
	var meadow := _colonise(1, Vector2i.ZERO, 48, Vector2.RIGHT, 0.6, 5)
	assert_lte(meadow.size(), 5)


# -- founders ----------------------------------------------------------------

## Founders are where a meadow started. Sparse, or the "spread" is a scatter
## with extra steps.
func test_founders_are_sparse():
	var founders := MeadowSpread.founder_tiles(1234, Vector2i.ZERO, Vector2i(64, 64))
	assert_gt(founders.size(), 0, "no meadow ever starts anywhere")
	assert_lt(
		founders.size(), 64 * 64 / 100,
		"%d founders in 4096 tiles is not a founding population" % founders.size()
	)


## Jittered inside their grid cell, never ON the grid. A visible lattice of
## meadows is the clustering-artifact class this project has hit five times
## (see PixelNoise's own doc comment).
func test_founders_do_not_sit_on_a_visible_lattice():
	var offsets := {}
	for founder in MeadowSpread.founder_tiles(1234, Vector2i(-96, -96), Vector2i(96, 96)):
		offsets[Vector2i(
			posmod(founder.x, MeadowSpread.FOUNDER_GRID_TILES),
			posmod(founder.y, MeadowSpread.FOUNDER_GRID_TILES)
		)] = true
	assert_gt(offsets.size(), 8, "founders landed on %d distinct grid offsets" % offsets.size())


func test_founders_are_all_inside_the_window_they_were_asked_for():
	var low := Vector2i(-20, 40)
	var high := Vector2i(20, 80)
	for founder in MeadowSpread.founder_tiles(7, low, high):
		assert_true(
			founder.x >= low.x and founder.x <= high.x
			and founder.y >= low.y and founder.y <= high.y,
			"%s is outside the window" % founder
		)


## World-space, so the same ground answers the same however the window around
## it is drawn -- that is what lets a meadow cross a chunk boundary.
func test_the_same_ground_founds_the_same_meadows_whatever_window_asks():
	var wide := {}
	for founder in MeadowSpread.founder_tiles(1234, Vector2i(-64, -64), Vector2i(64, 64)):
		wide[founder] = true
	for founder in MeadowSpread.founder_tiles(1234, Vector2i(0, 0), Vector2i(32, 32)):
		assert_true(wide.has(founder), "%s appears only when a narrow window asks" % founder)
