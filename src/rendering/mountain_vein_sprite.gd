extends RefCounted

## Deterministic offline pixel art for a mountain ore vein: a thin,
## mineral-colored streak oriented along the local slope-facing direction
## (aspect) -- see docs/concept/terrain_relief.md's "Mountain ore" section:
## "a mineral-colored streak following the local slope direction directly
## on the mountain wall texture ... not a decal stamped on top of one."
## This replaces the round ore-boulder decal (ProceduralOreSprite via
## StoneRenderer._ore_texture_for) mountain veins drew before.
##
## Reuses ProceduralOreSprite.SIZE (the shared 32x32 art canvas every
## seeded ore/stone sprite in this project draws at) and
## ProceduralOreSprite.FLECK_COLOR (the same signature ore-type colour
## flat-ground ore's flecks use) rather than retyping either -- a vein and
## a boulder's ore flecks read as the SAME mineral, just shaped
## differently. Hillshading is NOT this file's job: it draws flat, full-
## brightness colour, and StoneRenderer applies live relief shading on top
## via a shared EntityHillshadeShader material (see that file).

const ProceduralOreSprite = preload("res://src/rendering/procedural_ore_sprite.gd")

## How far the streak extends from canvas centre along its direction, and
## how wide it sits across that direction, in art pixels -- spans most of
## ProceduralOreSprite.SIZE (32px) without touching the edges.
const HALF_LENGTH_PX := 13.0
const HALF_WIDTH_PX := 2.0


func generate_texture(ore_type: String, seed_value: int, aspect_deg: float) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(ore_type, seed_value, aspect_deg))


## `aspect_deg` is the real GIS compass bearing TerrainRelief.aspect_at
## already produces everywhere in this project (0=north/90=east/180=south/
## 270=west, clockwise; -1.0 = undefined-on-flat-ground sentinel -- see
## terrain_relief.gd's aspect_at/aspect_degrees_from_gradient). Converted to
## a 2D screen-space unit direction by Vector2(sin(bearing), -cos(bearing)):
## aspect_degrees_from_gradient's own doc comment derives a bearing FROM a
## gradient via `atan2(east, north)` ("the EAST component passed as y and
## the NORTH component as x"), which means for a unit vector at that
## bearing, (east, north) == (sin(bearing), cos(bearing)) -- so
## (sin(bearing), -cos(bearing)) is exactly that same unit vector re-
## expressed in this project's screen space, where east is still +X but
## north is -Y (Godot 2D's Y axis increases downward). This is the inverse
## of aspect_degrees_from_gradient's own mapping, not an arbitrary choice.
##
## `aspect_deg < 0.0` (the flat-ground sentinel -- mountain veins only ever
## spawn on real slopes, see MountainOrePlacement.MIN_SLOPE_FOR_VEINS_DEG,
## so this is defensive only) falls back to due north (bearing 0) rather
## than feeding a negative bearing into the trig, so a caller always gets a
## real drawn image, never a NaN-poisoned or empty one.
func generate_image(ore_type: String, seed_value: int, aspect_deg: float) -> Image:
	var size := ProceduralOreSprite.SIZE
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var base_color: Color = ProceduralOreSprite.FLECK_COLOR.get(ore_type, ProceduralOreSprite.FLECK_COLOR["iron"])

	var bearing_deg := aspect_deg if aspect_deg >= 0.0 else 0.0
	var direction := Vector2(sin(deg_to_rad(bearing_deg)), -cos(deg_to_rad(bearing_deg)))
	var perpendicular := Vector2(-direction.y, direction.x)
	var center := Vector2(size) / 2.0

	for y in size.y:
		for x in size.x:
			var offset := Vector2(x + 0.5, y + 0.5) - center
			var along := offset.dot(direction)
			if absf(along) > HALF_LENGTH_PX:
				continue  # off the drawn ends of the streak

			var jitter := _wobble(seed_value, ore_type, roundi(along)) * HALF_WIDTH_PX
			var across := offset.dot(perpendicular) - jitter
			if absf(across) > HALF_WIDTH_PX:
				continue  # outside the streak's width at this point along it

			image.set_pixel(x, y, base_color)

	return image


## Seeded per-column perpendicular jitter in [-1, 1] -- the same hash-
## derived "wobble" idiom as ProceduralOreSprite.generate_image's own
## `wobble` (there: one scalar perturbing a boulder's whole radius; here:
## one independent draw per along-axis pixel step, so the streak's edge
## squiggles along its length instead of sitting dead straight). Scaled by
## HALF_WIDTH_PX at the call site rather than carrying its own separate
## tuned amplitude constant, so two veins of the same ore/orientation,
## differing only by seed, don't render as the identical rigid line --
## while staying bounded to a fraction of the canvas, so the central axis
## itself stays legible.
func _wobble(seed_value: int, ore_type: String, along_step: int) -> float:
	var h := hash("%d_%s_vein_wobble_%d" % [seed_value, ore_type, along_step])
	return (float(absi(h) % 10000) / 10000.0) * 2.0 - 1.0
