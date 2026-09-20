extends GutTest

## IllustratedBramblePatch: a chunk's thickets drawn the way ferns are, and
## bent by the long grass's own mechanism at a woody fraction of it
## (docs/concept/brambles.md, "A bramble gives, and it fights back").
##
## Asked for directly: *"Black berrys have no bend mechanism.. they should
## bend slightly when walked over from the side"*.

const IllustratedBramblePatch = preload("res://src/rendering/illustrated_bramble_patch.gd")
const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")
const IllustratedFernPatch = preload("res://src/rendering/illustrated_fern_patch.gd")


# -- one bend in the world ----------------------------------------------------

func test_a_bramble_bends_on_the_grasss_own_shader_code():
	assert_eq(IllustratedBramblePatch.SHADER_CODE, IllustratedGrassPatch.SHADER_CODE)


func test_a_bramble_y_sorts_on_the_grasss_own_band_rule():
	for local_y in [0.0, 3.5, 31.0]:
		assert_eq(
			IllustratedBramblePatch.band_index_for_local_y(local_y, 32),
			IllustratedGrassPatch.band_index_for_local_y(local_y, 32)
		)


func test_a_brambles_mesh_is_subdivided_the_way_a_blades_is():
	var mesh := IllustratedBramblePatch.new().mesh()
	assert_eq(mesh.subdivide_width, IllustratedGrassPatch.BEND_MESH_SUBDIVIDE_WIDTH)
	assert_eq(mesh.subdivide_depth, IllustratedGrassPatch.BEND_MESH_SUBDIVIDE_DEPTH)


# -- but it gives less --------------------------------------------------------

## The whole of "slightly": a cane is woody, so it takes a fraction of the
## bend a blade lays over with. The ORDERING is the decision, not the
## literal.
func test_a_cane_gives_less_than_a_blade_or_a_frond():
	assert_lt(IllustratedBramblePatch.BEND_SCALE, IllustratedGrassPatch.DEFAULT_BEND_SCALE)
	assert_lt(IllustratedBramblePatch.BEND_SCALE, 1.0)
	assert_gt(IllustratedBramblePatch.BEND_SCALE, 0.0, "it still gives, it is not a wall")


## ...and it really reaches the material, or the scale would be a constant
## nobody applies.
func test_the_scale_is_pushed_onto_the_material():
	var material := IllustratedBramblePatch.new().material()
	assert_almost_eq(
		float(material.get_shader_parameter("bend_scale")),
		IllustratedBramblePatch.BEND_SCALE, 0.0001
	)


## The plants that DO lay over keep the full bend -- a scale on one must
## not have quietly become a scale on all of them.
func test_the_ferns_still_take_the_whole_bend():
	var material := IllustratedFernPatch.new().material()
	var scale = material.get_shader_parameter("bend_scale")
	assert_true(
		scale == null or is_equal_approx(float(scale), IllustratedGrassPatch.DEFAULT_BEND_SCALE),
		"a fern must still lay over like the grass it stands beside"
	)


# -- one card, not a stack ----------------------------------------------------

## A thicket is a single woody clump with its berries and litter drawn into
## it, where a fern cell is a stand of fronds worth stacking -- and
## brambles are the sparser plant besides.
func test_a_thicket_draws_one_card():
	assert_eq(IllustratedBramblePatch.CARD_COUNT, 1)
	assert_lt(IllustratedBramblePatch.CARD_COUNT, IllustratedFernPatch.CARD_COUNT)


func test_a_cell_expands_into_exactly_its_own_cards():
	var cards := IllustratedBramblePatch.cards_for_cell({
		"seed": 7, "ground_position": Vector2(64.0, 96.0), "growth": 1.0,
	})
	assert_eq(cards.size(), IllustratedBramblePatch.CARD_COUNT)


func test_the_same_cell_draws_the_same_card_every_time():
	var spec := {"seed": 31, "ground_position": Vector2(8.0, 8.0), "growth": 1.0}
	assert_eq(
		IllustratedBramblePatch.cards_for_cell(spec),
		IllustratedBramblePatch.cards_for_cell(spec)
	)


# -- the sheet ----------------------------------------------------------------

## Delivered with real alpha, unlike the fern sheet's painted
## checkerboard -- so nothing is keyed, and keying it anyway would punch
## holes through every pale berry highlight.
func test_the_sheet_loads_with_its_own_transparency():
	var texture := IllustratedBramblePatch.new().texture()
	assert_not_null(texture, "the bramble sheet must load")
	var image := texture.get_image()
	# Effectively transparent rather than exactly zero: the delivered sheet
	# carries real alpha with a couple of levels of compression noise in it
	# (measured 2/255 in the corner), which is a fact about the file and
	# not something to key away.
	assert_lt(
		image.get_pixel(0, 0).a, 0.05,
		"the corner of a delivered sheet is transparent"
	)


func test_every_patch_shares_one_sheet():
	assert_same(IllustratedBramblePatch.new().texture(), IllustratedBramblePatch.new().texture())


func test_every_region_stays_inside_the_sheet():
	var size := Vector2i(1250, 1250)
	for seed_value in range(0, 13):
		var region := IllustratedBramblePatch.atlas_region_for(seed_value, 1.0, size)
		assert_gte(region.position.x, 0)
		assert_lte(region.end.x, size.x, "seed %d" % seed_value)
		assert_lte(region.end.y, size.y, "seed %d" % seed_value)
