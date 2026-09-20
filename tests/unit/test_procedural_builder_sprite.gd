extends GutTest

## The builder you see on a construction site (docs/concept/building.md,
## "Somebody is working on it"). Asked for directly, watching a village
## raise a cottage: *"the construction site should show a builder working
## on it"*.
##
## Drawn in the same tiny silhouette style as the Lumberjack and the
## Porter, at their own shared size, so the workers a village has out at
## once read at one scale -- and told apart from them at a glance, which is
## the only thing this art has to do that theirs does not.

const ProceduralBuilderSprite = preload("res://src/rendering/procedural_builder_sprite.gd")
const ProceduralLumberjackSprite = preload("res://src/rendering/procedural_lumberjack_sprite.gd")
const ProceduralPorterSprite = preload("res://src/rendering/procedural_porter_sprite.gd")


func test_a_builder_is_drawn_at_the_same_size_as_the_other_workers():
	assert_eq(ProceduralBuilderSprite.SIZE, ProceduralLumberjackSprite.SIZE)
	var image := ProceduralBuilderSprite.new().generate_image()
	assert_eq(image.get_width(), ProceduralBuilderSprite.SIZE)
	assert_eq(image.get_height(), ProceduralBuilderSprite.SIZE)


## A person, not a blank tile: the bug the Porter's own art was written to
## fix was a worker drawn as a floor tile, so this pins that there is a
## real, mostly-transparent figure here rather than a filled square.
func test_a_builder_is_a_figure_rather_than_a_filled_square():
	var image := ProceduralBuilderSprite.new().generate_image()
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	var share := float(opaque) / float(image.get_width() * image.get_height())
	assert_between(share, 0.05, 0.5, "a worker is a silhouette on open ground, not a block")


## Told apart from the two workers already walking a village: same size,
## same style, different person.
func test_a_builder_is_not_the_lumberjack_or_the_porter():
	var builder := ProceduralBuilderSprite.new().generate_image()
	assert_ne(builder.get_data(), ProceduralLumberjackSprite.new().generate_image().get_data())
	assert_ne(builder.get_data(), ProceduralPorterSprite.new().generate_image().get_data())


func test_a_builder_is_the_same_drawing_every_time():
	assert_eq(
		ProceduralBuilderSprite.new().generate_image().get_data(),
		ProceduralBuilderSprite.new().generate_image().get_data()
	)


# -- it has to READ at the size it is actually drawn -----------------------
#
# Measured on a real render at the game's own zoom (tools/probe_
# construction_render.gd): a builder stands about seven world units tall,
# a third the width of the cottage he is raising. At that size a figure is
# a silhouette and nothing else, and the first draft failed twice for
# reasons that are measurable rather than matters of taste -- an apron
# nearly the colour of skin, so the head vanished into the body, and a
# mallet head a third of the body's own area, which read as a grey slab
# floating beside a blob.
#
# Both are pinned against the Lumberjack, who has been out in this world
# since long before this one and reads fine: the same question, already
# answered once.


func _share_of_figure(image: Image, color: Color) -> float:
	var matching := 0
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.5:
				continue
			opaque += 1
			# Within a quantisation step, not exactly: the image is RGBA8,
			# so a colour written as a float comes back rounded to eight
			# bits and Color.is_equal_approx's own epsilon is far tighter
			# than that.
			if (
				absf(pixel.r - color.r) <= 0.01
				and absf(pixel.g - color.g) <= 0.01
				and absf(pixel.b - color.b) <= 0.01
			):
				matching += 1
	return 0.0 if opaque == 0 else float(matching) / float(opaque)


## A head is only a head if it is not the same tone as the body under it.
func test_a_builders_head_reads_against_his_own_body():
	var skin: Color = ProceduralBuilderSprite.SKIN_COLOR
	var apron: Color = ProceduralBuilderSprite.APRON_COLOR
	var lumberjack_contrast: float = absf(
		ProceduralLumberjackSprite.SKIN_COLOR.get_luminance()
		- ProceduralLumberjackSprite.TUNIC_COLOR.get_luminance()
	)
	assert_gte(
		absf(skin.get_luminance() - apron.get_luminance()), lumberjack_contrast * 0.75,
		"a builder's head must stand out from his apron about as well as the woodsman's does from his tunic"
	)


## And a tool is a tool, not a slab. The man's OWN head is the reference,
## not the woodsman's axe -- a mallet head is meant to be chunkier than an
## axe blade, and what went wrong in the first draft was not that it was
## chunky but that it was bigger than the person holding it (measured at
## 13% of the figure against a head's 21%, and detached from the arm, which
## read as a grey slab floating beside a blob). A tool smaller than the
## head above it reads as something a man is carrying.
func test_a_builders_tool_reads_as_a_tool_rather_than_a_slab():
	var builder := ProceduralBuilderSprite.new().generate_image()
	var mallet := _share_of_figure(builder, ProceduralBuilderSprite.HEAD_COLOR)
	var head := _share_of_figure(builder, ProceduralBuilderSprite.SKIN_COLOR)
	assert_gt(mallet, 0.0, "the mallet is really drawn")
	assert_gt(head, 0.0, "and so is the man")
	assert_lt(
		mallet, head,
		"the mallet head is %.0f%% of the figure against the man's own head at %.0f%%"
		% [mallet * 100.0, head * 100.0]
	)


