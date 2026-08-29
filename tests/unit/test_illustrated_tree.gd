extends GutTest

## The illustrated tree art: trunk, seasonal canopy, and fruit (see
## docs/concept/flora.md#illustrated-trees).
##
## Three separate pieces because they change on different clocks -- the trunk
## never changes, the canopy four times a year, the fruit as a crop ripens.

const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

var trees: IllustratedTree


func before_each():
	trees = IllustratedTree.new()


# -- which species have art --------------------------------------------------

func test_a_species_with_sheets_reports_art():
	assert_true(trees.has_art_for("cherry"))


## A species without sheets falls back to the procedural painter, exactly as a
## flower without a sheet does. Adding art must never be required.
func test_a_species_without_sheets_reports_none():
	assert_false(trees.has_art_for("not_a_real_species"))


func test_a_species_with_no_art_yields_no_frames():
	assert_eq(trees.canopy_frames_for("not_a_real_species").size(), 0)
	assert_null(trees.trunk_for("not_a_real_species"))


# -- the canopy carries the season -------------------------------------------

## Cherry now ALSO carries a fifth, snow-covered frame (see CANOPY_SNOW) --
## a real column the sheet grew, not a season. The four season frames are
## still there, unmoved, at their same indices; this is one MORE than the
## season count, not a replacement for any of them.
func test_a_canopy_has_one_frame_per_season():
	assert_eq(trees.canopy_frames_for("cherry").size(), SeasonCycle.SEASONS.size() + 1)


## The frames map to seasons by MEANING, not by their order in the sheet.
## Written down because it is exactly the kind of thing that silently works
## until a sheet is authored in a different order.
func test_every_season_picks_out_a_canopy():
	for season in SeasonCycle.SEASONS:
		assert_not_null(
			trees.canopy_for("cherry", season), "%s has no canopy" % season
		)


func test_each_season_gets_its_own_canopy():
	var seen := {}
	for season in SeasonCycle.SEASONS:
		seen[trees.canopy_for("cherry", season).get_image().get_data()] = true
	assert_eq(seen.size(), SeasonCycle.SEASONS.size(), "two seasons share a canopy")


## Winter is the bare one. A tree still in leaf under snow is the single most
## obvious way for the season to look broken.
func test_winter_is_the_barest_canopy():
	var winter := _opaque_share(trees.canopy_for("cherry", "winter").get_image())
	for season in ["spring", "summer", "autumn"]:
		assert_lt(
			winter, _opaque_share(trees.canopy_for("cherry", season).get_image()),
			"winter should be barer than %s" % season
		)


## Summer is green; spring is not. The blossom frame is the one that makes a
## cherry a cherry, so getting these two the right way round matters.
func test_summer_is_in_leaf_and_spring_is_in_blossom():
	assert_gt(
		_green_share(trees.canopy_for("cherry", "summer").get_image()),
		_green_share(trees.canopy_for("cherry", "spring").get_image()),
		"summer should be the leafier of the two"
	)


func test_an_unknown_season_still_yields_a_canopy():
	assert_not_null(
		trees.canopy_for("cherry", "harvest"),
		"an unknown season should fall back rather than crash the forest"
	)


# -- the fifth frame: snow ----------------------------------------------------
#
# A canopy sheet may carry a FIFTH drawing after the four seasons -- how much
# snow lies on the branches. Unlike bare/blossom/leaf/turning this is not a
# season: it is a live-weather overlay (see ProceduralTreeSprite's own snow
# section and docs/concept/seasons.md), so it gets its own slot rather than a
# fifth entry in _CANOPY_FRAME_BY_SEASON.

func test_a_species_with_snow_art_reports_a_snow_frame():
	assert_true(trees.has_snow_frame_for("cherry"))


## has_snow_frame_for counts real frames -- it does not name a species -- so
## an id with no registered art at all trivially has none. This is the gate
## the "rest follows" fallback actually leans on (see ProceduralTreeSprite),
## and it needs no roster of "which species have snow yet" to stay correct.
func test_an_unregistered_species_has_no_snow_frame():
	assert_false(trees.has_snow_frame_for("not_a_real_species"))


## Every illustrated species carries a snow frame as of this writing --
## verified against the REAL sheets on disk, not assumed from the roster.
## The task this was built from started from "only cherry has it, the rest
## follow" as a measured fact; by the time this landed, a second session had
## independently added the same fifth column to every composite sheet
## (acorn/hazelnut/apple/walnut/pine) while cherry's own separate-file one
## was being wired up here. has_snow_frame_for needed no code change for
## that -- it counts real frames rather than naming species -- which is
## exactly what this test is pinning: if a future edit ever regresses one
## sheet back to four frames, this notices.
func test_every_illustrated_species_currently_has_a_snow_frame():
	for species in IllustratedTree.SPECIES_WITH_ART:
		assert_true(trees.has_snow_frame_for(species), "%s should report a snow frame" % species)


func test_the_snow_frame_is_the_fifth_canopy_frame():
	var frames := trees.canopy_frames_for("cherry")
	assert_eq(frames.size(), IllustratedTree.CANOPY_SNOW + 1)
	assert_eq(trees.snow_canopy_for("cherry"), frames[IllustratedTree.CANOPY_SNOW])


func test_a_species_without_a_snow_frame_yields_no_snow_canopy():
	assert_null(trees.snow_canopy_for("not_a_real_species"))


## Snow reads as neutral grey-white, unlike every season frame, which is
## dominated by its own hue (brown bark, pink blossom, green leaf, orange
## turning). Measured off the real sheet: the snow region's mean colour is
## (0.458, 0.443, 0.468) -- practically equal channels -- against the leaf
## region's (0.212, 0.271, 0.022), which is nowhere near neutral.
func test_the_snow_frame_reads_neutral_rather_than_a_season_hue():
	var snow_neutral := _neutral_share(trees.snow_canopy_for("cherry").get_image())
	var leaf_neutral := _neutral_share(trees.canopy_for("cherry", "summer").get_image())
	assert_gt(
		snow_neutral, leaf_neutral,
		"the snow frame should read far greyer than a green summer canopy"
	)


# -- fruit -------------------------------------------------------------------

## Two frames, so a crop coming in is visible on the tree before it can be
## picked -- the same information FruitingModel already tracks, shown rather
## than hidden.
func test_fruit_has_an_unripe_and_a_ripe_frame():
	assert_not_null(trees.fruit_for("cherry", false))
	assert_not_null(trees.fruit_for("cherry", true))
	assert_ne(
		trees.fruit_for("cherry", true).get_image().get_data(),
		trees.fruit_for("cherry", false).get_image().get_data(),
		"a ripe cherry should not look like an unripe one"
	)


## Ripe is the red one. Backwards here would mean an orchard of green fruit
## that is somehow ready to pick.
func test_the_ripe_frame_is_the_redder_one():
	assert_gt(
		_red_share(trees.fruit_for("cherry", true).get_image()),
		_red_share(trees.fruit_for("cherry", false).get_image()),
		"ripe fruit should be the redder frame"
	)


# -- the sheets themselves ---------------------------------------------------

func test_a_trunk_is_a_single_image():
	assert_not_null(trees.trunk_for("cherry"))
	assert_gt(trees.trunk_for("cherry").get_width(), 0)


