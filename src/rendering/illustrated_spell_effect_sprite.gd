extends RefCounted

## Real illustrated art for spell atom effects, superseding
## ProceduralSpellEffectSprite per atom once registered here -- the same
## procedural-first, illustrated-second two-track pattern every other
## subject in this engine follows (docs/concept/magic.md's "Atom effects
## render as composite spritemaps" section, docs/concept/spell_runtime.md).
##
## magic.md's own brainstorm called for one sheet PER ATOM. What was
## actually delivered (docs/art/ai_sprite_prompts.md section 8, written
## once someone sat down to plan the real generation batches) groups
## delivery by the procedural generator's own 6 shared silhouette families
## instead -- burst/ring/cross/spiral/chevron/cloud -- one image per family,
## each atom still its own distinct 6-frame row within it. This is a
## delivery-efficiency divergence, not a design one: every atom still gets
## its own distinct art (magic.md's binding requirement), just co-located
## on disk rather than one file each. `cross.png` in particular holds TWO
## families (cross rows 0-2, spiral rows 3-5) in one file, since both are
## too small (3 atoms each) to warrant a generation session of their own.
##
## Grid measured directly per family sheet, not auto-detected: these
## effect sheets are dense with radiating spikes and scattered sparkle
## particles that routinely bridge or fake a SpriteSheetSlicer.detect_
## frames/detect_rows gap (measured live: automatic column detection on
## fire.png's own 7 rows returned anywhere from 1 to 9 "frames" depending
## on how sparse that particular atom's wind-up/fade frame happened to be)
## -- the same "measured directly, not assumed" precedent illustrated_
## mushroom_sprite.gd's own _ROW_BANDS already sets for a sheet whose rows
## aren't uniform. Columns split each row into 6 EQUAL frames instead (the
## generation brief's own "6-frame effect cycle... generous empty magenta
## padding around each pose" spec), verified end to end via a rendered
## contact-sheet probe before landing (no automatic detection needed once
## rows are known and content is safely padded inside its own column).

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")

## Resolution a frame is baked at. Deliberately NOT ProceduralSpellEffectSprite.
## SIZE (32): these are real illustrated sheets with far more source detail
## per frame (~300-400px) than a 32x32 procedural draw ever has, and baking
## straight down to 32px measured as destroying exactly the detail that
## reads as fire vs. lightning vs. ice -- shock_damage's jagged bolt spikes
## and saturated yellow core blurred into an indistinct pink-orange smear at
## 32px (a live report: "spark... should have more of a lightning effect"),
## confirmed by a direct side-by-side bake at 32/64/96/128px before landing
## this. SpellEffectMarker compensates the ON-SCREEN size (see
## DISPLAY_WORLD_SIZE) so switching between an atom with illustrated art and
## the smaller procedural fallback doesn't visibly jump in size.
const CANVAS_SIZE := 128

## The on-screen size (world pixels, at Sprite2D scale 1.0) every spell
## effect should read at regardless of its own texture's resolution --
## SpellEffectMarker scales by DISPLAY_WORLD_SIZE / texture width, so
## illustrated art (baked at CANVAS_SIZE) and the procedural fallback
## (drawn natively at its own SIZE) land on the same apparent size.
const DISPLAY_WORLD_SIZE := ProceduralSpellEffectSprite.SIZE

const FRAMES_PER_ROW := 6

## Shrinks every cell rect (rows and columns alike) by this many pixels on
## each side before content_rect scans it. Real bug found live: a cell
## rect that starts even 1-2px from a sheet's own divider line (near-white,
## ~1-2px wide plus antialiasing) still contains a sliver of that line --
## content_rect (which bounds ALL non-background pixels, not just the
## connected burst/ring/etc shape) then stretches to include it, both
## visibly leaking a thin magenta-tinted line into the baked frame AND
## shrinking the real art to share canvas space with it. Confirmed by
## direct pixel sampling (a divider's white core sits literally 1px from
## one measured column bound) and by a before/after bake. The generation
## brief's own "generous empty magenta padding around each pose so nothing
## touches a divider or the canvas edge" means real content is never this
## close to a boundary, so this margin only ever trims padding.
const _CELL_INSET_PX := 5

