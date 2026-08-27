extends RefCounted

## Species-shaped deterministic pixel-art generator for pond/ocean fish --
## small 16x10 top-down silhouettes in vivid, clearly distinct per-species
## colors (see SPECIES_BASE_COLORS), two of which get an extra overlay
## (trout speckles, koi patches) so they don't read as flat recolors of the
## same shape. Same "one shared shape, one color+pattern per species"
## approach as ProceduralAnimalSprite. Pure logic, no RandomNumberGenerator --
## same (species, seed) always yields the same image.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const PixelRamp = preload("res://src/rendering/pixel_ramp.gd")
const PixelForm = preload("res://src/rendering/pixel_form.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")




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
const SPECKLE_COUNT := 4 * 4
const PATCH_COUNT := 4 * 3
const PATCH_COLORS := [Color(0.95, 0.95, 0.92), Color(0.1, 0.08, 0.08)]

## Fish silhouette, facing right, tail fin at the left. Legend: '.'
## transparent, 'o' outline, 'b' body, 'h' highlight, 's' shade, 'e' eye,
## 'f' tail fin.


var _palette := PixelPalette.new()
var _ramp := PixelRamp.new()
var _form := PixelForm.new()


## How many distinct individual looks a species has, once generate_texture
## buckets a seed down to a cache key. Fish are chunk-spawned with
## MAX_FISH_PER_CHUNK capping population per chunk but potentially many
## water chunks loaded/visible at once -- an uncached generate_texture meant
## every visible fish paid its own image-generation cost AND ended up
## permanently unbatchable with every other fish, even of the same species,
## since each got its own unique Texture2D object. Same bucketing philosophy
## as ProceduralAnimalAnimation.LOOK_VARIANTS: bounded so a pond full of
## goldfish is a handful of shared pictures, not one composite per fish.
const LOOK_VARIANTS := 8

static var _texture_cache: Dictionary = {}


## Individuals sharing a (species, look) share one Texture2D. Instance
## method over a static cache because FishRenderer holds its own
## ProceduralFishSprite, so a per-instance cache would still redraw once per
## fish -- same reasoning as ProceduralAnimalAnimation.textures_for.
func generate_texture(species: String, seed_value: int) -> ImageTexture:
	var variant := absi(seed_value) % LOOK_VARIANTS
	var key := "%s/%d" % [species, variant]
	if not _texture_cache.has(key):
		_texture_cache[key] = ImageTexture.create_from_image(generate_image(species, variant))
	return _texture_cache[key]


## Renders `species` in its own color (falling back to "goldfish" for an
## unrecognized name) with a small seeded brightness jitter so individuals of
## the same species still vary slightly -- same technique as
## ProceduralAnimalSprite.generate_image.
## The fish's WORLD footprint, in world units -- unchanged by the art
## resolution pass (see docs/concept/art_resolution.md).
const WORLD_SIZE := Vector2i(16, 10)

## The ART canvas: DETAIL_MULTIPLIER times the world footprint. FishRenderer
## draws it at ArtResolution.SPRITE_SCALE.
const SIZE := Vector2i(32, 20)

## Per-species body plan, as fractions of the canvas. Fish used to stamp ONE
## hand-authored bitmap, so every species was the same silhouette in a
## different colour -- the same flaw the land animals had (see
## AnimalAnatomy). These are the proportions that actually tell real fish
## apart: how deep the body is, how forked the tail, how tall the dorsal
## fin.
##   body_length/body_depth   the barrel, as canvas fractions
##   tail_length/tail_fork    caudal fin size, and how deeply notched
##   dorsal_height            dorsal fin height above the back
const SPECIES_BODY := {
	# Round, deep-bodied, small fins.
	"goldfish": {"body_length": 0.60, "body_depth": 0.60, "tail_length": 0.22, "tail_fork": 0.35, "dorsal_height": 0.16},
	# Compact panfish, tall dorsal.
	"bluegill": {"body_length": 0.56, "body_depth": 0.66, "tail_length": 0.20, "tail_fork": 0.25, "dorsal_height": 0.26},
	# Streamlined torpedo with a deeply forked tail.
	"trout": {"body_length": 0.72, "body_depth": 0.40, "tail_length": 0.26, "tail_fork": 0.55, "dorsal_height": 0.15},
	# Long and deep -- the big carp body.
	"koi": {"body_length": 0.74, "body_depth": 0.56, "tail_length": 0.24, "tail_fork": 0.30, "dorsal_height": 0.13},
}


func generate_image(species: String, seed_value: int) -> Image:
	var key: String = species if SPECIES_BASE_COLORS.has(species) else "goldfish"
	var base_color: Color = SPECIES_BASE_COLORS[key]

	var jitter := PixelNoise.unit(seed_value, key.length(), 0) - 0.5
	var body := base_color.lightened(maxf(jitter * JITTER_RANGE, 0.0)).darkened(
		maxf(-jitter * JITTER_RANGE, 0.0)
	)

	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	_paint_fish(image, SPECIES_BODY.get(key, SPECIES_BODY["goldfish"]), body)
	_outline_silhouette(image)

	if SPECKLED_SPECIES.has(key):
		_paint_speckles(image, seed_value, key)
	if PATCHED_SPECIES.has(key):
		_paint_patches(image, seed_value, key)

	return image


