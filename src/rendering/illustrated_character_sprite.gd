extends RefCounted

## Real hand/AI-illustrated sprite-sheet art for the player/NPC character rig
## (see CharacterView), replacing ProceduralCharacterSprite's generated
## primitive-shape textures for whichever PARTS actually have registered
## art -- same "sheet -> SpriteSheetSlicer -> cached frames, has_X()/
## generate_textures() checked first, procedural fallback otherwise" shape
## as IllustratedAnimalSprite (see that file's own doc comment for the
## fuller rationale; this reuses its exact chroma-key convention).
##
## body/legs/arms are registered (see `_PARTS`) and drawn NEUTRAL -- a light
## grey/white base with no baked-in class color or skin tone -- so
## CharacterView tints a part via plain `modulate`, the same way it already
## tints the procedural textures (tunic color, leg color, skin color). One
## set of illustrated parts then serves every class palette and skin tone,
## instead of needing a separate hand-illustrated variant per (class, skin
## tone) combination.
##
## legs.png draws BOTH legs together as one fused pair rather than a single
## leg meant to be mirrored -- CharacterView wears it as one part covering
## both LegLeft/LegRight world slots, not two independently-swinging sprites
## (see CharacterView's own doc comment on legs fusion). arms.png holds two
## poses side by side, divided by an OPAQUE line rather than a transparent
## gap -- detect_frames' column-emptiness scan can't find that divider, so
## its `_PARTS` entry gives exact pixel rects instead (`idle_rects`) rather
## than relying on auto-detection.
##
## HEAD is NOT covered by has_part/generate_textures at all, and needs its
## own has_head()/generate_head_texture() surface below -- a head mixes skin
## tone, hair color and eye color in one drawing, which a single flat
## modulate can't separate out. What IS registered (head.png, a 10x10 grid of
## 100 fully-painted faces) still needs real per-pixel recoloring -- see
## generate_head_texture's own doc comment. Hair is a further, still-open gap
## on top of that: head.png's faces are all bald, and no hair overlay art
## exists yet, so an illustrated hero currently reads bald regardless of the
## DNA-picked hair_style/hair color (an honest gap, not a mismatched overlay
## of the old procedural hairstyles onto a head shape they were never drawn
## to fit -- see docs/concept/character_art_brief.md).

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

## Every registered part's frames, from a neutral idle pose to a normalized
## canvas with its ground-contact row on the same baseline -- mirrors
## IllustratedAnimalSprite's CANVAS_SIZE/BASELINE_Y convention (one shared
## size/anchor for every part, so nothing jumps around if art is swapped).
## Sized generously for a single character part rather than a whole animal.
const CANVAS_SIZE := Vector2i(64, 96)
const BASELINE_Y := 90

## part_name -> sheet metadata: "path", plus either "<action>_bands"
## (Array[Vector2i], sliced by SpriteSheetSlicer.detect_frames -- for a sheet
## whose frames are separated by a real transparent/background gap) or
## "<action>_rects" (Array[Rect2i], used AS the frame rects verbatim -- for a
## sheet where auto-detection can't find the boundary, e.g. arms.png's
## opaque divider line). Optional "alpha_threshold"/"divider_gray_min"/
## "chroma_key"/"chroma_key_tolerance" -- identical shape to
## IllustratedAnimalSprite's _SHEETS.
##
## Empty: body/legs/arms used to source single-pose neutral art from here
## (torso.png/leg.png/arms.png) directly, but now come from
## hero_composite.png instead -- see "hero_composite.png" below, which needs
## a variant+facing axis this simple part->rects shape has no room for, the
## same reason head has its own surface rather than living here. Kept as a
## real, working, tested mechanism (idle_rects included) for any FUTURE part
## that only ever needs one neutral pose -- torso.png/leg.png/arms.png
## themselves are untouched on disk, just no longer referenced.
const _PARTS := {}

var _slicer := SpriteSheetSlicer.new()

## Shared across every CharacterView instance, same reasoning as
## IllustratedAnimalSprite's _frame_cache: there's no per-character
## variation to lose by sharing (recoloring happens via modulate at the
## Sprite2D level, not by baking a different tint per instance), and
## reslicing per view would be pure waste.
static var _frame_cache: Dictionary = {}


func has_part(part_name: String) -> bool:
	return _PARTS.has(part_name)


func has_action(part_name: String, action: String) -> bool:
	if not _PARTS.has(part_name):
		return false
	var part: Dictionary = _PARTS[part_name]
	return part.has(action + "_bands") or part.has(action + "_rects")


## The registered frames for `part_name`/`action`, sliced+normalized once
## and cached thereafter. Empty Array for anything has_action would reject
## -- callers must check has_action first, the same "ask before you leap"
## shape as IllustratedAnimalSprite.generate_textures.
func generate_textures(part_name: String, action: String) -> Array[ImageTexture]:
	if not has_action(part_name, action):
		return []
	var key := "%s/%s" % [part_name, action]
	if not _frame_cache.has(key):
		var textures: Array[ImageTexture] = []
		for frame in _load_frames(part_name, action):
			textures.append(ImageTexture.create_from_image(frame))
		_frame_cache[key] = textures
	return _frame_cache[key]


