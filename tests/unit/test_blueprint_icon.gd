extends GutTest

## The build palette's icons (see docs/concept/planner_mode.md, "The build
## palette"): a square box holding the building's OWN art -- the very
## picture it will have once it is finished -- fitted rather than squashed.

const BlueprintIcon = preload("res://src/ui/blueprint_icon.gd")
const BlueprintPaletteModel = preload("res://src/ui/blueprint_palette_model.gd")
const BuildPlan = preload("res://src/world/build_plan.gd")

const BOX := 48


func _all_offered() -> Array:
	var out: Array = []
	for category in BlueprintPaletteModel.categories():
		for blueprint_id in category["blueprint_ids"]:
			out.append(blueprint_id)
	return out


func _opaque_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


# -- the fit, pure geometry ------------------------------------------------

func test_a_wide_cut_is_bounded_by_the_boxs_width():
	assert_eq(BlueprintIcon.fitted_size(Vector2i(192, 96), BOX), Vector2i(48, 24))


func test_a_tall_cut_is_bounded_by_the_boxs_height():
	assert_eq(BlueprintIcon.fitted_size(Vector2i(96, 192), BOX), Vector2i(24, 48))


func test_a_square_cut_fills_the_box():
	assert_eq(BlueprintIcon.fitted_size(Vector2i(100, 100), BOX), Vector2i(48, 48))


## The whole reason the fit exists: a manor really is wider than it is
## tall, and squashing every cut into the square would report every
## building as the same shape.
func test_the_aspect_survives_the_fit():
	for source in [Vector2i(192, 188), Vector2i(256, 120), Vector2i(64, 300), Vector2i(30, 31)]:
		var fitted: Vector2i = BlueprintIcon.fitted_size(source, BOX)
		var wanted := float(source.x) / float(source.y)
		var got := float(fitted.x) / float(fitted.y)
		assert_almost_eq(got, wanted, wanted * 0.06, "%s -> %s" % [source, fitted])


func test_nothing_is_ever_drawn_outside_its_box():
	for source in [Vector2i(1536, 1024), Vector2i(12, 900), Vector2i(48, 48), Vector2i(3, 3)]:
		var fitted: Vector2i = BlueprintIcon.fitted_size(source, BOX)
		assert_true(fitted.x <= BOX and fitted.y <= BOX, "%s spills: %s" % [source, fitted])
		assert_true(
			fitted.x == BOX or fitted.y == BOX,
			"%s does not reach its box on either axis: %s" % [source, fitted]
		)
		assert_true(fitted.x >= 1 and fitted.y >= 1, "%s vanished: %s" % [source, fitted])


func test_a_degenerate_cut_is_refused_rather_than_divided_by_zero():
	assert_eq(BlueprintIcon.fitted_size(Vector2i(0, 10), BOX), Vector2i.ZERO)
	assert_eq(BlueprintIcon.fitted_size(Vector2i(10, 0), BOX), Vector2i.ZERO)
	assert_eq(BlueprintIcon.fitted_size(Vector2i(10, 10), 0), Vector2i.ZERO)


# -- the real art ----------------------------------------------------------

## Every slot is the same size whatever stands in it, so a row of them is a
## row rather than a ragged line.
func test_every_icon_is_the_same_square_whatever_the_building():
	assert_gt(_all_offered().size(), 0, "the premise: the palette offers something")
	var icons := BlueprintIcon.new()
	for blueprint_id in _all_offered():
		var image: Image = icons.icon_image(blueprint_id, BOX)
		assert_not_null(image, "%s has no icon at all" % blueprint_id)
		assert_eq(
			Vector2i(image.get_width(), image.get_height()), Vector2i(BOX, BOX),
			"%s is not boxed" % blueprint_id
		)


## An icon that is blank, or the same blank for everything, is worse than
## the text it replaced. Each one has real art in it.
func test_every_icon_really_has_art_in_it():
	assert_gt(_all_offered().size(), 0, "the premise: the palette offers something")
	var icons := BlueprintIcon.new()
	for blueprint_id in _all_offered():
		var image: Image = icons.icon_image(blueprint_id, BOX)
		assert_gt(
			_opaque_pixels(image), BOX * BOX / 10,
			"%s's icon is all but empty" % blueprint_id
		)


## The doc's rule that the icon is the building's OWN art: two different
## buildings cannot share one picture, or the menu is a row of the same
## placeholder with different words under it -- exactly what it replaced.
func test_two_different_buildings_never_share_one_picture():
	assert_gt(_all_offered().size(), 0, "the premise: the palette offers something")
	var icons := BlueprintIcon.new()
	var seen := {}
	for blueprint_id in _all_offered():
		var data := icons.icon_image(blueprint_id, BOX).get_data()
		var key := data.hex_encode()
		assert_false(
			seen.has(key), "%s and %s are drawn with the same picture" % [seen.get(key, ""), blueprint_id]
		)
		seen[key] = blueprint_id


func test_the_same_building_is_always_the_same_icon():
	var icons := BlueprintIcon.new()
	var first := icons.icon_image("house_medium", BOX).get_data()
	var second := BlueprintIcon.new().icon_image("house_medium", BOX).get_data()
	assert_eq(first, second, "an icon that changes between rebuilds is not an icon")


## Pavement is not a BuildingCatalog entry, so it cannot come off a
## building sheet -- it draws the real road tile it will lay.
func test_pavement_draws_the_surface_it_will_lay():
	var icons := BlueprintIcon.new()
	var image: Image = icons.icon_image(BuildPlan.PAVEMENT_BLUEPRINT_ID, BOX)
	assert_not_null(image)
	assert_eq(
		_opaque_pixels(image), BOX * BOX,
		"a laid surface is a full tile, edge to edge, not a cut-out with a background"
	)


func test_an_unknown_blueprint_gets_no_icon_rather_than_a_wrong_one():
	assert_null(BlueprintIcon.new().icon_image("not_a_building", BOX))
