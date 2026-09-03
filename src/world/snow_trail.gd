extends RefCounted

const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")

## Footprints in snow: walking displaces it, and fresh snow fills the tracks
## back in (see docs/concept/snow_cover.md's "Footprints" section).
##
## ## Why this was rewritten, not tuned
##
## The first version kept one scalar per GAME TILE and called it every
## rendered frame the player stood in snow, not once per real stride.
## `TREAD_PER_STEP` reached `MAX_TREAD` in three frames regardless of whether
## the player was walking or standing still, so a tile went "as trodden as it
## will ever be" within a fraction of a second of first being entered, and
## because a TILE was the unit, one visit packed the WHOLE tile uniformly --
## there was no way to tell a corner crossing from a hundred laps, and
## nothing shaped like a boot could be drawn into one flat scalar in the
## first place. Two separate reports ("footprints look like a smear, not a
## boot" and "walking back and forth doesn't deepen a path") were one root
## cause.
##
## ## The fix: a mark is a place and a facing, not a tile
##
## `step` mirrors `BloodTrail.step`'s own distance-gated shape -- a mark is
## recorded only once real stride length (`STRIDE_PX`) has passed since the
## last one, and it carries the exact world position and facing at that
## moment. Walking one LINE repeatedly now lays down many distinct,
## closely-but-not-identically-placed marks (real strides never land in
## exactly the same spot twice), which is what "deepens" a path: not any one
## mark exceeding MAX_TREAD, but the line itself becoming continuous and
## wide as overlapping strides reinforce it -- exactly how a real desire path
## is worn.
##
## Each mark is an oriented CAPSULE (a rounded rectangle: the set of points
## within `FOOT_RADIUS_PX` of the line segment from heel to toe), not a
## circle -- a footprint, not a puddle -- graded from full tread on its own
## centreline down to zero at its edge, rather than a flat stencil. This
## costs nothing new the shader does not already have: `lying_at`'s
## `tread * tread_depth` subtraction was always "how much snow this exact
## point has displaced"; the only change is that the sampled value is now
## shaped like a boot instead of flat across a whole tile.
##
## ## Real-world grounding, and where it stops
##
## `STRIDE_PX` is a real average adult walking stride (`STRIDE_M`), converted
## through `GroundSlide.PX_PER_METER` -- the same real player-height scale
## `courtship.gd`'s dance radius and `flyer_personality.gd`'s flight
## distances already anchor to, so this is not a second, independently
## invented scale. `FOOT_HALF_LENGTH_PX`/`FOOT_RADIUS_PX` are NOT grounded
## the same way: a real shoe print (~26cm x ~10cm) converts to roughly
## 1.6px x 0.6px at this game's own player scale (a ~22px-tall character),
## which is sub-pixel and would render as nothing at all. `VISIBLE_TREAD`
## already named this exact tension for the scalar case ("one step has to
## show, or the whole feature is a number nobody can read"); the mark size
## constants are the same floor applied to shape -- the smallest size that
## still reads as an oriented mark at `MASK_TEXELS_PER_TILE` resolution,
## pinned by test_a_footprint_mark_is_bigger_than_one_mask_texel rather than
## left as an eyeballed literal.
##
## Pure logic over world positions -- drawing is the renderer's job, reached
## through build_mask_texture's real R8 texture bridge (see
## docs/concept/snow_cover.md).

## How far one game tile is, in world pixels -- named here (not just reached
## through TerrainRenderer) because MASK_TEXELS_PER_TILE and FOOT_* are
## dimensioned against it directly.
const TILE_SIZE_PX := 16.0

## A real average adult walking stride, converted through this project's own
## established real-world scale (see the module header). Two marks closer
## together than this are the same stride still in progress, not a second
## step.
const STRIDE_M := 0.75
const STRIDE_PX := STRIDE_M * GroundSlide.PX_PER_METER

## How much one mark displaces snow at its own centreline, and how deep any
## one mark can get. Unchanged from the per-tile version: the number was
## never wrong, only the UNIT it was applied to (a whole tile) was.
const TREAD_PER_STEP := 0.34
const MAX_TREAD := 1.0

## How much displacement is already visible. One step has to show, or the
## whole feature is a number nobody can read.
const VISIBLE_TREAD := 0.3

## How long a steady snowfall takes to fill a mark back in. See the deleted
## per-tile version's own reasoning (still true): faster than covering bare
## ground, since a footprint is a shallow depression and a snowfall must be
## able to fill one within a single weather spell (pinned by
## test_a_snowfall_fills_its_tracks_before_it_ends).
const SECONDS_TO_FILL := WeatherModel.WEATHER_PERIOD_SECONDS * 0.35