## How much to scale THIS part's Sprite2D so it reads at `target_world_height`
## world units tall -- the character-rig counterpart to
## IllustratedAnimalSprite.marker_scale, same reasoning: CANVAS_SIZE is one
## shared WORKING resolution every part is normalized onto, not a claim that
## a torso and a leg pair are the same real size. A flat, single
## ArtResolution.SPRITE_SCALE (the OLD procedural convention, where every
## part was generated at EXACTLY its own art_size with no padding) silently
## breaks the instant a part's actual drawn content is smaller than
## CANVAS_SIZE -- which normalize_frames' own aspect-preserving fit means
## every part's content usually is. Scale is measured by HEIGHT: every
## registered part reads taller than wide (a torso, a leg pair side by side,
## a single arm), so height is the stable axis to anchor against.
##
## `frame_index` matters because arms.png's two poses can measure to
## slightly different content heights (independent AI-illustrated crops, not
## a mirrored copy) -- ArmLeft and ArmRight must each use THEIR OWN frame's
## measurement, not frame 0's for both, or one arm would read a hair
## different size than the other.
static var _content_height_cache: Dictionary = {}


func part_scale_for(part_name: String, target_world_height: float, frame_index: int = 0, action: String = "idle") -> float:
	var frames := generate_textures(part_name, action)
	if frames.is_empty():
		return 1.0
	var index := clampi(frame_index, 0, frames.size() - 1)
	var key := "%s/%s/%d" % [part_name, action, index]
	if not _content_height_cache.has(key):
		_content_height_cache[key] = _measured_content_height(frames[index].get_image())
	var content_height: float = _content_height_cache[key]
	return target_world_height / content_height if content_height > 0.0 else 1.0


## The trimmed (padding-cropped) content image for a registered part's
## frame, or null for an unregistered part -- what generate_textures'
## underlying frame actually draws, without the shared CANVAS_SIZE's own
## padding. For a caller compositing raw Images at an exact pixel box rather
## than scaling a Sprite2D node onto a world size (see
## ProceduralCharacterSprite.generate_hero_portrait_image's illustrated
## branch) -- CharacterView never needs this, it uses the full padded canvas
## plus part_scale_for instead.
func trimmed_part_image(part_name: String, frame_index: int = 0, action: String = "idle") -> Image:
	var frames := generate_textures(part_name, action)
	if frames.is_empty():
		return null
	var index := clampi(frame_index, 0, frames.size() - 1)
	return _trimmed(frames[index].get_image())


## Same idea as trimmed_part_image, for the head's own recolored texture.
## Null if no head art is registered.
func trimmed_head_image(cell_index: int, skin_tone: Color) -> Image:
	var texture := generate_head_texture(cell_index, skin_tone)
	if texture == null:
		return null
	return _trimmed(texture.get_image())


## The tight opaque-pixel bounding box crop of `image` -- trims whatever
## padding normalize_frames' aspect-preserving fit left around the actual
## drawing. Returns `image` itself (untrimmed) if it is fully transparent,
## since there is no content box to crop to.
func _trimmed(image: Image) -> Image:
	var min_x := image.get_width()
	var max_x := -1
	var min_y := image.get_height()
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return image
	return image.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))


## The opaque-pixel bounding box height of `image` -- the Y-axis counterpart
## to IllustratedAnimalSprite._reference_width's opaque-pixel X scan.
func _measured_content_height(image: Image) -> float:
	var min_y := image.get_height()
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
				break
	if max_y < 0:
		return float(image.get_height())
	return float(max_y - min_y + 1)


func _load_frames(part_name: String, action: String) -> Array[Image]:
	var part: Dictionary = _PARTS[part_name]
	var image := Image.load_from_file(part.get("%s_path" % action, part["path"]))
	if part.has("chroma_key"):
		image = _apply_chroma_key(image, part["chroma_key"], part.get("chroma_key_tolerance", 0.1))
	var alpha_threshold: float = part.get("alpha_threshold", SpriteSheetSlicer.DEFAULT_ALPHA_THRESHOLD)
	var divider_gray_min: float = part.get("divider_gray_min", SpriteSheetSlicer.DEFAULT_DIVIDER_GRAY_MIN)
	var rects_key := "%s_rects" % action
	if part.has(rects_key):
		# Exact rects, no auto-detection: for a sheet whose frame boundary
		# detect_frames can't find (see the `_PARTS` doc comment on arms.png's
		# opaque divider), or that is simply one whole-canvas pose to begin
		# with (body/legs). normalize_frames still trims each rect down to
		# its own real content before resizing/baselining -- only the
		# BOUNDARY between frames is given verbatim, not the content itself.
		var frames: Array[Rect2i] = []
		for rect in part[rects_key]:
			frames.append(rect)
		return _slicer.normalize_frames(image, frames, CANVAS_SIZE, BASELINE_Y, alpha_threshold, divider_gray_min)
	var normalized: Array[Image] = []
	for band in part["%s_bands" % action]:
		var rect: Vector2i = band
		var frames := _slicer.detect_frames(image, rect.x, rect.y, 20, 1, alpha_threshold, divider_gray_min)
		normalized.append_array(
			_slicer.normalize_frames(image, frames, CANVAS_SIZE, BASELINE_Y, alpha_threshold, divider_gray_min)
		)
	return normalized


## Same per-channel chroma-key as IllustratedAnimalSprite._apply_chroma_key
## (see that function's own doc comment) -- duplicated rather than shared
## because the two classes have no other coupling and this is a handful of
## lines, not because the logic is meant to diverge.
func _apply_chroma_key(image: Image, key: Color, tolerance: float) -> Image:
	var keyed := image.duplicate()
	if keyed.get_format() != Image.FORMAT_RGBA8:
		keyed.convert(Image.FORMAT_RGBA8)
	for y in keyed.get_height():
		for x in keyed.get_width():
			var c: Color = keyed.get_pixel(x, y)
			if (
				absf(c.r - key.r) <= tolerance
				and absf(c.g - key.g) <= tolerance
				and absf(c.b - key.b) <= tolerance
			):
				keyed.set_pixel(x, y, Color(0, 0, 0, 0))
	return keyed


