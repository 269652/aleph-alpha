extends RefCounted

## Paints the SAMPLE `assets/sprites/items/wooden_club_combat.png`.
##
## docs/art/ai_sprite_prompts.md section 11 asks an image model for a
## two-row composite sheet of the wooden club ALONE (no hand, no arm): an
## 8-frame attack swing on row 1, then defense / worn / broken on row 2, on
## a solid magenta chroma-key ground with a near-white divider grid,
## posterized 3-band shading lit from the upper-left. No such art existed,
## and docs/concept/item_illustrations.md's wiring for it could not be built
## without real pixels to test against. This paints a deterministic stand-in
## in EXACTLY that format -- same grid, same ground, same divider lines, same
## fixed grip pivot across the swing -- so IllustratedItemSprite can be built
## and proven now, and swapping in generated art later is a file replacement
## plus a re-measure of the row bands, never a code change.
##
## Everything is a pure function of pixel position: to_local() maps a cell
## pixel into the club's own (across, along) frame for a given swing angle,
## signed_distance() says whether that point is wood, shade_band() picks one
## of three flat tones from the club's orientation against the fixed light,
## and pixel_color() assembles the answer. Every tuned number is a named
## constant pinned by test_wooden_club_sheet_painter.gd, not an eyeballed
## literal inside a loop.
##
## Usage from the generator: `WoodenClubSheetPainter.new().paint()` -- see
## tools/generate_wooden_club_sheet.gd.

enum Condition { PRISTINE, WORN, BROKEN }
enum Band { SHADOW, BASE, HIGHLIGHT }

## Grid: 8 attack cells across row 1, 3 condition cells across row 2 (the
## rest of row 2 stays bare ground), every cell boxed by a DIVIDER-wide
## near-white rule, including the outer edge (the same white frame
## wolf.png carries). Cell size clears the prompt's "at least 1600 x 300 per
## row" floor and leaves room for the club to swing fully sideways.
const CELL_SIZE := Vector2i(360, 300)
const DIVIDER := 2
const ATTACK_FRAMES := 8
const CONDITION_CELLS := 3
const SHEET_SIZE := Vector2i(
	DIVIDER + ATTACK_FRAMES * (CELL_SIZE.x + DIVIDER), DIVIDER + 2 * (CELL_SIZE.y + DIVIDER)
)
## The drawing (speed lines included) never comes closer than this to a
## divider -- a drawn pixel in a divider column would merge two cells.
const CELL_PADDING := 6

const CHROMA_KEY := Color(1.0, 0.0, 1.0)
const DIVIDER_COLOR := Color(0.97, 0.97, 0.97)

## The club in its own frame: `t` runs along the haft from the grip pivot
## (t = 0) to the striking end (t = CLUB_LENGTH); the butt extends a little
## past the pivot. `u` runs across it. Radius tapers from the grip to the
## head -- "a plain stout wooden haft with no blade".
const PIVOT := Vector2(180.0, 205.0)
const CLUB_LENGTH := 150.0
const BUTT_OVERHANG := 14.0
const GRIP_RADIUS := 9.0
const HEAD_RADIUS := 19.0
## Where along the haft the taper happens (fractions of CLUB_LENGTH).
const TAPER_START := 0.25
const TAPER_END := 0.85
const OUTLINE_WIDTH := 2.0

## Swing angles, degrees clockwise from straight up, one per attack frame:
## wind-up back and up (1-3), release through the peak (4-5), recovery
## settling toward the neutral ready pose (6-8).
const ATTACK_ANGLES := [-20.0, -60.0, -100.0, 30.0, 95.0, 65.0, 30.0, -5.0]
const NEUTRAL_ANGLE := -5.0
const DEFENSE_ANGLE := -45.0
## Frames (0-based) that trail speed lines: the release/peak pair.
const SPEED_LINE_FRAMES := [3, 4]
const SPEED_LINE_RADII := [0.55, 0.75, 0.95]
## Angular span behind the club (degrees) that each speed line arc covers.
const SPEED_LINE_TRAIL_FROM := 38.0
const SPEED_LINE_TRAIL_TO := 14.0

## Light from the upper-left; a surface is highlighted or shadowed once its
## across-the-haft normal tilts past this much toward or away from it.
const LIGHT_DIRECTION := Vector2(-0.70710678, -0.70710678)
const BAND_THRESHOLD := 0.3

## Wood palette: three flat bands plus outline and a grain streak tone.
const OUTLINE := Color(0.24, 0.14, 0.07)
const SHADOW := Color(0.42, 0.26, 0.13)
const BASE := Color(0.60, 0.40, 0.21)
const HIGHLIGHT := Color(0.78, 0.58, 0.35)
const GRAIN := Color(0.52, 0.34, 0.17)
const RAW_WOOD := Color(0.90, 0.80, 0.60)
const SPEED_LINE := Color(0.85, 0.72, 0.52)

## Grain streaks run along the haft; a worn club's grain is roughened (denser).
const GRAIN_PERIOD_PRISTINE := 7
const GRAIN_PERIOD_WORN := 4

