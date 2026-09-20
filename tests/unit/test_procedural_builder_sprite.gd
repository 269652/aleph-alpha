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