## Below this a mark is forgotten entirely, rather than kept at nearly-zero
## forever.
const FORGET_BELOW := 0.02

## A hard ceiling on how many marks are ever held at once, regardless of
## FORGET_BELOW -- nothing erases a mark without a snowfall
## (test_tracks_do_not_fade_on_their_own), so a long snow-free walk needs a
## bound that is not "wait for it to snow". The oldest mark is evicted first,
## the same "forget the far past, keep the recent" shape FORGET_BELOW already
## has for AGE rather than count.
const MAX_TRACKED_MARKS := 512

## How many mask texels one game tile packs, in the GPU-facing window (see
## build_mask_texture). One texel per tile -- the original resolution -- is
## exactly what made an oriented mark impossible to express at all, whatever
## the CPU math wanted to draw: a single averaged texel cannot be a boot
## shape at any orientation.
const MASK_TEXELS_PER_TILE := 4

## Half the capsule's length along its own facing axis, and its radius
## across it -- see the module header for why these are a visibility floor
## rather than a literal anatomical footprint size.
##
## FOOT_RADIUS_PX is bounded BELOW by the mask's own texel grid, not just
## picked: a shape narrower than roughly half a texel diagonal
## (`TILE_SIZE_PX / MASK_TEXELS_PER_TILE / sqrt(2)`) can fall entirely
## between two texel centres depending on exactly where the mark lands, and
## point-sample rasterization would then miss it completely -- an
## intermittent, alignment-dependent "sometimes a footstep just doesn't
## render" bug rather than a visual choice. Kept comfortably above that
## floor rather than exactly on it, since a step's real world position is
## never guaranteed to avoid the single worst-case corner.
const FOOT_HALF_LENGTH_PX := 5.0
const FOOT_RADIUS_PX := 3.2

## The floor FOOT_RADIUS_PX has to clear (see its own doc comment) --
## exposed so test_a_footprint_radius_clears_the_texel_grid_floor pins the
## RELATIONSHIP rather than the eyeballed 3.2 alone.
static func min_radius_for_texel_grid() -> float:
	return (TILE_SIZE_PX / float(MASK_TEXELS_PER_TILE)) / sqrt(2.0)

## One live mark: where it was placed, which way it faced, and how much it
## has displaced so far. `facing` is stored normalized; a zero vector is
## never passed in (see step's own guard).
class Mark:
	var position: Vector2
	var facing: Vector2
	var tread: float


var _marks: Array[Mark] = []
var _since_last_mark := 0.0
var _last_position := Vector2.ZERO
var _has_last_position := false


## Advances the walk by however far it has moved and, once a real stride's
## worth of ground has passed, places a mark facing `facing` at `position`.
## Returns whether a mark was placed this call -- the same reporting shape
## BloodTrail.step already uses, so a caller can react to a real footstep
## (a sound, a particle) rather than to every frame.
##
## Called every frame regardless of movement, deliberately: the distance
## gate lives HERE rather than in caller-side throttling, which is the
## entire fix for the original defect (see the module header).
func step(position: Vector2, facing: Vector2, _delta: float) -> bool:
	if not _has_last_position:
		# The very first call has nowhere to measure a stride FROM -- but the
		# player did not teleport here, so treating this as a warm-up with no
		# mark would mean the ground you were already standing on when snow
		# started tracking never shows a print until you move a further stride
		# tracking never shows a print until you move a further stride away.
		# One step is already visible (VISIBLE_TREAD); this is that step.
		_last_position = position
		_has_last_position = true
		_place_mark(position, facing)
		return true
	_since_last_mark += _last_position.distance_to(position)
	_last_position = position
	if _since_last_mark < STRIDE_PX:
		return false
	_since_last_mark = 0.0
	_place_mark(position, facing)
	return true


func _place_mark(position: Vector2, facing: Vector2) -> void:
	var mark := Mark.new()
	mark.position = position
	mark.facing = facing if facing.length() > 0.01 else Vector2.DOWN
	mark.tread = minf(TREAD_PER_STEP, MAX_TREAD)
	_marks.append(mark)
	if _marks.size() > MAX_TRACKED_MARKS:
		_marks.pop_front()


## Fills every live mark in while it is snowing. Nothing happens when it is
## not: marks do not fade on their own.
func advance(delta_seconds: float, snowing: bool) -> void:
	if not snowing or delta_seconds <= 0.0:
		return
	var filled := delta_seconds / SECONDS_TO_FILL
	var kept: Array[Mark] = []
	for mark in _marks:
		mark.tread -= filled
		if mark.tread > FORGET_BELOW:
			kept.append(mark)
	_marks = kept


