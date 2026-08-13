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
const PixelRamp = preload("res://src/rendering/pixel_ramp.gd")
const PixelForm = preload("res://src/rendering/pixel_form.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## The ART canvas -- 4x the original 24x16 (see
## docs/concept/art_resolution.md). CreatureRenderer draws it at
## ArtResolution.SPRITE_SCALE, so animals gain real detail (a muzzle, ears,
## antlers, separate legs) without growing in the world.
const WIDTH := 48
const HEIGHT := 32

const EYE_COLOR := Color(0.05, 0.05, 0.05)
const TUSK_COLOR := Color(0.92, 0.9, 0.8)
## Antlers and horns: warm bone/keratin, distinct from the coat so a
## deer's rack and a goat's horns read against the head behind them.
const ANTLER_COLOR := Color(0.72, 0.62, 0.46)
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
	"horse": Color(0.5, 0.3, 0.15),
	"mouse": Color(0.58, 0.52, 0.46),
	"deer": Color(0.62, 0.38, 0.2),
	"bear": Color(0.22, 0.15, 0.1),
	"lion": Color(0.78, 0.55, 0.15),
	"nonvenomous_snake": Color(0.35, 0.42, 0.22),
	"venomous_snake": Color(0.55, 0.22, 0.12),
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
## Horse joins the existing deer_shape reuse (both slender-legged ungulates,
## same as camel/reindeer/goat). Mouse is the one genuine exception: it
## doesn't read as any existing silhouette at any scale (short legs, round
## body, long tail), so it gets its own new "mouse_shape" family instead --
## see docs/concept/ecosystem_dynamics.md's Species roster section.
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
	"horse": "deer_shape",
	"mouse": "mouse_shape",
	"deer": "deer_shape",
	"bear": "boar_shape",
	"lion": "lynx_shape",
	"nonvenomous_snake": "snake_shape",
	"venomous_snake": "snake_shape",
}

## Jaguar (lynx-shaped) gets a scatter of dark rosette-like speckle dots so it
## reads as visually distinct from other lynx-shaped species rather than a
## plain recolor -- same speckle technique as
## ProceduralTreeSprite._paint_speckles. Nothing else is speckled.
## Real venomous snakes often carry a genuine, visible warning pattern (see
## docs/concept/ecosystem_dynamics.md's Species roster) -- venomous_snake
## reuses this exact speckle technique so the venomous/nonvenomous visual
## distinction is grounded, not an arbitrary recolor.
const JAGUAR_SPOT_COLOR := Color(0.12, 0.08, 0.05)
const SPOT_COUNT := 6
const SPOTTED_SPECIES := {"jaguar": true, "venomous_snake": true}