## The fish faces right. Built from a body ellipse, a forked caudal fin
## behind it, and a dorsal fin above -- flat-coloured with one shadow band
## along the belly, matching the codebase's 16-bit convention (see
## docs/concept/pixel_art_engine.md).
func _paint_fish(image: Image, plan: Dictionary, body: Color) -> void:
	var w := float(SIZE.x)
	var h := float(SIZE.y)
	var half := Vector2(plan.body_length * w * 0.5, plan.body_depth * h * 0.5)
	var center := Vector2(w * 0.56, h * 0.5)
	var belly := _ramp.sample(body, _BELLY_STOP)
	var fin := _ramp.sample(body, _FIN_STOP)

	# Caudal fin: a triangle behind the body, notched by tail_fork.
	var tail_length: float = plan.tail_length * w
	var tail_root := center.x - half.x + 1.0
	for x in SIZE.x:
		var into_tail := tail_root - (float(x) + 0.5)
		if into_tail < 0.0 or into_tail > tail_length:
			continue
		var t := into_tail / maxf(tail_length, 0.001)
		var spread: float = half.y * lerp(0.35, 1.15, t)
		var notch: float = spread * plan.tail_fork * t
		for y in SIZE.y:
			var dy := absf(float(y) + 0.5 - center.y)
			if dy <= spread and dy >= notch:
				image.set_pixel(x, y, fin)

	# Dorsal fin: a low triangle riding the back.
	var dorsal: float = plan.dorsal_height * h
	if dorsal >= 1.0:
		for x in SIZE.x:
			var along := (float(x) + 0.5 - (center.x - half.x * 0.5)) / maxf(half.x, 0.001)
			if along < 0.0 or along > 1.2:
				continue
			var rise := dorsal * sin(clampf(along / 1.2, 0.0, 1.0) * PI)
			var top := center.y - half.y * 0.85 - rise
			for y in SIZE.y:
				var py := float(y) + 0.5
				if py >= top and py <= center.y - half.y * 0.5:
					image.set_pixel(x, y, fin)

	# Body, flat with a belly shadow.
	for y in SIZE.y:
		for x in SIZE.x:
			var point := Vector2(x + 0.5, y + 0.5)
			if _form.ellipse_depth(center, half, point) <= 0.0:
				continue
			image.set_pixel(x, y, belly if point.y > center.y + half.y * _BELLY_FRACTION else body)

	# Eye, proportionally placed toward the snout.
	var eye := Vector2i(int(center.x + half.x * 0.55), int(center.y - half.y * 0.22))
	if eye.x >= 0 and eye.x < SIZE.x and eye.y >= 0 and eye.y < SIZE.y:
		image.set_pixel(eye.x, eye.y, EYE_COLOR)
		if eye.x + 1 < SIZE.x:
			image.set_pixel(eye.x + 1, eye.y, EYE_COLOR)


## Where the belly shadow starts, as a fraction of the body's half-depth,
## and which ramp stops the belly and fins use.
const _BELLY_FRACTION := 0.18
const _BELLY_STOP := 0.25
const _FIN_STOP := 0.42


## Rings the assembled silhouette so the fish separates from the water.
func _outline_silhouette(image: Image) -> void:
	var outline := _palette.outline_color()
	var to_outline: Array[Vector2i] = []
	var offsets := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for y in SIZE.y:
		for x in SIZE.x:
			if image.get_pixel(x, y).a > 0.0:
				continue
			for offset in offsets:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if nx < 0 or nx >= SIZE.x or ny < 0 or ny >= SIZE.y:
					continue
				if image.get_pixel(nx, ny).a > 0.0:
					to_outline.append(Vector2i(x, y))
					break
	for cell in to_outline:
		image.set_pixel(cell.x, cell.y, outline)


## A handful of deterministic dark speckle dots scattered across body-colored
## pixels ('b'/'h'/'s') -- same idea as
## ProceduralAnimalSprite._paint_body_spots.
func _paint_speckles(image: Image, seed_value: int, key: String) -> void:
	var body_cells := _body_cells(image)
	if body_cells.is_empty():
		return
	for i in SPECKLE_COUNT:
		var spot_seed := absi(hash("%d_%s_speckle_%d" % [seed_value, key, i]))
		var cell: Vector2i = body_cells[spot_seed % body_cells.size()]
		image.set_pixel(cell.x, cell.y, EYE_COLOR.lightened(0.1))


## Deterministic alternating white/black patches over body-colored pixels --
## koi's signature look, distinguishing it from a plain-colored fish.
func _paint_patches(image: Image, seed_value: int, key: String) -> void:
	var body_cells := _body_cells(image)
	if body_cells.is_empty():
		return
	for i in PATCH_COUNT:
		var patch_seed := absi(hash("%d_%s_patch_%d" % [seed_value, key, i]))
		var cell: Vector2i = body_cells[patch_seed % body_cells.size()]
		var patch_color: Color = PATCH_COLORS[i % PATCH_COLORS.size()]
		image.set_pixel(cell.x, cell.y, patch_color)


## Every painted body pixel of the ASSEMBLED fish -- markings go on
## whatever anatomy was built, rather than on a retired source bitmap.
func _body_cells(image: Image) -> Array[Vector2i]:
	var outline := _palette.outline_color()
	var cells: Array[Vector2i] = []
	for y in SIZE.y:
		for x in SIZE.x:
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0 and pixel != outline and pixel != EYE_COLOR:
				cells.append(Vector2i(x, y))
	return cells


func _seeded_unit_float(seed_value: int, salt: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, salt])) % 10000) / 10000.0