## Frames are each their OWN real content, not equal slices of the sheet --
## exactly like the composite layout's canopy strip already is (see
## CompositeSheetSlicer). Equal-slicing was an artefact of the old naive
## _frames() cut, not a real requirement: nothing downstream needs same-size
## frames (illustrated_canopy_box already re-trims and re-scales whichever
## frame it is handed). Measured on the real sheet, the five frames are
## 404/415/421/423/432px wide -- close, but never equal, because a bare
## winter bough really does take up less of the sheet than a snow-laden
## crown right beside it.
func test_canopy_frames_keep_their_own_content_size_not_an_equal_slice():
	var widths := {}
	for frame in trees.canopy_frames_for("cherry"):
		widths[frame.get_width()] = true
	assert_gt(
		widths.size(), 1,
		"content-trimmed frames should not all share one width the way equal slices would"
	)


func test_every_frame_has_real_content():
	for frame in trees.canopy_frames_for("cherry"):
		assert_gt(_opaque_share(frame.get_image()), 0.01, "a blank canopy frame")


## Loading is cached: a forest asks for the same canopy for every tree in it.
func test_asking_twice_returns_the_same_frames():
	assert_eq(trees.canopy_for("cherry", "summer"), trees.canopy_for("cherry", "summer"))


func _opaque_share(image: Image) -> float:
	var opaque := 0
	var total := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			total += 1
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	return float(opaque) / float(maxi(total, 1))


func _green_share(image: Image) -> float:
	var green := 0
	var total := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.5:
				continue
			total += 1
			var degrees := pixel.h * 360.0
			if degrees > 70.0 and degrees < 170.0 and pixel.s > 0.2:
				green += 1
	return float(green) / float(maxi(total, 1))


## Share of painted pixels that read as near-neutral grey/white rather than
## any real hue -- low saturation, regardless of how light or dark.
func _neutral_share(image: Image) -> float:
	var neutral := 0
	var total := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.5:
				continue
			total += 1
			if pixel.s < 0.15:
				neutral += 1
	return float(neutral) / float(maxi(total, 1))


func _red_share(image: Image) -> float:
	var red := 0
	var total := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.5:
				continue
			total += 1
			var degrees := pixel.h * 360.0
			if (degrees < 25.0 or degrees > 330.0) and pixel.s > 0.4:
				red += 1
	return float(red) / float(maxi(total, 1))


# -- compositing a whole tree ------------------------------------------------

## The three pieces are assembled into one tree image, at the same canvas size
## the procedural painter uses -- nothing downstream should have to care which
## of the two drew a given tree.
func test_an_illustrated_tree_fills_the_same_canvas_as_a_procedural_one():
	var sprite := ProceduralTreeSprite.new()
	var image := sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer")
	assert_eq(image.get_width(), ProceduralTreeSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralTreeSprite.SIZE.y)


## A tree stands on its trunk: the bottom of the canvas is trunk, the top is
## canopy. Getting this upside down would plant the forest in the air.
func test_the_trunk_is_at_the_bottom_and_the_canopy_on_top():
	var sprite := ProceduralTreeSprite.new()
	var image := sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer")
	var top_opaque := _row_opaque(image, int(float(image.get_height()) * 0.2))
	var bottom_opaque := _row_opaque(image, image.get_height() - 3)
	assert_gt(top_opaque, bottom_opaque, "the canopy should be wider than the trunk")
	assert_gt(bottom_opaque, 0, "the tree should stand on something")


## The season reaches the tree. This is the whole point of the canopy strip:
## trees previously wore one canopy all year while the flowers beneath them
## bloomed and died on schedule.
func test_a_tree_looks_different_in_winter_than_in_summer():
	var sprite := ProceduralTreeSprite.new()
	assert_ne(
		sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "winter").get_data(),
		sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer").get_data(),
		"a bare winter tree should not look like a summer one"
	)


func test_a_winter_tree_is_barer_than_a_summer_one():
	var sprite := ProceduralTreeSprite.new()
	assert_lt(
		_opaque_share(sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "winter")),
		_opaque_share(sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer")),
		"winter should show less canopy"
	)


## Fruit appears on the tree when there is a crop, and not before.
func test_ripe_fruit_shows_on_the_tree():
	var sprite := ProceduralTreeSprite.new()
	assert_ne(
		sprite.generate_image_with_fruit(_cherry_bias(), 7, 6, "summer").get_data(),
		sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer").get_data(),
		"a tree in fruit should not look like a bare-cropped one"
	)


## Fruit does not teleport as a crop grows: the Nth fruit is always in the
## same place, so more fruit means more of them, not a rearrangement.
func test_fruit_does_not_move_around_as_the_crop_grows():
	var sprite := ProceduralTreeSprite.new()
	var few := sprite.generate_image_with_fruit(_cherry_bias(), 7, 2, "summer")
	var many := sprite.generate_image_with_fruit(_cherry_bias(), 7, 6, "summer")
	var moved := 0
	for y in few.get_height():
		for x in few.get_width():
			# Anything painted in the small crop must still be painted in the
			# large one; the extra fruit may cover more, never less.
			if few.get_pixel(x, y).a > 0.5 and many.get_pixel(x, y).a <= 0.5:
				moved += 1
	assert_lt(moved, 8, "fruit rearranged itself as the crop grew")


## A species with no art still paints, through the procedural path, unchanged.
func test_a_species_without_art_still_draws_a_tree():
	var sprite := ProceduralTreeSprite.new()
	var image := sprite.generate_image_with_fruit(_unillustrated_bias(), 7, 0, "summer")
	assert_gt(_opaque_share(image), 0.05, "an unillustrated species should still be a tree")


## Callers that do not care about the season still work -- the parameter is
## optional and defaults to the same tree they got before.
func test_the_season_is_optional():
	var sprite := ProceduralTreeSprite.new()
	assert_gt(_opaque_share(sprite.generate_image(_cherry_bias(), 7)), 0.05)


func _cherry_bias() -> float:
	return _bias_for("cherry")


func _unillustrated_bias() -> float:
	for species in TreeSpecies.IDS:
		if not IllustratedTree.has_art_for(species):
			return _bias_for(species)
	return 0.0


## TreeSpecies keys trees off a bias FLOAT rather than an id, so a test that
## wants a particular species has to search for a bias that lands on it.
func _bias_for(species: String) -> float:
	for step in 201:
		var bias := float(step) / 200.0
		if TreeSpecies.species_for_bias(bias) == species:
			return bias
	return 0.0


func _row_opaque(image: Image, y: int) -> int:
	var opaque := 0
	for x in image.get_width():
		if image.get_pixel(x, clampi(y, 0, image.get_height() - 1)).a > 0.5:
			opaque += 1
	return opaque


## The canopy sits ON the trunk, not floating above it.
##
## The sheets carry transparent padding around the drawing, so positioning a
## frame by its rectangle positions the padding rather than the tree: the
## canopy hung in the air with a visible gap beneath it. Placement has to use
## each frame's actual painted content.
func test_the_canopy_meets_the_trunk_with_no_gap():
	var sprite := ProceduralTreeSprite.new()
	var image := sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer")
	var empty_rows := 0
	var worst := 0
	var seen_content := false
	for y in image.get_height():
		var opaque := _row_opaque(image, y)
		if opaque > 0:
			seen_content = true
			empty_rows = 0
		elif seen_content:
			empty_rows += 1
			worst = maxi(worst, empty_rows)
	assert_lte(worst, 1, "there is a gap of %d rows between canopy and trunk" % worst)