const _MAGENTA := Color(0.98, 0.01, 0.98)
## 0.25 (this codebase's usual convention, e.g. illustrated_mushroom_sprite.
## gd) left visible fully-opaque magenta-pink specks in a baked frame,
## confirmed by direct pixel sampling: the delivered sheets' own magenta
## backdrop is faintly textured/dithered per-pixel rather than a flat
## colour, and some of that texture's noise sits up to ~0.32 away from the
## sampled key on the green channel alone -- invisible at the smaller
## canvas this class used to bake at (an aggressive downscale blended the
## stray specks away by accident), a real defect at CANVAS_SIZE's larger
## one. Real content colours (the art's own oranges/yellows/blues/whites)
## sit far beyond any tolerance this wide, so widening it only ever
## reaches further into background noise, never into a real drawing.
const _MAGENTA_TOLERANCE := 0.4

## family_key -> {path, row_bands, col_bounds, atoms}. row_bands[i] is
## atoms[i]'s own (top_y, bottom_y) band within the sheet at `path`, top to
## bottom in delivery order -- exactly docs/art/ai_sprite_prompts.md
## section 8's own per-family atom tables. col_bounds is the sheet's own 7
## x-boundaries (6 columns) -- measured per file, not a uniform width/6
## split: a uniform split was off by up to ~12px from a real divider line
## on some boundaries (columns are NOT evenly sized -- e.g. fire.png's own
## widths run 391/347/350/350/350/384), which _CELL_INSET_PX alone could
## not reliably clear.
const _FAMILIES := {
	"burst": {
		"path": "res://assets/sprites/magic/fire.png",
		"atoms": ["fire_damage", "frost_damage", "shock_damage", "ignite", "induce_mutation", "illuminate", "fear"],
		"row_bands": [
			Vector2i(0, 107), Vector2i(107, 208), Vector2i(208, 310), Vector2i(310, 410),
			Vector2i(410, 512), Vector2i(512, 614), Vector2i(614, 724),
		],
		"col_bounds": [0, 390, 737, 1087, 1437, 1787, 2172],
	},
	"ring": {
		"path": "res://assets/sprites/magic/ring.png",
		"atoms": ["freeze", "root", "shield", "reveal", "suppress_mutation", "calm", "teleport", "portal"],
		"row_bands": [
			Vector2i(0, 116), Vector2i(116, 237), Vector2i(237, 351), Vector2i(351, 470),
			Vector2i(470, 601), Vector2i(601, 708), Vector2i(708, 853), Vector2i(853, 1024),
		],
		"col_bounds": [0, 256, 512, 768, 1023, 1279, 1536],
	},
	# cross.png delivers TWO families in one file (see class doc comment):
	# rows 0-2 are the cross family, rows 3-5 are spiral.
	"cross_and_spiral": {
		"path": "res://assets/sprites/magic/cross.png",
		"atoms": ["minor_heal", "major_heal", "summon_wisp", "slow", "accelerate_growth", "gravity_shift"],
		"row_bands": [
			Vector2i(15, 157), Vector2i(165, 335), Vector2i(341, 489),
			Vector2i(527, 672), Vector2i(692, 837), Vector2i(847, 1004),
		],
		"col_bounds": [0, 255, 511, 767, 1023, 1279, 1536],
	},
	"chevron": {
		"path": "res://assets/sprites/magic/chevron.png",
		"atoms": ["push", "pull"],
		"row_bands": [Vector2i(58, 412), Vector2i(473, 827)],
		"col_bounds": [0, 273, 542, 886, 1232, 1504, 1774],
	},
	"cloud": {
		"path": "res://assets/sprites/magic/cloud.png",
		"atoms": ["poison_damage", "blight"],
		"row_bands": [Vector2i(43, 335), Vector2i(390, 681)],
		"col_bounds": [0, 362, 724, 1086, 1449, 1812, 2172],
	},
}

## atom_id -> family_key, built once from _FAMILIES so callers look up by
## atom without scanning every family's own atom list.
static var _atom_family: Dictionary = {}

