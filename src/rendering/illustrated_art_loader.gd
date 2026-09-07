extends RefCounted

## Loads and anchors one single-row illustrated-art sheet's frames, per
## docs/concept/illustrated_art_addressing.md's "The address" table
## (Anchors section) and "One generic loader slices, keys and anchors by
## this field. The existing classes become thin adapters over it rather
## than each carrying its own copy of `_slice_bands`."
##
## Thin glue over SpriteSheetSlicer -- frame detection, chroma-keying, and
## the existing baseline-normalization path are ALL reused, not
## reinvented (design pillar 1). The two anchors nothing shared before
## this file: `footprint` (new logic) and `center` (a variant of
## normalize_frames' own content-crop-then-scale, positioned differently
## -- see SpriteSheetSlicer.content_rect's own doc comment). `pivot`
## generalizes illustrated_item_sprite.gd's own cell-keeping approach
## (the two-row wooden_club pilot this convention supersedes) rather than
## duplicating it per item.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

var _slicer := SpriteSheetSlicer.new()


## `load_row`'s own pipeline, minus the disk read -- takes an already-
## loaded Image directly, so callers with a real file use `load_row`
## while tests exercise this against a synthetic sheet with no file
## system involved (mirrors SpriteSheetSlicer.detect_frames/
## normalize_frames' own Image-in, Image-out shape).
##
## `canvas_size` bounds baseline/center (ignored by pivot, which keeps
## every cell at its own sheet size, and by footprint, which is bounded
## by `tile_size` instead -- a placed structure's height is deliberately
## NOT canvas-clamped, since a tall structure genuinely needs to render
## taller than one tile). Returns [] if the sheet holds no detectable
## frames, or if `anchor` is not one of the four declared types.
func frames_for_image(
	image: Image, anchor: String, chroma_key: Color, chroma_key_tolerance: float,
	canvas_size: Vector2i, tile_size: int
) -> Array[Image]:
	if image == null:
		return []
	# Cell boundaries come from the RAW image, BEFORE chroma-keying --
	# mirroring illustrated_item_sprite.gd's own "found BEFORE chroma-
	# keying while the ground is still opaque" precedent. A solid chroma-
	# key ground is itself fully saturated (pure magenta), so it does NOT
	# read as background to detect_frames' own is_empty check (which only
	# recognizes transparency or a near-white divider) -- keying first
	# would make the ENTIRE ground vanish and leave only each frame's own
	# drawn content as a "frame," far narrower than the real cell.
	var frames := _slicer.detect_frames(image, 0, image.get_height())
	if frames.is_empty():
		return []
	var keyed := SpriteSheetSlicer.chroma_keyed(image, chroma_key, chroma_key_tolerance)
	match anchor:
		"baseline":
			return _slicer.normalize_frames(keyed, frames, canvas_size, canvas_size.y)
		"pivot":
			return _anchor_pivot(keyed, frames)
		"center":
			return _anchor_center(keyed, frames, canvas_size)
		"footprint":
			return _anchor_footprint(keyed, frames, tile_size)
		_:
			return []


## `frames_for_image`, reading `path` from disk first (SpriteSheetLoader,
## not a raw Image.load_from_file -- see that class's own doc comment on
## why: a real .import sidecar needs the engine's own loader).
func load_row(
	path: String, anchor: String, chroma_key: Color, chroma_key_tolerance: float,
	canvas_size: Vector2i, tile_size: int
) -> Array[Image]:
	return frames_for_image(
		SpriteSheetLoader.load_image(path), anchor, chroma_key, chroma_key_tolerance,
		canvas_size, tile_size
	)


## Held items: a declared grip point stays at the same cell pixel every
## frame. Whatever is drawn at a cell pixel stays at that pixel -- no
## content crop, no rescale, the whole cell returned as-is (already
## chroma-keyed).
func _anchor_pivot(keyed: Image, frames: Array[Rect2i]) -> Array[Image]:
	var out: Array[Image] = []
	for frame in frames:
		out.append(keyed.get_region(frame))
	return out


## Icons: content-cropped and centered on a square canvas -- unlike
## `baseline`, which stands content on a shared foot-line, this centers
## on BOTH axes, so an icon reads as centered in its own frame rather
## than standing on an implied ground line no icon actually has.
func _anchor_center(keyed: Image, frames: Array[Rect2i], canvas_size: Vector2i) -> Array[Image]:
	var out: Array[Image] = []
	for frame in frames:
		var content := _slicer.content_rect(keyed, frame, SpriteSheetSlicer.DEFAULT_ALPHA_THRESHOLD, SpriteSheetSlicer.DEFAULT_DIVIDER_GRAY_MIN)
		if content.size.x <= 0 or content.size.y <= 0:
			continue
		var drawing := keyed.get_region(content)
		if drawing.get_format() != Image.FORMAT_RGBA8:
			drawing.convert(Image.FORMAT_RGBA8)
		var scale: float = minf(
			float(canvas_size.x) / float(content.size.x), float(canvas_size.y) / float(content.size.y)
		)
		var width := maxi(1, int(round(float(content.size.x) * scale)))
		var height := maxi(1, int(round(float(content.size.y) * scale)))
		drawing.resize(width, height, Image.INTERPOLATE_LANCZOS)
		var canvas := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
		var left := (canvas_size.x - width) / 2
		var top := (canvas_size.y - height) / 2
		canvas.blit_rect(drawing, Rect2i(0, 0, width, height), Vector2i(left, top))
		out.append(canvas)
	return out


## Placed structures: the cell's bottom edge is the tile's bottom edge;
## width matches the tile footprint. The WHOLE cell (not content-cropped
## -- a structure is drawn to fill its own canvas already, the same
## "whatever is drawn stays where it is drawn" shape `pivot` uses, not
## `center`'s), uniformly scaled so its width equals `tile_size` --
## height scales by the identical factor, so a structure taller than one
## tile (a campfire, a furnace) stays taller than one tile rather than
## being squashed to fit a fixed canvas. No repositioning: the caller
## (a `Sprite2D`, per that doc's own "the first subject whose placed art
## is a Sprite2D rather than a tile baked into TerrainRenderer's atlas")
## anchors the returned image's own bottom edge at the tile's bottom
## edge itself, the same way any bottom-anchored sprite already does.
func _anchor_footprint(keyed: Image, frames: Array[Rect2i], tile_size: int) -> Array[Image]:
	var out: Array[Image] = []
	for frame in frames:
		var cell := keyed.get_region(frame)
		if cell.get_format() != Image.FORMAT_RGBA8:
			cell.convert(Image.FORMAT_RGBA8)
		var scale := float(tile_size) / float(frame.size.x)
		var width := maxi(1, int(round(float(frame.size.x) * scale)))
		var height := maxi(1, int(round(float(frame.size.y) * scale)))
		cell.resize(width, height, Image.INTERPOLATE_LANCZOS)
		out.append(cell)
	return out
