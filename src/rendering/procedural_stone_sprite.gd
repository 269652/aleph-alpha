extends RefCounted

## Deterministic offline pixel-art for boulders, matching the shaded/outlined
## technique ProceduralTreeSprite and the other procedural sprite generators
## use. The boulder is a squashed grey ellipse with a darker outline ring, a
## top-left highlight, a bottom shade band, and a few seeded darker crack/
## speckle pixels plus a seeded radius wobble so no two boulders are
## pixel-identical clones.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## DETAIL_MULTIPLIER times the world footprint (see
## docs/concept/art_resolution.md) -- drawn at ArtResolution.SPRITE_SCALE
## so it gains pixel detail without growing in the world.
const SIZE := Vector2i(32, 32)
const OUTLINE_DARKEN := 0.5
const SHADE_DARKEN := 0.25
const HIGHLIGHT_LIGHTEN := 0.2
const SPECKLE_COUNT := 6

const STONE_COLOR := Color(0.56, 0.56, 0.59)

## Surface grain (reported: "the stones look unnatural"): the base fill used
## to be one flat colour across the whole boulder body, which is exactly what
## read as unnatural -- a real rock surface has continuous per-pixel tonal
## variation from mineral grain and weathering, not a flat fill. Sampled from
## PixelNoise.fractal (smooth, not white-noise-harsh) rather than an actual
## illustrated material swatch -- this is the "semi-procedural" middle
## ground: code supplies the silhouette (unchanged below) AND, for now, the
## grain; a real AI-illustrated swatch can later replace just this sampling
## step without touching the silhouette code at all, since both would feed
## the same "base colour per pixel" seam (_grain_color).
##
## How far the per-pixel grain pushes brightness away from STONE_COLOR, each
## direction. Kept small: this is texture, not a second shading pass -- it
## must not compete with or wash out the existing outline/highlight/shade
## zones, which still carry the actual lighting.
const GRAIN_STRENGTH := 0.12

## How zoomed-in the grain noise is, in noise-space units per pixel. Lower
## values (finer/faster-changing) read as sandy speckle; higher values
## (slower-changing) read as broad mottled patches. Picked to show several
## distinct patches across one 32px boulder rather than either a single flat
## tint (too high) or salt-and-pepper static (too low) -- see
## test_boulder_surface_has_real_grain_not_a_flat_fill's tone-count floor.
const GRAIN_SCALE := 0.35

## Floor for how many distinct tones the plain base-fill zone alone must
## show -- the direct regression guard for "the stones look unnatural": a
## flat fill (the old behaviour) produces exactly 1. Measured well below
## what GRAIN_STRENGTH/GRAIN_SCALE actually produce (dozens, on a ~32px
## boulder), so this is a floor against ever silently flattening the grain
## back out, not a tight bound on it.
const MIN_BASE_FILL_GRAIN_TONES := 15

## ## Silhouette irregularity (reported: "they all have the same shape")
##
## The old boundary was a near-perfect ellipse -- `radius_x` only ever
## shrank by up to 1.5px on a 32px canvas, which reads as identical from
## seed to seed. Real rock outlines are irregular in a way size/colour alone
## can never fix. The boundary is now perturbed per ANGLE (not per pixel) by
## smooth noise sampled around a circle in noise-space -- cos/sin naturally
## wrap at angle 0/2*PI, so the perturbation closes seamlessly with no seam
## artifact at the wraparound.
##
## Purely SUBTRACTIVE (the boundary only ever carves inward from the base
## ellipse, never bulges past it) so a jagged silhouette is automatically
## guaranteed to stay within the base ellipse's existing 1px canvas margin --
## no separate containment logic needed (see
## test_a_jagged_silhouette_never_exceeds_the_original_margin).
##
## How far in noise-space one lap around the silhouette travels. Higher
## means more, smaller notches per rock; lower means fewer, broader ones.
## Picked so a 32px boulder shows several distinct facets, not one smooth
## dent or all-over gravel-texture noise.
const IRREGULARITY_ANGULAR_FREQUENCY := 3.2

## How deep the irregularity can carve, as a fraction of the base radius.
## Varies per seed within this range (see _irregularity_strength_for) so
## some rocks read as smoother pebbles and others as craggier boulders,
## rather than every rock carrying identical roughness.
const MIN_IRREGULARITY_STRENGTH := 0.10
const MAX_IRREGULARITY_STRENGTH := 0.30

## Regression floor for test_different_seeds_produce_meaningfully_different_
## silhouettes: how many alpha-mask pixels (out of SIZE.x*SIZE.y = 1024) the
## worst-case tested seed must differ from a reference seed by. The old
## ellipse-plus-1.5px-wobble shape differed by a low double digits at most;
## this is set well above that and well below the ~1024 total so it is a
## real shape-diversity floor, not a near-total-image demand.
const MIN_SILHOUETTE_PIXEL_DIFFERENCE := 40

var _palette := PixelPalette.new()

## Fraction of SIZE.y the boulder occupies (squashed, sitting on the ground).
const BOULDER_HEIGHT_FRAC := 0.75


func generate_texture(seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(seed_value))