# -- and he is visibly loaded on the way back -----------------------------
#
# Asked for directly: *"the builders should carry materials to the site"*.
# A builder now walks a real round -- out to the store empty-handed, back
# to the site with a load (see ConstructionWorkerMarker) -- and which leg
# of it he is on has to read at village zoom, where he is seven world units
# tall and a silhouette is all there is.


func _carrying() -> Image:
	return ProceduralBuilderSprite.new().generate_image(true)


func _empty_handed() -> Image:
	return ProceduralBuilderSprite.new().generate_image(false)


## Told apart at a glance from himself: the same man, visibly carrying.
func test_a_loaded_builder_is_told_apart_from_the_empty_handed_one():
	var loaded := _carrying()
	var empty := _empty_handed()
	assert_ne(loaded.get_data(), empty.get_data(), "a load you cannot see is not a load")
	var differing := 0
	for y in ProceduralBuilderSprite.SIZE:
		for x in ProceduralBuilderSprite.SIZE:
			if loaded.get_pixel(x, y) != empty.get_pixel(x, y):
				differing += 1
	var figure := 0
	for y in ProceduralBuilderSprite.SIZE:
		for x in ProceduralBuilderSprite.SIZE:
			if loaded.get_pixel(x, y).a > 0.5:
				figure += 1
	assert_gt(
		float(differing) / float(figure), 0.15,
		"only %d of %d pixels change -- at this size that is not a difference anyone sees"
		% [differing, figure]
	)


## The same man: he does not change size, silhouette budget, or drawing
## between the two legs of his own round.
func test_a_loaded_builder_is_still_a_figure_rather_than_a_filled_square():
	var loaded := _carrying()
	assert_eq(loaded.get_width(), ProceduralBuilderSprite.SIZE)
	var opaque := 0
	for y in loaded.get_height():
		for x in loaded.get_width():
			if loaded.get_pixel(x, y).a > 0.5:
				opaque += 1
	var share := float(opaque) / float(loaded.get_width() * loaded.get_height())
	assert_between(share, 0.05, 0.5, "a loaded worker is still a silhouette on open ground")
	assert_eq(_carrying().get_data(), loaded.get_data(), "and the same drawing every time")


## A man with a load on his shoulder is not also swinging a mallet.
func test_the_mallet_is_down_while_his_arms_are_full():
	assert_eq(
		_share_of_figure(_carrying(), ProceduralBuilderSprite.HEAD_COLOR), 0.0,
		"the mallet is put down to carry"
	)
	assert_gt(
		_share_of_figure(_empty_handed(), ProceduralBuilderSprite.HEAD_COLOR), 0.0,
		"precondition: he has one in hand on the way out"
	)


## And the load is really drawn, at a size that reads: bigger than the
## mallet head he put down (he is carrying a building's worth of timber in
## stages, not a hand tool) and still smaller than the man.
func test_the_load_reads_as_something_a_man_is_carrying():
	var loaded := _carrying()
	var load_share := _share_of_figure(loaded, ProceduralBuilderSprite.LOAD_COLOR)
	var mallet_share := _share_of_figure(_empty_handed(), ProceduralBuilderSprite.HEAD_COLOR)
	var body_share := _share_of_figure(loaded, ProceduralBuilderSprite.APRON_COLOR)
	assert_gt(load_share, mallet_share, "a load smaller than a mallet head is not a load")
	assert_lt(load_share, body_share, "and one bigger than the man carrying it is a cart")


## The lesson the mallet already taught this sprite once, applied to the
## load: drawn detached, it reads as a slab floating beside a blob rather
## than as something a man is holding. Every pixel of the load must touch
## the figure, directly or through the rest of the load.
func test_the_load_rests_on_him_rather_than_floating_beside_him():
	var loaded := _carrying()
	var load_pixels: Array = []
	for y in ProceduralBuilderSprite.SIZE:
		for x in ProceduralBuilderSprite.SIZE:
			if _is_load(loaded, x, y):
				load_pixels.append(Vector2i(x, y))
	assert_gt(load_pixels.size(), 0, "precondition: the load is drawn")
	var touching := false
	for pixel in load_pixels:
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var neighbour := (pixel as Vector2i) + Vector2i(dx, dy)
				if neighbour.x < 0 or neighbour.y < 0:
					continue
				if neighbour.x >= ProceduralBuilderSprite.SIZE or neighbour.y >= ProceduralBuilderSprite.SIZE:
					continue
				if _is_load(loaded, neighbour.x, neighbour.y):
					continue
				if loaded.get_pixel(neighbour.x, neighbour.y).a > 0.5:
					touching = true
	assert_true(touching, "the load has to be attached to the man, or it is a slab in the air")


