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
## Measured directly from each PNG rather than guessed: torso.png and
## leg.png are already real alpha-channel art (a single pose each, no
## divider to find), and arms.png is 1774x887 -- exactly two 887x887 tiles
## side by side.
const _PARTS := {
	"body": {
		"path": "res://assets/sprites/player/torso.png",
		"idle_rects": [Rect2i(0, 0, 1254, 1254)],
	},
	"legs": {
		"path": "res://assets/sprites/player/leg.png",
		"idle_rects": [Rect2i(0, 0, 1024, 1536)],
	},
	"arms": {
		"path": "res://assets/sprites/player/arms.png",
		"idle_rects": [Rect2i(0, 0, 887, 887), Rect2i(887, 0, 887, 887)],
	},
}

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
func trimmed_head_image(seed_value: int, skin_tone: Color) -> Image:
	var texture := generate_head_texture(seed_value, skin_tone)
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


## Manhattan distance in RGB -- cheap, and all that a per-step tolerance
## needs (unlike a masking decision, there is no hue-vs-brightness question
## here, just "is this neighbour close enough to still be background").
func _color_distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


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
## color -- generous enough to ride the measured blur (steps up to ~0.18)
## while stopping at the sharpest jump measured at the true edge (~0.176 in
## the sampled ramp).
const HEAD_BACKGROUND_FLOOD_STEP_TOLERANCE := 0.2

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


## Which of the grid's 100 cells this hero wears -- deterministic per seed
## (see HeroAppearance.appearance_for/appearance_from_choices carrying
## "seed"), so a hero's face never changes from one frame, or one session, to
## the next.
func head_cell_index_for(seed_value: int) -> int:
	return absi(hash("%d_head_cell" % seed_value)) % (HEAD_GRID_COLUMNS * HEAD_GRID_ROWS)


## The recolored head texture for this seed's chosen face, tinted toward
## `skin_tone` -- null if no head art is registered (has_head() false),
## matching generate_textures' own "ask has_X first" contract.
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
func generate_head_texture(seed_value: int, skin_tone: Color) -> ImageTexture:
	if not has_head():
		return null
	var cell_index := head_cell_index_for(seed_value)
	var cache_key := "%d_%s" % [cell_index, skin_tone.to_html()]
	if _head_texture_cache.has(cache_key):
		return _head_texture_cache[cache_key]
	var recolored := _recolor_by_luminance(_load_head_cell(cell_index), skin_tone)
	var texture := ImageTexture.create_from_image(recolored)
	_head_texture_cache[cache_key] = texture
	return texture


## How much to scale the Head Sprite2D so this hero's face reads at
## `target_world_height` world units tall -- the head's own counterpart to
## part_scale_for above, kept separate because head art goes through a
## different load/cache path (crop-a-grid-cell, not slice-a-sheet) and has no
## `frame_index`/`action` axis to key on, only a seed.
func head_scale_for(seed_value: int, target_world_height: float) -> float:
	var cell_index := head_cell_index_for(seed_value)
	if not _head_content_height_cache.has(cell_index):
		_head_content_height_cache[cell_index] = _measured_content_height(_load_head_cell(cell_index))
	var content_height: float = _head_content_height_cache[cell_index]
	return target_world_height / content_height if content_height > 0.0 else 1.0


## Crops one grid cell out of the sheet, keys its black background to real
## transparency, and normalizes it onto HEAD_CANVAS_SIZE/HEAD_BASELINE_Y --
## everything generate_head_texture needs before the recolor pass.
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