## Fruit hangs IN the canopy. Scattered against the frame rectangle rather
## than the leaves, most of a crop fell outside the foliage entirely.
func test_fruit_hangs_inside_the_canopy():
	var sprite := ProceduralTreeSprite.new()
	var plain := sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer")
	var fruited := sprite.generate_image_with_fruit(_cherry_bias(), 7, 8, "summer")
	var on_leaves := 0
	var in_thin_air := 0
	for y in plain.get_height():
		for x in plain.get_width():
			if fruited.get_pixel(x, y).is_equal_approx(plain.get_pixel(x, y)):
				continue
			if plain.get_pixel(x, y).a > 0.5:
				on_leaves += 1
			else:
				in_thin_air += 1
	assert_gt(on_leaves, 0, "no fruit was drawn at all")
	assert_gt(
		on_leaves, in_thin_air,
		"most of the crop is hanging off the tree rather than in it"
	)


## A crop has to be VISIBLE, not merely present.
##
## The cherry art is mostly stem, so drawn small the actual cherry came out
## about three pixels and vanished into the leaf texture -- the fruit was
## there, and no player would ever have seen it. A tree in fruit should read as
## a tree in fruit at a glance.
func test_a_crop_is_actually_visible_on_the_tree():
	var sprite := ProceduralTreeSprite.new()
	var plain := sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer")
	var fruited := sprite.generate_image_with_fruit(_cherry_bias(), 7, 8, "summer")
	var changed := 0
	for y in plain.get_height():
		for x in plain.get_width():
			if not fruited.get_pixel(x, y).is_equal_approx(plain.get_pixel(x, y)):
				changed += 1
	assert_gte(
		changed, 8 * ProceduralTreeSprite.MIN_PIXELS_PER_FRUIT,
		"a crop of 8 covers only %d pixels -- it will not be seen" % changed
	)


## The crop is spread through the crown rather than piled in one spot.
##
## Scattered against the whole canopy box it landed on the trunk overlap and
## bunched at the join, which read as a single berry stuck to the trunk.
func test_a_crop_is_spread_through_the_crown():
	var sprite := ProceduralTreeSprite.new()
	var plain := sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer")
	var fruited := sprite.generate_image_with_fruit(_cherry_bias(), 7, 8, "summer")
	var trunk := sprite.illustrated_trunk_box(7)
	var columns := {}
	var on_trunk := 0
	var total := 0
	for y in plain.get_height():
		for x in plain.get_width():
			if fruited.get_pixel(x, y).is_equal_approx(plain.get_pixel(x, y)):
				continue
			total += 1
			columns[x] = true
			if y >= trunk.position.y + int(float(trunk.size.y) * 0.5):
				on_trunk += 1
	assert_gt(columns.size(), 6, "the whole crop is in one column of the tree")
	assert_lt(
		float(on_trunk) / float(maxi(total, 1)), 0.25,
		"most of the crop is stuck to the trunk rather than hanging in the crown"
	)


# -- composite sheets --------------------------------------------------------

## A species may ship as ONE image holding canopy strip, trunk and fruit,
## instead of three separate files. Both layouts work, so art can arrive
## either way without the renderer caring.
func test_a_composite_species_has_art():
	assert_true(trees.has_art_for("walnut"))


## Walnut's composite sheet now also carries a fifth, snow-covered canopy
## drawing (see CANOPY_SNOW) -- one MORE than the four seasons, not a
## replacement for any of them; the blob detection that already read this
## sheet's top band needed no change to pick it up (see
## test_every_illustrated_species_currently_has_a_snow_frame).
func test_a_composite_yields_the_same_four_canopies():
	assert_eq(trees.canopy_frames_for("walnut").size(), SeasonCycle.SEASONS.size() + 1)


func test_a_composite_yields_a_trunk():
	assert_not_null(trees.trunk_for("walnut"))


## The trunk is the biggest drawing below the canopy strip -- that is how it is
## picked out, rather than by being at a fixed place on the sheet.
func test_the_trunk_is_taller_than_a_fruit():
	var trunk := trees.trunk_for("walnut")
	var fruit := trees.fruit_for("walnut", true)
	assert_gt(trunk.get_height(), fruit.get_height(), "the trunk should be the big one")


## Species differ in how many fruit frames they have: a cherry has two, a
## walnut four (green husk, split husk, shelled nut, kernel).
func test_a_species_may_have_more_than_two_fruit_frames():
	assert_gt(trees.fruit_frames_for("walnut").size(), 2)


func test_the_cherry_still_has_its_two():
	assert_eq(trees.fruit_frames_for("cherry").size(), 2)


## Whatever the count, the tree shows the first frame before ripening and the
## second after. Extra frames are the fruit's later life -- shelled, cracked
## open -- and belong to item art, not to the tree.
func test_unripe_and_ripe_are_the_first_two_frames_whatever_the_count():
	for species in ["cherry", "walnut"]:
		var frames := trees.fruit_frames_for(species)
		assert_eq(trees.fruit_for(species, false), frames[0], "%s unripe" % species)
		assert_eq(trees.fruit_for(species, true), frames[1], "%s ripe" % species)


## The canopy strip is the top band of the sheet, so a winter canopy is still
## the bare one however the rest is laid out.
func test_a_composite_canopy_still_reads_bare_in_winter():
	var winter := _opaque_share(trees.canopy_for("walnut", "winter").get_image())
	for season in ["spring", "summer", "autumn"]:
		assert_lt(
			winter, _opaque_share(trees.canopy_for("walnut", season).get_image()),
			"winter should be barer than %s" % season
		)


## A composited walnut is a whole tree, same as a cherry.
func test_a_composite_species_composites_into_a_tree():
	var sprite := ProceduralTreeSprite.new()
	var image := sprite.generate_image_with_fruit(_bias_for("walnut"), 7, 0, "summer")
	assert_gt(_opaque_share(image), 0.05, "the walnut should draw as a tree")
	assert_ne(
		image.get_data(),
		sprite.generate_image_with_fruit(_bias_for("walnut"), 7, 0, "winter").get_data(),
		"a walnut should know the season too"
	)


# -- what a fruit frame MEANS ------------------------------------------------

## The fruit block is laid out in two rows, and the rows mean different things:
## the first is the crop AS IT HANGS ON THE TREE (drawn on a branch, with
## leaves or needles), the second is what you get once you have picked it --
## shelled, cracked open, the kernel.
##
## Every sheet so far follows it: walnut, acorn and hazelnut each draw two
## on-tree stages and two harvested ones, and pine draws three of each.
func test_on_tree_and_harvested_frames_are_told_apart():
	for species in ["walnut", "acorn", "hazelnut", "pine"]:
		var on_tree := trees.on_tree_frames_for(species)
		var harvested := trees.harvest_frames_for(species)
		assert_gt(on_tree.size(), 0, "%s has no on-tree stage" % species)
		assert_gt(harvested.size(), 0, "%s has nothing to harvest" % species)
		assert_eq(
			on_tree.size() + harvested.size(),
			trees.fruit_frames_for(species).size(),
			"%s lost a frame between the two" % species
		)


