extends RefCounted

## The herbalist's crop, drawn (see docs/concept/village_farms.md, "A herb
## plot renders as bare tilled soil" -- an honest gap this closes).
##
## Reported in play with the field in shot: "it plows the soil but then the
## soil mound sprites don't appear and nothing gets planted, nothing grows
## and nothing gets harvested". Measured on a real village before anything
## was touched (tools/probe_village_farming.gd), all of it WAS happening --
## beds sown, crops grown to 29.5/57.2, beds withered, 8 real herbs banked
## into the village market -- and none of it was ever drawn:
## IllustratedCropSprite has sheets for carrot and potato only, so
## leaf_texture("herb", ...) returns null and FarmPlotMarker put a VISIBLE
## sprite with no texture over a full tile of bare soil.
##
## No illustrated herb art exists, so this is a hand-drawn procedural sprite
## in the same offline-art style as ProceduralSoilSprite and
## ProceduralLandmarkSprite -- swappable for real art later behind
## IllustratedCropSprite's own has_crop() seam with no marker change, the
## same optional-illustrated-art layering every other such seam in this
## codebase uses.
##
## A culinary herb, not a second wheat and not a leaf-blob: an upright
## central stem with paired leaves climbing it, side shoots appearing as it
## matures, and a flowering tip on the ripe plant -- which is what a bed of
## sage/thyme/marjoram actually looks like when it is ready to cut.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")
const IllustratedCropSprite = preload("res://src/rendering/illustrated_crop_sprite.gd")

## Seedling, vegetative, mature -- the same three stages
## IllustratedCropSprite.growth_stage_index already maps a growth fraction
## onto, so a herb bed and a carrot bed step through growth together rather
## than on two different ladders.
const STAGES := 3

## DETAIL_MULTIPLIER-scale canvas (see docs/concept/art_resolution.md),
## taller than wide because a herb is an upright plant. The world size below
## is what decides how big it actually reads; this is only how much pixel
## detail it is drawn with.
const SIZE := Vector2i(24, 32)

## The herb's own colour -- ProceduralLandmarkSprite's, not a second green.
## A herbalist's workspot prop (its `garden`) already established what a herb
## looks like in this world, and a bed in its own shade would be two plants
## for one crop. Pinned by
## test_a_herb_is_the_same_colour_the_herbalists_garden_prop_already_uses.
const HERB_COLOR := ProceduralLandmarkSprite.HERB_COLOR

## The woody stem a culinary herb's leaves sit on -- deliberately NOT the
## leaf colour, so the plant reads as a stem with leaves rather than a
## smear.
const STEM_COLOR := Color(0.33, 0.42, 0.24)

## The pale flowering tip a ripe herb carries, which is the real-world signal
## that a herb is ready to cut.
const FLOWER_COLOR := Color(0.86, 0.84, 0.62)

## How wide a herb reads ON THE GROUND, in world pixels. Not a fresh number:
## it is exactly IllustratedCropSprite.LEAF_WORLD_SIZE, the size a carrot's
## or potato's leaves already read at -- itself re-tuned once after "huge
## potato crops above soil" was reported live. A herb bed and a carrot bed
## standing at two different scales would be the same bug again.
const HERB_WORLD_WIDTH := IllustratedCropSprite.LEAF_WORLD_SIZE

var _palette := PixelPalette.new()
## stage -> Image, drawn once. Same "generate once, reuse everywhere"
## precedent ProceduralSoilSprite and the fill bands already set: every herb
## bed in the world draws the same three pictures.
static var _images: Dictionary = {}
static var _textures: Dictionary = {}


## The scale factor a marker applies to a SIZE-authored herb sprite so that
## it really reads at HERB_WORLD_WIDTH on screen.
static func world_scale() -> float:
	return HERB_WORLD_WIDTH / float(SIZE.x)


func generate_texture(stage_index: int) -> ImageTexture:
	var stage := clampi(stage_index, 0, STAGES - 1)
	if not _textures.has(stage):
		_textures[stage] = ImageTexture.create_from_image(generate_image(stage))
	return _textures[stage]