var _palette := PixelPalette.new()
var _ramp := PixelRamp.new()
var _form := PixelForm.new()

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
	"mouse_shape":
	[
		"........................",
		"........................",
		"........................",
		"........................",
		"........................",
		"........................",
		"........................",
		"........................",
		"......o...o.............",
		"......obbbo.............",
		"......obbenoo...........",
		"......obssbo............",
		".......oso..............",
		"..........nnnn..........",
		"........................",
		"........................",
	],
	"snake_shape":
	[
		"........................",
		"........................",
		"........................",
		"........................",
		"........................",
		"........................",
		"........................",
		"........................",
		"........................",
		"..oo....................",
		".obeo...................",
		"..obbbo.................",
		"......obbbbo............",
		"...........obbbbo.......",
		"................obbo....",
		"....................o...",
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
	var key: String = species if SPECIES_BASE_COLORS.has(species) else "herbivore"
	var profile := AnimalAnatomy.profile_for(key)
	var base_color: Color = _palette.saturate(SPECIES_BASE_COLORS[key], BASE_SATURATE)

	var jitter := PixelNoise.unit(seed_value, key.length(), 0) - 0.5
	var coat := base_color.lightened(maxf(jitter * JITTER_RANGE, 0.0)).darkened(
		maxf(-jitter * JITTER_RANGE, 0.0)
	)

	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	_paint_animal(image, profile, coat)
	if SPOTTED_SPECIES.has(key):
		_paint_body_spots(image, seed_value)
	_outline_silhouette(image)
	return image

## Coat markings (jaguar rosettes, a venomous snake's warning bands).
## Reads the ASSEMBLED image rather than a source bitmap -- the hand-drawn
## bitmaps it used to scan are gone, and the marks belong on whatever body
## the anatomy produced.
func _paint_body_spots(image: Image, seed_value: int) -> void:
	var outline := _palette.outline_color()
	var body_cells: Array[Vector2i] = []
	for y in HEIGHT:
		for x in WIDTH:
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0 and pixel != outline:
				body_cells.append(Vector2i(x, y))
	if body_cells.is_empty():
		return

	# Scaled with the canvas area so marking density per drawn area is
	# unchanged now that the sprite carries 16x the pixels.
	var count := SPOT_COUNT * ArtResolution.DETAIL_MULTIPLIER * ArtResolution.DETAIL_MULTIPLIER
	for i in count:
		var cell: Vector2i = body_cells[PixelNoise.value(seed_value, i, 0) % body_cells.size()]
		# A 2x2 blot rather than a lone pixel, so a marking still reads at
		# the higher resolution instead of vanishing into the coat.
		for dy in 2:
			for dx in 2:
				var px: int = cell.x + dx
				var py: int = cell.y + dy
				if px >= WIDTH or py >= HEIGHT:
					continue
				var existing := image.get_pixel(px, py)
				if existing.a > 0.0 and existing != outline:
					image.set_pixel(px, py, JAGUAR_SPOT_COLOR)


func _seeded_unit_float(seed_value: int, salt: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, salt])) % 10000) / 10000.0


# -- anatomy assembly -------------------------------------------------------
#
# An animal is built from parts sized by its AnimalAnatomy profile, rather
# than stamped from one of a few shared bitmaps. Every part is a shaded
# ellipse or tapered limb, coloured through the pixel art engine's discrete
# ramp (see docs/concept/pixel_art_engine.md), so species differ by real
# proportions -- neck length, leg length, headgear, tail -- the way real
# animals do.

## The animal faces right; the head end sits this far along the body.
const _HEAD_SIDE := 1.0
## The far pair of legs is darkened, so the body reads as having depth.
const _FAR_LEG_DARKEN := 0.28


func _paint_animal(image: Image, profile: Dictionary, coat: Color) -> void:
	var w := float(WIDTH)
	var h := float(HEIGHT)
	var body_half := Vector2(profile.body_length * w * 0.5, profile.body_height * h * 0.5)
	var body_center := Vector2(w * 0.46, profile.body_y * h)
	var ground: float = body_center.y + body_half.y + profile.leg_length * h

	# Legs first, so the body overlaps them at the shoulder and hip.
	_paint_legs(image, profile, coat, body_center, body_half, ground)
	_paint_tail(image, profile, coat, body_center, body_half)
	_paint_body(image, profile, coat, body_center, body_half)

	# Neck and head, carried at the profile's angle.
	var neck_dir := _neck_direction(profile.neck_carriage)
	var neck_start := body_center + Vector2(body_half.x * 0.72 * _HEAD_SIDE, -body_half.y * 0.45)
	var neck_end: Vector2 = neck_start + neck_dir * (profile.neck_length * h)
	_paint_limb(image, neck_start, neck_end, profile.neck_thickness * h, coat)

	var head_half := Vector2(profile.head_length * w * 0.5, profile.head_height * h * 0.5)
	var head_center: Vector2 = neck_end + Vector2(head_half.x * 0.35 * _HEAD_SIDE, 0.0)
	_paint_head(image, profile, coat, head_center, head_half)

	if profile.has_mane:
		_paint_mane(image, coat, neck_start, neck_end, profile.neck_thickness * h)