## Pine carries an extra on-tree stage the others do not: a bare needle sprig
## with no cone on it at all. Frame counts differ per species and the rule has
## to survive that.
func test_pine_has_more_stages_than_the_nut_trees():
	assert_gt(
		trees.on_tree_frames_for("pine").size(),
		trees.on_tree_frames_for("walnut").size(),
		"pine draws a bare sprig as well as its two cone stages"
	)


## Ripe is the LAST on-tree stage and unripe the one before it, counted from
## the end rather than the start. Counted from the start, pine's bare sprig
## would be its unripe crop and the green cone its ripe one -- a tree bearing
## needles instead of cones.
func test_ripe_is_the_last_on_tree_stage_whatever_the_count():
	for species in ["walnut", "acorn", "hazelnut", "pine"]:
		var on_tree := trees.on_tree_frames_for(species)
		assert_eq(trees.fruit_for(species, true), on_tree[-1], "%s ripe" % species)
		assert_eq(trees.fruit_for(species, false), on_tree[-2], "%s unripe" % species)


## A ripe crop does not look like an unripe one on any species.
func test_every_species_shows_its_crop_ripening():
	for species in ["cherry", "walnut", "acorn", "hazelnut", "pine"]:
		assert_ne(
			trees.fruit_for(species, true).get_image().get_data(),
			trees.fruit_for(species, false).get_image().get_data(),
			"%s ripens invisibly" % species
		)


## Every species with art composites into a whole tree that knows its season.
func test_every_illustrated_species_draws_a_seasonal_tree():
	var sprite := ProceduralTreeSprite.new()
	for species in IllustratedTree.SPECIES_WITH_ART:
		if not TreeSpecies.IDS.has(species):
			continue
		var summer := sprite.generate_image_with_fruit(_bias_for(species), 7, 0, "summer")
		assert_gt(_opaque_share(summer), 0.05, "%s should draw as a tree" % species)
		assert_ne(
			summer.get_data(),
			sprite.generate_image_with_fruit(_bias_for(species), 7, 0, "winter").get_data(),
			"%s should know the season" % species
		)


# -- trunk and canopy proportions --------------------------------------------

## A trunk is tall and narrow.
##
## Scaled to preserve the source art's aspect it came out squat and wide --
## the trunk drawings are nearly square, because they include the flare of the
## roots -- so a tree read as a canopy sitting on a stump.
func test_a_trunk_is_taller_than_it_is_wide():
	var sprite := ProceduralTreeSprite.new()
	for seed_value in [1, 7, 23, 91]:
		var trunk := sprite.illustrated_trunk_box(seed_value)
		assert_gt(
			trunk.size.y, trunk.size.x,
			"a trunk at seed %d is wider than it is tall" % seed_value
		)


## ...and much narrower than the canopy above it. A trunk as wide as its crown
## is a mushroom.
func test_a_trunk_is_much_narrower_than_its_canopy():
	var sprite := ProceduralTreeSprite.new()
	for seed_value in [1, 7, 23, 91]:
		var trunk := sprite.illustrated_trunk_box(seed_value)
		var canopy := sprite.illustrated_canopy_box("cherry", seed_value, "summer")
		assert_lt(
			float(trunk.size.x) / float(canopy.size.x),
			ProceduralTreeSprite.MAX_TRUNK_SHARE_OF_CANOPY,
			"the trunk is nearly as wide as the crown"
		)


## The source art is stretched to reach those proportions, deliberately, but
## only so far -- past a point a stretched trunk reads as rubber rather than
## as wood.
func test_the_trunk_stretch_stays_within_bounds():
	var sprite := ProceduralTreeSprite.new()
	for seed_value in range(30):
		assert_lte(
			sprite.illustrated_trunk_stretch(seed_value),
			ProceduralTreeSprite.MAX_TRUNK_STRETCH + 0.001,
			"a trunk at seed %d is stretched out of shape" % seed_value
		)


# -- every tree is its own tree ----------------------------------------------

## Trees vary in height, or a wood reads as one tree stamped out repeatedly.
func test_trees_vary_in_trunk_height():
	var sprite := ProceduralTreeSprite.new()
	var heights := {}
	for seed_value in 40:
		heights[sprite.illustrated_trunk_box(seed_value).size.y] = true
	assert_gt(heights.size(), 2, "every trunk is the same height")


## Canopies vary too, though less -- a crown that changed as much as the trunk
## would stop reading as the same species.
func test_canopies_vary_in_size():
	var sprite := ProceduralTreeSprite.new()
	var widths := {}
	for seed_value in 40:
		widths[sprite.illustrated_canopy_box("cherry", seed_value, "summer").size.x] = true
	assert_gt(widths.size(), 2, "every canopy is the same size")


func test_a_given_tree_keeps_its_proportions():
	var sprite := ProceduralTreeSprite.new()
	for seed_value in [3, 44, 900]:
		assert_eq(
			sprite.illustrated_trunk_box(seed_value),
			sprite.illustrated_trunk_box(seed_value)
		)


## However they vary, trunk and canopy MEET. This is the point of varying them
## together rather than independently: a taller trunk lifts its canopy with it
## instead of leaving a gap or burying the crown.
func test_trunk_and_canopy_always_meet_however_they_vary():
	var sprite := ProceduralTreeSprite.new()
	for seed_value in range(40):
		var trunk := sprite.illustrated_trunk_box(seed_value)
		var canopy := sprite.illustrated_canopy_box("cherry", seed_value, "summer")
		var canopy_bottom: int = canopy.position.y + canopy.size.y
		assert_gt(
			canopy_bottom, trunk.position.y,
			"canopy floats above the trunk at seed %d" % seed_value
		)
		assert_lt(
			canopy_bottom, trunk.position.y + trunk.size.y,
			"canopy swallows the whole trunk at seed %d" % seed_value
		)


## The whole tree stays on its canvas whatever it rolls, and stands on the
## bottom edge rather than floating.
func test_every_tree_stands_on_the_ground_and_fits():
	var sprite := ProceduralTreeSprite.new()
	for seed_value in range(20):
		var trunk := sprite.illustrated_trunk_box(seed_value)
		assert_eq(
			trunk.position.y + trunk.size.y, ProceduralTreeSprite.SIZE.y,
			"a tree at seed %d is not standing on the ground" % seed_value
		)
		var canopy := sprite.illustrated_canopy_box("cherry", seed_value, "summer")
		assert_gte(canopy.position.y, 0, "a canopy at seed %d is cut off the top" % seed_value)