## How much snow has been displaced AT this exact world position, 0
## untouched to 1 trodden bare -- the SUM of every live mark whose oriented
## capsule covers this point, clamped to MAX_TREAD.
##
## A sum, not a max: real repeated treading of one spot -- standing and
## shuffling, or pacing a tight line -- has to actually deepen it toward
## MAX_TREAD, which is the literal original complaint this whole module was
## rewritten over ("walking back and forth doesn't deepen it"). A max would
## cap every spot at whatever ONE step's own mark is worth, however many
## times it was actually stepped on, which is the same defect in a new
## shape. Marks that do NOT overlap a given point contribute nothing there
## regardless -- this is real accumulated overlap, not every mark ever
## placed leaking into everywhere else (see
## test_marks_far_apart_do_not_combine_where_neither_reaches).
func tread_at(position: Vector2) -> float:
	var total := 0.0
	for mark in _marks:
		total += _mark_value_at(mark, position)
	return minf(total, MAX_TREAD)


## The capsule falloff: 1.0 exactly on the heel-to-toe centreline, tapering
## linearly to 0.0 at FOOT_RADIUS_PX away from it, scaled by the mark's own
## tread. Distance-to-segment rather than distance-to-point is what makes
## the mark ORIENTED and elongated along `facing` instead of a circle.
func _mark_value_at(mark: Mark, point: Vector2) -> float:
	var half_axis := mark.facing.normalized() * FOOT_HALF_LENGTH_PX
	var heel := mark.position - half_axis
	var toe := mark.position + half_axis
	var axis := toe - heel
	var axis_length_sq := axis.length_squared()
	var t := 0.0
	if axis_length_sq > 0.0001:
		t = clampf((point - heel).dot(axis) / axis_length_sq, 0.0, 1.0)
	var closest := heel + axis * t
	var distance := point.distance_to(closest)
	if distance >= FOOT_RADIUS_PX:
		return 0.0
	return mark.tread * (1.0 - distance / FOOT_RADIUS_PX)


func tracked_mark_count() -> int:
	return _marks.size()


## A real R8 Texture2D window in world pixels, centred on `centre` -- the
## bridge SnowBombShader.set_trail_mask wants (see docs/concept/
## snow_cover.md's "Footprints" section). `window_tiles` is in TILES;
## MASK_TEXELS_PER_TILE decides how many texels each tile actually packs, so
## a mark far smaller than one tile still has somewhere to be drawn.
##
## Splats each live mark only into the small texel range its own capsule can
## possibly reach, rather than evaluating every mark at every texel -- cost
## scales with tracked marks (bounded by MAX_TRACKED_MARKS), exactly as
## docs/concept/snow_cover.md's "cost is per footstep" claim requires,
## whatever the window size.
func build_mask_texture(centre: Vector2, window_tiles: int) -> ImageTexture:
	var texels := window_tiles * MASK_TEXELS_PER_TILE
	var texel_size := TILE_SIZE_PX / float(MASK_TEXELS_PER_TILE)
	var origin := centre - Vector2(texels, texels) * texel_size * 0.5
	var image := Image.create(texels, texels, false, Image.FORMAT_R8)

	for mark in _marks:
		_splat_mark(image, mark, origin, texel_size, texels)
	return ImageTexture.create_from_image(image)


func _splat_mark(
	image: Image, mark: Mark, origin: Vector2, texel_size: float, texels: int
) -> void:
	var reach := FOOT_HALF_LENGTH_PX + FOOT_RADIUS_PX
	var local := (mark.position - origin) / texel_size
	var texel_reach := ceili(reach / texel_size) + 1
	var min_x := maxi(0, int(local.x) - texel_reach)
	var max_x := mini(texels - 1, int(local.x) + texel_reach)
	var min_y := maxi(0, int(local.y) - texel_reach)
	var max_y := mini(texels - 1, int(local.y) + texel_reach)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var world_point := origin + Vector2(x + 0.5, y + 0.5) * texel_size
			var value := _mark_value_at(mark, world_point)
			if value <= 0.0:
				continue
			# Accumulated, not maxed -- the same rule tread_at uses (see its
			# own doc comment). Splatting marks one at a time onto a shared
			# image, each ADDING to whatever is already there and clamping
			# as it goes, is the same final total a sum-then-clamp-once
			# would give: every partial sum here is still monotonically
			# increasing, so clamping early never throws away a contribution
			# a later mark would have needed room for.
			var existing := image.get_pixel(x, y).r
			var total := minf(existing + value, MAX_TREAD)
			image.set_pixel(x, y, Color(total, total, total, total))