## Which way the neck points: grazers carry it up, predators level, rooters
## low with the head down near the ground.
func _neck_direction(carriage: String) -> Vector2:
	match carriage:
		AnimalAnatomy.NECK_UPRIGHT:
			return Vector2(0.42, -0.91).normalized()
		AnimalAnatomy.NECK_LOW:
			return Vector2(0.94, 0.34).normalized()
		_:
			return Vector2(0.96, -0.28).normalized()


func _paint_body(image: Image, profile: Dictionary, coat: Color, center: Vector2, half: Vector2) -> void:
	var hump: float = profile.shoulder_hump * float(HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			var point := Vector2(x + 0.5, y + 0.5)
			# The shoulder hump lifts the barrel toward the head end, which
			# is what makes a boar or camel read as humped rather than as a
			# plain cylinder.
			var along := clampf((point.x - (center.x - half.x)) / maxf(half.x * 2.0, 0.001), 0.0, 1.0)
			var lift := hump * sin(along * PI) * (0.6 + 0.4 * along)
			var shifted := Vector2(point.x, point.y + lift * 0.5)
			var shifted_half := Vector2(half.x, half.y + lift * 0.5)
			# A superellipse rather than a plain oval: `barrel_squareness`
			# flattens the top and bottom into a slab-sided barrel with a
			# level topline. A pure ellipse reads as a dog no matter how the
			# legs and neck are proportioned.
			if _barrel_depth(center, shifted_half, shifted, profile.barrel_squareness) <= 0.0:
				continue
			image.set_pixel(x, y, _form.shade(_ramp, coat, center, shifted_half, shifted))


func _paint_head(image: Image, profile: Dictionary, coat: Color, center: Vector2, half: Vector2) -> void:
	_paint_ellipse_shaded(image, center, half, coat)
	# Muzzle: a tapered snout reaching forward -- long on horses and boars,
	# blunt on cats -- one of the strongest species cues at this size.
	var muzzle_length: float = profile.muzzle * half.x * 1.4
	if muzzle_length > 0.5:
		var muzzle_center := center + Vector2((half.x * 0.55 + muzzle_length * 0.5) * _HEAD_SIDE, half.y * 0.25)
		_paint_ellipse_shaded(image, muzzle_center, Vector2(muzzle_length * 0.5, half.y * 0.42), coat.darkened(0.08))

	_paint_ears(image, profile, coat, center, half)
	_paint_headgear(image, profile, center, half)

	var eye := center + Vector2(half.x * 0.35 * _HEAD_SIDE, -half.y * 0.15)
	_paint_ellipse(image, eye, Vector2(maxf(half.x * 0.16, 1.0), maxf(half.y * 0.16, 1.0)), EYE_COLOR)


func _paint_ears(image: Image, profile: Dictionary, coat: Color, center: Vector2, half: Vector2) -> void:
	var ear := Vector2(half.x * profile.ear_size * 0.8, half.y * profile.ear_size * 1.4)
	if ear.y < 0.8:
		return
	for side in [-1.0, 1.0]:
		var ear_center := center + Vector2(half.x * 0.12 * side - half.x * 0.2, -half.y - ear.y * 0.5)
		_paint_ellipse(image, ear_center, ear, coat.darkened(0.22) if side < 0.0 else coat)


func _paint_headgear(image: Image, profile: Dictionary, center: Vector2, half: Vector2) -> void:
	match profile.headgear:
		AnimalAnatomy.HEADGEAR_ANTLERS:
			# Branched beams sweeping up and back -- the deer read.
			var base := center + Vector2(-half.x * 0.1, -half.y * 0.9)
			for side in [-1.0, 1.0]:
				var tip := base + Vector2(side * half.x * 0.5 - half.x * 0.6, -half.y * 2.6)
				_paint_limb(image, base, tip, maxf(half.y * 0.18, 1.5), ANTLER_COLOR)
				var fork_a: Vector2 = base.lerp(tip, 0.45)
				_paint_limb(image, fork_a, fork_a + Vector2(side * half.x * 0.5 + half.x * 0.3, -half.y * 0.8), maxf(half.y * 0.13, 1.0), ANTLER_COLOR)
				var fork_b: Vector2 = base.lerp(tip, 0.75)
				_paint_limb(image, fork_b, fork_b + Vector2(side * half.x * 0.4 + half.x * 0.25, -half.y * 0.6), maxf(half.y * 0.13, 1.0), ANTLER_COLOR)
		AnimalAnatomy.HEADGEAR_HORNS:
			# Short horns curving back over the neck.
			var horn_base := center + Vector2(-half.x * 0.15, -half.y * 0.85)
			for side in [-1.0, 1.0]:
				var mid := horn_base + Vector2(-half.x * 0.55, -half.y * 1.2)
				var tip := mid + Vector2(-half.x * 0.75, half.y * 0.35)
				_paint_limb(image, horn_base + Vector2(0.0, side * half.y * 0.15), mid, maxf(half.y * 0.17, 1.0), ANTLER_COLOR)
				_paint_limb(image, mid, tip, maxf(half.y * 0.14, 1.0), ANTLER_COLOR)
		AnimalAnatomy.HEADGEAR_TUSKS:
			var tusk_base := center + Vector2(half.x * 1.15 * _HEAD_SIDE, half.y * 0.45)
			_paint_limb(image, tusk_base, tusk_base + Vector2(half.x * 0.3, -half.y * 0.85), maxf(half.y * 0.15, 1.0), TUSK_COLOR)


func _paint_legs(
	image: Image, profile: Dictionary, coat: Color, body_center: Vector2, body_half: Vector2, ground: float
) -> void:
	if profile.leg_length <= 0.001:
		return  # legless (snakes) -- no limbs to draw at all
	var thickness: float = maxf(profile.leg_thickness * float(HEIGHT), 1.5)
	var shoulder_x := body_center.x + body_half.x * 0.58
	var hip_x := body_center.x - body_half.x * 0.62
	var top := body_center.y + body_half.y * 0.35
	# The far pair is drawn first and darker, so the body reads as solid.
	var pairs := [
		{"offset": -thickness * 0.95, "color": coat.darkened(_FAR_LEG_DARKEN)},
		{"offset": thickness * 0.6, "color": coat},
	]
	for pair in pairs:
		for x_base in [shoulder_x, hip_x]:
			var x: float = x_base + pair.offset
			_paint_limb(image, Vector2(x, top), Vector2(x, ground), thickness, pair.color)


func _paint_tail(
	image: Image, profile: Dictionary, coat: Color, body_center: Vector2, body_half: Vector2
) -> void:
	var root := body_center + Vector2(-body_half.x * 0.95, -body_half.y * 0.35)
	var length: float = profile.tail_length * float(HEIGHT)
	if length <= 0.5:
		return
	match profile.tail:
		AnimalAnatomy.TAIL_FLOWING:
			_paint_limb(image, root, root + Vector2(-length * 0.35, length * 0.95), maxf(length * 0.24, 2.0), coat.darkened(0.14))
		AnimalAnatomy.TAIL_BUSHY:
			_paint_limb(image, root, root + Vector2(-length * 0.85, length * 0.35), maxf(length * 0.36, 2.0), coat.darkened(0.1))
		AnimalAnatomy.TAIL_THIN:
			_paint_limb(image, root, root + Vector2(-length, -length * 0.25), maxf(length * 0.07, 1.0), coat.darkened(0.2))
		AnimalAnatomy.TAIL_TUFT:
			# Short upright scut with a pale underside -- the deer flag.
			_paint_limb(image, root, root + Vector2(-length * 0.25, -length * 0.9), maxf(length * 0.45, 1.5), coat.lightened(0.35))
		AnimalAnatomy.TAIL_STUB:
			_paint_ellipse(image, root + Vector2(-length * 0.5, 0.0), Vector2(maxf(length * 0.6, 1.0), maxf(length * 0.5, 1.0)), coat.darkened(0.1))


## A mane down the upper edge of a horse's neck.
func _paint_mane(image: Image, coat: Color, neck_start: Vector2, neck_end: Vector2, thickness: float) -> void:
	var mane := coat.darkened(0.35)
	var steps := 16
	for i in steps + 1:
		var t := float(i) / float(steps)
		var point: Vector2 = neck_start.lerp(neck_end, t)
		_paint_ellipse(image, point + Vector2(-thickness * 0.5, -thickness * 0.1), Vector2(thickness * 0.34, thickness * 0.44), mane)


## A tapered capsule between two points -- legs, necks, antler beams, tails.
func _paint_limb(image: Image, from_point: Vector2, to_point: Vector2, thickness: float, color: Color) -> void:
	var steps := maxi(int(from_point.distance_to(to_point)), 1)
	var half := maxf(thickness * 0.5, 0.5)
	for i in steps + 1:
		var t := float(i) / float(steps)
		var point: Vector2 = from_point.lerp(to_point, t)
		# Limbs taper toward their far end, like real ones.
		var radius: float = half * lerp(1.0, 0.72, t)
		_paint_ellipse_shaded(image, point, Vector2(radius, radius), color)


## Flat-filled ellipse, for parts small enough that ramping them would just
## add noise: ears, eyes, tail stubs.
func _paint_ellipse(image: Image, center: Vector2, half: Vector2, color: Color) -> void:
	for cell in _ellipse_cells(center, half):
		image.set_pixel(cell.x, cell.y, color)


## Ellipse shaded through the ramp, so rounded parts read as tubes rather
## than flat sticks.
func _paint_ellipse_shaded(image: Image, center: Vector2, half: Vector2, color: Color) -> void:
	for cell in _ellipse_cells(center, half):
		var lightness := _form.cylinder_lightness(center.x - half.x, half.x * 2.0, float(cell.x) + 0.5)
		image.set_pixel(cell.x, cell.y, _ramp.sample(color, lightness))


func _ellipse_cells(center: Vector2, half: Vector2) -> Array:
	var cells := []
	var min_x := maxi(int(center.x - half.x) - 1, 0)
	var max_x := mini(int(center.x + half.x) + 1, WIDTH - 1)
	var min_y := maxi(int(center.y - half.y) - 1, 0)
	var max_y := mini(int(center.y + half.y) + 1, HEIGHT - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if _form.ellipse_depth(center, half, Vector2(x + 0.5, y + 0.5)) > 0.0:
				cells.append(Vector2i(x, y))
	return cells


## Rings the assembled silhouette in the shared outline colour, so the
## animal separates cleanly from whatever ground it stands on.
func _outline_silhouette(image: Image) -> void:
	var outline := _palette.outline_color()
	var to_outline: Array[Vector2i] = []
	var offsets := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for y in HEIGHT:
		for x in WIDTH:
			if image.get_pixel(x, y).a > 0.0:
				continue
			for offset in offsets:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if nx < 0 or nx >= WIDTH or ny < 0 or ny >= HEIGHT:
					continue
				if image.get_pixel(nx, ny).a > 0.0:
					to_outline.append(Vector2i(x, y))
					break
	for cell in to_outline:
		image.set_pixel(cell.x, cell.y, outline)


## How deep inside the body barrel a point is, as a superellipse: exponent 2
## is a plain oval, higher exponents square it off into the deep slab-sided
## chest a horse or an ox actually has.
func _barrel_depth(center: Vector2, half: Vector2, point: Vector2, squareness: float) -> float:
	var nx := absf(point.x - center.x) / maxf(half.x, 0.001)
	var ny := absf(point.y - center.y) / maxf(half.y, 0.001)
	var exponent: float = lerp(2.0, 5.0, clampf(squareness, 0.0, 1.0))
	var d := pow(nx, exponent) + pow(ny, exponent)
	return 0.0 if d >= 1.0 else 1.0 - pow(d, 1.0 / exponent)
