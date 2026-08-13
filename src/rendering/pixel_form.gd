extends RefCounted

## Turns a shape's geometry into a lightness fraction, so a filled shape
## reads as a ROUNDED, LIT SOLID rather than a flat fill with an outline
## (see docs/concept/pixel_art_engine.md).
##
## Generators used to fake this per-file with ad-hoc rules like "if dy <
## -0.3 use the highlight color, if dy > 0.4 use the shade color". Those are
## hard horizontal bands, and at the 4x canvas they read as stripes painted
## across the shape rather than as light falling on a surface.
##
## PixelForm instead treats an ellipse as the silhouette of a SPHEROID: it
## reconstructs the surface normal at each point and takes its dot product
## with a light direction -- the standard diffuse term. Feed the result to
## PixelRamp.sample() and any shape becomes a properly lit volume.

const PixelRamp = preload("res://src/rendering/pixel_ramp.gd")

## Where the light comes from. Top-left, matching the convention the whole
## codebase's art already assumes (PixelPalette highlights the top/left and
## shades the bottom/right). Z points out of the screen toward the viewer.
const LIGHT_DIRECTION := Vector3(-0.52, -0.62, 0.59)

## How much ambient fill light there is: the darkest a surface gets, before
## the bounce rim below. Never 0 -- a shadow lit by nothing reads as a hole.
const AMBIENT := 0.18

## Strength and tightness of the bounce-light rim on the shadowed edge --
## light reflected back off the ground. Without it a shaded sphere fades to
## a flat dark blob at its far edge instead of reading as round.
const RIM_STRENGTH := 0.3
const RIM_START := 0.55


## How deep inside the ellipse `point` is: 1 at the center, falling to 0 at
## the edge, and exactly 0 anywhere outside. Doubles as an inside test.
func ellipse_depth(center: Vector2, radius: Vector2, point: Vector2) -> float:
	var normalized := _normalized_offset(center, radius, point)
	var distance_sq := normalized.length_squared()
	if distance_sq >= 1.0:
		return 0.0
	return 1.0 - sqrt(distance_sq)


## The 0..1 lightness of the spheroid surface at `point`, ready to hand to
## PixelRamp.sample(). Points outside the ellipse return 0.
func lightness(center: Vector2, radius: Vector2, point: Vector2, light: Vector3 = LIGHT_DIRECTION) -> float:
	var normalized := _normalized_offset(center, radius, point)
	var distance_sq := normalized.length_squared()
	if distance_sq >= 1.0:
		return 0.0

	# Reconstruct the sphere's surface normal: x/y straight from the
	# normalized offset, z bulging out toward the viewer in the middle.
	var normal := Vector3(normalized.x, normalized.y, sqrt(maxf(1.0 - distance_sq, 0.0)))
	var diffuse := maxf(normal.normalized().dot(light.normalized()), 0.0)

	# Bounce light: the shadowed side's rim catches light reflected off the
	# surroundings, so the form stays round instead of dissolving into dark.
	var edge := sqrt(distance_sq)
	var rim := 0.0
	if edge > RIM_START and diffuse < 0.35:
		rim = smoothstep(RIM_START, 1.0, edge) * RIM_STRENGTH

	return clampf(AMBIENT + diffuse * (1.0 - AMBIENT) + rim, 0.0, 1.0)


## The 0..1 lightness across a CYLINDER (a limb, a trunk, a barrel, a
## tower): `across` is the coordinate perpendicular to the tube's axis,
## spanning `left`..`left + width`. Unlike the spheroid term this is even
## along the tube's length -- shading an arm as a sphere would wrongly
## darken its wrist and shoulder.
func cylinder_lightness(left: float, width: float, across: float, light: Vector3 = LIGHT_DIRECTION) -> float:
	var radius := maxf(width, 0.0001) / 2.0
	var normalized := clampf((across - (left + radius)) / radius, -1.0, 1.0)
	# Surface normal of a vertical tube: sideways component from the
	# position across it, bulging toward the viewer in the middle.
	var normal := Vector3(normalized, 0.0, sqrt(maxf(1.0 - normalized * normalized, 0.0)))
	var diffuse := maxf(normal.normalized().dot(light.normalized()), 0.0)

	var edge := absf(normalized)
	var rim := 0.0
	if edge > RIM_START and diffuse < 0.35:
		rim = smoothstep(RIM_START, 1.0, edge) * RIM_STRENGTH

	return clampf(AMBIENT + diffuse * (1.0 - AMBIENT) + rim, 0.0, 1.0)


## Convenience: the ramp color for a point on a lit spheroid of `base`
## color -- the one call most generators actually want.
func shade(ramp: PixelRamp, base: Color, center: Vector2, radius: Vector2, point: Vector2) -> Color:
	return ramp.sample(base, lightness(center, radius, point))


func _normalized_offset(center: Vector2, radius: Vector2, point: Vector2) -> Vector2:
	return Vector2(
		(point.x - center.x) / maxf(radius.x, 0.0001),
		(point.y - center.y) / maxf(radius.y, 0.0001)
	)
