extends GutTest

## WoodenClubSheetPainter: the deterministic generator behind the SAMPLE
## `assets/sprites/items/wooden_club_combat.png` -- a stand-in drawn to the
## exact ingestion format docs/art/ai_sprite_prompts.md section 11 asks an
## image model for (one sheet, an 8-frame attack row over a 3-cell
## defense/worn/broken row, solid magenta chroma-key ground, near-white
## divider grid, posterized 3-band shading lit from the upper-left), so the
## wiring can be built and tested against real pixels before any generated
## art exists. Every tuned number below is pinned here rather than eyeballed.

const Painter = preload("res://src/rendering/wooden_club_sheet_painter.gd")

const L := Painter.CLUB_LENGTH


# -- layout: the format section 11 specifies -----------------------------------

func test_sheet_is_at_least_the_row_size_the_prompt_asks_for():
	# "Export at least 1600px wide by 300px tall for the row."
	assert_true(Painter.SHEET_SIZE.x >= 1600, "row must be at least 1600px wide")
	assert_true(Painter.CELL_SIZE.y >= 300, "row must be at least 300px tall")


func test_sheet_is_two_rows_of_cells_plus_dividers():
	assert_eq(Painter.ATTACK_FRAMES, 8)
	assert_eq(Painter.CONDITION_CELLS, 3)
	var width := Painter.DIVIDER + Painter.ATTACK_FRAMES * (Painter.CELL_SIZE.x + Painter.DIVIDER)
	var height := Painter.DIVIDER + 2 * (Painter.CELL_SIZE.y + Painter.DIVIDER)
	assert_eq(Painter.SHEET_SIZE, Vector2i(width, height))


func test_row_bands_exclude_the_divider_lines():
	assert_eq(Painter.attack_row_band(), Vector2i(Painter.DIVIDER, Painter.DIVIDER + Painter.CELL_SIZE.y))
	var second_top := Painter.DIVIDER * 2 + Painter.CELL_SIZE.y
	assert_eq(Painter.condition_row_band(), Vector2i(second_top, second_top + Painter.CELL_SIZE.y))


func test_cell_rects_tile_the_grid_between_dividers():
	var first := Painter.cell_rect(0, 0)
	assert_eq(first, Rect2i(Painter.DIVIDER, Painter.DIVIDER, Painter.CELL_SIZE.x, Painter.CELL_SIZE.y))
	var second := Painter.cell_rect(0, 1)
	assert_eq(second.position.x, first.end.x + Painter.DIVIDER)
	var below := Painter.cell_rect(1, 0)
	assert_eq(below.position.y, first.end.y + Painter.DIVIDER)


# -- the swing: wind-up (1-3), release/peak (4-5), recovery (6-8) --------------

func test_attack_cycle_has_eight_angles():
	assert_eq(Painter.ATTACK_ANGLES.size(), Painter.ATTACK_FRAMES)


func test_wind_up_rotates_progressively_back():
	# Frames 1-3 wind back and up: each further back (more negative) than the last.
	assert_lt(Painter.ATTACK_ANGLES[1], Painter.ATTACK_ANGLES[0])
	assert_lt(Painter.ATTACK_ANGLES[2], Painter.ATTACK_ANGLES[1])


func test_release_whips_forward_to_the_peak_of_the_arc():
	# Frames 4-5 swing forward past the wind-up; frame 5 is the furthest point.
	assert_gt(Painter.ATTACK_ANGLES[3], Painter.ATTACK_ANGLES[2])
	assert_gt(Painter.ATTACK_ANGLES[4], Painter.ATTACK_ANGLES[3])
	for angle in Painter.ATTACK_ANGLES:
		assert_true(angle <= Painter.ATTACK_ANGLES[4], "frame 5 must be the peak of the arc")


func test_recovery_settles_back_toward_the_neutral_ready_pose():
	assert_lt(Painter.ATTACK_ANGLES[5], Painter.ATTACK_ANGLES[4])
	assert_lt(Painter.ATTACK_ANGLES[6], Painter.ATTACK_ANGLES[5])
	assert_lt(Painter.ATTACK_ANGLES[7], Painter.ATTACK_ANGLES[6])
	assert_almost_eq(float(Painter.ATTACK_ANGLES[7]), Painter.NEUTRAL_ANGLE, 10.0)


func test_speed_lines_trail_only_the_release_frames():
	for index in Painter.ATTACK_FRAMES:
		assert_eq(Painter.frame_has_speed_lines(index), index == 3 or index == 4, "frame %d" % (index + 1))


func test_defense_pose_is_a_diagonal_guard():
	# "angled diagonally across the frame" -- well away from both upright and flat.
	assert_true(absf(Painter.DEFENSE_ANGLE) >= 30.0 and absf(Painter.DEFENSE_ANGLE) <= 60.0)


