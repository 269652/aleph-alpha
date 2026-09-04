extends GutTest

## IllustratedItemSprite: per-item combat art sliced from a two-row composite
## sheet (docs/concept/item_illustrations.md, "Combat sheets: attack,
## defense, condition -- wooden_club"). Row 1 is an 8-frame attack cycle; row
## 2 is defense/worn/broken at fixed indices. Mirrors IllustratedAnimalSprite's
## `_SHEETS`/`has_action` shape but keeps each CELL whole (the grip pivot has
## to stay put across a swing) rather than cropping to content and standing
## frames on a baseline the way an animal's feet need.

const IllustratedItemSprite = preload("res://src/rendering/illustrated_item_sprite.gd")
const Painter = preload("res://src/rendering/wooden_club_sheet_painter.gd")

var sprite: IllustratedItemSprite


func before_each():
	sprite = IllustratedItemSprite.new()


func test_wooden_club_is_the_registered_pilot_item():
	assert_true(sprite.has_item("wooden_club"))


func test_items_without_a_sheet_are_not_registered():
	assert_false(sprite.has_item("iron_sword"))
	assert_false(sprite.has_item("crude_blade"))
	assert_false(sprite.has_item("totally_unknown_item"))


func test_attack_is_the_only_action_and_there_is_no_fallback_chain():
	assert_true(sprite.has_action("wooden_club", "attack"))
	assert_false(sprite.has_action("wooden_club", "walk"))
	assert_false(sprite.has_action("wooden_club", "idle"))
	assert_false(sprite.has_action("iron_sword", "attack"))


func test_registered_bands_match_the_painter_that_generated_the_sample_sheet():
	# The sheet is generated, so its bands are derived, not hand-measured --
	# but they are still pinned literally in _SHEETS (a wrong band slices
	# garbage silently), and this keeps the two from drifting apart.
	assert_eq(sprite.attack_bands("wooden_club"), [Painter.attack_row_band()])
	assert_eq(sprite.condition_bands("wooden_club"), [Painter.condition_row_band()])


func test_attack_cycle_is_eight_frames():
	assert_eq(sprite.generate_textures("wooden_club", "attack").size(), 8)


func test_unknown_requests_yield_no_textures():
	assert_eq(sprite.generate_textures("wooden_club", "walk").size(), 0)
	assert_eq(sprite.generate_textures("iron_sword", "attack").size(), 0)


func test_condition_row_reads_defense_worn_broken_by_fixed_index():
	assert_eq(IllustratedItemSprite.CONDITION_INDEX, {"defense": 0, "worn": 1, "broken": 2})
	for condition in ["defense", "worn", "broken"]:
		assert_true(sprite.has_condition("wooden_club", condition), condition)
		assert_not_null(sprite.condition_texture("wooden_club", condition), condition)


func test_pristine_has_no_cell_of_its_own():
	# A pristine club is simply the attack cycle's own neutral frame; the
	# sheet does not spend a cell on it.
	assert_false(sprite.has_condition("wooden_club", "pristine"))
	assert_null(sprite.condition_texture("wooden_club", "pristine"))
	assert_null(sprite.condition_texture("iron_sword", "worn"))


func test_frames_keep_the_whole_cell_so_the_grip_pivot_stays_put():
	var frames := sprite.generate_textures("wooden_club", "attack")
	for index in frames.size():
		var image: Image = frames[index].get_image()
		assert_eq(image.get_width(), Painter.CELL_SIZE.x, "frame %d width" % (index + 1))
		assert_eq(image.get_height(), Painter.CELL_SIZE.y, "frame %d height" % (index + 1))
		var grip := Vector2i(Painter.PIVOT)
		assert_gt(image.get_pixel(grip.x, grip.y).a, 0.5, "frame %d: the grip must be wood, in place" % (index + 1))


func test_frames_have_no_leftover_magenta_ground():
	var frame: Image = sprite.generate_textures("wooden_club", "attack")[4].get_image()
	assert_almost_eq(frame.get_pixel(0, 0).a, 0.0, 0.01, "top-left corner should be transparent")
	assert_almost_eq(frame.get_pixel(frame.get_width() - 1, frame.get_height() - 1).a, 0.0, 0.01, "bottom-right corner should be transparent")
	var survivors := 0
	for y in frame.get_height():
		for x in frame.get_width():
			var c := frame.get_pixel(x, y)
			if c.a > 0.5 and c.r > 0.8 and c.g < 0.2 and c.b > 0.8:
				survivors += 1
	assert_eq(survivors, 0, "no opaque magenta pixel should survive chroma-keying")


func test_frames_carry_no_divider_line_pixels():
	var frame: Image = sprite.generate_textures("wooden_club", "attack")[0].get_image()
	var pale := 0
	for y in frame.get_height():
		for x in frame.get_width():
			var c := frame.get_pixel(x, y)
			if c.a > 0.5 and c.r >= 0.9 and c.g >= 0.9 and c.b >= 0.9 and c.s <= 0.05:
				pale += 1
	assert_eq(pale, 0)


func test_frames_have_real_wood_colored_content():
	var frame: Image = sprite.generate_textures("wooden_club", "attack")[0].get_image()
	var wood := 0
	for y in frame.get_height():
		for x in frame.get_width():
			var c := frame.get_pixel(x, y)
			if c.a > 0.5 and c.r > c.b and c.r > c.g:
				wood += 1
	assert_gt(wood, 500, "the club itself must survive chroma-keying")


func test_condition_cells_are_distinct_drawings():
	var defense := sprite.condition_texture("wooden_club", "defense").get_image()
	var worn := sprite.condition_texture("wooden_club", "worn").get_image()
	var broken := sprite.condition_texture("wooden_club", "broken").get_image()
	assert_gt(_differing_pixels(defense, worn), 100)
	assert_gt(_differing_pixels(worn, broken), 100)


func test_textures_are_cached_across_instances():
	var first := sprite.generate_textures("wooden_club", "attack")
	var second := IllustratedItemSprite.new().generate_textures("wooden_club", "attack")
	assert_same(first[0], second[0])


func _differing_pixels(a: Image, b: Image) -> int:
	var count := 0
	for y in mini(a.get_height(), b.get_height()):
		for x in mini(a.get_width(), b.get_width()):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				count += 1
	return count