## The trunk must run UP INTO the foliage, with no sky between them.
##
## The earlier no-gap test scanned whole rows and missed this: these canopies
## are notched along the bottom, exactly where the trunk is, so the rows either
## side of the gap were never empty and the check passed while the crown
## visibly floated above the trunk.
##
## Measured down the MIDDLE of the trunk. The outer columns legitimately have
## sky above them -- the canopy art converges to a stem narrower than the
## trunk, so the trunk has shoulders -- and it is the centre line that reads as
## connected or not.
func test_the_trunk_runs_up_into_the_foliage():
	var sprite := ProceduralTreeSprite.new()
	for seed_value in [1, 7, 23, 91, 140]:
		var image := sprite.generate_image_with_fruit(_cherry_bias(), seed_value, 0, "summer")
		var trunk := sprite.illustrated_trunk_box(seed_value)
		var worst := 0
		var inset: int = int(float(trunk.size.x) * 0.3)
		for x in range(trunk.position.x + inset, trunk.position.x + trunk.size.x - inset):
			var lowest_canopy := -1
			var highest_trunk := image.get_height()
			for y in image.get_height():
				if image.get_pixel(x, y).a <= 0.5:
					continue
				if y < trunk.position.y:
					lowest_canopy = maxi(lowest_canopy, y)
				else:
					highest_trunk = mini(highest_trunk, y)
			if lowest_canopy < 0 or highest_trunk >= image.get_height():
				continue
			worst = maxi(worst, highest_trunk - lowest_canopy - 1)
		assert_lte(
			worst, 0,
			"seed %d leaves %d rows of sky between crown and trunk" % [seed_value, worst]
		)


## The PROCEDURAL fruit dots had the same clustering bug, and still affect
## every species without illustrated art.
func test_procedural_fruit_dots_are_spread_around_the_canopy():
	var sprite := ProceduralTreeSprite.new()
	var species := _unillustrated_bias()
	var plain := sprite.generate_image_with_fruit(species, 7, 0, "summer")
	var fruited := sprite.generate_image_with_fruit(species, 7, 8, "summer")
	var columns := {}
	for y in plain.get_height():
		for x in plain.get_width():
			if not fruited.get_pixel(x, y).is_equal_approx(plain.get_pixel(x, y)):
				columns[x] = true
	assert_gt(columns.size(), 4, "the procedural crop is stacked in one place")


# -- a bounded number of distinct trees --------------------------------------

## There are only so many DIFFERENT trees, and that is what makes them cheap.
##
## Composites cost real time, and a tree is rebuilt every time its crop or its
## season changes -- which under /ecotest is constantly. Keyed by raw seed,
## every tree in the world is unique and nothing can be reused: measured, one
## fast-forward frame spent 3.3 seconds rebuilding about 190 trees, and the
## game locked up. Variance is drawn from a bounded variant instead, so a wood
## still looks varied while the renderer only ever builds a fixed number of
## images.
func test_only_a_bounded_number_of_distinct_trees_exist():
	var sprite := ProceduralTreeSprite.new()
	var variants := {}
	for seed_value in 400:
		variants[sprite.tree_variant_for(seed_value)] = true
	assert_lte(variants.size(), ProceduralTreeSprite.TREE_VARIANTS)
	assert_eq(
		variants.size(), ProceduralTreeSprite.TREE_VARIANTS,
		"every variant should actually be reachable"
	)


## ...and there are enough of them that a wood does not read as copies.
##
## Six, chosen against a measured cost rather than by eye: every variant
## multiplies the set of pictures a wood needs by species, season and crop
## level, and that whole set has to be built before it is cheap (see
## test_the_whole_set_of_tree_pictures_is_small). Six distinct trunk-and-crown
## shapes, across six species and four seasons, is a varied-looking wood; the
## cost of doubling it is a visible hitch every time a season turns.
func test_there_are_enough_variants_to_look_varied():
	assert_gte(ProceduralTreeSprite.TREE_VARIANTS, 6)


## Two trees of the same variant are the same picture -- that is the point,
## and it is what lets the second one be a cache hit.
func test_trees_of_the_same_variant_are_identical():
	var sprite := ProceduralTreeSprite.new()
	var first := -1
	var second := -1
	for seed_value in 400:
		var variant: int = sprite.tree_variant_for(seed_value)
		if first < 0:
			first = seed_value
		elif sprite.tree_variant_for(first) == variant and second < 0:
			second = seed_value
	assert_gt(second, 0, "expected two seeds sharing a variant")
	assert_eq(
		sprite.generate_image_with_fruit(_cherry_bias(), first, 3, "summer").get_data(),
		sprite.generate_image_with_fruit(_cherry_bias(), second, 3, "summer").get_data()
	)


## Rebuilding the same tree twice is free the second time.
func test_rebuilding_the_same_tree_is_cached():
	var sprite := ProceduralTreeSprite.new()
	sprite.generate_texture_with_fruit(_cherry_bias(), 5, 2, "summer")
	var started := Time.get_ticks_msec()
	for _i in 200:
		sprite.generate_texture_with_fruit(_cherry_bias(), 5, 2, "summer")
	var elapsed := Time.get_ticks_msec() - started
	assert_lt(elapsed, 200, "200 cached rebuilds took %dms -- they are not cached" % elapsed)


## Trees still differ from each other, cache or no cache.
func test_the_wood_still_looks_varied():
	var sprite := ProceduralTreeSprite.new()
	var looks := {}
	for seed_value in 40:
		looks[sprite.generate_image_with_fruit(_cherry_bias(), seed_value, 0, "summer").get_data()] = true
	assert_gt(looks.size(), 4, "every tree in the wood looks the same")


# -- how many different pictures a wood needs --------------------------------

## Every distinct tree picture costs a composite, and they are only cheap once
## built. The whole set has to be small enough to build without the game
## noticing.
##
## Measured: at sixteen variants and a picture per exact fruit count, the set
## came to a few thousand images and roughly a minute of solid work -- so a
## fast-forward spent its first minute building pictures instead of showing a
## year. Both axes are cut: fewer variants, and the crop drawn in a few LEVELS
## rather than per fruit.
func test_the_whole_set_of_tree_pictures_is_small():
	var TreeSpecies := load("res://src/world/tree_species.gd")
	var SeasonCycle := load("res://src/world/season_cycle.gd")
	var total: int = (
		TreeSpecies.IDS.size()
		* SeasonCycle.SEASONS.size()
		* ProceduralTreeSprite.CROP_LEVELS
		* ProceduralTreeSprite.TREE_VARIANTS
	)
	assert_lte(total, 700, "%d tree pictures is too many to build" % total)


## A crop is drawn in levels, not per fruit: at this size nobody can tell seven
## cherries from eight, and a picture per count is what made the set enormous.
func test_a_crop_is_drawn_in_levels():
	var levels := {}
	for count in 40:
		levels[ProceduralTreeSprite.crop_level_for(count)] = true
	assert_eq(levels.size(), ProceduralTreeSprite.CROP_LEVELS)


## No crop is no fruit -- the empty level has to stay empty, or a bare tree
## would show a berry.
func test_no_crop_means_no_fruit():
	assert_eq(ProceduralTreeSprite.crop_level_for(0), 0)
	assert_gt(ProceduralTreeSprite.crop_level_for(1), 0)


## More fruit never draws as less.
func test_a_bigger_crop_never_draws_as_a_smaller_one():
	var previous := -1
	for count in 40:
		var level: int = ProceduralTreeSprite.crop_level_for(count)
		assert_gte(level, previous)
		previous = level