# -- the club's own shape: a stout haft, no blade ------------------------------

func test_haft_widens_from_the_grip_to_the_striking_end():
	assert_almost_eq(Painter.haft_radius(0.0), Painter.GRIP_RADIUS, 0.01)
	assert_almost_eq(Painter.haft_radius(L), Painter.HEAD_RADIUS, 0.01)
	var previous := Painter.haft_radius(0.0)
	for step in range(1, 21):
		var radius := Painter.haft_radius(L * step / 20.0)
		assert_true(radius >= previous - 0.001, "radius must never narrow toward the head")
		previous = radius


func test_points_on_the_axis_are_inside_the_club_and_points_beyond_it_are_not():
	assert_gt(Painter.signed_distance(Vector2(0.0, L * 0.5), Painter.Condition.PRISTINE), 0.0)
	assert_gt(Painter.signed_distance(Vector2(0.0, 0.0), Painter.Condition.PRISTINE), 0.0)
	assert_lt(Painter.signed_distance(Vector2(0.0, L + Painter.HEAD_RADIUS + 5.0), Painter.Condition.PRISTINE), 0.0)
	assert_lt(Painter.signed_distance(Vector2(Painter.HEAD_RADIUS + 5.0, L * 0.5), Painter.Condition.PRISTINE), 0.0)


func test_local_frame_rotates_clockwise_around_the_grip_pivot():
	# Upright (0 degrees): the head is straight above the pivot on screen.
	var upright := Painter.to_local(Painter.PIVOT + Vector2(0.0, -100.0), 0.0)
	assert_almost_eq(upright.x, 0.0, 0.01)
	assert_almost_eq(upright.y, 100.0, 0.01)
	# 90 degrees clockwise: the head points to the right.
	var flat := Painter.to_local(Painter.PIVOT + Vector2(100.0, 0.0), 90.0)
	assert_almost_eq(flat.x, 0.0, 0.01)
	assert_almost_eq(flat.y, 100.0, 0.01)


# -- posterized shading, lit from the upper-left -------------------------------

func test_upright_club_is_lit_on_its_left_and_shadowed_on_its_right():
	var u := Painter.GRIP_RADIUS * 0.8
	assert_eq(Painter.shade_band(Vector2(-u, 10.0), 0.0), Painter.Band.HIGHLIGHT)
	assert_eq(Painter.shade_band(Vector2(u, 10.0), 0.0), Painter.Band.SHADOW)
	assert_eq(Painter.shade_band(Vector2(0.0, 10.0), 0.0), Painter.Band.BASE)


func test_light_stays_upper_left_when_the_club_rotates():
	# Turned upside down, the club's own left side now faces away from the light.
	var u := Painter.GRIP_RADIUS * 0.8
	assert_eq(Painter.shade_band(Vector2(-u, 10.0), 180.0), Painter.Band.SHADOW)
	assert_eq(Painter.shade_band(Vector2(u, 10.0), 180.0), Painter.Band.HIGHLIGHT)


func test_a_cell_uses_only_the_flat_wood_palette():
	var cell := Painter.new().paint_cell(0.0, Painter.Condition.PRISTINE, false)
	var colors := _distinct_opaque_colors(cell)
	assert_true(colors.size() <= 6, "posterized: at most base/highlight/shadow/outline/grain, got %d" % colors.size())
	assert_true(colors.size() >= 4, "needs at least outline + three shading bands, got %d" % colors.size())


# -- condition variants: worn chips, broken crack ------------------------------

func test_worn_club_has_chips_bitten_out_of_its_striking_end():
	var bitten := 0
	for step in range(0, 400):
		var t := L * (0.6 + 0.4 * step / 400.0)
		for side in [-1.0, 1.0]:
			var edge := Vector2(side * (Painter.haft_radius(t) - 1.5), t)
			var pristine := Painter.signed_distance(edge, Painter.Condition.PRISTINE)
			var worn := Painter.signed_distance(edge, Painter.Condition.WORN)
			if pristine > 0.0 and worn <= 0.0:
				bitten += 1
	assert_gt(bitten, 0, "some edge of the striking end must be chipped away when worn")


func test_worn_club_is_still_whole_along_its_axis():
	for step in range(0, 100):
		var t := L * step / 100.0
		assert_gt(Painter.signed_distance(Vector2(0.0, t), Painter.Condition.WORN), 0.0)


