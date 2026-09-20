extends GutTest

## IllustratedFernPatch: a chunk's ForestFern cells drawn from the fern
## sheet, bent by the LONG GRASS's own mechanism (docs/concept/ferns.md).
##
## Asked for directly: *"please add the same leaf tracing and bending
## mechanism which the long grass already has"*. "The same" is taken
## literally and structurally, and most of this file exists to pin that: a
## second bend shader that drifted from the first would be two wind systems
## in one world, and the first thing anybody would notice is ferns swaying
## out of time with the grass beside them.
##
## What is genuinely the fern's own is the SHEET and the geometry it
## implies, and that is pinned here too.

const IllustratedFernPatch = preload("res://src/rendering/illustrated_fern_patch.gd")
const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")


# -- the bend is the grass's, reached for rather than copied ----------------

func test_a_fern_bends_with_the_grasss_own_shader_code():
	assert_eq(
		IllustratedFernPatch.SHADER_CODE, IllustratedGrassPatch.SHADER_CODE,
		"a fern must bend on the same code a blade does, not a copy of it"
	)


func test_a_fern_and_a_blade_bend_by_exactly_the_same_amount():
	for top_t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		assert_almost_eq(
			IllustratedFernPatch.bend_curve(top_t),
			IllustratedGrassPatch.bend_curve(top_t),
			0.000001, "at %s" % str(top_t)
		)


## A bent frond needs the same vertex budget to travel along that a bent
## blade does -- the whole reason the bend moves the MESH rather than only
## the sampled UV (docs/concept/long_grass.md, "Where a bent blade actually
## goes"). A coarser mesh here would clip fronds off at a card's edge.
func test_a_ferns_mesh_is_subdivided_the_way_a_blades_is():
	var mesh := IllustratedFernPatch.new().mesh()
	assert_eq(mesh.subdivide_width, IllustratedGrassPatch.BEND_MESH_SUBDIVIDE_WIDTH)
	assert_eq(mesh.subdivide_depth, IllustratedGrassPatch.BEND_MESH_SUBDIVIDE_DEPTH)


## A card's root sits at its BOTTOM edge, so growth and bend never drift a
## fern away from the ground it stands on.
func test_a_ferns_root_is_its_own_bottom_edge():
	var mesh := IllustratedFernPatch.new().mesh()
	assert_eq(mesh.size, Vector2(IllustratedFernPatch.WORLD_SIZE, IllustratedFernPatch.WORLD_SIZE))
	assert_almost_eq(mesh.center_offset.y, -IllustratedFernPatch.WORLD_SIZE * 0.5, 0.0001)


## Y-sorting is the grass's rule too, not a second one: a walker must not
## read as behind the ferns and in front of the grass in the same step.
func test_a_fern_y_sorts_on_the_grasss_own_band_rule():
	var patch := IllustratedFernPatch.new()
	for world_y in [0.0, 37.0, 512.0]:
		assert_eq(
			IllustratedFernPatch.local_row_for_world_y(world_y, 0, 16.0),
			IllustratedGrassPatch.local_row_for_world_y(world_y, 0, 16.0),
			"at %s" % str(world_y)
		)
	for local_y in [0.0, 3.5, 31.0]:
		assert_eq(
			IllustratedFernPatch.band_index_for_local_y(local_y, 32),
			IllustratedGrassPatch.band_index_for_local_y(local_y, 32),
			"at %s" % str(local_y)
		)


func test_a_fern_band_is_anchored_where_a_grass_band_is():
	for band in [0, 7, 63]:
		assert_almost_eq(
			IllustratedFernPatch.band_anchor_world_y(band, 0, 32, 16.0),
			IllustratedGrassPatch.band_anchor_world_y(band, 0, 32, 16.0),
			0.0001, "band %d" % band
		)


# -- the sheet, which IS the fern's own --------------------------------------

func test_the_fern_sheet_is_a_five_by_five_grid():
	assert_eq(IllustratedFernPatch.ATLAS_COLUMNS, 5)
	assert_eq(IllustratedFernPatch.ATLAS_ROWS, 5)


## Growth picks the ROW, the seed picks the COLUMN -- the same two
## independent axes long grass uses.
func test_growth_picks_the_row_and_the_seed_picks_the_column():
	var size := Vector2i(1250, 1250)
	var shoot := IllustratedFernPatch.atlas_region_for(0, 0.0, size)
	var grown := IllustratedFernPatch.atlas_region_for(0, 1.0, size)
	assert_lt(shoot.position.y, grown.position.y, "a young clump samples an earlier row")
	var other_variant := IllustratedFernPatch.atlas_region_for(1, 0.0, size)
	assert_ne(shoot.position.x, other_variant.position.x, "a different seed is a different column")
	assert_eq(shoot.position.y, other_variant.position.y, "...at the same growth stage")


func test_growth_is_clamped_not_wrapped():
	var size := Vector2i(1250, 1250)
	assert_eq(
		IllustratedFernPatch.atlas_region_for(0, 1.0, size),
		IllustratedFernPatch.atlas_region_for(0, 4.0, size),
		"a mature fern stays mature rather than cycling back to a shoot"
	)
	assert_eq(
		IllustratedFernPatch.atlas_region_for(0, 0.0, size),
		IllustratedFernPatch.atlas_region_for(0, -1.0, size)
	)


func test_every_region_stays_inside_the_sheet():
	var size := Vector2i(1250, 1250)
	for seed_value in range(0, 13):
		for growth in [0.0, 0.3, 0.7, 1.0]:
			var region := IllustratedFernPatch.atlas_region_for(seed_value, growth, size)
			assert_gte(region.position.x, 0)
			assert_gte(region.position.y, 0)
			assert_lte(region.end.x, size.x, "seed %d" % seed_value)
			assert_lte(region.end.y, size.y, "seed %d" % seed_value)


