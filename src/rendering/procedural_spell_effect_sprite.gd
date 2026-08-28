extends RefCounted

## Deterministic in-engine pixel-art for spell atom effects (docs/concept/
## magic.md's "Atom effects render as composite spritemaps" section,
## docs/concept/spell_runtime.md) -- the procedural-first fallback every atom
## must render correctly from before any illustrated sheet exists, the same
## two-track pattern ProceduralItemSprite already established for items.
## Keyed by ATOM id, not item/spell id: an effect belongs to the atom being
## cast, not whichever wand triggered it. A handful of shared shape
## primitives (burst/ring/cross/spiral/chevron/cloud) are reused across all
## ~25 atoms, mirroring ProceduralItemSprite's own "shapes reused across many
## entries" convention rather than one bespoke draw routine per atom.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## Matches ProceduralItemSprite.SIZE -- keeps every generated sprite in the
## game on the same pixel-detail scale.
const SIZE := 32

const OUTLINE_DARKEN := 0.55
const SHADE_DARKEN := 0.25

var _palette := PixelPalette.new()

## atom_id -> {color, shape}. shape is one of: burst, ring, cross, spiral,
## chevron, cloud. Grouped by spell_atom_catalog.gd's own category, which is
## the shared "motion language" magic.md's atom-effects section describes --
## every damage atom is a burst, every control atom a ring/cloud, etc. --
## while each atom still keeps its own distinct color so none collide.
const _ATOM_LOOKS := {
	# damage -- an instantaneous burst at the target
	"fire_damage": {"color": Color(0.95, 0.35, 0.1), "shape": "burst"},
	"frost_damage": {"color": Color(0.55, 0.8, 0.95), "shape": "burst"},
	"shock_damage": {"color": Color(0.95, 0.9, 0.25), "shape": "burst"},
	"poison_damage": {"color": Color(0.45, 0.75, 0.25), "shape": "cloud"},
	# heal -- a soft cross/sparkle
	"minor_heal": {"color": Color(0.95, 0.85, 0.55), "shape": "cross"},
	"major_heal": {"color": Color(1.0, 0.95, 0.6), "shape": "cross"},
	# control -- lingering statuses: rings (frozen/rooted/shielded-in-place),
	# clouds (creeping damage/blight), a spiral for a viscous drag (slow)
	"ignite": {"color": Color(0.85, 0.25, 0.1), "shape": "burst"},
	"freeze": {"color": Color(0.65, 0.9, 0.98), "shape": "ring"},
	"slow": {"color": Color(0.35, 0.55, 0.55), "shape": "spiral"},
	"root": {"color": Color(0.45, 0.35, 0.18), "shape": "ring"},
	# movement -- opposed chevrons (push outward, pull inward): the
	# procedural fallback differentiates them by color, since a single
	# static sprite can't show a swept direction the way real motion would
	"push": {"color": Color(0.75, 0.75, 0.8), "shape": "chevron"},
	"pull": {"color": Color(0.4, 0.4, 0.55), "shape": "chevron"},
	# defense
	"shield": {"color": Color(0.4, 0.65, 0.95), "shape": "ring"},
	# summon -- a small bright spark
	"summon_wisp": {"color": Color(0.75, 0.95, 0.95), "shape": "cross"},
	# utility
	"reveal": {"color": Color(0.95, 0.92, 0.7), "shape": "ring"},
	# biological
	"accelerate_growth": {"color": Color(0.4, 0.8, 0.35), "shape": "spiral"},
	"induce_mutation": {"color": Color(0.65, 0.3, 0.75), "shape": "burst"},
	"suppress_mutation": {"color": Color(0.6, 0.6, 0.65), "shape": "ring"},
	"blight": {"color": Color(0.35, 0.22, 0.32), "shape": "cloud"},
	# perceptual
	"illuminate": {"color": Color(1.0, 0.98, 0.75), "shape": "burst"},
	"calm": {"color": Color(0.6, 0.8, 0.85), "shape": "ring"},
	"fear": {"color": Color(0.28, 0.15, 0.3), "shape": "burst"},
	# spatial
	"teleport": {"color": Color(0.6, 0.4, 0.9), "shape": "ring"},
	"portal": {"color": Color(0.25, 0.2, 0.55), "shape": "ring"},
	"gravity_shift": {"color": Color(0.3, 0.28, 0.5), "shape": "spiral"},
}
const _FALLBACK := {"color": Color(0.7, 0.7, 0.7), "shape": "burst"}


func has_look(atom_id: String) -> bool:
	return _ATOM_LOOKS.has(atom_id)


static func color_for(atom_id: String) -> Color:
	return _ATOM_LOOKS.get(atom_id, _FALLBACK)["color"]


func generate_texture(atom_id: String) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(atom_id))


## Effect art is a pure function of the atom id, so every cast of the same
## atom shares one texture -- same reasoning/shape as
## ProceduralItemSprite._texture_cache.
static var _texture_cache: Dictionary = {}


func texture_for(atom_id: String) -> ImageTexture:
	if not _texture_cache.has(atom_id):
		_texture_cache[atom_id] = ImageTexture.create_from_image(generate_image(atom_id))
	return _texture_cache[atom_id]


func generate_image(atom_id: String) -> Image:
	var look: Dictionary = _ATOM_LOOKS.get(atom_id, _FALLBACK)
	var base: Color = _palette.saturate(look["color"], 0.1)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)

	match look["shape"]:
		"ring":
			_draw_ring(image, base)
		"cross":
			_draw_cross(image, base)
		"spiral":
			_draw_spiral(image, base)
		"chevron":
			_draw_chevron(image, base)
		"cloud":
			_draw_cloud(image, base)
		_:
			_draw_burst(image, base)

	return image


