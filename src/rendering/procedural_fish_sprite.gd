extends RefCounted

## Species-shaped deterministic pixel-art generator for pond/ocean fish --
## small 16x10 top-down silhouettes in vivid, clearly distinct per-species
## colors (see SPECIES_BASE_COLORS), two of which get an extra overlay
## (trout speckles, koi patches) so they don't read as flat recolors of the
## same shape. Same "one shared shape, one color+pattern per species"
## approach as ProceduralAnimalSprite. Pure logic, no RandomNumberGenerator --
## same (species, seed) always yields the same image.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## NOT yet on the resolution pass: this generator stamps hand-authored
## ASCII bitmaps (see the SPECIES/SHAPE tables below), which are
## written for exactly this canvas. Doubling the canvas would need the
## bitmaps redrawn -- upscaling them adds pixels but no information,
## the trap docs/concept/art_resolution.md warns about. Converting
## these to anatomy-built sprites (as ProceduralAnimalSprite now is)
## is the real fix and is deferred.
const SIZE := Vector2i(16, 10)

const EYE_COLOR := Color(0.05, 0.05, 0.05)
const JITTER_RANGE := 0.1

## Vivid, mutually distinct per-species colors -- "colorful and multiple
## varieties" is the whole point of this generator, so every entry stays
## clearly saturated (test-pinned: s > 0.4) rather than fading toward a
## muddy/neutral tone.
const SPECIES_IDS: Array[String] = ["goldfish", "bluegill", "trout", "koi"]

const SPECIES_BASE_COLORS := {
	"goldfish": Color(0.95, 0.45, 0.08),
	"bluegill": Color(0.15, 0.55, 0.75),
	"trout": Color(0.55, 0.62, 0.28),
	"koi": Color(0.85, 0.25, 0.15),
}

## Trout gets dark speckles, koi gets white/black patches -- both overlaid on
## the same base silhouette so they read as visually distinct varieties
## rather than plain recolors. Goldfish/bluegill stay plain (their color
## contrast alone is enough).
const SPECKLED_SPECIES := {"trout": true}
const PATCHED_SPECIES := {"koi": true}
const SPECKLE_COUNT := 4
const PATCH_COUNT := 3
const PATCH_COLORS := [Color(0.95, 0.95, 0.92), Color(0.1, 0.08, 0.08)]

## Fish silhouette, facing right, tail fin at the left. Legend: '.'
## transparent, 'o' outline, 'b' body, 'h' highlight, 's' shade, 'e' eye,
## 'f' tail fin.
const FISH_BITMAP := [
	"................",
	"......oooo......",
	".....ohhhhoo....",
	"..oo.obbbbboo...",
	".offo.obbbbbeboo",
	".offo.obssssboo.",
	"..oo.obssssboo..",
	".....oosssboo...",
	"......ooooo.....",
	"................",
]

var _palette := PixelPalette.new()


func generate_texture(species: String, seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(species, seed_value))


## Renders `species` in its own color (falling back to "goldfish" for an
## unrecognized name) with a small seeded brightness jitter so individuals of
## the same species still vary slightly -- same technique as
## ProceduralAnimalSprite.generate_image.
func generate_image(species: String, seed_value: int) -> Image:
	var key: String = species if SPECIES_BASE_COLORS.has(species) else "goldfish"
	var base_color: Color = SPECIES_BASE_COLORS[key]

	var jitter := _seeded_unit_float(seed_value, key + "_shade") - 0.5
	var body := base_color.lightened(maxf(jitter * JITTER_RANGE, 0.0)).darkened(
		maxf(-jitter * JITTER_RANGE, 0.0)
	)
	var palette := {
		"o": _palette.outline_color(),
		"b": body,
		"h": _palette.highlight(body),
		"s": _palette.shade(body),
		"e": EYE_COLOR,
		"f": body.darkened(0.35),
	}

	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	for y in SIZE.y:
		var row: String = FISH_BITMAP[y]
		for x in mini(row.length(), SIZE.x):
			var glyph := row[x]
			if palette.has(glyph):
				image.set_pixel(x, y, palette[glyph])

	if SPECKLED_SPECIES.has(key):
		_paint_speckles(image, seed_value, key)
	if PATCHED_SPECIES.has(key):
		_paint_patches(image, seed_value, key)

	return image


## A handful of deterministic dark speckle dots scattered across body-colored
## pixels ('b'/'h'/'s') -- same idea as
## ProceduralAnimalSprite._paint_body_spots.
func _paint_speckles(image: Image, seed_value: int, key: String) -> void:
	var body_cells := _body_cells()
	if body_cells.is_empty():
		return
	for i in SPECKLE_COUNT:
		var spot_seed := absi(hash("%d_%s_speckle_%d" % [seed_value, key, i]))
		var cell: Vector2i = body_cells[spot_seed % body_cells.size()]
		image.set_pixel(cell.x, cell.y, EYE_COLOR.lightened(0.1))


## Deterministic alternating white/black patches over body-colored pixels --
## koi's signature look, distinguishing it from a plain-colored fish.
func _paint_patches(image: Image, seed_value: int, key: String) -> void:
	var body_cells := _body_cells()
	if body_cells.is_empty():
		return
	for i in PATCH_COUNT:
		var patch_seed := absi(hash("%d_%s_patch_%d" % [seed_value, key, i]))
		var cell: Vector2i = body_cells[patch_seed % body_cells.size()]
		var patch_color: Color = PATCH_COLORS[i % PATCH_COLORS.size()]
		image.set_pixel(cell.x, cell.y, patch_color)


func _body_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in SIZE.y:
		var row: String = FISH_BITMAP[y]
		for x in mini(row.length(), SIZE.x):
			if row[x] in ["b", "h", "s"]:
				cells.append(Vector2i(x, y))
	return cells


func _seeded_unit_float(seed_value: int, salt: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, salt])) % 10000) / 10000.0
