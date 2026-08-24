extends GutTest

## Pins IllustratedFlowerHead: slicing assets/sprites/flowers/<archetype>.png
## (an AI-generated 4-stage reference sheet -- bud/opening/full bloom/spent,
## see docs/art/ai_sprite_prompts.md) into 4 ready-to-composite frames per
## archetype, the same "hand-assembled sheet -> SpriteSheetSlicer -> cached
## frames" shape IllustratedAnimalSprite already uses for horse/deer/boar.

const IllustratedFlowerHead = preload("res://src/rendering/illustrated_flower_head.gd")

var generator: IllustratedFlowerHead


func before_each():
	generator = IllustratedFlowerHead.new()


func test_has_archetype_is_true_for_a_supplied_sheet():
	assert_true(generator.has_archetype("cup"))


func test_has_archetype_is_false_for_one_with_no_sheet_yet():
	# Spike and puff are the shape families still drawn procedurally. Layered
	# used to stand here and has since been given a sheet.
	assert_false(generator.has_archetype("spike"))
	assert_false(generator.has_archetype("puff"))
	assert_false(generator.has_archetype("not_a_real_archetype"))


func test_frames_for_returns_exactly_the_four_bloom_stages():
	var frames := generator.frames_for("cup")
	assert_eq(frames.size(), IllustratedFlowerHead.STAGE_COUNT)


func test_frames_for_an_unregistered_archetype_returns_empty():
	assert_eq(generator.frames_for("spike").size(), 0)


func test_every_frame_is_a_real_non_empty_texture():
	for frame in generator.frames_for("cup"):
		var image: Image = frame.get_image()
		assert_gt(image.get_width(), 0)
		assert_gt(image.get_height(), 0)
		assert_gt(_painted_pixel_count(image), 0, "frame should have real painted content, not be blank")


func test_bud_reads_smaller_than_full_bloom():
	# Not a claim about exact shape -- just that the sheet's own stage
	# progression (closed bud -> open bloom) survives slicing: the bud
	# frame's painted content should be noticeably more compact than the
	# full-bloom frame's.
	var frames := generator.frames_for("cup")
	var bud_area := _painted_pixel_count(frames[IllustratedFlowerHead.STAGE_BUD].get_image())
	var bloom_area := _painted_pixel_count(frames[IllustratedFlowerHead.STAGE_FULL_BLOOM].get_image())
	assert_lt(bud_area, bloom_area)


func test_frames_are_cached_not_resliced_every_call():
	var first := generator.frames_for("cup")
	var second := generator.frames_for("cup")
	assert_eq(first, second)


func _painted_pixel_count(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.05:
				count += 1
	return count


# -- a species may bring its own art -----------------------------------------
#
# One sheet per ARCHETYPE is the default because it costs no new art per
# species, and for most species that is right: a real crocus and a real tulip
# are the same shallow cup differing only in colour and size. But a species
# that deserves its own drawing should be able to have one without every other
# species of that archetype changing.

func test_a_species_without_its_own_art_uses_its_archetypes():
	# Crocus and tulip both have their own sheets now, so the fallback is
	# checked with a species that does not: a hypothetical cup-shaped species
	# with no drawing of its own still gets the shared cup sheet.
	assert_eq(
		IllustratedFlowerHead.sheet_path_for("some_other_cup_flower", "cup"),
		IllustratedFlowerHead.sheet_path_for("a_third_cup_flower", "cup"),
		"archetype-mates share a sheet until one is given its own"
	)
	assert_ne(IllustratedFlowerHead.sheet_path_for("some_other_cup_flower", "cup"), "")
	assert_false(generator.has_own_art("some_other_cup_flower"))


## A species given its own sheet stops using the shared one, and does not drag
## its archetype-mates along with it.
func test_a_species_with_its_own_art_stops_using_the_shared_sheet():
	var shared: String = IllustratedFlowerHead.sheet_path_for("some_other_cup_flower", "cup")
	for species in ["crocus", "tulip"]:
		assert_true(generator.has_own_art(species), "%s should have its own sheet" % species)
		assert_ne(
			IllustratedFlowerHead.sheet_path_for(species, "cup"), shared,
			"%s should draw from its own sheet, not the archetype's" % species
		)
	assert_ne(
		IllustratedFlowerHead.sheet_path_for("crocus", "cup"),
		IllustratedFlowerHead.sheet_path_for("tulip", "cup"),
		"two species with their own art should not share a sheet"
	)


func test_a_species_with_no_art_at_all_reports_nothing_to_draw():
	assert_eq(IllustratedFlowerHead.sheet_path_for("clover", "puff"), "")
	assert_false(generator.has_art_for("clover", "puff"))


func test_frames_come_back_for_a_species_covered_by_its_archetype():
	assert_eq(generator.frames_for_species("crocus", "cup").size(), IllustratedFlowerHead.STAGE_COUNT)


func test_a_species_with_nothing_to_draw_gets_no_frames():
	assert_eq(generator.frames_for_species("clover", "puff").size(), 0)


## A raw Image.load_from_file logs an engine WARNING ("Loaded resource as
## image file, this will not work on export") that GUT's error tracker
## counts as an unhandled error -- see SpriteSheetLoader's own doc comment.
## _frame_cache is cleared first (static, shared across every test in this
## file) so this genuinely re-reads cup.png off disk rather than hitting a
## cache an earlier test already warmed.
func test_loading_a_sheet_does_not_log_an_engine_warning():
	IllustratedFlowerHead._frame_cache.clear()
	generator.frames_for("cup")
	assert_engine_error_count(0, "loading a flower sheet should not warn")