## A radiating starburst -- the shared "instantaneous impact" silhouette for
## damage/fire/shock-flavored atoms: a bright core with spikes reaching
## outward, tapering and darkening toward each tip.
func _draw_burst(image: Image, base: Color) -> void:
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	var core_radius := SIZE * 0.16
	var spike_count := 8
	for y in SIZE:
		for x in SIZE:
			var offset := Vector2(x + 0.5, y + 0.5) - center
			var distance := offset.length()
			if distance > SIZE * 0.48:
				continue
			var angle := offset.angle()
			var spike_phase := absf(sin(angle * spike_count / 2.0))
			var max_radius := lerpf(SIZE * 0.22, SIZE * 0.48, spike_phase)
			if distance > max_radius:
				continue
			if distance <= core_radius:
				image.set_pixel(x, y, _palette.highlight(base))
			else:
				var t := (distance - core_radius) / maxf(max_radius - core_radius, 0.001)
				image.set_pixel(x, y, base.darkened(clampf(t * 0.5, 0.0, 0.5)))


## A thin outlined ring -- shared "surrounds the target" silhouette for
## frozen/rooted/shielded/revealed/calmed/teleport-flavored atoms.
func _draw_ring(image: Image, base: Color) -> void:
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	var outer := SIZE * 0.46
	var inner := SIZE * 0.3
	for y in SIZE:
		for x in SIZE:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if distance > outer or distance < inner:
				continue
			var edge := (outer - distance) / (outer - inner)
			if edge < 0.15 or edge > 0.85:
				image.set_pixel(x, y, base.darkened(OUTLINE_DARKEN))
			else:
				image.set_pixel(x, y, _palette.highlight(base) if edge > 0.5 else base)


## A cross/sparkle -- shared "restorative/small spark" silhouette for
## heal/summon-flavored atoms: two crossed bars with a bright center.
func _draw_cross(image: Image, base: Color) -> void:
	var center := SIZE / 2
	var half_length := SIZE * 0.4
	var half_width := SIZE * 0.07
	for y in SIZE:
		for x in SIZE:
			var dx := absf(x + 0.5 - center)
			var dy := absf(y + 0.5 - center)
			var on_vertical := dx <= half_width and dy <= half_length
			var on_horizontal := dy <= half_width and dx <= half_length
			if not (on_vertical or on_horizontal):
				continue
			var distance := Vector2(dx, dy).length()
			image.set_pixel(x, y, _palette.highlight(base) if distance < SIZE * 0.12 else base)


## An inward spiral -- shared "viscous drag / gradual change" silhouette for
## slow/growth/gravity-flavored atoms.
func _draw_spiral(image: Image, base: Color) -> void:
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	var max_radius := SIZE * 0.46
	var turns := 2.2
	var steps := 220
	for i in steps:
		var t := float(i) / float(steps - 1)
		var radius := max_radius * (1.0 - t)
		var angle := t * turns * TAU
		var point := center + Vector2(cos(angle), sin(angle)) * radius
		var px := int(point.x)
		var py := int(point.y)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var x := px + dx
				var y := py + dy
				if x >= 0 and x < SIZE and y >= 0 and y < SIZE:
					image.set_pixel(x, y, base.darkened(t * 0.3))


## Two opposed wedges (an outward-facing chevron pair) -- shared
## "directional force" silhouette for push/pull-flavored atoms.
func _draw_chevron(image: Image, base: Color) -> void:
	var center := SIZE / 2.0
	for y in SIZE:
		for x in SIZE:
			var dx := x + 0.5 - center
			var dy := y + 0.5 - center
			var distance := Vector2(dx, dy).length()
			if distance > SIZE * 0.44:
				continue
			# Two wedges opening left and right, each a triangular chevron
			# shape: |dy| grows narrower as |dx| approaches the center.
			var on_right_wedge := dx > 0.0 and absf(dy) <= dx * 0.8
			var on_left_wedge := dx < 0.0 and absf(dy) <= -dx * 0.8
			if not (on_right_wedge or on_left_wedge):
				continue
			var edge := distance / (SIZE * 0.44)
			image.set_pixel(x, y, _shade_radial(base, edge))


## A soft, irregular blob cluster -- shared "creeping/spreading" silhouette
## for poison/blight-flavored atoms, distinct from burst's sharp spikes.
func _draw_cloud(image: Image, base: Color) -> void:
	var puffs := [
		Vector2(SIZE * 0.42, SIZE * 0.55), Vector2(SIZE * 0.58, SIZE * 0.55),
		Vector2(SIZE * 0.5, SIZE * 0.4), Vector2(SIZE * 0.35, SIZE * 0.45),
		Vector2(SIZE * 0.65, SIZE * 0.45),
	]
	var radius := SIZE * 0.2
	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			var closest := INF
			for puff in puffs:
				closest = minf(closest, point.distance_to(puff))
			if closest > radius:
				continue
			var t := closest / radius
			image.set_pixel(x, y, base.darkened(t * 0.4))


func _shade_radial(base: Color, edge: float) -> Color:
	if edge > 0.85:
		return base.darkened(OUTLINE_DARKEN)
	if edge < 0.3:
		return _palette.highlight(base)
	return base.darkened(SHADE_DARKEN * edge)