# -- a clump is one plant, where a tuft is a field ---------------------------

## Each delivered fern cell is already a whole clump with its own rocks,
## logs and mushrooms drawn in, so stacking a grass tuft's worth of them
## per tile would read as a hedge and cost that much overdraw for it.
func test_a_fern_cell_draws_fewer_cards_than_a_grass_cell():
	assert_lt(IllustratedFernPatch.CARD_COUNT, IllustratedGrassPatch.CARD_COUNT)
	assert_gte(IllustratedFernPatch.CARD_COUNT, 1)


## ...and each of them is drawn bigger. A fern clump stands taller than a
## grass tuft and arches over the tile it roots on; that is the trade the
## lower card count pays for.
func test_a_fern_card_is_drawn_larger_than_a_blade_card():
	assert_gt(IllustratedFernPatch.WORLD_SIZE, IllustratedGrassPatch.WORLD_SIZE)


## But the two together must not cost more fill rate than a grass tuft
## does, or the wood is where the frame rate goes. Area is what the GPU
## blends, so the comparison is area, not count.
func test_a_fern_cell_is_no_more_overdraw_than_a_grass_cell():
	var fern := IllustratedFernPatch.CARD_COUNT * pow(IllustratedFernPatch.WORLD_SIZE, 2.0)
	var grass := IllustratedGrassPatch.CARD_COUNT * pow(IllustratedGrassPatch.WORLD_SIZE, 2.0)
	assert_lte(fern, grass, "a fern tile blends more pixels than a grass tile")


func test_a_cell_expands_into_exactly_its_own_cards():
	var cards := IllustratedFernPatch.cards_for_cell({
		"seed": 12345, "ground_position": Vector2(100.0, 200.0), "growth": 0.5,
	})
	assert_eq(cards.size(), IllustratedFernPatch.CARD_COUNT)
	for card in cards:
		assert_eq(card.growth, 0.5)


## Cards are offset from the cell's own centre so a clump fills its tile
## rather than sitting in one corner -- and never outside the tile it
## belongs to, or a fern would stand on its neighbour's ground.
## Bounded by the TILE, not by the card: a fern card is drawn larger than
## a tile so its fronds arch over the edges the way a real clump does, but
## its ROOT still has to sit on the tile it belongs to, or a fern would be
## standing on its neighbour's ground.
func test_cards_spread_across_the_tile_without_leaving_it():
	var half := IllustratedFernPatch.TILE_SPAN * 0.5
	var spread_x := 0.0
	var spread_y := 0.0
	for seed_value in range(0, 40):
		for spec in IllustratedFernPatch.card_specs_for_seed(seed_value):
			var offset: Vector2 = spec.offset
			assert_lte(absf(offset.x), half, "seed %d ran off the tile" % seed_value)
			assert_lte(absf(offset.y), half, "seed %d ran off the tile" % seed_value)
			spread_x = maxf(spread_x, absf(offset.x))
			spread_y = maxf(spread_y, absf(offset.y))
	assert_gt(spread_x, half * 0.4, "cards huddle in the middle instead of filling the tile")
	assert_gt(spread_y, half * 0.4, "cards huddle in the middle instead of filling the tile")


func test_the_same_cell_draws_the_same_cards_every_time():
	var spec := {"seed": 999, "ground_position": Vector2(8.0, 8.0), "growth": 1.0}
	assert_eq(
		IllustratedFernPatch.cards_for_cell(spec),
		IllustratedFernPatch.cards_for_cell(spec)
	)


# -- instances ---------------------------------------------------------------

func test_a_cards_root_is_pinned_at_its_own_position():
	var cards := IllustratedFernPatch.cards_for_cell({
		"seed": 7, "ground_position": Vector2(64.0, 96.0), "growth": 1.0,
	})
	var anchor := Vector2(0.0, 80.0)
	var instances := IllustratedFernPatch.instances_for_cards(cards, anchor, Vector2i(1250, 1250))
	assert_eq(instances.size(), cards.size())
	for i in instances.size():
		var t: Transform2D = instances[i].transform
		assert_almost_eq(t.get_scale().x, 1.0, 0.0001, "a fern is never squashed by its growth")


## Back to front within a band, so overlapping translucent clumps blend in
## roughly the right order.
func test_instances_are_ordered_back_to_front():
	var cards: Array = []
	for y in [300.0, 100.0, 200.0]:
		cards.append({"atlas_seed": 1, "position": Vector2(0.0, y), "growth": 1.0})
	var instances := IllustratedFernPatch.instances_for_cards(cards, Vector2.ZERO, Vector2i(1250, 1250))
	var previous := -INF
	for instance in instances:
		var y: float = (instance.transform as Transform2D).origin.y
		assert_gte(y, previous)
		previous = y


# -- the sheet loads, and is shared ------------------------------------------

func test_the_sheet_loads_and_is_keyed_to_real_transparency():
	var texture := IllustratedFernPatch.new().texture()
	assert_not_null(texture, "the fern sheet must load")
	assert_eq(texture.get_size(), Vector2(1254, 1254))
	var image := texture.get_image()
	assert_eq(image.get_format(), Image.FORMAT_RGBA8, "the delivered sheet is opaque RGB until it is keyed")
	assert_eq(image.get_pixel(0, 0).a, 0.0, "the checkerboard is still in the corner")


## One texture for every patch in the world, not one per chunk: a 1254
## square sheet held per loaded chunk is the kind of cost that only shows
## up once a player has walked a while.
func test_every_patch_shares_one_sheet():
	assert_same(IllustratedFernPatch.new().texture(), IllustratedFernPatch.new().texture())