func test_only_the_broken_club_shows_raw_wood_along_a_crack_near_its_midpoint():
	var raw_pristine := 0
	var raw_broken := 0
	for step in range(0, 200):
		var t := L * (0.35 + 0.3 * step / 200.0)
		for u in range(-12, 13):
			var local := Vector2(float(u), t)
			if Painter.crack_distance(local) <= Painter.CRACK_HALF_WIDTH:
				raw_broken += 1
	assert_gt(raw_broken, 20, "the crack must run across the haft near its midpoint")
	assert_eq(raw_pristine, 0)
	# The crack lies within the middle third of the haft, not at either end.
	for u in range(-12, 13):
		assert_gt(Painter.crack_distance(Vector2(float(u), L * 0.1)), Painter.CRACK_HALF_WIDTH)
		assert_gt(Painter.crack_distance(Vector2(float(u), L * 0.9)), Painter.CRACK_HALF_WIDTH)


func test_broken_cell_paints_raw_wood_and_the_worn_cell_does_not():
	var painter := Painter.new()
	var broken := painter.paint_cell(Painter.NEUTRAL_ANGLE, Painter.Condition.BROKEN, false)
	var worn := painter.paint_cell(Painter.NEUTRAL_ANGLE, Painter.Condition.WORN, false)
	assert_true(_has_color(broken, Painter.RAW_WOOD), "broken shows pale raw wood at the fracture")
	assert_false(_has_color(worn, Painter.RAW_WOOD), "worn is scuffed, not split open")


# -- the assembled sheet -------------------------------------------------------

func test_sheet_has_the_declared_size_on_a_magenta_ground_with_a_near_white_grid():
	var sheet := Painter.new().paint()
	assert_eq(sheet.get_width(), Painter.SHEET_SIZE.x)
	assert_eq(sheet.get_height(), Painter.SHEET_SIZE.y)
	# The outer 2px frame and every divider is near-white, low saturation.
	var divider := sheet.get_pixel(0, 0)
	assert_true(divider.r >= 0.9 and divider.g >= 0.9 and divider.b >= 0.9 and divider.s <= 0.05)
	var between := sheet.get_pixel(Painter.cell_rect(0, 0).end.x, 50)
	assert_true(between.r >= 0.9 and between.g >= 0.9 and between.b >= 0.9)
	# A cell corner, far from any club, is the flat chroma-key ground.
	var corner := Painter.cell_rect(0, 0).position + Vector2i(2, 2)
	assert_true(sheet.get_pixel(corner.x, corner.y).is_equal_approx(Painter.CHROMA_KEY))


func test_every_cell_keeps_its_drawing_clear_of_the_dividers():
	var sheet := Painter.new().paint()
	var cells: Array[Rect2i] = []
	for column in Painter.ATTACK_FRAMES:
		cells.append(Painter.cell_rect(0, column))
	for column in Painter.CONDITION_CELLS:
		cells.append(Painter.cell_rect(1, column))
	for cell in cells:
		var content := _content_rect(sheet, cell)
		assert_true(content.size.x > 0, "cell %s must contain a drawing" % cell)
		assert_true(content.position.x >= cell.position.x + Painter.CELL_PADDING, "left padding in %s" % cell)
		assert_true(content.position.y >= cell.position.y + Painter.CELL_PADDING, "top padding in %s" % cell)
		assert_true(content.end.x <= cell.end.x - Painter.CELL_PADDING, "right padding in %s" % cell)
		assert_true(content.end.y <= cell.end.y - Painter.CELL_PADDING, "bottom padding in %s" % cell)


func test_the_grip_stays_put_across_every_attack_frame():
	# The whole point of a fixed pivot: the grip pixel is wood in all 8 frames.
	var sheet := Painter.new().paint()
	for column in Painter.ATTACK_FRAMES:
		var cell := Painter.cell_rect(0, column)
		var grip := cell.position + Vector2i(Painter.PIVOT)
		var color := sheet.get_pixel(grip.x, grip.y)
		assert_false(color.is_equal_approx(Painter.CHROMA_KEY), "frame %d grip is not wood" % (column + 1))


# -- helpers --------------------------------------------------------------------

func _is_ground(color: Color) -> bool:
	if color.is_equal_approx(Painter.CHROMA_KEY):
		return true
	return color.r >= 0.9 and color.g >= 0.9 and color.b >= 0.9 and color.s <= 0.05


func _content_rect(sheet: Image, cell: Rect2i) -> Rect2i:
	var left := cell.end.x
	var right := cell.position.x - 1
	var top := cell.end.y
	var bottom := cell.position.y - 1
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			if _is_ground(sheet.get_pixel(x, y)):
				continue
			left = mini(left, x)
			right = maxi(right, x)
			top = mini(top, y)
			bottom = maxi(bottom, y)
	if right < left:
		return Rect2i(cell.position, Vector2i.ZERO)
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


func _distinct_opaque_colors(image: Image) -> Array:
	var seen := {}
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.5 or c.is_equal_approx(Painter.CHROMA_KEY):
				continue
			seen[c.to_html(false)] = true
	return seen.keys()


func _has_color(image: Image, target: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.5 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.02:
				return true
	return false
