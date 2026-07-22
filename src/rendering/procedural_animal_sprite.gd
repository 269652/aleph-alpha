extends RefCounted

## Species-shaped deterministic pixel-art generator: renders recognizable
## 24x16 animal silhouettes (boar, lynx, deer-ish herbivore, wolf-ish
## predator) from hand-authored bitmaps, shaded and outlined, with a small
## seeded brightness jitter so individuals of the same species vary slightly.
## Pure logic, no RandomNumberGenerator -- same (species, seed) always yields
## the same image. Intended to replace ProceduralSpriteGenerator's generic
## blob for creatures.

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
## read as vivid overworld critters rather than muddy blobs.
const SPECIES_BASE_COLORS := {
	"boar": Color(0.44, 0.27, 0.13),
	"lynx": Color(0.86, 0.66, 0.36),
	"herbivore": Color(0.68, 0.48, 0.26),
	"predator": Color(0.47, 0.47, 0.52),
}

var _palette := PixelPalette.new()

## Bitmap legend: '.' transparent, 'o' outline, 'b' body, 'h' highlight,
## 's' shade, 'e' eye, 'n' nose/snout, 'w' tusk. Rows shorter than WIDTH are
## padded with transparency. Boar deliberately keeps the top rows empty
## (stocky, low to the ground); lynx ears reach the very top rows.
const SPECIES_BITMAPS := {
	"boar":
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
	"lynx":
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
	"herbivore":
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
	"predator":
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


func generate_image(species: String, seed_value: int) -> Image:
	var key: String = species if SPECIES_BITMAPS.has(species) else "herbivore"
	var base_color: Color = _palette.saturate(SPECIES_BASE_COLORS[key], BASE_SATURATE)
	var bitmap: Array = SPECIES_BITMAPS[key]

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
	return image


func _seeded_unit_float(seed_value: int, salt: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, salt])) % 10000) / 10000.0
