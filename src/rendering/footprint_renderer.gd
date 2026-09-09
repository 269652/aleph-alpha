extends RefCounted

## Builds/fills MultiMeshInstance2D nodes to render a FootprintField's
## individual stamps -- mirrors LeafLitterRenderer's own "many small
## per-instance ground marks, one GPU-instanced draw call, not one Node2D
## each" shape, deliberately simplified: a footprint is static once
## stamped (see FootprintField's own doc comment), so this needs no
## per-frame vertex-shader motion, no wind, no atlas -- three plain
## MultiMeshInstance2D nodes per chunk (one per real surface: snow/grass/
## forest), each with ONE shared static ProceduralFootprintSprite texture
## and Godot's own built-in per-instance 2D transform. That simplicity
## also makes fill()'s own actual output directly testable (a plain
## get_instance_transform_2d readback) rather than needing to defer to a
## higher wiring test the way LeafLitterRenderer's own lossy
## INSTANCE_CUSTOM packing has to.
##
## "Left" vs "right" is a negative-x-scale mirror of the SAME texture at
## render time (see ProceduralFootprintSprite's own doc comment on why
## one asymmetric source shape is enough), not a second texture or a
## fourth MultiMeshInstance2D per chunk.

const ProceduralFootprintSprite = preload("res://src/rendering/procedural_footprint_sprite.gd")

const SURFACES := ["snow", "grass", "forest", "underwater"]
const _FALLBACK_SURFACE := "grass"

static var _generator := ProceduralFootprintSprite.new()
static var _textures_by_surface: Dictionary = {}
static var _quad_mesh: QuadMesh = null


static func _texture_for(surface: String) -> ImageTexture:
	if not _textures_by_surface.has(surface):
		_textures_by_surface[surface] = _generator.generate_texture(surface)
	return _textures_by_surface[surface]


## One QuadMesh, shared across every MultiMesh this renderer ever builds
## (identical size for every surface -- ProceduralFootprintSprite.SIZE is
## the same for all three) -- built once lazily, the same "one generator,
## many sprites" convention _leaf_litter_renderer's own shared instance
## already establishes at the EarthChunkManager level.
static func _shared_quad_mesh() -> QuadMesh:
	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2(ProceduralFootprintSprite.SIZE)
	return _quad_mesh


## One MultiMeshInstance2D per SURFACES entry, added as a child of
## `parent` and ready to fill(). Caller keys them however it likes
## (EarthChunkManager keys by surface string directly, mirroring how it
## already keys _leaf_litter_mmis by chunk coord).
func build_multimeshes(parent: Node) -> Dictionary:
	var mmis := {}
	for surface in SURFACES:
		var mmi := MultiMeshInstance2D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.mesh = _shared_quad_mesh()
		mmi.multimesh = mm
		mmi.texture = _texture_for(surface)
		parent.add_child(mmi)
		mmis[surface] = mmi
	return mmis


## Rebuilds every surface's MultiMesh instance buffer from `prints`
## (FootprintField.prints()), replacing whatever was there before --
## grouped by each print's own `surface` key, falling back to
## _FALLBACK_SURFACE for anything unrecognized (a print must always
## render SOMEWHERE, the same "never silently drop a real record" rule
## ProceduralFootprintSprite's own surface fallback already follows).
## Called only when the field's generation() has actually changed (see
## EarthChunkManager.step_footprints's own dirty-check, mirroring
## step_leaf_litter's identical FPS-regression-round-4 lesson -- rebuilding
## an unchanged MultiMesh buffer every single frame is exactly the cost
## that regression was).
func fill(mmis: Dictionary, prints: Array) -> void:
	var by_surface := {}
	for surface in SURFACES:
		by_surface[surface] = []
	for p in prints:
		var surface: String = p.get("surface", _FALLBACK_SURFACE)
		if not by_surface.has(surface):
			surface = _FALLBACK_SURFACE
		by_surface[surface].append(p)

	for surface in SURFACES:
		var mmi: MultiMeshInstance2D = mmis.get(surface)
		if mmi == null:
			continue
		var group: Array = by_surface[surface]
		mmi.multimesh.instance_count = group.size()
		for i in group.size():
			mmi.multimesh.set_instance_transform_2d(i, _transform_for(group[i]))


## A footprint's own art is authored toe-up (see ProceduralFootprintSprite's
## own doc comment: the ball/toe sits near the top of the canvas, i.e.
## Vector2.UP is this shape's own natural forward) -- rotated so the toe
## points along the real heading it was stamped with instead. "Left" is
## a horizontal mirror of the same shape (negative local x-scale) rather
## than a second texture.
##
## Scaled by the print's own "size_scale" (see FootprintField.add_print's
## own doc comment) on top of the fixed PRINT_WORLD_SCALE -- a heavier
## creature's own print reads larger, a lighter one's smaller (see
## docs/concept/snow_cover.md's "Footprints depend on real mass, not just
## surface"), the SAME shared texture just rendered at a different real
## size rather than a texture per mass bucket. Defaults to 1.0 (today's
## existing fixed size) for any print dict with no such key at all --
## every pre-existing caller is unaffected.
func _transform_for(p: Dictionary) -> Transform2D:
	var heading: Vector2 = p.get("heading", Vector2.UP)
	var direction := heading.normalized()
	if direction == Vector2.ZERO:
		# No established heading (e.g. a print stamped standing still) --
		# fall back to a fixed, stable direction rather than a NaN
		# rotation from normalizing a zero vector.
		direction = Vector2.UP
	# Vector2.UP's own angle() is -PI/2 in Godot's Y-down convention;
	# Transform2D's rotation parameter rotates +X (angle 0) to point along
	# the given angle, so aligning UP with `direction` needs the
	# difference between the two, not `direction.angle()` alone.
	var rotation := direction.angle() - Vector2.UP.angle()
	var side_scale := -1.0 if p.get("side", "right") == "left" else 1.0
	var scale := ProceduralFootprintSprite.PRINT_WORLD_SCALE * float(p.get("size_scale", 1.0))
	# Basis vectors built directly (rotation composed with scale, mirror
	# included) rather than via Transform2D(rotation, origin).scaled_local
	# -- that chained call was silently discarding the origin in practice,
	# confirmed by a real failing readback test before this fix.
	var basis_x := Vector2(cos(rotation), sin(rotation)) * (side_scale * scale)
	var basis_y := Vector2(-sin(rotation), cos(rotation)) * scale
	return Transform2D(basis_x, basis_y, p.get("position", Vector2.ZERO))