func generate_image(seed_value: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)

	var outline_color := _palette.outline_color()
	var shade_color := _palette.shade(STONE_COLOR)
	var highlight_color := _palette.highlight(STONE_COLOR)

	var boulder_height := SIZE.y * BOULDER_HEIGHT_FRAC
	var boulder_top := SIZE.y - boulder_height
	var center := Vector2(SIZE.x / 2.0, boulder_top + boulder_height / 2.0)
	var radius_x := SIZE.x / 2.0 - 1.0
	var radius_y := boulder_height / 2.0 - 0.5

	# Seeded shape wobble: shrink the horizontal radius slightly per seed so
	# boulders differ in silhouette, not just surface detail.
	var wobble := float(absi(hash("%d_shape" % seed_value)) % 10000) / 10000.0
	radius_x -= wobble * 1.5

	var irregularity := _irregularity_strength_for(seed_value)
	var angle_offset := PixelNoise.unit(seed_value, 0, 0) * TAU

	for y in SIZE.y:
		for x in SIZE.x:
			var dx := (x + 0.5 - center.x) / radius_x
			var dy := (y + 0.5 - center.y) / radius_y
			var dist := sqrt(dx * dx + dy * dy)
			if dist < 0.001:
				image.set_pixel(x, y, _grain_color(STONE_COLOR, seed_value, x, y))
				continue
			var local_radius := _local_radius(dx / dist, dy / dist, seed_value, irregularity, angle_offset)
			if dist > local_radius:
				continue  # outside the (possibly jagged) boulder silhouette

			var color := _grain_color(STONE_COLOR, seed_value, x, y)
			if dist > local_radius * 0.78:
				color = _grain_color(outline_color, seed_value, x, y)
			elif dx < -0.15 and dy < -0.2:
				color = _grain_color(highlight_color, seed_value, x, y)
			elif dy > 0.35:
				color = _grain_color(shade_color, seed_value, x, y)
			image.set_pixel(x, y, color)

	_paint_speckles(image, center, radius_x, radius_y, outline_color, seed_value, irregularity, angle_offset)
	return image


## How deep this ROCK's irregularity carves in, seeded independently of the
## angular noise itself (see angle_offset's own sample point) so strength and
## the pattern of notches vary independently -- otherwise a strongly-carved
## rock and a lightly-carved one would always notch at the same angles.
func _irregularity_strength_for(seed_value: int) -> float:
	return lerpf(MIN_IRREGULARITY_STRENGTH, MAX_IRREGULARITY_STRENGTH, PixelNoise.unit(seed_value, 1, 1))


## The silhouette boundary, as a fraction of the base ellipse radius, in the
## direction (unit_dx, unit_dy) (a unit vector from the centre -- callers
## pass (dx/dist, dy/dist)). Always <= 1.0: irregularity only carves inward
## (see the class doc comment), so the result can never push a pixel outside
## the base ellipse's own canvas margin.
func _local_radius(unit_dx: float, unit_dy: float, seed_value: int, irregularity: float, angle_offset: float) -> float:
	var angle := atan2(unit_dy, unit_dx) + angle_offset
	var noise := PixelNoise.fractal(
		seed_value, cos(angle) * IRREGULARITY_ANGULAR_FREQUENCY, sin(angle) * IRREGULARITY_ANGULAR_FREQUENCY, 2
	)
	return 1.0 - irregularity * noise


## `base` pushed brighter or darker per-pixel by smooth noise (see
## GRAIN_STRENGTH/GRAIN_SCALE), applied as a multiply so it darkens/lightens
## `base` proportionally rather than shifting hue -- a highlight pixel and a
## shade pixel each keep their own grain contrast instead of the texture
## flattening one of them out. Deterministic per (seed_value, x, y): the same
## boulder always grains the same way.
func _grain_color(base: Color, seed_value: int, x: int, y: int) -> Color:
	var noise := PixelNoise.fractal(seed_value, float(x) * GRAIN_SCALE, float(y) * GRAIN_SCALE, 2)
	var factor := 1.0 + (noise - 0.5) * 2.0 * GRAIN_STRENGTH
	return Color(
		clampf(base.r * factor, 0.0, 1.0),
		clampf(base.g * factor, 0.0, 1.0),
		clampf(base.b * factor, 0.0, 1.0),
		base.a
	)


## A handful of deterministic darker crack/pit pixels inside the boulder,
## seeded from `seed_value` -- same idea as the tree canopy speckles.
## `irregularity`/`angle_offset` are the SAME values generate_image already
## computed for this rock's silhouette (see _local_radius) -- a speckle must
## never land in a notch irregularity has carved away, or it paints a stray
## opaque fleck floating outside the (now jagged) rock's own outline.
func _paint_speckles(
	image: Image, center: Vector2, radius_x: float, radius_y: float, speckle_color: Color, seed_value: int,
	irregularity: float, angle_offset: float
) -> void:
	for i in SPECKLE_COUNT:
		var speckle_seed := hash("%d_stone_speckle_%d" % [seed_value, i])
		var angle := float(absi(speckle_seed) % 360) * PI / 180.0
		var radius_fraction := 0.15 + float((absi(speckle_seed) / 360) % 100) / 100.0 * 0.55
		var speckle_x := int(center.x + cos(angle) * radius_x * radius_fraction)
		var speckle_y := int(center.y + sin(angle) * radius_y * radius_fraction)
		if speckle_x < 0 or speckle_x >= image.get_width() or speckle_y < 0 or speckle_y >= image.get_height():
			continue
		var dx := (speckle_x + 0.5 - center.x) / radius_x
		var dy := (speckle_y + 0.5 - center.y) / radius_y
		var dist := sqrt(dx * dx + dy * dy)
		if dist < 0.001:
			image.set_pixel(speckle_x, speckle_y, speckle_color)
			continue
		var local_radius := _local_radius(dx / dist, dy / dist, seed_value, irregularity, angle_offset)
		# keep speckles off the outline ring AND out of any carved notch
		if dist <= minf(0.78, local_radius * 0.78):
			image.set_pixel(speckle_x, speckle_y, speckle_color)
