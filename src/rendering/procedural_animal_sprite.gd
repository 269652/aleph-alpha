extends RefCounted

## Species-shaped deterministic pixel-art generator: renders recognizable
## 24x16 animal silhouettes from 4 hand-authored shape families (boar-shaped,
## lynx-shaped, deer-shaped, wolf-shaped -- see SPECIES_BITMAPS), shaded and
## outlined, with a small seeded brightness jitter so individuals of the same
## species vary slightly. Every species maps to one of those 4 families (see
## SPECIES_SHAPE_FAMILY) and has its own coat color (SPECIES_BASE_COLORS), so
## new biome-specific species can reuse an existing silhouette in a new color
## rather than needing new pixel art. Pure logic, no RandomNumberGenerator --
## same (species, seed) always yields the same image. Intended to replace
## ProceduralSpriteGenerator's generic blob for creatures.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const WIDTH := 24
const HEIGHT := 16

const EYE_COLOR := Color(0.05, 0.05, 0.05)
const TUSK_COLOR := Color(0.92, 0.9, 0.8)
const JITTER_RANGE := 0.08

## Push coat colors toward a warmer, more saturated look before shading.
const BASE_SATURATE := 0.14

## Base coat colors: boar dark brown, lynx light tawny, herbivore deer-tan,
## predator wolf-gray -- brighter and more saturated than before so creatures
## read as vivid overworld critters rather than muddy blobs. Every biome-
## specific species added on top of these 4 (see SPECIES_SHAPE_FAMILY) gets
## its own entry here too, reusing one of the 4 hand-drawn silhouettes below
## with a new color rather than needing new pixel art. Colors stay in the
## same muted/moderately-saturated palette family as the original 4 (no
## neon/cartoonish tones) while remaining visually distinct from every other
## species, including whichever shape family they reuse.
const SPECIES_BASE_COLORS := {
	"boar": Color(0.44, 0.27, 0.13),
	"lynx": Color(0.86, 0.66, 0.36),
	"herbivore": Color(0.68, 0.48, 0.26),
	"predator": Color(0.47, 0.47, 0.52),
	"camel": Color(0.78, 0.62, 0.38),
	"jackal": Color(0.58, 0.5, 0.38),
	"reindeer": Color(0.75, 0.72, 0.68),
	"arctic_fox": Color(0.88, 0.88, 0.85),
	"tapir": Color(0.28, 0.26, 0.24),
	"jaguar": Color(0.75, 0.5, 0.22),
	"goat": Color(0.7, 0.68, 0.64),
	"mountain_lion": Color(0.62, 0.52, 0.4),
}

## Maps every species name to one of the 4 hand-drawn silhouette families in
## SPECIES_BITMAPS below -- so a new species can look recognizable (deer-ish,
## boar-ish, wolf-ish, lynx-ish) without hand-authoring new pixel art. The
## original 4 species each map to their own eponymous family; the 8 newer
## biome-specific species each reuse whichever family fits their real-world
## silhouette (e.g. reindeer/camel/goat are all deer-shaped grazers, jaguar/
## arctic_fox are lynx-shaped cats). Temperament/role are independent of
## shape family and set separately in CreatureInfo (e.g. tapir reuses boar's
## shape but is calm, not aggressive, like boar is).
const SPECIES_SHAPE_FAMILY := {
	"boar": "boar_shape",
	"lynx": "lynx_shape",
	"herbivore": "deer_shape",
	"predator": "wolf_shape",
	"camel": "deer_shape",
	"jackal": "wolf_shape",
	"reindeer": "deer_shape",
	"arctic_fox": "lynx_shape",
	"tapir": "boar_shape",
	"jaguar": "lynx_shape",
	"goat": "deer_shape",
	"mountain_lion": "wolf_shape",
}

## Jaguar (lynx-shaped) gets a scatter of dark rosette-like speckle dots so it
## reads as visually distinct from other lynx-shaped species rather than a
## plain recolor -- same speckle technique as
## ProceduralTreeSprite._paint_speckles. Nothing else is speckled.
const JAGUAR_SPOT_COLOR := Color(0.12, 0.08, 0.05)
const SPOT_COUNT := 6
const SPOTTED_SPECIES := {"jaguar": true}

var _palette := PixelPalette.new()