## Removes a solid-but-anti-aliased background via a border-connected flood
## fill (a "magic wand" from the edges) instead of a flat per-pixel
## chroma-key. Starting from the four canvas edges (guaranteed background)
## and stepping only to a 4-connected neighbour whose color is within
## `step_tolerance` of the pixel that reached it, the flood rides a gradual
## blur all the way to wherever the real content begins, and can never cross
## INTO that content's interior no matter how dark a pixel there is --
## reaching it would require one big step across the content's own edge,
## which the per-step tolerance refuses. A flat distance-from-a-fixed-color
## key cannot make that distinction: it treats a coincidentally dark pixel in
## the MIDDLE of the content exactly like real background, because it never
## looks at what a pixel is connected to (see HEAD_BACKGROUND_FLOOD_STEP_TOLERANCE's
## own doc comment for the measurement that found this the hard way).
func _remove_background_by_flood(image: Image, step_tolerance: float) -> Image:
	var result := image.duplicate()
	if result.get_format() != Image.FORMAT_RGBA8:
		result.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var visited := {}
	var queue: Array[Vector2i] = []
	for x in width:
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, height - 1))
	for y in height:
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(width - 1, y))
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		if visited.has(at):
			continue
		visited[at] = true
		var here := image.get_pixel(at.x, at.y)
		# Explicit type, not := -- result's static type is ambiguous after
		# .duplicate() (same reason _apply_chroma_key's own `keyed.get_pixel`
		# is typed this way above), so inference has nothing concrete to
		# infer from.
		var was: Color = result.get_pixel(at.x, at.y)
		result.set_pixel(at.x, at.y, Color(was.r, was.g, was.b, 0.0))
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = at + step
			if next.x < 0 or next.x >= width or next.y < 0 or next.y >= height:
				continue
			if visited.has(next):
				continue
			if _color_distance(image.get_pixel(next.x, next.y), here) <= step_tolerance:
				queue.append(next)
	return result