## family_key -> {atom_id -> Array[ImageTexture]} -- a whole family's sheet
## is loaded and sliced once, on first use by ANY of its atoms, not once
## per atom (mirrors ProceduralSpellEffectSprite._texture_cache's own
## per-process, load-once reasoning).
static var _family_frames_cache: Dictionary = {}

var _slicer := SpriteSheetSlicer.new()


func _init() -> void:
	if _atom_family.is_empty():
		for family_key in _FAMILIES:
			for atom_id in _FAMILIES[family_key]["atoms"]:
				_atom_family[atom_id] = family_key


func has_look(atom_id: String) -> bool:
	return _atom_family.has(atom_id)


func frame_count(atom_id: String) -> int:
	return frames_for(atom_id).size()


## The atom's real 6-frame effect cycle (wind-up/peak/fade, per docs/art/
## ai_sprite_prompts.md section 8's own addendum), or an empty array if no
## illustrated look is registered -- callers fall back to
## ProceduralSpellEffectSprite in that case, the same has_look()-gated
## shape every other optional illustrated-art seam in this codebase uses.
func frames_for(atom_id: String) -> Array[ImageTexture]:
	if not has_look(atom_id):
		return []
	var family_key: String = _atom_family[atom_id]
	if not _family_frames_cache.has(family_key):
		_family_frames_cache[family_key] = _load_family(family_key)
	return _family_frames_cache[family_key][atom_id]


func _load_family(family_key: String) -> Dictionary:
	var family: Dictionary = _FAMILIES[family_key]
	var raw := SpriteSheetLoader.load_image(family["path"])
	var keyed := SpriteSheetSlicer.chroma_keyed(raw, _MAGENTA, _MAGENTA_TOLERANCE)
	var atoms: Array = family["atoms"]
	var row_bands: Array = family["row_bands"]
	var col_bounds: Array = family["col_bounds"]

	var result: Dictionary = {}
	for i in atoms.size():
		var band: Vector2i = row_bands[i]
		var frames: Array[ImageTexture] = []
		for col in FRAMES_PER_ROW:
			var x0: int = col_bounds[col] + _CELL_INSET_PX
			var x1: int = col_bounds[col + 1] - _CELL_INSET_PX
			var rect := Rect2i(
				x0, band.x + _CELL_INSET_PX, x1 - x0, (band.y - _CELL_INSET_PX) - (band.x + _CELL_INSET_PX)
			)
			frames.append(ImageTexture.create_from_image(_center_frame(keyed, rect)))
		result[atoms[i]] = frames
	return result


## Content-cropped and centered on a CANVAS_SIZE square, both axes -- these
## are small floating effects with no ground/baseline to stand on (per the
## generation brief: "no ground, no shadow, no surrounding scene"), so this
## mirrors illustrated_art_loader.gd's own `center` anchor rather than
## SpriteSheetSlicer.normalize_frames' baseline-positioned one.
func _center_frame(keyed: Image, rect: Rect2i) -> Image:
	var canvas := Image.create(CANVAS_SIZE, CANVAS_SIZE, false, Image.FORMAT_RGBA8)
	var content := _slicer.content_rect(
		keyed, rect, SpriteSheetSlicer.DEFAULT_ALPHA_THRESHOLD, SpriteSheetSlicer.DEFAULT_DIVIDER_GRAY_MIN
	)
	if content.size.x <= 0 or content.size.y <= 0:
		return canvas
	var drawing := keyed.get_region(content)
	if drawing.get_format() != Image.FORMAT_RGBA8:
		drawing.convert(Image.FORMAT_RGBA8)
	var scale: float = minf(float(CANVAS_SIZE) / float(content.size.x), float(CANVAS_SIZE) / float(content.size.y))
	var width := maxi(1, int(round(float(content.size.x) * scale)))
	var height := maxi(1, int(round(float(content.size.y) * scale)))
	drawing.resize(width, height, Image.INTERPOLATE_LANCZOS)
	var left := (CANVAS_SIZE - width) / 2
	var top := (CANVAS_SIZE - height) / 2
	canvas.blit_rect(drawing, Rect2i(0, 0, width, height), Vector2i(left, top))
	return canvas