## Worn: chips bitten from the striking end's edge, and small dents in the
## surface. Each entry is (side, t fraction, radius); the chip center sits
## just outside the edge so the bite is shallow.
const WORN_CHIPS := [[1.0, 0.88, 5.0], [-1.0, 0.95, 4.0], [1.0, 0.72, 4.0]]
const WORN_DENTS := [[3.0, 0.80, 3.5], [-5.0, 0.62, 3.0]]

## Broken: a zig-zag crack across the haft near its midpoint (local (u, t)
## points), with splinter ticks off it, drawn in pale raw wood; the upper
## half hangs kinked off the lower one.
const CRACK_T := 0.5
const CRACK_HALF_WIDTH := 2.0
const CRACK_PATH := [
	Vector2(-26.0, 0.47), Vector2(-6.0, 0.52), Vector2(2.0, 0.48), Vector2(10.0, 0.54), Vector2(26.0, 0.50)
]
const CRACK_SPLINTERS := [
	[Vector2(-4.0, 0.52), Vector2(-1.0, 0.60)], [Vector2(2.0, 0.48), Vector2(5.0, 0.41)]
]
const KINK_DEGREES := 8.0


# -- layout --------------------------------------------------------------------

static func attack_row_band() -> Vector2i:
	return Vector2i(DIVIDER, DIVIDER + CELL_SIZE.y)


static func condition_row_band() -> Vector2i:
	var top := DIVIDER * 2 + CELL_SIZE.y
	return Vector2i(top, top + CELL_SIZE.y)


static func cell_rect(row: int, column: int) -> Rect2i:
	return Rect2i(
		DIVIDER + column * (CELL_SIZE.x + DIVIDER),
		DIVIDER + row * (CELL_SIZE.y + DIVIDER),
		CELL_SIZE.x,
		CELL_SIZE.y
	)


static func frame_has_speed_lines(index: int) -> bool:
	return SPEED_LINE_FRAMES.has(index)


# -- geometry ------------------------------------------------------------------

## Direction the haft points at `angle_deg` (clockwise from straight up, in
## screen space where +y is down).
static func axis_direction(angle_deg: float) -> Vector2:
	var radians := deg_to_rad(angle_deg)
	return Vector2(sin(radians), -cos(radians))


## A cell pixel in the club's own frame: x across the haft, y along it from
## the grip pivot toward the head.
static func to_local(cell_px: Vector2, angle_deg: float) -> Vector2:
	var offset := cell_px - PIVOT
	var along := axis_direction(angle_deg)
	var across := Vector2(-along.y, along.x)
	return Vector2(offset.dot(across), offset.dot(along))


static func haft_radius(t: float) -> float:
	var fraction: float = clampf(t / CLUB_LENGTH, 0.0, 1.0)
	return lerpf(GRIP_RADIUS, HEAD_RADIUS, smoothstep(TAPER_START, TAPER_END, fraction))


## Distance inside the wood (positive) or outside it (negative) for the given
## condition -- worn takes chips out of the edge, broken kinks the upper half.
static func signed_distance(local: Vector2, condition: int) -> float:
	var point := local
	if condition == Condition.BROKEN:
		point = _kinked(local)
	var distance := _pristine_distance(point)
	if condition == Condition.WORN:
		for chip in WORN_CHIPS:
			var t: float = CLUB_LENGTH * chip[1]
			var center := Vector2(chip[0] * (haft_radius(t) + 1.0), t)
			distance = minf(distance, point.distance_to(center) - chip[2])
	return distance


static func _pristine_distance(local: Vector2) -> float:
	var t := local.y
	if t < -BUTT_OVERHANG:
		return GRIP_RADIUS - local.distance_to(Vector2(0.0, -BUTT_OVERHANG))
	if t > CLUB_LENGTH:
		return HEAD_RADIUS - local.distance_to(Vector2(0.0, CLUB_LENGTH))
	return haft_radius(t) - absf(local.x)


## The upper half of a broken club hangs off the crack at a slight angle.
static func _kinked(local: Vector2) -> Vector2:
	var hinge := CLUB_LENGTH * CRACK_T
	if local.y <= hinge:
		return local
	var relative := Vector2(local.x, local.y - hinge).rotated(deg_to_rad(-KINK_DEGREES))
	return Vector2(relative.x, relative.y + hinge)


static func shade_band(local: Vector2, angle_deg: float) -> int:
	var along := axis_direction(angle_deg)
	var across := Vector2(-along.y, along.x)
	var radius := maxf(haft_radius(local.y), 0.001)
	var facing: float = clampf(local.x / radius, -1.0, 1.0) * across.dot(LIGHT_DIRECTION)
	if facing > BAND_THRESHOLD:
		return Band.HIGHLIGHT
	if facing < -BAND_THRESHOLD:
		return Band.SHADOW
	return Band.BASE


static func is_grain(local: Vector2, condition: int) -> bool:
	var period := GRAIN_PERIOD_WORN if condition == Condition.WORN else GRAIN_PERIOD_PRISTINE
	var streak := int(floor(local.x * 0.5 + local.y * 0.08 + 100.0))
	return posmod(streak, period) == 0


