extends RefCounted

## Deterministic offline pixel-art for a single flower in bloom (see
## docs/concept/flora.md). A thin stem, a couple of leaves, and a petal head
## in the species' own colour -- flat 16-bit fills with one shade side, the
## same convention as the other procedural generators.
##
## `seed_value` (hashed from the flower's cell) varies stem lean, height and
## petal count, so a meadow of one species still isn't a row of clones.

const FlowerSpecies = preload("res://src/world/flower_species.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const IllustratedFlowerHead = preload("res://src/rendering/illustrated_flower_head.gd")

## The ART canvas. Kept independent of the world size below on purpose: this
## project has twice shipped sprites that changed size on screen because a
## world scale was derived from canvas dimensions, so raising this for more
## detail must never change how big a flower looks.
const SIZE := Vector2i(32, 32)

## ## How big a flower is
##
## Measured against the PLAYER, who is the yardstick everything else in this
## world is read against. Flowers used to be sized against grass alone, which
## let a tulip reach 72% of the player's height and stand chest-high on the
## hero ("the current scales are a bit too big ... flowers should not be
## almost as tall as a player"). Grass is a poor yardstick because grass is
## itself waist-high in places.
##
## The character's own height comes from the same rule CharacterView uses --
## two thirds of a full-grown tree -- rather than a second copy of the number.
## Pinned against CharacterView by
## test_the_player_height_flowers_are_measured_against_is_the_real_one, so the
## two cannot drift apart.
const PLAYER_HEIGHT_FRACTION_OF_TREE := 2.0 / 3.0
const PLAYER_WORLD_HEIGHT_PX := (
	PLAYER_HEIGHT_FRACTION_OF_TREE * float(ProceduralTreeSprite.WORLD_SIZE.y)
)

## ## Where the curve is pinned
##
## Two stated reference points, rather than a shape chosen by eye: a tulip
## comes up to the player's HIP, and a sunflower stands as tall as the player.
## Everything else follows from its real height in centimetres.
##
## Deliberately a little taller than life. At true scale a tulip reaches a
## quarter of a person and a crocus about a sixteenth -- correct, and dull:
## flowers you can barely see are not worth walking through. These are plants
## as they feel rather than as they measure.
const HIP_HEIGHT_ANCHOR_CM := 40.0
const HIP_FRACTION_OF_PLAYER := 0.52
const PLAYER_HEIGHT_ANCHOR_CM := 200.0

## No species renders below this, however short the real plant is.
const MINIMUM_READABLE_HEIGHT_PX := 1.5

## How much one plant's size may differ from its species' own.
##
## A bed where every bloom is pixel-identical reads as stamped-out copies
## rather than as things that grew. Kept to a nudge: a runt and a giant of the
## same species must still read as that species.
const PLANT_SIZE_VARIANCE := 0.22

## ## Bushes
##
## Lavender does not grow as a single stem -- it is a bush of many spikes, and
## one lone spike per plant made a lavender bed read as scattered twigs.
## FlowerSpecies.stems_for says how many a species puts up; these say how they
## are arranged.
##
## Spacing is in art pixels, and stays small enough that the spikes of one
## bush overlap into a single mass rather than reading as separate plants.
const BUSH_STEM_SPACING_PX := 3.0

## How much a spike's sideways position may vary, as a fraction of its
## spacing, so the spikes are not evenly ruled.
const BUSH_SPREAD_JITTER := 0.35

## The shortest an outer spike may be, as a fraction of the bush's height. The
## centre spike is always full height, so a bush has a crown rather than a
## flat top.
const BUSH_OUTER_HEIGHT := 0.55

## Offsets each spike's seed so the spikes of one bush lean and flower
## differently instead of being the same sprite drawn several times.
const BUSH_STEM_SEED_STRIDE := 7919

const TILE_SIZE := 16.0

## How dark the deepest shading in an illustrated head is allowed to go.
## Without a floor the sheet's own linework multiplies down to near-black,
## which at this size reads as a hole punched in the flower rather than as
## shading.
const ILLUSTRATED_SHADE_FLOOR := 0.35

## Floor under a sheet's peak brightness when normalising its shading. Guards
## the division: a sheet drawn wholly in shadow would otherwise be stretched
## into a blown-out blob rather than staying dark, which is the honest result.
const MINIMUM_PEAK_LUMINANCE := 0.35

## ## The accent mask
##
## A flower's centre is not its petals. The recolour discards the sheet's hue
## entirely -- which is what fixed blooms rendering as green cages -- but it
## discarded the yellow eye along with it, so an illustrated daisy came out
## uniformly grey where it should have a gold centre. The eye is not a shading
## artifact; it is part of the flower drawn in another colour on purpose.
##
## The mask is DERIVED from the sheet rather than hand-painted, so a new sheet
## needs no companion art. The dominant hue is the petal mass; a saturated
## minority sitting far from it in hue is an accent, and keeps its own colour.
##
## Which hue is "petal" cannot be derived from the sheet -- the cup sheet's
## PETALS sit at 30 degrees, exactly where the daisy sheet's EYE sits, so a
## "biggest cluster wins" rule gets one of the two backwards. Each sheet
## declares its own petal hue instead (IllustratedFlowerHead._SHEET_PETAL_HUE);
## this is how far from that a pixel must be to count as something else.
##
## Chosen against the measurements there: the widest gap that still has to
## read as PETAL is the cup sheet's own 30 degrees, and the narrowest that has
## to read as ACCENT is the daisy eye's 45. Thirty-five sits between them.
## Below 30 the cup sheet starts escaping the recolour, which is the green
## cage coming back; above 45 the daisy loses its eye again.
const ACCENT_HUE_DISTANCE := 35.0

## Below this saturation a pixel has no meaningful hue to compare -- white and
## grey sit at an arbitrary point on the wheel -- so it is petal by default.
const ACCENT_MIN_SATURATION := 0.25

## An accent is a flower's CENTRE, and a flower's centre is gold.
##
## Being far from the petals in hue is not enough on its own: these sheets
## also draw green sepals at the base of the head, which are equally far from
## the petals and would be preserved by a distance rule alone. On a bloom a
## few pixels tall a preserved sepal does not read as botanical detail, it
## reads as a green flower -- which is the exact complaint that started all of
## this ("green petals are hard to see on green grass"). Measured, the sepals
## sit at 75 degrees and every eye and stamen between 30 and 60, so the window
## closes before the green starts.
const ACCENT_HUE_MIN := 20.0
const ACCENT_HUE_MAX := 70.0

const STEM_COLOR := Color(0.24, 0.45, 0.16)
const SHADE := 0.28
const HIGHLIGHT := 0.26


## How big a flower is at a given growth, 0 (just seeded) to 1 (mature).
##
## A newly-seeded flower is a SEEDLING rather than a full bloom that happens
## to be new -- a meadow filling in is something the player should be able to
## watch. Floored well above zero so a seedling still reads as a plant rather
## than as bare ground.
const SEEDLING_SCALE := 0.3


static func growth_scale(growth: float) -> float:
	return lerpf(SEEDLING_SCALE, 1.0, clampf(growth, 0.0, 1.0))


## The scale that renders this species at its intended world size regardless
## of the art canvas's pixel resolution.
## How much real heights are compressed toward each other, COMPUTED from the
## two anchors above rather than typed in.
##
## An exponent below 1 lifts the small species toward visibility while
## preserving the ordering (pinned by
## test_shrinking_never_reorders_the_species): a lavender still reads as
## clearly taller than a crocus, it is simply not five times taller as it
## would be in life.
static func size_exaggeration() -> float:
	return log(HIP_FRACTION_OF_PLAYER) / log(HIP_HEIGHT_ANCHOR_CM / PLAYER_HEIGHT_ANCHOR_CM)


## How tall this species stands in the world, in pixels.
##
## Anchored to real centimetres, NOT to whichever species happens to be
## tallest. Sizing everything relative to the tallest meant adding one tall
## species silently shrank every other flower in the world; now a new entry
## only decides its own size.
static func world_height_px(species_id: String) -> float:
	var ratio := FlowerSpecies.height_cm_for(species_id) / PLAYER_HEIGHT_ANCHOR_CM
	return maxf(
		PLAYER_WORLD_HEIGHT_PX * pow(ratio, size_exaggeration()),
		MINIMUM_READABLE_HEIGHT_PX
	)


## The species' own size, with no individual variation. Callers drawing an
## actual plant want plant_scale_for instead.
static func world_scale_for(species_id: String) -> float:
	return world_height_px(species_id) / float(SIZE.y)


## How much larger or smaller THIS plant is than its species' norm. Derived
## from the plant's own seed, so it is fixed for that plant's life -- a flower
## does not breathe in and out as you watch it.
static func size_variance_for(seed_value: int) -> float:
	var roll := float(PixelNoise.range_index(seed_value, 7, 0, 101)) / 100.0
	return 1.0 + (roll * 2.0 - 1.0) * PLANT_SIZE_VARIANCE


## The world scale for ONE plant: its species' size, nudged by its own
## variance.
static func plant_scale_for(species_id: String, seed_value: int) -> float:
	return world_scale_for(species_id) * size_variance_for(seed_value)


## How tall this flower's stem is, in art pixels. Shared with the painter so
## the two can never drift: the blossom's world height is derived from this,
## and a pollinator lands ON the blossom rather than at the stem's foot.
static func stem_height_px(seed_value: int) -> int:
	return SIZE.y / 2 + PixelNoise.range_index(seed_value, 2, 0, SIZE.y / 4)


## How far above the flower's own world position (which is the stem's FOOT,
## since the sprite is foot-anchored for Y-sorting) the blossom sits, in
## world units, for a plant actually rendered at `plant_scale` -- the SAME
## per-plant scale (species size, this plant's own variance, and how far it
## has grown -- see plant_scale_for/growth_scale) the sprite itself is drawn
## at, not just the species' nominal size.
##
## Landing at the flower's position alone put insects at the base of the
## stem instead of on the bloom. Scaling by the species alone was a smaller
## version of the same mistake: a below-average or still-growing plant's
## sprite is smaller than its species' norm, but its landing point did not
## shrink with it, which reads as landing near the stem rather than on the
## bloom -- worst on a species whose scale is large to begin with, where even
## a modest mismatch is a lot of world pixels (reported on the sunflower:
## "butterflies drink from their stem").
static func blossom_height_world(seed_value: int, plant_scale: float) -> float:
	return float(stem_height_px(seed_value)) * plant_scale


## How much an illustrated head's canvas must shrink, 0..1, to fit
## `headroom_px` rows -- the space actually available above the stem's own
## attachment point (see stem_height_px) -- given the head's nominal size is
## `head_canvas_px`. 1.0 means it already fits as drawn.
##
## See _paint_illustrated_head for why the whole head shrinks instead of
## letting whatever doesn't fit get clipped by the canvas edge.
static func head_fit_scale(headroom_px: int, head_canvas_px: int) -> float:
	if head_canvas_px <= 0:
		return 1.0
	return clampf(float(headroom_px) / float(head_canvas_px), 0.0, 1.0)


func generate_texture(
	species_id: String, seed_value: int, nectar: float = 1.0, withered: bool = false
) -> ImageTexture:
	return ImageTexture.create_from_image(
		generate_image(species_id, seed_value, nectar, withered)
	)


## Which species the current paint pass is for, so the head painter can pick
## its shape. Set at the top of generate_image rather than threaded through
## every helper, matching how the terrain painter dispatches on biome.
var _head_species := ""
## Set alongside _head_species -- see generate_image. Only consulted for an
## archetype with illustrated art (see _paint_head); procedural heads ignore
## it entirely, unaffected by nectar.
var _head_nectar := 1.0
## Whether this flower has gone over for the year (see FlowerBloom).
var _head_withered := false

var _illustrated_heads := IllustratedFlowerHead.new()

## Below this remaining nectar (see FlowerPatch.nectar_at), an illustrated
## head switches from its "full bloom" frame to its "spent" one -- a fresh
## bloom (nectar 1.0, FlowerPatch.plant's own default) always reads as full;
## a bloom foraged down near empty reads visibly spent. Picked low enough
## that an ordinarily-still-worth-visiting bloom (well above pollinator_
## foraging.gd's own forageable floor) still reads full, not wilted.
const SPENT_NECTAR_THRESHOLD := 0.15


## How far each stem of a bush sits from the plant's centre, and how much
## shorter or taller it is than the plant's own height.
##
## `x` is a horizontal offset in art pixels; `y` is a height MULTIPLIER, so a
## spike at 0.8 stands four fifths as tall as the bush's nominal height. The
## first entry is always the centre spike at full height, so a bush reads as
## one plant with a crown rather than as a row.
static func bush_offsets(species_id: String, seed_value: int) -> Array[Vector2]:
	var stems := FlowerSpecies.stems_for(species_id)
	var offsets: Array[Vector2] = [Vector2(0.0, 1.0)]
	for index in range(1, stems):
		# Alternating sides, stepping outward, so a bush is balanced rather
		# than leaning; each spike's spread and height come from the plant's
		# own seed, so no two bushes are arranged alike.
		var side := 1.0 if index % 2 == 1 else -1.0
		var rank := float((index + 1) / 2)
		var spread := float(PixelNoise.range_index(seed_value, 20 + index, 0, 100)) / 100.0
		var x := side * rank * BUSH_STEM_SPACING_PX * (1.0 - BUSH_SPREAD_JITTER + spread * BUSH_SPREAD_JITTER * 2.0)
		var height_roll := float(PixelNoise.range_index(seed_value, 40 + index, 0, 100)) / 100.0
		var height := BUSH_OUTER_HEIGHT + height_roll * (1.0 - BUSH_OUTER_HEIGHT)
		offsets.append(Vector2(x, height))
	return offsets


## `withered` is the flower at the END OF ITS SEASON (see FlowerBloom), which
## is what the spent look means. It used to be derived from `nectar`, so a
## bloom a bee had just emptied read as dead -- and a nectary refills in about
## a minute. Two different things were wearing one sprite.
##
## `nectar` is kept in the signature: it is still the plant's contents, still
## what a pollinator drinks, and a future pass may well want a full flower to
## look plumper than an empty one. It simply does not decide WILTED.
func generate_image(
	species_id: String, seed_value: int, nectar: float = 1.0, withered: bool = false
) -> Image:
	_head_species = species_id
	_head_nectar = nectar
	_head_withered = withered
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	# This PLANT's colour, not the species' canonical one: a bed of crocuses
	# comes up mixed (see FlowerSpecies "On variety"), and the seed keeps each
	# individual the same colour for life.
	var petal := FlowerSpecies.tint_for(species_id, seed_value)

	var base_x := SIZE.x / 2
	var stem_height := stem_height_px(seed_value)
	# A bush puts up several spikes (lavender, clover); everything else is a
	# single stem, which is bush_offsets' one-entry case.
	for index in bush_offsets(species_id, seed_value).size():
		var offset: Vector2 = bush_offsets(species_id, seed_value)[index]
		_paint_stem_and_head(
			image,
			base_x + int(round(offset.x)),
			int(round(float(stem_height) * offset.y)),
			petal,
			# Each spike leans and is seeded slightly differently, so the
			# spikes of one bush are not the same sprite drawn several times.
			seed_value + index * BUSH_STEM_SEED_STRIDE,
			index == 0
		)
	# Overlapping spikes leave single-pixel gaps inside the bloom mass, which
	# read as holes punched in the flower rather than as anything botanical.
	# Same rule as the illustrated heads (see _filled_head): anything the
	# outside cannot reach is inside the plant. Gaps BETWEEN spikes are
	# reachable from the edge and are left alone -- you should see grass
	# between the spikes of a lavender bush.
	_fill_enclosed_gaps(image)
	return image


## Paints one stem with its head on top. A single-stemmed flower calls this
## once; a bush calls it once per spike.
func _paint_stem_and_head(
	image: Image, base_x: int, stem_height: int, petal: Color, seed_value: int, with_leaves: bool
) -> void:
	# Stem: rises from the bottom edge, leaning slightly so a bed of flowers
	# doesn't read as a picket fence.
	var lean: int = PixelNoise.range_index(seed_value, 1, 0, 5) - 2
	var head_x := base_x
	var head_y := SIZE.y - stem_height
	for step in stem_height:
		var y := SIZE.y - 1 - step
		var x: int = base_x + int(round(float(lean) * float(step) / float(maxi(stem_height, 1))))
		x = clampi(x, 1, SIZE.x - 2)
		image.set_pixel(x, y, STEM_COLOR)
		# A second column low down so the stem doesn't vanish at small scale.
		if step < stem_height / 2:
			image.set_pixel(clampi(x + 1, 0, SIZE.x - 1), y, STEM_COLOR.darkened(SHADE))
		head_x = x

	# Leaves belong to the plant, not to each spike: a bush with a full set of
	# leaves per stem is a thicket.
	if with_leaves:
		_paint_leaves(image, base_x, stem_height, seed_value)
	_paint_head(image, head_x, head_y, petal, seed_value)


## Two small leaves partway up the stem, on alternating sides.
func _paint_leaves(image: Image, base_x: int, stem_height: int, seed_value: int) -> void:
	var leaf_color := STEM_COLOR.lightened(0.12)
	for i in 2:
		var at: int = SIZE.y - 1 - int(float(stem_height) * (0.35 + 0.25 * float(i)))
		var direction: int = 1 if i % 2 == 0 else -1
		var span: int = 2 + PixelNoise.range_index(seed_value, 30 + i, 0, 3)
		for k in span:
			var x := clampi(base_x + direction * (k + 1), 0, SIZE.x - 1)
			var y := clampi(at + k / 2, 0, SIZE.y - 1)
			image.set_pixel(x, y, leaf_color)


## The bloom itself: a small ring of petals around a lighter centre. Drawn as
## discrete petals rather than a filled disc so it reads as a flower head at
## pixel scale instead of a berry.
## Pollen-warm core, so a bloom has a focal point that reads from a distance
## even when the petals are dark.
const CENTRE_COLOR := Color(0.97, 0.84, 0.36)

## Each species' head is its own SHAPE, not one shape recoloured.
##
## The bloom used to be petal_count single-pixel RAYS from a 3x3 centre --
## about 58 painted pixels, which reads as an asterisk, and left every species
## sharing one silhouette with only its hue to tell it apart (measured: all
## five species produced an identical alpha mask). Real petals have area, and
## a lavender spike genuinely does not look like a tulip cup.
const HEAD_SHAPE_BY_SPECIES := {
	"crocus": "cup",
	"tulip": "cup",
	"rose": "layered",
	"lavender": "spike",
	"clover": "puff",
}
## The shape family anything unmapped falls back to: petals radiating from a
## centre.
##
## This was called "daisy", which was a category error -- a daisy is a
## SPECIES, and naming a shape family after one of its members meant the
## species could never have art of its own without colliding with the
## fallback everything else uses. Named for the shape now, as cup/layered/
## spike/puff already are.
const _FALLBACK_HEAD_SHAPE := "radial"


func _paint_head(image: Image, cx: int, cy: int, petal: Color, seed_value: int) -> void:
	var archetype: String = HEAD_SHAPE_BY_SPECIES.get(_head_species, _FALLBACK_HEAD_SHAPE)
	# Asked per SPECIES, not per archetype: a species can have its own sheet
	# while its archetype has none (spike and puff have no art today), and
	# gating on the archetype alone would ignore that species' art.
	if _illustrated_heads.has_art_for(_head_species, archetype):
		_paint_illustrated_head(image, cx, cy, petal, archetype)
		return
	match archetype:
		"cup":
			_paint_cup_head(image, cx, cy, petal, seed_value)
		"layered":
			_paint_layered_head(image, cx, cy, petal, seed_value)
		"spike":
			_paint_spike_head(image, cx, cy, petal, seed_value)
		"puff":
			_paint_puff_head(image, cx, cy, petal, seed_value)
		_:
			_paint_radial_head(image, cx, cy, petal, seed_value)


## Composites an AI-illustrated head (see IllustratedFlowerHead) onto the
## procedural stem/leaves, in place of the shape-specific procedural
## painters above. Bottom-center anchored at (cx, cy) -- the same point the
## procedural painters treat as the cup's mouth/the head's base -- and
## recoloured to `petal` by taking the source's SHADING ONLY and none of its
## hue.
##
## This was a plain multiply, which relies on the source art being pale and
## neutral. The cup sheet is not -- it carries real green in its sepals and
## outlines -- and multiply preserves hue, so crocus and tulip came out as
## green cages: invisible against grass, and not a colour petals come in.
##
## Reading the source as luminance and painting `petal` at that brightness
## keeps every bit of the illustration's form and shading while discarding
## whatever hue it happened to be drawn in, so the recolour is robust to the
## art rather than depending on a promise about it. The floor stops the
## darkest linework going black, which at this size reads as a hole.
func _paint_illustrated_head(image: Image, cx: int, cy: int, petal: Color, archetype: String) -> void:
	# Species art wins over the archetype's shared sheet (see
	# IllustratedFlowerHead.sheet_path_for).
	var frames := _illustrated_heads.frames_for_species(_head_species, archetype)
	var stage := (
		IllustratedFlowerHead.STAGE_SPENT
		if _head_withered
		else IllustratedFlowerHead.STAGE_FULL_BLOOM
	)
	var head_image: Image = _filled_head(frames[stage].get_image())
	var canvas := IllustratedFlowerHead.HEAD_CANVAS_SIZE
	# The stem leaves only `cy` rows of headroom above its own attachment
	# point (see stem_height_px), which is LESS than the head's nominal
	# canvas height for every roll this project currently draws -- composited
	# at full size, the crown was sliced off flat by the canvas edge instead
	# of drawn smaller. Invisible on the small species this shipped with;
	# glaring on the sunflower, whose much larger world scale turned that
	# always-present few-pixel clip into an obvious flat top (reported, with
	# a screenshot: "the sunflower sprite is clipped at the top"). Shrinking
	# the whole head to fit -- the same trick normalize_frames already uses
	# one layer up, to fit a drawing to ITS canvas -- keeps every stage's
	# full silhouette, just smaller on a short-stemmed plant, instead of
	# cutting its crown off.
	var fit_scale := head_fit_scale(cy, canvas.y)
	if fit_scale < 1.0:
		canvas = Vector2i(
			maxi(1, int(round(float(canvas.x) * fit_scale))),
			maxi(1, int(round(float(canvas.y) * fit_scale)))
		)
		head_image.resize(canvas.x, canvas.y, Image.INTERPOLATE_LANCZOS)
	# What counts as "fully lit" in THIS sheet. Without it the recolour tops
	# out at however bright the artist happened to draw the highlight, so
	# every variety came out darker than its own colour -- which a saturated
	# red survives and a white or pale yellow does not, washing the pale
	# varieties into grey. Normalising here means a white tulip is actually
	# white, whatever the sheet's exposure. Measured AFTER any fit-shrink
	# above, so it normalises against what is actually about to be painted.
	# Where this sheet's petals sit on the hue wheel (see "The accent mask").
	# -1 means the sheet declares no mask, and everything is petal.
	var petal_hue := IllustratedFlowerHead.petal_hue_for(_head_species, archetype) / 360.0
	var peak := _peak_luminance(head_image, petal_hue)
	var dest_x := cx - canvas.x / 2
	var dest_y := cy - canvas.y
	for y in canvas.y:
		var image_y := dest_y + y
		if image_y < 0 or image_y >= SIZE.y:
			continue
		for x in canvas.x:
			var source := head_image.get_pixel(x, y)
			if source.a < 0.05:
				continue
			var image_x := dest_x + x
			if image_x < 0 or image_x >= SIZE.x:
				continue
			# Rec. 709 luminance: the source's light and shade, none of its
			# colour.
			var shade := _luminance(source) / peak
			var lit := ILLUSTRATED_SHADE_FLOOR + (1.0 - ILLUSTRATED_SHADE_FLOOR) * shade
			if petal_hue >= 0.0 and _is_accent(source, petal_hue):
				# Drawn in another colour on purpose -- a stamen or an eye.
				# Keeps its own hue, but takes the same normalised shading, so
				# it sits in the same light as the petals around it.
				image.set_pixel(
					image_x, image_y,
					Color(source.r * lit, source.g * lit, source.b * lit, source.a)
				)
				continue
			image.set_pixel(
				image_x, image_y,
				Color(petal.r * lit, petal.g * lit, petal.b * lit, source.a)
			)


## Whether this pixel is drawn in a colour that is deliberately not the
## petals' -- an eye or a stamen, which keeps its own hue.
func _is_accent(source: Color, petal_hue: float) -> bool:
	if source.s < ACCENT_MIN_SATURATION:
		return false
	if _hue_gap_degrees(source.h, petal_hue) <= ACCENT_HUE_DISTANCE:
		return false
	var degrees := source.h * 360.0
	return degrees >= ACCENT_HUE_MIN and degrees <= ACCENT_HUE_MAX


## Hue is circular: 350 degrees and 10 degrees are 20 apart, not 340.
func _hue_gap_degrees(hue_a: float, hue_b: float) -> float:
	var gap: float = absf(hue_a - hue_b) * 360.0
	return minf(gap, 360.0 - gap)


## Fills transparent pixels the outside cannot reach.
##
## A hole enclosed by petal on every side is a rasterisation artifact, not a
## gap: it shows the background through the middle of a bloom. Gaps that
## connect to the edge of the canvas are real gaps -- the space between the
## spikes of a bush -- and are left alone.
func _fill_enclosed_gaps(image: Image) -> void:
	var outside := {}
	var queue: Array[Vector2i] = []
	for x in image.get_width():
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, image.get_height() - 1))
	for y in image.get_height():
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(image.get_width() - 1, y))
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		if at.x < 0 or at.x >= image.get_width() or at.y < 0 or at.y >= image.get_height():
			continue
		if outside.has(at) or image.get_pixel(at.x, at.y).a >= 0.05:
			continue
		outside[at] = true
		queue.append(at + Vector2i(1, 0))
		queue.append(at + Vector2i(-1, 0))
		queue.append(at + Vector2i(0, 1))
		queue.append(at + Vector2i(0, -1))
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.05 or outside.has(Vector2i(x, y)):
				continue
			# Take a neighbour's colour, so the patch sits in the same light
			# as what encloses it rather than being a flat spot.
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + step.x
				var ny: int = y + step.y
				if nx < 0 or nx >= image.get_width() or ny < 0 or ny >= image.get_height():
					continue
				var neighbour := image.get_pixel(nx, ny)
				if neighbour.a >= 0.05:
					image.set_pixel(x, y, neighbour)
					break