## Mean per-channel RGB difference -- cheap, and all a per-step tolerance
## needs (unlike a masking decision, there is no hue-vs-brightness question
## here, just "is this neighbour close enough to still be background").
## Averaged rather than summed so `step_tolerance` reads as "typical
## per-channel difference" -- the same unit head_edge_probe.js measured the
## real background-to-face ramp in (a single max-channel reading per pixel);
## summing all three channels instead would silently need a tolerance ~3x
## larger for the same real-world gap on a roughly-greyscale transition like
## this sheet's, which is exactly the bug the first version of this
## function shipped with (its own test caught it: a uniform grey step the
## flood should clearly cross read as 0.45 distance under a raw sum, not the
## measured 0.15).
func _color_distance(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0


## ============================================================================
## hero_composite.png: 8 pre-colored outfits x {arms, torso, legs} --
## what body/legs/arms now actually come from.
## ============================================================================
##
## Replaces the single-pose neutral torso.png/leg.png/arms.png this class
## used to source "body"/"legs"/"arms" from via `_PARTS` (asked directly:
## "I added hero_composite ... use it"). Needs its own surface for the same
## reason head does: a variant (which of 8 outfits) axis the simple
## part->rects shape has no room for.
##
## REGENERATED once already, from a prompt this project wrote after
## measuring the first version's per-cell inconsistency (see
## docs/progress.md) -- 1024x1536, 3 columns (arms/torso/legs) x 8 rows, cell
## boundaries measured directly by scanning for real transparent gaps
## between content blocks (colorType 6, real populated alpha -- no
## chroma-key/flood needed, unlike head.png's solid background), not assumed
## from an even three-way pixel split (1024 does not divide evenly by 3).
## Column x-ranges are generous, not exact-to-the-pixel: normalize_frames'
## own crop-to-content step (see _composite_image) finds the real boundary
## inside whatever range it's given, so the range only has to fully CONTAIN
## one column's content without touching its neighbour's, not land exactly
## on the seam.
##
## PRE-COLORED per variant/row -- NOT neutral grey for runtime
## modulate-tinting the way body/legs/arms used to be. A caller must
## therefore leave `modulate` at WHITE for whatever this generates, the same
## rule the illustrated head's own luminance recolor follows: this art is
## already the color it should be.
##
## Which of the 8 outfits a hero wears is DNA-derived (asked directly, and
## answered the same way skin/hair/eyes already are: no new player-choosable
## axis, unlike head's own) -- see outfit_variant_for.
##
## legs are a FUSED pair (both legs drawn together, exactly like legs.png
## always was) -- CharacterView wears them as one sprite covering both world
## slots (see CharacterView._apply_legs). arms are genuinely TWO separate
## drawings side by side with real transparent space between them (unlike
## the fused legs, or the first hero_composite version's arms) -- detected
## as two frames via the same detect_frames column-emptiness scan the old
## arms.png used, not treated as one fused image, so ArmLeft/ArmRight keep
## independent art the way they did before.
##
## Only FRONT-facing art exists at this path today -- the earlier version
## additionally had a side-profile set, but this regenerated file replaced
## it with a cleaner front-only sheet (see the art brief's follow-up prompt
## for back/side, not yet run). `facing` stays a real parameter throughout
## this surface, defaulting to and currently only ever resolving to "front"
## (see _resolved_facing), so a future side/back sheet slots in without
## another signature change.

const HERO_COMPOSITE_PATH := "res://assets/sprites/player/hero_composite.png"

const HERO_COMPOSITE_ROW_HEIGHT := 192
const HERO_COMPOSITE_ROWS := 8

## x-ranges per part, front-facing, in art pixels -- see this section's own
## doc comment on how these were measured. Not an even 3-way split of the
## 1024px width: arms' content sits toward the left of its own third, so its
## range is trimmed slightly narrower than an even split would give it,
## leaving torso/legs the remainder.
## Verified against the LIVE slicer across all 8 rows, not just row 0 --
## `test_every_outfit_row_produces_the_expected_frame_count` -- after this
## exact class of miscount (a row's real content landing outside the
## assumed range, or a stray fragment landing inside it) twice reached the
## live game: once as a malformed portrait (body row 7's shoulder cape casts
## a detached fragment at x=[672,683) that an upper bound of 683 wrongly
## included as a second "body" frame) and once as a silently-missing part
## (legs row 7's content starts at x=670, left of an assumed 683 lower
## bound, so the whole frame fell outside the range and vanished). Bounds
## below are deliberately not an even three-way split of the 1024px width
## for exactly this reason -- they were adjusted until every row matched,
## not assumed from geometry.
const HERO_COMPOSITE_COLUMN_X := {
	"arms": {"front": Vector2i(0, 341)},
	"body": {"front": Vector2i(341, 660)},
	"legs": {"front": Vector2i(668, 1024)},
}

var _hero_composite_sheet: Image = null

## (part, variant, facing) key -> Array[Image] (1 entry for body/legs, 2 for
## arms) / measured content height of frame 0 -- the composite counterpart
## to _frame_cache/_head_content_height_cache: shared across every
## CharacterView, since geometry and color are both fixed once the art
## exists (nothing per-instance to lose by sharing).
static var _composite_frames_cache: Dictionary = {}
static var _composite_content_height_cache: Dictionary = {}


func has_composite_part(part_name: String) -> bool:
	return HERO_COMPOSITE_COLUMN_X.has(part_name)


## Which of the 8 pre-colored outfits this hero wears -- deterministic per
## seed, same "vary by DNA, no new UI" answer skin/hair/eyes already give
## (asked directly, unlike head's own real axis -- see HeroAppearance.AXES).
func outfit_variant_for(seed_value: int) -> int:
	return absi(hash("%d_outfit_variant" % seed_value)) % HERO_COMPOSITE_ROWS


## The pre-colored texture(s) for one part of one outfit variant -- one
## element for body/legs, two (left, right) for arms (see this section's own
## doc comment on why arms alone splits). Empty for an unregistered part,
## matching generate_textures' own "ask has_X first" contract.
func generate_composite_textures(part_name: String, variant: int, facing: String = "front") -> Array[ImageTexture]:
	var textures: Array[ImageTexture] = []
	for image in _composite_frames(part_name, variant, facing):
		textures.append(ImageTexture.create_from_image(image))
	return textures


## How much to scale the Sprite2D wearing this part/variant/facing/frame so
## it reads at `target_world_height` world units tall -- same
## measured-content approach as part_scale_for/head_scale_for above.
## `frame_index` matters for arms: its two drawings are independent, not a
## mirrored copy, so each side must be measured on its own.
func composite_part_scale_for(
	part_name: String, variant: int, target_world_height: float,
	frame_index: int = 0, facing: String = "front"
) -> float:
	var frames := _composite_frames(part_name, variant, facing)
	if frames.is_empty():
		return 1.0
	var index := clampi(frame_index, 0, frames.size() - 1)
	var key := "%s/%d" % [_composite_key(part_name, variant, facing), index]
	if not _composite_content_height_cache.has(key):
		_composite_content_height_cache[key] = _measured_content_height(frames[index])
	var content_height: float = _composite_content_height_cache[key]
	return target_world_height / content_height if content_height > 0.0 else 1.0


func _composite_key(part_name: String, variant: int, facing: String) -> String:
	return "%s/%d/%s" % [part_name, variant, facing]


## Only "front" resolves to real art today (see this section's own doc
## comment) -- anything else falls back to it rather than to nothing, so a
## caller asking for "side" before that art exists gets a facing hero
## instead of a blank one.
func _resolved_facing(part_name: String, facing: String) -> String:
	var facings: Dictionary = HERO_COMPOSITE_COLUMN_X.get(part_name, {})
	return facing if facings.has(facing) else "front"


## Finds and normalizes the frame(s) within one part's column for outfit row
## `variant` -- one frame for body/legs (the whole column is one drawing),
## two for arms (a real transparent gap splits it, found the same way
## detect_frames already splits any other divided sheet).
func _composite_frames(part_name: String, variant: int, facing: String) -> Array[Image]:
	if not HERO_COMPOSITE_COLUMN_X.has(part_name):
		return []
	var resolved := _resolved_facing(part_name, facing)
	var key := _composite_key(part_name, variant, resolved)
	if _composite_frames_cache.has(key):
		return _composite_frames_cache[key]
	if _hero_composite_sheet == null:
		_hero_composite_sheet = Image.load_from_file(HERO_COMPOSITE_PATH)
	var x_range: Vector2i = HERO_COMPOSITE_COLUMN_X[part_name][resolved]
	var row := clampi(variant, 0, HERO_COMPOSITE_ROWS - 1)
	var top := row * HERO_COMPOSITE_ROW_HEIGHT
	var bottom := top + HERO_COMPOSITE_ROW_HEIGHT
	var frame_rects := _slicer.detect_frames(_hero_composite_sheet, top, bottom)
	# Clip to this part's own x-range -- detect_frames scans the WHOLE row,
	# which would also find the neighbouring parts' content.
	var column_rects: Array[Rect2i] = []
	for rect in frame_rects:
		if rect.position.x >= x_range.x and rect.position.x + rect.size.x <= x_range.y:
			column_rects.append(_primary_content_rect(_hero_composite_sheet, rect))
	var result: Array[Image] = _slicer.normalize_frames(
		_hero_composite_sheet, column_rects, CANVAS_SIZE, BASELINE_Y
	)
	_composite_frames_cache[key] = result
	return result


## Clips `rect` down to just its first contiguous run of non-empty rows,
## discarding anything below the first real gap.
##
## detect_frames only ever splits on COLUMN gaps (see its own doc comment)
## -- it hands back a rect spanning the FULL row height regardless of what's
## actually drawn in it, on the assumption that one column-separated blob is
## one frame's whole vertical extent. hero_composite.png's rows break that
## assumption: several rows hold a second, unrelated close-up (a belt
## buckle, a shoulder pauldron) sitting BELOW the real garment at
## x-coordinates that land inside the very same legs/body column range, with
## a real gap of empty rows between the two. Left alone, normalize_frames'
## plain min/max bounding-box scan welds them into one "frame" spanning from
## the garment's top to the fragment's bottom -- inflating the measured
## content height composite_part_scale_for scales against (shrinking the
## real garment well below its intended on-screen size) and painting a
## second, unrelated object below it. Measured directly against the real
## sheet (see test_every_outfit_rows_legs_have_no_fragment_stacked_below_a_gap):
## 6 of legs' 8 rows and 6 of body's 8 rows carry this; only rows 0 and 7 of
## each are clean -- reached the live game as "still no legs" even after
## raising CharacterView.TARGET_HEIGHT_FRACTION_OF_TREE, because the actual
## defect was never size, it was this contamination.
##
## The real garment is always the FIRST (topmost) contiguous run in every
## row observed -- the stray fragment always sits below it, never above --
## so "first run, cut at the first full gap" is enough; no magic gap-size
## threshold is needed, the same single-empty-row-is-a-divider convention
## detect_frames itself already uses for columns (its own default
## min_divider_width is 1).
func _primary_content_rect(image: Image, rect: Rect2i) -> Rect2i:
	var left := rect.position.x
	var right := rect.position.x + rect.size.x
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y
	var content_start := -1
	for y in range(top, bottom):
		if _row_is_empty(image, y, left, right):
			if content_start >= 0:
				return Rect2i(left, content_start, rect.size.x, y - content_start)
			continue
		if content_start < 0:
			content_start = y
	if content_start < 0:
		return rect  # Fully empty -- let normalize_frames' own empty-content handling apply, unchanged.
	return Rect2i(left, content_start, rect.size.x, bottom - content_start)


func _row_is_empty(image: Image, y: int, left: int, right: int) -> bool:
	for x in range(left, right):
		if not SpriteSheetSlicer.is_empty(image.get_pixel(x, y)):
			return false
	return true


## The trimmed (padding-cropped) content image for one composite part/
## variant/frame -- the raw-Image-compositing counterpart to
## trimmed_part_image/trimmed_head_image, for ProceduralCharacterSprite's
## portrait. Null if the part or frame_index doesn't exist.
func trimmed_composite_image(
	part_name: String, variant: int, facing: String = "front", frame_index: int = 0
) -> Image:
	var frames := _composite_frames(part_name, variant, facing)
	if frames.is_empty():
		return null
	var index := clampi(frame_index, 0, frames.size() - 1)
	return _trimmed(frames[index])


## ============================================================================
## Leg hip/knee segments: a real joint on the fused leg pair, from the SAME
## pixels, no new art.
## ============================================================================
##
## Reported live, directly: "add proper walk animation by morphing the leg
## sprites and include a knee joint animated motion." The fused leg pair (see
## this file's own doc comment on why legs.png/hero_composite.png's legs
## column draws both legs together as one connected pose, not two
## independently-swinging sprites) has no thigh/shin split baked into the
## source art at all -- CharacterView cannot wear a "thigh" and "shin" that
## were never drawn separately.
##
## A full weight-painted Polygon2D/Skeleton2D mesh skin (the standard Godot
## mechanism for bending one texture smoothly around a joint with no visible
## seam) was evaluated and set aside for this pass: Godot 4's
## `Polygon2D.bones` property expects a specific, thinly-documented internal
## array shape (pairs of a Bone2D NodePath and a PackedFloat32Array of
## per-vertex weights, normally hand-painted with the editor's own UV/weight
## tool) that has to be assembled and assigned through `set("bones", ...)`
## from script -- with zero precedent anywhere in this codebase to build
## from, and real risk of a subtly wrong weight paint being effectively
## undebuggable without the editor's own visual painting tool. What this
## builds instead is the fallback the same design brief explicitly allows: a
## genuine two-piece CROP, hinged on a real hip+knee pivot chain
## (CharacterView._leg_left/_leg_knee, driven by leg_gait_cycle.gd's real
## hip_angle/knee_angle functions) -- real image content, cut rather than
## fabricated, cruder than a smooth skin (a rigid crop shows a seam once the
## knee actually bends, a soft skin wouldn't) but honest about being cruder,
## and buildable/testable with ordinary Image.get_region calls this file
## already uses everywhere else (see _trimmed).

## Thigh and shank are close enough to equal length in Winter's own
## anthropometric table (CharacterView.WINTER_THIGH_FRACTION_OF_HEIGHT ~=
## WINTER_SHANK_FRACTION_OF_HEIGHT -- see that constant's own citation) that
## the knee sits at essentially the leg art's own midpoint. This does NOT
## detect where a given outfit row's artist actually drew the knee crease --
## no such per-row pixel analysis is attempted -- it reuses the same real
## anthropometric number the leg's own overall height is already built from,
## rather than a second, independent eyeballed guess.
const KNEE_LINE_FRACTION := 0.5

## How far the thigh/shin crops overlap across the knee line, in raw
## composite-canvas pixels -- a real mitigation for the seam a RIGID
## two-piece crop-and-hinge (see this section's own doc comment on why it
## isn't a full weight-painted skin) would otherwise show the moment the
## knee bends even slightly. Several hero_composite.png outfit rows draw a
## belt or a heraldic banner that visually bridges straight across the knee
## line (verified directly: crop both rows and look -- row 0's belt sits
## well above the knee line, but row 7's banner runs from the hip down past
## it); a bare, non-overlapping cut would tear that shared decoration in two
## the instant the shin piece rotates independently of the thigh. Generous
## on purpose -- both crops carry the SAME pixels across this band at rest,
## so it costs nothing when the knee angle is zero (the shin piece is drawn
## on top and exactly matches what's already there), and only becomes a
## visible trade-off (a slightly thicker knee) once the joint actually bends.
const KNEE_OVERLAP_PX := 10


## The thigh (top) and shin (bottom) crops of one outfit variant's fused leg
## pair, split at KNEE_LINE_FRACTION of its own measured content height with
## a KNEE_OVERLAP_PX overlap band shared by both -- what CharacterView wears
## on its hip/knee pivot chain (see this section's own doc comment) instead
## of one whole-pair sprite, so a real hip+knee gait can bend the pair at a
## real joint instead of only ever rotating or bobbing it as one rigid
## whole. Returns `[thigh_image, shin_image]`; empty if legs aren't
## registered for this variant/facing (mirrors trimmed_composite_image's own
## has-X-then-fallback contract).
func composite_leg_segments(variant: int, facing: String = "front") -> Array[Image]:
	var trimmed := trimmed_composite_image("legs", variant, facing)
	if trimmed == null:
		return []
	var height := trimmed.get_height()
	var width := trimmed.get_width()
	var knee_y := clampi(roundi(height * KNEE_LINE_FRACTION), 1, height - 1)
	var thigh_bottom := mini(height, knee_y + KNEE_OVERLAP_PX)
	var shin_top := maxi(0, knee_y - KNEE_OVERLAP_PX)
	var thigh := trimmed.get_region(Rect2i(0, 0, width, thigh_bottom))
	var shin := trimmed.get_region(Rect2i(0, shin_top, width, height - shin_top))
	var result: Array[Image] = [thigh, shin]
	return result


## How far down (raw, unscaled texture-pixel units -- the same convention
## _composite_content_offset_y already uses for Sprite2D.offset elsewhere in
## this rig) the thigh crop's own drawn texture must be offset so its TOP
## edge -- not Sprite2D's own default CENTER -- lands on `.position` (the
## hip pivot). Pure geometry, no image access, independently testable
## without loading the real sheet.
func leg_thigh_offset_y(thigh_height_px: float) -> float:
	return thigh_height_px * 0.5


## The knee pivot's own LOCAL Y position (raw, unscaled pixel units) as a
## child of the hip/thigh sprite -- straight down from the hip line
## (`.position`, the thigh's own top edge, see leg_thigh_offset_y above) by
## however many pixels KNEE_LINE_FRACTION of the FULL trimmed leg puts the
## knee.
func leg_knee_pivot_local_y(trimmed_height_px: float) -> float:
	return trimmed_height_px * KNEE_LINE_FRACTION


## How far down the shin crop's own drawn texture must be offset so the SAME
## knee point the thigh/knee pivot above already sits at -- not the shin
## crop's own top edge, which is `overlap_px` pixels ABOVE that point (see
## composite_leg_segments) -- lands on the knee pivot's own `.position`.
func leg_shin_offset_y(shin_height_px: float, overlap_px: float) -> float:
	return shin_height_px * 0.5 - overlap_px


## ============================================================================
## Head art: a 10x10 grid of 100 fully-painted faces, recolored per hero.
## ============================================================================
##
## Not a neutral sheet like body/legs/arms -- head.png's faces are painted in
## a real, single baked-in skin tone with no alpha channel and a solid near-
## black background (measured: RGB 0-3 across the background, no gradient),
## so this needs its own load path rather than reusing `_PARTS`/
## generate_textures: crop one cell out of the grid, key its black background
## to real transparency (the same per-channel chroma-key body/legs/arms could
## use but don't need to), then recolor it toward the hero's own DNA-picked
## skin tone.

const HEAD_PATH := "res://assets/sprites/player/head.png"
const HEAD_GRID_COLUMNS := 10
const HEAD_GRID_ROWS := 10

## Its own canvas/baseline, deliberately NOT CANVAS_SIZE/BASELINE_Y -- a head
## is not a full standing limb anchored at ground contact, it is anchored
## where the neck meets the torso. Sized to match ART_HEAD_SIZE
## (CharacterView's existing procedural head texture size) so swapping to
## illustrated art does not silently resize the head relative to the rest of
## the rig or the .tscn's hand-placed Head node position.
const HEAD_CANVAS_SIZE := Vector2i(24, 24)
const HEAD_BASELINE_Y := 24

## The sheet's own background: near-pure black, no alpha channel -- but the
## transition into a face is a WIDE, gradual blur (measured directly against
## the real file: 20-30 pixels of ramp between near-black and clearly-face
## brightness, not a crisp cut). A flat per-pixel distance-from-black
## chroma-key first tried here either left a visible dark halo around every
## face (a tight tolerance, reported: the recolored head rendering as a dark
## block) or would have risked punching a hole through a genuinely dark part
## of a face -- an eye -- wherever it happened to also fall within tolerance
## of black. See _remove_background_by_flood's own doc comment for why a
## border flood fill replaces the flat key instead. This is the per-STEP
## tolerance the flood walks with, not a distance from a fixed reference
## color.
##
## Revised once already, the hard way: a first pass at 0.2 (calibrated from
## one cell's two scanlines, "generous enough to ride the measured blur")
## blew straight through most of the grid once actually run against every
## cell -- the real background-to-face contrast is not uniform across all
## 100 faces. Swept 0.02-0.18 against 7 sample cells with a throwaway
## harness that dumped the result at each value as a real PNG for direct
## visual comparison (not just an opaque-pixel percentage, which alone
## can't tell "cleanly isolated face" from "a fragment of one"): most cells
## hold a stable ~33-42% opaque from 0.02 up to a per-cell cliff between
## 0.06 and 0.10 where retention collapses to single digits (the flood
## leaking through a weak point on that face's silhouette a single scanline
## never sampled), but two of the seven (both darker-toned faces, rows 8-9
## of the grid) show no clean plateau at all -- they lose real content
## gradually from 0.02 upward, with no tolerance that is both fully clean
## AND fully safe for them. 0.02 is the value that visually held a complete,
## recognizable face on every sampled cell, including those two --
## conservative on purpose: a faint residual edge is a far smaller defect
## than eating into the face itself.
const HEAD_BACKGROUND_FLOOD_STEP_TOLERANCE := 0.02

## How dark the recolor's own deepest shading is allowed to go, and the floor
## under the sheet's measured peak brightness -- identical role to
## ProceduralFlowerSprite's ILLUSTRATED_SHADE_FLOOR/MINIMUM_PEAK_LUMINANCE,
## same reasoning: without a shade floor the darkest linework multiplies to
## near-black, which reads as a hole rather than shading; without a peak
## floor a sheet drawn entirely in shadow would divide up into a blown-out
## white blob instead of staying dark.
const HEAD_SHADE_FLOOR := 0.35
const HEAD_MINIMUM_PEAK_LUMINANCE := 0.35

## Loaded once and reused for every cell -- slicing 100 cells out of the same
## 1254x1254 sheet should not mean reading the file from disk 100 times.
var _head_sheet: Image = null

## cell_index -> its cropped/keyed/normalized (but not yet recolored) Image,
## and cell_index -> its measured content height (see head_scale_for). Kept
## separate from _head_texture_cache below: geometry doesn't depend on skin
## tone, so slicing a cell once serves every tone a hero might roll, and
## measuring its height once serves every hero who happens to land on this
## same cell.
static var _head_cell_cache: Dictionary = {}
static var _head_content_height_cache: Dictionary = {}

## (cell_index, skin_tone html) -> ImageTexture. Every hero with the same
## rolled face AND the same DNA skin tone shares one generated texture,
## mirroring IllustratedAnimalSprite/this class's own _frame_cache -- there
## is no per-instance state to lose by sharing.
static var _head_texture_cache: Dictionary = {}


func has_head() -> bool:
	return HEAD_PATH != ""


## Minimum fraction of a generated head texture's own canvas that must
## still be opaque for it to count as usable art, rather than a
## background-removal failure. Measured directly across all 100 cells: 7 of
## them (all but one landing in the sheet's own column 1, a systematic
## pattern rather than per-cell noise, though the exact cause wasn't chased
## down here) have their _remove_background_by_flood erode almost the
## entire face -- opaque fraction <=0.083 for every one of the 7 -- while
## every other cell holds comfortably above that. 0.15 sits with margin on
## both sides of that measured gap. Left unguarded, one of these 7 cells
## reaches the live game as a huge, near-blank, wildly oversized texture
## (head_scale_for dividing a target height by a near-zero measured content
## height) -- reported live as a floating translucent smear where a face
## should be.
const HEAD_MINIMUM_OPAQUE_FRACTION := 0.15

## The flood's OTHER failure mode, found by a second full-grid survey done
## alongside the near-empty one above: 12 of the 100 cells (a contiguous
## block, rows 1-2 columns 3-8 of the grid) come back with opaque fraction
## of essentially 1.0 -- the background wasn't removed AT ALL, leaving the
## whole square cell opaque, which recolors as a flat solid block rather
## than a face (reported live, seeing exactly this: a dark rectangle where
## a face should be). Consistent with _remove_background_by_flood's own
## border-flood approach: if one of these cells' face art is drawn all the
## way to (or past) the cell's own edge with no background margin left for
## the flood to start from, the flood never finds anywhere to begin and
## leaves the entire cell untouched. A real face's silhouette, cropped from
## a square cell, always leaves at least the corners transparent -- 1.0 is
## only reachable by a flood that found nothing to remove.
const HEAD_MAXIMUM_OPAQUE_FRACTION := 0.97


## Whether cell_index's generated (recolored) head texture is real, usable
## art -- the head counterpart to has_action/has_composite_part's own
## has-X-then-fallback contract, so a caller (CharacterView, the portrait)
## can fall back to the procedural head for the cells whose flood-fill
## failed (too little retained -- HEAD_MINIMUM_OPAQUE_FRACTION -- or too
## much -- HEAD_MAXIMUM_OPAQUE_FRACTION, see its own doc comment), exactly
## the same safety net body/legs/arms already apply for their own per-row
## gaps.
func has_usable_head(cell_index: int, skin_tone: Color) -> bool:
	if not has_head():
		return false
	var texture := generate_head_texture(cell_index, skin_tone)
	if texture == null:
		return false
	var image := texture.get_image()
	var total := image.get_width() * image.get_height()
	if total <= 0:
		return false
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.05:
				opaque += 1
	var fraction := float(opaque) / float(total)
	return fraction >= HEAD_MINIMUM_OPAQUE_FRACTION and fraction <= HEAD_MAXIMUM_OPAQUE_FRACTION


## Wraps any integer into a valid [0, 100) cell index, both directions --
## the same "cycling never goes out of range" contract HeroAppearance._wrap
## already gives every other axis. Defense in depth: HeroAppearance is the
## one caller expected to hand this a pre-wrapped index (see
## appearance_from_choices' own "head_index"), but a bad index here should
## still degrade to SOME face rather than an out-of-bounds crop.
func _wrap_cell_index(cell_index: int) -> int:
	var count := HEAD_GRID_COLUMNS * HEAD_GRID_ROWS
	return ((cell_index % count) + count) % count


## The recolored head texture for grid cell `cell_index` (see
## HeroAppearance's "head" axis / "head_index" on the appearance dict --
## this is a real player-chosen customization, not derived from a seed),
## tinted toward `skin_tone` -- null if no head art is registered
## (has_head() false), matching generate_textures' own "ask has_X first"
## contract.
##
## Recolors by LUMINANCE ONLY, discarding the sheet's own baked hue entirely
## -- the same trick ProceduralFlowerSprite._paint_illustrated_head already
## proved on illustrated blooms (see docs/concept/flora.md "Recolouring
## illustrated blooms"), applied here so two heroes with the identical face
## cell but different DNA skin tones actually read differently rather than
## both wearing the sheet's own single painted tone.
##
## Deliberately simpler than the flower version: there is no accent-hue mask
## separating eyes from skin, so an eye recolors along with the rest of the
## face rather than keeping its own color. Eyes in this art are already quite
## dark/low-luminance, so they still read as a distinctly darker patch of
## whatever tone the recolor lands on -- not indistinguishable from skin, just
## not independently colored. A real eye-color mask is a legitimate follow-up
## (see the art brief), not attempted here.
func generate_head_texture(cell_index: int, skin_tone: Color) -> ImageTexture:
	if not has_head():
		return null
	var index := _wrap_cell_index(cell_index)
	var cache_key := "%d_%s" % [index, skin_tone.to_html()]
	if _head_texture_cache.has(cache_key):
		return _head_texture_cache[cache_key]
	var recolored := _recolor_by_luminance(_load_head_cell(index), skin_tone)
	var texture := ImageTexture.create_from_image(recolored)
	_head_texture_cache[cache_key] = texture
	return texture


## How much to scale the Head Sprite2D so this cell's face reads at
## `target_world_height` world units tall -- the head's own counterpart to
## part_scale_for above, kept separate because head art goes through a
## different load/cache path (crop-a-grid-cell, not slice-a-sheet) and has no
## `frame_index`/`action` axis to key on, only a cell index.
func head_scale_for(cell_index: int, target_world_height: float) -> float:
	var index := _wrap_cell_index(cell_index)
	if not _head_content_height_cache.has(index):
		_head_content_height_cache[index] = _measured_content_height(_load_head_cell(index))
	var content_height: float = _head_content_height_cache[index]
	return target_world_height / content_height if content_height > 0.0 else 1.0


## Crops one grid cell out of the sheet, keys its black background to real
## transparency, and normalizes it onto HEAD_CANVAS_SIZE/HEAD_BASELINE_Y --
## everything generate_head_texture needs before the recolor pass.
## `cell_index` must already be wrapped into range -- callers go through
## generate_head_texture/head_scale_for, which do that.
func _load_head_cell(cell_index: int) -> Image:
	if _head_cell_cache.has(cell_index):
		return _head_cell_cache[cell_index]
	if _head_sheet == null:
		_head_sheet = Image.load_from_file(HEAD_PATH)
	var column := cell_index % HEAD_GRID_COLUMNS
	var row := cell_index / HEAD_GRID_COLUMNS
	# Integer division: 1254/10 = 125 with a small remainder the sheet's own
	# outer margin already absorbs, not a seam a cell boundary would land
	# inside (each face sits comfortably clear of its own cell's edges).
	var cell_width := _head_sheet.get_width() / HEAD_GRID_COLUMNS
	var cell_height := _head_sheet.get_height() / HEAD_GRID_ROWS
	var cropped := _head_sheet.get_region(
		Rect2i(column * cell_width, row * cell_height, cell_width, cell_height)
	)
	var keyed := _remove_background_by_flood(cropped, HEAD_BACKGROUND_FLOOD_STEP_TOLERANCE)
	var frames := _slicer.detect_frames(keyed, 0, keyed.get_height())
	var result := keyed
	if not frames.is_empty():
		var normalized := _slicer.normalize_frames(keyed, frames, HEAD_CANVAS_SIZE, HEAD_BASELINE_Y)
		if not normalized.is_empty():
			result = normalized[0]
	_head_cell_cache[cell_index] = result
	return result


## Repaints every opaque pixel of `image` as `tint` at that pixel's own
## brightness, discarding whatever hue the source was drawn in -- see
## generate_head_texture's own doc comment for why.
func _recolor_by_luminance(image: Image, tint: Color) -> Image:
	var peak := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.05:
				continue
			peak = maxf(peak, _luminance(c))
	peak = maxf(peak, HEAD_MINIMUM_PEAK_LUMINANCE)

	var recolored := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.05:
				continue
			var shade := _luminance(c) / peak
			var lit := HEAD_SHADE_FLOOR + (1.0 - HEAD_SHADE_FLOOR) * shade
			recolored.set_pixel(x, y, Color(tint.r * lit, tint.g * lit, tint.b * lit, c.a))
	return recolored


## Rec. 709 luminance -- a pixel's light and shade, none of its colour. Same
## formula as ProceduralFlowerSprite._luminance; duplicated for the same
## "no real coupling between these two classes" reason as _apply_chroma_key
## above.
func _luminance(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