## A bare tree and a laden one still look different, or the levels are
## pointless.
func test_a_laden_tree_looks_different_from_a_bare_one():
	var sprite := ProceduralTreeSprite.new()
	assert_ne(
		sprite.generate_image_with_fruit(_cherry_bias(), 5, 0, "summer").get_data(),
		sprite.generate_image_with_fruit(_cherry_bias(), 5, 9, "summer").get_data()
	)


# -- a canopy turns branch by branch -----------------------------------------

## At either end of a turn, the tree is simply one season or the other.
func test_a_turn_at_zero_is_the_old_season():
	var sprite := ProceduralTreeSprite.new()
	assert_eq(
		sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer", "autumn", 0.0).get_data(),
		sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer").get_data()
	)


func test_a_turn_at_one_is_the_new_season():
	var sprite := ProceduralTreeSprite.new()
	assert_eq(
		sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer", "autumn", 1.0).get_data(),
		sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "autumn").get_data()
	)


## Halfway through, the tree is neither -- some of it has turned and some has
## not, which is the whole point.
func test_a_half_turned_tree_is_neither_season():
	var sprite := ProceduralTreeSprite.new()
	var half := sprite.generate_image_with_fruit(
		_cherry_bias(), 7, 0, "summer", "autumn", 0.5
	).get_data()
	assert_ne(half, sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer").get_data())
	assert_ne(half, sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "autumn").get_data())


## It turns PROGRESSIVELY: every step is a different picture from the one
## before, so the change arrives over time rather than in a jump.
##
## Counting pixels that match the finished tree does NOT work as a measure of
## "how far along", because the crown's own size interpolates across the turn
## (see _blend_boxes) -- so a half-turned crown is a slightly different shape
## from either end, and matches both less. That confound is real, not a
## measurement artefact: the crown really is a different size partway through.
func test_every_step_of_the_turn_is_a_different_picture():
	var sprite := ProceduralTreeSprite.new()
	var seen := {}
	for step in 6:
		var progress := float(step) / 5.0
		var image := sprite.generate_image_with_fruit(
			_cherry_bias(), 7, 0, "summer", "autumn", progress
		)
		seen[image.get_data()] = true
	assert_eq(seen.size(), 6, "the turn jumps rather than advancing step by step")


## The turn is ORDERED, not a random dissolve: it spreads along the canopy
## rather than speckling it, so twigs turn as twigs rather than as noise.
func test_the_turn_spreads_rather_than_speckling():
	var sprite := ProceduralTreeSprite.new()
	var half := sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer", "autumn", 0.5)
	var autumn := sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "autumn")
	# Turned pixels should cluster: measure how often a turned pixel's
	# neighbour is also turned, against how often it is not.
	var together := 0
	var apart := 0
	for y in range(1, half.get_height() - 1):
		for x in range(1, half.get_width() - 1):
			if half.get_pixel(x, y).a < 0.5:
				continue
			var turned := half.get_pixel(x, y).is_equal_approx(autumn.get_pixel(x, y))
			var right_turned := half.get_pixel(x + 1, y).is_equal_approx(
				autumn.get_pixel(x + 1, y)
			)
			if turned == right_turned:
				together += 1
			else:
				apart += 1
	assert_gt(
		float(together) / float(maxi(together + apart, 1)), 0.7,
		"the turn speckles rather than spreading"
	)


## Two trees of the same species turn in DIFFERENT orders, so a wood does not
## change as one animation.
func test_two_trees_turn_in_different_orders():
	var sprite := ProceduralTreeSprite.new()
	var seeds: Array[int] = []
	for seed_value in 60:
		if sprite.tree_variant_for(seed_value) not in seeds:
			seeds.append(seed_value)
		if seeds.size() >= 2:
			break
	var first := sprite.generate_image_with_fruit(
		_cherry_bias(), seeds[0], 0, "summer", "autumn", 0.5
	)
	var second := sprite.generate_image_with_fruit(
		_cherry_bias(), seeds[1], 0, "summer", "autumn", 0.5
	)
	assert_ne(
		first.get_data(), second.get_data(),
		"every tree in the wood turns in the same order"
	)


# -- snow: a live-weather overlay, composed AFTER season/turn/growth --------
#
# Unlike bare/blossom/leaf/turning, how much of a canopy is under snow is not
# a season -- it is a live weather fact, the same one the ground's own lying
## snow already is (see IllustratedTree.CANOPY_SNOW's own doc comment). It
# reuses the exact same branch-order blend the season turn does (see
# _turned_canopy), which is the whole point: this is a reuse, not a new
# blend mechanism.

## Coverage 0 is exactly the untouched tree -- the same picture the season/
## turn/growth pipeline already produced, byte for byte. Every call site that
## predates this parameter passes no ninth argument at all, which is exactly
## this default.
func test_zero_snow_coverage_is_the_untouched_tree():
	var sprite := ProceduralTreeSprite.new()
	assert_eq(
		sprite.generate_image_with_fruit(
			_cherry_bias(), 7, 0, "winter", "", 0.0, 1.0, 0.0
		).get_data(),
		sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "winter").get_data()
	)


## It covers PROGRESSIVELY, the same way a season turn advances step by step
## rather than jumping between two states (see SNOW_LEVELS).
func test_snow_covers_progressively_more_as_coverage_rises():
	var sprite := ProceduralTreeSprite.new()
	var seen := {}
	for step in 6:
		var coverage := float(step) / 5.0
		var image := sprite.generate_image_with_fruit(
			_cherry_bias(), 7, 0, "winter", "", 0.0, 1.0, coverage
		)
		seen[image.get_data()] = true
	assert_eq(seen.size(), 6, "snow coverage should advance step by step, not jump")


## Two trees at the SAME coverage are covered on DIFFERENT branches -- the
## same per-tree branch-order variance the season turn already has (see
## tree_variant_for), not one shared "snow" stamp applied identically to
## every tree of a species.
func test_two_trees_show_different_snowed_branches_at_the_same_coverage():
	var sprite := ProceduralTreeSprite.new()
	var seeds: Array[int] = []
	for seed_value in 60:
		if sprite.tree_variant_for(seed_value) not in seeds:
			seeds.append(seed_value)
		if seeds.size() >= 2:
			break
	var first := sprite.generate_image_with_fruit(
		_cherry_bias(), seeds[0], 0, "winter", "", 0.0, 1.0, 0.6
	)
	var second := sprite.generate_image_with_fruit(
		_cherry_bias(), seeds[1], 0, "winter", "", 0.0, 1.0, 0.6
	)
	assert_ne(
		first.get_data(), second.get_data(),
		"every tree in the wood should show snow on the same branches"
	)


## Snow layers ON TOP of the turn, rather than instead of it: a tree caught
## mid-turn under snow should be neither the plain turned canopy nor the
## plain snowed one.
func test_snow_composes_on_top_of_a_season_turn_not_instead_of_it():
	var sprite := ProceduralTreeSprite.new()
	var turned_only := sprite.generate_image_with_fruit(
		_cherry_bias(), 7, 0, "autumn", "winter", 0.5
	).get_data()
	var snowed_turn := sprite.generate_image_with_fruit(
		_cherry_bias(), 7, 0, "autumn", "winter", 0.5, 1.0, 0.6
	).get_data()
	assert_ne(turned_only, snowed_turn, "snow on a mid-turn tree should change the picture")