## Rec. 709 luminance: a pixel's light and shade, none of its colour.
func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


## The brightest PETAL in a head, used as "fully lit" when recolouring.
##
## Petals only: on the rose sheet the brightest pixel in the head is a gold
## stamen, and measuring the peak against that left every petal short of its
## own colour -- a white rose came out grey. The question this answers is
## "how bright does this sheet draw a lit petal", so accents must not vote.
##
## Clamped to a sane minimum so a sheet drawn entirely in shadow cannot divide
## the shading up into a blown-out white blob.
func _peak_luminance(head_image: Image, petal_hue: float) -> float:
	var peak := 0.0
	for y in head_image.get_height():
		for x in head_image.get_width():
			var pixel := head_image.get_pixel(x, y)
			if pixel.a < 0.05:
				continue
			if petal_hue >= 0.0 and _is_accent(pixel, petal_hue):
				continue
			peak = maxf(peak, _luminance(pixel))
	return maxf(peak, MINIMUM_PEAK_LUMINANCE)


## Fills the enclosed interiors of an illustrated head, so the bloom is solid.
##
## The cup sheet is line art: petals drawn as outlines with nothing inside
## them. Composited as-is, the grass showed straight through every petal, so a
## flower read as a green wireframe cage even once the outlines themselves
## were correctly coloured (reported twice -- "green petals ... on green
## grass", then "the bloom is correctly colored but the petals are still
## green"). Petals are not windows.
##
## Anything transparent that cannot be reached from the canvas edge is INSIDE
## the drawing, so it gets filled. The flood starts at the border and marks
## what is genuinely outside; everything else is interior by definition. That
## works for any line-art sheet rather than for this one specifically.
func _filled_head(source: Image) -> Image:
	var width := source.get_width()
	var height := source.get_height()
	var filled := Image.create(width, height, false, Image.FORMAT_RGBA8)
	filled.copy_from(source)

	var outside := {}
	var queue: Array[Vector2i] = []
	for x in width:
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, height - 1))
	for y in height:
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(width - 1, y))

	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		if at.x < 0 or at.x >= width or at.y < 0 or at.y >= height:
			continue
		if outside.has(at):
			continue
		if source.get_pixel(at.x, at.y).a >= 0.05:
			continue  # part of the drawing: the flood stops at the outline
		outside[at] = true
		queue.append(at + Vector2i(1, 0))
		queue.append(at + Vector2i(-1, 0))
		queue.append(at + Vector2i(0, 1))
		queue.append(at + Vector2i(0, -1))

	# Interior holes take the mid-tone of the art around them, so the fill
	# reads as the petal's own surface rather than as a flat sticker behind
	# the linework.
	for y in height:
		for x in width:
			if source.get_pixel(x, y).a >= 0.05:
				continue
			if outside.has(Vector2i(x, y)):
				continue
			filled.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
	return filled


