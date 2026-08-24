extends RefCounted

## Deterministic offline pixel-art for the player/NPC body (torso, limbs,
## head) -- shaded and outlined rather than the old single flat-color fills,
## matching the same technique ProceduralSpriteGenerator (creatures) and
## ProceduralItemSprite (items) already use, for a consistent look across the
## whole game.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const PixelRamp = preload("res://src/rendering/pixel_ramp.gd")
const PixelForm = preload("res://src/rendering/pixel_form.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const IllustratedCharacterSprite = preload("res://src/rendering/illustrated_character_sprite.gd")

## The character creator's live preview (see main_menu.gd's `_portrait`) goes
## through generate_hero_portrait_image below, entirely independently of
## CharacterView's in-game Sprite2D paperdoll -- it composites raw Images
## onto one small canvas rather than positioning/scaling nodes, so it needs
## its own has-art-then-fallback branch per part rather than reusing
## CharacterView's. Shared instance (same reasoning as CharacterView's own
## _illustrated -- no per-caller state, IllustratedCharacterSprite's own
## caches are already static/shared).
var _illustrated := IllustratedCharacterSprite.new()

const OUTLINE_DARKEN := 0.5
const SHADE_DARKEN := 0.2
const HIGHLIGHT_LIGHTEN := 0.2

var _palette := PixelPalette.new()
## Where the head's dark rim begins, as squared normalized distance from
## its center -- keeps the silhouette crisp against the world behind it.
const _HEAD_OUTLINE_START := 0.86

## Where a flat sprite's shadow side begins, as a fraction in from the
## unlit edge, and which ramp stop that shadow uses. Two flat tones per
## material -- base and shadow -- is the 16-bit convention; the ramp is
## still what picks a shadow that shifts cooler rather than just darker.
const _SHADOW_SIDE_FRACTION := 0.34
const _SHADOW_STOP := 0.25

var _ramp := PixelRamp.new()
var _form := PixelForm.new()


## A rectangular body part (torso/limb): outlined edge, lighter top, darker
## bottom -- reads as a small rounded block instead of a flat rectangle.
func generate_body_part_texture(size: Vector2i, base_color: Color) -> ImageTexture:
	return ImageTexture.create_from_image(generate_body_part_image(size, base_color))


## A limb (arm or leg) shaded as a CYLINDER through the shared pixel art
## engine (see docs/concept/pixel_art_engine.md): lightness varies across
## the limb's width and stays even along its length, coloured through a
## hue-shifted ramp. The previous version banded it by height -- lighter
## top third, darker bottom third -- which read as a flat strip cut into
## three, not as a rounded arm.
func generate_body_part_image(size: Vector2i, base_color: Color) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var outline := _palette.outline_color()
	var shadow := _ramp.sample(base_color, _SHADOW_STOP)
	for y in size.y:
		for x in size.x:
			var is_edge := x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1
			if is_edge:
				image.set_pixel(x, y, outline)
				continue
			# Flat, with one shadow column down the unlit side (see the
			# tunic above -- same 16-bit convention).
			var shaded := float(x) + 0.5 > float(size.x) * (1.0 - _SHADOW_SIDE_FRACTION * 0.5)
			image.set_pixel(x, y, shadow if shaded else base_color)
	return image


## A round, shaded head with two simple eye pixels.
func generate_head_texture(size: Vector2i, skin_color: Color, eye_color: Color) -> ImageTexture:
	return ImageTexture.create_from_image(generate_head_image(size, skin_color, eye_color))


func generate_head_image(size: Vector2i, skin_color: Color, eye_color: Color) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var center := Vector2(size.x / 2.0, size.y / 2.0)
	var rx := size.x / 2.0
	var ry := size.y / 2.0

	for y in size.y:
		for x in size.x:
			var dx := (x + 0.5 - center.x) / rx
			var dy := (y + 0.5 - center.y) / ry
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			var color := skin_color
			if d > 0.75:
				color = _palette.outline_color()
			elif dy < -0.3:
				color = _palette.highlight(skin_color)
			elif dy > 0.3:
				color = _palette.shade(skin_color)
			image.set_pixel(x, y, color)

	var eye_y := int(size.y / 3.0)
	image.set_pixel(int(size.x * 0.3), eye_y, eye_color)
	image.set_pixel(int(size.x * 0.7), eye_y, eye_color)
	return image


const _EYE_COLOR := Color(0.08, 0.08, 0.1)


## A hero head (see HeroAppearance): a shaded skin ellipse with a real
## hairline in the appearance's color and style, brows, colored eyes with a
## catchlight, a mouth line, and optional facial hair. What turns "a circle
## with two dots" into a face.
##
## Hair styles (HeroAppearance.HAIR_STYLES, by index): 0 short, 1 swept
## (asymmetric fringe), 2 long (falls past the jaw both sides), 3 ponytail
## (long plus a tail out to one side), 4 topknot (crop plus a bun above),
## 5 bald. Beards (HeroAppearance.BEARD_STYLES): 0 none, 1 stubble (sparse,
## along the jaw), 2 goatee (chin + upper lip), 3 full (jaw + chin).
func generate_hero_head_texture(size: Vector2i, appearance: Dictionary) -> ImageTexture:
	return ImageTexture.create_from_image(generate_hero_head_image(size, appearance))


func generate_hero_head_image(size: Vector2i, appearance: Dictionary) -> Image:
	var skin: Color = appearance.skin
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var center := Vector2(size.x / 2.0, size.y / 2.0)
	var rx := size.x / 2.0
	var ry := size.y / 2.0

	# The head is shaded as a real SPHEROID through the shared engine (see
	# docs/concept/pixel_art_engine.md) rather than with hard "top-left is
	# lighter, bottom is darker" cutoffs, which read as two flat patches
	# stuck on a disc. A skin ramp also warms the highlights and cools the
	# shadows, which is most of what makes skin look like skin.
	var outline := _palette.outline_color()
	var skin_shadow := _ramp.sample(skin, _SHADOW_STOP)
	for y in size.y:
		for x in size.x:
			var point := Vector2(x + 0.5, y + 0.5)
			var dx := (point.x - center.x) / rx
			var dy := (point.y - center.y) / ry
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			if d > _HEAD_OUTLINE_START:
				image.set_pixel(x, y, outline)
				continue
			# Flat skin with one shadow side; the face's real detail comes
			# from the features painted over it below, not from shading.
			var shaded := dx > _SHADOW_SIDE_FRACTION or dy > 0.55
			image.set_pixel(x, y, skin_shadow if shaded else skin)

	_paint_facial_hair(image, size, appearance, center, rx, ry)
	_paint_face_features(image, size, appearance, center, rx, ry)
	_paint_hair(image, size, appearance, center, rx, ry)
	return image


## Brows, eyes (iris + dark pupil + a single catchlight pixel) and a soft
## mouth line, all placed proportionally so they land correctly at any head
## size.
func _paint_face_features(
	image: Image, size: Vector2i, appearance: Dictionary, center: Vector2, rx: float, ry: float
) -> void:
	var eye_color: Color = appearance.get("eyes", Color(0.22, 0.16, 0.10))
	var eye_y := int(center.y + ry * 0.02)
	var brow_y := eye_y - maxi(1, int(ry * 0.26))
	var eye_dx := maxi(1, int(rx * 0.42))
	var left_x := int(center.x) - eye_dx
	var right_x := int(center.x) + eye_dx - 1

	var brow: Color = (appearance.hair as Color).darkened(0.2)
	for x_offset in range(-1, 2):
		_set_if_inside(image, size, left_x + x_offset, brow_y, brow)
		_set_if_inside(image, size, right_x + x_offset, brow_y, brow)

	for eye_x in [left_x, right_x]:
		_set_if_inside(image, size, eye_x, eye_y, eye_color)
		# Pupil directly below the iris pixel on larger heads, plus a
		# highlight above it -- reads as a real eye rather than a dot.
		if ry >= 5.0:
			_set_if_inside(image, size, eye_x, eye_y + 1, _EYE_COLOR)
			_set_if_inside(image, size, eye_x, eye_y - 1, _palette.highlight(eye_color))

	var mouth_y := int(center.y + ry * 0.52)
	var mouth_color: Color = (appearance.skin as Color).darkened(0.35)
	for x_offset in range(-1, 2):
		_set_if_inside(image, size, int(center.x) + x_offset, mouth_y, mouth_color)


## Facial hair over the lower face, under the eyes/mouth pass so a beard
## never paints over them.
func _paint_facial_hair(
	image: Image, size: Vector2i, appearance: Dictionary, center: Vector2, rx: float, ry: float
) -> void:
	var beard := int(appearance.get("beard", 0))
	if beard == 0:
		return
	var hair: Color = appearance.hair
	var beard_color := hair.darkened(0.15) if beard != 1 else hair.darkened(0.05)

	for y in size.y:
		for x in size.x:
			if image.get_pixel(x, y).a == 0.0:
				continue
			var dx := (x + 0.5 - center.x) / rx
			var dy := (y + 0.5 - center.y) / ry
			if dx * dx + dy * dy > 0.82:
				continue  # keep the outline ring
			var covered := false
			match beard:
				1:  # stubble: a sparse dither along the jaw
					covered = dy > 0.28 and (x + y) % 2 == 0
				2:  # goatee: chin column plus a moustache line
					covered = (dy > 0.3 and absf(dx) < 0.32) or (dy > 0.28 and dy < 0.45 and absf(dx) < 0.5)
				3:  # full: the whole jaw and chin
					covered = dy > 0.18 or (absf(dx) > 0.55 and dy > -0.1)
			if covered:
				image.set_pixel(x, y, beard_color)


## The hairline: a per-style silhouette painted over the top of the face,
## with the lower/outer strands shaded so the head reads as rounded.
func _paint_hair(
	image: Image, size: Vector2i, appearance: Dictionary, center: Vector2, rx: float, ry: float
) -> void:
	var style := int(appearance.get("hair_style", 0))
	if style == 5:  # bald
		return
	var hair: Color = appearance.hair

	for y in size.y:
		for x in size.x:
			if image.get_pixel(x, y).a == 0.0:
				continue
			var dx := (x + 0.5 - center.x) / rx
			var dy := (y + 0.5 - center.y) / ry
			var d := dx * dx + dy * dy
			var covered := false
			match style:
				0:  # short: a neat cap above the brows
					covered = dy < -0.32
				1:  # swept: fringe angled across the forehead
					covered = dy < -0.22 or (dy < 0.0 and dx < -0.25 + dy * 0.5)
				2:  # long: cap plus curtains falling past the jaw
					covered = dy < -0.28 or absf(dx) > 0.62
				3:  # ponytail: long-ish, gathered to the right
					covered = dy < -0.3 or (absf(dx) > 0.66 and dy < 0.2) or (dx > 0.5 and dy < 0.55)
				4:  # topknot: crop plus a bun crowning the head
					covered = dy < -0.46 or (dy < -0.3 and absf(dx) < 0.3)
			if not covered:
				continue
			image.set_pixel(x, y, hair.darkened(0.35) if d > 0.7 else hair)


func _set_if_inside(image: Image, size: Vector2i, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return
	if image.get_pixel(x, y).a == 0.0:
		return  # outside the head silhouette
	image.set_pixel(x, y, color)


## A hero tunic (torso): the class-colored body with shaped shoulders, a
## contrasting collar, a trim belt with a buckle, and shaded sleeve edges --
## the class reads at a glance (see HeroAppearance.CLASS_PALETTES).
func generate_hero_tunic_texture(size: Vector2i, appearance: Dictionary) -> ImageTexture:
	return ImageTexture.create_from_image(generate_hero_tunic_image(size, appearance))


## Half the torso's width at row `y`, in pixels -- the body's silhouette.
## Proportions are expressed as fractions of the canvas so they hold at any
## art resolution: a narrow neck/shoulder line at the very top, the widest
## point across the chest, a pinched waist, then a flare to the hem.
func torso_half_width(size: Vector2i, y: int) -> float:
	var t := clampf(float(y) / maxf(float(size.y - 1), 1.0), 0.0, 1.0)
	var widest := float(size.x) / 2.0
	var fraction: float
	if t < _SHOULDER_T:
		# Shoulders rise quickly from the neck to the chest's full width.
		fraction = lerp(_NECK_FRACTION, 1.0, t / _SHOULDER_T)
	elif t < _WAIST_T:
		# Chest tapers in toward the waist.
		fraction = lerp(1.0, _WAIST_FRACTION, (t - _SHOULDER_T) / (_WAIST_T - _SHOULDER_T))
	else:
		# Hem flares back out below the waist.
		fraction = lerp(_WAIST_FRACTION, _HEM_FRACTION, (t - _WAIST_T) / maxf(1.0 - _WAIST_T, 0.0001))
	return clampf(widest * fraction, 1.0, widest)


## Torso proportions, as fractions of the canvas height (where the landmark
## sits) and of its half-width (how wide it is there).
const _SHOULDER_T := 0.16
const _WAIST_T := 0.62
const _NECK_FRACTION := 0.62
const _WAIST_FRACTION := 0.82
const _HEM_FRACTION := 0.96


func generate_hero_tunic_image(size: Vector2i, appearance: Dictionary) -> Image:
	var tunic: Color = appearance.tunic
	var trim: Color = appearance.trim
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

	# The torso is shaded as a CYLINDER through the shared pixel art engine
	# (see docs/concept/pixel_art_engine.md), with cloth folds broken into
	# it -- previously it was a flat fill with a 1px lighter left edge and
	# darker right edge, which read as a plain colored rectangle.
	var outline := _palette.outline_color()
	var tunic_shadow := _ramp.sample(tunic, _SHADOW_STOP)
	var center_x := float(size.x) / 2.0
	for y in size.y:
		# The torso is a SHAPE, not a rectangle: wide at the shoulders,
		# pinched at the waist, flaring at the hem. Silhouette is the
		# strongest readability cue in pixel art -- a well-shaded box still
		# reads as a box.
		var half := torso_half_width(size, y)
		var left := center_x - half
		var right := center_x + half
		for x in size.x:
			var px := float(x) + 0.5
			if px < left or px > right:
				continue  # outside the body -- left transparent
			var is_edge := (
				px < left + 1.0 or px > right - 1.0 or y == 0 or y == size.y - 1
			)
			if is_edge:
				image.set_pixel(x, y, outline)
				continue
			# FLAT colour with a single shadow side. 16-bit garments are
			# flat regions plus hand-placed detail, not lit volumes -- a
			# per-pixel ramp across the body read as a soft 3D render.
			var shaded := px > right - half * _SHADOW_SIDE_FRACTION
			image.set_pixel(x, y, tunic_shadow if shaded else tunic)

	# Collar: a trim V just under the shoulders.
	var collar_y := maxi(1, int(size.y * 0.12))
	for x in range(2, size.x - 2):
		image.set_pixel(x, collar_y, trim)
	_set_opaque(image, size, int(size.x / 2.0), collar_y + 1, trim)

	# Belt across the waist, with a darker buckle at its center.
	var belt_y := int(size.y * 0.66)
	for x in range(1, size.x - 1):
		image.set_pixel(x, belt_y, trim)
		if belt_y + 1 < size.y - 1:
			image.set_pixel(x, belt_y + 1, trim.darkened(0.25))
	_set_opaque(image, size, int(size.x / 2.0), belt_y, trim.darkened(0.5))

	return image


func _set_opaque(image: Image, size: Vector2i, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return
	image.set_pixel(x, y, color)


## -- Full-body portrait (character creator preview) -------------------------

## The portrait's fixed proportions, in pixels. Composed at this size and
## scaled up by the UI (nearest-neighbour) so it stays crisp pixel art.
const PORTRAIT_SIZE := Vector2i(26, 40)
const _PORTRAIT_HEAD := Vector2i(14, 14)
const _PORTRAIT_TORSO := Vector2i(16, 16)
const _PORTRAIT_LEG := Vector2i(5, 9)
const _PORTRAIT_ARM := Vector2i(4, 12)


## One cohesive standing figure -- head, torso, arms, legs, boots -- for the
## character creator's live preview (see MainMenu). Replaces the old preview,
## which was a disembodied head floating above a flat colored rectangle.
func generate_hero_portrait_texture(appearance: Dictionary) -> ImageTexture:
	return ImageTexture.create_from_image(generate_hero_portrait_image(appearance))


## The character creator's live preview -- must reflect the SAME illustrated
## rig CharacterView wears in-game, not just the procedural fallback (asked
## directly: "rehaul the character rendering in game AND in creation"). Each
## part checks IllustratedCharacterSprite first and falls back to this
## file's own procedural generator otherwise, the same has-art-then-fallback
## shape CharacterView uses -- just working in raw Images (this function
## composites onto one small canvas by pixel-blending, not by positioning
## Sprite2D nodes), which is why it needs its own per-part helpers below
## rather than reusing CharacterView's Sprite2D-scale logic.
func generate_hero_portrait_image(appearance: Dictionary) -> Image:
	var image := Image.create(PORTRAIT_SIZE.x, PORTRAIT_SIZE.y, false, Image.FORMAT_RGBA8)
	var center_x := PORTRAIT_SIZE.x / 2

	# Which of hero_composite.png's 8 pre-colored outfits this portrait wears
	# -- DNA-derived, rolled once so body/legs/arms all match the same
	# outfit (see IllustratedCharacterSprite.outfit_variant_for).
	var outfit_variant := _illustrated.outfit_variant_for(appearance.get("seed", 0))

	var torso_y := _PORTRAIT_HEAD.y - 2
	var legs_y := torso_y + _PORTRAIT_TORSO.y - 1

	# Arms first, so the torso's outline overlaps them at the shoulder rather
	# than the other way around. Left/right use frame 0/1 of the illustrated
	# sheet's two independent drawings (see IllustratedCharacterSprite's own
	# doc comment on hero_composite.png's arms column) rather than the same
	# frame mirrored twice.
	var arm_y := torso_y + 3
	_blend(
		image, _portrait_arm_image(appearance, outfit_variant, 0),
		Vector2i(center_x - _PORTRAIT_TORSO.x / 2 - _PORTRAIT_ARM.x + 1, arm_y)
	)
	_blend(
		image, _portrait_arm_image(appearance, outfit_variant, 1),
		Vector2i(center_x + _PORTRAIT_TORSO.x / 2 - 1, arm_y)
	)

	_blend_portrait_legs(image, appearance, outfit_variant, center_x, legs_y)

	_blend(
		image, _portrait_torso_image(appearance, outfit_variant),
		Vector2i(center_x - _PORTRAIT_TORSO.x / 2, torso_y)
	)
	_blend(image, _portrait_head_image(appearance), Vector2i(center_x - _PORTRAIT_HEAD.x / 2, 0))
	return image


func _portrait_head_image(appearance: Dictionary) -> Image:
	var cell_index: int = appearance.get("head_index", 0)
	if _illustrated.has_usable_head(cell_index, appearance.skin):
		var trimmed := _illustrated.trimmed_head_image(cell_index, appearance.skin)
		if trimmed != null:
			return _fit_to_box(trimmed, _PORTRAIT_HEAD)
	return generate_hero_head_image(_PORTRAIT_HEAD, appearance)


## Pre-colored by hero_composite.png itself (see IllustratedCharacterSprite's
## own doc comment on that sheet) -- fit only, no tint, the same rule the
## illustrated head already follows: re-tinting already-colored art would
## double the color.
func _portrait_torso_image(appearance: Dictionary, outfit_variant: int) -> Image:
	if _illustrated.has_composite_part("body"):
		var trimmed := _illustrated.trimmed_composite_image("body", outfit_variant)
		if trimmed != null:
			return _fit_to_box(trimmed, _PORTRAIT_TORSO)
	return generate_hero_tunic_image(_PORTRAIT_TORSO, appearance)


func _portrait_arm_image(appearance: Dictionary, outfit_variant: int, frame_index: int) -> Image:
	if _illustrated.has_composite_part("arms"):
		var trimmed := _illustrated.trimmed_composite_image("arms", outfit_variant, "front", frame_index)
		if trimmed != null:
			return _fit_to_box(trimmed, _PORTRAIT_ARM)
	return generate_body_part_image(_PORTRAIT_ARM, appearance.skin)


## legs.png draws both legs together as one fused pair (see
## IllustratedCharacterSprite's own doc comment on why), so unlike arms it
## is blended ONCE, centred, sized to the combined span the procedural
## path's two separate leg blends would otherwise occupy -- not the same
## small image blended twice. The procedural fallback still paints its own
## synthetic boots (`_paint_boots`); the illustrated pair already has real
## boots drawn into the art, so that step is skipped for it.
##
## Anchored by its BOTTOM at the portrait canvas's own bottom edge, not by
## its top at `legs_y` the way the procedural fallback below still is --
## feet belong on the ground regardless of exactly how tall trimmed_
## composite_image's aspect-fit happens to come out for a given outfit row,
## the same "anchor the ground-contact point, not an arbitrary top" rule
## normalize_frames' own BASELINE_Y already applies one step up the
## pipeline (see IllustratedCharacterSprite). A fixed top anchor instead
## left the fitted image occasionally falling short of the canvas bottom
## whenever a row's own aspect ratio didn't happen to fill the full target
## height -- caught by test_portrait_is_a_cohesive_figure_when_legs_are_a_
## fused_pair once _primary_content_rect (see IllustratedCharacterSprite)
## started returning each row's real, un-inflated content height instead of
## one padded out by a stray fragment stacked below it.
func _blend_portrait_legs(
	image: Image, appearance: Dictionary, outfit_variant: int, center_x: int, legs_y: int
) -> void:
	if _illustrated.has_composite_part("legs"):
		var trimmed := _illustrated.trimmed_composite_image("legs", outfit_variant)
		if trimmed != null:
			var span := Vector2i(_PORTRAIT_LEG.x * 2 + 2, _PORTRAIT_LEG.y)
			var fitted := _fit_to_box(trimmed, span)
			var feet_y := PORTRAIT_SIZE.y - fitted.get_height()
			_blend(image, fitted, Vector2i(center_x - fitted.get_width() / 2, feet_y))
			return
	var leg := generate_body_part_image(_PORTRAIT_LEG, appearance.legs)
	_paint_boots(leg, _PORTRAIT_LEG, appearance)
	_blend(image, leg, Vector2i(center_x - _PORTRAIT_LEG.x - 1, legs_y))
	_blend(image, leg, Vector2i(center_x + 1, legs_y))


## Scales `source` to fit inside `target_size`, preserving aspect (the same
## "scale to fit, never stretch" rule normalize_frames applies one step up)
## -- no tint, for the head, whose skin tone is already baked in by
## IllustratedCharacterSprite.generate_head_texture's own luminance recolor.
func _fit_to_box(source: Image, target_size: Vector2i) -> Image:
	var scale := minf(
		float(target_size.x) / float(maxi(1, source.get_width())),
		float(target_size.y) / float(maxi(1, source.get_height()))
	)
	var width := maxi(1, int(round(float(source.get_width()) * scale)))
	var height := maxi(1, int(round(float(source.get_height()) * scale)))
	var resized := source.duplicate()
	if resized.get_format() != Image.FORMAT_RGBA8:
		resized.convert(Image.FORMAT_RGBA8)
	resized.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return resized


## Darkens the bottom rows of a leg into a boot, so legs read as clothed
## limbs rather than plain colored bars.
func _paint_boots(leg: Image, size: Vector2i, appearance: Dictionary) -> void:
	var boot: Color = (appearance.legs as Color).darkened(0.4)
	for y in range(size.y - 3, size.y):
		for x in size.x:
			if leg.get_pixel(x, y).a == 0.0:
				continue
			var is_edge := x == 0 or x == size.x - 1 or y == size.y - 1
			leg.set_pixel(x, y, _palette.outline_color() if is_edge else boot)


## Alpha-composites `src` onto `dst` at `at`, clipped to dst's bounds.
func _blend(dst: Image, src: Image, at: Vector2i) -> void:
	dst.blend_rect(src, Rect2i(Vector2i.ZERO, Vector2i(src.get_width(), src.get_height())), at)