## `stage_index` out of range clamps to the nearest real stage rather than
## erroring -- the same contract IllustratedCropSprite.leaf_texture offers.
func generate_image(stage_index: int) -> Image:
	var stage := clampi(stage_index, 0, STAGES - 1)
	if not _images.has(stage):
		_images[stage] = _draw(stage)
	return _images[stage]


## One plant. Everything scales off `stage` so the three pictures are one
## plant at three ages rather than three drawings: a taller stem, more leaf
## pairs, wider leaves, and -- only on the ripe plant -- a flowering tip.
func _draw(stage: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var grown := float(stage + 1) / float(STAGES)
	var centre := SIZE.x / 2
	# The stem rises from the bottom row (the bed it is rooted in) to a
	# height set by its age, so a marker that pins the sprite by its root
	# never leaves the plant floating.
	var height := int(round(lerpf(SIZE.y * 0.34, SIZE.y - 2.0, grown)))
	var top := SIZE.y - height
	var stems := 1 if stage == 0 else (2 if stage == 1 else 3)
	for shoot in stems:
		# Side shoots lean out from the crown, the middle one upright --
		# alternating sides so the plant reads as a bush, not a fan.
		var lean := 0 if shoot == 0 else (1 if shoot % 2 == 1 else -1)
		var shoot_top := top + int(round(float(shoot) * height * 0.18))
		_draw_shoot(image, centre, shoot_top, lean, grown, stage)
	return image


## One stem with leaf pairs climbing it, leaning `lean` tiles' worth across
## its own height.
func _draw_shoot(image: Image, base_x: int, top_y: int, lean: int, grown: float, stage: int) -> void:
	var bottom := SIZE.y - 1
	var leaf_half := maxi(1, int(round(lerpf(1.0, SIZE.x * 0.28, grown))))
	var pairs := maxi(2, int(round(lerpf(2.0, 5.0, grown))))
	for y in range(top_y, bottom + 1):
		var t := float(bottom - y) / float(maxi(bottom - top_y, 1))
		var x := base_x + int(round(float(lean) * t * SIZE.x * 0.22))
		_pixel(image, x, y, STEM_COLOR)
		_pixel(image, x, y + 1, _palette.shade(STEM_COLOR))
	# Leaf pairs, evenly spaced up the stem, widest low down and tapering
	# toward the growing tip -- how an upright herb actually carries them.
	for pair in pairs:
		var t := float(pair + 1) / float(pairs + 1)
		var y := int(round(lerpf(float(bottom) - 1.0, float(top_y) + 1.0, t)))
		var stem_t := float(bottom - y) / float(maxi(bottom - top_y, 1))
		var x := base_x + int(round(float(lean) * stem_t * SIZE.x * 0.22))
		var width := maxi(1, int(round(float(leaf_half) * (1.0 - t * 0.55))))
		_draw_leaf(image, x, y, -1, width)
		_draw_leaf(image, x, y, 1, width)
	if stage == STAGES - 1:
		# A ripe herb has flowered -- the real signal that a bed is ready to
		# cut, and the one thing that cannot be mistaken for more foliage.
		for dx in range(-1, 2):
			_pixel(image, base_x + dx, top_y, FLOWER_COLOR)
		_pixel(image, base_x, top_y - 1, FLOWER_COLOR)


## One leaf: a stroke sweeping out from the stem and curving upward, two
## pixels thick at the base and tapering to one at the tip, shaded along its
## underside. A leaf drawn as a flat horizontal bar reads as a rung on a
## ladder rather than as foliage -- which is what the first pass of this
## sprite actually looked like when it was rendered out and looked at.
func _draw_leaf(image: Image, stem_x: int, stem_y: int, direction: int, length: int) -> void:
	for step in range(1, length + 1):
		var along := float(step) / float(length)
		# The lift is what makes it a leaf rather than a bar: a real leaf
		# leaves the stem near-level and lifts toward its tip.
		var y := stem_y - int(round(along * along * float(length) * 0.8))
		var x := stem_x + direction * step
		_pixel(image, x, y, HERB_COLOR)
		if along < 0.6:
			_pixel(image, x, y + 1, _palette.shade(HERB_COLOR))
		if along > 0.5:
			_pixel(image, x, y - 1, _palette.highlight(HERB_COLOR))


func _pixel(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= SIZE.x or y >= SIZE.y:
		return
	image.set_pixel(x, y, color)