## And it rides above his waist, because a load drawn at his feet is a
## crate on the ground. Measured against the MAN -- the middle of his own
## apron -- rather than against the middle of the canvas, which says
## nothing about where a body happens to stand on it.
func test_the_load_rides_above_his_waist():
	var loaded := _carrying()
	var load_middle := _middle_row_of(loaded, ProceduralBuilderSprite.LOAD_COLOR)
	var waist := _middle_row_of(loaded, ProceduralBuilderSprite.APRON_COLOR)
	assert_gt(waist, 0.0, "precondition: there is a man to carry it")
	assert_lt(load_middle, waist, "the load's middle is above his own")


func _middle_row_of(image: Image, color: Color) -> float:
	var rows := 0.0
	var count := 0.0
	for pixel in _pixels_of(image, color):
		rows += float((pixel as Vector2i).y)
		count += 1.0
	return 0.0 if count == 0.0 else rows / count


func _is_load(image: Image, x: int, y: int) -> bool:
	var pixel := image.get_pixel(x, y)
	if pixel.a <= 0.5:
		return false
	var load_color: Color = ProceduralBuilderSprite.LOAD_COLOR
	return (
		absf(pixel.r - load_color.r) <= 0.01
		and absf(pixel.g - load_color.g) <= 0.01
		and absf(pixel.b - load_color.b) <= 0.01
	)


# -- it has to read against what it is drawn over -------------------------
#
# The same measured yardstick the head already answers to: the Lumberjack's
# own skin-against-tunic contrast, which has been out in this world long
# enough to prove it reads. The load is carried OVER the apron and rests
# AGAINST the head, so it owes both -- pale sawn timber, brighter than
# either, rather than one more brown in a figure already made of browns.


func _lumberjack_contrast() -> float:
	return absf(
		ProceduralLumberjackSprite.SKIN_COLOR.get_luminance()
		- ProceduralLumberjackSprite.TUNIC_COLOR.get_luminance()
	)


func test_the_load_reads_against_the_apron_it_is_carried_over():
	var load_color: Color = ProceduralBuilderSprite.LOAD_COLOR
	var apron: Color = ProceduralBuilderSprite.APRON_COLOR
	assert_gte(
		absf(load_color.get_luminance() - apron.get_luminance()), _lumberjack_contrast() * 0.75,
		"a load the tone of the apron under it is a stain, not a load"
	)


## Less is owed here than against the apron -- a load rests against a head
## rather than being drawn over it, so they need only be told apart, not
## separated. A third of the same yardstick, measured rather than guessed.
func test_the_load_reads_against_the_head_it_rests_beside():
	var load_color: Color = ProceduralBuilderSprite.LOAD_COLOR
	var skin: Color = ProceduralBuilderSprite.SKIN_COLOR
	assert_gte(
		absf(load_color.get_luminance() - skin.get_luminance()), _lumberjack_contrast() * 0.3,
		"a load the tone of his own head merges with it at this size"
	)


## And it must not swallow the man. Measured on a real render at the game's
## own zoom (tools/probe_construction_haul.gd, `loaded.png`): a bundle
## drawn up at head height put pale timber where the head was, and skin and
## sawn wood are near enough in tone that the two merged into one pale mass
## with a brown body under it -- the same failure the mallet head had, one
## step along. A load is carried BESIDE the head, never over it, and the
## dark apron between them is what keeps the two readable.
func test_the_load_never_covers_or_touches_his_head():
	var loaded := _carrying()
	var empty := _empty_handed()
	var skin_loaded := _pixels_of(loaded, ProceduralBuilderSprite.SKIN_COLOR)
	var skin_empty := _pixels_of(empty, ProceduralBuilderSprite.SKIN_COLOR)
	assert_eq(
		skin_loaded, skin_empty,
		"the head is the same head on both legs of the round -- the load does not cover it"
	)
	for pixel in _pixels_of(loaded, ProceduralBuilderSprite.LOAD_COLOR):
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			assert_false(
				skin_loaded.has((pixel as Vector2i) + step),
				"the load at %s is right against his head, and the two merge at this size" % pixel
			)


func _pixels_of(image: Image, color: Color) -> Dictionary:
	var found := {}
	for y in ProceduralBuilderSprite.SIZE:
		for x in ProceduralBuilderSprite.SIZE:
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.5:
				continue
			if (
				absf(pixel.r - color.r) <= 0.01
				and absf(pixel.g - color.g) <= 0.01
				and absf(pixel.b - color.b) <= 0.01
			):
				found[Vector2i(x, y)] = true
	return found