## Bitmap legend: '.' transparent, 'o' outline, 'b' body, 'h' highlight,
## 's' shade, 'e' eye, 'n' nose/snout, 'w' tusk. Rows shorter than WIDTH are
## padded with transparency. Boar-shaped keeps the top rows empty (stocky,
## low to the ground); lynx-shaped ears reach the very top rows. Keyed by
## shape family (see SPECIES_SHAPE_FAMILY), not species name, so multiple
## species can share one hand-authored silhouette.
const SPECIES_BITMAPS := {
	"boar_shape":
	[
		"........................",
		"........................",
		"........................",
		"........................",
		"........................",
		"....ooooooooooo.........",
		"...ohhhhhhhhhhhoo.......",
		"..ohhbbbbbbbbbbbhoo.....",
		"..obbbbbbbbbbbbbbboo....",
		"..obbbbbbbbbbbbebbnoo...",
		"..obbsssbbbbbbbbbnnnno..",
		"..obssssssbbbbbbsnnno...",
		"..obsssssssssssssoow....",
		"..oosbboossssbboo.......",
		"...obbo..o.obbo.........",
		"...oooo....oooo.........",
	],
	"lynx_shape":
	[
		".....o...o..............",
		"....oho.oho.............",
		"....ohhohho.............",
		"....ohhhhho.............",
		"....obebbeo.............",
		"....obbbbbo.............",
		".....obbbbooooooo.......",
		"....obbbbbbbbbbbboo.....",
		"....obbbbbbbbbbbbbo.oo..",
		"....obbssbbbbbbbbbooso..",
		"....obssssbbbbbbsssoo...",
		".....obsssssssssssso....",
		".....obbossssssobbo.....",
		".....obo..obbo..obo.....",
		".....oo...oo.o...oo.....",
		"........................",
	],
	"deer_shape":
	[
		"........................",
		"...o..o.................",
		"...oo.oo................",
		"...ohhho................",
		"...obebo................",
		"...obbo.................",
		"...obbooooooooo.........",
		"...obbbbbbbbbbbo........",
		"...obbbbbbbbbbbbo.......",
		"....obbssbbbbbsbo.......",
		"....obsssssssssso.......",
		"....obosssssssobo.......",
		"....obo.obbo...obo......",
		"....obo.obo....obo......",
		"....oo..oo......oo......",
		"........................",
	],
	"wolf_shape":
	[
		"........................",
		"..o..o..................",
		"..oooho.................",
		"..ohhhhoo...............",
		"..obebbboo..............",
		"..nnbbbbbo..............",
		"...obbbbboooooooo.......",
		"...obbbbbbbbbbbbboo.....",
		"....obbbbbbbbbbbbbso....",
		"....obbssbbbbbbbssso....",
		"....obsssssbbbsssoo.....",
		".....obossssssobso......",
		".....obo.obbo..oso......",
		".....oo..oo.o...o.......",
		"........................",
		"........................",
	],
}


func generate_texture(species: String, seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(species, seed_value))


## Looks up the shape family for `species` (falling back to the deer-shaped
## family, via the "herbivore" species, for anything unmapped -- same
## fail-safe-default philosophy as BiomeClassifier's `.get(name, default)`
## style) and renders that family's hand-authored bitmap in the species' own
## color. `key` (not the raw `species`) drives color/jitter/bitmap lookups so
## an unrecognized species resolves fully to "herbivore", not just its shape.
func generate_image(species: String, seed_value: int) -> Image:
	var key: String = species if SPECIES_SHAPE_FAMILY.has(species) else "herbivore"
	var family: String = SPECIES_SHAPE_FAMILY[key]
	var base_color: Color = _palette.saturate(SPECIES_BASE_COLORS[key], BASE_SATURATE)
	var bitmap: Array = SPECIES_BITMAPS[family]

	var jitter := _seeded_unit_float(seed_value, key + "_shade") - 0.5
	var coat := base_color.lightened(maxf(jitter * JITTER_RANGE, 0.0)).darkened(
		maxf(-jitter * JITTER_RANGE, 0.0)
	)
	var palette := {
		"o": _palette.outline_color(),
		"b": coat,
		"h": _palette.highlight(coat),
		"s": _palette.shade(coat),
		"e": EYE_COLOR,
		"n": base_color.darkened(0.5),
		"w": TUSK_COLOR,
	}

	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in HEIGHT:
		var row: String = bitmap[y]
		for x in mini(row.length(), WIDTH):
			var glyph := row[x]
			if palette.has(glyph):
				image.set_pixel(x, y, palette[glyph])

	if SPOTTED_SPECIES.has(key):
		_paint_body_spots(image, bitmap, seed_value)

	return image


## A handful of deterministic dark speckle dots scattered across a species'
## body-colored pixels (glyphs 'b'/'h'/'s' -- coat/highlight/shade, never
## outline/eye/nose/tusk), seeded from seed_value -- same idea as
## ProceduralTreeSprite._paint_speckles, adapted to a fixed bitmap instead of
## an ellipse. Currently used only for jaguar (see SPOTTED_SPECIES) so it
## reads as distinct from other lynx-shaped species rather than a plain
## recolor.
func _paint_body_spots(image: Image, bitmap: Array, seed_value: int) -> void:
	var body_cells: Array[Vector2i] = []
	for y in HEIGHT:
		var row: String = bitmap[y]
		for x in mini(row.length(), WIDTH):
			if row[x] in ["b", "h", "s"]:
				body_cells.append(Vector2i(x, y))
	if body_cells.is_empty():
		return

	for i in SPOT_COUNT:
		var spot_seed := absi(hash("%d_jaguar_spot_%d" % [seed_value, i]))
		var cell: Vector2i = body_cells[spot_seed % body_cells.size()]
		image.set_pixel(cell.x, cell.y, JAGUAR_SPOT_COLOR)


func _seeded_unit_float(seed_value: int, salt: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, salt])) % 10000) / 10000.0