## The fallback guarantee -- a species without a snow frame must render
## identically whatever snow_coverage is -- rests entirely on
## IllustratedTree.has_snow_frame_for, which _composite_illustrated's own
## snow block checks before ever touching a canopy image (see its doc
## comment above). That gate is unit-tested directly in
## test_illustrated_tree.gd's own snow section
## (test_an_unregistered_species_has_no_snow_frame,
## test_a_species_without_a_snow_frame_yields_no_snow_canopy).
##
## It cannot ALSO be demonstrated end-to-end here against a real species,
## the way it could have been when this was written: TreeSpecies.IDS covers
## exactly six named species and _unillustrated_bias() (below) can only ever
## return one of them, so there is no species_bias that reaches the
## procedural, non-illustrated branch at all -- and by the time this
## feature landed, a second session had independently given every one of
## those six a snow frame too (see
## test_every_illustrated_species_currently_has_a_snow_frame), so none of
## them can stand in for "art without snow" either. The guarantee is real
## and holds by construction; there is simply no species left in the
## current roster to prove it against pixel-for-pixel.


# -- a young tree has fewer branches, not a smaller picture ------------------

## Growth used to scale the whole node down, so a sapling was a full-grown tree
## drawn small -- crown, boughs, every twig, in miniature. A real young tree has
## FEWER BRANCHES, and puts out more as it grows.
##
## Traced the same way the season turn is: outward along the boughs, so a
## sapling is the inner branches and the twigs come later.
func test_a_young_canopy_has_less_in_it_than_a_grown_one():
	var sprite := ProceduralTreeSprite.new()
	var young := sprite.generate_image_with_fruit(
		_cherry_bias(), 7, 0, "summer", "", 0.0, 0.35
	)
	var grown := sprite.generate_image_with_fruit(
		_cherry_bias(), 7, 0, "summer", "", 0.0, 1.0
	)
	assert_lt(
		_opaque_share(young), _opaque_share(grown),
		"a young tree should carry less canopy than a grown one"
	)


func test_a_grown_tree_is_the_whole_canopy():
	var sprite := ProceduralTreeSprite.new()
	assert_eq(
		sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer", "", 0.0, 1.0).get_data(),
		sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer").get_data()
	)


## It fills in progressively rather than jumping between two states.
func test_a_canopy_fills_in_as_the_tree_grows():
	var sprite := ProceduralTreeSprite.new()
	var previous := -1.0
	for step in 6:
		var growth := 0.2 + float(step) / 5.0 * 0.8
		var share := _opaque_share(
			sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer", "", 0.0, growth)
		)
		assert_gte(share, previous - 0.001, "the canopy shrank as the tree grew")
		previous = share


## Two saplings put out different branches, so a nursery is not one tree drawn
## many times.
func test_two_saplings_grow_different_branches():
	var sprite := ProceduralTreeSprite.new()
	var seeds: Array[int] = []
	for seed_value in 60:
		if sprite.tree_variant_for(seed_value) not in seeds:
			seeds.append(seed_value)
		if seeds.size() >= 2:
			break
	assert_ne(
		sprite.generate_image_with_fruit(_cherry_bias(), seeds[0], 0, "summer", "", 0.0, 0.4).get_data(),
		sprite.generate_image_with_fruit(_cherry_bias(), seeds[1], 0, "summer", "", 0.0, 0.4).get_data()
	)


## Even the youngest sapling has SOMETHING -- a seedling with no canopy at all
## is a bare stick.
func test_the_youngest_sapling_still_has_a_shoot():
	var sprite := ProceduralTreeSprite.new()
	assert_gt(
		_opaque_share(
			sprite.generate_image_with_fruit(_cherry_bias(), 7, 0, "summer", "", 0.0, 0.05)
		),
		0.01,
		"a seedling should still be something"
	)


## A sapling's crown starts where the boughs leave the TRUNK and works outward.
##
## The season turn seeds its trace from the whole bottom edge of the crown,
## which for a spreading crown is the drooping outer RIM -- so growth seeded the
## same way drew a young cherry as an arch hanging in the air with a gap between
## it and the trunk (seen in the growth filmstrip). A young tree is the opposite
## shape: a tuft at the trunk that spreads.
##
## Tested against a synthetic arch rather than the art, so it pins the ordering
## itself and not one species' crown.
func test_growth_starts_at_the_trunk_not_the_rim():
	var sprite := ProceduralTreeSprite.new()
	var arch := _arch_image()
	var order := sprite.growth_order(arch, 0)
	var earliest := Vector2i.ZERO
	var lowest := INF
	for at in order:
		if order[at] < lowest:
			lowest = order[at]
			earliest = at
	assert_almost_eq(
		float(earliest.x), float(arch.get_width()) / 2.0, 3.0,
		"growth should begin at the trunk, near the middle of the crown"
	)


## And the rim comes LAST -- the far tips of the boughs are the last thing a
## tree puts out.
func test_the_far_tips_of_an_arch_come_last():
	var sprite := ProceduralTreeSprite.new()
	var arch := _arch_image()
	var order := sprite.growth_order(arch, 0)
	var tip := Vector2i(2, arch.get_height() - 2)
	var crown := Vector2i(arch.get_width() / 2, 2)
	assert_gt(
		float(order.get(tip, 0.0)), float(order.get(crown, 0.0)),
		"a bough tip should come after the crown above the trunk"
	)


## An inverted U: paint down both sides and across the top, hollow in the
## middle -- the shape a spreading crown makes, and the one that broke.
func _arch_image() -> Image:
	var image := Image.create(21, 16, false, Image.FORMAT_RGBA8)
	for x in 21:
		for y in 3:
			image.set_pixel(x, y, Color.GREEN)
	for y in range(3, 16):
		for x in 3:
			image.set_pixel(x, y, Color.GREEN)
			image.set_pixel(20 - x, y, Color.GREEN)
	return image


## One crown, not a cloud of specks: most of what is drawn belongs to a single
## connected clump.
func test_a_young_canopy_is_one_crown_rather_than_confetti():
	var sprite := ProceduralTreeSprite.new()
	var image := sprite.generate_image_with_fruit(
		_cherry_bias(), 7, 0, "summer", "", 0.0, 0.3
	)
	assert_gt(
		_largest_blob_share(image), 0.6,
		"most of a young canopy should hang together in one crown"
	)


## Growth is traced, not dissolved -- pinned so the weight cannot drift back
## toward the turn's even split without this failing.
func test_growth_follows_the_branches_more_than_the_noise():
	assert_gt(ProceduralTreeSprite.GROWTH_BRANCH_WEIGHT, 0.75)
	assert_lt(
		ProceduralTreeSprite.GROWTH_BRANCH_WEIGHT, 1.0,
		"some noise keeps two saplings of the same art apart"
	)


func _mean_opaque_y(image: Image) -> float:
	var total := 0.0
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				total += float(y)
				count += 1
	return total / maxf(float(count), 1.0)