## A filled disc -- the building block every head shape is made of, so petals
## have area rather than being lines.
func _fill_disc(image: Image, cx: int, cy: int, radius: float, color: Color) -> void:
	var r := int(ceil(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if float(dx * dx + dy * dy) > radius * radius:
				continue
			var x := cx + dx
			var y := cy + dy
			if x < 1 or x >= SIZE.x - 1 or y < 0 or y >= SIZE.y:
				continue
			# Lit from the top-left, shaded to the lower-right -- the shared
			# convention across this project's art.
			image.set_pixel(x, y, color.darkened(SHADE) if dx + dy > int(radius) else color)


## Petals radiating as LOBES around a pollen centre -- the "radial" family.
func _paint_radial_head(image: Image, cx: int, cy: int, petal: Color, seed_value: int) -> void:
	var petal_count: int = 5 + PixelNoise.range_index(seed_value, 7, 0, 3)
	var reach: float = 4.0 + float(PixelNoise.range_index(seed_value, 8, 0, 2))
	for i in petal_count:
		var angle := TAU * float(i) / float(petal_count)
		_fill_disc(
			image,
			cx + int(round(cos(angle) * reach)),
			cy + int(round(sin(angle) * reach)),
			2.2,
			petal
		)
	_fill_disc(image, cx, cy, 2.4, CENTRE_COLOR)


## A closed cup opening upward: tulips and crocuses hold their petals in.
func _paint_cup_head(image: Image, cx: int, cy: int, petal: Color, seed_value: int) -> void:
	# A crocus is a low, tight cup and a tulip a taller, fuller one -- true to
	# life, and what stops the two species sharing a silhouette just because
	# they share a shape family.
	var tight := _head_species == "crocus"
	var height: int = (4 if tight else 7) + PixelNoise.range_index(seed_value, 11, 0, 2)
	var half: int = (2 if tight else 4) + PixelNoise.range_index(seed_value, 12, 0, 2)
	for step in height:
		# Widens toward the mouth of the cup.
		var t := float(step) / float(maxi(1, height - 1))
		var width := int(round(float(half) * (0.55 + 0.45 * t)))
		var y := cy - step
		for dx in range(-width, width + 1):
			var x := cx + dx
			if x < 1 or x >= SIZE.x - 1 or y < 0 or y >= SIZE.y:
				continue
			image.set_pixel(x, y, petal.darkened(SHADE) if dx > width - 2 else petal)
	# Three petal tips breaking the rim, so the mouth is not a flat line.
	for tip in [-half, 0, half]:
		_fill_disc(image, cx + tip, cy - height, 1.6, petal.lightened(HIGHLIGHT * 0.5))
	_fill_disc(image, cx, cy - maxi(2, height / 2), 2.2, CENTRE_COLOR)


## Concentric rings of petals -- a rose is petals all the way in.
func _paint_layered_head(image: Image, cx: int, cy: int, petal: Color, seed_value: int) -> void:
	var rings: int = 3 + PixelNoise.range_index(seed_value, 13, 0, 2)
	for ring in range(rings, 0, -1):
		var radius := 1.7 * float(ring)
		var tone := petal.darkened(SHADE) if ring % 2 == 1 else petal.lightened(HIGHLIGHT * 0.4)
		_fill_disc(image, cx, cy - ring / 2, radius, tone)
	_fill_disc(image, cx, cy - 1, 1.6, CENTRE_COLOR.darkened(0.25))


## A vertical spike of small florets -- lavender advertises by scent from a
## tall, narrow head rather than by a broad face.
func _paint_spike_head(image: Image, cx: int, cy: int, petal: Color, seed_value: int) -> void:
	var florets: int = 7 + PixelNoise.range_index(seed_value, 14, 0, 3)
	for i in florets:
		var y := cy - i
		# Tapers toward the tip, and alternates side to side so the spike
		# reads as many small flowers rather than one thick stroke.
		var lean := 1 if i % 2 == 0 else -1
		var radius := 2.0 * (1.0 - float(i) / float(florets + 2))
		_fill_disc(image, cx + lean, y, maxf(0.9, radius), petal)
	_fill_disc(image, cx, cy - 1, 1.3, petal.lightened(HIGHLIGHT))


## A dense round cluster of tiny florets, the way clover heads actually grow.
func _paint_puff_head(image: Image, cx: int, cy: int, petal: Color, seed_value: int) -> void:
	var radius := 4.0 + float(PixelNoise.range_index(seed_value, 15, 0, 2))
	_fill_disc(image, cx, cy - 2, radius, petal)
	# Speckled with lighter florets so the puff has texture rather than
	# reading as a plain ball.
	var florets: int = 10 + PixelNoise.range_index(seed_value, 16, 0, 5)
	for i in florets:
		var angle := TAU * float(PixelNoise.range_index(seed_value + i, 17, 0, 360)) / 360.0
		var spread := radius * (
			0.25 + 0.6 * float(PixelNoise.range_index(seed_value + i, 18, 0, 100)) / 100.0
		)
		_fill_disc(
			image,
			cx + int(round(cos(angle) * spread)),
			cy - 2 + int(round(sin(angle) * spread)),
			1.0,
			petal.lightened(HIGHLIGHT * 0.7)
		)
	_fill_disc(image, cx, cy - 2, 1.5, CENTRE_COLOR.darkened(0.15))