static func is_dent(local: Vector2) -> bool:
	for dent in WORN_DENTS:
		if local.distance_to(Vector2(dent[0], CLUB_LENGTH * dent[1])) <= dent[2]:
			return true
	return false


## Distance from a local point to the nearest crack or splinter segment.
static func crack_distance(local: Vector2) -> float:
	var nearest := INF
	for index in CRACK_PATH.size() - 1:
		nearest = minf(nearest, _segment_distance(local, _crack_point(CRACK_PATH[index]), _crack_point(CRACK_PATH[index + 1])))
	for splinter in CRACK_SPLINTERS:
		nearest = minf(nearest, _segment_distance(local, _crack_point(splinter[0]), _crack_point(splinter[1])))
	return nearest


static func _crack_point(entry: Vector2) -> Vector2:
	return Vector2(entry.x, CLUB_LENGTH * entry.y)


static func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared <= 0.0:
		return point.distance_to(a)
	var projection: float = clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * projection)


## Speed lines trail the club through the release frames: short arcs about
## the pivot, behind the direction of the swing (which is clockwise).
static func is_speed_line(cell_px: Vector2, angle_deg: float) -> bool:
	var offset := cell_px - PIVOT
	var distance := offset.length()
	var pixel_angle := rad_to_deg(atan2(offset.x, -offset.y))
	var behind := angle_deg - pixel_angle
	if behind < SPEED_LINE_TRAIL_TO or behind > SPEED_LINE_TRAIL_FROM:
		return false
	for fraction in SPEED_LINE_RADII:
		if absf(distance - CLUB_LENGTH * fraction) <= 1.0:
			return true
	return false


# -- painting ------------------------------------------------------------------

## The color a cell pixel takes, or transparent where nothing is drawn.
static func pixel_color(cell_px: Vector2, angle_deg: float, condition: int, speed_lines: bool) -> Color:
	var local := to_local(cell_px, angle_deg)
	var distance := signed_distance(local, condition)
	if distance <= 0.0:
		if speed_lines and is_speed_line(cell_px, angle_deg):
			return SPEED_LINE
		return Color(0, 0, 0, 0)
	if distance <= OUTLINE_WIDTH:
		return OUTLINE
	if condition == Condition.BROKEN and crack_distance(local) <= CRACK_HALF_WIDTH:
		return RAW_WOOD
	if condition == Condition.WORN and is_dent(local):
		return SHADOW
	match shade_band(local, angle_deg):
		Band.HIGHLIGHT:
			return HIGHLIGHT
		Band.SHADOW:
			return SHADOW
	return GRAIN if is_grain(local, condition) else BASE


## One cell on its own: the club at `angle_deg` in `condition`, on the
## chroma-key ground, the pivot at PIVOT.
func paint_cell(angle_deg: float, condition: int, speed_lines: bool) -> Image:
	var cell := Image.create(CELL_SIZE.x, CELL_SIZE.y, false, Image.FORMAT_RGBA8)
	cell.fill(CHROMA_KEY)
	_paint_club(cell, Vector2i.ZERO, angle_deg, condition, speed_lines)
	return cell


## The whole two-row sheet.
func paint() -> Image:
	var sheet := Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	sheet.fill(CHROMA_KEY)
	_paint_dividers(sheet)
	for column in ATTACK_FRAMES:
		_paint_club(
			sheet, cell_rect(0, column).position, ATTACK_ANGLES[column],
			Condition.PRISTINE, frame_has_speed_lines(column)
		)
	_paint_club(sheet, cell_rect(1, 0).position, DEFENSE_ANGLE, Condition.PRISTINE, false)
	_paint_club(sheet, cell_rect(1, 1).position, NEUTRAL_ANGLE, Condition.WORN, false)
	_paint_club(sheet, cell_rect(1, 2).position, NEUTRAL_ANGLE, Condition.BROKEN, false)
	return sheet


func _paint_dividers(sheet: Image) -> void:
	for row in 3:
		var y := row * (CELL_SIZE.y + DIVIDER)
		sheet.fill_rect(Rect2i(0, y, SHEET_SIZE.x, DIVIDER), DIVIDER_COLOR)
	for column in ATTACK_FRAMES + 1:
		var x := column * (CELL_SIZE.x + DIVIDER)
		sheet.fill_rect(Rect2i(x, 0, DIVIDER, SHEET_SIZE.y), DIVIDER_COLOR)


func _paint_club(target: Image, origin: Vector2i, angle_deg: float, condition: int, speed_lines: bool) -> void:
	# Nothing is drawn further from the pivot than the club's own reach (or
	# the outermost speed line), so most of a cell is skipped outright.
	var reach := CLUB_LENGTH + HEAD_RADIUS + OUTLINE_WIDTH + 2.0
	var reach_squared := reach * reach
	for y in CELL_SIZE.y:
		for x in CELL_SIZE.x:
			var cell_px := Vector2(x + 0.5, y + 0.5)
			if (cell_px - PIVOT).length_squared() > reach_squared:
				continue
			var color := pixel_color(cell_px, angle_deg, condition, speed_lines)
			if color.a > 0.0:
				target.set_pixel(origin.x + x, origin.y + y, color)