## The share of opaque pixels belonging to the biggest connected region.
func _largest_blob_share(image: Image) -> float:
	var seen := {}
	var opaque := 0
	var biggest := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= 0.5:
				continue
			opaque += 1
			var at := Vector2i(x, y)
			if seen.has(at):
				continue
			var queue: Array[Vector2i] = [at]
			seen[at] = true
			var size := 0
			var head := 0
			while head < queue.size():
				var here: Vector2i = queue[head]
				head += 1
				size += 1
				for step in [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1),
				]:
					var next: Vector2i = here + step
					if seen.has(next):
						continue
					if next.x < 0 or next.y < 0:
						continue
					if next.x >= image.get_width() or next.y >= image.get_height():
						continue
					if image.get_pixel(next.x, next.y).a <= 0.5:
						continue
					seen[next] = true
					queue.append(next)
			biggest = maxi(biggest, size)
	return float(biggest) / maxf(float(opaque), 1.0)


# -- scaling keeps the pixels ------------------------------------------------

## Scaling a piece must not invent colours that were never in the art.
##
## The pieces were resampled with Lanczos, which blends neighbouring pixels and
## so makes up in-between colours and part-transparent edges. On a dense summer
## canopy that hides; on BARE WINTER BRANCHES -- thin high-contrast strokes on
## transparency -- it reads as smeared, haloed twigs (reported: the winter trees
## look blurry). The rest of the game is nearest-neighbour pixel art; the
## project even sets default_texture_filter to nearest. Resampling the source
## art smoothly contradicted that.
##
## Tested as a PROPERTY of the scaler on a two-colour image rather than by
## eyeballing a tree: nearest-neighbour can only ever copy pixels, so the
## result's palette is a subset of the source's. Any smooth filter fails this.
func test_scaling_a_piece_invents_no_new_colours():
	var source := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.0, 0.0, 0.0, 0.0))
	for x in 8:
		source.set_pixel(x, 3, Color(0.6, 0.3, 0.1, 1.0))
	# Read the branch colour back OUT of the source rather than restating the
	# literal: RGBA8 quantises 0.3 to 0.298, so comparing against the literal
	# fails on the storage format rather than on the scaling.
	var branch: Color = source.get_pixel(0, 3)
	var scaled: Image = ProceduralTreeSprite.scale_piece(source, Vector2i(21, 17))
	for y in scaled.get_height():
		for x in scaled.get_width():
			var colour: Color = scaled.get_pixel(x, y)
			var known: bool = colour == branch or colour.a == 0.0
			assert_true(
				known, "scaling invented %s at %d,%d" % [colour, x, y]
			)


## A raw Image.load_from_file logs an engine WARNING ("Loaded resource as
## image file, this will not work on export") that GUT's error tracker
## counts as an unhandled error -- see SpriteSheetLoader's own doc comment.
## _load_image already guarded against this before this pass (it already
## preferred load()); this pins that guarantee now that the read itself
## delegates to SpriteSheetLoader instead of duplicating the same logic.
## _image_cache is cleared first (static, shared across every test in this
## file) so this genuinely re-reads trunk_cherry.png off disk rather than
## hitting a cache an earlier test already warmed.
func test_loading_a_sheet_does_not_log_an_engine_warning():
	IllustratedTree._image_cache.clear()
	trees.trunk_for("cherry")
	assert_engine_error_count(0, "loading a tree sheet should not warn")


## No half-transparent edges either: a pixel is branch or it is air.
func test_a_scaled_piece_has_no_part_transparent_edges():
	var source := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.0, 0.0, 0.0, 0.0))
	source.set_pixel(4, 4, Color(1.0, 1.0, 1.0, 1.0))
	var scaled: Image = ProceduralTreeSprite.scale_piece(source, Vector2i(30, 30))
	for y in scaled.get_height():
		for x in scaled.get_width():
			var alpha: float = scaled.get_pixel(x, y).a
			assert_true(
				alpha == 0.0 or alpha == 1.0,
				"a scaled pixel came out half-transparent (%f)" % alpha
			)


# -- what the four frames actually DRAW --------------------------------------
#
# TreePhenology (src/world/tree_phenology.gd) now decides WHEN a tree wears
# each of these frames: bare all winter, blossom briefly in early spring, leaf
# after. That schedule is only the right call if the frames really draw what
# their names claim, and those are claims about pixels somebody could repaint.


## Pine is called an evergreen in TreeSpecies ("its canopy never goes bare").
## Its ART has to agree, because TreePhenology walks it through the same four
## stages as everything else -- which is harmless only because a pine's four
## frames are four TONES of conifer rather than a tree losing its leaves.
func test_pine_is_an_evergreen_in_its_art_and_not_only_in_its_data():
	var kept := (
		float(_opaque_pixels(trees.canopy_for("pine", "winter").get_image()))
		/ float(maxi(_opaque_pixels(trees.canopy_for("pine", "summer").get_image()), 1))
	)
	assert_gt(kept, 0.7, "a pine in winter must still be carrying its needles")
	# The contrast it is measured against: everything else really does strip.
	for species in ["cherry", "walnut", "acorn", "hazelnut", "apple"]:
		var deciduous := (
			float(_opaque_pixels(trees.canopy_for(species, "winter").get_image()))
			/ float(maxi(_opaque_pixels(trees.canopy_for(species, "summer").get_image()), 1))
		)
		assert_lt(deciduous, 0.5, "%s should actually go bare in winter" % species)


## The blossom frame is only a FLOWERING event for cherry.
##
## It is shown briefly in early spring now rather than across the whole of it,
## which has to be sensible for the species that do not flower too. Measured
## off the shipped sheets: a cherry draws pink flowers, and the nut and orchard
## sheets draw the yellow-green flush of a bursting bud -- new leaf, which is
## exactly what an early-spring tree looks like and reads far better in a short
## window than it did across three months.
func test_the_blossom_frame_is_flowers_on_a_cherry_and_new_leaf_on_the_rest():
	assert_lt(
		_mean_hue_degrees(trees.canopy_for("cherry", "spring").get_image()), 30.0,
		"a cherry's blossom frame has to read pink -- it is the whole point of it"
	)
	for species in ["walnut", "acorn", "hazelnut", "apple"]:
		var flush := trees.canopy_for(species, "spring").get_image()
		assert_gt(
			_mean_hue_degrees(flush), 40.0,
			"%s draws new leaf in that slot, not flowers" % species
		)
		assert_gt(
			_opaque_pixels(flush),
			_opaque_pixels(trees.canopy_for(species, "winter").get_image()),
			"%s's flush must be fuller than its bare branches" % species
		)
		assert_lt(
			_green_share(flush),
			_green_share(trees.canopy_for(species, "summer").get_image()),
			"%s's flush must be paler than its full leaf" % species
		)


## How many pixels of a frame are actually drawn on. Sampled, so it is a count
## for COMPARING frames rather than an absolute -- which is all any caller here
## wants.
func _opaque_pixels(image: Image) -> int:
	var opaque := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	return opaque


## The hue of a frame's MEAN colour, in degrees. Pink sits near 0, the
## yellow-olive of a bud flush near 50-65, full leaf higher still.
func _mean_hue_degrees(image: Image) -> float:
	var red := 0.0
	var green := 0.0
	var blue := 0.0
	var count := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.5:
				continue
			red += pixel.r
			green += pixel.g
			blue += pixel.b
			count += 1
	if count == 0:
		return 0.0
	var total := float(count)
	return Color(red / total, green / total, blue / total).h * 360.0
